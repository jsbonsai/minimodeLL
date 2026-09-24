import Foundation
import CryptoKit
import OSLog

/// Install state of one catalog artifact. Content-free.
public enum ArtifactStatus: Sendable, Equatable {
    case notInstalled
    /// A file with the artifact's name exists but has not been verified since it changed.
    case unverified
    case downloading(received: Int64, total: Int64)
    case verifying
    case ready
    case failed(String)

    public var summary: String {
        switch self {
        case .notInstalled: "Not downloaded"
        case .unverified: "Not verified yet"
        case .downloading(let received, let total):
            "Downloading \(total > 0 ? Int(Double(received) / Double(total) * 100) : 0)%"
        case .verifying: "Verifying…"
        case .ready: "Ready"
        case .failed(let reason): "Failed: \(reason)"
        }
    }
    public var isBusy: Bool {
        switch self { case .downloading, .verifying: true; default: false }
    }
}

/// A transport failure after which the partial file is still a valid prefix and can be resumed.
public enum ArtifactTransportError: Error, Sendable { case interrupted }

/// Streams an HTTPS download into a file. Test seam; the real implementation is `URLSessionArtifactTransport`.
public protocol ArtifactTransport: Sendable {
    /// Appends the body of `url` to `destination`, requesting bytes from `offset` (the destination's current size).
    /// If the server ignores the range, the implementation truncates `destination` and starts over.
    /// Must refuse redirects to hosts for which `isApprovedHost` is false, and stop once more than `limit` bytes
    /// would be on disk. `progress` receives the destination's total size.
    func download(_ url: URL, to destination: URL, offset: Int64, limit: Int64,
                  isApprovedHost: @escaping @Sendable (String) -> Bool,
                  progress: @escaping @Sendable (Int64) -> Void) async throws
}

/// Verified model files in the app's `Models` folder (ADR 0009).
///
/// Layout: `Models/<fileName>` (promoted, verified), `Models/.partial/<id>.part` (in-progress download/import),
/// `Models/.verified/<id>.json` (verification record bound to the file's size, inode and modification time).
/// Size and SHA-256 are checked on the partial file BEFORE it is atomically renamed into place, so an unverified
/// or corrupt file is never promoted. A promoted file whose record no longer matches is re-hashed before use.
public actor ModelStore {
    public typealias CapacityProbe = @Sendable (URL) throws -> Int64
    /// Free space to keep after an artifact is written.
    public static let diskMargin: Int64 = 512 << 20

    public let directory: URL
    private let transport: any ArtifactTransport
    private let availableCapacity: CapacityProbe
    private let logger = Logger(subsystem: Brand.identity, category: "models")
    public private(set) var statuses: [String: ArtifactStatus] = [:]
    private var active: [String: Task<Void, any Error>] = [:]
    private var userCancelled: Set<String> = []
    private var observers: [UUID: AsyncStream<[String: ArtifactStatus]>.Continuation] = [:]

    public init(directory: URL = RuntimeManager.defaultModelsDirectory,
                transport: any ArtifactTransport = URLSessionArtifactTransport(),
                availableCapacity: @escaping CapacityProbe = ModelStore.volumeAvailableCapacity) {
        self.directory = directory; self.transport = transport; self.availableCapacity = availableCapacity
    }

    public static let volumeAvailableCapacity: CapacityProbe = { url in
        var probe = url
        while !FileManager.default.fileExists(atPath: probe.path), probe.pathComponents.count > 1 { probe.deleteLastPathComponent() }
        let values = try probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let capacity = values.volumeAvailableCapacityForImportantUsage else {
            throw AgentError.rejected("Could not determine free disk space.")
        }
        return capacity
    }

    /// Current statuses followed by every change.
    public func updates() -> AsyncStream<[String: ArtifactStatus]> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<[String: ArtifactStatus]>.makeStream(bufferingPolicy: .bufferingNewest(4))
        continuation.yield(statuses)
        observers[id] = continuation
        continuation.onTermination = { _ in Task { await self.removeObserver(id) } }
        return stream
    }
    private func removeObserver(_ id: UUID) { observers[id] = nil }

    public func status(of artifact: ModelArtifact) -> ArtifactStatus { statuses[artifact.id] ?? .notInstalled }

    /// Recomputes idle statuses from disk (cheap: attributes only, no hashing). Busy artifacts are left alone.
    public func refresh(_ artifacts: [ModelArtifact]) {
        for artifact in artifacts where !(statuses[artifact.id]?.isBusy ?? false) {
            if case .failed = statuses[artifact.id], !FileManager.default.fileExists(atPath: fileURL(artifact).path) { continue }
            set(artifact.id, diskStatus(artifact))
        }
    }

    // MARK: Paths

    func fileURL(_ artifact: ModelArtifact) -> URL { directory.appendingPathComponent(artifact.fileName, isDirectory: false) }
    func partialURL(_ artifact: ModelArtifact) -> URL {
        directory.appendingPathComponent(".partial", isDirectory: true).appendingPathComponent(artifact.id + ".part")
    }
    func recordURL(_ artifact: ModelArtifact) -> URL {
        directory.appendingPathComponent(".verified", isDirectory: true).appendingPathComponent(artifact.id + ".json")
    }

    // MARK: Download

    /// Downloads, verifies and promotes `artifact`. Resumes a partial file left by an interrupted download.
    /// Throws `CancellationError` after `cancel(_:)`; the partial file is then removed.
    public func download(_ artifact: ModelArtifact, catalog: ModelCatalog) async throws {
        guard catalog.allowDownloads else { throw AgentError.rejected("Your configuration does not allow model downloads. Import a verified file instead.") }
        guard catalog.artifact(id: artifact.id) == artifact else { throw AgentError.rejected("This model is not in the approved catalog.") }
        try ModelArtifact.validateSource(artifact.sourceURL, approvedHosts: catalog.approvedHosts)
        if diskStatus(artifact) == .ready { set(artifact.id, .ready); return }
        let hosts = catalog.approvedHosts
        try await run(artifact) { store in
            let partial = store.partialURL(artifact)
            try store.prepareDirectories()
            var offset = Self.size(of: partial) ?? 0
            if offset > artifact.sizeBytes { try? FileManager.default.removeItem(at: partial); offset = 0 }
            // A previous attempt wrote every byte but stopped before verification: verify locally instead of
            // requesting an empty range, which some servers answer with the full multi-GB body.
            if offset == artifact.sizeBytes { try await store.verifyAndPromote(partial, as: artifact); return }
            if offset == 0 { guard FileManager.default.createFile(atPath: partial.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw AgentError.rejected("Could not create the download file.")
            } }
            try store.checkDiskSpace(needed: artifact.sizeBytes - offset)
            store.set(artifact.id, .downloading(received: offset, total: artifact.sizeBytes))
            let throttle = ProgressThrottle(total: artifact.sizeBytes)
            let id = artifact.id
            do {
                try await store.transport.download(artifact.sourceURL, to: partial, offset: offset, limit: artifact.sizeBytes,
                                                  isApprovedHost: { ModelCatalog.isApproved(host: $0, approvedHosts: hosts) },
                                                  progress: { received in
                    guard throttle.shouldPublish(received) else { return }
                    Task { await store.progress(id, received: received, total: artifact.sizeBytes) }
                })
            } catch let error where !(error is CancellationError) && !Task.isCancelled {
                // Network interruption: keep the partial file so the next attempt resumes. Anything else (unapproved
                // redirect, HTTP error, oversize body) discards it. Never surface raw transport errors.
                let resumable = error is ArtifactTransportError || error is URLError
                store.logger.error("model download failed artifact=\(id, privacy: .public) resumable=\(resumable, privacy: .public)")
                if !resumable { try? FileManager.default.removeItem(at: partial) }
                throw resumable ? AgentError.rejected("The download was interrupted. Download again to resume.")
                    : (error as? AgentError) ?? AgentError.rejected("The model download failed.")
            }
            try Task.checkCancellation()
            try await store.verifyAndPromote(partial, as: artifact)
        }
    }

    /// Cancels an in-progress download or import and removes its partial file.
    public func cancel(_ artifactID: String) {
        guard let task = active[artifactID] else { return }
        userCancelled.insert(artifactID)
        task.cancel()
    }

    // MARK: Import

    /// Copies a user-selected file into the store and promotes it only if it matches the artifact's size and hash.
    /// The copy (not the source) is hashed, so a source changed after selection cannot slip through.
    public func importFile(_ source: URL, as artifact: ModelArtifact, catalog: ModelCatalog) async throws {
        guard catalog.artifact(id: artifact.id) == artifact else { throw AgentError.rejected("This model is not in the approved catalog.") }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        guard let size = Self.size(of: source) else { throw AgentError.rejected("The selected file could not be read.") }
        guard size == artifact.sizeBytes else {
            set(artifact.id, .failed("The selected file is not \(artifact.displayName) (size mismatch)."))
            throw AgentError.rejected("The selected file does not match the approved size for \(artifact.displayName).")
        }
        try await run(artifact) { store in
            let partial = store.partialURL(artifact)
            try store.prepareDirectories()
            try? FileManager.default.removeItem(at: partial)
            try store.checkDiskSpace(needed: artifact.sizeBytes)
            store.set(artifact.id, .verifying)
            do { try FileManager.default.copyItem(at: source, to: partial) } // APFS clones when on the same volume
            catch { throw AgentError.rejected("The selected file could not be copied into the Models folder.") }
            try await store.verifyAndPromote(partial, as: artifact)
        }
    }

    // MARK: Delete

    /// Removes the promoted file, its record and any partial file.
    public func delete(_ artifact: ModelArtifact) async {
        if let task = active[artifact.id] {
            userCancelled.insert(artifact.id); task.cancel()
            _ = try? await task.value
        }
        for url in [fileURL(artifact), recordURL(artifact), partialURL(artifact)] { try? FileManager.default.removeItem(at: url) }
        logger.notice("model deleted artifact=\(artifact.id, privacy: .public)")
        set(artifact.id, .notInstalled)
    }

    // MARK: Use

    /// The verified file for `artifact`, re-hashing it if it changed since verification. Fails closed.
    public func verifiedURL(for artifact: ModelArtifact) async throws -> URL {
        let url = fileURL(artifact)
        guard active[artifact.id] == nil else { throw AgentError.rejected("\(artifact.displayName) is still downloading or verifying.") }
        guard FileManager.default.fileExists(atPath: url.path) else {
            set(artifact.id, .notInstalled)
            throw AgentError.rejected("\(artifact.displayName) is not downloaded. Download it in Settings → Models.")
        }
        if diskStatus(artifact) == .ready { return url }
        set(artifact.id, .verifying)
        do {
            try await Self.verify(url, artifact: artifact)
            try writeRecord(artifact)
            set(artifact.id, .ready)
            return url
        } catch {
            let reason = (error as? AgentError)?.localizedDescription ?? "Verification failed."
            set(artifact.id, .failed(reason))
            throw AgentError.rejected(reason)
        }
    }

    // MARK: Internals

    private func run(_ artifact: ModelArtifact, _ body: @escaping @Sendable (isolated ModelStore) async throws -> Void) async throws {
        guard active[artifact.id] == nil else { throw AgentError.rejected("\(artifact.displayName) is already being installed.") }
        userCancelled.remove(artifact.id)
        let task = Task { try await body(self) }
        active[artifact.id] = task
        defer { active[artifact.id] = nil }
        do {
            try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        } catch {
            let cancelled = error is CancellationError || task.isCancelled || userCancelled.contains(artifact.id)
            userCancelled.remove(artifact.id)
            if cancelled {
                try? FileManager.default.removeItem(at: partialURL(artifact))
                set(artifact.id, diskStatus(artifact))
                throw CancellationError()
            }
            set(artifact.id, .failed((error as? AgentError)?.localizedDescription ?? "Installation failed."))
            throw error
        }
    }

    private func verifyAndPromote(_ partial: URL, as artifact: ModelArtifact) async throws {
        set(artifact.id, .verifying)
        do { try await Self.verify(partial, artifact: artifact) }
        catch {
            // A complete file with the wrong size or hash is never resumed or promoted.
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
        try Task.checkCancellation()
        // rename(2) within one volume is atomic: readers see either the old file or the verified new one.
        guard rename(partial.path, fileURL(artifact).path) == 0 else {
            throw AgentError.rejected("The verified model could not be moved into place.")
        }
        try writeRecord(artifact)
        logger.notice("model verified artifact=\(artifact.id, privacy: .public)")
        set(artifact.id, .ready)
    }

    /// Size first (cheap), then streaming SHA-256. Cancellable between chunks.
    static func verify(_ url: URL, artifact: ModelArtifact) async throws {
        guard size(of: url) == artifact.sizeBytes else {
            throw AgentError.rejected("\(artifact.displayName) failed verification (size mismatch).")
        }
        guard try await sha256(of: url) == artifact.sha256 else {
            throw AgentError.rejected("\(artifact.displayName) failed verification (SHA-256 mismatch).")
        }
    }

    static func sha256(of url: URL) async throws -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { throw AgentError.rejected("The model file could not be read.") }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            try Task.checkCancellation()
            let chunk = try autoreleasepool { try handle.read(upToCount: 8 << 20) } ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private struct Record: Codable, Equatable {
        let artifactID: String
        let sha256: String
        let sizeBytes: Int64
        let fileNumber: UInt64
        let modified: Double
    }
    private func currentRecord(_ artifact: ModelArtifact) -> Record? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL(artifact).path),
              (attributes[.type] as? FileAttributeType) == .typeRegular,
              let size = (attributes[.size] as? NSNumber)?.int64Value,
              let number = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
              let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 else { return nil }
        return Record(artifactID: artifact.id, sha256: artifact.sha256, sizeBytes: size, fileNumber: number, modified: modified)
    }
    private func writeRecord(_ artifact: ModelArtifact) throws {
        guard let record = currentRecord(artifact) else { throw AgentError.rejected("The verified model disappeared.") }
        try prepareDirectories()
        try JSONEncoder().encode(record).write(to: recordURL(artifact), options: .atomic)
    }
    /// ready only when a record for this exact hash still matches the file's size, inode and modification time.
    private func diskStatus(_ artifact: ModelArtifact) -> ArtifactStatus {
        guard let current = currentRecord(artifact) else {
            return FileManager.default.fileExists(atPath: fileURL(artifact).path) ? .unverified : .notInstalled
        }
        guard let data = try? Data(contentsOf: recordURL(artifact)),
              let saved = try? JSONDecoder().decode(Record.self, from: data),
              saved == current, current.sizeBytes == artifact.sizeBytes else { return .unverified }
        return .ready
    }
    private func prepareDirectories() throws {
        for sub in [".partial", ".verified"] {
            try FileManager.default.createDirectory(at: directory.appendingPathComponent(sub, isDirectory: true),
                                                    withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
    }
    private func checkDiskSpace(needed: Int64) throws {
        let available = try availableCapacity(directory)
        guard available >= needed + Self.diskMargin else {
            let gb = { (bytes: Int64) in String(format: "%.1f GB", Double(bytes) / 1_000_000_000) }
            throw AgentError.rejected("Not enough free disk space: \(gb(needed + Self.diskMargin)) needed, \(gb(max(0, available))) available.")
        }
    }
    static func size(of url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    }
    private func progress(_ id: String, received: Int64, total: Int64) {
        guard case .downloading = statuses[id] else { return }
        set(id, .downloading(received: received, total: total))
    }
    private func set(_ id: String, _ status: ArtifactStatus) {
        guard statuses[id] != status else { return }
        statuses[id] = status
        for observer in observers.values { observer.yield(statuses) }
    }
}

/// Publishes roughly every 0.5% so the UI is not flooded with per-chunk updates.
private final class ProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private let step: Int64
    private var last: Int64 = -1
    init(total: Int64) { step = max(1, total / 200) }
    func shouldPublish(_ value: Int64) -> Bool {
        lock.withLock {
            guard last < 0 || value - last >= step else { return false }
            last = value; return true
        }
    }
}

/// HTTPS range-resumable download with redirect host checks. Writes straight to disk; nothing is logged.
public struct URLSessionArtifactTransport: ArtifactTransport {
    public init() {}
    public func download(_ url: URL, to destination: URL, offset: Int64, limit: Int64,
                         isApprovedHost: @escaping @Sendable (String) -> Bool,
                         progress: @escaping @Sendable (Int64) -> Void) async throws {
        let delegate = try DownloadDelegate(destination: destination, offset: offset, limit: limit,
                                            isApprovedHost: isApprovedHost, progress: progress)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 6 * 3600
        configuration.httpCookieAcceptPolicy = .never
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: queue)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: url)
        if offset > 0 { request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }
        let task = session.dataTask(with: request)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                delegate.start(continuation)
                task.resume()
            }
        } onCancel: { task.cancel() }
    }
}

private final class DownloadDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let handle: FileHandle
    private let limit: Int64
    private let isApprovedHost: @Sendable (String) -> Bool
    private let progress: @Sendable (Int64) -> Void
    private var offset: Int64
    private var written: Int64 = 0
    private var failure: AgentError?
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, any Error>?

    init(destination: URL, offset: Int64, limit: Int64, isApprovedHost: @escaping @Sendable (String) -> Bool,
         progress: @escaping @Sendable (Int64) -> Void) throws {
        guard let handle = try? FileHandle(forWritingTo: destination) else { throw AgentError.rejected("Could not open the download file.") }
        self.handle = handle; self.offset = offset; self.limit = limit
        self.isApprovedHost = isApprovedHost; self.progress = progress
    }
    func start(_ continuation: CheckedContinuation<Void, any Error>) { lock.withLock { self.continuation = continuation } }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard let next = request.url, next.scheme == "https", let host = next.host, isApprovedHost(host) else {
            failure = AgentError.rejected("The download was redirected to an unapproved host.")
            completionHandler(nil); return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, let host = http.url?.host, isApprovedHost(host) else {
            failure = AgentError.rejected("The download response came from an unapproved host.")
            completionHandler(.cancel); return
        }
        do {
            switch http.statusCode {
            case 206 where offset > 0:
                // Only append when the server resumes exactly where the partial file ends.
                guard let range = http.value(forHTTPHeaderField: "Content-Range"), range.hasPrefix("bytes \(offset)-") else {
                    failure = AgentError.rejected("The server resumed at an unexpected position. Download again.")
                    try handle.truncate(atOffset: 0)
                    completionHandler(.cancel); return
                }
                try handle.seekToEnd()
            case 200:
                // No (or ignored) range request: start over.
                try handle.truncate(atOffset: 0); offset = 0
            default:
                failure = AgentError.rejected("The model download failed (HTTP \(http.statusCode)).")
                completionHandler(.cancel); return
            }
        } catch {
            failure = AgentError.rejected("Could not write the download file.")
            completionHandler(.cancel); return
        }
        if http.expectedContentLength > 0, offset + http.expectedContentLength > limit {
            failure = AgentError.rejected("The server offered a larger file than the approved size.")
            completionHandler(.cancel); return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard failure == nil else { return }
        guard offset + written + Int64(data.count) <= limit else {
            failure = AgentError.rejected("The download exceeded the approved size.")
            dataTask.cancel(); return
        }
        do { try handle.write(contentsOf: data) } catch {
            failure = AgentError.rejected("Could not write the download file. Check free disk space.")
            dataTask.cancel(); return
        }
        written += Int64(data.count)
        progress(offset + written)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        try? handle.synchronize()
        try? handle.close()
        let result: Result<Void, any Error>
        if let failure { result = .failure(failure) }
        else if let error {
            result = .failure((error as? URLError)?.code == .cancelled
                ? CancellationError() : ArtifactTransportError.interrupted)
        } else if let http = task.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            result = .failure(AgentError.rejected("The model download failed (HTTP \(http.statusCode))."))
        } else { result = .success(()) }
        let continuation = lock.withLock { () -> CheckedContinuation<Void, any Error>? in
            defer { self.continuation = nil }; return self.continuation
        }
        continuation?.resume(with: result)
    }
}
