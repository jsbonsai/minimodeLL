import Foundation
import OSLog

public actor AuditLog {
    public enum Event: String, Codable, Sendable {
        case runStarted, runCompleted, runFailed, runCancelled, toolProposed, toolApproved, toolDenied, toolCompleted
    }
    public struct Entry: Codable, Sendable {
        public let timestamp: Date
        public let runID: UUID
        public let event: Event
        public let modelID: String
        public let toolID: String?
    }
    private let directory: URL
    private let logger = Logger(subsystem: Brand.identity, category: "audit")
    public init(directory: URL = Brand.supportDirectory.appendingPathComponent("Audit")) { self.directory = directory }
    public func record(_ event: Event, runID: UUID, modelID: String, toolID: String? = nil) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent("events.jsonl")
        // Bounded retention: active log + one previous segment, approximately 2 MiB total.
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? NSNumber, size.intValue > 1_048_576 {
            let previous = directory.appendingPathComponent("events.previous.jsonl")
            if FileManager.default.fileExists(atPath: previous.path) { try FileManager.default.removeItem(at: previous) }
            try FileManager.default.moveItem(at: url, to: previous)
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw AgentError.rejected("Cannot create the audit log.")
            }
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var data = try encoder.encode(Entry(timestamp: Date(), runID: runID, event: event, modelID: modelID, toolID: toolID))
        data.append(0x0a)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        logger.notice("event=\(event.rawValue, privacy: .public) run=\(runID.uuidString, privacy: .public)")
    }
}
