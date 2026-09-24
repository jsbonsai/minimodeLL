import Foundation
import LocalAgentCore

struct Probe: Encodable {
    let providerID: String
    let destination: String
    let reachable: Bool
    let modelIDs: [String]
    let error: String?
}
struct Report: Encodable {
    let schemaVersion = 1
    let appVersion = Brand.version
    let operatingSystem: String
    let architecture: String
    let memoryGB: UInt64
    let configurationValid: Bool
    let managed: Bool
    let eligibleModelIDs: [String]
    /// Provider ID → `this-mac`, `lan-tls`, `lan-unencrypted` or `cloud` (ADR 0011).
    let providerDestinations: [String: String]
    let checks: [String]
    /// Present only with `--probe-provider`, the one option that performs a network request.
    let probe: Probe?
}
let usage = "Usage: minimodell-diagnostics [--config /path/to/config.json] [--probe-provider <provider-id>]"
var args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String, in args: inout [String]) throws -> String? {
    guard let index = args.firstIndex(of: name) else { return nil }
    guard index + 1 < args.count else { throw AgentError.rejected(usage) }
    let value = args[index + 1]
    args.removeSubrange(index...(index + 1))
    return value
}
do {
    let configPath = try option("--config", in: &args)
    let probeID = try option("--probe-provider", in: &args)
    guard args.isEmpty else { throw AgentError.rejected(usage) }
    let snapshot: ConfigurationSnapshot?
    let config: AgentConfiguration
    if let configPath {
        snapshot = nil
        config = try ConfigurationLoader.decode(Data(contentsOf: URL(fileURLWithPath: configPath)))
    } else {
        snapshot = try ConfigurationLoader.load()
        config = snapshot!.configuration
    }
    let memory = ProcessInfo.processInfo.physicalMemory / 1_073_741_824
    let eligible = config.models.filter { model in
        let provider = config.providers.first { $0.id == model.providerID }
        return provider?.kind.isOnDevice == false || model.minimumMemoryGB <= memory
    }.map(\.id)
    var probe: Probe?
    if let probeID {
        guard let provider = config.providers.first(where: { $0.id == probeID }) else {
            throw AgentError.rejected("No provider with that ID in the configuration.")
        }
        do {
            let ids = try await ProviderProbe.listModels(provider: provider)
            probe = Probe(providerID: provider.id, destination: provider.destination.code, reachable: true, modelIDs: ids, error: nil)
        } catch {
            // Only our own fixed messages or an error code; never a response body.
            let message = (error as? AgentError)?.localizedDescription
                ?? (error as? URLError).map { "Connection failed (URLError \($0.errorCode))." } ?? "Connection failed."
            probe = Probe(providerID: provider.id, destination: provider.destination.code, reachable: false, modelIDs: [], error: message)
        }
    }
    let report = Report(operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
                        architecture: "arm64", memoryGB: memory, configurationValid: true,
                        managed: snapshot?.managed ?? false, eligibleModelIDs: eligible,
                        providerDestinations: Dictionary(uniqueKeysWithValues: config.providers.map { ($0.id, $0.destination.code) }),
                        checks: ["schema", "endpoint-policy", "model-references", "run-limit-bounds", "model-catalog", "physical-memory-eligibility"],
                        probe: probe)
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try encoder.encode(report), as: UTF8.self))
    if probe?.reachable == false { exit(2) }
} catch let failure as AgentError where failure.localizedDescription == usage || failure.localizedDescription.hasPrefix("No provider") {
    FileHandle.standardError.write(Data((failure.localizedDescription + "\n").utf8))
    exit(1)
} catch {
    // Do not print configuration contents, URLs, credentials, or raw decoder errors.
    FileHandle.standardError.write(Data("Configuration validation failed. Check the schema and policy bounds.\n".utf8))
    exit(1)
}
