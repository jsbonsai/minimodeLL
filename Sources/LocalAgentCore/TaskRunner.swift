import Foundation
import MCP

public struct ToolProposal: Sendable, Identifiable {
    public let id: String
    public let server: String
    public let tool: String
    public let arguments: String
}
public struct TaskRunner: Sendable {
    public typealias Approval = @Sendable (ToolProposal) async -> Bool
    private let inference: any InferenceClient
    private let tools: any ToolClient
    private let audit: AuditLog
    public init(inference: any InferenceClient, tools: any ToolClient, audit: AuditLog = AuditLog()) {
        self.inference = inference; self.tools = tools; self.audit = audit
    }
    public func run(input: String, modelID: String, configuration: AgentConfiguration,
                    approve: @escaping Approval) async throws -> String {
        try configuration.validate()
        guard let model = configuration.models.first(where: { $0.id == modelID }),
              let provider = configuration.providers.first(where: { $0.id == model.providerID }) else {
            throw AgentError.rejected("Select an approved model.")
        }
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              input.utf8.count <= configuration.limits.inputBytes else {
            throw AgentError.rejected("Keep the request within \(configuration.limits.inputBytes) UTF-8 bytes.")
        }
        if provider.kind.isOnDevice {
            let memory = ProcessInfo.processInfo.physicalMemory / 1_073_741_824
            guard memory >= model.minimumMemoryGB else { throw AgentError.rejected("This model requires more system memory.") }
        }
        let runID = UUID()
        try await audit.record(.runStarted, runID: runID, modelID: model.id)
        do {
            let result = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    try await withTaskCancellationHandler {
                        try await loop(input: input, model: model, configuration: configuration, runID: runID, approve: approve)
                    } onCancel: {
                        Task { await tools.disconnect() }
                    }
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(configuration.limits.timeoutSeconds))
                    throw AgentError.rejected("Task time limit reached. Check any pending action before retrying.")
                }
                defer { group.cancelAll() }
                guard let result = try await group.next() else { throw CancellationError() }
                return result
            }
            await tools.disconnect()
            try await audit.record(.runCompleted, runID: runID, modelID: model.id)
            return result
        } catch {
            await tools.disconnect()
            try await audit.record(error is CancellationError ? .runCancelled : .runFailed, runID: runID, modelID: model.id)
            throw error
        }
    }
    private func loop(input: String, model: ModelSpec, configuration: AgentConfiguration, runID: UUID,
                      approve: @escaping Approval) async throws -> String {
        let limits = configuration.limits
        let available = try await tools.discover()
        let definitions = available.map(\.definition)
        var messages = [ChatMessage(role: "system", content: configuration.systemPrompt), ChatMessage(role: "user", content: input)]
        var calls = 0
        var seen = Set<String>()
        while true {
            try Task.checkCancellation()
            try ContextBudget.validate(messages: messages, tools: definitions, model: model, limits: limits)
            let reply = try await inference.complete(messages: messages, tools: definitions, model: model, limits: limits)
            try Task.checkCancellation()
            guard let proposed = reply.tool_calls, !proposed.isEmpty else {
                guard let content = reply.content, !content.isEmpty else { throw AgentError.rejected("The model returned an empty response.") }
                return content
            }
            guard proposed.count == 1 else { throw AgentError.rejected("This app accepts one tool action at a time.") }
            guard calls < limits.maxToolCalls else { throw AgentError.rejected("Tool step limit reached. Narrow the task.") }
            let call = proposed[0]
            guard call.type == "function", !call.id.isEmpty, seen.insert(call.id).inserted,
                  let tool = available.first(where: { $0.alias == call.function.name }) else {
                throw AgentError.rejected("Model requested an unknown or repeated tool call.")
            }
            let args = try JSONDecoder().decode([String: Value].self, from: Data(call.function.arguments.utf8))
            try ToolSchema.validate(.object(args), schema: tool.definition.function.parameters)
            let toolID = tool.serverID + "/" + tool.originalName
            try await audit.record(.toolProposed, runID: runID, modelID: model.id, toolID: toolID)
            if tool.requiresConfirmation {
                let accepted = await approve(ToolProposal(id: call.id, server: tool.serverID, tool: tool.originalName, arguments: call.function.arguments))
                try Task.checkCancellation()
                try await audit.record(accepted ? .toolApproved : .toolDenied, runID: runID, modelID: model.id, toolID: toolID)
                guard accepted else { throw AgentError.rejected("Tool action declined.") }
            }
            try Task.checkCancellation()
            let output = try await tools.execute(tool, arguments: args)
            try await audit.record(.toolCompleted, runID: runID, modelID: model.id, toolID: toolID)
            // Reject oversized results rather than silently losing evidence or splitting structured output.
            guard output.utf8.count <= limits.toolResultBytes else {
                throw AgentError.rejected("Tool result is too large. Request a smaller date range or fewer items.")
            }
            messages.append(reply)
            messages.append(ChatMessage(role: "tool", content: output, toolCallID: call.id))
            calls += 1
        }
    }
}
