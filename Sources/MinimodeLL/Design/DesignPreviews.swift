import AppKit
import SwiftUI
import LocalAgentCore

/// `minimodell --render-design-previews <dir>`: renders the command bar in its key states, light and dark, to
/// PNG files with `ImageRenderer` and exits. No configuration, model, server or window is involved: every state
/// is a synthetic fixture. Materials render as opaque surfaces (ImageRenderer cannot draw `NSVisualEffectView`)
/// and scroll views as static text, so the images show layout, hierarchy and colour, not the live vibrancy.
enum DesignPreviewCommand {
    struct Fixture {
        let name: String
        let inputs: CommandBarInputs
        let showActions: Bool
        let input: String
    }

    static var fixtures: [Fixture] {
        var base = CommandBarInputs()
        base.providerKind = .managed; base.usesManagedRuntime = true; base.modelTitle = "Qwen3 4B"
        base.inputLimit = 8_000; base.serverCount = 2; base.runtimeState = .ready
        var idle = base; idle.runtimeState = .stopped
        var typing = base; typing.input = "Summarize this: the quarterly planning notes from the team meeting"
        var starting = base; starting.busy = true; starting.runtimeState = .starting
        var running = base; running.busy = true
        var approval = base; approval.busy = true
        approval.proposal = ProposalSummary(server: "Orders (synthetic)", tool: "lookup_order",
                                            arguments: "{\n  \"order_id\": \"SO-10424\",\n  \"include_history\": true\n}")
        var result = base
        result.result = "Three points from the planning notes:\n\n1. The rollout moves to the second week of October so the support team can finish onboarding.\n2. Two open risks remain: the vendor contract renewal and the unassigned QA capacity for the mobile client.\n3. Owners were confirmed for each item; the next checkpoint is Friday's stand-up."
        var error = base; error.error = "The task could not complete. Check the provider, connection, and sign-in settings."
        var cloud = base; cloud.providerKind = .litellm; cloud.usesManagedRuntime = false; cloud.providerHost = "litellm.example.com"
        cloud.modelTitle = "Gateway model"; cloud.runtimeState = .stopped
        cloud.input = "Draft a short reply to: the vendor's renewal email"
        var locked = CommandBarInputs(); locked.configurationAvailable = false; locked.managed = true
        return [
            Fixture(name: "idle", inputs: idle, showActions: false, input: ""),
            Fixture(name: "typing", inputs: typing, showActions: false, input: typing.input),
            Fixture(name: "model-starting", inputs: starting, showActions: false, input: ""),
            Fixture(name: "running", inputs: running, showActions: false, input: ""),
            Fixture(name: "approval", inputs: approval, showActions: false, input: ""),
            Fixture(name: "result", inputs: result, showActions: false, input: ""),
            Fixture(name: "result-actions", inputs: result, showActions: true, input: ""),
            Fixture(name: "error", inputs: error, showActions: false, input: ""),
            Fixture(name: "cloud-typing", inputs: cloud, showActions: false, input: cloud.input),
            Fixture(name: "locked", inputs: locked, showActions: false, input: "")
        ]
    }

    @MainActor static func runAndExit(directory: String) -> Never {
        BrandAssets.registerFonts()
        let directoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            var written: [String] = []
            for fixture in fixtures {
                for (schemeName, palette) in [("light", DesignPalette.light), ("dark", DesignPalette.dark)] {
                    let session = CommandBarSession()
                    session.showActions = fixture.showActions
                    let model = CommandBarModel.resolve(fixture.inputs)
                    let models = [ModelChoice(id: "a", title: model.modelTitle.isEmpty ? "Model" : model.modelTitle), ModelChoice(id: "b", title: "Qwen3 8B")]
                    let view = CommandBarView(model: model, input: .constant(fixture.input), session: session, models: models,
                                              selectedModel: "a", hotkey: Hotkey.fallback.displayString, actions: CommandBarActions())
                        .designRoot(palette: palette, opaque: true)
                        .environment(\.staticLayout, true)
                        .shadow(color: .black.opacity(palette.isDark ? 0.55 : 0.22), radius: 28, y: 14)
                        .padding(40)
                        .frame(width: CommandBarLayout.width + 80)
                        .background(desktop(palette))
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 2
                    renderer.isOpaque = true
                    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                          let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else {
                        throw AgentError.rejected("Rendering \(fixture.name) (\(schemeName)) produced no image.")
                    }
                    let url = directoryURL.appendingPathComponent("command-bar-\(fixture.name)-\(schemeName).png")
                    try png.write(to: url, options: .atomic)
                    written.append(url.path)
                }
            }
            for path in written { print(path) }
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("render failed: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    /// A calm stand-in for a desktop so shadow and contrast can be judged; not part of the product. Flat, so
    /// the PNGs stay small enough to keep in the repository.
    private static func desktop(_ palette: DesignPalette) -> some View {
        Color(hex: palette.isDark ? 0x20243A : 0xDFE4EE)
    }
}

private struct StaticLayoutKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// True while rendering offline previews: scroll views become plain stacks so their content is drawn.
    var staticLayout: Bool {
        get { self[StaticLayoutKey.self] }
        set { self[StaticLayoutKey.self] = newValue }
    }
}

/// A scroll view that turns into its content under `staticLayout`.
struct BoundedScroll<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder let content: () -> Content
    @Environment(\.staticLayout) private var staticLayout
    var body: some View {
        if staticLayout {
            content()
        } else {
            ScrollView { content() }.frame(maxHeight: maxHeight).fixedSize(horizontal: false, vertical: true)
        }
    }
}
