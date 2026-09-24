import SwiftUI
import LocalAgentCore

@MainActor @Observable
final class AppState {
    var snapshot: ConfigurationSnapshot?
    var selectedModel = ""
    var input = ""
    var result = ""
    var error: String?
    var busy = false
    var policyText = ""
    var proposal: ToolProposal?
    var approval: Bool?
    var credentialAccount = ""
    var credentialValue = ""
    var settingsNotice = ""
    var runtimeState: RuntimeState = .stopped
    private var runningTask: Task<Void, Never>?
    private let browser = BrowserAuthorization()
    /// App-owned bundled llama-server for `managed` providers (ADR 0008).
    let runtime = RuntimeManager()
    init() {
        reload()
        let runtime = runtime
        Task { [weak self] in
            for await state in await runtime.updates() { self?.runtimeState = state }
        }
        // Never leave the helper running after the app quits.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { _ in
            runtime.terminateForQuit()
        }
    }
    var usesManagedRuntime: Bool { provider?.kind == .managed }
    func stopRuntime() { Task { await runtime.stop() } }
    var model: ModelSpec? { snapshot?.configuration.models.first { $0.id == selectedModel } }
    var provider: ProviderSpec? { snapshot?.configuration.providers.first { $0.id == model?.providerID } }
    var memoryGB: UInt64 { ProcessInfo.processInfo.physicalMemory / 1_073_741_824 }
    func reload() {
        do {
            try ConfigurationLoader.installStarterIfNeeded()
            let loaded = try ConfigurationLoader.load()
            snapshot = loaded
            if !loaded.configuration.models.contains(where: { $0.id == selectedModel }) {
                selectedModel = loaded.configuration.models.first?.id ?? ""
            }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            policyText = String(decoding: try encoder.encode(loaded.configuration), as: UTF8.self)
            error = nil
            // Policy no longer allows the bundled runtime: release its memory now.
            if !loaded.configuration.providers.contains(where: { $0.kind == .managed }) { stopRuntime() }
        } catch {
            snapshot = nil
            self.error = "Configuration could not be loaded. Check config.json or the managed PolicyJSON."
        }
    }
    func savePolicy() {
        do {
            // Recheck management status at write time.
            guard !(try ConfigurationLoader.isManaged()) else { throw AgentError.rejected("Your organization manages this configuration.") }
            _ = try ConfigurationLoader.decode(Data(policyText.utf8))
            try Data(policyText.utf8).write(to: ConfigurationLoader.userURL, options: .atomic)
            reload(); settingsNotice = "Configuration saved."
        } catch { settingsNotice = error.localizedDescription }
    }
    func saveCredential() {
        do {
            guard !credentialAccount.isEmpty, !credentialValue.isEmpty else { throw AgentError.rejected("Enter the configured account name and token.") }
            try CredentialStore.save(credentialValue, account: credentialAccount)
            credentialValue = ""; settingsNotice = "Credential saved in your Keychain."
        } catch { settingsNotice = error.localizedDescription }
    }
    func submit() {
        guard !busy else { return }
        // Capture freshly resolved policy for every run, including MDM changes since launch.
        let previousModel = selectedModel
        let previousProvider = provider
        reload()
        guard let snapshot, let provider else { return }
        guard selectedModel == previousModel, provider == previousProvider else {
            error = "Your model policy changed. Review the selected model and destination, then submit again."
            return
        }
        busy = true; error = nil; result = ""
        let input = input
        let modelID = selectedModel
        runningTask = Task {
            let connections = MCPConnections(servers: snapshot.configuration.mcpServers, authorizationDelegate: browser)
            let inference: any InferenceClient = provider.kind == .managed
                ? ManagedInferenceClient(runtime: runtime, provider: provider)
                : CompatibleInferenceClient(provider: provider)
            let runner = TaskRunner(inference: inference, tools: connections)
            do {
                result = try await runner.run(input: input, modelID: modelID, configuration: snapshot.configuration) { [weak self] proposal in
                    await self?.requestApproval(proposal) ?? false
                }
            } catch is CancellationError {
                self.error = "Task stopped. An action already sent to a service may still complete."
            } catch let failure as AgentError {
                self.error = failure.localizedDescription
            } catch {
                // Remote error bodies can contain content or credentials; never display or log them verbatim.
                self.error = "The task could not complete. Check the provider, connection, and sign-in settings."
            }
            proposal = nil; busy = false; runningTask = nil
        }
    }
    func cancel() { runningTask?.cancel() }
    func decide(_ accepted: Bool) { approval = accepted; proposal = nil }
    private func requestApproval(_ proposed: ToolProposal) async -> Bool {
        approval = nil; proposal = proposed
        defer { proposal = nil; approval = nil }
        while approval == nil {
            do { try await Task.sleep(for: .milliseconds(100)) }
            catch { return false }
        }
        return approval ?? false
    }
}
