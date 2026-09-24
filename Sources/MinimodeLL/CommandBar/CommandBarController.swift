import AppKit
import SwiftUI
import LocalAgentCore

/// Owns the command bar panel, the global hotkey and the keyboard map. Everything the bar does goes through
/// `AppState`, so the core's policy and approval enforcement is unchanged.
@MainActor final class CommandBarController: NSObject, NSWindowDelegate {
    let state: AppState
    let session = CommandBarSession()
    private var panel: CommandBarPanel?
    private var hosting: NSHostingView<AnyView>?
    private var hotkey: GlobalHotkey?
    // Read in deinit (nonisolated); only ever written on the main actor.
    nonisolated(unsafe) private var keyMonitor: Any?
    private var lastHeight: CGFloat = CommandBarLayout.headerHeight
    nonisolated(unsafe) private var defaultsObserver: NSObjectProtocol?
    /// Incremented by every show/hide so a fade-out that is still running cannot order the panel out after a
    /// later `show()` (the completion handler compares its generation).
    private var hideGeneration = 0
    /// Approval arming (see `armApproval`). `approvalArmingDelay` is a property so tests can shorten it.
    private var armedProposalID: String?
    private var armingTask: Task<Void, Never>?
    var approvalArmingDelay: TimeInterval = 0.6

    init(state: AppState) {
        self.state = state
        super.init()
        session.onHeightChange = { [weak self] height in self?.cardHeightChanged(height) }
    }

    deinit {
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        armingTask?.cancel()
    }

    /// Registers the configured hotkey and starts watching the approval state. Idempotent.
    func install() {
        guard hotkey == nil else { return }
        hotkey = GlobalHotkey { [weak self] in self?.toggle() }
        registerConfiguredHotkey()
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.registerConfiguredHotkey() }
        }
        watchApprovals()
    }

    private func registerConfiguredHotkey() {
        let wanted = Hotkey.configured()
        guard wanted != registeredHotkey else { return }
        session.registeredHotkey = hotkey?.register(wanted) == true ? wanted : nil
    }

    /// Saves `hotkey` as the preference and registers it immediately. Returns false when the system refused the
    /// combination; the previous registration is then released (`GlobalHotkey.register`) and the status shows "—".
    @discardableResult
    func apply(_ hotkey: Hotkey) -> Bool {
        UserDefaults.standard.set(hotkey.storageString, forKey: Hotkey.defaultsKey)
        guard let global = self.hotkey else { return false }
        let ok = global.register(hotkey)
        session.registeredHotkey = ok ? hotkey : nil
        return ok
    }

    /// The shortcut registered with the system, or nil. Observable through `session`.
    var registeredHotkey: Hotkey? { session.registeredHotkey }
    var hotkeyLabel: String { registeredHotkey?.displayString ?? "—" }

    // MARK: Showing and hiding

    var isVisible: Bool { panel?.isVisible == true }

    /// Why the bar is being shown. An approval surfaces the panel without taking the keyboard, so a key the
    /// user is pressing in another app at that moment cannot land on Approve.
    enum ShowReason { case user, approval }

    /// Hotkey: hides a bar that has the keyboard; otherwise shows it, or gives an approval-surfaced bar the keyboard.
    func toggle() {
        if let panel, panel.isVisible, panel.isKeyWindow { hide() } else { show() }
    }

    func show(reason: ShowReason = .user) {
        let panel = makePanelIfNeeded()
        hideGeneration += 1 // cancels a pending order-out
        if panel.isVisible {
            // Either fully shown, or mid fade-out: restore the alpha and, for the user, take the keyboard.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.08
                panel.animator().alphaValue = 1
            }
            if reason == .user { takeKeyboard(panel) }
            return
        }
        session.showActions = false
        session.copied = false
        panel.place(height: lastHeight)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // The window only fades; the card's scale-in lives in SwiftUI so the window frame can keep following
        // the card's height while the entrance plays (an AppKit frame animation would fight `follow`).
        session.presented = false
        panel.alphaValue = 0
        switch reason {
        case .user: takeKeyboard(panel)
        case .approval: panel.orderFrontRegardless() // visible, not key: no key monitor until the hotkey or a click
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.08 : Motion.panelInSeconds
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        withAnimation(reduceMotion ? Motion.crossfade : Motion.panelIn) { session.presented = true }
    }

    private func takeKeyboard(_ panel: CommandBarPanel) {
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
        session.focusToken += 1
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        removeKeyMonitor()
        hideGeneration += 1
        let generation = hideGeneration
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = reduceMotion ? 0.05 : Motion.panelOutSeconds
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor [weak self] in
                guard let self, self.hideGeneration == generation else { return } // re-shown meanwhile
                panel.orderOut(nil)
                panel.alphaValue = 1
            }
        })
    }

    private func makePanelIfNeeded() -> CommandBarPanel {
        if let panel { return panel }
        let root = AnyView(CommandBarHost(state: state, session: session, controller: self).designRoot())
        let hosting = NSHostingView(rootView: root)
        // AppKit keeps the window's content size equal to the SwiftUI card's ideal size, including while the
        // card animates. The panel re-anchors its top edge on every resize (see `windowDidResize`).
        hosting.sizingOptions = [.preferredContentSize]
        let panel = CommandBarPanel(contentView: hosting)
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.escape() }
        self.panel = panel
        self.hosting = hosting
        return panel
    }

    private func cardHeightChanged(_ height: CGFloat) {
        lastHeight = height
        panel?.follow(height: height)
    }

    func windowDidResize(_ notification: Notification) {
        panel?.anchorTop()
    }

    /// A click on an approval-surfaced (non-key) panel makes it key; only then does the keyboard map apply.
    func windowDidBecomeKey(_ notification: Notification) {
        installKeyMonitor()
    }

    func windowDidResignKey(_ notification: Notification) {
        // Clicking elsewhere dismisses, like a system launcher. A pending approval stays pending in the core.
        hide()
    }

    // MARK: Keyboard map (see docs/design/raycast-redesign.md)

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // AppKit invokes local monitors on the main thread; NSEvent is not Sendable, so box it for the hop.
            let boxed = UncheckedBox(event)
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard let self, let panel = self.panel, boxed.value.window === panel else { return false }
                return self.handle(boxed.value)
            }
            return consumed ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func escape() {
        if session.showActions { session.showActions = false } else { hide() }
    }

    /// Returns true when the event was consumed. Special keys are matched by key code (layout independent);
    /// letter and punctuation shortcuts by `charactersIgnoringModifiers`, so ⌘K is ⌘K on every keyboard layout.
    func handle(_ event: NSEvent) -> Bool {
        armApproval(for: state.proposal)
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        let command = flags == .command
        let plain = flags.isEmpty
        let model = CommandBarModel.resolve(state.commandBarInputs)
        let actions = currentActions(model)
        switch event.keyCode {
        case 53: // esc
            escape(); return true
        case 126 where plain: // ↑
            if session.showActions { session.actionSelection = max(0, session.actionSelection - 1); return true }
            if model.phase == .idle { session.suggestionSelection = max(0, session.suggestionSelection - 1); return true }
            return false
        case 125 where plain: // ↓
            if session.showActions { session.actionSelection = min(actions.count - 1, session.actionSelection + 1); return true }
            if model.phase == .idle { session.suggestionSelection = min(Suggestion.all.count - 1, session.suggestionSelection + 1); return true }
            return false
        case 36 where plain, 76 where plain: // ↩ / enter
            if session.showActions {
                if actions.indices.contains(session.actionSelection) { perform(actions[session.actionSelection], model) }
                return true
            }
            if model.phase == .idle, Suggestion.all.indices.contains(session.suggestionSelection) {
                state.input = Suggestion.all[session.suggestionSelection].insert
                session.focusToken += 1
                return true
            }
            if model.canSubmit { submit(); return true }
            return model.phase != .typing // swallow ↩ while busy/locked; let the field handle other cases
        case 36 where command, 76 where command: // ⌘↩
            if model.phase == .approval { approveIfArmed(event, accepted: true); return true }
            if model.canSubmit { submit(); return true }
            return true
        case 51 where command: // ⌘⌫
            if model.phase == .approval { approveIfArmed(event, accepted: false); return true }
            return false
        default:
            break
        }
        guard command, let characters = event.charactersIgnoringModifiers?.lowercased() else { return false }
        switch characters {
        case "k":
            session.actionSelection = 0
            session.showActions.toggle(); return true
        case ".":
            if model.busy { state.cancel(); return true }
            return false
        case "c": // copy the result unless the user has selected text (then the selection's own copy applies)
            if model.phase == .result, !hasTextSelection { copyResult(); return true }
            return false
        case "n":
            if model.phase == .result || model.phase == .error { clear(); return true }
            return false
        case ",":
            openSettings(); return true
        case "o":
            openWorkspace(); return true
        default:
            return false
        }
    }

    /// True when the panel's first responder is a text view with a non-empty selection.
    private var hasTextSelection: Bool {
        guard let textView = panel?.firstResponder as? NSTextView else { return false }
        return textView.selectedRange().length > 0
    }

    /// The approval keys act only once the card is armed and never on a key repeat, so a held or in-flight
    /// ⌘↩ from another app cannot approve a tool action the user has not seen.
    private func approveIfArmed(_ event: NSEvent, accepted: Bool) {
        guard !event.isARepeat else { return }
        decide(accepted)
    }

    /// The one path to `AppState.decide` from the bar (keys, buttons, ⌘K rows): armed only, and disarms at once.
    private func decide(_ accepted: Bool) {
        guard session.approvalArmed, state.proposal != nil else { return }
        state.decide(accepted)
        armApproval(for: state.proposal)
    }

    // MARK: Actions (all through AppState)

    func currentActions(_ model: CommandBarModel) -> [BarAction] {
        let models = state.snapshot?.configuration.models.map { ($0.id, $0.title) } ?? []
        return model.actions(models: models, selectedModel: state.selectedModel)
    }

    private func perform(_ action: BarAction, _ model: CommandBarModel) {
        session.showActions = false
        switch action.id {
        case "copy": copyResult()
        case "clear": clear()
        case "cancel": state.cancel()
        case "approve": decide(true)
        case "deny": decide(false)
        case "unload": state.stopRuntime()
        case "workspace": openWorkspace()
        case "settings": openSettings()
        default:
            if action.id.hasPrefix("model:") { state.selectedModel = String(action.id.dropFirst(6)) }
        }
    }

    var actions: CommandBarActions {
        CommandBarActions(
            submit: { [weak self] in self?.submit() },
            cancel: { [weak self] in self?.state.cancel() },
            approve: { [weak self] in self?.decide(true) },
            deny: { [weak self] in self?.decide(false) },
            dismiss: { [weak self] in self?.hide() },
            clear: { [weak self] in self?.clear() },
            copyResult: { [weak self] in self?.copyResult() },
            openSettings: { [weak self] in self?.openSettings() },
            openWorkspace: { [weak self] in self?.openWorkspace() },
            unloadModel: { [weak self] in self?.state.stopRuntime() },
            selectModel: { [weak self] id in self?.state.selectedModel = id })
    }

    private func submit() {
        session.showActions = false
        state.submit()
        // The input stays in the workspace's editor too; clear the bar so the result has the stage.
        if state.busy { state.input = "" }
    }

    private func clear() {
        state.result = ""
        state.error = nil
        session.suggestionSelection = 0
        session.focusToken += 1
    }

    private func copyResult() {
        guard !state.result.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(state.result, forType: .string)
        session.copied = true
    }

    private func openSettings() {
        hide()
        NSApp.activate(ignoringOtherApps: true)
        // SwiftUI's Settings scene responds to this selector on macOS 14.
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    func openWorkspace() {
        hide()
        NSApp.activate(ignoringOtherApps: true)
        onOpenWorkspace?()
    }
    /// Set by the App scene, which owns the `openWindow` environment action. It is attached to the always-present
    /// menu bar label (`WorkspaceOpener`) so ⌘O works before any window has ever been shown.
    var onOpenWorkspace: (() -> Void)?

    // MARK: Approval surfacing

    /// While a task runs with the bar hidden, an approval request brings the bar back so it is never missed.
    /// The bar is shown without taking the keyboard (`ShowReason.approval`).
    private func watchApprovals() {
        withObservationTracking {
            _ = state.proposal
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.armApproval(for: self.state.proposal)
                if self.state.proposal != nil, !self.isVisible { self.show(reason: .approval) }
                self.watchApprovals()
            }
        }
    }

    /// Starts the arming window for a newly seen proposal: the approval keys and buttons are inert until
    /// `approvalArmingDelay` has passed, and VoiceOver is told that a decision is needed. Called from the
    /// observation above and from `handle`, so the window also applies when the panel already had the keyboard.
    private func armApproval(for proposal: ToolProposal?) {
        guard let proposal else {
            armedProposalID = nil
            armingTask?.cancel(); armingTask = nil
            session.approvalArmed = false
            return
        }
        guard proposal.id != armedProposalID else { return }
        armedProposalID = proposal.id
        armingTask?.cancel()
        session.approvalArmed = approvalArmingDelay <= 0
        // Metadata only (server and tool IDs), like the audit log; never the arguments.
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: "Approval required: \(proposal.server), \(proposal.tool). Review the tool action in the \(Brand.displayName) command bar.",
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
        guard !session.approvalArmed else { return }
        let delay = approvalArmingDelay
        let id = proposal.id
        armingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.state.proposal?.id == id else { return }
            self.session.approvalArmed = true
        }
    }
}

/// Live bridge from `AppState` to the pure `CommandBarView`. `controller` is unowned: the controller owns the
/// hosting view that owns this value, and it outlives the panel.
struct CommandBarHost: View {
    @Bindable var state: AppState
    var session: CommandBarSession
    unowned let controller: CommandBarController
    var body: some View {
        CommandBarView(model: CommandBarModel.resolve(state.commandBarInputs), input: $state.input, session: session,
                       models: state.snapshot?.configuration.models.map { ModelChoice(id: $0.id, title: $0.title) } ?? [],
                       selectedModel: state.selectedModel, hotkey: controller.hotkeyLabel, actions: controller.actions)
    }
}

extension AppState {
    /// Facts for the command bar, taken from the same state the workspace window uses. The destination is the
    /// core's classification (`ProviderSpec.destination`, ADR 0011), not re-derived here.
    var commandBarInputs: CommandBarInputs {
        CommandBarInputs(configurationAvailable: snapshot != nil, managed: snapshot?.managed == true || (snapshot == nil && ((try? ConfigurationLoader.isManaged()) ?? false)),
                         busy: busy, input: input, result: result, error: error,
                         proposal: proposal.map(ProposalSummary.init), runtimeState: runtimeState,
                         usesManagedRuntime: usesManagedRuntime, providerKind: provider?.kind, destination: destination,
                         providerHost: provider?.baseURL?.host ?? "", modelTitle: model?.title ?? "",
                         inputLimit: snapshot?.configuration.limits.inputBytes ?? 0,
                         serverCount: snapshot?.configuration.mcpServers.count ?? 0)
    }
}

private struct UncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
