import Testing
import Foundation
@testable import LocalAgentCore

// ADR 0011: `lan` providers. No network access; hosts below are never contacted.

private func lanProvider(_ url: String, insecure: Bool? = true, credential: String? = nil) -> [String: Any] {
    var provider: [String: Any] = ["id": "lan", "kind": "lan", "baseURL": url]
    if let insecure { provider["allowInsecureTransport"] = insecure }
    if let credential { provider["credentialAccount"] = credential }
    return provider
}
private func lanConfig(_ provider: [String: Any]) throws -> AgentConfiguration {
    try config { json in
        json["providers"] = [provider]
        var models = json["models"] as! [[String: Any]]
        models[0]["providerID"] = "lan"
        json["models"] = models
    }
}

@Test(arguments: ["10.0.0.1", "10.255.255.254", "172.16.0.1", "172.31.255.254", "192.168.1.50", "169.254.10.20",
                  "fd12:3456:789a::1", "fc00::1", "fe80::1", "fe80::1%en0", "[fd00::1]",
                  "macbook.local", "M2-Max.LOCAL", "studio.local.", "a.b.local"])
func acceptsLANHosts(host: String) {
    #expect(LANHost.classify(host) != nil)
}

@Test(arguments: ["8.8.8.8", "1.1.1.1", "172.15.0.1", "172.32.0.1", "192.169.1.1", "100.64.0.1", "11.0.0.1",
                  "127.0.0.1", "0.0.0.0", "255.255.255.255", "224.0.0.251", "169.254.169.254",
                  "::1", "::", "2001:db8::1", "2606:4700::1111", "fec0::1", "ff02::fb", "::ffff:192.168.1.1", "fd00::1%en0",
                  "localhost", "localhost.", "local", ".local", "lmstudio", "lmstudio.lan", "studio.home.arpa",
                  "lmstudio.local.example.com", "example.com", "localhost.localdomain", "evil.com#.local",
                  "3232235777", "0xC0.0xA8.1.1", "192.168.001.001", "192.168.1", "192.168.1.1.", "-bad.local", "bad_.local", ""])
func rejectsNonLANHosts(host: String) {
    #expect(LANHost.classify(host) == nil)
}

@Test func lanRequiresExplicitInsecureTransportForHTTP() throws {
    _ = try lanConfig(lanProvider("http://192.168.1.50:1234/v1"))
    _ = try lanConfig(lanProvider("http://m2-max.local:1234/v1"))
    _ = try lanConfig(lanProvider("http://[fd00::50]:1234/v1"))
    _ = try lanConfig(lanProvider("https://192.168.1.50:1234/v1", insecure: nil))
    _ = try lanConfig(lanProvider("https://m2-max.local/v1", insecure: false))
    #expect(throws: (any Error).self) { try lanConfig(lanProvider("http://192.168.1.50:1234/v1", insecure: nil)) }
    #expect(throws: (any Error).self) { try lanConfig(lanProvider("http://192.168.1.50:1234/v1", insecure: false)) }
    // A meaningless flag on an HTTPS URL is a misconfiguration.
    #expect(throws: (any Error).self) { try lanConfig(lanProvider("https://192.168.1.50/v1", insecure: true)) }
    #expect(throws: (any Error).self) { try lanConfig(lanProvider("ftp://192.168.1.50/v1")) }
}

@Test func lanRejectsPublicAndPlainHostnames() throws {
    for url in ["http://8.8.8.8:1234/v1", "https://8.8.8.8/v1", "http://lmstudio:1234/v1", "http://lmstudio.lan:1234/v1",
                "https://llm.example.com/v1", "http://localhost:1234/v1", "http://127.0.0.1:1234/v1", "http://[::1]:1234/v1",
                "http://3232235777:1234/v1"] {
        #expect(throws: (any Error).self, "\(url)") { try lanConfig(lanProvider(url)) }
        #expect(throws: (any Error).self, "\(url)") { try lanConfig(lanProvider(url, insecure: nil)) }
    }
}

@Test func lanRejectsCredentialsQueryAndFragment() throws {
    for url in ["http://user:secret@192.168.1.50:1234/v1", "http://192.168.1.50:1234/v1?key=abc", "http://192.168.1.50:1234/v1#x"] {
        #expect(throws: (any Error).self, "\(url)") { try lanConfig(lanProvider(url)) }
    }
}

@Test func insecureTransportFlagOnlyForLAN() throws {
    #expect(throws: (any Error).self) {
        try config { $0["providers"] = [["id": "local", "kind": "local", "baseURL": "http://127.0.0.1:9931/v1", "allowInsecureTransport": true]] }
    }
    #expect(throws: (any Error).self) {
        try config { $0["providers"] = [["id": "local", "kind": "litellm", "baseURL": "http://gateway.example/v1", "allowInsecureTransport": true]] }
    }
    // Existing configurations without the field are unchanged.
    _ = try config()
}

@Test func lanProviderNeedsBaseURLAndNoRuntime() throws {
    #expect(throws: (any Error).self) { try lanConfig(["id": "lan", "kind": "lan"]) }
    #expect(throws: (any Error).self) {
        try lanConfig(["id": "lan", "kind": "lan", "baseURL": "http://192.168.1.50:1234/v1", "allowInsecureTransport": true,
                       "runtime": ["artifact": "qwen3-4b-instruct-2507-q4_k_m"]])
    }
}

@Test func lanProviderAcceptsKeychainCredentialAccount() throws {
    let configuration = try lanConfig(lanProvider("http://192.168.1.50:1234/v1", credential: "lan.lmstudio"))
    #expect(configuration.providers[0].credentialAccount == "lan.lmstudio")
}

@Test func lanIsNotOnDeviceSoMemoryGateDoesNotApply() {
    #expect(!ProviderSpec.Kind.lan.isOnDevice)
    #expect(ProviderSpec.Kind.local.isOnDevice && ProviderSpec.Kind.managed.isOnDevice && !ProviderSpec.Kind.litellm.isOnDevice)
}

@Test func unknownKindFailsClosed() throws {
    // An older build (or a typo) must reject, not reinterpret, an unknown provider kind.
    #expect(throws: (any Error).self) {
        try config { $0["providers"] = [["id": "local", "kind": "remote-lan", "baseURL": "http://192.168.1.50:1234/v1"]] }
    }
}

@Test func destinationLabels() throws {
    let insecure = try lanConfig(lanProvider("http://192.168.1.50:1234/v1")).providers[0].destination
    #expect(insecure == .lan(host: "192.168.1.50", encrypted: false))
    #expect(insecure.label.hasPrefix("LAN · unencrypted"))
    #expect(insecure.label.contains("tool results") && insecure.label.contains("192.168.1.50"))
    #expect(insecure.code == "lan-unencrypted")
    let tls = try lanConfig(lanProvider("https://m2-max.local/v1", insecure: nil)).providers[0].destination
    #expect(tls == .lan(host: "m2-max.local", encrypted: true))
    #expect(tls.label.hasPrefix("LAN · TLS") && tls.label.contains("tool results"))
    #expect(tls.code == "lan-tls")
    #expect(try config().providers[0].destination == .thisMac)
    #expect(ProviderSpec(id: "g", kind: .litellm, baseURL: URL(string: "https://g.example/v1")).destination == .cloud)
    #expect(ProviderSpec(id: "m", kind: .managed, baseURL: nil).destination == .thisMac)
}

@Test func resolvedAddressesMustAllBeLAN() throws {
    try LANHost.checkResolved([[192, 168, 1, 50]])
    try LANHost.checkResolved([[10, 0, 0, 2], [0xfd, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]])
    #expect(throws: (any Error).self) { try LANHost.checkResolved([]) }
    // DNS rebinding / public answer for a .local name: one public address rejects the whole answer.
    #expect(throws: (any Error).self) { try LANHost.checkResolved([[192, 168, 1, 50], [93, 184, 216, 34]]) }
    #expect(throws: (any Error).self) { try LANHost.checkResolved([[127, 0, 0, 1]]) }
    #expect(throws: (any Error).self) { try LANHost.checkResolved([[0x20, 0x01, 0x0d, 0xb8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]]) }
}

@Test func requestTimeCheckRejectsInvalidLANProviderBeforeNetwork() async throws {
    // Constructed directly (bypassing configuration validation): the client re-validates before sending.
    let publicHost = ProviderSpec(id: "lan", kind: .lan, baseURL: URL(string: "http://8.8.8.8:1234/v1"), allowInsecureTransport: true)
    let noFlag = ProviderSpec(id: "lan", kind: .lan, baseURL: URL(string: "http://192.168.1.50:1234/v1"))
    let configuration = try config()
    for provider in [publicHost, noFlag] {
        await #expect(throws: AgentError.self) {
            _ = try await CompatibleInferenceClient(provider: provider)
                .complete(messages: [ChatMessage(role: "user", content: "x")], tools: [], model: configuration.models[0], limits: configuration.limits)
        }
        await #expect(throws: AgentError.self) { _ = try await ProviderProbe.listModels(provider: provider) }
    }
    await #expect(throws: AgentError.self) {
        _ = try await ProviderProbe.listModels(provider: ProviderSpec(id: "m", kind: .managed, baseURL: nil))
    }
}

@Test func parsesOpenAIModelList() throws {
    let json = #"{"object":"list","data":[{"id":"qwen3-8b","object":"model"},{"id":"llama-3.1-8b","owned_by":"x"},{"id":""},{"id":"bad\u0007id"}]}"#
    #expect(try ProviderProbe.parseModelList(Data(json.utf8)) == ["qwen3-8b", "llama-3.1-8b"])
    #expect(throws: AgentError.self) { try ProviderProbe.parseModelList(Data(#"{"error":"nope"}"#.utf8)) }
    let many = "{\"data\":[" + (0..<150).map { "{\"id\":\"m\($0)\"}" }.joined(separator: ",") + "]}"
    #expect(try ProviderProbe.parseModelList(Data(many.utf8)).count == ProviderProbe.maximumModelIDs)
}

@Test func lanExampleConfigValidates() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Config/lan-lmstudio.example.json")
    let configuration = try ConfigurationLoader.decode(Data(contentsOf: url))
    #expect(configuration.providers.contains { $0.kind == .lan && $0.allowInsecureTransport == true })
}
