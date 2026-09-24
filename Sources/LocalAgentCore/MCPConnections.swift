import Foundation
import MCP
import Logging

public struct AvailableTool: Sendable {
    public let alias: String
    public let serverID: String
    public let originalName: String
    public let requiresConfirmation: Bool
    public let definition: FunctionTool
}
public protocol ToolClient: Sendable {
    func discover() async throws -> [AvailableTool]
    func execute(_ tool: AvailableTool, arguments: [String: Value]) async throws -> String
    func disconnect() async
}
/// Builds the SDK Streamable HTTP transport for one server: timeouts, bearer or OAuth authorization, and custom
/// headers (ADR 0012). Header and token values are resolved here from Keychain (or unsaved `secretOverrides`
/// during "Test connection"), are validated, and are never logged.
public struct MCPTransportFactory: Sendable {
    public let credentials: any CredentialStoring
    /// Test seam: tests install a `URLProtocol` here. Production uses an ephemeral configuration.
    public let sessionConfiguration: @Sendable () -> URLSessionConfiguration
    public init(credentials: any CredentialStoring = KeychainCredentials(),
                sessionConfiguration: @escaping @Sendable () -> URLSessionConfiguration = { .ephemeral }) {
        self.credentials = credentials; self.sessionConfiguration = sessionConfiguration
    }
    /// Resolved `(name, value)` pairs in configuration order. Throws if a secret is missing or a value is invalid.
    public func resolveHeaders(for server: MCPServerSpec, secretOverrides: [String: String] = [:]) throws -> [(String, String)] {
        try MCPHeaderPolicy.validate(server.headers ?? [], authMode: server.authMode, serverID: server.id)
        return try (server.headers ?? []).map { header in
            let value: String
            if let inline = header.value { value = inline }
            else if let account = header.secretAccount {
                guard let saved = try secretOverrides[account] ?? credentials.read(account: account), !saved.isEmpty else {
                    throw AgentError.rejected("Save the secret value for header \(header.name) of \(server.id) in Settings first.")
                }
                value = saved
            } else { throw AgentError.rejected("Header \(header.name) has no value.") }
            try MCPHeaderPolicy.validateValue(value, headerName: header.name)
            return (header.name, value)
        }
    }
    public func makeTransport(for server: MCPServerSpec, secretOverrides: [String: String] = [:],
                              authorizationDelegate: (any OAuthAuthorizationDelegate)?) throws -> HTTPClientTransport {
        try server.validate()
        let token: String?
        if let account = server.credentialAccount {
            guard let saved = try secretOverrides[account] ?? credentials.read(account: account), !saved.isEmpty else {
                throw AgentError.rejected("Save the credential for \(account) in Settings first.")
            }
            guard !saved.contains(where: { $0.isNewline || $0 == "\0" }) else {
                throw AgentError.rejected("The saved credential for \(account) is not a single-line token.")
            }
            token = saved
        } else { token = nil }
        let headers = try resolveHeaders(for: server, secretOverrides: secretOverrides)
        var logger = Logging.Logger(label: Brand.identity + ".mcp")
        logger.logLevel = .critical // SDK logs can include remote errors; keep payloads out of routine logs.
        let config = sessionConfiguration()
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        let authorizer: OAuthAuthorizer?
        if let oauth = server.oauth, let account = server.oauthStorageAccount {
            guard let authorizationDelegate else { throw AgentError.rejected("Interactive sign-in requires the app.") }
            authorizer = OAuthAuthorizer(configuration: OAuthConfiguration(
                grantType: .authorizationCode, authentication: .none(clientID: oauth.clientID),
                authorizationRedirectURI: URL(string: Brand.identity + "://oauth-callback")!,
                clientName: Brand.displayName, authorizationDelegate: authorizationDelegate),
                tokenStorage: KeychainOAuthStorage(account: account))
        } else { authorizer = nil }
        let authMode = server.authMode
        return HTTPClientTransport(endpoint: server.endpoint, configuration: config, authorizer: authorizer, requestModifier: { request in
            var request = request
            if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
            // Applied after the SDK sets protocol headers. Validation already rejected reserved names; skip them
            // again here so a future validation gap cannot override Mcp-Session-Id, Content-Type, and so on.
            for (name, value) in headers where !MCPHeaderPolicy.isReserved(name, authMode: authMode) {
                request.setValue(value, forHTTPHeaderField: name)
            }
            return request
        }, logger: logger)
    }
}
public actor MCPConnections: ToolClient {
    private let servers: [MCPServerSpec]
    private let authorizationDelegate: (any OAuthAuthorizationDelegate)?
    private let factory: MCPTransportFactory
    private var clients: [String: Client] = [:]
    public init(servers: [MCPServerSpec], authorizationDelegate: (any OAuthAuthorizationDelegate)? = nil,
                factory: MCPTransportFactory = MCPTransportFactory()) {
        // Disabled servers are never connected (ADR 0012).
        self.servers = servers.filter(\.isEnabled); self.authorizationDelegate = authorizationDelegate; self.factory = factory
    }
    public func discover() async throws -> [AvailableTool] {
        var available: [AvailableTool] = []
        for (serverIndex, server) in servers.enumerated() where !server.tools.isEmpty {
            try Task.checkCancellation()
            let transport = try factory.makeTransport(for: server, authorizationDelegate: authorizationDelegate)
            let client = Client(name: Brand.identity, version: Brand.version)
            clients[server.id] = client
            try await client.connect(transport: transport)
            try Task.checkCancellation()
            var cursor: String?
            var pages = 0
            repeat {
                try Task.checkCancellation()
                let result = try await client.listTools(cursor: cursor)
                for tool in result.tools {
                    guard let rule = server.tools.first(where: { $0.name == tool.name }) else { continue }
                    guard !available.contains(where: { $0.serverID == server.id && $0.originalName == tool.name }) else { continue }
                    try ToolSchema.checkSupported(tool.inputSchema)
                    let alias = "s\(serverIndex)_t\(available.count)"
                    available.append(AvailableTool(alias: alias, serverID: server.id, originalName: tool.name,
                        requiresConfirmation: rule.requiresConfirmation,
                        definition: FunctionTool(function: .init(name: alias,
                            description: "\(server.title): \(tool.name). \(tool.description ?? "")", parameters: tool.inputSchema))))
                    guard available.count <= 16 else { throw AgentError.rejected("Approve at most 16 tools per task configuration.") }
                }
                cursor = result.nextCursor
                pages += 1
                guard cursor == nil || pages < 10 else { throw AgentError.rejected("MCP tool discovery exceeded its page limit.") }
            } while cursor != nil
        }
        return available
    }
    public func execute(_ tool: AvailableTool, arguments: [String: Value]) async throws -> String {
        guard let server = servers.first(where: { $0.id == tool.serverID }),
              server.tools.contains(where: { $0.name == tool.originalName }),
              let client = clients[tool.serverID] else { throw AgentError.rejected("Tool is not approved.") }
        let result = try await client.callTool(name: tool.originalName, arguments: arguments)
        if result.isError == true { throw AgentError.rejected("The tool reported an error. No automatic retry was performed.") }
        guard !result.content.isEmpty else { throw AgentError.rejected("The tool returned no supported text content.") }
        return try result.content.map { content in
            guard case .text(let text, _, _) = content else {
                throw AgentError.rejected("This preview supports text tool results only.")
            }
            return text
        }.joined(separator: "\n")
    }
    public func disconnect() async {
        for client in clients.values { await client.disconnect() }
        clients.removeAll()
    }
}

/// A tool a server offered during "Test connection". Names and descriptions come from the remote server and are
/// untrusted display text; offering a tool does not approve it.
public struct DiscoveredTool: Sendable, Identifiable, Equatable {
    public var id: String { name }
    public let name: String
    public let description: String
    /// False when the input schema uses JSON Schema keywords outside the supported subset; approving such a tool
    /// would block every run, so the UI should not offer it.
    public let schemaSupported: Bool
}
/// "Test connection" for Settings (ADR 0012): connect, list every tool the server offers (bounded), disconnect.
/// Nothing is executed and nothing is logged. The allowlist stays the explicit `tools` array.
public enum MCPServerProbe {
    /// Entry point for the app: resolves the current policy itself (an invalid forced policy throws, failing closed)
    /// and applies the managed-policy restriction when a forced policy is active.
    public static func discoverToolsUnderCurrentPolicy(_ server: MCPServerSpec, secretOverrides: [String: String] = [:],
                                                       authorizationDelegate: (any OAuthAuthorizationDelegate)? = nil) async throws -> [DiscoveredTool] {
        let snapshot = try ConfigurationLoader.load()
        return try await discoverTools(server, secretOverrides: secretOverrides,
                                       managedPolicy: snapshot.managed ? snapshot.configuration : nil,
                                       authorizationDelegate: authorizationDelegate)
    }
    public static let maxPages = 10
    public static let maxTools = 200
    public static let maxDescriptionCharacters = 300
    /// - Parameters:
    ///   - secretOverrides: unsaved values typed in the editor (account → value), used instead of Keychain.
    ///   - managedPolicy: when a forced policy is active, pass it: only a server exactly as the policy defines it
    ///     may be probed, so a managed Mac cannot be used to send credentials or headers to arbitrary endpoints.
    public static func discoverTools(_ server: MCPServerSpec, secretOverrides: [String: String] = [:],
                                     managedPolicy: AgentConfiguration? = nil,
                                     authorizationDelegate: (any OAuthAuthorizationDelegate)? = nil,
                                     factory: MCPTransportFactory = MCPTransportFactory()) async throws -> [DiscoveredTool] {
        if let managedPolicy {
            guard managedPolicy.mcpServers.contains(server), secretOverrides.isEmpty else {
                throw AgentError.rejected("Your organization manages MCP servers. Only configured servers can be tested.")
            }
        }
        let transport = try factory.makeTransport(for: server, secretOverrides: secretOverrides, authorizationDelegate: authorizationDelegate)
        let client = Client(name: Brand.identity, version: Brand.version)
        do {
            try await client.connect(transport: transport)
            var found: [DiscoveredTool] = []
            var cursor: String?
            var pages = 0
            repeat {
                try Task.checkCancellation()
                let result = try await client.listTools(cursor: cursor)
                for tool in result.tools where !found.contains(where: { $0.name == tool.name }) {
                    guard !tool.name.isEmpty, tool.name.utf8.count <= 128 else { continue }
                    let supported = (try? ToolSchema.checkSupported(tool.inputSchema)) != nil
                    let text = (tool.description ?? "").replacingOccurrences(of: "\n", with: " ")
                    found.append(DiscoveredTool(name: tool.name, description: String(text.prefix(maxDescriptionCharacters)),
                                                schemaSupported: supported))
                    guard found.count <= maxTools else { throw AgentError.rejected("The server offers more than \(maxTools) tools.") }
                }
                cursor = result.nextCursor
                pages += 1
                guard cursor == nil || pages < maxPages else { throw AgentError.rejected("MCP tool discovery exceeded its page limit.") }
            } while cursor != nil
            await client.disconnect()
            return found
        } catch {
            await client.disconnect()
            throw error
        }
    }
}
