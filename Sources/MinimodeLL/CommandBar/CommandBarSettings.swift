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
                Text(controller.registeredHotkey?.displayString ?? "Not registered").font(Typography.labelStrong)
                    .foregroundStyle(controller.registeredHotkey == nil ? palette.blocked : palette.muted)
                    .padding(.horizontal, 8).padding(.vertical, 4).insetSurface()
            }
            Text("Use modifier names with +: cmd, shift, option, control, then one key (letters, digits, space, F-keys, arrows). At least one modifier is required. The shortcut is registered with the system hot-key service, which works inside the App Sandbox without Accessibility permission and never sees other keystrokes.")
                .font(Typography.caption).foregroundStyle(palette.muted)
            if !notice.isEmpty { Text(notice).font(Typography.caption).foregroundStyle(palette.blocked) }
            Button("Show command bar") { controller.show() }
            Spacer()
        }
    }
    private func save() {
        do {
            let hotkey = try Hotkey.parse(text)
            UserDefaults.standard.set(hotkey.storageString, forKey: Hotkey.defaultsKey)
            text = hotkey.storageString
            notice = ""
            Task { @MainActor in
                if controller.registeredHotkey != hotkey { notice = "The system refused \(hotkey.displayString); it may be taken by another app." }
            }
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
