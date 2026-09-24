import AppKit
import SwiftUI

/// Native vibrancy for floating surfaces. Wraps `NSVisualEffectView` with a rounded mask so `behindWindow`
/// blending stays inside the card's corners.
///
/// Fallbacks: when `opaqueMaterials` is set in the environment (Reduce Transparency, or the offline preview
/// renderer, which cannot draw AppKit views) the same shape is filled with the palette's surface color instead.
struct Material: View {
    enum Kind { case hud, popover }
    var kind: Kind = .hud
    var radius: CGFloat = Radius.panel
    @Environment(\.opaqueMaterials) private var opaque
    @Environment(\.palette) private var palette
    var body: some View {
        if opaque {
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(palette.surface)
        } else {
            VisualEffect(material: kind == .hud ? .hudWindow : .popover, radius: radius)
        }
    }
}

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var radius: CGFloat
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = material
        view.maskImage = Self.mask(radius: radius)
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.maskImage = Self.mask(radius: radius)
    }
    /// Resizable rounded-rectangle mask; the cap insets keep corners crisp at any size.
    static func mask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// The floating card chrome: material, a hairline inner border that separates the card from any wallpaper,
/// and a soft edge highlight in dark mode (the way system HUDs read as glass).
struct CardChrome: ViewModifier {
    var radius: CGFloat = Radius.panel
    var kind: Material.Kind = .hud
    @Environment(\.palette) private var palette
    func body(content: Content) -> some View {
        content
            .background(Material(kind: kind, radius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(palette.isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func cardChrome(radius: CGFloat = Radius.panel, kind: Material.Kind = .hud) -> some View {
        modifier(CardChrome(radius: radius, kind: kind))
    }
}

/// A subtle inset surface (chips, key caps, code blocks).
struct InsetSurface: ViewModifier {
    var radius: CGFloat = Radius.sm
    @Environment(\.palette) private var palette
    func body(content: Content) -> some View {
        content
            .background(palette.inset, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
    }
}

extension View {
    func insetSurface(radius: CGFloat = Radius.sm) -> some View { modifier(InsetSurface(radius: radius)) }
}
