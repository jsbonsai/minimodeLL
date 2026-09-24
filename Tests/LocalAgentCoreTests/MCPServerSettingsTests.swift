import Testing
import Foundation
import MCP
@testable import LocalAgentCore

// MARK: Fixtures

/// In-memory stand-in for Keychain.
final class FakeCredentials: CredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: String]
    init(_ items: [String: String] = [:]) { self.items = items }
    var all: [String: String] { lock.withLock { items } }
    func read(account: String) throws -> String? { lock.withLock { items[account] } }
    func save(_ value: String, account: String) throws { lock.withLock { items[account] = value } }
    func delete(account: String) throws { _ = lock.withLock { items.removeValue(forKey: account) } }
}

/// A tiny Streamable HTTP MCP server inside `URLProtocol`: initialize, notifications (202), tools/list, and 405 for
/// the optional GET event stream. Requests are recorded per host so parallel tests do not interfere.
final class MockMCPServer: URLProtocol, @unchecked Sendable {
    struct Recorded: Sendable { let method: String; let rpc: String?; let headers: [String: String] }
    struct Behavior: Sendable { var requiredHeader: (String, String)? = nil; var toolsJSON = MockMCPServer.defaultTools }
    static let defaultTools = ##"[{"name":"search","description":"Find things","inputSchema":{"type":"object","properties":{"q":{"type":"string"}}}},{"name":"send","description":"Send a message","inputSchema":{"type":"object"}},{"name":"fancy","description":"Uses refs","inputSchema":{"type":"object","properties":{"a":{"$ref":"#/x"}}}}]"##
    private static let lock = NSLock()
    nonisolated(unsafe) private static var recorded: [String: [Recorded]] = [:]
    nonisolated(unsafe) private static var behaviors: [String: Behavior] = [:]
    static func configure(host: String, _ behavior: Behavior = Behavior()) { lock.withLock { behaviors[host] = behavior; recorded[host] = [] } }
    static func requests(host: String) -> [Recorded] { lock.withLock { recorded[host] ?? [] } }
    static func sessionConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockMCPServer.self]
        return config
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let host = request.url?.host ?? ""
        let body = Self.body(of: request)
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let rpc = json?["method"] as? String
        Self.lock.withLock {
            Self.recorded[host, default: []].append(Recorded(method: request.httpMethod ?? "GET", rpc: rpc, headers: request.allHTTPHeaderFields ?? [:]))
        }
        let behavior = Self.lock.withLock { Self.behaviors[host] } ?? Behavior()
        if let (name, value) = behavior.requiredHeader, request.value(forHTTPHeaderField: name) != value {
            return respond(401, body: Data())
        }
        guard request.httpMethod == "POST" else { return respond(405, body: Data()) }
        guard let json, let id = json["id"] else { return respond(202, body: Data()) }
        let idJSON = String(decoding: try! JSONSerialization.data(withJSONObject: id, options: .fragmentsAllowed), as: UTF8.self)
        let result: String
        switch rpc {
        case "initialize":
            let version = ((json["params"] as? [String: Any])?["protocolVersion"] as? String) ?? Version.latest
            result = #"{"protocolVersion":"\#(version)","capabilities":{"tools":{}},"serverInfo":{"name":"fixture","version":"1"}}"#
        case "tools/list": result = #"{"tools":\#(behavior.toolsJSON)}"#
        default: result = #"{}"#
        }
        respond(200, body: Data(#"{"jsonrpc":"2.0","id":\#(idJSON),"result":\#(result)}"#.utf8),
                headers: ["Content-Type": "application/json", "Mcp-Session-Id": "session-1"])
    }
    private func respond(_ status: Int, body: Data, headers: [String: String] = [:]) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !body.isEmpty { client?.urlProtocol(self, didLoad: body) }
        client?.urlProtocolDidFinishLoading(self)
    }
    private static func body(of request: URLRequest) -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private func server(_ id: String = "svc", endpoint: String = "https://mcp.example.test/mcp", credentialAccount: String? = nil,
                    tools: [ToolRule] = [], oauth: OAuthSpec? = nil, enabled: Bool? = nil,
                    headers: [MCPHeaderSpec]? = nil) -> MCPServerSpec {
    MCPServerSpec(id: id, title: "Service \(id)", endpoint: URL(string: endpoint)!, credentialAccount: credentialAccount,
                  tools: tools, oauth: oauth, enabled: enabled, headers: headers)
}
private func tempConfigURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("mcp-store-\(UUID().uuidString).json")
}
private func store(_ url: URL, _ credentials: FakeCredentials, managed: Bool = false) -> MCPServerStore {
    MCPServerStore(fileURL: url, credentials: credentials, isManaged: { managed })
}

// MARK: Schema

@Test func oldServerConfigurationStillDecodes() throws {
    let configuration = try config {
        $0["mcpServers"] = [["id": "gmail", "title": "Gmail", "endpoint": "https://mcp.example.test/mcp",
                             "oauth": ["clientID": "native-client"], "tools": [["name": "search", "requiresConfirmation": false]]],
                            ["id": "notes", "title": "Notes", "endpoint": "https://notes.example.test/mcp",
                             "credentialAccount": "notes.token", "tools": []]]
    }
    #expect(configuration.mcpServers[0].isEnabled)
    #expect(configuration.mcpServers[0].headers == nil)
    #expect(configuration.mcpServers[0].authMode == .oauth(clientID: "native-client"))
    #expect(configuration.mcpServers[1].authMode == .bearer(account: "notes.token"))
    // Re-encoding does not add keys that older builds would see.
    let encoded = String(decoding: try JSONEncoder().encode(configuration.mcpServers[1]), as: UTF8.self)
    #expect(!encoded.contains("enabled") && !encoded.contains("headers"))
}
@Test(arguments: ["http://mcp.example.test/mcp", "https://user:pw@mcp.example.test/mcp",
                  "https://mcp.example.test/mcp?key=1", "https://mcp.example.test/mcp#x", "ftp://mcp.example.test/"])
func mcpEndpointMustBePlainHTTPS(_ endpoint: String) {
    #expect(throws: (any Error).self) { try server(endpoint: endpoint).validate() }
}
@Test(arguments: ["Host", "content-length", "Content-Type", "Accept", "Connection", "Transfer-Encoding", "Cookie",
                  "Mcp-Session-Id", "MCP-Protocol-Version", "Last-Event-ID", "Proxy-Authorization", "Sec-Fetch-Mode",
                  "Mcp-Future", "Origin", "TE", "Upgrade"])
func reservedHeaderNamesAreRejected(_ name: String) {
    #expect(throws: (any Error).self) { try server(headers: [MCPHeaderSpec(name: name, value: "x")]).validate() }
}
@Test(arguments: ["", "X Space", "X:Colon", "X\r\nInjected", "Ümlaut", "(paren)", String(repeating: "a", count: 65)])
func invalidHeaderNamesAreRejected(_ name: String) {
    #expect(throws: (any Error).self) { try server(headers: [MCPHeaderSpec(name: name, value: "x")]).validate() }
}
@Test func headerValueAndShapeRules() throws {
    try server(headers: [MCPHeaderSpec(name: "X-Tenant", value: "acme"), MCPHeaderSpec(name: "X-Api-Key", secretAccount: "mcp.svc.header.x-api-key")]).validate()
    // Values: no line breaks, controls, non-ASCII or surrounding whitespace.
    for bad in ["a\r\nX-Evil: 1", "a\nb", " lead", "trail ", "", "caf\u{e9}", "nul\u{0}"] {
        #expect(throws: (any Error).self) { try server(headers: [MCPHeaderSpec(name: "X-Tenant", value: bad)]).validate() }
    }
    // Duplicates are case-insensitive.
    #expect(throws: (any Error).self) {
        try server(headers: [MCPHeaderSpec(name: "X-Tenant", value: "a"), MCPHeaderSpec(name: "x-tenant", value: "b")]).validate()
    }
    // Exactly one of value / secretAccount.
    let both = try JSONDecoder().decode(MCPHeaderSpec.self, from: Data(#"{"name":"X-A","value":"v","secretAccount":"acct"}"#.utf8))
    let neither = try JSONDecoder().decode(MCPHeaderSpec.self, from: Data(#"{"name":"X-A"}"#.utf8))
    #expect(throws: (any Error).self) { try server(headers: [both]).validate() }
    #expect(throws: (any Error).self) { try server(headers: [neither]).validate() }
    #expect(throws: (any Error).self) { try server(headers: [MCPHeaderSpec(name: "X-A", secretAccount: "bad account")]).validate() }
    #expect(throws: (any Error).self) {
        try server(headers: (0...16).map { MCPHeaderSpec(name: "X-H\($0)", value: "v") }).validate()
    }
}
@Test func authorizationHeaderDependsOnAuthMode() throws {
    // No auth mode: a custom Authorization scheme is allowed, but only as a Keychain secret.
    try server(headers: [MCPHeaderSpec(name: "Authorization", secretAccount: "mcp.svc.header.authorization")]).validate()
    #expect(throws: (any Error).self) { try server(headers: [MCPHeaderSpec(name: "Authorization", value: "Basic abc")]).validate() }
    // Bearer or OAuth owns Authorization.
    #expect(throws: (any Error).self) {
        try server(credentialAccount: "mcp.svc.bearer", headers: [MCPHeaderSpec(name: "authorization", secretAccount: "a")]).validate()
    }
    #expect(throws: (any Error).self) {
        try server(oauth: OAuthSpec(clientID: "c"), headers: [MCPHeaderSpec(name: "Authorization", secretAccount: "a")]).validate()
    }
    #expect(throws: (any Error).self) { try server(credentialAccount: "a", oauth: OAuthSpec(clientID: "c")).validate() }
}
@Test func onlyEnabledServersCountTowardToolBudget() throws {
    let many = (0..<12).map { ["name": "t\($0)", "requiresConfirmation": true] }
    func servers(secondEnabled: Bool) -> [[String: Any]] {
        [["id": "a", "title": "A", "endpoint": "https://a.example.test/mcp", "tools": many],
         ["id": "b", "title": "B", "endpoint": "https://b.example.test/mcp", "tools": many, "enabled": secondEnabled]]
    }
    #expect(throws: (any Error).self) { try config { $0["mcpServers"] = servers(secondEnabled: true) } }
    let configuration = try config { $0["mcpServers"] = servers(secondEnabled: false) }
    #expect(configuration.mcpServers[1].isEnabled == false)
}

// MARK: Store

@Test func createStoresSecretsInKeychainOnlyAndPreservesOtherKeys() throws {
    let url = tempConfigURL(); defer { try? FileManager.default.removeItem(at: url) }
    var json = try JSONSerialization.jsonObject(with: Data(AgentConfiguration.starterJSON.utf8)) as! [String: Any]
    json["x-note"] = "kept"
    try JSONSerialization.data(withJSONObject: json).write(to: url)
    let credentials = FakeCredentials()
    let bearer = MCPServerStore.bearerAccount(serverID: "svc")
    let headerAccount = MCPServerStore.headerSecretAccount(serverID: "svc", headerName: "X-Api-Key")
    let spec = server(credentialAccount: bearer, tools: [ToolRule(name: "search", requiresConfirmation: true)],
                      headers: [MCPHeaderSpec(name: "X-Tenant", value: "acme"), MCPHeaderSpec(name: "X-Api-Key", secretAccount: headerAccount)])
    try store(url, credentials).save(spec, secrets: [bearer: "bearer-SECRET-1", headerAccount: "header-SECRET-2"], replacing: nil)
    let text = try String(contentsOf: url, encoding: .utf8)
    #expect(!text.contains("SECRET"))
    #expect(text.contains("x-note") && text.contains("X-Tenant") && text.contains(headerAccount))
    #expect(credentials.all == [bearer: "bearer-SECRET-1", headerAccount: "header-SECRET-2"])
    let reloaded = try ConfigurationLoader.decode(Data(contentsOf: url))
    #expect(reloaded.mcpServers == [spec])
    #expect(reloaded.limits.inputBytes == 2048)
}
@Test func storeRejectsInvalidEditsWithoutWriting() throws {
    let url = tempConfigURL(); defer { try? FileManager.default.removeItem(at: url) }
    let credentials = FakeCredentials()
    let editor = store(url, credentials)
    try editor.save(server("svc"), replacing: nil)
    let before = try Data(contentsOf: url)
    #expect(throws: (any Error).self) { try editor.save(server("svc"), replacing: nil) } // duplicate ID
    #expect(throws: (any Error).self) { try editor.save(server("other"), replacing: "svc") } // rename
    #expect(throws: (any Error).self) { try editor.save(server("svc", endpoint: "http://mcp.example.test/mcp"), replacing: "svc") }
    #expect(throws: (any Error).self) { try editor.save(server("svc", headers: [MCPHeaderSpec(name: "Host", value: "x")]), replacing: "svc") }
    // A secret for an account the server does not reference would overwrite someone else's Keychain item.
    #expect(throws: (any Error).self) { try editor.save(server("svc"), secrets: ["provider.token": "x"], replacing: "svc") }
    // Secret header values get the same injection checks as inline values.
    let account = MCPServerStore.headerSecretAccount(serverID: "svc", headerName: "X-Key")
    #expect(throws: (any Error).self) {
        try editor.save(server("svc", headers: [MCPHeaderSpec(name: "X-Key", secretAccount: account)]), secrets: [account: "a\r\nb"], replacing: "svc")
    }
    // The whole resulting configuration must validate (tool budget across enabled servers).
    let tools = (0..<17).map { ToolRule(name: "t\($0)", requiresConfirmation: true) }
    #expect(throws: (any Error).self) { try editor.save(server("svc", tools: tools), replacing: "svc") }
    #expect(try Data(contentsOf: url) == before)
    #expect(credentials.all.isEmpty)
}
@Test func managedPolicyBlocksEveryEdit() throws {
    let url = tempConfigURL(); defer { try? FileManager.default.removeItem(at: url) }
    let credentials = FakeCredentials(["mcp.svc.bearer": "keep"])
    try store(url, credentials).save(server("svc", credentialAccount: "mcp.svc.bearer"), replacing: nil)
    let before = try Data(contentsOf: url)
    let managed = store(url, credentials, managed: true)
    #expect(throws: (any Error).self) { try managed.save(server("new"), replacing: nil) }
    #expect(throws: (any Error).self) { try managed.save(server("svc"), replacing: "svc") }
    #expect(throws: (any Error).self) { try managed.setEnabled(false, serverID: "svc") }
    #expect(throws: (any Error).self) { try managed.delete(serverID: "svc") }
    let failing = MCPServerStore(fileURL: url, credentials: credentials, isManaged: { throw AgentError.rejected("unreadable") })
    #expect(throws: (any Error).self) { try failing.save(server("new"), replacing: nil) }
    #expect(try Data(contentsOf: url) == before)
    #expect(credentials.all == ["mcp.svc.bearer": "keep"])
}
@Test func deleteRemovesOnlySecretsOwnedByThatServer() throws {
    let url = tempConfigURL(); defer { try? FileManager.default.removeItem(at: url) }
    let oauthServer = server("svc", oauth: OAuthSpec(clientID: "native"),
                             headers: [MCPHeaderSpec(name: "X-Key", secretAccount: "mcp.svc.header.x-key"),
                                       MCPHeaderSpec(name: "X-Shared", secretAccount: "shared.key"),
                                       MCPHeaderSpec(name: "X-Both", secretAccount: "mcp.svc.header.x-both")])
    let other = server("other", endpoint: "https://other.example.test/mcp",
                       headers: [MCPHeaderSpec(name: "X-Both", secretAccount: "mcp.svc.header.x-both")])
    let oauthAccount = try #require(oauthServer.oauthStorageAccount)
    let credentials = FakeCredentials(["mcp.svc.header.x-key": "1", "shared.key": "2", "mcp.svc.header.x-both": "3",
                                       oauthAccount: "{}", "mcp.svcx.bearer": "4", "unrelated": "5"])
    let editor = store(url, credentials)
    try editor.save(oauthServer, replacing: nil)
    try editor.save(other, replacing: nil)
    let removed = try editor.delete(serverID: "svc")
    #expect(removed == 2)
    // Kept: an account without the owned prefix, one still referenced by another server, and look-alike prefixes.
    #expect(credentials.all == ["shared.key": "2", "mcp.svc.header.x-both": "3", "mcp.svcx.bearer": "4", "unrelated": "5"])
    #expect(try editor.servers().map(\.id) == ["other"])
}
@Test func updateCleansUpDroppedSecretsAndChangedOAuthBinding() throws {
    let url = tempConfigURL(); defer { try? FileManager.default.removeItem(at: url) }
    let original = server("svc", oauth: OAuthSpec(clientID: "one"), headers: [MCPHeaderSpec(name: "X-Key", secretAccount: "mcp.svc.header.x-key")])
    let oldOAuth = try #require(original.oauthStorageAccount)
    let credentials = FakeCredentials([oldOAuth: "{}"])
    let editor = store(url, credentials)
    try editor.save(original, secrets: ["mcp.svc.header.x-key": "v"], replacing: nil)
    let updated = server("svc", oauth: OAuthSpec(clientID: "two"))
    try editor.save(updated, replacing: "svc")
    #expect(credentials.all.isEmpty)
    try editor.setEnabled(false, serverID: "svc")
    #expect(try editor.servers()[0].isEnabled == false)
    try editor.setEnabled(true, serverID: "svc")
    #expect(try editor.servers()[0].enabled == nil)
}

// MARK: Transport

@Test func customHeadersAndBearerReachTheServer() async throws {
    let host = "headers-\(UUID().uuidString.prefix(8)).example.test"
    MockMCPServer.configure(host: host, .init(requiredHeader: ("X-Api-Key", "k-123")))
    let spec = server(endpoint: "https://\(host)/mcp", credentialAccount: "mcp.svc.bearer",
                      tools: [ToolRule(name: "search", requiresConfirmation: true)],
                      headers: [MCPHeaderSpec(name: "X-Tenant", value: "acme"), MCPHeaderSpec(name: "X-Api-Key", secretAccount: "mcp.svc.header.x-api-key")])
    let factory = MCPTransportFactory(credentials: FakeCredentials(["mcp.svc.bearer": "tok", "mcp.svc.header.x-api-key": "k-123"]),
                                      sessionConfiguration: { MockMCPServer.sessionConfiguration() })
    let connections = MCPConnections(servers: [spec], factory: factory)
    let tools = try await connections.discover()
    await connections.disconnect()
    // Only the allowlisted tool is exposed, even though the server offers three.
    #expect(tools.map(\.originalName) == ["search"])
    let posts = MockMCPServer.requests(host: host).filter { $0.method == "POST" }
    #expect(posts.contains { $0.rpc == "initialize" } && posts.contains { $0.rpc == "tools/list" })
    for request in posts {
        #expect(request.headers["X-Tenant"] == "acme")
        #expect(request.headers["X-Api-Key"] == "k-123")
        #expect(request.headers["Authorization"] == "Bearer tok")
        #expect(request.headers["Content-Type"] == "application/json")
    }
    // The protocol-owned session header is still the SDK's (header names are case-insensitive).
    #expect(posts.last?.headers.first { $0.key.lowercased() == "mcp-session-id" }?.value == "session-1")
}
@Test func testConnectionListsToolsUsingUnsavedSecrets() async throws {
    let host = "probe-\(UUID().uuidString.prefix(8)).example.test"
    MockMCPServer.configure(host: host, .init(requiredHeader: ("X-Api-Key", "draft")))
    let spec = server(endpoint: "https://\(host)/mcp", headers: [MCPHeaderSpec(name: "X-Api-Key", secretAccount: "mcp.svc.header.x-api-key")])
    let credentials = FakeCredentials()
    let factory = MCPTransportFactory(credentials: credentials, sessionConfiguration: { MockMCPServer.sessionConfiguration() })
    let found = try await MCPServerProbe.discoverTools(spec, secretOverrides: ["mcp.svc.header.x-api-key": "draft"], factory: factory)
    #expect(found.map(\.name) == ["search", "send", "fancy"])
    #expect(found.map(\.schemaSupported) == [true, true, false])
    #expect(found[0].description == "Find things")
    #expect(credentials.all.isEmpty) // Testing never saves the draft secret.
}
@Test func missingSecretFailsBeforeAnyRequest() async throws {
    let host = "missing-\(UUID().uuidString.prefix(8)).example.test"
    MockMCPServer.configure(host: host)
    let spec = server(endpoint: "https://\(host)/mcp", tools: [ToolRule(name: "search", requiresConfirmation: true)],
                      headers: [MCPHeaderSpec(name: "X-Api-Key", secretAccount: "mcp.svc.header.x-api-key")])
    let factory = MCPTransportFactory(credentials: FakeCredentials(), sessionConfiguration: { MockMCPServer.sessionConfiguration() })
    await #expect(throws: (any Error).self) { try await MCPServerProbe.discoverTools(spec, factory: factory) }
    await #expect(throws: (any Error).self) { try await MCPConnections(servers: [spec], factory: factory).discover() }
    #expect(MockMCPServer.requests(host: host).isEmpty)
}
@Test func disabledServersAreNeverContacted() async throws {
    let host = "disabled-\(UUID().uuidString.prefix(8)).example.test"
    MockMCPServer.configure(host: host)
    let spec = server(endpoint: "https://\(host)/mcp", tools: [ToolRule(name: "search", requiresConfirmation: true)], enabled: false)
    let factory = MCPTransportFactory(credentials: FakeCredentials(), sessionConfiguration: { MockMCPServer.sessionConfiguration() })
    #expect(try await MCPConnections(servers: [spec], factory: factory).discover().isEmpty)
    #expect(MockMCPServer.requests(host: host).isEmpty)
}
@Test func managedPolicyLimitsTestConnectionToPolicyServers() async throws {
    let host = "managed-\(UUID().uuidString.prefix(8)).example.test"
    MockMCPServer.configure(host: host)
    let policyServer = server("svc", endpoint: "https://\(host)/mcp")
    let policy = try config { $0["mcpServers"] = [["id": "svc", "title": "Service svc", "endpoint": "https://\(host)/mcp", "tools": []]] }
    let factory = MCPTransportFactory(credentials: FakeCredentials(), sessionConfiguration: { MockMCPServer.sessionConfiguration() })
    #expect(try await MCPServerProbe.discoverTools(policyServer, managedPolicy: policy, factory: factory).count == 3)
    let draft = server("svc", endpoint: "https://elsewhere.example.test/mcp")
    await #expect(throws: (any Error).self) { try await MCPServerProbe.discoverTools(draft, managedPolicy: policy, factory: factory) }
    await #expect(throws: (any Error).self) {
        try await MCPServerProbe.discoverTools(policyServer, secretOverrides: ["x": "y"], managedPolicy: policy, factory: factory)
    }
}

@Test func typographicDashInHeaderValueGetsSpecificError() throws {
    #expect(throws: Never.self) { try MCPHeaderPolicy.validateValue("ak_--Jg0synthetic", headerName: "X-API-Key") }
    do {
        try MCPHeaderPolicy.validateValue("ak_\u{2014}Jg0synthetic", headerName: "X-API-Key")
        Issue.record("em dash accepted")
    } catch {
        #expect(error.localizedDescription.contains("typographic"))
    }
}
