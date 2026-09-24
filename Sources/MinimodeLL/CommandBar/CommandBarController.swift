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
    private(set) var registeredHotkey: Hotkey?
    private var keyMonitor: Any?
    private var lastHeight: CGFloat = CommandBarLayout.headerHeight
    private var defaultsObserver: NSObjectProtocol?

    init(state: AppState) {
        self.state = state
        super.init()
        session.onHeightChange = { [weak self] height in self?.cardHeightChanged(height) }
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
        registeredHotkey = hotkey?.register(wanted) == true ? wanted : nil
    }

    var hotkeyLabel: String { registeredHotkey?.displayString ?? "—" }

    // MARK: Showing and hiding

    var isVisible: Bool { panel?.isVisible == true }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        let panel = makePanelIfNeeded()
        guard !panel.isVisible else { panel.makeKeyAndOrderFront(nil); session.focusToken += 1; return }
        session.showActions = false
        session.copied = false
        panel.place(height: lastHeight)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // The window only fades; the card's scale-in lives in SwiftUI so the window frame can keep following
        // the card's height while the entrance plays (an AppKit frame animation would fight `follow`).
        session.presented = false
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.08 : Motion.panelInSeconds
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        withAnimation(reduceMotion ? Motion.crossfade : Motion.panelIn) { session.presented = true }
        installKeyMonitor()
        session.focusToken += 1
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        removeKeyMonitor()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = reduceMotion ? 0.05 : Motion.panelOutSeconds
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in
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

    /// Returns true when the event was consumed.
    func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        let command = flags == .command
        let plain = flags.isEmpty
        let model = CommandBarModel.resolve(state.commandBarInputs)
        let actions = currentActions(model)
        switch (event.keyCode, command, plain) {
        case (53, _, _): // esc
            escape(); return true
        case (40, true, _): // ⌘K
            session.actionSelection = 0
            session.showActions.toggle(); return true
        case (126, _, true): // ↑
            if session.showActions { session.actionSelection = max(0, session.actionSelection - 1); return true }
            if model.phase == .idle { session.suggestionSelection = max(0, session.suggestionSelection - 1); return true }
            return false
        case (125, _, true): // ↓
            if session.showActions { session.actionSelection = min(actions.count - 1, session.actionSelection + 1); return true }
            if model.phase == .idle { session.suggestionSelection = min(Suggestion.all.count - 1, session.suggestionSelection + 1); return true }
            return false
        case (36, _, true), (76, _, true): // ↩ / enter
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
        case (36, true, _), (76, true, _): // ⌘↩
            if model.phase == .approval { state.decide(true); return true }
            if model.canSubmit { submit(); return true }
            return true
        case (51, true, _): // ⌘⌫
            if model.phase == .approval { state.decide(false); return true }
            return false
        case (47, true, _): // ⌘.
            if model.busy { state.cancel(); return true }
            return false
        case (8, true, _): // ⌘C: copy the result when nothing is being edited
            if model.phase == .result, state.input.isEmpty { copyResult(); return true }
            return false
        case (45, true, _): // ⌘N
            if model.phase == .result || model.phase == .error { clear(); return true }
            return false
        case (43, true, _): // ⌘,
            openSettings(); return true
        case (31, true, _): // ⌘O
            openWorkspace(); return true
        default:
            return false
        }
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
        case "approve": state.decide(true)
        case "deny": state.decide(false)
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
            approve: { [weak self] in self?.state.decide(true) },
            deny: { [weak self] in self?.state.decide(false) },
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

    private func openWorkspace() {
        hide()
        NSApp.activate(ignoringOtherApps: true)
        onOpenWorkspace?()
    }
    /// Set by the App scene, which owns the `openWindow` environment action.
    var onOpenWorkspace: (() -> Void)?

    // MARK: Approval surfacing

    /// While a task runs with the bar hidden, an approval request brings the bar back so it is never missed.
    private func watchApprovals() {
        withObservationTracking {
            _ = state.proposal
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.state.proposal != nil, !self.isVisible { self.show() }
                self.watchApprovals()
            }
        }
    }
}

/// Live bridge from `AppState` to the pure `CommandBarView`.
struct CommandBarHost: View {
    @Bindable var state: AppState
    var session: CommandBarSession
    let controller: CommandBarController
    var body: some View {
        CommandBarView(model: CommandBarModel.resolve(state.commandBarInputs), input: $state.input, session: session,
                       models: state.snapshot?.configuration.models.map { ModelChoice(id: $0.id, title: $0.title) } ?? [],
                       selectedModel: state.selectedModel, hotkey: controller.hotkeyLabel, actions: controller.actions)
    }
}

extension AppState {
    /// Facts for the command bar, taken from the same state the workspace window uses.
    var commandBarInputs: CommandBarInputs {
        CommandBarInputs(configurationAvailable: snapshot != nil, managed: snapshot?.managed == true || (snapshot == nil && ((try? ConfigurationLoader.isManaged()) ?? false)),
                         busy: busy, input: input, result: result, error: error,
                         proposal: proposal.map(ProposalSummary.init), runtimeState: runtimeState,
                         usesManagedRuntime: usesManagedRuntime, providerKind: provider?.kind,
                         providerHost: provider?.baseURL?.host ?? "", modelTitle: model?.title ?? "",
                         inputLimit: snapshot?.configuration.limits.inputBytes ?? 0,
                         serverCount: snapshot?.configuration.mcpServers.count ?? 0)
    }
}

private struct UncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
