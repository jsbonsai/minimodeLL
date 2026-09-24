import SwiftUI
import LocalAgentCore

/// Settings → Command Bar: the global shortcut (a per-user preference, not policy) and a way to show the bar.
struct CommandBarSettings: View {
    let controller: CommandBarController
    @State private var text = Hotkey.configured().storageString
    @State private var notice = ""
    @Environment(\.palette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Command bar").font(Typography.title)
                Text("Press the shortcut anywhere to open \(Brand.displayName) over your current app. Type a request, press ↩ to run it, ⌘K for actions and esc to hide.")
                    .font(Typography.label).foregroundStyle(palette.muted)
            }
            HStack(spacing: Space.sm) {
                TextField("option+space", text: $text).textFieldStyle(.roundedBorder).frame(width: 200)
                    .font(Typography.mono).accessibilityLabel("Global shortcut")
                    .onSubmit(save)
                Button("Apply", action: save)
                // Read through the observable session so the status updates the moment `apply` returns.
                Text(controller.session.registeredHotkey?.displayString ?? "Not registered").font(Typography.labelStrong)
                    .foregroundStyle(controller.session.registeredHotkey == nil ? palette.blockedInk : palette.muted)
                    .padding(.horizontal, 8).padding(.vertical, 4).insetSurface()
                    .accessibilityLabel(controller.session.registeredHotkey.map { "Registered shortcut \(Keycap.spoken($0.displayString))" } ?? "Shortcut not registered")
            }
            Text("Use modifier names with +: cmd, shift, option, control (or the ⌘ ⇧ ⌥ ⌃ glyphs), then one key (letters, digits, space, F-keys, arrows). At least one modifier is required. The shortcut is registered with the system hot-key service, which works inside the App Sandbox without Accessibility permission and never sees other keystrokes.")
                .font(Typography.caption).foregroundStyle(palette.muted)
            if !notice.isEmpty { Text(notice).font(Typography.caption).foregroundStyle(palette.blockedInk) }
            Button("Show command bar") { controller.show() }
            Spacer()
        }
    }
    private func save() {
        do {
            let hotkey = try Hotkey.parse(text)
            text = hotkey.storageString
            // Synchronous: the preference is written and the hotkey registered before this returns.
            notice = controller.apply(hotkey) ? "" : "The system refused \(hotkey.displayString); it may be taken by another app."
        } catch {
            switch error {
            case .empty: notice = "Enter a shortcut such as option+space."
            case .unknownToken(let token): notice = "“\(token)” is not a modifier or key name."
            case .noKey: notice = "Add one key after the modifiers."
            case .noModifier: notice = "Add at least one modifier (cmd, shift, option, control)."
            case .multipleKeys: notice = "Use exactly one key."
            }
        }
    }
}
