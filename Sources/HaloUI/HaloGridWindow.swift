import AppKit
import SwiftUI
import HaloCore

/// Full-screen translucent NSPanel that hosts `HoneycombGridView`.
///
/// Sized to the screen's full `frame` (not `visibleFrame`) so the grid
/// covers the menu bar and Dock — watchOS Launchpad style. Activates
/// the app on summon so the AppDelegate's local key + scroll monitors
/// pick up ESC / Tab / arrow / scroll while the grid is on screen, and
/// hands focus back to the wheel panel (and ultimately to the launched
/// app) on dismiss.
///
/// Mirrors the lifecycle of `HaloWindow` — separate panel, but the same
/// summon / dismiss / order-out semantics so the AppDelegate can swap
/// between the two without reasoning about platform-specific window
/// mechanics in two places.
@MainActor
public final class HaloGridWindow {
    public let panel: NSPanel
    private let state: HaloState
    /// Halo windows other than the grid panel that were visible at
    /// summon time — same trick `HaloWindow` uses on macOS 12 / 13 so
    /// `NSApp.activate(ignoringOtherApps:)` doesn't haul Settings up
    /// with the overlay.
    private var hiddenForSummon: [NSWindow] = []

    public init(state: HaloState) {
        self.state = state
        let initialFrame = NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        // `HaloOverlayPanel` (defined in HaloWindow.swift) forces
        // `canBecomeKey = true` so a borderless `.nonactivatingPanel`
        // can still take key focus — the grid needs it for ESC / Tab
        // delivery.
        let panel = HaloGridOverlayPanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false

        let host = NSHostingView(rootView: HoneycombGridView(state: state))
        host.frame = initialFrame
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        self.panel = panel
    }

    // MARK: - Summon / dismiss

    /// Show the grid on whichever screen the cursor lives on. Activates
    /// Halo so local NSEvent monitors fire (ESC / Tab / scroll). The
    /// frame covers the **Dock** (extends to `frame.minY`) and the full
    /// screen width, but stops short of the **menu bar** at the top —
    /// menu bars on notched displays run flush with the notch hardware
    /// in black, so a panel that ran underneath would create a visible
    /// notch step on summon. The fade-in mirrors `HaloWindow.summon`'s
    /// 0.16s alpha so the cross-fade between wheel and grid reads as
    /// one motion.
    public func summon() {
        let cursor = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(cursor) }
            ?? NSScreen.main
            ?? NSScreen.screens.first!
        let frame = screen.frame
        let visible = screen.visibleFrame
        // Cocoa y-up: extend top to visibleFrame.maxY (just below the
        // menu bar), bottom to frame.minY (cover the Dock area).
        let target = NSRect(
            x: frame.minX,
            y: frame.minY,
            width: frame.width,
            height: visible.maxY - frame.minY
        )
        panel.setFrame(target, display: true)

        panel.alphaValue = 0
        panel.orderFrontRegardless()

        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            hiddenForSummon = NSApp.windows.filter {
                $0 !== panel && $0.isVisible
            }
            for win in hiddenForSummon { win.orderOut(nil) }
            NSApp.activate(ignoringOtherApps: true)
        }
        panel.makeKey()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    /// Hide the grid, optionally with a fade-out. The fade matches the
    /// wheel's dismiss timing (0.18s ease-in) so a Tab off-and-on of
    /// the ALL profile feels like a single coherent transition.
    public func dismiss(animated: Bool = true) {
        if animated {
            let panel = self.panel
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.16
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            }, completionHandler: {
                Task { @MainActor in
                    panel.orderOut(nil)
                    panel.alphaValue = 1
                }
            })
        } else {
            panel.orderOut(nil)
            panel.alphaValue = 1
        }
        // Restore any Halo windows we hid on summon (macOS 12 / 13 path).
        for win in hiddenForSummon { win.orderFront(nil) }
        hiddenForSummon.removeAll()
    }
}

/// Borderless `.nonactivatingPanel` defaults `canBecomeKey` to false. Same
/// override the wheel uses (`HaloOverlayPanel` in `HaloWindow.swift`); kept
/// private here so the grid window is self-contained.
private final class HaloGridOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
