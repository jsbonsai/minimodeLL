import Foundation
import LocalAgentCore

struct Report: Encodable {
    let schemaVersion = 1
    let appVersion = Brand.version
    let operatingSystem: String
    let architecture: String
    let memoryGB: UInt64
    let configurationValid: Bool
    let managed: Bool
    let eligibleModelIDs: [String]
    let checks: [String]
}
let args = Array(CommandLine.arguments.dropFirst())
do {
    let snapshot: ConfigurationSnapshot?
    let config: AgentConfiguration
    if args.count == 2, args[0] == "--config" {
        snapshot = nil
        config = try ConfigurationLoader.decode(Data(contentsOf: URL(fileURLWithPath: args[1])))
    } else if args.isEmpty {
        snapshot = try ConfigurationLoader.load()
        config = snapshot!.configuration
    } else {
        throw AgentError.rejected("Usage: minimodell-diagnostics [--config /path/to/config.json]")
    }
    let memory = ProcessInfo.processInfo.physicalMemory / 1_073_741_824
    let eligible = config.models.filter { model in
        let provider = config.providers.first { $0.id == model.providerID }
        return provider?.kind == .litellm || model.minimumMemoryGB <= memory
    }.map(\.id)
    let report = Report(operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
                        architecture: "arm64", memoryGB: memory, configurationValid: true,
                        managed: snapshot?.managed ?? false, eligibleModelIDs: eligible,
                        checks: ["schema", "endpoint-policy", "model-references", "run-limit-bounds", "physical-memory-eligibility"])
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try encoder.encode(report), as: UTF8.self))
} catch {
    // Do not print configuration contents, URLs, credentials, or raw decoder errors.
    FileHandle.standardError.write(Data("Configuration validation failed. Check the schema and policy bounds.\n".utf8))
    exit(1)
}
