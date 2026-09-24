import Foundation
import LocalAgentCore

/// What the command bar is showing. Derived from `AppState` by `CommandBarModel.resolve`, never stored,
/// so the bar can only ever display what the core already decided (no UI-side approval or policy state).
enum CommandBarPhase: Equatable, Sendable {
    /// Configuration unavailable or invalid. Requests are blocked (invalid forced policy fails closed).
    case locked
    case idle
    case typing
    /// The bundled runtime is loading the model for this task.
    case modelStarting
    case running
    /// The core is waiting for the user's decision on a tool call.
    case approval
    case result
    case error
}

/// Where the model call goes, for the chip. Derived from the core's `InferenceDestination` (ADR 0011), which is
/// the same classification the workspace window and diagnostics use; the bar adds only short labels.
enum Destination: Equatable, Sendable {
    case local
    case lan(host: String, encrypted: Bool)
    case cloud(host: String)
    case none

    init(_ destination: InferenceDestination?, host: String) {
        switch destination {
        case .thisMac?: self = .local
        case .lan(let host, let encrypted)?: self = .lan(host: host, encrypted: encrypted)
        case .cloud?: self = .cloud(host: host)
        case nil: self = .none
        }
    }
    /// Short chip text. LAN destinations disclose the transport; the full disclosure is in `spoken`.
    var label: String {
        switch self {
        case .local: "On this Mac"
        case .lan(let host, true): "LAN · TLS · \(host)"
        case .lan(let host, false): "LAN · unencrypted · \(host)"
        case .cloud(let host): host.isEmpty ? "Cloud" : "Cloud · \(host)"
        case .none: "No model"
        }
    }
    /// VoiceOver text. For LAN it is the core's own disclosure line (request and tool results go to that host).
    var spoken: String {
        switch self {
        case .lan(let host, let encrypted): InferenceDestination.lan(host: host, encrypted: encrypted).label
        default: label
        }
    }
    var symbol: String {
        switch self {
        case .local: "desktopcomputer"
        case .lan(_, true): "network"
        case .lan(_, false): "network.badge.shield.half.filled"
        case .cloud: "cloud"
        case .none: "questionmark.circle"
        }
    }
}

/// Plain facts the bar needs. `AppState` fills this in; tests fill it in directly.
struct CommandBarInputs: Equatable, Sendable {
    var configurationAvailable = true
    var managed = false
    var busy = false
    var input = ""
    var result = ""
    var error: String?
    var proposal: ProposalSummary?
    var runtimeState: RuntimeState = .stopped
    var usesManagedRuntime = false
    var providerKind: ProviderSpec.Kind?
    /// The core's classification of the selected provider (`ProviderSpec.destination`); nil when no model is selected.
    var destination: InferenceDestination?
    /// Host shown for cloud gateways (the core's `.cloud` case carries no host).
    var providerHost = ""
    var modelTitle = ""
    var inputLimit = 0
    var serverCount = 0
}

/// Presentation copy of a `ToolProposal`. The decision itself still goes through `AppState.decide`.
struct ProposalSummary: Equatable, Sendable {
    let server: String
    let tool: String
    let arguments: String
    init(server: String, tool: String, arguments: String) { self.server = server; self.tool = tool; self.arguments = arguments }
    init(_ proposal: ToolProposal) { self.init(server: proposal.server, tool: proposal.tool, arguments: proposal.arguments) }
}

struct CommandBarModel: Equatable, Sendable {
    var phase: CommandBarPhase
    var destination: Destination
    var modelTitle: String
    /// One short line under the input while something is happening. Content-free.
    var statusLine: String
    var runtimeState: RuntimeState
    var managed: Bool
    var inputBytes: Int
    var inputLimit: Int
    var serverCount: Int
    var canSubmit: Bool
    var result: String
    var errorMessage: String?
    var proposal: ProposalSummary?

    static func resolve(_ inputs: CommandBarInputs) -> CommandBarModel {
        let trimmed = inputs.input.trimmingCharacters(in: .whitespacesAndNewlines)
        let bytes = inputs.input.utf8.count
        let phase: CommandBarPhase
        if !inputs.configurationAvailable { phase = .locked }
        else if inputs.proposal != nil { phase = .approval }
        else if inputs.busy { phase = inputs.usesManagedRuntime && inputs.runtimeState == .starting ? .modelStarting : .running }
        else if inputs.error != nil { phase = .error }
        else if !inputs.result.isEmpty { phase = .result }
        else if !trimmed.isEmpty { phase = .typing }
        else { phase = .idle }

        let destination = Destination(inputs.destination, host: inputs.providerHost)

        let status: String
        switch phase {
        case .locked: status = inputs.managed ? "Managed policy could not be applied. Requests are blocked." : "Configuration could not be loaded."
        case .modelStarting: status = "Starting local model…"
        case .running:
            switch destination {
            case .local: status = inputs.usesManagedRuntime ? "Working on this Mac…" : "Working with the local model…"
            case .lan: status = "Working with the model on your network…"
            case .cloud, .none: status = "Working through your gateway…"
            }
        case .approval: status = "Waiting for your decision"
        case .result: status = "Done"
        case .error: status = "Could not complete"
        case .idle, .typing:
            if inputs.usesManagedRuntime {
                switch inputs.runtimeState {
                case .ready: status = "Local model loaded"
                case .stopped: status = "Local model starts with your next task"
                case .starting, .stopping, .failed: status = inputs.runtimeState.summary
                }
            } else { status = "" }
        }

        let canSubmit = phase != .locked && !inputs.busy && !trimmed.isEmpty && inputs.providerKind != nil
            && (inputs.inputLimit == 0 || bytes <= inputs.inputLimit)
        return CommandBarModel(phase: phase, destination: destination, modelTitle: inputs.modelTitle, statusLine: status,
                               runtimeState: inputs.runtimeState, managed: inputs.managed, inputBytes: bytes,
                               inputLimit: inputs.inputLimit, serverCount: inputs.serverCount, canSubmit: canSubmit,
                               result: inputs.result, errorMessage: inputs.error, proposal: inputs.proposal)
    }

    /// Mark state for the status dot: running while the core works, ring when ready, none when locked.
    var markState: MinimodeMark.State {
        switch phase {
        case .locked: .off
        case .running, .modelStarting, .approval: .active
        default: .idle
        }
    }
}

/// Commands the bar can send. Everything routes to `AppState`; the bar holds no policy or approval logic.
struct CommandBarActions {
    var submit: () -> Void = {}
    var cancel: () -> Void = {}
    var approve: () -> Void = {}
    var deny: () -> Void = {}
    var dismiss: () -> Void = {}
    var clear: () -> Void = {}
    var copyResult: () -> Void = {}
    var openSettings: () -> Void = {}
    var openWorkspace: () -> Void = {}
    var unloadModel: () -> Void = {}
    var selectModel: (String) -> Void = { _ in }
}

/// One row in the ⌘K action panel.
struct BarAction: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String
    let shortcut: String?
    var destructive = false
}

extension CommandBarModel {
    /// The actions available in the current phase. Order is the on-screen order.
    func actions(models: [(id: String, title: String)], selectedModel: String) -> [BarAction] {
        var list: [BarAction] = []
        switch phase {
        case .result:
            list.append(BarAction(id: "copy", title: "Copy result", symbol: "doc.on.doc", shortcut: "⌘C"))
            list.append(BarAction(id: "clear", title: "New task", symbol: "sparkles", shortcut: "⌘N"))
        case .error:
            list.append(BarAction(id: "clear", title: "Dismiss error", symbol: "xmark.circle", shortcut: "⌘N"))
        case .running, .modelStarting:
            list.append(BarAction(id: "cancel", title: "Stop task", symbol: "stop.circle", shortcut: "⌘.", destructive: true))
        case .approval:
            list.append(BarAction(id: "approve", title: "Approve once", symbol: "checkmark.shield", shortcut: "⌘↩"))
            list.append(BarAction(id: "deny", title: "Deny", symbol: "hand.raised", shortcut: "⌘⌫", destructive: true))
        case .idle, .typing, .locked: break
        }
        if phase != .locked, !busy, models.count > 1 {
            for model in models where model.id != selectedModel {
                list.append(BarAction(id: "model:\(model.id)", title: "Switch to \(model.title)", symbol: "arrow.triangle.2.circlepath", shortcut: nil))
            }
        }
        if runtimeState == .ready, !busy {
            list.append(BarAction(id: "unload", title: "Unload local model", symbol: "memorychip", shortcut: nil))
        }
        list.append(BarAction(id: "workspace", title: "Open workspace window", symbol: "macwindow", shortcut: "⌘O"))
        list.append(BarAction(id: "settings", title: "Settings…", symbol: "gearshape", shortcut: "⌘,"))
        return list
    }
    var busy: Bool { phase == .running || phase == .modelStarting || phase == .approval }
}
