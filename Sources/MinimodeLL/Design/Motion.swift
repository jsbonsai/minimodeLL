import SwiftUI

/// Motion spec (`docs/design/raycast-redesign.md`, "Motion"). Every animated change goes through one of these
/// so Reduce Motion is honoured in one place: with the setting on, movement and scale collapse to a short
/// opacity crossfade, and continuous indicators stop pulsing.
enum Motion {
    /// Hover/selection highlight. 120 ms ease-out.
    static let quick: Animation = .easeOut(duration: 0.12)
    /// Default state changes (chips, status line). 200 ms ease-in-out.
    static let standard: Animation = .easeInOut(duration: 0.2)
    /// Card sections expanding or collapsing (result, approval). Gentle spring, ~320 ms settle, no overshoot.
    static let expand: Animation = .spring(response: 0.32, dampingFraction: 0.86)
    /// The panel arriving on screen. 220 ms with a slight ease-out; the AppKit side uses the same timing.
    static let panelIn: Animation = .spring(response: 0.26, dampingFraction: 0.82)
    /// Reduce Motion replacement for anything that moves or scales.
    static let crossfade: Animation = .easeInOut(duration: 0.12)

    static let panelInSeconds: TimeInterval = 0.22
    static let panelOutSeconds: TimeInterval = 0.12
    static let panelRise: CGFloat = 10
}

extension View {
    /// Animates `value` changes with `animation`, or with a crossfade under Reduce Motion.
    func motion<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(MotionModifier(animation: animation, value: value))
    }
}

private struct MotionModifier<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.animation(reduceMotion ? Motion.crossfade : animation, value: value)
    }
}

/// Section transition: rises 6 pt while fading in, drops while fading out; opacity-only under Reduce Motion.
struct SectionTransition {
    static func transition(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(insertion: .opacity.combined(with: .offset(y: 6)),
                           removal: .opacity.combined(with: .offset(y: -4)))
    }
}

/// A breathing status dot for "starting" and "running". Static under Reduce Motion.
struct PulseDot: View {
    var color: Color
    var size: CGFloat = 7
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false
    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
            .opacity(on || reduceMotion ? 1 : 0.35)
            .scaleEffect(on || reduceMotion ? 1 : 0.85)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { on = true }
            }
    }
}
