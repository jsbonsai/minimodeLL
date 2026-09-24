import Foundation
import LocalAgentCore

/// `minimodell --probe-provider <provider-id>`: "Test connection" inside the packaged app's sandbox (ADR 0011).
/// Lists model IDs from `GET <baseURL>/models` of a provider in the resolved policy. Prints JSON; exit 0 only when reachable.
/// Output contains the provider ID, destination code and model IDs only — never credentials or response bodies.
enum ProviderProbeCommand {
    struct Summary: Encodable {
        var ok = false
        var providerID = ""
        var destination: String?
        var modelIDs: [String] = []
        var failure: String?
    }
    static func runAndExit() -> Never {
        let arguments = CommandLine.arguments
        let providerID = arguments.firstIndex(of: "--probe-provider").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil } ?? ""
        let done = DispatchSemaphore(value: 0)
        let box = ProbeBox()
        Task.detached {
            var summary = Summary(providerID: providerID)
            do {
                let snapshot = try ConfigurationLoader.load()
                guard let provider = snapshot.configuration.providers.first(where: { $0.id == providerID }) else {
                    throw AgentError.rejected("No provider with that ID in the resolved policy.")
                }
                summary.destination = provider.destination.code
                summary.modelIDs = try await ProviderProbe.listModels(provider: provider)
                summary.ok = true
            } catch let failure as AgentError {
                summary.failure = failure.localizedDescription
            } catch let failure as URLError {
                summary.failure = "Connection failed (URLError \(failure.errorCode))."
            } catch {
                summary.failure = "Connection failed."
            }
            box.summary = summary
            done.signal()
        }
        done.wait()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let summary = box.summary, let data = try? encoder.encode(summary) { print(String(decoding: data, as: UTF8.self)) }
        exit(box.summary?.ok == true ? 0 : 1)
    }
}
private final class ProbeBox: @unchecked Sendable { var summary: ProviderProbeCommand.Summary? }
