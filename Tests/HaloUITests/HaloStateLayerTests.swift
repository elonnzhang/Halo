import XCTest
import HaloCore
@testable import HaloUI

@MainActor
final class HaloStateLayerTests: XCTestCase {
    private func ctx(origin: Int = 0) -> HaloState.ActionContext {
        HaloState.ActionContext(
            bundleID: "com.test.app",
            appName: "Test",
            identityColor: IdentityColor(lightness: 0.7, chroma: 0.2, hue: 200),
            originSlotIndex: origin
        )
    }

    private func makeAction(_ label: String) -> HaloAction {
        HaloAction(label: label, kind: .openURL, payload: "https://example.com")
    }

    func test_enterActionRing_landsOnOriginSlot_andPopulatesActionSlots() {
        let state = HaloState()
        state.slotCount = 8
        state.phase = .idle
        let a = makeAction("A")
        let b = makeAction("B")

        state.enterActionRing(ctx(origin: 3), actions: [a, b])

        guard case .actions(let c) = state.layer else { return XCTFail("layer should be .actions") }
        XCTAssertEqual(c.bundleID, "com.test.app")
        XCTAssertEqual(state.actionSlots.count, 8)
        XCTAssertEqual(state.actionSlots[0].action?.label, "A")
        XCTAssertEqual(state.actionSlots[1].action?.label, "B")
        XCTAssertNil(state.actionSlots[2].action)
        XCTAssertEqual(state.phase, .hovering(3))
    }

    func test_enterActionRing_clampsOriginSlotToWheel() {
        let state = HaloState()
        state.slotCount = 6
        state.phase = .idle
        state.enterActionRing(ctx(origin: 99), actions: [])
        XCTAssertEqual(state.phase, .hovering(5))
    }

    func test_enterActionRing_isNoOpWhenHidden() {
        let state = HaloState()
        state.phase = .hidden
        state.enterActionRing(ctx(), actions: [makeAction("A")])
        XCTAssertEqual(state.layer, .slots)
        XCTAssertTrue(state.actionSlots.isEmpty)
        XCTAssertEqual(state.phase, .hidden)
    }

    func test_exitActionRing_dropsToSlotsLayer_andClearsActionSlots() {
        let state = HaloState()
        state.slotCount = 8
        state.phase = .idle
        state.enterActionRing(ctx(origin: 2), actions: [makeAction("A")])
        XCTAssertEqual(state.actionSlots.count, 8)

        state.exitActionRing()
        XCTAssertEqual(state.layer, .slots)
        XCTAssertTrue(state.actionSlots.isEmpty)
        // Phase preserved so the user lands back on the original slot.
        XCTAssertEqual(state.phase, .hovering(2))
    }

    func test_exitActionRing_isNoOpWhenAlreadyOnSlotsLayer() {
        let state = HaloState()
        state.phase = .idle
        state.exitActionRing()
        XCTAssertEqual(state.layer, .slots)
        XCTAssertEqual(state.phase, .idle)
    }
}
