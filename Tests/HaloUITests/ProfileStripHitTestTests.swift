import XCTest
import AppKit
import SwiftUI
@testable import HaloUI

/// The wheel's profile strip lives inside RadialView's hit-test shape. A wide
/// strip (ALL, ALL-New and several profiles) reaches past the circle inscribed
/// in the panel; every pill, including those outermost ones, must still get
/// its own tap. Positions come from a bare `ProfileTabBar`, so the test needs
/// no knowledge of the strip's layout.
@MainActor
final class ProfileStripHitTestTests: XCTestCase {
    private final class TestPanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }

    private final class TapRecorder {
        var last: String?
    }

    /// Points from the panel top: 18pt strip padding plus half of the capsule.
    private let stripRow: CGFloat = 35
    private let names = ["ALL", "Default", "默认", "日常", "开发", "Profile 5", "Profile 6", "Profile 7"]

    private func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func host(_ root: AnyView, side: CGFloat) -> NSPanel {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let panel = TestPanel(contentRect: NSRect(x: 200, y: 200, width: side, height: side),
                              styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        let view = NSHostingView(rootView: root)
        view.frame = NSRect(x: 0, y: 0, width: side, height: side)
        view.autoresizingMask = [.width, .height]
        panel.contentView = view
        panel.orderFrontRegardless()
        panel.makeKey()
        view.layoutSubtreeIfNeeded()
        spin(0.6)
        addTeardownBlock { panel.orderOut(nil) }
        return panel
    }

    private func click(_ panel: NSPanel, x: CGFloat, side: CGFloat) {
        let point = CGPoint(x: x, y: side - stripRow)
        func event(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                               timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: panel.windowNumber, context: nil,
                               eventNumber: 0, clickCount: 1,
                               pressure: type == .leftMouseDown ? 1 : 0)!
        }
        panel.sendEvent(event(.mouseMoved)); spin(0.004)
        panel.sendEvent(event(.leftMouseDown)); spin(0.004)
        panel.sendEvent(event(.leftMouseUp)); spin(0.006)
    }

    func test_everyPill_receivesItsTap_insideRadialView() throws {
        try XCTSkipIf(NSScreen.main == nil, "needs a window server")
        let side = HaloUI.Geometry.scaledTotalDiameter
        let pills = names.enumerated().map { index, name in
            ProfilePill(id: index == 0 ? GridProfile.id : UUID(), name: name, tint: nil)
        }
        let nameByID = Dictionary(uniqueKeysWithValues: pills.map { ($0.id, $0.name) })
        let recorder = TapRecorder()

        // Positive control: a bare strip taps every pill along the row, which
        // gives each pill's horizontal extent.
        let bare = ProfileTabBar(pills: pills, activeID: pills[6].id,
                                 onSwitch: { recorder.last = nameByID[$0] })
            .padding(.top, 18)
            .frame(width: side, height: side, alignment: .top)
        let barePanel = host(AnyView(bare), side: side)
        var extents: [String: ClosedRange<CGFloat>] = [:]
        for x in stride(from: CGFloat(0), through: side, by: 6) {
            recorder.last = nil
            click(barePanel, x: x, side: side)
            if let name = recorder.last {
                extents[name] = min(extents[name]?.lowerBound ?? x, x)...max(extents[name]?.upperBound ?? x, x)
            }
        }
        barePanel.orderOut(nil)
        XCTAssertEqual(Set(extents.keys), Set(names), "bare strip should tap every pill (harness check)")

        let state = HaloState()
        state.profilePills = pills
        state.activeProfileID = pills[6].id
        state.phase = .idle
        state.summonProgress = 1
        state.dismissProgress = 0
        state.onSwitchProfile = { recorder.last = nameByID[$0] }
        let wheelPanel = host(AnyView(RadialView(state: state)), side: side)

        var missed: [String] = []
        for name in names {
            guard let extent = extents[name] else { continue }
            recorder.last = nil
            click(wheelPanel, x: (extent.lowerBound + extent.upperBound) / 2, side: side)
            if recorder.last != name { missed.append(name) }
        }
        XCTAssertTrue(missed.isEmpty, "pills that never received a tap inside RadialView: \(missed)")
    }
}
