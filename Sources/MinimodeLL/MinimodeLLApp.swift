import SwiftUI
import LocalAgentCore

@main
struct MinimodeLLApp: App {
    @State private var state = AppState()
    init() {
        if CommandLine.arguments.contains("--runtime-smoke-test") { RuntimeSmokeCommand.runAndExit() }
        if CommandLine.arguments.contains("--model-download") { ModelDownloadCommand.runAndExit() }
        BrandAssets.registerFonts()
    }
    var body: some Scene {
        WindowGroup(Brand.displayName, id: "workspace") {
            WorkspaceView(state: state).tint(.mmAccent).font(.custom("Geist-Regular", size: 13))
        }
        .defaultSize(width: 820, height: 650)
        MenuBarExtra {
            MenuContent(state: state)
        } label: {
            Image(nsImage: BrandAssets.menuIcon(state.brandState))
                .accessibilityLabel(Brand.displayName)
        }
        Settings { SettingsView(state: state).tint(.mmAccent).frame(width: 720, height: 560) }
    }
}
/// `minimodell --runtime-smoke-test [--tool] [--show-reply] [--hold N]`: exercises the bundled runtime under the
/// app's own sandbox with the resolved policy and fixed synthetic prompts, prints a JSON report (timings and token
/// counts; synthetic reply text only with --show-reply), and exits before any window is shown. `--tool` adds a
/// synthetic tool round trip through TaskRunner with an in-process fixture. Exit status 0 only on success.
enum RuntimeSmokeCommand {
    static func runAndExit() -> Never {
        let arguments = CommandLine.arguments
        let hold = arguments.firstIndex(of: "--hold").flatMap { arguments.indices.contains($0 + 1) ? Int(arguments[$0 + 1]) : nil } ?? 0
        let done = DispatchSemaphore(value: 0)
        let box = ReportBox()
        Task.detached {
            let report: RuntimeSmokeTest.Report
            do {
                let snapshot = try ConfigurationLoader.load()
                report = await RuntimeSmokeTest.run(configuration: snapshot.configuration,
                                                    runtime: RuntimeManager(modelStore: ModelStore()), holdSeconds: hold,
                                                    includeTool: arguments.contains("--tool"),
                                                    showReply: arguments.contains("--show-reply"))
            } catch {
                var failed = RuntimeSmokeTest.Report(); failed.failure = "Configuration could not be loaded."
                report = failed
            }
            box.report = report
            done.signal()
        }
        done.wait()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let report = box.report, let data = try? encoder.encode(report) { print(String(decoding: data, as: UTF8.self)) }
        exit(box.report?.ok == true ? 0 : 1)
    }
}
private final class ReportBox: @unchecked Sendable { var report: RuntimeSmokeTest.Report? }
/// `minimodell --model-download [artifact-id]`: downloads, verifies and promotes an approved artifact through
/// `ModelStore` inside the packaged app's sandbox (default: the artifact the resolved policy's managed provider uses).
/// Prints coarse progress to stderr and a JSON summary; exit status 0 only when the artifact is verified and ready.
enum ModelDownloadCommand {
    struct Summary: Encodable {
        var ok = false
        var artifactID: String?
        var sizeBytes: Int64?
        var seconds: Double?
        var status = ""
        var failure: String?
    }
    static func runAndExit() -> Never {
        let arguments = CommandLine.arguments
        let requested = arguments.firstIndex(of: "--model-download").flatMap {
            arguments.indices.contains($0 + 1) && !arguments[$0 + 1].hasPrefix("--") ? arguments[$0 + 1] : nil
        }
        let done = DispatchSemaphore(value: 0)
        let box = SummaryBox()
        Task.detached {
            var summary = Summary()
            do {
                let configuration = try ConfigurationLoader.load().configuration
                let catalog = configuration.effectiveCatalog
                let fromPolicy = configuration.providers.lazy.compactMap { configuration.artifact(for: $0) }.first
                guard let artifact = requested.flatMap(catalog.artifact(id:)) ?? (requested == nil ? fromPolicy : nil) else {
                    throw AgentError.rejected("No such approved artifact in the resolved catalog.")
                }
                summary.artifactID = artifact.id; summary.sizeBytes = artifact.sizeBytes
                let store = ModelStore()
                let watcher = Task {
                    var lastStep = -1
                    for await statuses in await store.updates() {
                        guard case .downloading(let received, let total)? = statuses[artifact.id], total > 0 else { continue }
                        let step = Int(Double(received) / Double(total) * 20)
                        if step != lastStep { lastStep = step; FileHandle.standardError.write(Data("downloading \(step * 5)%\n".utf8)) }
                    }
                }
                let started = Date()
                do { try await store.download(artifact, catalog: catalog) } catch { watcher.cancel(); throw error }
                watcher.cancel()
                summary.seconds = (Date().timeIntervalSince(started) * 10).rounded() / 10
                summary.status = await store.status(of: artifact).summary
                summary.ok = await store.status(of: artifact) == .ready
            } catch {
                summary.failure = (error as? AgentError)?.localizedDescription ?? "Download failed."
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
private final class SummaryBox: @unchecked Sendable { var summary: ModelDownloadCommand.Summary? }
struct MenuContent: View {
    @Bindable var state: AppState
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(state.busy ? "Task in progress" : "Ready for a small task")
        Button("Open \(Brand.displayName)") {
            openWindow(id: "workspace"); NSApp.activate(ignoringOtherApps: true)
        }
        if state.usesManagedRuntime || state.runtimeState != .stopped { Text(state.runtimeState.summary) }
        SettingsLink()
        if state.busy { Button("Stop task") { state.cancel() } }
        if !state.busy, state.runtimeState == .ready { Button("Unload local model") { state.stopRuntime() } }
        Divider()
        Button("Quit") { state.cancel(); NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
struct WorkspaceView: View {
    @Bindable var state: AppState
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                BrandLockup(state: state.brandState)
                Text("Small tasks.\nYour tools.\nYour Mac.")
                    .font(.title3).foregroundStyle(.secondary)
                Divider()
                Label("\(state.memoryGB) GB memory", systemImage: "memorychip")
                Label(state.snapshot?.managed == true ? "Managed by your organization" : "Personal configuration",
                      systemImage: "slider.horizontal.3")
                VStack(alignment: .leading, spacing: 8) {
                    Text("CONNECTIONS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    if let servers = state.snapshot?.configuration.mcpServers, !servers.isEmpty {
                        ForEach(servers) { server in
                            Label(server.title, systemImage: "link").font(.callout)
                        }
                        Text("Connected when a task runs").font(.caption).foregroundStyle(.secondary)
                    } else { Text("Add MCP servers in Settings").font(.callout).foregroundStyle(.secondary) }
                }
                Spacer()
                SettingsLink { Label("Settings", systemImage: "gearshape") }
                Text("Preview · \(Brand.version)").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(24).frame(width: 220, alignment: .leading).frame(maxHeight: .infinity)
            .background(.ultraThinMaterial)
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("What can we get done?").font(.title2.weight(.semibold))
                    Spacer()
                    if state.busy { ProgressView().controlSize(.small) }
                }
                Text("One focused request at a time. Try a short summary, a lookup, or a specific action.")
                    .foregroundStyle(.secondary)
                if let snapshot = state.snapshot {
                    Picker("Model", selection: $state.selectedModel) {
                        ForEach(snapshot.configuration.models) { model in Text(model.title).tag(model.id) }
                    }.disabled(state.busy)
                }
                Label(state.provider?.kind == .litellm ? "Cloud inference through your LiteLLM gateway" : "Local inference · tools connect to remote services",
                      systemImage: state.provider?.kind == .litellm ? "cloud" : "desktopcomputer")
                    .font(.caption).foregroundStyle(.secondary)
                if state.usesManagedRuntime { RuntimeStatus(runtime: state.runtimeState) }
                TextEditor(text: $state.input)
                    .font(.body).scrollContentBackground(.hidden).padding(10)
                    .frame(height: 100).background(.background, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
                    .disabled(state.busy).accessibilityLabel("Task request")
                HStack {
                    Text("\(state.input.utf8.count) / \(state.snapshot?.configuration.limits.inputBytes ?? 0) bytes")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Spacer()
                    if state.busy { Button("Stop") { state.cancel() } }
                    else {
                        Button("Run task", systemImage: "arrow.up") { state.submit() }
                            .buttonStyle(.borderedProminent).tint(.mmAccent).keyboardShortcut(.return, modifiers: .command)
                            .disabled(state.snapshot == nil || state.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.input.utf8.count > (state.snapshot?.configuration.limits.inputBytes ?? 0))
                    }
                }
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let error = state.error {
                            Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                        }
                        if !state.result.isEmpty { Text(state.result).font(.custom("Geist-Regular", size: 14)).textSelection(.enabled) }
                        else if state.busy { Text("Working through your request…").foregroundStyle(.secondary) }
                        else if state.error == nil {
                            ContentUnavailableView {
                                MinimodeMark(state: .idle).frame(width: 56, height: 56).accessibilityHidden(true)
                                Text("Ready when you are").font(.custom("Geist-SemiBold", size: 24))
                            } description: {
                                Text("Results appear here. Each task starts with a fresh context.")
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(28).frame(minWidth: 480)
        }
        .frame(minWidth: 780, minHeight: 600)
        .sheet(item: $state.proposal, onDismiss: { if state.approval == nil { state.decide(false) } }) { proposal in
            VStack(alignment: .leading, spacing: 16) {
                Text("Review tool action").font(.title2.bold())
                Text("\(proposal.server) → \(proposal.tool)").font(.headline)
                Text("These arguments were generated by the model. Review them before allowing the action.").foregroundStyle(.secondary)
                ScrollView { Text(proposal.arguments).font(.custom("GeistMono-Regular", size: 13)).textSelection(.enabled) }
                HStack { Button("Decline") { state.decide(false) }; Spacer(); Button("Allow once") { state.decide(true) }.buttonStyle(.borderedProminent) }
            }.padding(24).frame(width: 540, height: 360)
        }
    }
}
struct SettingsView: View {
    @Bindable var state: AppState
    var body: some View {
        TabView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Approved models, providers & tools").font(.title2)
                Text(state.snapshot?.managed == true ? "Your organization supplies this policy." : "Configure local inference, LiteLLM aliases, and HTTPS MCP servers. Store tokens in the Credentials tab.")
                    .foregroundStyle(.secondary)
                TextEditor(text: $state.policyText).font(.custom("GeistMono-Regular", size: 12))
                    .disabled(state.snapshot?.managed == true || state.busy)
                HStack {
                    Button("Reload") { state.reload() }.disabled(state.busy)
                    Spacer()
                    Button("Validate & save") { state.savePolicy() }.disabled(state.snapshot?.managed == true || state.busy)
                }
                Text(state.settingsNotice).font(.caption)
            }.padding(24).tabItem { Label("Configuration", systemImage: "slider.horizontal.3") }
            ModelsSettings(state: state).padding(24).tabItem { Label("Models", systemImage: "cpu") }
            Form {
                Text("Credentials stay in your macOS Keychain.").font(.headline)
                Text("For a provider or bearer-authenticated MCP server, use its credentialAccount value below. OAuth servers open browser sign-in when first used.").foregroundStyle(.secondary)
                TextField("Account", text: $state.credentialAccount)
                SecureField("Token", text: $state.credentialValue)
                Button("Save in Keychain") { state.saveCredential() }.disabled(state.busy)
                Text(state.settingsNotice)
            }.padding(24).tabItem { Label("Credentials", systemImage: "key") }
            VStack(alignment: .leading, spacing: 16) {
                Text("Privacy & audit").font(.title2)
                Text("Audit events record run IDs, configured model and tool IDs, timestamps, and outcomes. Prompts, responses, tool arguments, and tokens are excluded.")
                Text("Local logs are useful for troubleshooting; they are not a tamper-proof enterprise audit trail. Administrators can collect metadata through their existing endpoint tooling.").foregroundStyle(.secondary)
                Button("Open audit folder") {
                    let url = Brand.supportDirectory.appendingPathComponent("Audit")
                    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(url)
                }
                Spacer()
            }.padding(24).tabItem { Label("Audit", systemImage: "list.bullet.rectangle") }
        }
    }
}
/// Minimal readiness indicator for the app-owned local runtime. Content-free: state and reason only.
struct RuntimeStatus: View {
    let runtime: RuntimeState
    var body: some View {
        HStack(spacing: 6) {
            switch runtime {
            case .starting, .stopping: ProgressView().controlSize(.mini)
            case .ready: Image(systemName: "circle.fill").foregroundStyle(.green)
            case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            case .stopped: Image(systemName: "circle").foregroundStyle(.secondary)
            }
            Text(runtime == .stopped ? "Local model starts with your next task" : runtime.summary)
                .lineLimit(2)
        }
        .font(.caption).foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}
/// Approved model files: status, download, cancel, delete, import. Deliberately plain (a redesign is backlog).
/// All checks (approved catalog, hosts, disk space, size + SHA-256 before promotion) happen in `ModelStore`.
struct ModelsSettings: View {
    @Bindable var state: AppState
    @State private var importing: ModelArtifact?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Approved models").font(.title2)
            Text("Models run on this Mac in the bundled runtime. Each file is checked against its approved size and SHA-256 before it can be used.")
                .foregroundStyle(.secondary)
            if let catalog = state.catalog {
                if catalog.artifacts.isEmpty { Text("No approved models in this configuration.").foregroundStyle(.secondary) }
                ForEach(catalog.artifacts) { artifact in
                    ModelRow(artifact: artifact, status: state.status(of: artifact), active: state.activeArtifactID == artifact.id,
                             canDownload: catalog.allowDownloads, busy: state.busy,
                             download: { state.download(artifact) }, cancel: { state.cancelDownload(artifact) },
                             delete: { state.delete(artifact) }, importFile: { importing = artifact })
                    Divider()
                }
                Text("Catalog \(catalog.catalogVersion)\(state.snapshot?.managed == true ? " · managed by your organization" : "")")
                    .font(.caption).foregroundStyle(.tertiary)
            } else {
                Text("Configuration could not be loaded.").foregroundStyle(.secondary)
            }
            Spacer()
            Text(state.modelNotice).font(.caption)
        }
        .fileImporter(isPresented: Binding(get: { importing != nil }, set: { if !$0 { importing = nil } }),
                      allowedContentTypes: [.data]) { result in
            if let artifact = importing, case .success(let url) = result { state.importModel(artifact, from: url) }
            importing = nil
        }
    }
}
struct ModelRow: View {
    let artifact: ModelArtifact
    let status: ArtifactStatus
    let active: Bool
    let canDownload: Bool
    let busy: Bool
    let download: () -> Void, cancel: () -> Void, delete: () -> Void, importFile: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(artifact.displayName).font(.headline)
                if active { Text("In use by policy").font(.caption).padding(.horizontal, 6).background(.quaternary, in: Capsule()) }
                Spacer()
                statusView
            }
            Text("\(ByteCountFormatter.string(fromByteCount: artifact.sizeBytes, countStyle: .file)) · \(artifact.quantization) · \(artifact.license) · needs \(artifact.minimumMemoryGB) GB memory")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                switch status {
                case .downloading, .verifying:
                    Button("Cancel", action: cancel)
                case .ready:
                    Button("Delete", role: .destructive, action: delete).disabled(busy && active)
                case .notInstalled, .unverified, .failed:
                    if canDownload { Button("Download", action: download).buttonStyle(.borderedProminent).tint(.mmAccent) }
                    Button("Import…", action: importFile)
                    if status != .notInstalled { Button("Delete", role: .destructive, action: delete).disabled(busy && active) }
                }
            }.controlSize(.small)
        }
    }
    @ViewBuilder private var statusView: some View {
        switch status {
        case .downloading(let received, let total):
            HStack(spacing: 6) {
                ProgressView(value: Double(received), total: Double(max(total, 1))).frame(width: 120)
                Text(status.summary).font(.caption.monospacedDigit())
            }
        case .verifying: HStack(spacing: 6) { ProgressView().controlSize(.mini); Text(status.summary).font(.caption) }
        case .ready: Label(status.summary, systemImage: "checkmark.seal.fill").font(.caption).foregroundStyle(.green)
        case .failed: Label(status.summary, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange).lineLimit(2)
        case .notInstalled, .unverified: Text(status.summary).font(.caption).foregroundStyle(.secondary)
        }
    }
}
