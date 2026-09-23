import Testing
import Foundation
import MCP
@testable import LocalAgentCore

actor FakeInference: InferenceClient {
    var replies: [ChatMessage]
    var requests = 0
    init(_ replies: [ChatMessage]) { self.replies = replies }
    func complete(messages: [ChatMessage], tools: [FunctionTool], model: ModelSpec, limits: RunLimits) async throws -> ChatMessage {
        requests += 1
        guard !replies.isEmpty else { throw AgentError.rejected("Unexpected inference request.") }
        return replies.removeFirst()
    }
}
actor FakeTools: ToolClient {
    var executions = 0
    var disconnected = false
    let output: String
    init(output: String = "One meeting at noon.") { self.output = output }
    func discover() async throws -> [AvailableTool] {
        [.init(alias: "calendar", serverID: "work", originalName: "create_event", requiresConfirmation: true,
               definition: .init(function: .init(name: "calendar", description: "Calendar",
                    parameters: .object(["type": .string("object"), "additionalProperties": .bool(false)]))))]
    }
    func execute(_ tool: AvailableTool, arguments: [String: Value]) async throws -> String { executions += 1; return output }
    func disconnect() async { disconnected = true }
}
func toolReply(_ name: String = "calendar") -> ChatMessage {
    .init(role: "assistant", content: nil,
          toolCalls: [.init(id: "call1", type: "function", function: .init(name: name, arguments: "{}"))])
}
func runnerAudit() -> (AuditLog, URL) {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    return (AuditLog(directory: url), url)
}
@Test func deniedActionNeverExecutes() async throws {
    let (audit, url) = runnerAudit(); defer { try? FileManager.default.removeItem(at: url) }
    let inference = FakeInference([toolReply()]); let tools = FakeTools()
    let runner = TaskRunner(inference: inference, tools: tools, audit: audit)
    await #expect(throws: (any Error).self) {
        try await runner.run(input: "Create a meeting", modelID: "local-approved", configuration: config(), approve: { _ in false })
    }
    #expect(await tools.executions == 0)
    #expect(await tools.disconnected)
}
@Test func approvedActionReturnsFinalAnswer() async throws {
    let (audit, url) = runnerAudit(); defer { try? FileManager.default.removeItem(at: url) }
    let inference = FakeInference([toolReply(), .init(role: "assistant", content: "Meeting created.")]); let tools = FakeTools()
    let runner = TaskRunner(inference: inference, tools: tools, audit: audit)
    let output = try await runner.run(input: "Create a meeting", modelID: "local-approved", configuration: config(), approve: { _ in true })
    #expect(output == "Meeting created.")
    #expect(await tools.executions == 1)
    #expect(await tools.disconnected)
}
@Test func unknownToolNeverExecutes() async throws {
    let (audit, url) = runnerAudit(); defer { try? FileManager.default.removeItem(at: url) }
    let tools = FakeTools()
    let runner = TaskRunner(inference: FakeInference([toolReply("unapproved")]), tools: tools, audit: audit)
    await #expect(throws: (any Error).self) {
        try await runner.run(input: "Lookup", modelID: "local-approved", configuration: config(), approve: { _ in true })
    }
    #expect(await tools.executions == 0)
}
@Test func oversizedToolResultStopsBeforeAnotherInference() async throws {
    let (audit, url) = runnerAudit(); defer { try? FileManager.default.removeItem(at: url) }
    let inference = FakeInference([toolReply()]); let tools = FakeTools(output: String(repeating: "x", count: 2049))
    let runner = TaskRunner(inference: inference, tools: tools, audit: audit)
    await #expect(throws: (any Error).self) {
        try await runner.run(input: "Lookup", modelID: "local-approved", configuration: config(), approve: { _ in true })
    }
    #expect(await inference.requests == 1)
}
@Test func oversizedInputNeverReachesInference() async throws {
    let (audit, url) = runnerAudit(); defer { try? FileManager.default.removeItem(at: url) }
    let inference = FakeInference([])
    let runner = TaskRunner(inference: inference, tools: FakeTools(), audit: audit)
    await #expect(throws: (any Error).self) {
        try await runner.run(input: String(repeating: "x", count: 2049), modelID: "local-approved", configuration: config(), approve: { _ in true })
    }
    #expect(await inference.requests == 0)
}

@Test func cancellationWhileAwaitingApprovalNeverExecutes() async throws {
    let (audit, url) = runnerAudit(); defer { try? FileManager.default.removeItem(at: url) }
    let tools = FakeTools()
    let runner = TaskRunner(inference: FakeInference([toolReply()]), tools: tools, audit: audit)
    let task = Task {
        try await runner.run(input: "Create a meeting", modelID: "local-approved", configuration: config()) { _ in
            try? await Task.sleep(for: .seconds(20))
            return true
        }
    }
    try await Task.sleep(for: .milliseconds(30))
    task.cancel()
    await #expect(throws: (any Error).self) { try await task.value }
    #expect(await tools.executions == 0)
    #expect(await tools.disconnected)
}
@Test func duplicateCallIDDoesNotRepeatAction() async throws {
    let (audit, url) = runnerAudit(); defer { try? FileManager.default.removeItem(at: url) }
    let tools = FakeTools()
    let runner = TaskRunner(inference: FakeInference([toolReply(), toolReply()]), tools: tools, audit: audit)
    await #expect(throws: (any Error).self) {
        try await runner.run(input: "Create a meeting", modelID: "local-approved", configuration: config(), approve: { _ in true })
    }
    #expect(await tools.executions == 1)
}
@Test func auditFailureBlocksInference() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data("not a directory".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let inference = FakeInference([])
    let runner = TaskRunner(inference: inference, tools: FakeTools(), audit: AuditLog(directory: url))
    await #expect(throws: (any Error).self) {
        try await runner.run(input: "Hello", modelID: "local-approved", configuration: config(), approve: { _ in true })
    }
    #expect(await inference.requests == 0)
}

@Test func insufficientPhysicalMemoryBlocksLocalInference() async throws {
    let (audit, url) = runnerAudit(); defer { try? FileManager.default.removeItem(at: url) }
    let inference = FakeInference([])
    let configuration = try config { json in
        var models = json["models"] as! [[String: Any]]
        models[0]["minimumMemoryGB"] = Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) + 1
        json["models"] = models
    }
    let runner = TaskRunner(inference: inference, tools: FakeTools(), audit: audit)
    await #expect(throws: (any Error).self) {
        try await runner.run(input: "Hello", modelID: "local-approved", configuration: configuration, approve: { _ in true })
    }
    #expect(await inference.requests == 0)
}
