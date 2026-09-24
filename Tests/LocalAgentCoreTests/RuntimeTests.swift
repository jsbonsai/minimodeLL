import Testing
import Foundation
@testable import LocalAgentCore

/// Fake child process: never spawns anything.
final class FakeProcess: RuntimeProcess, @unchecked Sendable {
    let processIdentifier: Int32
    private let lock = NSLock()
    private var status: Int32?
    private var waiters: [CheckedContinuation<Int32, Never>] = []
    private let ignoresTerminate: Bool
    private(set) var receivedTerminate = false
    private(set) var receivedKill = false
    init(pid: Int32, ignoresTerminate: Bool = false) { processIdentifier = pid; self.ignoresTerminate = ignoresTerminate }
    var isRunning: Bool { lock.withLock { status == nil } }
    func terminate() { lock.withLock { receivedTerminate = true }; if !ignoresTerminate { exit(0) } }
    func forceKill() { lock.withLock { receivedKill = true }; exit(9) }
    func crash() { exit(139) }
    func exit(_ code: Int32) {
        let resume: [CheckedContinuation<Int32, Never>] = lock.withLock {
            guard status == nil else { return [] }
            status = code; defer { waiters = [] }; return waiters
        }
        for waiter in resume { waiter.resume(returning: code) }
    }
    func exitStatus() async -> Int32 {
        await withCheckedContinuation { continuation in
            let done: Int32? = lock.withLock {
                if let status { return status }
                waiters.append(continuation); return nil
            }
            if let done { continuation.resume(returning: done) }
        }
    }
}

/// Fake OS services. Behaves like llama-server unless configured to misbehave.
final class FakeHost: RuntimeHost, @unchecked Sendable {
    private let lock = NSLock()
    var healthyAfterPolls = 1          // Int.max: never ready
    var anonymousStatus = 401          // 200 simulates a foreign server that accepts anything
    var childOwnsListener = true
    var exitImmediately = false
    var ignoresTerminate = false
    var servedAlias = "local-model"
    private(set) var launches: [(arguments: [String], environment: [String: String], process: FakeProcess)] = []
    private var healthPolls = 0
    private var nextPort: UInt16 = 40000

    func reserveLoopbackPort() throws -> UInt16 { lock.withLock { nextPort += 1; return nextPort } }
    func launch(executable: URL, arguments: [String], environment: [String: String]) throws -> any RuntimeProcess {
        let process = lock.withLock { () -> FakeProcess in
            let process = FakeProcess(pid: Int32(1000 + launches.count), ignoresTerminate: ignoresTerminate)
            launches.append((arguments, environment, process)); healthPolls = 0
            return process
        }
        if exitImmediately { process.exit(1) }
        return process
    }
    func get(_ url: URL, bearer: String?) async throws -> (status: Int, body: Data) {
        let key = lock.withLock { launches.last?.environment["LLAMA_API_KEY"] }
        if url.path == "/health" {
            let polls = lock.withLock { healthPolls += 1; return healthPolls }
            return (polls >= healthyAfterPolls ? 200 : 503, Data())
        }
        guard url.path == "/v1/models" else { return (404, Data()) }
        if bearer == nil { return (anonymousStatus, Data()) }
        guard bearer == key else { return (401, Data()) }
        return (200, Data(#"{"data":[{"id":"\#(servedAlias)","meta":{"n_ctx":8192}}]}"#.utf8))
    }
    func isListening(pid: Int32, port: UInt16) -> Bool { childOwnsListener }
    var lastProcess: FakeProcess? { lock.withLock { launches.last?.process } }
    var launchCount: Int { lock.withLock { launches.count } }
}

func runtimeSettings(timeout: Duration = .seconds(2), idle: Duration? = nil, context: Int = 8192) -> RuntimeLaunchSettings {
    RuntimeLaunchSettings(helper: URL(fileURLWithPath: "/nonexistent/llama-server"),
                          modelPath: URL(fileURLWithPath: "/nonexistent/model.gguf"), alias: "local-model",
                          contextTokens: context, parallel: 1, startupTimeout: timeout, idleUnload: idle)
}
func makeRuntime(_ host: FakeHost) -> RuntimeManager {
    RuntimeManager(host: host, helperURL: URL(fileURLWithPath: "/nonexistent/llama-server"),
                   modelsDirectory: FileManager.default.temporaryDirectory,
                   pollInterval: .milliseconds(10), stopGrace: .milliseconds(100))
}
func eventually(_ condition: () async -> Bool) async -> Bool {
    for _ in 0..<200 { if await condition() { return true }; try? await Task.sleep(for: .milliseconds(10)) }
    return false
}

@Test func runtimeStartsOnLoopbackWithPerLaunchKeyAndIsShared() async throws {
    let host = FakeHost(); host.healthyAfterPolls = 3
    let runtime = makeRuntime(host)
    let endpoint = try await runtime.acquire(runtimeSettings())
    #expect(await runtime.state == .ready)
    #expect(endpoint.baseURL.host == "127.0.0.1")
    #expect(endpoint.baseURL.scheme == "http")
    let launch = try #require(host.launches.first)
    let key = try #require(launch.environment["LLAMA_API_KEY"])
    #expect(key.count == 64 && key == endpoint.apiKey)
    #expect(!launch.arguments.contains(key))
    #expect(!endpoint.description.contains(key))
    #expect(launch.arguments.contains("--host") && launch.arguments[launch.arguments.firstIndex(of: "--host")! + 1] == "127.0.0.1")
    #expect(launch.arguments[launch.arguments.firstIndex(of: "--port")! + 1] == String(endpoint.baseURL.port!))
    #expect(launch.arguments[launch.arguments.firstIndex(of: "--ctx-size")! + 1] == "8192")
    #expect(launch.arguments.contains("--offline") && !launch.arguments.contains("--tools"))
    #expect(Set(launch.environment.keys).isSubset(of: ["LLAMA_API_KEY", "HOME", "TMPDIR"]))
    // A second call reuses the verified process.
    _ = try await runtime.acquire(runtimeSettings())
    #expect(host.launchCount == 1)
    #expect(await runtime.leaseCount == 2)
    await runtime.stop()
}

@Test func keysDifferPerLaunch() async throws {
    let host = FakeHost(); let runtime = makeRuntime(host)
    let first = try await runtime.acquire(runtimeSettings())
    await runtime.stop()
    let second = try await runtime.acquire(runtimeSettings())
    #expect(first.apiKey != second.apiKey)
    #expect(host.launchCount == 2)
    await runtime.stop()
}

@Test func readinessTimeoutFailsAndTerminatesChild() async throws {
    let host = FakeHost(); host.healthyAfterPolls = .max
    let runtime = makeRuntime(host)
    await #expect(throws: AgentError.self) { try await runtime.acquire(runtimeSettings(timeout: .milliseconds(200))) }
    guard case .failed = await runtime.state else { Issue.record("expected failed state"); return }
    let process = try #require(host.lastProcess)
    #expect(!process.isRunning && process.receivedTerminate)
}

@Test func exitDuringStartupFails() async throws {
    let host = FakeHost(); host.exitImmediately = true
    let runtime = makeRuntime(host)
    await #expect(throws: AgentError.self) { try await runtime.acquire(runtimeSettings()) }
    guard case .failed(let reason) = await runtime.state else { Issue.record("expected failed state"); return }
    #expect(reason.contains("exited during startup"))
}

@Test func crashWhileReadyBecomesFailedWithoutAutomaticRestart() async throws {
    let host = FakeHost(); let runtime = makeRuntime(host)
    _ = try await runtime.acquire(runtimeSettings())
    host.lastProcess?.crash()
    #expect(await eventually { if case .failed = await runtime.state { true } else { false } })
    guard case .failed(let reason) = await runtime.state else { return }
    #expect(reason.contains("unexpectedly"))
    #expect(host.launchCount == 1) // no background restart
    // The next user-initiated request launches a fresh process.
    _ = try await runtime.acquire(runtimeSettings())
    #expect(host.launchCount == 2)
    #expect(await runtime.state == .ready)
    await runtime.stop()
}

@Test func crashMidRequestSurfacesRuntimeFailure() async throws {
    let host = FakeHost(); let runtime = makeRuntime(host)
    _ = try await runtime.acquire(runtimeSettings())
    host.lastProcess?.crash()
    // refreshState observes the dead child even before the exit notification is processed.
    guard case .failed = await runtime.refreshState() else { Issue.record("expected failed state"); return }
}

@Test func foreignServerThatAcceptsAnyRequestIsRejected() async throws {
    let host = FakeHost(); host.anonymousStatus = 200
    let runtime = makeRuntime(host)
    await #expect(throws: AgentError.self) { try await runtime.acquire(runtimeSettings()) }
    guard case .failed(let reason) = await runtime.state else { Issue.record("expected failed state"); return }
    #expect(reason.contains("could not be verified"))
    #expect(host.lastProcess?.isRunning == false)
}

@Test func listenerNotOwnedByChildIsRejected() async throws {
    let host = FakeHost(); host.childOwnsListener = false
    let runtime = makeRuntime(host)
    await #expect(throws: AgentError.self) { try await runtime.acquire(runtimeSettings()) }
    #expect(host.lastProcess?.isRunning == false)
}

@Test func wrongModelAliasIsRejected() async throws {
    let host = FakeHost(); host.servedAlias = "something-else"
    let runtime = makeRuntime(host)
    await #expect(throws: AgentError.self) { try await runtime.acquire(runtimeSettings()) }
}

@Test func idleUnloadStopsOnlyWithoutLeases() async throws {
    let host = FakeHost(); let runtime = makeRuntime(host)
    _ = try await runtime.acquire(runtimeSettings(idle: .milliseconds(80)))
    try await Task.sleep(for: .milliseconds(250))
    #expect(await runtime.state == .ready) // lease held: never unloaded mid-request
    await runtime.release()
    #expect(await eventually { await runtime.state == .stopped })
    #expect(host.lastProcess?.isRunning == false)
    #expect(host.lastProcess?.receivedTerminate == true)
}

@Test func stopCleansUpAndEscalatesToKill() async throws {
    let host = FakeHost(); host.ignoresTerminate = true
    let runtime = makeRuntime(host)
    _ = try await runtime.acquire(runtimeSettings())
    await runtime.stop()
    let process = try #require(host.lastProcess)
    #expect(await runtime.state == .stopped)
    #expect(process.receivedTerminate && process.receivedKill && !process.isRunning)
    #expect(await runtime.leaseCount == 0)
}

@Test func quitHandlerTerminatesSynchronously() async throws {
    let host = FakeHost(); let runtime = makeRuntime(host)
    _ = try await runtime.acquire(runtimeSettings())
    runtime.terminateForQuit()
    #expect(host.lastProcess?.isRunning == false)
}

@Test func changedPolicyRestartsRuntime() async throws {
    let host = FakeHost(); let runtime = makeRuntime(host)
    _ = try await runtime.acquire(runtimeSettings(context: 4096))
    await runtime.release()
    _ = try await runtime.acquire(runtimeSettings(context: 8192))
    #expect(host.launchCount == 2)
    #expect(host.launches[0].process.isRunning == false)
    await runtime.stop()
}

@Test func cancellingStartupStopsChild() async throws {
    let host = FakeHost(); host.healthyAfterPolls = .max
    let runtime = makeRuntime(host)
    let task = Task { try await runtime.acquire(runtimeSettings(timeout: .seconds(30))) }
    #expect(await eventually { host.launchCount == 1 })
    task.cancel()
    await #expect(throws: (any Error).self) { try await task.value }
    #expect(await eventually { await runtime.state == .stopped })
    #expect(host.lastProcess?.isRunning == false)
}

// MARK: Managed provider policy

func managedConfig(_ provider: [String: Any], models: [[String: Any]]? = nil) throws -> AgentConfiguration {
    try config { json in
        json["providers"] = [provider]
        json["models"] = models ?? [["id": "bundled", "title": "Bundled", "providerID": "bundled", "model": "local-model",
                                     "minimumMemoryGB": 0, "contextTokens": 8192]]
    }
}
@Test func managedProviderValidation() throws {
    let valid: [String: Any] = ["id": "bundled", "kind": "managed", "runtime": ["modelFile": "SmolLM2-135M-Instruct-Q8_0.gguf"]]
    let configuration = try managedConfig(valid)
    #expect(configuration.providers[0].runtime?.effectiveIdleUnloadSeconds == 900)
    // A managed provider has no URL or credential: the app picks the port and key per launch.
    #expect(throws: (any Error).self) { try managedConfig(valid.merging(["baseURL": "http://127.0.0.1:9931/v1"]) { $1 }) }
    #expect(throws: (any Error).self) { try managedConfig(valid.merging(["credentialAccount": "x"]) { $1 }) }
    #expect(throws: (any Error).self) { try managedConfig(["id": "bundled", "kind": "managed"]) }
    for bad in ["../secret.gguf", "/etc/model.gguf", "model.bin", ".hidden.gguf", "a/b.gguf"] {
        #expect(throws: (any Error).self) { try managedConfig(["id": "bundled", "kind": "managed", "runtime": ["modelFile": bad]]) }
    }
    for runtime in [["modelFile": "m.gguf", "parallel": 9], ["modelFile": "m.gguf", "startupTimeoutSeconds": 1],
                    ["modelFile": "m.gguf", "idleUnloadSeconds": 5]] as [[String: Any]] {
        #expect(throws: (any Error).self) { try managedConfig(["id": "bundled", "kind": "managed", "runtime": runtime]) }
    }
    #expect(throws: (any Error).self) {
        let model: [String: Any] = ["title": "B", "providerID": "bundled", "model": "local-model", "minimumMemoryGB": 0, "contextTokens": 8192]
        try managedConfig(valid, models: [model.merging(["id": "one"]) { $1 }, model.merging(["id": "two"]) { $1 }])
    }
    // External providers still require a URL and reject a runtime block.
    #expect(throws: (any Error).self) { try config { $0["providers"] = [["id": "local", "kind": "local"]] } }
    #expect(throws: (any Error).self) {
        try config { $0["providers"] = [["id": "local", "kind": "local", "baseURL": "http://127.0.0.1:9931/v1", "runtime": ["modelFile": "m.gguf"]]] }
    }
}
@Test func existingConfigurationsStillDecode() throws {
    for name in ["local.example.json", "enterprise.example.json"] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Config/\(name)")
        _ = try ConfigurationLoader.decode(Data(contentsOf: url))
    }
    _ = try ConfigurationLoader.decode(Data(AgentConfiguration.starterJSON.utf8))
}
@Test func launchSettingsRequireBundledHelperAndInstalledModel() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let configuration = try managedConfig(["id": "bundled", "kind": "managed", "runtime": ["modelFile": "tiny.gguf", "parallel": 2]])
    let provider = configuration.providers[0], model = configuration.models[0]
    let noHelper = RuntimeManager(host: FakeHost(), helperURL: nil, modelsDirectory: directory)
    await #expect(throws: AgentError.self) { try await noHelper.acquire(provider: provider, model: model) }
    guard case .failed = await noHelper.state else { Issue.record("expected failed state"); return }
    let runtime = RuntimeManager(host: FakeHost(), helperURL: URL(fileURLWithPath: "/bin/true"), modelsDirectory: directory)
    await #expect(throws: AgentError.self) { try await runtime.launchSettings(provider: provider, model: model) }
    try Data("GGUF".utf8).write(to: directory.appendingPathComponent("tiny.gguf"))
    let settings = try await runtime.launchSettings(provider: provider, model: model)
    #expect(settings.parallel == 2 && settings.contextTokens == 8192)
    #expect(settings.arguments(port: 1234).contains("16384")) // each slot gets the policy context
    #expect(settings.idleUnload == .seconds(900))
}
@Test func systemHostReservesLoopbackPortAndSeesOwnListener() throws {
    let host = SystemRuntimeHost()
    let port = try host.reserveLoopbackPort()
    #expect(port > 0)
    // Not listening on the just-released port.
    #expect(!host.isListening(pid: getpid(), port: port))
    // Listen on it ourselves: the socket-ownership check must see it for this pid only.
    let fd = socket(AF_INET, SOCK_STREAM, 0); defer { close(fd) }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = inet_addr("127.0.0.1"); address.sin_port = port.bigEndian
    let bound = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
    }
    try #require(bound == 0 && listen(fd, 1) == 0)
    #expect(host.isListening(pid: getpid(), port: port))
    #expect(!host.isListening(pid: 1, port: port))
}
