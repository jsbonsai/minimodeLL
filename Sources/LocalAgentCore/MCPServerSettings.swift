import Foundation

// MCP server management (ADR 0012): custom request headers, the credential-store seam, and the user-config editor.
// Every rule here is enforced in code; the Settings UI only presents it.

/// One extra HTTP request header for an MCP server. Set exactly one of `value` (non-secret, stored in config.json)
/// or `secretAccount` (a Keychain account; the value never appears in configuration).
public struct MCPHeaderSpec: Codable, Sendable, Equatable, Hashable {
    public let name: String
    public let value: String?
    public let secretAccount: String?
    public init(name: String, value: String) { self.name = name; self.value = value; self.secretAccount = nil }
    public init(name: String, secretAccount: String) { self.name = name; self.value = nil; self.secretAccount = secretAccount }
    public var isSecret: Bool { secretAccount != nil }
}

public enum MCPHeaderPolicy {
    public static let maxHeaders = 16
    public static let maxNameLength = 64
    public static let maxValueBytes = 4096
    /// Headers the transport, URLSession or the MCP protocol own. Overriding them could break framing, session
    /// binding or protocol negotiation, or smuggle state (cookies, proxy credentials). Compared case-insensitively.
    public static let reservedNames: Set<String> = [
        "host", "content-length", "content-type", "content-encoding", "accept", "accept-encoding", "connection",
        "keep-alive", "transfer-encoding", "te", "trailer", "upgrade", "expect", "cookie", "cookie2", "set-cookie",
        "www-authenticate", "mcp-session-id", "mcp-protocol-version", "last-event-id", "cache-control", "origin",
        "forwarded", "via", "range", "if-range", "date",
    ]
    /// Whole namespaces that are reserved: proxy credentials, browser fetch metadata, and future MCP protocol headers.
    public static let reservedPrefixes = ["proxy-", "sec-", "mcp-"]
    public static let accountPattern = "^[A-Za-z0-9_.:@-]{1,128}$"

    /// RFC 9110 `token` (formerly RFC 7230): visible ASCII letters, digits and ``!#$%&'*+-.^_`|~``.
    public static func isToken(_ name: String) -> Bool {
        name.range(of: "^[!#$%&'*+.^_`|~0-9A-Za-z-]+$", options: .regularExpression) != nil
    }
    public static func isReserved(_ name: String, authMode: MCPServerSpec.AuthMode) -> Bool {
        let lower = name.lowercased()
        if reservedNames.contains(lower) || reservedPrefixes.contains(where: lower.hasPrefix) { return true }
        // The configured bearer/OAuth mode owns Authorization; a custom header would silently replace it.
        return lower == "authorization" && authMode != .none
    }
    /// RFC 9110 field value restricted to visible ASCII plus inner spaces/tabs: no CR, LF, NUL or other controls,
    /// no leading/trailing whitespace, no non-ASCII bytes. Prevents header injection through a value.
    public static func validateValue(_ value: String, headerName: String) throws {
        let bytes = Array(value.utf8)
        guard !bytes.isEmpty, bytes.count <= maxValueBytes,
              bytes.allSatisfy({ ($0 >= 0x21 && $0 <= 0x7E) || $0 == 0x20 || $0 == 0x09 }),
              bytes.first != 0x20, bytes.first != 0x09, bytes.last != 0x20, bytes.last != 0x09 else {
            throw AgentError.rejected("The value for header \(headerName) must be 1–\(maxValueBytes) bytes of printable ASCII without line breaks or surrounding spaces.")
        }
    }
    public static func validate(_ headers: [MCPHeaderSpec], authMode: MCPServerSpec.AuthMode, serverID: String) throws {
        guard headers.count <= maxHeaders else { throw AgentError.rejected("MCP server \(serverID) has more than \(maxHeaders) custom headers.") }
        var seen = Set<String>()
        for header in headers {
            guard (1...maxNameLength).contains(header.name.utf8.count), isToken(header.name) else {
                throw AgentError.rejected("Header names must be 1–\(maxNameLength) HTTP token characters (letters, digits, and !#$%&'*+-.^_`|~).")
            }
            guard seen.insert(header.name.lowercased()).inserted else {
                throw AgentError.rejected("Duplicate header \(header.name) in \(serverID) (header names are case-insensitive).")
            }
            guard !isReserved(header.name, authMode: authMode) else {
                throw AgentError.rejected("Header \(header.name) is reserved by the app, the MCP protocol, or the selected authentication mode.")
            }
            switch (header.value, header.secretAccount) {
            case (let value?, nil):
                // An inline Authorization value would put a credential in plain configuration.
                guard header.name.lowercased() != "authorization" else {
                    throw AgentError.rejected("An Authorization header must be stored as a secret (Keychain), not in configuration.")
                }
                try validateValue(value, headerName: header.name)
            case (nil, let account?):
                guard account.range(of: accountPattern, options: .regularExpression) != nil else {
                    throw AgentError.rejected("Header \(header.name) has an invalid Keychain account name.")
                }
            default:
                throw AgentError.rejected("Header \(header.name) needs exactly one of value or secretAccount.")
            }
        }
    }
}

// MARK: Credential store seam

/// Keychain access used by MCP connections and the server editor. `KeychainCredentials` is the only production
/// implementation; tests substitute an in-memory store.
public protocol CredentialStoring: Sendable {
    func read(account: String) throws -> String?
    func save(_ value: String, account: String) throws
    func delete(account: String) throws
}
public struct KeychainCredentials: CredentialStoring {
    public init() {}
    public func read(account: String) throws -> String? { try CredentialStore.read(account: account) }
    public func save(_ value: String, account: String) throws { try CredentialStore.save(value, account: account) }
    public func delete(account: String) throws { try CredentialStore.delete(account: account) }
}

// MARK: User-configuration editor

/// Create, update, enable/disable and delete MCP servers in the user `config.json` (ADR 0012).
///
/// - Refuses every edit while a forced managed policy is active (managed servers are read-only).
/// - Only the `mcpServers` array is replaced; other keys in the file are preserved as JSON.
/// - The complete resulting configuration is decoded and validated before anything is written; the write is atomic.
/// - Secret values are written only to Keychain accounts that the edited server references, never to the file.
/// - Keychain cleanup removes only accounts the app generated for that server (`mcp.<id>.` prefix) and its OAuth
///   token storage, and only when no remaining server or provider still references them.
public struct MCPServerStore: Sendable {
    public let fileURL: URL
    private let credentials: any CredentialStoring
    private let isManaged: @Sendable () throws -> Bool
    public init(fileURL: URL = ConfigurationLoader.userURL, credentials: any CredentialStoring = KeychainCredentials(),
                isManaged: @escaping @Sendable () throws -> Bool = { try ConfigurationLoader.isManaged() }) {
        self.fileURL = fileURL; self.credentials = credentials; self.isManaged = isManaged
    }

    /// Accounts under this prefix were generated by the editor for one server and are deleted with it.
    public static func ownedAccountPrefix(serverID: String) -> String { "mcp." + serverID + "." }
    public static func bearerAccount(serverID: String) -> String { ownedAccountPrefix(serverID: serverID) + "bearer" }
    public static func headerSecretAccount(serverID: String, headerName: String) -> String {
        ownedAccountPrefix(serverID: serverID) + "header." + headerName.lowercased()
    }

    /// Servers in the user configuration (the starter configuration when no file exists yet).
    public func servers() throws -> [MCPServerSpec] { try loadDocument().configuration.mcpServers }

    /// Creates (`replacing == nil`) or updates (`replacing == server.id`) a server. Server IDs cannot be renamed:
    /// delete and recreate instead, so Keychain ownership never moves between IDs.
    /// `secrets` maps Keychain account → value for the bearer token and secret headers entered in this edit;
    /// omitted accounts keep their saved value.
    public func save(_ server: MCPServerSpec, secrets: [String: String] = [:], replacing originalID: String?) throws {
        try requireEditable()
        let document = try loadDocument()
        var servers = document.configuration.mcpServers
        let previous: MCPServerSpec?
        if let originalID {
            guard originalID == server.id else { throw AgentError.rejected("A server ID cannot be changed. Delete the server and add it again.") }
            guard let index = servers.firstIndex(where: { $0.id == originalID }) else { throw AgentError.rejected("MCP server \(originalID) no longer exists.") }
            previous = servers[index]
            servers[index] = server
        } else {
            guard !servers.contains(where: { $0.id == server.id }) else { throw AgentError.rejected("An MCP server with ID \(server.id) already exists.") }
            previous = nil
            servers.append(server)
        }
        try server.validate()
        try validateSecrets(secrets, for: server)
        let (data, updated) = try render(document, servers: servers)
        for (account, value) in secrets { try credentials.save(value, account: account) }
        try data.write(to: fileURL, options: .atomic)
        if let previous { removeOrphanedSecrets(of: previous, remaining: updated) }
    }

    public func setEnabled(_ enabled: Bool, serverID: String) throws {
        try requireEditable()
        let document = try loadDocument()
        guard let server = document.configuration.mcpServers.first(where: { $0.id == serverID }) else {
            throw AgentError.rejected("MCP server \(serverID) no longer exists.")
        }
        let toggled = MCPServerSpec(id: server.id, title: server.title, endpoint: server.endpoint, credentialAccount: server.credentialAccount,
                                    tools: server.tools, oauth: server.oauth, enabled: enabled ? nil : false, headers: server.headers)
        let servers = document.configuration.mcpServers.map { $0.id == serverID ? toggled : $0 }
        try render(document, servers: servers).data.write(to: fileURL, options: .atomic)
    }

    /// Removes the server from config.json, then deletes the Keychain items it owned. Returns the number of
    /// Keychain accounts removed.
    @discardableResult
    public func delete(serverID: String) throws -> Int {
        try requireEditable()
        let document = try loadDocument()
        guard let server = document.configuration.mcpServers.first(where: { $0.id == serverID }) else {
            throw AgentError.rejected("MCP server \(serverID) no longer exists.")
        }
        let (data, updated) = try render(document, servers: document.configuration.mcpServers.filter { $0.id != serverID })
        try data.write(to: fileURL, options: .atomic)
        return removeOrphanedSecrets(of: server, remaining: updated)
    }

    // MARK: Internals

    private struct Document { var json: [String: Any]; var configuration: AgentConfiguration }

    private func requireEditable() throws {
        // Re-checked at every edit: MDM can force a policy at any time. An unreadable domain also refuses.
        guard !(try isManaged()) else {
            throw AgentError.rejected("Your organization manages MCP servers. They are read-only on this Mac.")
        }
    }
    private func loadDocument() throws -> Document {
        let data = FileManager.default.fileExists(atPath: fileURL.path)
            ? try Data(contentsOf: fileURL) : Data(AgentConfiguration.starterJSON.utf8)
        let configuration: AgentConfiguration
        do { configuration = try ConfigurationLoader.decode(data) }
        catch { throw AgentError.rejected("config.json is not valid. Fix it in the Configuration tab before editing MCP servers.") }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentError.rejected("config.json must contain a JSON object.")
        }
        return Document(json: json, configuration: configuration)
    }
    /// Replaces only `mcpServers`, then decodes and validates the whole result before returning it for writing.
    private func render(_ document: Document, servers: [MCPServerSpec]) throws -> (data: Data, configuration: AgentConfiguration) {
        var json = document.json
        let encoded = try JSONEncoder().encode(servers)
        json["mcpServers"] = try JSONSerialization.jsonObject(with: encoded)
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return (data, try ConfigurationLoader.decode(data))
    }
    private func validateSecrets(_ secrets: [String: String], for server: MCPServerSpec) throws {
        let headerAccounts = Dictionary((server.headers ?? []).compactMap { h in h.secretAccount.map { ($0, h.name) } },
                                        uniquingKeysWith: { first, _ in first })
        for (account, value) in secrets {
            if let headerName = headerAccounts[account] {
                try MCPHeaderPolicy.validateValue(value, headerName: headerName)
            } else if account == server.credentialAccount {
                guard !value.isEmpty, value.utf8.count <= MCPHeaderPolicy.maxValueBytes,
                      !value.contains(where: { $0.isNewline || $0 == "\0" }) else {
                    throw AgentError.rejected("The bearer token must be a single line of at most \(MCPHeaderPolicy.maxValueBytes) bytes.")
                }
            } else {
                // Never let one server's edit overwrite a Keychain item it does not reference.
                throw AgentError.rejected("A secret was supplied for an account this server does not use.")
            }
        }
    }
    /// Deletes Keychain accounts that `server` referenced, that the editor owns for it, and that nothing in
    /// `remaining` still references. Deletion failures are ignored (the item may never have been saved).
    @discardableResult
    private func removeOrphanedSecrets(of server: MCPServerSpec, remaining: AgentConfiguration) -> Int {
        var stillUsed = Set(remaining.mcpServers.flatMap(\.referencedAccounts))
        stillUsed.formUnion(remaining.providers.compactMap(\.credentialAccount))
        let prefix = Self.ownedAccountPrefix(serverID: server.id)
        var removed = 0
        for account in server.referencedAccounts where !stillUsed.contains(account) {
            let owned = account.hasPrefix(prefix) || account == server.oauthStorageAccount
            guard owned else { continue }
            if (try? credentials.delete(account: account)) != nil { removed += 1 }
        }
        return removed
    }
}
