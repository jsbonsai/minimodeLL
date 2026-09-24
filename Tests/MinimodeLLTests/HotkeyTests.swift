import Testing
import Foundation
import Carbon.HIToolbox
@testable import MinimodeLL

@Test func parsesPlusSeparatedNames() throws {
    let hotkey = try Hotkey.parse("option+space")
    #expect(hotkey.modifiers == .option)
    #expect(hotkey.keyCode == UInt32(kVK_Space))
    #expect(hotkey.displayString == "⌥Space")
    #expect(hotkey.storageString == "option+space")
}

@Test func parsesGlyphsDashesAndAliases() throws {
    #expect(try Hotkey.parse("⌘⇧K") == Hotkey(modifiers: [.command, .shift], keyCode: UInt32(kVK_ANSI_K), keyName: "k"))
    #expect(try Hotkey.parse("ctrl-alt-m") == Hotkey(modifiers: [.control, .option], keyCode: UInt32(kVK_ANSI_M), keyName: "m"))
    #expect(try Hotkey.parse("Cmd Shift F5") == Hotkey(modifiers: [.command, .shift], keyCode: UInt32(kVK_F5), keyName: "f5"))
    #expect(try Hotkey.parse("cmd+-").keyCode == UInt32(kVK_ANSI_Minus))
    #expect(try Hotkey.parse("⌃⌥⇧⌘Space").displayString == "⌃⌥⇧⌘Space")
}

@Test func rejectsBareKeysAndUnknownTokens() {
    #expect(throws: Hotkey.ParseError.noModifier) { try Hotkey.parse("space") }
    #expect(throws: Hotkey.ParseError.noKey) { try Hotkey.parse("cmd+shift") }
    #expect(throws: Hotkey.ParseError.empty) { try Hotkey.parse("  ") }
    #expect(throws: Hotkey.ParseError.unknownToken("hyper")) { try Hotkey.parse("hyper+k") }
    #expect(throws: Hotkey.ParseError.multipleKeys) { try Hotkey.parse("cmd+k+j") }
}

@Test func storageRoundTripsAndInvalidPreferenceFallsBack() throws {
    let suite = "org.minimodell.tests.hotkey-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    #expect(Hotkey.configured(defaults: defaults) == Hotkey.fallback)
    defaults.set("nonsense", forKey: Hotkey.defaultsKey)
    #expect(Hotkey.configured(defaults: defaults) == Hotkey.fallback)
    let custom = try Hotkey.parse("control+shift+l")
    defaults.set(custom.storageString, forKey: Hotkey.defaultsKey)
    #expect(Hotkey.configured(defaults: defaults) == custom)
    #expect(try Hotkey.parse(custom.storageString) == custom)
}
