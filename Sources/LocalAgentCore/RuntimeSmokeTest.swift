import Foundation
import MCP

/// Content-free end-to-end check of the managed runtime using the resolved policy and fixed synthetic prompts.
/// Used by `minimodell --runtime-smoke-test` inside the packaged, sandboxed app. Reports timings, token counts
/// and sizes. Reply text is included only with `showReply`, and only because every prompt here is synthetic.
public enum RuntimeSmokeTest {
    public struct Report: Encodable, Sendable {
        public var ok = false
        public var modelID: String?
        public var artifactID: String?
        public var runtimeTag: String?
        public var startupMilliseconds: Int?
        public var inferenceMilliseconds: Int?
        public var replyBytes: Int?
        public var promptTokens: Int?
        public var completionTokens: Int?
        public var promptTokensPerSecond: Double?
        public var generationTokensPerSecond: Double?
        public var reply: String?
        public var tool: ToolReport?
        public var finalState = "stopped"
        public var failure: String?
        public init() {}
    }
    /// Synthetic tool round trip through `TaskRunner` with an in-process fixture tool (no MCP server, no account).
    public struct ToolReport: Encodable, Sendable {
        public var ok = false
        public var milliseconds: Int?
        public var toolExecutions = 0
        public var argumentsMatched = false
        public var finalAnswerBytes: Int?
        public var finalAnswerUsesToolResult = false
        public var finalAnswer: String?
        public var failure: String?
    }
    static let prompt = "In two sentences, explain what a checksum is."
    static let toolPrompt = "What is the shipping status of order A-1001?"

    public static func run(configuration: AgentConfiguration, runtime: RuntimeManager, holdSeconds: Int = 0,
                           includeTool: Bool = false, showReply: Bool = false) async -> Report {
        var report = Report()
        report.runtimeTag = RuntimeManager.bundledRuntimeTag
        guard let model = configuration.models.first(where: { model in
            configuration.providers.contains { $0.id == model.providerID && $0.kind == .managed }
        }), let provider = configuration.providers.first(where: { $0.id == model.providerID }) else {
            report.failure = "No managed provider in the resolved policy."
            return report
        }
        let artifact = configuration.artifact(for: provider)
        report.modelID = model.id
        report.artifactID = artifact?.id
        let clock = ContinuousClock()
        do {
            let started = clock.now
            _ = try await runtime.acquire(provider: provider, model: model, artifact: artifact)
            report.startupMilliseconds = milliseconds(clock.now - started)
            await runtime.release()
            let inferenceStart = clock.now
            let (reply, metrics) = try await ManagedInferenceClient(runtime: runtime, provider: provider, artifact: artifact).completeMeasured(
                messages: [ChatMessage(role: "user", content: prompt)], tools: [], model: model,
                limits: RunLimits(inputBytes: 2048, outputTokens: 256, maxToolCalls: 0, toolResultBytes: 2048, timeoutSeconds: 120))
            report.inferenceMilliseconds = milliseconds(clock.now - inferenceStart)
            report.replyBytes = reply.content?.utf8.count ?? 0
            report.promptTokens = metrics?.usage?.prompt_tokens ?? metrics?.timings?.prompt_n
            report.completionTokens = metrics?.usage?.completion_tokens ?? metrics?.timings?.predicted_n
            report.promptTokensPerSecond = metrics?.timings?.prompt_per_second.map(rounded)
            report.generationTokensPerSecond = metrics?.timings?.predicted_per_second.map(rounded)
            if showReply { report.reply = reply.content }
            report.ok = (report.replyBytes ?? 0) > 0
            if includeTool {
                let tool = await runTool(configuration: configuration, model: model, provider: provider,
                                         artifact: artifact, runtime: runtime, showReply: showReply)
                report.tool = tool
                report.ok = report.ok && tool.ok
            }
            if holdSeconds > 0 { try? await Task.sleep(for: .seconds(min(holdSeconds, 120))) }
        } catch {
            report.failure = (error as? AgentError)?.localizedDescription ?? "Runtime smoke test failed."
        }
        await runtime.stop()
        report.finalState = await runtime.state.summary
        return report
    }

    private static func runTool(configuration: AgentConfiguration, model: ModelSpec, provider: ProviderSpec,
                                artifact: ModelArtifact?, runtime: RuntimeManager, showReply: Bool) async -> ToolReport {
        var report = ToolReport()
        let fixture = SyntheticOrderTool()
        let runner = TaskRunner(inference: ManagedInferenceClient(runtime: runtime, provider: provider, artifact: artifact),
                                tools: fixture)
        let clock = ContinuousClock(), started = clock.now
        do {
            // The fixture tool is read-only and needs no approval; any approval request is declined.
            let answer = try await runner.run(input: toolPrompt, modelID: model.id, configuration: configuration) { _ in false }
            report.finalAnswerBytes = answer.utf8.count
            report.finalAnswerUsesToolResult = answer.localizedCaseInsensitiveContains("shipped")
            if showReply { report.finalAnswer = answer }
        } catch {
            report.failure = (error as? AgentError)?.localizedDescription ?? "Tool round trip failed."
        }
        report.milliseconds = milliseconds(clock.now - started)
        report.toolExecutions = await fixture.executions
        report.argumentsMatched = await fixture.lastOrderID == "A-1001"
        report.ok = report.failure == nil && report.toolExecutions == 1 && report.argumentsMatched && report.finalAnswerUsesToolResult
        return report
    }

    private static func rounded(_ value: Double) -> Double { (value * 10).rounded() / 10 }
    private static func milliseconds(_ duration: Duration) -> Int {
        Int(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000)
    }
}

/// In-process synthetic tool used only by the smoke test: fixed data, no network, no account.
actor SyntheticOrderTool: ToolClient {
    private(set) var executions = 0
    private(set) var lastOrderID: String?
    func discover() async throws -> [AvailableTool] {
        let schema: Value = .object([
            "type": .string("object"),
            "properties": .object(["order_id": .object(["type": .string("string"), "description": .string("Order ID such as A-1001")])]),
            "required": .array([.string("order_id")]),
            "additionalProperties": .bool(false)])
        return [AvailableTool(alias: "lookup_order_status", serverID: "synthetic", originalName: "lookup_order_status",
                              requiresConfirmation: false,
                              definition: FunctionTool(function: .init(name: "lookup_order_status",
                                  description: "Look up the shipping status of a synthetic test order by its ID.", parameters: schema)))]
    }
    func execute(_ tool: AvailableTool, arguments: [String: Value]) async throws -> String {
        executions += 1
        if case .string(let id)? = arguments["order_id"] { lastOrderID = id }
        return #"{"order_id":"A-1001","status":"shipped","carrier":"SyntheticPost"}"#
    }
    func disconnect() async {}
}
