import Foundation

/// Content-free end-to-end check of the managed runtime using the resolved policy and a fixed synthetic prompt.
/// Used by `minimodell --runtime-smoke-test` inside the packaged, sandboxed app. Reports timings and sizes only.
public enum RuntimeSmokeTest {
    public struct Report: Encodable, Sendable {
        public var ok = false
        public var modelID: String?
        public var runtimeTag: String?
        public var startupMilliseconds: Int?
        public var inferenceMilliseconds: Int?
        public var replyBytes: Int?
        public var finalState = "stopped"
        public var failure: String?
        public init() {}
    }
    static let prompt = "Reply with exactly one word: ready"

    public static func run(configuration: AgentConfiguration, runtime: RuntimeManager, holdSeconds: Int = 0) async -> Report {
        var report = Report()
        report.runtimeTag = bundledRuntimeTag()
        guard let model = configuration.models.first(where: { model in
            configuration.providers.contains { $0.id == model.providerID && $0.kind == .managed }
        }), let provider = configuration.providers.first(where: { $0.id == model.providerID }) else {
            report.failure = "No managed provider in the resolved policy."
            return report
        }
        report.modelID = model.id
        let clock = ContinuousClock()
        do {
            let started = clock.now
            _ = try await runtime.acquire(provider: provider, model: model)
            report.startupMilliseconds = milliseconds(clock.now - started)
            await runtime.release()
            let inferenceStart = clock.now
            let reply = try await ManagedInferenceClient(runtime: runtime, provider: provider).complete(
                messages: [ChatMessage(role: "user", content: prompt)], tools: [], model: model,
                limits: RunLimits(inputBytes: 2048, outputTokens: 64, maxToolCalls: 0, toolResultBytes: 2048, timeoutSeconds: 60))
            report.inferenceMilliseconds = milliseconds(clock.now - inferenceStart)
            report.replyBytes = reply.content?.utf8.count ?? 0
            report.ok = (report.replyBytes ?? 0) > 0
            if holdSeconds > 0 { try? await Task.sleep(for: .seconds(min(holdSeconds, 120))) }
        } catch {
            report.failure = (error as? AgentError)?.localizedDescription ?? "Runtime smoke test failed."
        }
        await runtime.stop()
        report.finalState = await runtime.state.summary
        return report
    }

    /// The pinned llama.cpp tag embedded by scripts/package-app.sh, if any.
    public static func bundledRuntimeTag() -> String? {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Runtime/runtime.lock.json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["tag"] as? String
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        Int(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000)
    }
}
