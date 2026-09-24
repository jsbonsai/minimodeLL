import AppKit
import Carbon.HIToolbox

/// A global keyboard shortcut for summoning the command bar. Parsed from a short text form such as
/// `"option+space"`, `"⌘⇧K"` or `"ctrl-alt-m"`, and registered with Carbon's `RegisterEventHotKey`.
///
/// `RegisterEventHotKey` is the one global-shortcut API that works inside the App Sandbox without Accessibility
/// or Input Monitoring permission (it delivers only the registered combination, never other keystrokes), which is
/// why the app does not use a global `NSEvent` monitor or `CGEventTap`. The shortcut is a per-user preference
/// stored in `UserDefaults` (`Hotkey.defaultsKey`), not part of the policy configuration: it grants no capability.
struct Hotkey: Equatable, Sendable {
    struct Modifiers: OptionSet, Equatable, Sendable {
        let rawValue: UInt32
        static let command = Modifiers(rawValue: UInt32(cmdKey))
        static let shift = Modifiers(rawValue: UInt32(shiftKey))
        static let option = Modifiers(rawValue: UInt32(optionKey))
        static let control = Modifiers(rawValue: UInt32(controlKey))
    }
    let modifiers: Modifiers
    /// Carbon virtual key code (`kVK_*`).
    let keyCode: UInt32
    /// Canonical key name (`space`, `k`, `f5`, …).
    let keyName: String

    static let defaultsKey = "commandBarHotkey"
    static let fallback = Hotkey(modifiers: .option, keyCode: UInt32(kVK_Space), keyName: "space")

    enum ParseError: Error, Equatable { case empty, unknownToken(String), noKey, noModifier, multipleKeys }

    /// Parses `+`, `-`, or whitespace separated tokens and the ⌘⇧⌥⌃ glyphs. Requires exactly one key and at
    /// least one modifier so a bare key can never be captured system-wide.
    static func parse(_ text: String) throws(ParseError) -> Hotkey {
        var modifiers = Modifiers()
        var key: (code: UInt32, name: String)?
        var tokens: [String] = []
        for piece in text.split(whereSeparator: { $0 == "+" || $0.isWhitespace }) {
            if piece.count == 1 { tokens.append(String(piece)); continue }
            var plain = ""
            for character in piece {
                switch character {
                case "⌘": tokens.append("cmd")
                case "⇧": tokens.append("shift")
                case "⌥": tokens.append("option")
                case "⌃": tokens.append("control")
                default: plain.append(character)
                }
            }
            // Dash-separated form ("ctrl-alt-m"). A lone dash is a key, handled by the single-character case.
            tokens += plain.split(separator: "-", omittingEmptySubsequences: true).map(String.init)
        }
        guard !tokens.isEmpty else { throw .empty }
        for token in tokens {
            let lowered = token.lowercased()
            if let modifier = modifierNames[lowered] { modifiers.insert(modifier); continue }
            if let code = keyCodes[lowered] {
                guard key == nil else { throw .multipleKeys }
                key = (code, lowered); continue
            }
            throw .unknownToken(token)
        }
        guard let key else { throw .noKey }
        guard !modifiers.isEmpty else { throw .noModifier }
        return Hotkey(modifiers: modifiers, keyCode: key.code, keyName: key.name)
    }

    /// Human-readable form in macOS menu order: ⌃ ⌥ ⇧ ⌘ then the key.
    var displayString: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        parts.append(Self.displayNames[keyName] ?? keyName.uppercased())
        return parts.joined()
    }

    /// Stable text form for storage (`option+space`).
    var storageString: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("control") }
        if modifiers.contains(.option) { parts.append("option") }
        if modifiers.contains(.shift) { parts.append("shift") }
        if modifiers.contains(.command) { parts.append("cmd") }
        parts.append(keyName)
        return parts.joined(separator: "+")
    }

    /// The configured shortcut, or the fallback when the preference is missing or invalid.
    static func configured(defaults: UserDefaults = .standard) -> Hotkey {
        guard let text = defaults.string(forKey: defaultsKey), let parsed = try? parse(text) else { return fallback }
        return parsed
    }

    /// Includes the ⌘⇧⌥⌃ glyphs as stand-alone tokens so a spaced form ("⌥ ⇧ Space") parses like "⌥⇧Space".
    private static let modifierNames: [String: Modifiers] = [
        "cmd": .command, "command": .command, "⌘": .command,
        "shift": .shift, "⇧": .shift, "opt": .option, "option": .option, "alt": .option, "⌥": .option,
        "ctrl": .control, "control": .control, "⌃": .control
    ]
    private static let displayNames: [String: String] = [
        "space": "Space", "return": "↩", "enter": "↩", "tab": "⇥", "escape": "⎋", "delete": "⌫",
        "up": "↑", "down": "↓", "left": "←", "right": "→", "`": "`", "-": "-", "=": "=", "[": "[", "]": "]",
        ";": ";", "'": "'", ",": ",", ".": ".", "/": "/", "\\": "\\"
    ]
    static let keyCodes: [String: UInt32] = {
        var map: [String: UInt32] = [
            "a": UInt32(kVK_ANSI_A), "b": UInt32(kVK_ANSI_B), "c": UInt32(kVK_ANSI_C), "d": UInt32(kVK_ANSI_D),
            "e": UInt32(kVK_ANSI_E), "f": UInt32(kVK_ANSI_F), "g": UInt32(kVK_ANSI_G), "h": UInt32(kVK_ANSI_H),
            "i": UInt32(kVK_ANSI_I), "j": UInt32(kVK_ANSI_J), "k": UInt32(kVK_ANSI_K), "l": UInt32(kVK_ANSI_L),
            "m": UInt32(kVK_ANSI_M), "n": UInt32(kVK_ANSI_N), "o": UInt32(kVK_ANSI_O), "p": UInt32(kVK_ANSI_P),
            "q": UInt32(kVK_ANSI_Q), "r": UInt32(kVK_ANSI_R), "s": UInt32(kVK_ANSI_S), "t": UInt32(kVK_ANSI_T),
            "u": UInt32(kVK_ANSI_U), "v": UInt32(kVK_ANSI_V), "w": UInt32(kVK_ANSI_W), "x": UInt32(kVK_ANSI_X),
            "y": UInt32(kVK_ANSI_Y), "z": UInt32(kVK_ANSI_Z),
            "0": UInt32(kVK_ANSI_0), "1": UInt32(kVK_ANSI_1), "2": UInt32(kVK_ANSI_2), "3": UInt32(kVK_ANSI_3),
            "4": UInt32(kVK_ANSI_4), "5": UInt32(kVK_ANSI_5), "6": UInt32(kVK_ANSI_6), "7": UInt32(kVK_ANSI_7),
            "8": UInt32(kVK_ANSI_8), "9": UInt32(kVK_ANSI_9),
            "space": UInt32(kVK_Space), "return": UInt32(kVK_Return), "enter": UInt32(kVK_Return),
            "tab": UInt32(kVK_Tab), "escape": UInt32(kVK_Escape), "delete": UInt32(kVK_Delete),
            "up": UInt32(kVK_UpArrow), "down": UInt32(kVK_DownArrow), "left": UInt32(kVK_LeftArrow), "right": UInt32(kVK_RightArrow),
            "`": UInt32(kVK_ANSI_Grave), "-": UInt32(kVK_ANSI_Minus), "=": UInt32(kVK_ANSI_Equal),
            "[": UInt32(kVK_ANSI_LeftBracket), "]": UInt32(kVK_ANSI_RightBracket), ";": UInt32(kVK_ANSI_Semicolon),
            "'": UInt32(kVK_ANSI_Quote), ",": UInt32(kVK_ANSI_Comma), ".": UInt32(kVK_ANSI_Period),
            "/": UInt32(kVK_ANSI_Slash), "\\": UInt32(kVK_ANSI_Backslash)
        ]
        let fKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12]
        for (index, code) in fKeys.enumerated() { map["f\(index + 1)"] = UInt32(code) }
        return map
    }()
}

/// Owns one Carbon hot key registration and calls `handler` on the main actor when it fires.
@MainActor final class GlobalHotkey {
    nonisolated(unsafe) private var hotKeyRef: EventHotKeyRef?
    nonisolated(unsafe) private var handlerRef: EventHandlerRef?
    private let handler: () -> Void
    private(set) var registered: Hotkey?
    private static let signature: OSType = 0x6D6D4C4C // 'mmLL'

    init(handler: @escaping () -> Void) { self.handler = handler }

    /// Registers `hotkey`, replacing any previous registration. Returns false when the system refuses the
    /// combination (for example one already taken by another app); the previous registration is then released.
    @discardableResult
    func register(_ hotkey: Hotkey) -> Bool {
        unregister()
        if handlerRef == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let selfPointer = Unmanaged.passUnretained(self).toOpaque()
            InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
                guard let userData, let event else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                guard id.signature == GlobalHotkey.signature else { return OSStatus(eventNotHandledErr) }
                let owner = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
                // Carbon delivers on the main thread; hop explicitly to satisfy actor isolation.
                Task { @MainActor in owner.handler() }
                return noErr
            }, 1, &eventType, selfPointer, &handlerRef)
        }
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(hotkey.keyCode, hotkey.modifiers.rawValue, id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        hotKeyRef = ref
        registered = hotkey
        return true
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        registered = nil
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
