import XCTest
import HaloCore
@testable import HaloUI

@MainActor
final class HaloStateArcTests: XCTestCase {
    private func makeArc(slot: Int = 3) -> ActiveArc {
        ActiveArc(
            slotIndex: slot,
            bundleID: "com.test.app",
            appName: "Test",
            chips: [
                .builtin(.quit),
                .builtin(.fullscreenToggle),
                .builtin(.hide),
                .emptyCustom,
            ],
            appIsFullscreen: false,
            axGranted: true
        )
    }

    func test_showArc_setsActiveArc_andClearsHoverChip() {
        let state = HaloState()
        state.phase = .idle
        state.arcHoverChip = 99
        state.showArc(makeArc(slot: 2))
        XCTAssertEqual(state.activeArc?.slotIndex, 2)
        XCTAssertNil(state.arcHoverChip)
    }

    func test_showArc_isNoOpWhenHidden() {
        let state = HaloState()
        state.phase = .hidden
        state.showArc(makeArc())
        XCTAssertNil(state.activeArc)
    }

    func test_hideArc_clearsState() {
        let state = HaloState()
        state.phase = .idle
        state.showArc(makeArc())
        state.arcHoverChip = 1
        state.hideArc()
        XCTAssertNil(state.activeArc)
        XCTAssertNil(state.arcHoverChip)
    }
}

final class ActionArcGeometryTests: XCTestCase {
    func test_chipCenters_landOnExpectedRadius() {
        // 4 chips, slot 0 (12 o'clock), N=8.
        for i in 0..<4 {
            let p = ActionArcGeometry.chipCenter(
                chipIndex: i,
                slotIndex: 0,
                sectorCount: 8,
                chipCount: 4
            )
            let r = (p.x * p.x + p.y * p.y).squareRoot()
            XCTAssertEqual(r, ActionArcGeometry.arcRadius, accuracy: 0.001)
        }
    }

    func test_chipHitTest_findsClosestChip_orNilOutside() {
        let center = ActionArcGeometry.chipCenter(
            chipIndex: 1, slotIndex: 0, sectorCount: 8, chipCount: 4
        )
        // The cursor timer feeds points in SwiftUI y-down coordinates (the
        // helper inverts internally), so to land on chip 1 we pass the
        // flipped y.
        let cursorOnChip = CGPoint(x: center.x, y: -center.y)
        XCTAssertEqual(
            ActionArcGeometry.chipIndex(
                forCenteredPoint: cursorOnChip,
                slotIndex: 0, sectorCount: 8, chipCount: 4
            ),
            1
        )
        // Way outside the wheel — nothing.
        XCTAssertNil(
            ActionArcGeometry.chipIndex(
                forCenteredPoint: CGPoint(x: 800, y: 800),
                slotIndex: 0, sectorCount: 8, chipCount: 4
            )
        )
        // Centre of wheel — no chip.
        XCTAssertNil(
            ActionArcGeometry.chipIndex(
                forCenteredPoint: .zero,
                slotIndex: 0, sectorCount: 8, chipCount: 4
            )
        )
    }
}
