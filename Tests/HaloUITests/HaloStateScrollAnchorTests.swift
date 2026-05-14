import XCTest
@testable import HaloCore
@testable import HaloUI

/// State-level regression: the `scrollAnchor` field is consumed on the
/// first `advanceSelection` call within a summon, then cleared so the
/// second scroll tick advances from the *new* highlighted slot rather
/// than re-anchoring on the frontmost. Pure `SlotCycle` tests cover the
/// math; these tests pin the state mutation surrounding it.
@MainActor
final class HaloStateScrollAnchorTests: XCTestCase {
    func test_advanceSelection_consumesScrollAnchorOnce() {
        let state = HaloState()
        state.slotCount = 8
        state.phase = .idle
        state.scrollAnchor = 5  // frontmost app pinned at slot 5

        // First scroll: no hover, anchor seeds the advance from slot 5.
        state.advanceSelection(by: 1)
        guard case .hovering(let first) = state.phase else {
            return XCTFail("expected .hovering, got \(state.phase)")
        }
        XCTAssertEqual(first, 6)
        XCTAssertNil(state.scrollAnchor, "anchor should be consumed after first use")

        // Second scroll: anchor is gone; advance from currentHover (6).
        state.advanceSelection(by: 1)
        guard case .hovering(let second) = state.phase else {
            return XCTFail("expected .hovering, got \(state.phase)")
        }
        XCTAssertEqual(second, 7)
    }

    func test_advanceSelection_doesNotConsumeAnchor_whenHoverIsSet() {
        let state = HaloState()
        state.slotCount = 8
        state.scrollAnchor = 5
        state.phase = .hovering(2)  // cursor on slot 2

        state.advanceSelection(by: 1)
        guard case .hovering(let next) = state.phase else {
            return XCTFail("expected .hovering, got \(state.phase)")
        }
        XCTAssertEqual(next, 3, "should advance from hover (2), not anchor (5)")
        XCTAssertEqual(state.scrollAnchor, 5, "anchor untouched when hover wins")
    }

    func test_advanceSelection_isNoOpWhenHidden() {
        let state = HaloState()
        state.slotCount = 8
        state.phase = .hidden
        state.scrollAnchor = 5

        state.advanceSelection(by: 1)
        XCTAssertEqual(state.phase, .hidden)
        XCTAssertEqual(state.scrollAnchor, 5, "hidden no-op leaves anchor alone")
    }
}
