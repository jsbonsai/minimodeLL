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
    var artifactStatuses: [String: ArtifactStatus] = [:]
    var modelNotice = ""
    /// Result of the last "Test connection" (model IDs or a safe error). For later UI use.
    var probeNotice = ""
    var probedModelIDs: [String] = []
    private var runningTask: Task<Void, Never>?
    private let browser = BrowserAuthorization()
    /// Verified model files in the container's Models folder (ADR 0009).
    let modelStore: ModelStore
    /// App-owned bundled llama-server for `managed` providers (ADR 0008).
    let runtime: RuntimeManager
    init() {
        // Keys, headers, URLs and JSON are typed in this app; typographic substitution would corrupt them
        // (for example "--" becoming an em dash). Set in the app domain so it overrides the global preference.
        for key in ["NSAutomaticDashSubstitutionEnabled", "NSAutomaticQuoteSubstitutionEnabled", "NSAutomaticTextReplacementEnabled"] {
            UserDefaults.standard.set(false, forKey: key)
        }
        let store = ModelStore()
        modelStore = store
        runtime = RuntimeManager(modelStore: store)
        reload()
        let runtime = runtime
        Task { [weak self] in
            for await state in await runtime.updates() { self?.runtimeState = state }
        }
        Task { [weak self] in
            for await statuses in await store.updates() { self?.artifactStatuses = statuses }
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
    /// Destination shown before submission (ADR 0011). LAN labels disclose that the request and tool results go to that host.
    var destination: InferenceDestination? { provider?.destination }
    var destinationLabel: String { destination?.label ?? "Select an approved model" }
    var destinationSymbol: String {
        switch destination {
        case .cloud: "cloud"
        case .lan(_, true): "network"
        case .lan(_, false): "network.badge.shield.half.filled"
        case .thisMac, nil: "desktopcomputer"
        }
    }
    /// "Test connection": GET <baseURL>/models on a configured provider. Shows model IDs only; nothing is logged.
    func testConnection(providerID: String) {
        guard let provider = snapshot?.configuration.providers.first(where: { $0.id == providerID }) else {
            probeNotice = "Unknown provider."; return
        }
        probeNotice = "Testing \(provider.id)…"; probedModelIDs = []
        Task {
            do {
                let ids = try await ProviderProbe.listModels(provider: provider)
                probedModelIDs = ids
                probeNotice = ids.isEmpty ? "Connected. The server reported no models." : "Connected. \(ids.count) model(s) available."
            } catch let failure as AgentError {
                probeNotice = failure.localizedDescription
            } catch {
                probeNotice = "Could not reach \(provider.id). Check the address, network, and credential."
            }
        }
    }
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
            let artifacts = loaded.configuration.effectiveCatalog.artifacts
            Task { await modelStore.refresh(artifacts) }
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
                ? ManagedInferenceClient(runtime: runtime, provider: provider, artifact: snapshot.configuration.artifact(for: provider))
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

    // MARK: Models (ADR 0009). The store enforces catalog membership, hosts, disk space and hashes.
    var catalog: ModelCatalog? { snapshot?.configuration.effectiveCatalog }
    /// The artifact the selected managed provider runs, if any.
    var activeArtifactID: String? { provider.flatMap { snapshot?.configuration.artifact(for: $0)?.id } }
    func status(of artifact: ModelArtifact) -> ArtifactStatus { artifactStatuses[artifact.id] ?? .notInstalled }
    func download(_ artifact: ModelArtifact) {
        guard let catalog else { return }
        modelNotice = ""
        Task {
            do { try await modelStore.download(artifact, catalog: catalog) }
            catch is CancellationError { modelNotice = "Download cancelled." }
            catch { modelNotice = (error as? AgentError)?.localizedDescription ?? "The download failed." }
        }
    }
    func cancelDownload(_ artifact: ModelArtifact) { Task { await modelStore.cancel(artifact.id) } }
    func delete(_ artifact: ModelArtifact) {
        modelNotice = ""
        Task {
            // Release the file (and its memory) before removing it.
            if activeArtifactID == artifact.id { await runtime.stop() }
            await modelStore.delete(artifact)
        }
    }
    func importModel(_ artifact: ModelArtifact, from url: URL) {
        guard let catalog else { return }
        modelNotice = ""
        Task {
            do { try await modelStore.importFile(url, as: artifact, catalog: catalog); modelNotice = "\(artifact.displayName) imported and verified." }
            catch is CancellationError { modelNotice = "Import cancelled." }
            catch { modelNotice = (error as? AgentError)?.localizedDescription ?? "The import failed." }
        }
    }
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
