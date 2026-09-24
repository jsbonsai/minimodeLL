import SwiftUI
import LocalAgentCore

/// Command bar geometry shared by the view and the panel controller.
enum CommandBarLayout {
    static let width: CGFloat = 680
    static let headerHeight: CGFloat = 62
    static let footerHeight: CGFloat = 38
    static let horizontalInset: CGFloat = 18
    static let resultMaxHeight: CGFloat = 320
    static let argumentsMaxHeight: CGFloat = 150
    static let actionPanelWidth: CGFloat = 300
}

/// Transient interaction state that is not policy: the ⌘K panel, keyboard selection and focus requests.
@MainActor @Observable final class CommandBarSession {
    var showActions = false
    /// False for the first frame after the panel is ordered front; the entrance animates it to true.
    var presented = true
    var actionSelection = 0
    var suggestionSelection = 0
    var focusToken = 0
    var copied = false
    /// False for a short arming window after an approval card appears, so a ⌘↩ or click that was meant for
    /// another app cannot approve a tool action that had not been seen yet (`CommandBarController.armApproval`).
    var approvalArmed = false
    /// The shortcut currently registered with the system, or nil when registration failed. Observable so
    /// Settings → Command Bar shows the live status after Apply.
    var registeredHotkey: Hotkey?
    /// Reported card height (unanimated target after each layout pass); the panel follows it.
    var onHeightChange: (CGFloat) -> Void = { _ in }
}

/// Spoken names for key caps, so VoiceOver reads "Command Return" rather than a string of symbols.
enum Keycap {
    static func spoken(_ keys: String) -> String {
        let names: [Character: String] = ["⌘": "Command", "⇧": "Shift", "⌥": "Option", "⌃": "Control",
                                          "↩": "Return", "⌫": "Delete", "↑": "Up arrow", "↓": "Down arrow", "⎋": "Escape"]
        if keys.lowercased() == "esc" { return "Escape" }
        var parts: [String] = []
        var plain = ""
        for character in keys {
            if let name = names[character] {
                if !plain.isEmpty { parts.append(plain); plain = "" }
                parts.append(name)
            } else { plain.append(character) }
        }
        if !plain.isEmpty { parts.append(plain == "," ? "Comma" : plain == "." ? "Period" : plain.uppercased()) }
        return parts.joined(separator: " ")
    }
}

struct ModelChoice: Identifiable, Equatable {
    let id: String
    let title: String
}

/// Starter prompts shown while the bar is empty. ↑↓ selects, ↩ inserts. They are text only; nothing runs.
struct Suggestion: Identifiable, Equatable {
    let id: String
    let symbol: String
    let title: String
    let insert: String
    static let all = [
        Suggestion(id: "summarize", symbol: "text.quote", title: "Summarize a passage", insert: "Summarize this: "),
        Suggestion(id: "reply", symbol: "envelope", title: "Draft a short reply", insert: "Draft a short reply to: "),
        Suggestion(id: "explain", symbol: "questionmark.bubble", title: "Explain something plainly", insert: "Explain in plain terms: ")
    ]
}

private struct CardHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    // Siblings without a value (the hidden ⌘K panel) contribute the default; keep the card's measurement.
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// The floating command bar. Pure presentation: every action is a closure into `AppState`.
struct CommandBarView: View {
    let model: CommandBarModel
    @Binding var input: String
    var session: CommandBarSession
    let models: [ModelChoice]
    let selectedModel: String
    let hotkey: String
    let actions: CommandBarActions
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                header
                body(for: model.phase)
                Spacer(minLength: 0)
                footer
            }
            // The card opens far enough for the ⌘K panel to sit above the footer inside the window.
            .frame(minHeight: session.showActions ? ActionPanel.estimatedHeight(rows: barActions.count) + CommandBarLayout.footerHeight + Space.sm * 2 : 0, alignment: .top)
            .frame(width: CommandBarLayout.width)
            // Take the card's natural height even when the hosting window is still the previous size.
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: CardHeightKey.self, value: proxy.size.height)
            })
            .cardChrome()
            if session.showActions {
                ActionPanel(actions: barActions, selection: session.actionSelection, perform: perform(_:))
                    .padding(.trailing, Space.md)
                    .padding(.bottom, CommandBarLayout.footerHeight + Space.sm)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.96, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .motion(Motion.expand, value: model.phase)
        .motion(Motion.expand, value: session.showActions)
        // Entrance: a 2 % scale-in with the window's fade. Under Reduce Motion the scale is skipped.
        .scaleEffect(session.presented || reduceMotion ? 1 : 0.98, anchor: .top)
        .onPreferenceChange(CardHeightKey.self) { height in
            Task { @MainActor in session.onHeightChange(height) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(Brand.displayName) command bar")
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Space.md) {
            MinimodeMark(state: model.markState, ink: palette.text, dot: palette.accent)
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
            CommandInput(text: $input, session: session, disabled: model.phase == .locked || model.busy)
            DestinationChip(model: model)
        }
        .padding(.horizontal, CommandBarLayout.horizontalInset)
        .frame(height: CommandBarLayout.headerHeight)
    }

    // MARK: Body sections

    @ViewBuilder private func body(for phase: CommandBarPhase) -> some View {
        let transition = SectionTransition.transition(reduceMotion: reduceMotion)
        switch phase {
        case .idle:
            SuggestionList(selection: session.suggestionSelection, choose: apply(_:)).transition(transition)
        case .typing:
            EmptyView()
        case .modelStarting, .running:
            ProgressSection(status: model.statusLine).transition(transition)
        case .approval:
            if let proposal = model.proposal {
                ApprovalCard(proposal: proposal, armed: session.approvalArmed, approve: actions.approve, deny: actions.deny).transition(transition)
            }
        case .result:
            ResultSection(text: model.result).transition(transition)
        case .error:
            NoticeSection(kind: .error, title: "Could not complete", message: model.errorMessage ?? "").transition(transition)
        case .locked:
            NoticeSection(kind: .locked, title: model.managed ? "Managed policy locked" : "Configuration unavailable",
                          message: model.statusLine).transition(transition)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: Space.md) {
            footerStatus
            Spacer(minLength: Space.md)
            footerHints
        }
        .font(Typography.caption)
        .foregroundStyle(palette.muted)
        .padding(.horizontal, CommandBarLayout.horizontalInset)
        .frame(height: CommandBarLayout.footerHeight)
        .overlay(alignment: .top) { Rectangle().fill(palette.border).frame(height: 1) }
    }

    @ViewBuilder private var footerStatus: some View {
        switch model.phase {
        case .running, .modelStarting:
            Label { Text("Fresh context · stops with ⌘.") } icon: { PulseDot(color: palette.accent) }
        case .approval:
            Label { Text("Nothing runs until you decide") } icon: { Circle().fill(palette.warning).frame(width: 7, height: 7) }
        case .locked:
            Label { Text("Requests are blocked") } icon: { Circle().fill(palette.blocked).frame(width: 7, height: 7) }
        case .error:
            Label { Text("Could not complete · nothing was retried") } icon: { Circle().fill(palette.blocked).frame(width: 7, height: 7) }
        case .result:
            Label { Text("Done · fresh context next time") } icon: { Circle().fill(palette.running).frame(width: 7, height: 7) }
        default:
            if !model.statusLine.isEmpty {
                Label { Text(model.statusLine) } icon: { runtimeDot }
            } else {
                Text(model.serverCount == 0 ? "Fresh context every task · no tool servers" : "Fresh context every task · \(model.serverCount) tool server\(model.serverCount == 1 ? "" : "s")")
            }
        }
    }

    @ViewBuilder private var runtimeDot: some View {
        switch model.runtimeState {
        case .ready: Circle().fill(palette.running).frame(width: 7, height: 7)
        case .starting, .stopping: PulseDot(color: palette.warning)
        case .failed: Circle().fill(palette.blocked).frame(width: 7, height: 7)
        case .stopped: Circle().strokeBorder(palette.muted, lineWidth: 1.5).frame(width: 7, height: 7)
        }
    }

    @ViewBuilder private var footerHints: some View {
        HStack(spacing: Space.lg) {
            switch model.phase {
            case .idle: KeyHint("Insert", "↩"); KeyHint("Navigate", "↑↓")
            case .typing:
                if model.inputLimit > 0, model.inputBytes > model.inputLimit * 3 / 4 {
                    Text("\(model.inputBytes) / \(model.inputLimit) bytes").monospacedDigit()
                        .foregroundStyle(model.inputBytes > model.inputLimit ? palette.blockedInk : palette.muted)
                }
                KeyHint("Run", "↩")
            case .running, .modelStarting: KeyHint("Hide", "esc")
            case .approval: KeyHint("Deny", "⌘⌫"); KeyHint("Approve", "⌘↩")
            case .result: KeyHint("Copy", "⌘C"); KeyHint("New", "⌘N")
            case .error: KeyHint("Dismiss", "⌘N")
            case .locked: KeyHint("Settings", "⌘,")
            }
            KeyHint("Actions", "⌘K")
        }
    }

    // MARK: Actions

    private var barActions: [BarAction] {
        model.actions(models: models.map { ($0.id, $0.title) }, selectedModel: selectedModel)
    }

    private func apply(_ suggestion: Suggestion) {
        input = suggestion.insert
        session.focusToken += 1
    }

    func perform(_ action: BarAction) {
        session.showActions = false
        switch action.id {
        case "copy": actions.copyResult()
        case "clear": actions.clear()
        case "cancel": actions.cancel()
        case "approve": actions.approve()
        case "deny": actions.deny()
        case "unload": actions.unloadModel()
        case "workspace": actions.openWorkspace()
        case "settings": actions.openSettings()
        default:
            if action.id.hasPrefix("model:") { actions.selectModel(String(action.id.dropFirst(6))) }
        }
    }
}

// MARK: - Header pieces

struct CommandInput: View {
    @Binding var text: String
    var session: CommandBarSession
    var disabled: Bool
    @Environment(\.palette) private var palette
    @Environment(\.staticLayout) private var staticLayout
    @FocusState private var focused: Bool
    var body: some View {
        if staticLayout {
            // ImageRenderer cannot draw AppKit-backed text fields; show the same text with a caret.
            HStack(spacing: 1) {
                Text(text.isEmpty ? "What can we get done?" : text).font(Typography.input)
                    .foregroundStyle(text.isEmpty ? palette.muted : palette.text).lineLimit(1)
                if !text.isEmpty { RoundedRectangle(cornerRadius: 1).fill(palette.accent).frame(width: 2, height: 22) }
                Spacer(minLength: 0)
            }
            .opacity(disabled ? 0.6 : 1)
        } else {
            field
        }
    }
    private var field: some View {
        TextField("", text: $text, prompt: Text("What can we get done?").foregroundStyle(palette.muted), axis: .vertical)
            .textFieldStyle(.plain)
            .font(Typography.input)
            .foregroundStyle(palette.text)
            .lineLimit(1...4)
            .focused($focused)
            .disabled(disabled)
            .opacity(disabled ? 0.6 : 1)
            .accessibilityLabel("Task request")
            .onAppear { focused = true }
            .onChange(of: session.focusToken) { focused = true }
    }
}

/// Model name plus destination, with a dot that mirrors the runtime state. Read-only; switching is in ⌘K.
struct DestinationChip: View {
    let model: CommandBarModel
    @Environment(\.palette) private var palette
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: model.destination.symbol).font(.system(size: 10.5, weight: .semibold))
            if !model.modelTitle.isEmpty {
                Text(model.modelTitle).lineLimit(1)
                Text("·").foregroundStyle(palette.muted.opacity(0.6))
            }
            Text(model.destination.label).lineLimit(1)
            if model.managed { Image(systemName: "lock.fill").font(.system(size: 9, weight: .semibold)) }
        }
        .font(Typography.captionStrong)
        .foregroundStyle(palette.muted)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .insetSurface(radius: Radius.md)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
    }
    /// "Model Qwen3 4B, On this Mac, managed by your organization"; without a selected model, just the destination.
    private var spokenLabel: String {
        var parts: [String] = []
        if !model.modelTitle.isEmpty { parts.append("Model \(model.modelTitle)") }
        parts.append(model.destination.spoken)
        if model.managed { parts.append("managed by your organization") }
        return parts.joined(separator: ", ")
    }
}

/// Key-cap hint used in the footer and action panel: `Run ↩`.
struct KeyHint: View {
    let label: String
    let keys: String
    @Environment(\.palette) private var palette
    init(_ label: String, _ keys: String) { self.label = label; self.keys = keys }
    var body: some View {
        HStack(spacing: 5) {
            Text(label)
            Text(keys).font(Typography.keycap).foregroundStyle(palette.text)
                .padding(.horizontal, 5).frame(height: 17).insetSurface(radius: 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(Keycap.spoken(keys))")
    }
}

// MARK: - Sections

struct SuggestionList: View {
    let selection: Int
    let choose: (Suggestion) -> Void
    @Environment(\.palette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Start with").font(Typography.captionStrong).foregroundStyle(palette.muted)
                .padding(.horizontal, Space.md).padding(.top, Space.sm).padding(.bottom, Space.xs)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(Suggestion.all.enumerated()), id: \.element.id) { index, suggestion in
                Button { choose(suggestion) } label: {
                    HStack(spacing: Space.md) {
                        Image(systemName: suggestion.symbol).font(.system(size: 13, weight: .medium))
                            .frame(width: 22, height: 22).foregroundStyle(index == selection ? palette.accent : palette.muted)
                            .insetSurface(radius: Radius.sm)
                            .accessibilityHidden(true)
                        Text(suggestion.title).font(Typography.label).foregroundStyle(palette.text)
                        Spacer()
                        if index == selection { Text("↩").font(Typography.keycap).foregroundStyle(palette.muted).accessibilityHidden(true) }
                    }
                    .padding(.horizontal, Space.md).frame(height: 36)
                    .background(index == selection ? palette.accentWash : .clear, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(index == selection ? .isSelected : [])
            }
        }
        .padding(.horizontal, Space.sm).padding(.bottom, Space.sm)
        .overlay(alignment: .top) { Rectangle().fill(palette.border).frame(height: 1) }
        .motion(Motion.quick, value: selection)
    }
}

struct ProgressSection: View {
    let status: String
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep = false
    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(spacing: Space.sm) {
                PulseDot(color: palette.accent)
                Text(status).font(Typography.label).foregroundStyle(palette.text)
                Spacer()
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.border)
                    Capsule().fill(palette.accent)
                        .frame(width: reduceMotion ? proxy.size.width : proxy.size.width * 0.28)
                        .offset(x: reduceMotion ? 0 : (sweep ? proxy.size.width * 0.72 : 0))
                        .opacity(reduceMotion ? 0.5 : 1)
                }
            }
            .frame(height: 3)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { sweep = true }
            }
            .accessibilityHidden(true)
        }
        .padding(.horizontal, CommandBarLayout.horizontalInset).padding(.vertical, Space.lg)
        .overlay(alignment: .top) { Rectangle().fill(palette.border).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }
}

/// Inline approval. Presentation only: both buttons call `AppState.decide`, which the core awaits. While
/// `armed` is false (the first ~0.6 s after the card appears) both buttons are disabled, matching the key map.
struct ApprovalCard: View {
    let proposal: ProposalSummary
    var armed = true
    let approve: () -> Void
    let deny: () -> Void
    @Environment(\.palette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(spacing: Space.sm) {
                Image(systemName: "checkmark.shield").font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.warningInk)
                    .accessibilityHidden(true)
                Text("Review tool action").font(Typography.title).accessibilityAddTraits(.isHeader)
                Spacer()
                Text("Approval required").font(Typography.captionStrong).foregroundStyle(palette.warningInk)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(palette.warning.opacity(0.12), in: Capsule())
            }
            HStack(spacing: Space.sm) {
                Text(proposal.server).font(Typography.labelStrong)
                Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold)).foregroundStyle(palette.muted)
                    .accessibilityHidden(true)
                Text(proposal.tool).font(Typography.labelStrong).foregroundStyle(palette.accent)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Server \(proposal.server), tool \(proposal.tool)")
            BoundedScroll(maxHeight: CommandBarLayout.argumentsMaxHeight) {
                Text(proposal.arguments).font(Typography.mono).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(Space.md)
            }
            .insetSurface(radius: Radius.md)
            .accessibilityLabel("Tool arguments")
            Text("These arguments were generated by the model. Approving runs this action once; nothing else is authorized.")
                .font(Typography.caption).foregroundStyle(palette.muted)
            HStack(spacing: Space.sm) {
                Spacer()
                Button(action: deny) { HStack(spacing: 6) { Text("Deny"); Text("⌘⌫").font(Typography.keycap).opacity(0.7).accessibilityHidden(true) } }
                    .buttonStyle(BarButtonStyle(prominent: false))
                    .accessibilityLabel("Deny").accessibilityHint("Command Delete")
                Button(action: approve) { HStack(spacing: 6) { Text("Approve once"); Text("⌘↩").font(Typography.keycap).opacity(0.8).accessibilityHidden(true) } }
                    .buttonStyle(BarButtonStyle(prominent: true))
                    .accessibilityLabel("Approve once").accessibilityHint("Command Return")
            }
            .disabled(!armed)
        }
        .padding(.horizontal, CommandBarLayout.horizontalInset).padding(.vertical, Space.lg)
        .overlay(alignment: .top) { Rectangle().fill(palette.border).frame(height: 1) }
    }
}

struct ResultSection: View {
    let text: String
    @Environment(\.palette) private var palette
    var body: some View {
        BoundedScroll(maxHeight: CommandBarLayout.resultMaxHeight) {
            Text(text).font(Typography.body).lineSpacing(3).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, CommandBarLayout.horizontalInset).padding(.vertical, Space.lg)
        }
        .overlay(alignment: .top) { Rectangle().fill(palette.border).frame(height: 1) }
        .accessibilityLabel("Result")
    }
}

struct NoticeSection: View {
    enum Kind { case error, locked }
    let kind: Kind
    let title: String
    let message: String
    @Environment(\.palette) private var palette
    var body: some View {
        HStack(alignment: .top, spacing: Space.md) {
            Image(systemName: kind == .error ? "exclamationmark.circle" : "lock.shield")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.blockedInk)
                .frame(width: 28, height: 28).insetSurface(radius: Radius.sm)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Typography.title)
                if !message.isEmpty { Text(message).font(Typography.label).foregroundStyle(palette.muted).textSelection(.enabled) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, CommandBarLayout.horizontalInset).padding(.vertical, Space.lg)
        .overlay(alignment: .top) { Rectangle().fill(palette.border).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }
}

/// ⌘K panel: a compact list anchored above the footer, navigated with ↑↓ and ↩.
struct ActionPanel: View {
    let actions: [BarAction]
    let selection: Int
    let perform: (BarAction) -> Void
    @Environment(\.palette) private var palette
    static let rowHeight: CGFloat = 30
    /// Deterministic height (padding, heading, rows) so the card can open to fit the panel before it is measured.
    static func estimatedHeight(rows: Int) -> CGFloat { Space.sm * 2 + 28 + CGFloat(rows) * rowHeight + CGFloat(max(rows - 1, 0)) * 2 }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Actions").font(Typography.captionStrong).foregroundStyle(palette.muted)
                .padding(.horizontal, Space.md).padding(.top, Space.sm).padding(.bottom, Space.xs)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                Button { perform(action) } label: {
                    HStack(spacing: Space.sm) {
                        Image(systemName: action.symbol).font(.system(size: 12, weight: .medium)).frame(width: 18)
                            .foregroundStyle(action.destructive ? palette.blockedInk : (index == selection ? palette.accent : palette.muted))
                            .accessibilityHidden(true)
                        Text(action.title).font(Typography.label).foregroundStyle(action.destructive ? palette.blockedInk : palette.text)
                        Spacer()
                        if let shortcut = action.shortcut {
                            Text(shortcut).font(Typography.keycap).foregroundStyle(palette.muted)
                                .padding(.horizontal, 5).frame(height: 17).insetSurface(radius: 4)
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(.horizontal, Space.sm).frame(height: Self.rowHeight)
                    .background(index == selection ? palette.accentWash : .clear, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(action.title)
                .accessibilityHint(action.shortcut.map(Keycap.spoken) ?? "")
                .accessibilityAddTraits(index == selection ? .isSelected : [])
            }
        }
        .padding(Space.sm)
        .frame(width: CommandBarLayout.actionPanelWidth)
        .cardChrome(radius: Radius.lg, kind: .popover)
        .shadow(color: .black.opacity(palette.isDark ? 0.5 : 0.18), radius: 18, y: 8)
        .motion(Motion.quick, value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Actions")
    }
}

struct BarButtonStyle: ButtonStyle {
    var prominent: Bool
    @Environment(\.palette) private var palette
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.labelStrong)
            .foregroundStyle(prominent ? palette.onAccent : palette.text)
            .padding(.horizontal, 12).frame(height: 28)
            .background(prominent ? palette.accent : palette.inset, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(prominent ? .clear : palette.border, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .motion(Motion.quick, value: configuration.isPressed)
    }
}
