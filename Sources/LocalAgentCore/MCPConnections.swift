import Foundation
import MCP
import Logging
import CryptoKit

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
public actor MCPConnections: ToolClient {
    private let servers: [MCPServerSpec]
    private let authorizationDelegate: (any OAuthAuthorizationDelegate)?
    private var clients: [String: Client] = [:]
    public init(servers: [MCPServerSpec], authorizationDelegate: (any OAuthAuthorizationDelegate)? = nil) {
        self.servers = servers; self.authorizationDelegate = authorizationDelegate
    }
    public func discover() async throws -> [AvailableTool] {
        var available: [AvailableTool] = []
        for (serverIndex, server) in servers.enumerated() where !server.tools.isEmpty {
            try Task.checkCancellation()
            let token: String?
            if let account = server.credentialAccount {
                guard let saved = try CredentialStore.read(account: account), !saved.isEmpty else {
                    throw AgentError.rejected("Save the credential for \(account) in Settings first.")
                }
                token = saved
            } else { token = nil }
            var logger = Logging.Logger(label: Brand.identity + ".mcp")
            logger.logLevel = .critical // SDK logs can include remote errors; keep payloads out of routine logs.
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 60
            let authorizer: OAuthAuthorizer?
            if let oauth = server.oauth {
                guard let authorizationDelegate else { throw AgentError.rejected("Interactive sign-in requires the app.") }
                authorizer = OAuthAuthorizer(configuration: OAuthConfiguration(
                    grantType: .authorizationCode, authentication: .none(clientID: oauth.clientID),
                    authorizationRedirectURI: URL(string: Brand.identity + "://oauth-callback")!,
                    clientName: Brand.displayName, authorizationDelegate: authorizationDelegate),
                    tokenStorage: KeychainOAuthStorage(account: Self.credentialIdentity(server: server, oauth: oauth)))
            } else { authorizer = nil }
            let transport = HTTPClientTransport(endpoint: server.endpoint, configuration: config, authorizer: authorizer, requestModifier: { request in
                var request = request
                if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
                return request
            }, logger: logger)
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
    private static func credentialIdentity(server: MCPServerSpec, oauth: OAuthSpec) -> String {
        let binding = server.endpoint.absoluteString + "\n" + oauth.clientID
        let digest = SHA256.hash(data: Data(binding.utf8)).map { String(format: "%02x", $0) }.joined()
        return "oauth." + server.id + "." + digest
    }
    public func disconnect() async {
        for client in clients.values { await client.disconnect() }
        clients.removeAll()
    }
}
