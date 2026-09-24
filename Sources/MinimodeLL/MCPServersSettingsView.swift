import SwiftUI
import LocalAgentCore

// Settings → MCP Servers (ADR 0012). Presentation only: validation, managed-policy locking, Keychain ownership and
// discovery limits are enforced by `MCPServerStore`, `MCPServerSpec.validate()` and `MCPServerProbe` in LocalAgentCore.
// Deliberately built from standard controls so the visual redesign can restyle it without touching behavior.

struct MCPServersSettingsView: View {
    @Bindable var state: AppState
    @State private var editing: EditorTarget?
    @State private var pendingDelete: MCPServerSpec?
    @State private var notice = ""
    private let store = MCPServerStore()

    struct EditorTarget: Identifiable {
        let id = UUID()
        let server: MCPServerSpec?
    }
    private var managed: Bool { state.snapshot?.managed == true }
    private var servers: [MCPServerSpec] { state.snapshot?.configuration.mcpServers ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("MCP servers").font(.title2)
                Spacer()
                Button { editing = EditorTarget(server: nil) } label: { Label("Add server", systemImage: "plus") }
                    .disabled(managed || state.snapshot == nil)
            }
            Text("HTTPS (Streamable HTTP) services the assistant may use. Only tools you approve are offered to the model.")
                .foregroundStyle(.secondary)
            if managed {
                Label("Managed by your organization. These servers are read-only on this Mac.", systemImage: "lock.fill")
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
            if state.snapshot == nil {
                Text("Configuration could not be loaded. Fix it in the Configuration tab first.").foregroundStyle(.secondary)
            } else if servers.isEmpty {
                Text("No MCP servers yet.").foregroundStyle(.secondary)
            }
            List {
                ForEach(servers) { server in
                    MCPServerRow(server: server, managed: managed,
                                 setEnabled: { setEnabled($0, server) },
                                 edit: { editing = EditorTarget(server: server) },
                                 delete: { pendingDelete = server })
                }
            }
            .listStyle(.inset)
            Text(notice).font(.caption)
        }
        .sheet(item: $editing) { target in
            MCPServerEditor(state: state, original: target.server, managed: managed) { message in
                notice = message; state.reload()
            }
        }
        .confirmationDialog("Delete \(pendingDelete?.title ?? "server")?",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            presenting: pendingDelete) { server in
            Button("Delete server and its saved secrets", role: .destructive) { delete(server) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The server is removed from your configuration. Keychain items the app created for it (bearer token, secret header values, OAuth sign-in) are deleted. Accounts shared with other servers are kept.")
        }
    }
    private func setEnabled(_ enabled: Bool, _ server: MCPServerSpec) {
        do { try store.setEnabled(enabled, serverID: server.id); notice = ""; state.reload() }
        catch { notice = error.localizedDescription }
    }
    private func delete(_ server: MCPServerSpec) {
        do {
            let removed = try store.delete(serverID: server.id)
            notice = "Deleted \(server.title). Removed \(removed) saved secret(s)."
            state.reload()
        } catch { notice = error.localizedDescription }
        pendingDelete = nil
    }
}

struct MCPServerRow: View {
    let server: MCPServerSpec
    let managed: Bool
    let setEnabled: (Bool) -> Void
    let edit: () -> Void
    let delete: () -> Void
    private var authLabel: String {
        switch server.authMode {
        case .none: "No authentication"
        case .bearer: "Bearer token"
        case .oauth: "OAuth sign-in"
        }
    }
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(server.title).font(.headline)
                Text(server.endpoint.host ?? server.endpoint.absoluteString).font(.caption).foregroundStyle(.secondary)
                Text("\(authLabel) · \(server.tools.count) approved tool(s) · \(server.headers?.count ?? 0) custom header(s)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Enabled", isOn: Binding(get: { server.isEnabled }, set: { setEnabled($0) }))
                .toggleStyle(.switch).labelsHidden().disabled(managed)
                .help(server.isEnabled ? "Enabled" : "Disabled: never connected")
            Button(managed ? "View" : "Edit", action: edit)
            if !managed {
                Button(role: .destructive, action: delete) { Image(systemName: "trash") }
                    .help("Delete server")
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: Editor

struct MCPServerEditor: View {
    enum AuthChoice: String, CaseIterable, Identifiable {
        case none = "None", bearer = "Bearer token", oauth = "OAuth (public client)"
        var id: String { rawValue }
    }
    struct HeaderDraft: Identifiable {
        let id = UUID()
        var name = ""
        var secret = false
        var value = ""
        /// Keychain account of a secret header that already exists; blank `value` keeps the saved secret.
        var existingAccount: String?
    }
    struct ToolDraft: Identifiable {
        var id: String { name }
        let name: String
        var description = ""
        var allowed: Bool
        var requiresConfirmation: Bool
        var schemaSupported = true
        var offered = false
    }

    @Environment(\.dismiss) private var dismiss
    let state: AppState
    let original: MCPServerSpec?
    let managed: Bool
    let onSaved: (String) -> Void

    @State private var serverID = ""
    @State private var title = ""
    @State private var endpoint = "https://"
    @State private var enabled = true
    @State private var auth: AuthChoice = .none
    @State private var bearerToken = ""
    @State private var clientID = ""
    @State private var headers: [HeaderDraft] = []
    @State private var tools: [ToolDraft] = []
    @State private var status = ""
    @State private var testing = false
    @State private var browser = BrowserAuthorization()
    @State private var loaded = false

    private var isNew: Bool { original == nil }
    private var readOnly: Bool { managed }
    private var existingBearerAccount: String? { original?.credentialAccount }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isNew ? "Add MCP server" : (readOnly ? "MCP server (managed)" : "Edit MCP server"))
                .font(.title3).padding([.top, .horizontal], 20)
            Form {
                Section("Server") {
                    TextField("ID", text: $serverID, prompt: Text("letters, digits, _ or -"))
                        .disabled(!isNew || readOnly)
                    TextField("Display name", text: $title)
                    TextField("URL", text: $endpoint, prompt: Text("https://mcp.example.com/mcp"))
                    Toggle("Enabled", isOn: $enabled)
                }
                .disabled(readOnly)
                Section("Authentication") {
                    Picker("Mode", selection: $auth) { ForEach(AuthChoice.allCases) { Text($0.rawValue).tag($0) } }
                    switch auth {
                    case .none: EmptyView()
                    case .bearer:
                        SecureField("Token", text: $bearerToken,
                                    prompt: Text(existingBearerAccount == nil ? "Stored in your Keychain" : "Leave blank to keep the saved token"))
                        Text("Keychain account: \(bearerAccount)").font(.caption).foregroundStyle(.secondary)
                    case .oauth:
                        TextField("Client ID", text: $clientID, prompt: Text("Registered native public client"))
                        Text("Callback: \(Brand.identity)://oauth-callback. Sign-in opens in your browser on first use.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(readOnly)
                Section {
                    ForEach($headers) { $header in
                        HStack {
                            TextField("Name", text: $header.name).frame(maxWidth: 170)
                            if header.secret {
                                SecureField("Value", text: $header.value,
                                            prompt: Text(header.existingAccount == nil ? "Secret value" : "Leave blank to keep"))
                            } else {
                                TextField("Value", text: $header.value)
                            }
                            Toggle("Secret", isOn: $header.secret).toggleStyle(.checkbox)
                            Button { headers.removeAll { $0.id == header.id } } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless).help("Remove header")
                        }
                    }
                    Button { headers.append(HeaderDraft()) } label: { Label("Add header", systemImage: "plus") }
                        .disabled(headers.count >= MCPHeaderPolicy.maxHeaders)
                } header: {
                    Text("Custom headers")
                } footer: {
                    Text("Secret values are stored in your Keychain; only the header name is saved in configuration. Protocol headers (Host, Content-Type, Accept, Mcp-Session-Id, Cookie, Proxy-*, and others) cannot be set.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .disabled(readOnly)
                Section {
                    HStack {
                        Button(testing ? "Testing…" : "Test connection") { testConnection() }.disabled(testing)
                        if testing { ProgressView().controlSize(.small) }
                    }
                    if tools.isEmpty {
                        Text("No tools approved. Test the connection to choose tools.").foregroundStyle(.secondary)
                    }
                    ForEach($tools) { $tool in
                        HStack(alignment: .top) {
                            Toggle(isOn: $tool.allowed) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tool.name).font(.body.monospaced())
                                    if !tool.description.isEmpty {
                                        Text(tool.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                    if !tool.schemaSupported {
                                        Text("Input schema uses unsupported JSON Schema features; this tool cannot be approved.")
                                            .font(.caption).foregroundStyle(.orange)
                                    } else if !tool.offered && !tools.allSatisfy({ !$0.offered }) {
                                        Text("Not offered by the server in the last test.").font(.caption).foregroundStyle(.orange)
                                    }
                                }
                            }
                            .toggleStyle(.checkbox)
                            .disabled(!tool.schemaSupported && !tool.allowed)
                            Spacer()
                            Toggle("Ask before running", isOn: $tool.requiresConfirmation)
                                .toggleStyle(.checkbox).disabled(!tool.allowed)
                        }
                        .disabled(readOnly)
                    }
                } header: {
                    Text("Approved tools")
                } footer: {
                    Text("Tools the server offers but you do not approve stay blocked. \"Ask before running\" requires your confirmation for every call.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            HStack {
                Text(status).font(.caption).lineLimit(3)
                Spacer()
                Button(readOnly ? "Close" : "Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                if !readOnly {
                    Button("Save") { save() }.keyboardShortcut(.defaultAction).disabled(testing)
                }
            }
            .padding(20)
        }
        .frame(width: 640, height: 620)
        .onAppear(perform: load)
    }

    private var bearerAccount: String {
        existingBearerAccount ?? MCPServerStore.bearerAccount(serverID: serverID.isEmpty ? "<id>" : serverID)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let original else { return }
        serverID = original.id; title = original.title; endpoint = original.endpoint.absoluteString; enabled = original.isEnabled
        switch original.authMode {
        case .none: auth = .none
        case .bearer: auth = .bearer
        case .oauth(let id): auth = .oauth; clientID = id
        }
        headers = (original.headers ?? []).map {
            HeaderDraft(name: $0.name, secret: $0.isSecret, value: $0.value ?? "", existingAccount: $0.secretAccount)
        }
        tools = original.tools.map { ToolDraft(name: $0.name, allowed: true, requiresConfirmation: $0.requiresConfirmation) }
    }

    /// Builds the spec and the unsaved secrets (Keychain account → value) from the form.
    private func draft() throws -> (MCPServerSpec, [String: String]) {
        let id = serverID.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespaces)) else { throw AgentError.rejected("Enter a valid URL.") }
        var secrets: [String: String] = [:]
        var credentialAccount: String?
        var oauth: OAuthSpec?
        switch auth {
        case .none: break
        case .bearer:
            let account = existingBearerAccount ?? MCPServerStore.bearerAccount(serverID: id)
            credentialAccount = account
            if !bearerToken.isEmpty { secrets[account] = bearerToken }
            else if existingBearerAccount == nil { throw AgentError.rejected("Enter the bearer token.") }
        case .oauth:
            oauth = OAuthSpec(clientID: clientID.trimmingCharacters(in: .whitespaces))
        }
        let headerSpecs: [MCPHeaderSpec] = try headers.map { draft in
            let name = draft.name.trimmingCharacters(in: .whitespaces)
            guard draft.secret else { return MCPHeaderSpec(name: name, value: draft.value) }
            // Keep an existing account only for the same header name; otherwise the editor owns a fresh one.
            let reuse = draft.existingAccount.flatMap { account in
                original?.headers?.first(where: { $0.secretAccount == account && $0.name.lowercased() == name.lowercased() }) != nil ? account : nil
            }
            let account = reuse ?? MCPServerStore.headerSecretAccount(serverID: id, headerName: name)
            if !draft.value.isEmpty { secrets[account] = draft.value }
            else if reuse == nil { throw AgentError.rejected("Enter a value for secret header \(name).") }
            return MCPHeaderSpec(name: name, secretAccount: account)
        }
        let rules = tools.filter(\.allowed).map { ToolRule(name: $0.name, requiresConfirmation: $0.requiresConfirmation) }
        let spec = MCPServerSpec(id: id, title: title.trimmingCharacters(in: .whitespaces), endpoint: url,
                                 credentialAccount: credentialAccount, tools: rules, oauth: oauth,
                                 enabled: enabled ? nil : false, headers: headerSpecs.isEmpty ? nil : headerSpecs)
        return (spec, secrets)
    }

    private func save() {
        do {
            let (spec, secrets) = try draft()
            try MCPServerStore().save(spec, secrets: secrets, replacing: original?.id)
            onSaved("Saved \(spec.title).")
            dismiss()
        } catch { status = error.localizedDescription }
    }

    private func testConnection() {
        let spec: MCPServerSpec
        let secrets: [String: String]
        do {
            if readOnly {
                // Managed: test exactly the policy's server, with saved credentials only.
                guard let original else { return }
                spec = original; secrets = [:]
            } else {
                (spec, secrets) = try draft()
            }
        } catch { status = error.localizedDescription; return }
        testing = true; status = "Connecting to \(spec.endpoint.host ?? "server")…"
        let browser = browser
        Task {
            do {
                // Core re-resolves policy and restricts testing to policy servers when management is active.
                let found = try await MCPServerProbe.discoverToolsUnderCurrentPolicy(spec, secretOverrides: secrets,
                                                                                     authorizationDelegate: browser)
                merge(found)
                status = found.isEmpty ? "Connected. The server offers no tools." : "Connected. \(found.count) tool(s) offered."
            } catch let failure as AgentError {
                status = failure.localizedDescription
            } catch {
                // Remote error text can contain server content; show a fixed message instead.
                status = "Could not connect. Check the URL, network, authentication and headers."
            }
            testing = false
        }
    }

    private func merge(_ found: [DiscoveredTool]) {
        var merged = found.map { tool in
            let existing = tools.first { $0.name == tool.name }
            return ToolDraft(name: tool.name, description: tool.description,
                             allowed: (existing?.allowed ?? false) && tool.schemaSupported,
                             requiresConfirmation: existing?.requiresConfirmation ?? true,
                             schemaSupported: tool.schemaSupported, offered: true)
        }
        // Keep approved tools the server did not list this time; they stay visible so removal is explicit.
        for tool in tools where tool.allowed && !found.contains(where: { $0.name == tool.name }) {
            var kept = tool; kept.offered = false; merged.append(kept)
        }
        tools = merged
    }
}
