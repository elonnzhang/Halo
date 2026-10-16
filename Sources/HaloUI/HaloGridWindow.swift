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
    /// 60 fps cursor poll that drives the hovered-app selection while the
    /// grid is up. SwiftUI `.onHover` inside the borderless panel is
    /// shadowed by the full-frame pan gesture, so we resolve hover the same
    /// way the wheel does — poll `NSEvent.mouseLocation` and hit-test.
    private var hoverTimer: Timer?
    private var lastHoverLocation: CGPoint?

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
        // Required for SwiftUI `.onHover` inside a borderless nonactivating
        // panel to fire as the cursor moves between cells. Without this the
        // panel never delivers mouseMoved, so `selectedBundleID` only
        // updates on click and the bottom name badge appears "stuck".
        panel.acceptsMouseMovedEvents = true
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

        startHoverTimer()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func startHoverTimer() {
        hoverTimer?.invalidate()
        lastHoverLocation = NSEvent.mouseLocation
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateHover() }
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    private func stopHoverTimer() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        lastHoverLocation = nil
    }

    /// Convert the global cursor to the hosting view's coordinates (top-left
    /// origin, y-down to match SwiftUI) and let `GridState` resolve which
    /// app is under it. `HoneycombGridView` writes its projected cell frames
    /// into `gridState.cellFrames` in the same coordinate space.
    private func updateHover() {
        guard panel.isVisible, state.isGridMode else { return }
        let mouse = NSEvent.mouseLocation                 // screen, y-up
        // A stationary cursor must not overwrite keyboard/search selection,
        // nor continually select different icons as the constellation coasts.
        guard mouse != lastHoverLocation else { return }
        lastHoverLocation = mouse
        let f = panel.frame
        guard f.contains(mouse) else {
            // The lens keeps its centred app selected; the flat sheet clears.
            let fallback = state.gridState.style == .lens ? state.gridState.lens.centredID : nil
            if state.gridState.selectedBundleID != fallback {
                state.gridState.selectedBundleID = fallback
            }
            return
        }
        // Panel origin is bottom-left (y-up). SwiftUI view space is
        // top-left (y-down): flip y within the panel height.
        let localX = mouse.x - f.minX
        let localY = f.maxY - mouse.y
        let iconSize = HoneycombGridView.baseIconSize
            * state.gridState.zoomLevel
            * HaloUI.Geometry.panelScale
        state.gridState.hoverSelect(at: CGPoint(x: localX, y: localY), iconSize: iconSize)
    }

    /// Hide the grid, optionally with a fade-out. The fade matches the
    /// wheel's dismiss timing (0.18s ease-in) so a Tab off-and-on of
    /// the ALL profile feels like a single coherent transition.
    public func dismiss(animated: Bool = true) {
        stopHoverTimer()
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
