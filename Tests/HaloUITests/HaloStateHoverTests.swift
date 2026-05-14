import XCTest
@testable import HaloCore
@testable import HaloUI

/// Transition coverage for `HaloState.updateHover`. The function is a
/// 5×5 state-machine gate (current phase × incoming slot) that previously
/// had no direct test — regressions slipped through unless they happened
/// to break a downstream behaviour. These tests pin each branch.
@MainActor
final class HaloStateHoverTests: XCTestCase {

    func test_hidden_phase_ignoresAllUpdates() {
        let state = HaloState()
        state.slotCount = 8
        state.phase = .hidden
        state.updateHover(slot: 3)
        XCTAssertEqual(state.phase, .hidden)
        state.updateHover(slot: nil)
        XCTAssertEqual(state.phase, .hidden)
    }

    func test_idle_to_hovering_onValidSlot() {
        let state = HaloState()
        state.slotCount = 8
        state.phase = .idle
        state.updateHover(slot: 2)
        XCTAssertEqual(state.phase, .hovering(2))
    }

    func test_idle_stays_idle_onNil() {
        let state = HaloState()
        state.slotCount = 8
        state.phase = .idle
        state.updateHover(slot: nil)
        XCTAssertEqual(state.phase, .idle)
    }

    func test_hovering_to_idle_onNil() {
        let state = HaloState()
        state.slotCount = 8
        state.phase = .hovering(2)
        state.updateHover(slot: nil)
        XCTAssertEqual(state.phase, .idle)
    }

    func test_hovering_sameSlot_isNoop() {
        let state = HaloState()
        state.slotCount = 8
        state.phase = .hovering(2)
        state.updateHover(slot: 2)
        XCTAssertEqual(state.phase, .hovering(2))
    }

    func test_hovering_differentSlot_movesHover() {
        let state = HaloState()
        state.slotCount = 8
        state.phase = .hovering(2)
        state.updateHover(slot: 5)
        XCTAssertEqual(state.phase, .hovering(5))
    }

    func test_previewing_to_idle_onNil() {
        let state = HaloState()
        state.slotCount = 8
        state.phase = .previewing(2)
        state.updateHover(slot: nil)
        XCTAssertEqual(state.phase, .idle)
    }

    func test_previewing_sameSlot_isNoop() {
        let state = HaloState()
        state.slotCount = 8
        state.phase = .previewing(2)
        state.updateHover(slot: 2)
        XCTAssertEqual(state.phase, .previewing(2))
    }

    func test_previewing_differentSlot_dropsToHovering() {
        let state = HaloState()
        state.slotCount = 8
        state.phase = .previewing(2)
        state.updateHover(slot: 4)
        XCTAssertEqual(state.phase, .hovering(4))
    }

    func test_committing_phase_isLatched() {
        let state = HaloState()
        state.slotCount = 8
        state.phase = .committing(2)
        // Once committing, hover updates are inert until the next
        // summon resets phase to .hidden then .idle.
        state.updateHover(slot: 5)
        XCTAssertEqual(state.phase, .committing(2))
        state.updateHover(slot: nil)
        XCTAssertEqual(state.phase, .committing(2))
    }
}
