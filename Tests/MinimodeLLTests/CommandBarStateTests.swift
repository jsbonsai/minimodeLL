import Testing
import Foundation
import LocalAgentCore
@testable import MinimodeLL

private func inputs(_ configure: (inout CommandBarInputs) -> Void = { _ in }) -> CommandBarInputs {
    var value = CommandBarInputs()
    value.providerKind = .managed; value.destination = .thisMac; value.usesManagedRuntime = true; value.modelTitle = "Qwen3 4B"
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

@Test func destinationMirrorsTheCoreClassification() throws {
    // The chip follows `ProviderSpec.destination` (ADR 0011): the bar never re-derives it from the URL.
    #expect(CommandBarModel.resolve(inputs { $0.destination = .thisMac }).destination == .local)
    #expect(CommandBarModel.resolve(inputs { $0.destination = .cloud; $0.providerHost = "gw.example.com" }).destination == .cloud(host: "gw.example.com"))
    #expect(CommandBarModel.resolve(inputs { $0.destination = .lan(host: "192.168.1.50", encrypted: false) }).destination == .lan(host: "192.168.1.50", encrypted: false))
    #expect(CommandBarModel.resolve(inputs { $0.destination = nil; $0.providerKind = nil }).destination == .none)
    #expect(Destination.cloud(host: "gw.example.com").label == "Cloud · gw.example.com")
    #expect(Destination.lan(host: "192.168.1.50", encrypted: false).label == "LAN · unencrypted · 192.168.1.50")
    #expect(Destination.lan(host: "studio.local", encrypted: true).label == "LAN · TLS · studio.local")
    #expect(Destination.lan(host: "studio.local", encrypted: true).symbol == "network")
    #expect(Destination.lan(host: "studio.local", encrypted: false).symbol == "network.badge.shield.half.filled")
    // VoiceOver gets the core's full disclosure line for LAN.
    #expect(Destination.lan(host: "studio.local", encrypted: false).spoken == InferenceDestination.lan(host: "studio.local", encrypted: false).label)
    // A real lan provider spec maps through the same path.
    let spec = try JSONDecoder().decode(ProviderSpec.self, from: Data(#"{"id":"p","kind":"lan","baseURL":"http://192.168.1.50:1234/v1","allowInsecureTransport":true}"#.utf8))
    #expect(Destination(spec.destination, host: "") == .lan(host: "192.168.1.50", encrypted: false))
    let running = CommandBarModel.resolve(inputs { $0.busy = true; $0.usesManagedRuntime = false; $0.destination = .lan(host: "h.local", encrypted: true) })
    #expect(running.statusLine == "Working with the model on your network…")
}

@Test func keycapsHaveSpokenNames() {
    #expect(Keycap.spoken("⌘↩") == "Command Return")
    #expect(Keycap.spoken("⌘⌫") == "Command Delete")
    #expect(Keycap.spoken("⌘K") == "Command K")
    #expect(Keycap.spoken("↑↓") == "Up arrow Down arrow")
    #expect(Keycap.spoken("esc") == "Escape")
    #expect(Keycap.spoken("⌘,") == "Command Comma")
    #expect(Keycap.spoken("⌘.") == "Command Period")
    #expect(Keycap.spoken("↩") == "Return")
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
