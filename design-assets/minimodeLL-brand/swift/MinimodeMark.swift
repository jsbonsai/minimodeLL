import SwiftUI

/// The minimodeLL "Twin L" mark as a native, resolution-independent SwiftUI view.
/// Drawn on the brand's 64-unit grid; scales to any frame while keeping proportions.
public struct MinimodeMark: View {
    public enum State { case active, idle, off }

    public var state: State = .active
    public var ink: Color = Color("BrandInk")
    public var dot: Color = Color("AccentColor")

    public init(state: State = .active, ink: Color = Color("BrandInk"), dot: Color = Color("AccentColor")) {
        self.state = state; self.ink = ink; self.dot = dot
    }

    public var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height) / 64
            ZStack {
                TwinL()
                    .stroke(ink, style: StrokeStyle(lineWidth: 7 * s, lineCap: .round, lineJoin: .round))
                switch state {
                case .active:
                    Circle().fill(dot)
                        .frame(width: 11 * s, height: 11 * s)
                        .position(x: 49 * s, y: 15 * s)
                case .idle:
                    Circle().stroke(dot, lineWidth: 2.5 * s)
                        .frame(width: 8.5 * s, height: 8.5 * s)
                        .position(x: 49 * s, y: 15 * s)
                case .off:
                    EmptyView()
                }
            }
            .frame(width: 64 * s, height: 64 * s)
            .animation(.easeOut(duration: 0.2), value: state)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// The two nested L strokes (centre-line path; stroke at 7/64 of the size).
public struct TwinL: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 64
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var path = Path()
        path.move(to: p(14, 10)); path.addLine(to: p(14, 50)); path.addLine(to: p(40, 50))
        path.move(to: p(27, 10)); path.addLine(to: p(27, 37)); path.addLine(to: p(50, 37))
        return path
    }
}

// Menu bar usage (AppKit):
//   let image = NSImage(named: "MenuBarIconTemplate")   // template-rendered automatically
//   statusItem.button?.image = image
// Swap to "MenuBarIconIdleTemplate" / "MenuBarIconOffTemplate" to reflect server state.
//
// MenuBarExtra (SwiftUI):
//   MenuBarExtra("minimodeLL", image: "MenuBarIconTemplate") { ContentView() }
