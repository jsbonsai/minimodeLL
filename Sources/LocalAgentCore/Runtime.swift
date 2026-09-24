import Foundation
import OSLog
import Security

/// Lifecycle of the app-owned bundled llama-server (ADR 0008).
public enum RuntimeState: Sendable, Equatable {
    case stopped, starting, ready, stopping
    case failed(String)
    /// Short, content-free text for the UI.
    public var summary: String {
        switch self {
        case .stopped: "Local model stopped"
        case .starting: "Starting local model…"
        case .ready: "Local model ready"
        case .stopping: "Stopping local model…"
        case .failed(let reason): "Local model failed: \(reason)"
        }
    }
}

/// Where a ready runtime listens. The key is per-launch, random, never persisted or logged.
public struct RuntimeEndpoint: Sendable, CustomStringConvertible {
    public let baseURL: URL
    let apiKey: String
    public var description: String { "RuntimeEndpoint(\(baseURL.absoluteString))" }
}

/// A launched helper process. Test seam; the real implementation wraps `Foundation.Process`.
public protocol RuntimeProcess: AnyObject, Sendable {
    var processIdentifier: Int32 { get }
    var isRunning: Bool { get }
    /// SIGTERM.
    func terminate()
    /// SIGKILL.
    func forceKill()
    /// Resolves when the process has exited. Safe to call from several waiters.
    func exitStatus() async -> Int32
}

/// Operating-system services the runtime manager needs. Test seam, not a plugin system.
public protocol RuntimeHost: Sendable {
    /// A currently free TCP port on 127.0.0.1. Another process may still take it before the child binds,
    /// which is why readiness verifies the child is alive and answers a key challenge.
    func reserveLoopbackPort() throws -> UInt16
    func launch(executable: URL, arguments: [String], environment: [String: String]) throws -> any RuntimeProcess
    /// Loopback-only GET. Returns status and a bounded body. Never follows redirects.
    func get(_ url: URL, bearer: String?) async throws -> (status: Int, body: Data)
}

/// Settings for one launch. Equal settings reuse a running process; different settings restart it.
struct RuntimeLaunchSettings: Sendable, Equatable {
    let helper: URL
    let modelPath: URL
    let alias: String
    let contextTokens: Int
    let parallel: Int
    let startupTimeout: Duration
    /// nil disables idle unload.
    let idleUnload: Duration?

    func arguments(port: UInt16) -> [String] {
        // Each slot gets the policy context size. No web UI, no network model downloads, no built-in
        // agent tools, no slot inspection endpoint, and no server logs (they could contain content).
        ["--model", modelPath.path, "--host", "127.0.0.1", "--port", String(port),
         "--alias", alias, "--ctx-size", String(contextTokens * parallel), "--parallel", String(parallel),
         "--jinja", "--no-webui", "--offline", "--no-slots", "--log-disable"]
    }
}

/// Owns the bundled llama-server: launch on a random loopback port with a per-launch API key, verify it,
/// share it between inference calls, unload it when idle, and stop it on quit. Never falls back to cloud.
public actor RuntimeManager {
    private struct Running {
        let settings: RuntimeLaunchSettings
        let process: any RuntimeProcess
        let endpoint: RuntimeEndpoint
        let generation: Int
    }
    private let host: any RuntimeHost
    private let helperURL: URL?
    private let modelsDirectory: URL
    private let pollInterval: Duration
    private let stopGrace: Duration
    private let quitHandle = QuitHandle()
    private let logger = Logger(subsystem: Brand.identity, category: "runtime")
    public private(set) var state: RuntimeState = .stopped
    private var current: Running?
    private var pending: (any RuntimeProcess)?
    private var starting: (settings: RuntimeLaunchSettings, task: Task<RuntimeEndpoint, any Error>)?
    private var leases = 0
    private var idleTask: Task<Void, Never>?
    private var generation = 0
    private var observers: [UUID: AsyncStream<RuntimeState>.Continuation] = [:]

    private let guardURL: URL?
    private let modelStore: ModelStore?
    private let runtimeTag: String?

    /// `guardURL`: optional supervisor that launches the server and stops it if the app dies (see RuntimeGuard).
    /// `modelStore`: verifies catalog artifacts before launch (ADR 0009). `runtimeTag`: the bundled llama.cpp tag
    /// artifacts must list in `runtimeTags`.
    public init(host: any RuntimeHost = SystemRuntimeHost(), helperURL: URL? = RuntimeManager.bundledHelperURL,
                guardURL: URL? = RuntimeManager.bundledGuardURL,
                modelsDirectory: URL = RuntimeManager.defaultModelsDirectory,
                modelStore: ModelStore? = nil, runtimeTag: String? = RuntimeManager.bundledRuntimeTag,
                pollInterval: Duration = .milliseconds(250), stopGrace: Duration = .seconds(5)) {
        self.host = host; self.helperURL = helperURL; self.guardURL = guardURL; self.modelsDirectory = modelsDirectory
        self.modelStore = modelStore; self.runtimeTag = runtimeTag
        self.pollInterval = pollInterval; self.stopGrace = stopGrace
    }

    /// The pinned llama.cpp tag embedded by scripts/package-app.sh (`Contents/Resources/Runtime/runtime.lock.json`).
    public static var bundledRuntimeTag: String? {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Runtime/runtime.lock.json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["tag"] as? String
    }

    /// `Contents/Helpers/llama-server` inside the packaged app, or nil (SwiftPM runs, runtime not fetched).
    /// Requires the guard too: the packaged app never runs the server unsupervised.
    public static var bundledHelperURL: URL? {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/llama-server")
        return FileManager.default.isExecutableFile(atPath: url.path) && bundledGuardURL != nil ? url : nil
    }
    /// `Contents/Helpers/minimodell-runtime-guard` inside the packaged app.
    public static var bundledGuardURL: URL? {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/minimodell-runtime-guard")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }
    /// `<Application Support>/<bundle id>/Models`; inside the sandbox container for the packaged app.
    public static var defaultModelsDirectory: URL {
        Brand.supportDirectory.appendingPathComponent("Models", isDirectory: true)
    }

    /// Current state followed by every change.
    public func updates() -> AsyncStream<RuntimeState> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<RuntimeState>.makeStream(bufferingPolicy: .bufferingNewest(8))
        continuation.yield(state)
        observers[id] = continuation
        continuation.onTermination = { _ in Task { await self.removeObserver(id) } }
        return stream
    }
    private func removeObserver(_ id: UUID) { observers[id] = nil }

    // MARK: Public lifecycle

    /// Returns a verified endpoint and takes a lease. Call `release()` after each inference call.
    /// `artifact`: the provider's catalog entry (`AgentConfiguration.artifact(for:)`) when `runtime.artifact` is set.
    public func acquire(provider: ProviderSpec, model: ModelSpec, artifact: ModelArtifact? = nil) async throws -> RuntimeEndpoint {
        let settings: RuntimeLaunchSettings
        do { settings = try await launchSettings(provider: provider, model: model, artifact: artifact) }
        catch {
            if current == nil, starting == nil { publish(.failed(error.localizedDescription)) }
            throw error
        }
        return try await acquire(settings)
    }

    /// Ends one lease; schedules idle unload when none remain.
    public func release() {
        leases = max(0, leases - 1)
        guard leases == 0, let current, let idle = current.settings.idleUnload else { return }
        let owner = current.generation
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: idle)
            guard !Task.isCancelled else { return }
            await self?.idleExpired(owner)
        }
    }

    /// Stops the runtime (SIGTERM, then SIGKILL after a grace period) and waits for exit.
    public func stop() async { await stopNow() }

    /// Re-checks the child after an inference failure so a crash surfaces as `.failed` immediately.
    public func refreshState() -> RuntimeState {
        if let current, !current.process.isRunning { markCrashed(current.generation, status: nil) }
        return state
    }

    /// Synchronous best-effort shutdown for `NSApplication.willTerminate`. Blocks up to ~2 seconds.
    public nonisolated func terminateForQuit() { quitHandle.terminate(grace: 2) }

    // MARK: Internals (internal for tests)

    func launchSettings(provider: ProviderSpec, model: ModelSpec, artifact: ModelArtifact? = nil) async throws -> RuntimeLaunchSettings {
        guard provider.kind == .managed, let spec = provider.runtime, model.providerID == provider.id else {
            throw AgentError.rejected("This model does not use the bundled local runtime.")
        }
        try spec.validate()
        guard let helperURL else {
            throw AgentError.rejected("This build does not include the bundled local runtime.")
        }
        let modelPath: URL
        if let artifactID = spec.artifact {
            // Verified path (ADR 0009): the catalog entry, qualified for this runtime, hash-verified on disk.
            guard let artifact, artifact.id == artifactID else {
                throw AgentError.rejected("The approved model artifact \(artifactID) is not in the model catalog.")
            }
            guard let runtimeTag, artifact.runtimeTags.contains(runtimeTag) else {
                throw AgentError.rejected("\(artifact.displayName) is not approved for the bundled runtime \(runtimeTag ?? "(unknown)").")
            }
            guard let modelStore else { throw AgentError.rejected("Model verification is unavailable.") }
            modelPath = try await modelStore.verifiedURL(for: artifact)
        } else if let modelFile = spec.modelFile {
            // Legacy unverified file name (ADR 0008).
            modelPath = modelsDirectory.appendingPathComponent(modelFile, isDirectory: false)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: modelPath.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                throw AgentError.rejected("Model file \(modelFile) is not in the Models folder.")
            }
        } else {
            throw AgentError.rejected("Managed runtime needs exactly one of artifact or modelFile.")
        }
        let idle = spec.effectiveIdleUnloadSeconds
        return RuntimeLaunchSettings(helper: helperURL, modelPath: modelPath, alias: model.model,
                                     contextTokens: model.contextTokens, parallel: spec.effectiveParallel,
                                     startupTimeout: .seconds(spec.effectiveStartupTimeoutSeconds),
                                     idleUnload: idle == 0 ? nil : .seconds(idle))
    }

    func acquire(_ settings: RuntimeLaunchSettings) async throws -> RuntimeEndpoint {
        idleTask?.cancel(); idleTask = nil
        // Policy changed since launch: never serve a request with a stale model or context size.
        if let current, current.settings != settings { await stopNow() }
        if let starting, starting.settings != settings { await stopNow() }
        if let current {
            if current.process.isRunning, state == .ready { leases += 1; return current.endpoint }
            await stopNow()
        }
        let task: Task<RuntimeEndpoint, any Error>
        if let starting { task = starting.task } else {
            task = Task { try await self.start(settings) }
            starting = (settings, task)
        }
        let endpoint = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        guard let current, current.endpoint.baseURL == endpoint.baseURL, current.process.isRunning, state == .ready else {
            throw AgentError.rejected("The local model runtime stopped during startup.")
        }
        leases += 1
        return endpoint
    }

    var leaseCount: Int { leases }

    private func start(_ settings: RuntimeLaunchSettings) async throws -> RuntimeEndpoint {
        generation += 1
        let owner = generation
        publish(.starting)
        var launched: (any RuntimeProcess)?
        do {
            let port = try host.reserveLoopbackPort()
            let key = try Self.makeKey()
            var environment = ["LLAMA_API_KEY": key]
            // Explicit environment: no inherited LLAMA_ARG_* overrides can reach the child.
            for name in ["HOME", "TMPDIR"] { environment[name] = ProcessInfo.processInfo.environment[name] }
            let serverArguments = settings.arguments(port: port)
            let process = try host.launch(executable: guardURL ?? settings.helper,
                                          arguments: guardURL == nil ? serverArguments : [settings.helper.path] + serverArguments,
                                          environment: environment)
            launched = process
            pending = process
            quitHandle.set(process)
            Task { [weak self] in
                let status = await process.exitStatus()
                await self?.markCrashed(owner, status: status)
            }
            try await waitUntilReady(process, port: port, key: key, settings: settings)
            let endpoint = RuntimeEndpoint(baseURL: URL(string: "http://127.0.0.1:\(port)/v1")!, apiKey: key)
            try Task.checkCancellation()
            pending = nil
            current = Running(settings: settings, process: process, endpoint: endpoint, generation: owner)
            starting = nil
            publish(.ready)
            return endpoint
        } catch {
            if generation == owner { generation += 1 } // ignore this child's exit notification
            if let launched { await terminate(launched) }
            pending = nil
            quitHandle.clear()
            starting = nil
            if error is CancellationError { publish(.stopped); throw error }
            let reason = (error as? AgentError)?.localizedDescription ?? "The local model runtime could not start."
            publish(.failed(reason))
            throw AgentError.rejected(reason)
        }
    }

    private func waitUntilReady(_ process: any RuntimeProcess, port: UInt16, key: String,
                                settings: RuntimeLaunchSettings) async throws {
        let deadline = ContinuousClock.now + settings.startupTimeout
        let root = URL(string: "http://127.0.0.1:\(port)")!
        while true {
            try Task.checkCancellation()
            guard process.isRunning else {
                throw AgentError.rejected("The runtime exited during startup. Check the model file and available memory.")
            }
            guard ContinuousClock.now < deadline else {
                throw AgentError.rejected("The runtime was not ready within \(settings.startupTimeout.components.seconds) seconds.")
            }
            if let (status, _) = try? await host.get(root.appendingPathComponent("health"), bearer: nil), status == 200 { break }
            try await Task.sleep(for: pollInterval)
        }
        // /health is unauthenticated, so readiness alone proves nothing about who answered. Only a server that
        // knows this launch's secret key can refuse a missing key AND a wrong random key yet accept ours.
        // (If another process held the port first, our child fails to bind and exits; checked before and after.)
        // A libproc listener-ownership check was evaluated and is denied by App Sandbox (process-info-pidfdinfo).
        func foreign(_ stage: String) -> AgentError {
            logger.error("runtime verification failed stage=\(stage, privacy: .public)")
            return AgentError.rejected("The runtime port could not be verified. Another process may be using it.")
        }
        guard process.isRunning else { throw foreign("child-exited") }
        let models = root.appendingPathComponent("v1/models")
        let decoy = try Self.makeKey()
        guard let (anonymous, _) = try? await host.get(models, bearer: nil), anonymous == 401 else { throw foreign("anonymous") }
        guard let (wrong, _) = try? await host.get(models, bearer: decoy), wrong == 401 else { throw foreign("wrong-key") }
        guard let (status, body) = try? await host.get(models, bearer: key), status == 200 else { throw foreign("key") }
        guard process.isRunning else { throw foreign("child-exited") }
        struct List: Decodable {
            struct Entry: Decodable { struct Meta: Decodable { let n_ctx: Int? }; let id: String; let meta: Meta? }
            let data: [Entry]
        }
        guard let list = try? JSONDecoder().decode(List.self, from: body),
              let entry = list.data.first(where: { $0.id == settings.alias }) else { throw foreign("alias") }
        if let context = entry.meta?.n_ctx, context < settings.contextTokens {
            throw AgentError.rejected("The runtime context is smaller than the policy requires.")
        }
    }

    private func idleExpired(_ owner: Int) async {
        guard leases == 0, current?.generation == owner else { return }
        logger.notice("runtime idle unload")
        await stopNow()
    }

    private func markCrashed(_ owner: Int, status: Int32?) {
        guard owner == generation, let current, current.generation == owner else { return }
        self.current = nil
        leases = 0
        idleTask?.cancel(); idleTask = nil
        quitHandle.clear()
        let detail = status.map { " (exit status \($0))" } ?? ""
        publish(.failed("The runtime stopped unexpectedly\(detail)."))
    }

    private func stopNow() async {
        idleTask?.cancel(); idleTask = nil
        let wasActive = current != nil || starting != nil
        generation += 1
        if wasActive { publish(.stopping) }
        if let starting {
            starting.task.cancel()
            _ = try? await starting.task.value
        }
        self.starting = nil
        if let pending { await terminate(pending); self.pending = nil }
        if let running = current {
            current = nil
            await terminate(running.process)
        }
        leases = 0
        quitHandle.clear()
        if wasActive || state != .stopped { publish(.stopped) }
    }

    private func terminate(_ process: any RuntimeProcess) async {
        guard process.isRunning else { return }
        process.terminate()
        let deadline = ContinuousClock.now + stopGrace
        while process.isRunning, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        if process.isRunning {
            process.forceKill()
            _ = await process.exitStatus()
        }
    }

    private func publish(_ new: RuntimeState) {
        state = new
        let name: String = switch new {
        case .stopped: "stopped"; case .starting: "starting"; case .ready: "ready"
        case .stopping: "stopping"; case .failed: "failed"
        }
        logger.notice("runtime state=\(name, privacy: .public)")
        for observer in observers.values { observer.yield(new) }
    }

    static func makeKey() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw AgentError.rejected("Could not create a runtime key.")
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

/// Tracks the live child so a synchronous quit handler can stop it without awaiting the actor.
private final class QuitHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var process: (any RuntimeProcess)?
    func set(_ process: any RuntimeProcess) { lock.withLock { self.process = process } }
    func clear() { lock.withLock { process = nil } }
    func terminate(grace: TimeInterval) {
        guard let process = lock.withLock({ self.process }), process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(grace)
        while process.isRunning, Date() < deadline { usleep(20_000) }
        if process.isRunning { process.forceKill() }
    }
}

/// Inference through the app-owned runtime: acquire (start/verify if needed), call, release.
public struct ManagedInferenceClient: InferenceClient {
    private let runtime: RuntimeManager
    private let provider: ProviderSpec
    private let artifact: ModelArtifact?
    /// `artifact`: `configuration.artifact(for: provider)`; required when the provider's runtime names an artifact.
    public init(runtime: RuntimeManager, provider: ProviderSpec, artifact: ModelArtifact? = nil) {
        self.runtime = runtime; self.provider = provider; self.artifact = artifact
    }
    public func complete(messages: [ChatMessage], tools: [FunctionTool], model: ModelSpec, limits: RunLimits) async throws -> ChatMessage {
        try await completeMeasured(messages: messages, tools: tools, model: model, limits: limits).message
    }
    /// Same as `complete`, plus content-free token counts and server timings when the runtime reports them.
    public func completeMeasured(messages: [ChatMessage], tools: [FunctionTool], model: ModelSpec,
                                 limits: RunLimits) async throws -> (message: ChatMessage, metrics: CompletionMetrics?) {
        let endpoint = try await runtime.acquire(provider: provider, model: model, artifact: artifact)
        do {
            let reply = try await CompatibleInferenceClient(endpoint: endpoint)
                .completeMeasured(messages: messages, tools: tools, model: model, limits: limits)
            await runtime.release()
            return reply
        } catch {
            await runtime.release()
            // A crash mid-request surfaces as the runtime failure, not a generic transport error. No cloud fallback.
            if case .failed(let reason) = await runtime.refreshState() { throw AgentError.rejected(reason) }
            throw error
        }
    }
}
