import SwiftUI
import LocalAgentCore

@main
struct MinimodeLLApp: App {
    @State private var state = AppState()
    var body: some Scene {
        WindowGroup(Brand.displayName, id: "workspace") {
            WorkspaceView(state: state)
        }
        .defaultSize(width: 820, height: 650)
        MenuBarExtra(Brand.displayName, systemImage: "sparkle.magnifyingglass") {
            MenuContent(state: state)
        }
        Settings { SettingsView(state: state).frame(width: 720, height: 560) }
    }
}
struct MenuContent: View {
    @Bindable var state: AppState
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(state.busy ? "Task in progress" : "Ready for a small task")
        Button("Open \(Brand.displayName)") {
            openWindow(id: "workspace"); NSApp.activate(ignoringOtherApps: true)
        }
        SettingsLink()
        if state.busy { Button("Stop task") { state.cancel() } }
        Divider()
        Button("Quit") { state.cancel(); NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
struct WorkspaceView: View {
    @Bindable var state: AppState
    private let accent = Color(red: 0.19, green: 0.55, blue: 0.48)
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                Label(Brand.displayName, systemImage: "sparkle.magnifyingglass")
                    .font(.title2.weight(.semibold))
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
                            .buttonStyle(.borderedProminent).tint(accent).keyboardShortcut(.return, modifiers: .command)
                            .disabled(state.snapshot == nil || state.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.input.utf8.count > (state.snapshot?.configuration.limits.inputBytes ?? 0))
                    }
                }
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let error = state.error {
                            Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                        }
                        if !state.result.isEmpty { Text(state.result).textSelection(.enabled) }
                        else if state.busy { Text("Working through your request…").foregroundStyle(.secondary) }
                        else if state.error == nil {
                            ContentUnavailableView("Ready when you are", systemImage: "text.bubble",
                                description: Text("Results appear here. Each task starts with a fresh context."))
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
                ScrollView { Text(proposal.arguments).font(.system(.body, design: .monospaced)).textSelection(.enabled) }
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
                TextEditor(text: $state.policyText).font(.system(.caption, design: .monospaced))
                    .disabled(state.snapshot?.managed == true || state.busy)
                HStack {
                    Button("Reload") { state.reload() }.disabled(state.busy)
                    Spacer()
                    Button("Validate & save") { state.savePolicy() }.disabled(state.snapshot?.managed == true || state.busy)
                }
                Text(state.settingsNotice).font(.caption)
            }.padding(24).tabItem { Label("Configuration", systemImage: "slider.horizontal.3") }
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
