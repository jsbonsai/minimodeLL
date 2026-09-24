import Testing
import Foundation
import CryptoKit
@testable import LocalAgentCore

/// Fake HTTPS transport: serves `content` from the requested offset. Never touches the network.
final class FakeTransport: ArtifactTransport, @unchecked Sendable {
    enum Mode { case serve, failAfter(Int), hangAfter(Int) }
    private let lock = NSLock()
    let content: Data
    var mode: Mode
    private(set) var offsets: [Int64] = []
    init(_ content: Data, mode: Mode = .serve) { self.content = content; self.mode = mode }
    var callCount: Int { lock.withLock { offsets.count } }
    func download(_ url: URL, to destination: URL, offset: Int64, limit: Int64,
                  isApprovedHost: @escaping @Sendable (String) -> Bool,
                  progress: @escaping @Sendable (Int64) -> Void) async throws {
        let mode = lock.withLock { offsets.append(offset); return self.mode }
        guard let host = url.host, isApprovedHost(host) else { throw AgentError.rejected("unapproved host") }
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }
        try handle.seekToEnd()
        var body = content.count > Int(offset) ? content.subdata(in: Int(offset)..<content.count) : Data()
        switch mode {
        case .serve: break
        case .failAfter(let bytes), .hangAfter(let bytes): body = body.prefix(bytes)
        }
        guard offset + Int64(body.count) <= limit else { throw AgentError.rejected("The download exceeded the approved size.") }
        try handle.write(contentsOf: body)
        progress(offset + Int64(body.count))
        switch mode {
        case .serve: return
        case .failAfter: throw ArtifactTransportError.interrupted
        case .hangAfter: while true { try await Task.sleep(for: .milliseconds(10)) }
        }
    }
}

func syntheticBytes(_ count: Int = 256 * 1024, seed: UInt8 = 7) -> Data {
    Data((0..<count).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ Int(seed)) })
}
func sha256Hex(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
func artifact(for data: Data, id: String = "synthetic-q4", sha: String? = nil, size: Int64? = nil,
              host: String = "huggingface.co", runtimeTags: [String] = ["b11140"]) -> ModelArtifact {
    ModelArtifact(id: id, displayName: "Synthetic", sourceURL: URL(string: "https://\(host)/org/repo/resolve/abc/\(id).gguf")!,
                  fileName: "\(id).gguf", sizeBytes: size ?? Int64(data.count), sha256: sha ?? sha256Hex(data),
                  quantization: "Q4_K_M", license: "Apache-2.0", chatTemplate: "synthetic", runtimeTags: runtimeTags,
                  minimumMemoryGB: 1, contextTokens: 8192)
}
func catalog(_ artifacts: [ModelArtifact], hosts: [String] = ["huggingface.co", "hf.co"], allowDownloads: Bool = true) -> ModelCatalog {
    ModelCatalog(schemaVersion: 1, catalogVersion: "test", approvedHosts: hosts, allowDownloads: allowDownloads, artifacts: artifacts)
}
func tempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("models-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
func store(_ directory: URL, _ transport: FakeTransport, capacity: Int64 = Int64(1) << 40) -> ModelStore {
    ModelStore(directory: directory, transport: transport, availableCapacity: { _ in capacity })
}

// MARK: Catalog and policy

@Test func builtInCatalogIsValidAndPinned() throws {
    let builtIn = ModelCatalog.builtIn
    try builtIn.validate()
    let qwen = try #require(builtIn.artifact(id: "qwen3-4b-instruct-2507-q4_k_m"))
    #expect(qwen.sizeBytes == 2_497_280_736)
    #expect(qwen.sha256 == "2fde00ce69dd4899c70d020845e2638353015bba0fdf161b3eb965f2bca4464e")
    #expect(qwen.license == "Apache-2.0" && qwen.runtimeTags == ["b11140"])
    // Pinned to an immutable revision, not a moving branch.
    #expect(!qwen.sourceURL.path.contains("/resolve/main/"))
    // Built-in catalog and the pinned runtime lock must agree.
    let lockURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../packaging/runtime.lock.json")
    let lock = try JSONSerialization.jsonObject(with: Data(contentsOf: lockURL)) as! [String: Any]
    #expect(qwen.runtimeTags.contains(lock["tag"] as! String))
}

@Test func catalogValidationFailsClosed() throws {
    let data = syntheticBytes()
    let good = artifact(for: data)
    try catalog([good]).validate()
    var bad: [ModelCatalog] = [
        catalog([artifact(for: data, host: "evil.example")]),                      // unapproved host
        catalog([artifact(for: data, sha: "ABC")]),                                // malformed hash
        catalog([artifact(for: data, sha: String(repeating: "A", count: 64))]),    // uppercase hash
        catalog([artifact(for: data, size: 0)]),
        catalog([artifact(for: data, runtimeTags: [])]),
        catalog([good, good]),                                                     // duplicate IDs
        catalog([good], hosts: ["*.hf.co"]),                                       // wildcards are not hosts
        catalog([good], hosts: [])
    ]
    let http = ModelArtifact(id: "x", displayName: "X", sourceURL: URL(string: "http://huggingface.co/x.gguf")!, fileName: "x.gguf",
                             sizeBytes: 1, sha256: sha256Hex(data), quantization: "Q4", license: "MIT", chatTemplate: "t",
                             runtimeTags: ["b1"], minimumMemoryGB: 1, contextTokens: 4096)
    let query = ModelArtifact(id: "y", displayName: "Y", sourceURL: URL(string: "https://huggingface.co/y.gguf?token=1")!, fileName: "y.gguf",
                              sizeBytes: 1, sha256: sha256Hex(data), quantization: "Q4", license: "MIT", chatTemplate: "t",
                              runtimeTags: ["b1"], minimumMemoryGB: 1, contextTokens: 4096)
    let path = ModelArtifact(id: "z", displayName: "Z", sourceURL: URL(string: "https://huggingface.co/z.gguf")!, fileName: "../z.gguf",
                             sizeBytes: 1, sha256: sha256Hex(data), quantization: "Q4", license: "MIT", chatTemplate: "t",
                             runtimeTags: ["b1"], minimumMemoryGB: 1, contextTokens: 4096)
    bad += [catalog([http]), catalog([query]), catalog([path])]
    for entry in bad { #expect(throws: AgentError.self) { try entry.validate() } }
    // Subdomains of an approved host are approved (HF redirects to its CDN); look-alikes are not.
    #expect(ModelCatalog.isApproved(host: "us.aws.cdn.hf.co", approvedHosts: ["hf.co"]))
    #expect(!ModelCatalog.isApproved(host: "evilhf.co", approvedHosts: ["hf.co"]))
}

func artifactPolicy(runtime: [String: Any], modelCatalog: [String: Any]? = nil, context: Int = 8192, memory: Int = 16) throws -> AgentConfiguration {
    try config { json in
        json["providers"] = [["id": "bundled", "kind": "managed", "runtime": runtime]]
        json["models"] = [["id": "bundled", "title": "Bundled", "providerID": "bundled", "model": "local-model",
                           "minimumMemoryGB": memory, "contextTokens": context]]
        if let modelCatalog { json["modelCatalog"] = modelCatalog }
    }
}
func artifactJSON(_ artifact: ModelArtifact) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: JSONEncoder().encode(artifact)) as! [String: Any]
}

@Test func managedArtifactPolicyIsValidatedAgainstCatalog() throws {
    // Built-in catalog entry: accepted and resolvable.
    let valid = try artifactPolicy(runtime: ["artifact": "qwen3-4b-instruct-2507-q4_k_m"])
    #expect(valid.artifact(for: valid.providers[0])?.sha256 == ModelCatalog.builtIn.artifacts[0].sha256)
    // Unknown artifact, both artifact and modelFile, or neither: fail closed.
    #expect(throws: AgentError.self) { try artifactPolicy(runtime: ["artifact": "not-approved"]) }
    #expect(throws: AgentError.self) { try artifactPolicy(runtime: ["artifact": "qwen3-4b-instruct-2507-q4_k_m", "modelFile": "m.gguf"]) }
    #expect(throws: AgentError.self) { try artifactPolicy(runtime: ["parallel": 1]) }
    // A stub cannot exceed the approved context or understate the artifact's memory requirement.
    #expect(throws: AgentError.self) { try artifactPolicy(runtime: ["artifact": "qwen3-4b-instruct-2507-q4_k_m"], context: 16384) }
    #expect(throws: AgentError.self) { try artifactPolicy(runtime: ["artifact": "qwen3-4b-instruct-2507-q4_k_m"], memory: 8) }
}

@Test func policyCatalogReplacesBuiltInAndCannotBeExtended() throws {
    let own = artifact(for: syntheticBytes(), id: "org-approved")
    let catalogJSON: [String: Any] = ["approvedHosts": ["huggingface.co"], "allowDownloads": false, "artifacts": [try artifactJSON(own)]]
    let policy = try artifactPolicy(runtime: ["artifact": "org-approved"], modelCatalog: catalogJSON, memory: 1)
    let effective = policy.effectiveCatalog
    #expect(effective.artifacts.map(\.id) == ["org-approved"])
    #expect(effective.allowDownloads == false && effective.catalogVersion == "policy")
    // Once a policy supplies its catalog, built-in artifacts are no longer approved by it.
    #expect(throws: AgentError.self) {
        try artifactPolicy(runtime: ["artifact": "qwen3-4b-instruct-2507-q4_k_m"], modelCatalog: catalogJSON)
    }
    // An invalid policy catalog fails closed rather than falling back to the built-in one.
    var broken = try artifactJSON(own); broken["sha256"] = "not-a-hash"
    #expect(throws: (any Error).self) {
        try artifactPolicy(runtime: ["artifact": "org-approved"], modelCatalog: ["artifacts": [broken]], memory: 1)
    }
    // Forced managed policy is a complete replacement (ConfigurationLoader): a user config.json cannot add artifacts
    // because it is never read while PolicyJSON is forced. Validation of the forced JSON is what decides.
    let managed = try ConfigurationLoader.decode(JSONEncoder().encode(policy))
    #expect(managed.effectiveCatalog.artifacts.map(\.id) == ["org-approved"])
}

@Test func legacyModelFileConfigurationsStillDecode() throws {
    let legacy = try artifactPolicy(runtime: ["modelFile": "SmolLM2-135M-Instruct-Q8_0.gguf"], memory: 0)
    #expect(legacy.providers[0].runtime?.modelFile == "SmolLM2-135M-Instruct-Q8_0.gguf")
    #expect(legacy.artifact(for: legacy.providers[0]) == nil)
    #expect(legacy.effectiveCatalog == ModelCatalog.builtIn)
}

// MARK: Store

@Test func downloadVerifiesBeforeAtomicPromotion() async throws {
    let directory = try tempDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let data = syntheticBytes(), item = artifact(for: data)
    let transport = FakeTransport(data)
    let models = store(directory, transport)
    try await models.download(item, catalog: catalog([item]))
    #expect(await models.status(of: item) == .ready)
    #expect(try Data(contentsOf: directory.appendingPathComponent(item.fileName)) == data)
    #expect(!FileManager.default.fileExists(atPath: await models.partialURL(item).path))
    #expect(try await models.verifiedURL(for: item) == directory.appendingPathComponent(item.fileName))
    // Already verified: no second transfer.
    try await models.download(item, catalog: catalog([item]))
    #expect(transport.callCount == 1)
}

@Test func hashMismatchIsRejectedAndNeverPromoted() async throws {
    let directory = try tempDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let expected = syntheticBytes(), served = syntheticBytes(seed: 9) // same size, different bytes
    let item = artifact(for: expected)
    let models = store(directory, FakeTransport(served))
    await #expect(throws: AgentError.self) { try await models.download(item, catalog: catalog([item])) }
    guard case .failed(let reason) = await models.status(of: item) else { Issue.record("expected failed"); return }
    #expect(reason.contains("SHA-256"))
    #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(item.fileName).path))
    #expect(!FileManager.default.fileExists(atPath: await models.partialURL(item).path)) // not resumable garbage
    await #expect(throws: AgentError.self) { try await models.verifiedURL(for: item) }
}

@Test func sizeMismatchIsRejected() async throws {
    let directory = try tempDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let data = syntheticBytes()
    let item = artifact(for: data, size: Int64(data.count) + 10) // server delivers fewer bytes than approved
    let models = store(directory, FakeTransport(data))
    await #expect(throws: AgentError.self) { try await models.download(item, catalog: catalog([item])) }
    guard case .failed(let reason) = await models.status(of: item) else { Issue.record("expected failed"); return }
    #expect(reason.contains("size"))
    #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(item.fileName).path))
    // A server offering more than the approved size is cut off by the transport limit.
    let small = artifact(for: data, id: "small", size: 1024)
    await #expect(throws: AgentError.self) { try await models.download(small, catalog: catalog([small])) }
    #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(small.fileName).path))
}

@Test func cancellationRemovesPartialFile() async throws {
    let directory = try tempDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let data = syntheticBytes(), item = artifact(for: data)
    let models = store(directory, FakeTransport(data, mode: .hangAfter(4096)))
    let task = Task { try await models.download(item, catalog: catalog([item])) }
    let partial = await models.partialURL(item)
    #expect(await eventually { ModelStore.size(of: partial) == 4096 })
    guard case .downloading = await models.status(of: item) else { Issue.record("expected downloading"); return }
    await models.cancel(item.id)
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(!FileManager.default.fileExists(atPath: partial.path))
    #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(item.fileName).path))
    #expect(await models.status(of: item) == .notInstalled)
}

@Test func interruptedDownloadKeepsPartialAndResumes() async throws {
    let directory = try tempDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let data = syntheticBytes(), item = artifact(for: data)
    let transport = FakeTransport(data, mode: .failAfter(100_000))
    let models = store(directory, transport)
    await #expect(throws: AgentError.self) { try await models.download(item, catalog: catalog([item])) }
    #expect(ModelStore.size(of: await models.partialURL(item)) == 100_000)
    transport.mode = .serve
    try await models.download(item, catalog: catalog([item]))
    #expect(transport.offsets == [0, 100_000])
    #expect(await models.status(of: item) == .ready)
}

@Test func completePartialIsVerifiedWithoutNetwork() async throws {
    let directory = try tempDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let data = syntheticBytes(), item = artifact(for: data)
    let transport = FakeTransport(data)
    let models = store(directory, transport)
    let partial = await models.partialURL(item)
    try FileManager.default.createDirectory(at: partial.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: partial)
    try await models.download(item, catalog: catalog([item]))
    #expect(transport.callCount == 0)
    #expect(await models.status(of: item) == .ready)
}

@Test func insufficientDiskSpaceRefusesBeforeTransfer() async throws {
    let directory = try tempDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let data = syntheticBytes(), item = artifact(for: data)
    let transport = FakeTransport(data)
    let models = store(directory, transport, capacity: ModelStore.diskMargin) // margin only, no room for the file
    await #expect(throws: AgentError.self) { try await models.download(item, catalog: catalog([item])) }
    guard case .failed(let reason) = await models.status(of: item) else { Issue.record("expected failed"); return }
    #expect(reason.contains("disk space"))
    #expect(transport.callCount == 0)
}

@Test func downloadsRequireApprovedCatalogAndHosts() async throws {
    let directory = try tempDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let data = syntheticBytes(), item = artifact(for: data)
    let transport = FakeTransport(data)
    let models = store(directory, transport)
    // Not in the catalog it is checked against.
    await #expect(throws: AgentError.self) { try await models.download(item, catalog: catalog([])) }
    // Policy disabled downloads.
    await #expect(throws: AgentError.self) { try await models.download(item, catalog: catalog([item], allowDownloads: false)) }
    // Host no longer approved.
    await #expect(throws: AgentError.self) { try await models.download(item, catalog: catalog([item], hosts: ["example.org"])) }
    #expect(transport.callCount == 0)
}

@Test func importVerifiesAgainstManifest() async throws {
    let directory = try tempDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let source = try tempDirectory(); defer { try? FileManager.default.removeItem(at: source) }
    let data = syntheticBytes(), item = artifact(for: data)
    let models = store(directory, FakeTransport(Data()))
    // Same size, wrong bytes: rejected, nothing promoted.
    let wrong = source.appendingPathComponent("wrong.gguf"); try syntheticBytes(seed: 3).write(to: wrong)
    await #expect(throws: AgentError.self) { try await models.importFile(wrong, as: item, catalog: catalog([item])) }
    #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(item.fileName).path))
    // Wrong size: rejected before copying.
    let short = source.appendingPathComponent("short.gguf"); try data.prefix(10).write(to: short)
    await #expect(throws: AgentError.self) { try await models.importFile(short, as: item, catalog: catalog([item])) }
    // Matching file: copied, verified, promoted; the source is untouched.
    let good = source.appendingPathComponent("any-name.gguf"); try data.write(to: good)
    try await models.importFile(good, as: item, catalog: catalog([item]))
    #expect(await models.status(of: item) == .ready)
    #expect(FileManager.default.fileExists(atPath: good.path))
    #expect(try Data(contentsOf: directory.appendingPathComponent(item.fileName)) == data)
}

@Test func tamperedFileIsReverifiedAndRefused() async throws {
    let directory = try tempDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let data = syntheticBytes(), item = artifact(for: data)
    let models = store(directory, FakeTransport(data))
    try await models.download(item, catalog: catalog([item]))
    let file = directory.appendingPathComponent(item.fileName)
    // Change content (same size) after verification; the record no longer matches the file's modification time.
    let handle = try FileHandle(forWritingTo: file); try handle.seek(toOffset: 10); try handle.write(contentsOf: Data([0xFF])); try handle.close()
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: file.path)
    await models.refresh([item])
    #expect(await models.status(of: item) == .unverified)
    await #expect(throws: AgentError.self) { try await models.verifiedURL(for: item) }
    guard case .failed = await models.status(of: item) else { Issue.record("expected failed"); return }
    // An unverified file dropped into the folder by hand is also hashed before use.
    await models.delete(item)
    try data.write(to: file)
    await models.refresh([item])
    #expect(await models.status(of: item) == .unverified)
    #expect(try await models.verifiedURL(for: item) == file)
    #expect(await models.status(of: item) == .ready)
}

@Test func deleteRemovesFileRecordAndPartial() async throws {
    let directory = try tempDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let data = syntheticBytes(), item = artifact(for: data)
    let models = store(directory, FakeTransport(data))
    try await models.download(item, catalog: catalog([item]))
    await models.delete(item)
    #expect(await models.status(of: item) == .notInstalled)
    for url in [directory.appendingPathComponent(item.fileName), await models.recordURL(item), await models.partialURL(item)] {
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}

// MARK: Runtime integration

func artifactRuntime(_ host: FakeHost, store: ModelStore, tag: String? = "b11140") -> RuntimeManager {
    RuntimeManager(host: host, helperURL: URL(fileURLWithPath: "/nonexistent/llama-server"), guardURL: nil,
                   modelsDirectory: FileManager.default.temporaryDirectory, modelStore: store, runtimeTag: tag,
                   pollInterval: .milliseconds(10), stopGrace: .milliseconds(100))
}

@Test func runtimeLaunchesOnlyVerifiedArtifacts() async throws {
    let directory = try tempDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let data = syntheticBytes(), item = artifact(for: data)
    let models = store(directory, FakeTransport(data))
    let provider = ProviderSpec(id: "bundled", kind: .managed, baseURL: nil, runtime: ManagedRuntimeSpec(artifact: item.id))
    let model = try artifactPolicy(runtime: ["artifact": "qwen3-4b-instruct-2507-q4_k_m"]).models[0]
    let host = FakeHost()
    let runtime = artifactRuntime(host, store: models)
    // Not downloaded: refused, nothing launched.
    await #expect(throws: AgentError.self) { try await runtime.acquire(provider: provider, model: model, artifact: item) }
    #expect(host.launchCount == 0)
    // Corrupt file under the approved name: refused after hashing, nothing launched.
    try syntheticBytes(seed: 1).write(to: directory.appendingPathComponent(item.fileName))
    await #expect(throws: AgentError.self) { try await runtime.acquire(provider: provider, model: model, artifact: item) }
    #expect(host.launchCount == 0)
    // Artifact missing from the resolved catalog: refused.
    await #expect(throws: AgentError.self) { try await runtime.acquire(provider: provider, model: model, artifact: nil) }
    // Verified: launched with the promoted path and the Jinja template engine.
    await models.delete(item)
    try await models.download(item, catalog: catalog([item]))
    _ = try await runtime.acquire(provider: provider, model: model, artifact: item)
    let launch = try #require(host.launches.first)
    #expect(launch.arguments[launch.arguments.firstIndex(of: "--model")! + 1] == directory.appendingPathComponent(item.fileName).path)
    #expect(launch.arguments.contains("--jinja"))
    await runtime.stop()
}

@Test func runtimeRefusesArtifactNotQualifiedForBundledTag() async throws {
    let directory = try tempDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let data = syntheticBytes(), item = artifact(for: data, runtimeTags: ["b9999"])
    let models = store(directory, FakeTransport(data))
    try await models.download(item, catalog: catalog([item]))
    let provider = ProviderSpec(id: "bundled", kind: .managed, baseURL: nil, runtime: ManagedRuntimeSpec(artifact: item.id))
    let model = try artifactPolicy(runtime: ["artifact": "qwen3-4b-instruct-2507-q4_k_m"]).models[0]
    let host = FakeHost()
    await #expect(throws: AgentError.self) {
        try await artifactRuntime(host, store: models).acquire(provider: provider, model: model, artifact: item)
    }
    await #expect(throws: AgentError.self) {
        try await artifactRuntime(host, store: models, tag: nil).acquire(provider: provider, model: model, artifact: item)
    }
    #expect(host.launchCount == 0)
}
