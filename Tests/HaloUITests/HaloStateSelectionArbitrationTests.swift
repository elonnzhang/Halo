import XCTest
@testable import HaloCore
@testable import HaloUI

/// Scroll wheel / arrow keys vs. the cursor poll. The poll re-samples the
/// sector under the cursor every frame; a parked cursor must not undo a slot
/// the user just chose with the wheel or keys, while real pointer movement
/// takes the highlight back.
@MainActor
final class HaloStateSelectionArbitrationTests: XCTestCase {
    private func summoned(hovering slot: Int? = nil) -> HaloState {
        let state = HaloState()
        state.slotCount = 8
        state.phase = slot.map { .hovering($0) } ?? .idle
        return state
    }

    func test_scrolledSlot_survivesParkedCursorInHub() {
        let state = summoned()
        state.advanceSelection(by: 1)
        state.updateHover(slot: nil, pointerMoved: false)
        XCTAssertEqual(state.phase, .hovering(1))
        XCTAssertTrue(state.inputOwnsSelection)
    }

    func test_scrolledSlot_survivesParkedCursorOverAnotherSlot() {
        let state = summoned(hovering: 2)
        state.advanceSelection(by: 1)
        state.updateHover(slot: 2, pointerMoved: false)
        XCTAssertEqual(state.phase, .hovering(3))
    }

    func test_successiveScrollSteps_continueFromTheScrolledSlot() {
        let state = summoned(hovering: 2)
        for expected in [3, 4, 5] {
            state.advanceSelection(by: 1)
            state.updateHover(slot: 2, pointerMoved: false)
            XCTAssertEqual(state.phase, .hovering(expected))
        }
    }

    func test_pointerMovingOverASlot_takesTheHighlightBack() {
        let state = summoned(hovering: 2)
        state.advanceSelection(by: 1)
        state.updateHover(slot: 6, pointerMoved: true)
        XCTAssertEqual(state.phase, .hovering(6))
        XCTAssertFalse(state.inputOwnsSelection)
        // The pointer owns the highlight again, so a later parked sample applies normally.
        state.updateHover(slot: 5, pointerMoved: false)
        XCTAssertEqual(state.phase, .hovering(5))
    }

    func test_pointerMovingIntoTheHub_clearsTheScrolledSlot() {
        let state = summoned()
        state.advanceSelection(by: 1)
        state.updateHover(slot: nil, pointerMoved: true)
        XCTAssertEqual(state.phase, .idle)
        XCTAssertFalse(state.inputOwnsSelection)
    }

    func test_dragGesturePath_defaultsToPointerMoved() {
        let state = summoned()
        state.advanceSelection(by: 1)
        state.updateHover(slot: 4)
        XCTAssertEqual(state.phase, .hovering(4))
    }

    func test_hidingEndsInputOwnership() {
        let state = summoned()
        state.advanceSelection(by: 1)
        state.phase = .hidden
        state.phase = .idle
        XCTAssertFalse(state.inputOwnsSelection)
        state.updateHover(slot: 3, pointerMoved: false)
        XCTAssertEqual(state.phase, .hovering(3))
    }

    func test_profileSwitchResetToIdle_endsInputOwnership() {
        let state = summoned()
        state.advanceSelection(by: 1)
        state.phase = .idle
        state.updateHover(slot: 3, pointerMoved: false)
        XCTAssertEqual(state.phase, .hovering(3))
    }

    func test_advanceSelectionWhileHidden_doesNotClaimTheSelection() {
        let state = HaloState()
        state.slotCount = 8
        state.advanceSelection(by: 1)
        XCTAssertEqual(state.phase, .hidden)
        XCTAssertFalse(state.inputOwnsSelection)
        XCTAssertEqual(state.inputSelectionGeneration, 0)
    }

    func test_everyStep_startsANewInputGeneration() {
        let state = summoned()
        state.advanceSelection(by: 1)
        let first = state.inputSelectionGeneration
        state.advanceSelection(by: 1)
        XCTAssertNotEqual(state.inputSelectionGeneration, first,
                          "the cursor poll re-baselines on each step, so each step must be distinguishable")
    }
}
