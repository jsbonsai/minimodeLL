import SwiftUI

/// Design tokens for the command bar and the restyled windows (`docs/design/raycast-redesign.md`).
///
/// Colors are mapped one-to-one from the supplied brand kit (`design-assets/minimodeLL-brand/tokens/tokens.json`,
/// `brand.css`). Unlike `BrandAssets.color`, which resolves through `NSAppearance`, a `DesignPalette` is a plain
/// value chosen for one color scheme. That keeps rendering deterministic for the offline preview renderer
/// (`--render-design-previews`), which cannot depend on the current `NSAppearance`. The live app selects the
/// palette from the SwiftUI `colorScheme` at the root of every design surface (see `DesignRoot`).
struct DesignPalette: Equatable, Sendable {
    /// Window/background surface (`--mm-bg`).
    let background: Color
    /// Raised card surface (`--mm-surface`).
    let surface: Color
    /// Slightly raised inset surface for chips, key caps and code blocks (derived: surface mixed with text at 6%).
    let inset: Color
    /// Primary text (`--mm-text`).
    let text: Color
    /// Secondary text (`--mm-text-muted`).
    let muted: Color
    /// Hairlines and dividers (`--mm-border`).
    let border: Color
    /// Interactive accent and the status dot (`--mm-accent`).
    let accent: Color
    /// Accent wash for selection rows (accent at 12%).
    let accentWash: Color
    /// Status colors (`color.status.*`). Dark variants are lightened so they keep ≥ 4.5:1 on ink.
    let running: Color
    let warning: Color
    let blocked: Color
    let isDark: Bool

    static let light = DesignPalette(
        background: Color(hex: 0xF2F3EF), surface: Color(hex: 0xFFFFFF), inset: Color(hex: 0xF2F3EF),
        text: Color(hex: 0x16181D), muted: Color(hex: 0x5B5F68), border: Color(hex: 0xE2E4DF),
        accent: Color(hex: 0x3A5BD9), accentWash: Color(hex: 0x3A5BD9, alpha: 0.12),
        running: Color(hex: 0x1F8A5B), warning: Color(hex: 0xB7791F), blocked: Color(hex: 0xC23B3B), isDark: false)

    static let dark = DesignPalette(
        background: Color(hex: 0x16181D), surface: Color(hex: 0x22252C), inset: Color(hex: 0x2B2E36),
        text: Color(hex: 0xF2F3EF), muted: Color(hex: 0xA3A7AF), border: Color(hex: 0x33363E),
        accent: Color(hex: 0x7D96FF), accentWash: Color(hex: 0x7D96FF, alpha: 0.16),
        running: Color(hex: 0x3DBD85), warning: Color(hex: 0xD9A441), blocked: Color(hex: 0xE0605F), isDark: true)

    static func forScheme(_ scheme: ColorScheme) -> DesignPalette { scheme == .dark ? .dark : .light }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}

/// Spacing scale (`space.*` in tokens.json). Points.
enum Space {
    static let xs: CGFloat = 4, sm: CGFloat = 8, md: CGFloat = 12, lg: CGFloat = 16, xl: CGFloat = 24, xxl: CGFloat = 32
}

/// Corner radii (`radius.*`). `panel` is the command bar card; it is larger than the kit's `lg` because the
/// card floats over the desktop like a system HUD.
enum Radius {
    static let sm: CGFloat = 6, md: CGFloat = 10, lg: CGFloat = 16, panel: CGFloat = 18
}

/// Geist type ramp. Fonts are registered for the process by `BrandAssets.registerFonts()`; if a face is missing
/// (for example in unit tests) SwiftUI falls back to the system font with the same size, so nothing breaks.
enum Typography {
    /// The command bar input: large, calm, regular weight.
    static let input = Font.custom("Geist-Regular", size: 19)
    static let title = Font.custom("Geist-SemiBold", size: 15)
    static let body = Font.custom("Geist-Regular", size: 14)
    static let label = Font.custom("Geist-Regular", size: 13)
    static let labelStrong = Font.custom("Geist-SemiBold", size: 13)
    static let caption = Font.custom("Geist-Regular", size: 11.5)
    static let captionStrong = Font.custom("Geist-SemiBold", size: 11.5)
    static let mono = Font.custom("GeistMono-Regular", size: 12.5)
    static let keycap = Font.custom("Geist-SemiBold", size: 10.5)
}

// MARK: Environment plumbing

private struct DesignPaletteKey: EnvironmentKey { static let defaultValue = DesignPalette.light }
/// When true, materials render as opaque surfaces. Set by the preview renderer (ImageRenderer cannot draw
/// `NSVisualEffectView`) and by the Reduce Transparency accessibility setting.
private struct OpaqueMaterialsKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var palette: DesignPalette {
        get { self[DesignPaletteKey.self] }
        set { self[DesignPaletteKey.self] = newValue }
    }
    var opaqueMaterials: Bool {
        get { self[OpaqueMaterialsKey.self] }
        set { self[OpaqueMaterialsKey.self] = newValue }
    }
}

/// Root modifier for every design surface: picks the palette from the color scheme, applies the base Geist font
/// and tint, and honours Reduce Transparency by switching materials to opaque surfaces.
struct DesignRoot: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var forcedPalette: DesignPalette?
    var forceOpaque = false
    func body(content: Content) -> some View {
        let palette = forcedPalette ?? DesignPalette.forScheme(scheme)
        content
            .environment(\.palette, palette)
            .environment(\.opaqueMaterials, forceOpaque || reduceTransparency)
            .font(Typography.body)
            .foregroundStyle(palette.text)
            .tint(palette.accent)
    }
}

extension View {
    func designRoot(palette: DesignPalette? = nil, opaque: Bool = false) -> some View {
        modifier(DesignRoot(forcedPalette: palette, forceOpaque: opaque))
    }
}
