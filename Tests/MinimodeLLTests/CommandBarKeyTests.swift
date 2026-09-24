import AppKit
import Testing
@testable import LocalAgentCore
@testable import MinimodeLL

/// Keyboard map of the command bar (`CommandBarController.handle`). Uses a real `AppState` (which loads the
/// developer configuration of the test process) but never shows the panel, registers a hotkey or runs a task.
@MainActor private func makeController() -> CommandBarController {
    let state = AppState()
    state.input = ""; state.result = ""; state.error = nil
    return CommandBarController(state: state)
}

private func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags = [], characters: String = "") -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                     characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
}

private let esc: UInt16 = 53, enter: UInt16 = 36, up: UInt16 = 126, down: UInt16 = 125, k: UInt16 = 40, delete: UInt16 = 51

@Test @MainActor func commandKTogglesActionsAndEscapeClosesThemFirst() {
    let controller = makeController()
    #expect(controller.handle(key(k, .command)))
    #expect(controller.session.showActions)
    #expect(controller.handle(key(esc)))
    #expect(!controller.session.showActions)
    // A second escape with nothing open is still consumed (it hides the panel; no panel exists here).
    #expect(controller.handle(key(esc)))
}

@Test @MainActor func arrowsMoveTheSuggestionAndReturnInsertsIt() {
    let controller = makeController()
    guard controller.state.snapshot != nil else { return } // no developer configuration on this machine
    #expect(controller.handle(key(down)))
    #expect(controller.handle(key(down)))
    #expect(controller.handle(key(down))) // clamps at the last suggestion
    #expect(controller.session.suggestionSelection == Suggestion.all.count - 1)
    #expect(controller.handle(key(up)))
    #expect(controller.session.suggestionSelection == Suggestion.all.count - 2)
    #expect(controller.handle(key(enter)))
    #expect(controller.state.input == Suggestion.all[Suggestion.all.count - 2].insert)
    #expect(!controller.state.busy) // inserting a suggestion never submits
}

@Test @MainActor func arrowsFallThroughToTheTextFieldWhileTyping() {
    let controller = makeController()
    guard controller.state.snapshot != nil else { return }
    controller.state.input = "draft"
    #expect(!controller.handle(key(down)))
    #expect(!controller.handle(key(up)))
}

@Test @MainActor func approvalKeysRouteThroughAppStateDecide() {
    let controller = makeController()
    controller.state.busy = true
    controller.state.proposal = ToolProposal(id: "1", server: "s", tool: "t", arguments: "{}")
    // Plain return never approves.
    #expect(controller.handle(key(enter)))
    #expect(controller.state.proposal != nil && controller.state.approval == nil)
    #expect(controller.handle(key(enter, .command)))
    #expect(controller.state.approval == true && controller.state.proposal == nil)

    controller.state.proposal = ToolProposal(id: "2", server: "s", tool: "t", arguments: "{}")
    controller.state.approval = nil
    #expect(controller.handle(key(delete, .command)))
    #expect(controller.state.approval == false && controller.state.proposal == nil)
}

@Test @MainActor func actionListNavigationRunsTheSelectedAction() {
    let controller = makeController()
    controller.state.result = "answer"
    #expect(controller.handle(key(k, .command)))
    let actions = controller.currentActions(CommandBarModel.resolve(controller.state.commandBarInputs))
    #expect(actions.first?.id == "copy")
    #expect(controller.handle(key(down)))
    #expect(controller.session.actionSelection == 1)
    #expect(actions[1].id == "clear")
    #expect(controller.handle(key(enter)))
    #expect(controller.state.result.isEmpty)
    #expect(!controller.session.showActions)
}

@Test @MainActor func unhandledCombinationsPassThrough() {
    let controller = makeController()
    #expect(!controller.handle(key(8, [], characters: "c")))          // plain typing
    #expect(!controller.handle(key(45, .command, characters: "n")))  // ⌘N with nothing to clear
    #expect(!controller.handle(key(47, .command, characters: ".")))  // ⌘. with nothing running
}
