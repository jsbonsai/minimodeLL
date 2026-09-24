import AppKit
import SwiftUI

/// Borderless, non-activating floating panel that hosts the command bar. The window is transparent; the
/// SwiftUI card draws its own material, corners and hairline, and AppKit computes the shadow from the card's alpha.
///
/// Non-activating means summoning the bar does not switch the frontmost app (like Spotlight), yet the panel
/// becomes key so typing goes straight to the input. It hides when it loses key status, and never appears in
/// the window list or Mission Control (`.transient`).
final class CommandBarPanel: NSPanel {
    init(contentView: NSView) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: CommandBarLayout.width, height: CommandBarLayout.headerHeight),
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        // Launchers stay put; dragging the card would also fight the top-anchored resize (`anchorTop`).
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        self.contentView = contentView
        setAccessibilityRole(.window)
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    /// Esc anywhere in the panel closes it (also reached through the responder chain from the text field).
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    var onCancel: (() -> Void)?

    /// Places the panel horizontally centred on the screen under the mouse, its top edge at ~22 % of the
    /// visible height, like system launchers. `height` is the card height.
    private var top: CGFloat = 0
    func place(height: CGFloat) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let width = CommandBarLayout.width
        top = (visible.maxY - visible.height * 0.22).rounded()
        let origin = NSPoint(x: (visible.midX - width / 2).rounded(), y: top - height)
        setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
    }

    /// AppKit grows a window from its bottom-left corner; keep the top edge where `place` put it.
    func anchorTop() {
        guard top > 0, frame.maxY != top else { return }
        setFrameOrigin(NSPoint(x: frame.minX, y: top - frame.height))
        invalidateShadow()
    }

    /// Resizes to the card's height keeping the top edge fixed. Called on every layout pass while the SwiftUI
    /// card animates, so the window tracks the animation frame by frame.
    func follow(height: CGFloat) {
        guard height > 0, abs(frame.height - height) >= 0.5 else { return }
        let top = frame.maxY
        setFrame(NSRect(x: frame.minX, y: top - height, width: frame.width, height: height), display: true)
        invalidateShadow()
    }
}
