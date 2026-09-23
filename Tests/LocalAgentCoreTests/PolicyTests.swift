import Testing
import Foundation
import MCP
@testable import LocalAgentCore

func config(_ transform: (inout [String: Any]) -> Void = { _ in }) throws -> AgentConfiguration {
    var json = try JSONSerialization.jsonObject(with: Data(AgentConfiguration.starterJSON.utf8)) as! [String: Any]
    // Fake inference does not load weights. Do not require a hosted CI machine to have model RAM.
    var models = json["models"] as! [[String: Any]]
    models[0]["minimumMemoryGB"] = 0
    json["models"] = models
    transform(&json)
    return try ConfigurationLoader.decode(JSONSerialization.data(withJSONObject: json))
}
@Test func disallowsNonLoopbackLocalProvider() throws {
    #expect(throws: (any Error).self) {
        try config { $0["providers"] = [["id":"local", "kind":"local", "baseURL":"http://192.168.1.1:9931/v1"]] }
    }
}
@Test func requiresRemoteTLS() throws {
    #expect(throws: (any Error).self) {
        try config { $0["providers"] = [["id":"local", "kind":"litellm", "baseURL":"http://gateway.example/v1"]] }
    }
}
@Test func rejectsEmbeddedCredentials() throws {
    #expect(throws: (any Error).self) { try AgentConfiguration.validateEndpoint(URL(string: "https://user:secret@example.com/v1")!, local: false) }
}
@Test func rejectsUnknownModelProviderAndUnboundedLimits() throws {
    #expect(throws: (any Error).self) { try config { $0["providers"] = [] } }
    #expect(throws: (any Error).self) {
        try config { $0["limits"] = ["inputBytes":2048,"outputTokens":768,"maxToolCalls":999,"toolResultBytes":2048,"timeoutSeconds":120] }
    }
}
@Test func contextIncludesToolsAndResults() throws {
    let configuration = try config()
    let messages = [ChatMessage(role: "tool", content: String(repeating: "x", count: 8000))]
    #expect(throws: (any Error).self) {
        try ContextBudget.validate(messages: messages, tools: [], model: configuration.models[0], limits: configuration.limits)
    }
}
@Test func schemaChecksRequiredTypesAndUnknownConstraints() throws {
    let schema: Value = .object(["type": .string("object"), "required": .array([.string("count")]),
        "properties": .object(["count": .object(["type": .string("integer"), "maximum": .int(10)])]),
        "additionalProperties": .bool(false)])
    try ToolSchema.validate(.object(["count": .int(5)]), schema: schema)
    #expect(throws: (any Error).self) { try ToolSchema.validate(.object([:]), schema: schema) }
    #expect(throws: (any Error).self) { try ToolSchema.validate(.object(["count": .int(11)]), schema: schema) }
    #expect(throws: (any Error).self) { try ToolSchema.validate(.object(["count": .string("5")]), schema: schema) }
    #expect(throws: (any Error).self) { try ToolSchema.checkSupported(.object(["$ref": .string("external")])) }
}
@Test func auditContainsOnlyMetadata() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let log = AuditLog(directory: directory)
    try await log.record(.runStarted, runID: UUID(), modelID: "approved")
    let data = try Data(contentsOf: directory.appendingPathComponent("events.jsonl"))
    let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    #expect(Set(object.keys) == Set(["timestamp", "runID", "event", "modelID"]))
    #expect(object["event"] as? String == "runStarted")
}
