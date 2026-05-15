import AppKit
import SwiftUI
import HaloCore

/// Transparent floating panel that hosts the radial Halo. While visible, a
/// 60 fps cursor timer polls `NSEvent.mouseLocation` and drives
/// `state.updateHover(slot:)` — that's the primary hover mechanism, because
/// `.onContinuousHover` / mouse-moved events don't reliably fire for
/// non-activating panels.
///
/// On summon we activate Halo (`NSApp.activate(ignoringOtherApps: true)`) so
/// local `NSEvent` monitors receive keystrokes (ESC, Return, digits). The
/// previous frontmost app is remembered and restored on cancel; on commit the
/// Switcher activates the target app directly.
@MainActor
public final class HaloWindow {
    public let panel: NSPanel
    private let state: HaloState
    private var cursorTimer: Timer?
    private var previousFrontApp: NSRunningApplication?
    private var rippleWindow: NSWindow?
    /// Halo windows other than the Halo panel that were visible at summon
    /// time and have been ordered-out to keep them from riding up with the
    /// overlay on macOS 12 / 13. macOS 14+ uses the targeted `NSApp.activate()`
    /// instead and leaves this empty. Restored on cancel; cleared on commit.
    private var hiddenForSummon: [NSWindow] = []

    public init(state: HaloState) {
        self.state = state
        let size = HaloUI.Geometry.scaledTotalDiameter
        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        // HaloOverlayPanel forces `canBecomeKey` — a borderless
        // `.nonactivatingPanel` otherwise refuses key focus, so keyDown for
        // Cmd+digit while the user is still holding Cmd from the double-tap
        // would route to the previously-frontmost app and fire its
        // shortcuts instead of reaching our local monitor.
        let panel = HaloOverlayPanel(
            contentRect: rect,
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
        panel.appearance = NSAppearance(named: .darkAqua)

        let host = NSHostingView(rootView: RadialView(state: state))
        host.frame = rect
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        self.panel = panel
    }

    // MARK: - Summon / dismiss

    public func summon(at origin: CGPoint? = nil) {
        // Recompute scaled size each summon — `panelScale` can change at
        // runtime via Settings without an app restart.
        let scaledSize = HaloUI.Geometry.scaledTotalDiameter
        let cursor = origin ?? NSEvent.mouseLocation
        let screen = screenContaining(cursor) ?? NSScreen.main ?? NSScreen.screens.first!
        let frame = RadialPanelFrame.frame(
            forCursor: cursor,
            in: screen.visibleFrame,
            wheelSize: scaledSize
        )
        panel.setFrame(frame, display: true)

        // Always warp the cursor to the panel centre on summon. When the
        // summon was already cursor-anchored AND no edge clamp happened
        // this is a no-op; on edge clamps or menu-bar summons it pulls
        // the cursor into the deadzone so the user can immediately point
        // out toward a slot. User directive: 鼠标始终在 Halo 圆心.
        warpCursorToPanelCentre(frame: frame)

        previousFrontApp = NSWorkspace.shared.frontmostApplication.flatMap { app in
            app.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : app
        }
        // Publish to the view layer so the centre hub can render the
        // pre-summon app's icon. Captured BEFORE NSApp.activate flips
        // frontmost to Halo itself.
        state.summonOriginBundleID = previousFrontApp?.bundleIdentifier

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        // Activate without pulling every Halo window to the front. On
        // macOS 14+ the new `NSApp.activate()` honours that intent —
        // local NSEvent monitors still fire (we need ESC / arrow / digit)
        // but an open Settings window stays where it was. macOS 12 / 13
        // only have the older `activate(ignoringOtherApps:)` which raises
        // ALL windows, so on those systems we explicitly order other Halo
        // windows out around the activation and restore them on cancel.
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            hiddenForSummon = NSApp.windows.filter {
                $0 !== panel && $0.isVisible
            }
            for win in hiddenForSummon { win.orderOut(nil) }
            NSApp.activate(ignoringOtherApps: true)
        }
        // Force key focus onto the overlay panel. Without this, the
        // previously-frontmost app stays the key window from the OS's
        // keystroke-routing perspective; Cmd+digit while the user keeps
        // Cmd held from the double-tap then fires that app's shortcut
        // instead of being delivered to our local keyDown monitor.
        panel.makeKey()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        state.center = CGPoint(x: frame.midX, y: frame.midY)
        if state.phase == .hidden { state.phase = .idle }
        installCursorTimer()
    }

    public func dismiss(animated: Bool = true, restorePreviousFront: Bool = false) {
        uninstallCursorTimer()
        state.phase = .hidden
        state.summonOriginBundleID = nil
        let restore = restorePreviousFront ? previousFrontApp : nil
        previousFrontApp = nil

        // Restore any Halo windows we hid on summon (macOS 12 / 13 path).
        // Only restore on cancel — on commit the user is switching to a
        // target app and we don't want Settings popping back into view.
        if restorePreviousFront {
            for win in hiddenForSummon { win.orderFront(nil) }
        }
        hiddenForSummon.removeAll()

        if animated {
            let panel = self.panel
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.12
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            }, completionHandler: {
                // Completion handler is called on main; hop explicitly
                // so the @MainActor isolation is statically verified.
                Task { @MainActor in
                    panel.orderOut(nil)
                    panel.alphaValue = 1
                }
            })
        } else {
            panel.orderOut(nil)
        }

        if let app = restore, !app.isTerminated {
            app.activate(options: [])
        }
    }

    // MARK: - Ripple

    public func fireRipple(color: IdentityColor) {
        let rippleSize: CGFloat = 1200
        let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        let rect = NSRect(x: center.x - rippleSize / 2,
                          y: center.y - rippleSize / 2,
                          width: rippleSize, height: rippleSize)

        let win = NSPanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        win.level = .popUpMenu
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.contentView = NSHostingView(rootView: RippleView(color: color))
        win.orderFrontRegardless()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { [weak win] in
            win?.orderOut(nil)
        }
    }

    // MARK: - Cursor timer

    private func installCursorTimer() {
        cursorTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateHoverFromCursor() }
        }
        RunLoop.main.add(timer, forMode: .common)
        cursorTimer = timer
    }

    private func uninstallCursorTimer() {
        cursorTimer?.invalidate()
        cursorTimer = nil
    }

    private func updateHoverFromCursor() {
        let mouse = NSEvent.mouseLocation
        // Panel frame is screen coords, y-up. The SwiftUI root inside the
        // panel is `scaleEffect(panelScale)`-ed, so the unscaled view
        // coordinates we feed `RadialGeometry` need the cursor offset
        // divided by `panelScale` before centering.
        let scale = HaloUI.Geometry.panelScale
        let local = CGPoint(
            x: (mouse.x - panel.frame.minX) / scale,
            y: (mouse.y - panel.frame.minY) / scale
        )
        let size = HaloUI.Geometry.totalDiameter
        // Centered: NSEvent.mouseLocation is y-up (Cocoa convention), and
        // panel.frame.minY is also y-up. After subtracting (size/2, size/2)
        // we have a math-convention point (y-up, +y is "up the screen").
        let centered = CGPoint(
            x: local.x - size / 2,
            y: local.y - size / 2
        )

        // Arc active: hit-test chips first. Chips sit outside the wheel's
        // reach radius and would never register on the slot path.
        if let arc = state.activeArc {
            let chipIdx = ActionArcGeometry.chipIndex(
                forCenteredPoint: centered,
                slotIndex: arc.slotIndex,
                sectorCount: state.slotCount,
                chipCount: arc.chips.count
            )
            if state.arcHoverChip != chipIdx {
                state.arcHoverChip = chipIdx
            }
            // The slot fall-through below still runs intentionally: we want
            // the underlying slot to stay lit so the user knows which slot
            // the arc belongs to. Chip hover and slot hover coexist; commit
            // dispatch in AppDelegate gives the chip priority when both
            // are set.
        }

        // outerRadius uses `reachDiameter` (1.5× wheel) by default so the
        // cursor counts as hovering a sector anywhere within that wider
        // invisible cushion. While the arc is up we shrink to 1× (just the
        // visible disc) so the cursor moving outward to a chip doesn't
        // also drag the underlying slot hover around — the arc stays
        // anchored to its slot, and chip hover takes priority.
        let outerRadius: CGFloat = state.activeArc == nil
            ? HaloUI.Geometry.reachDiameter / 2
            : HaloUI.Geometry.visibleOuterRadius
        let index = RadialGeometry.sectorIndex(
            for: centered,
            sectorCount: state.slotCount,
            innerRadius: HaloUI.Geometry.deadzoneDiameter / 2,
            outerRadius: outerRadius
        )
        state.updateHover(slot: index)
    }

    // MARK: - Screen helpers

    private func screenContaining(_ point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }

    /// Move the system cursor to the panel's geometric centre.
    /// `CGWarpMouseCursorPosition` takes global display coordinates
    /// (origin at the top-left of NSScreen[0], y-down), so we flip the
    /// Cocoa y-up frame.midY against the primary screen's height.
    private func warpCursorToPanelCentre(frame: NSRect) {
        guard let primary = NSScreen.screens.first else { return }
        let centreCocoa = CGPoint(x: frame.midX, y: frame.midY)
        let globalY = primary.frame.height - centreCocoa.y
        CGWarpMouseCursorPosition(CGPoint(x: centreCocoa.x, y: globalY))
        // Re-associate after warp so subsequent movement deltas are
        // applied — `CGWarpMouseCursorPosition` documents that the mouse
        // and cursor stay associated by default, but a defensive call
        // here also resets any prior dissociate state.
        CGAssociateMouseAndMouseCursorPosition(1)
    }
}

/// A borderless `.nonactivatingPanel` defaults `canBecomeKey` to false,
/// which prevents our local keyDown monitor from receiving events while
/// the user keeps Cmd held from the double-tap summon. Forcing the
/// override (same trick `WelcomeOverlayPanel` uses) lets the panel take
/// key focus without flipping activation policy or stealing the dock.
private final class HaloOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
