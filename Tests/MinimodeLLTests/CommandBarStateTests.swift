import Testing
import Foundation
import LocalAgentCore
@testable import MinimodeLL

private func inputs(_ configure: (inout CommandBarInputs) -> Void = { _ in }) -> CommandBarInputs {
    var value = CommandBarInputs()
    value.providerKind = .managed; value.usesManagedRuntime = true; value.modelTitle = "Qwen3 4B"
    value.inputLimit = 100; value.serverCount = 1
    configure(&value)
    return value
}

@Test func phasePrecedenceFollowsTheCore() {
    #expect(CommandBarModel.resolve(inputs()).phase == .idle)
    #expect(CommandBarModel.resolve(inputs { $0.input = "  hello " }).phase == .typing)
    #expect(CommandBarModel.resolve(inputs { $0.input = "   " }).phase == .idle)
    #expect(CommandBarModel.resolve(inputs { $0.result = "done" }).phase == .result)
    #expect(CommandBarModel.resolve(inputs { $0.result = "done"; $0.error = "failed" }).phase == .error)
    #expect(CommandBarModel.resolve(inputs { $0.busy = true; $0.error = "stale" }).phase == .running)
    #expect(CommandBarModel.resolve(inputs { $0.busy = true; $0.runtimeState = .starting }).phase == .modelStarting)
    // A proposal wins over everything except a missing configuration, because the core is waiting on it.
    let proposal = ProposalSummary(server: "s", tool: "t", arguments: "{}")
    #expect(CommandBarModel.resolve(inputs { $0.busy = true; $0.proposal = proposal }).phase == .approval)
    #expect(CommandBarModel.resolve(inputs { $0.configurationAvailable = false; $0.proposal = proposal; $0.busy = true }).phase == .locked)
}

@Test func modelStartingOnlyForTheManagedRuntime() {
    // An external local server has no observable startup; a starting runtime for a litellm task is irrelevant.
    let external = inputs { $0.providerKind = .local; $0.usesManagedRuntime = false; $0.busy = true; $0.runtimeState = .starting }
    #expect(CommandBarModel.resolve(external).phase == .running)
}

@Test func destinationMirrorsProviderKind() {
    #expect(CommandBarModel.resolve(inputs { $0.providerKind = .local }).destination == .local)
    #expect(CommandBarModel.resolve(inputs { $0.providerKind = .managed }).destination == .local)
    #expect(CommandBarModel.resolve(inputs { $0.providerKind = .litellm; $0.providerHost = "gw.example.com" }).destination == .cloud(host: "gw.example.com"))
    #expect(CommandBarModel.resolve(inputs { $0.providerKind = nil }).destination == .none)
    #expect(Destination.cloud(host: "gw.example.com").label == "Cloud · gw.example.com")
}

@Test func submitRequiresConfigurationInputAndBudget() {
    #expect(CommandBarModel.resolve(inputs { $0.input = "ok" }).canSubmit)
    #expect(!CommandBarModel.resolve(inputs()).canSubmit)
    #expect(!CommandBarModel.resolve(inputs { $0.input = "ok"; $0.busy = true }).canSubmit)
    #expect(!CommandBarModel.resolve(inputs { $0.input = "ok"; $0.configurationAvailable = false }).canSubmit)
    #expect(!CommandBarModel.resolve(inputs { $0.input = "ok"; $0.providerKind = nil }).canSubmit)
    #expect(!CommandBarModel.resolve(inputs { $0.input = String(repeating: "x", count: 101) }).canSubmit)
    #expect(CommandBarModel.resolve(inputs { $0.input = String(repeating: "x", count: 100) }).canSubmit)
}

@Test func lockedStatusDistinguishesManagedPolicy() {
    let managed = CommandBarModel.resolve(inputs { $0.configurationAvailable = false; $0.managed = true })
    #expect(managed.phase == .locked && managed.statusLine.contains("Managed policy"))
    let personal = CommandBarModel.resolve(inputs { $0.configurationAvailable = false })
    #expect(personal.statusLine == "Configuration could not be loaded.")
    #expect(managed.markState == .off)
}

@Test func actionsMatchThePhase() {
    let models = [("a", "A"), ("b", "B")]
    let idle = CommandBarModel.resolve(inputs { $0.runtimeState = .ready }).actions(models: models, selectedModel: "a")
    #expect(idle.map(\.id) == ["model:b", "unload", "workspace", "settings"])
    let running = CommandBarModel.resolve(inputs { $0.busy = true; $0.runtimeState = .ready }).actions(models: models, selectedModel: "a")
    #expect(running.map(\.id) == ["cancel", "workspace", "settings"]) // no model switch or unload while busy
    let approval = CommandBarModel.resolve(inputs { $0.busy = true; $0.proposal = ProposalSummary(server: "s", tool: "t", arguments: "{}") })
        .actions(models: models, selectedModel: "a")
    #expect(approval.map(\.id) == ["approve", "deny", "workspace", "settings"])
    let result = CommandBarModel.resolve(inputs { $0.result = "r" }).actions(models: [], selectedModel: "")
    #expect(result.map(\.id) == ["copy", "clear", "workspace", "settings"])
    let locked = CommandBarModel.resolve(inputs { $0.configurationAvailable = false }).actions(models: models, selectedModel: "a")
    #expect(locked.map(\.id) == ["workspace", "settings"])
}

@Test func statusLineIsContentFree() {
    let secret = "SECRET-ARGUMENT"
    let model = CommandBarModel.resolve(inputs { $0.input = secret; $0.result = secret; $0.busy = true })
    #expect(!model.statusLine.contains(secret))
    #expect(model.inputBytes == secret.utf8.count)
}
