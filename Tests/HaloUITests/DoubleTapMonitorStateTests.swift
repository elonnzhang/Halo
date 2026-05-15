import XCTest
import AppKit
@testable import HaloCore
@testable import HaloUI

/// Drives `DoubleTapMonitor`'s state machine directly via the internal
/// `tickKeyboard(matchedKeyDown:otherModifiersPresent:at:)` /
/// `tickMouse(pressed:at:)` entry points. The real Timer polls
/// `CGEventSource.flagsState` + `NSEvent.modifierFlags` /
/// `NSEvent.pressedMouseButtons`; these tests substitute the poll result
/// so transitions can be verified deterministically without hardware
/// events. Coverage spans every state transition + the suppression gate.
@MainActor
final class DoubleTapMonitorStateTests: XCTestCase {

    // MARK: keyboard path

    func test_singleTap_doesNotTrigger() {
        let (monitor, log) = makeMonitor(trigger: .command, gap: 0.30)

        monitor.tickKeyboard(matchedKeyDown: true,  otherModifiersPresent: false, at: t(0.00))
        monitor.tickKeyboard(matchedKeyDown: false, otherModifiersPresent: false, at: t(0.10))

        XCTAssertEqual(log.value.triggers, 0)
        XCTAssertEqual(log.value.releases, 0)
    }

    func test_doubleTap_inWindow_firesTriggerThenRelease() {
        let (monitor, log) = makeMonitor(trigger: .command, gap: 0.30)

        monitor.tickKeyboard(matchedKeyDown: true,  otherModifiersPresent: false, at: t(0.00))
        monitor.tickKeyboard(matchedKeyDown: false, otherModifiersPresent: false, at: t(0.10))
        monitor.tickKeyboard(matchedKeyDown: true,  otherModifiersPresent: false, at: t(0.20))
        XCTAssertEqual(log.value.triggers, 1)
        XCTAssertEqual(log.value.releases, 0)
        monitor.tickKeyboard(matchedKeyDown: false, otherModifiersPresent: false, at: t(0.40))
        XCTAssertEqual(log.value.releases, 1)
    }

    func test_secondPress_beyondGap_doesNotTrigger() {
        let (monitor, log) = makeMonitor(trigger: .command, gap: 0.30)

        monitor.tickKeyboard(matchedKeyDown: true,  otherModifiersPresent: false, at: t(0.00))
        monitor.tickKeyboard(matchedKeyDown: false, otherModifiersPresent: false, at: t(0.10))
        monitor.tickKeyboard(matchedKeyDown: true,  otherModifiersPresent: false, at: t(0.50))

        XCTAssertEqual(log.value.triggers, 0)
    }

    func test_firstTapHeldTooLong_resetsToIdle() {
        let (monitor, log) = makeMonitor(trigger: .command, gap: 0.30)

        monitor.tickKeyboard(matchedKeyDown: true,  otherModifiersPresent: false, at: t(0.00))
        // Release at 0.25s → exceeds firstTapMax (0.20s).
        monitor.tickKeyboard(matchedKeyDown: false, otherModifiersPresent: false, at: t(0.25))
        monitor.tickKeyboard(matchedKeyDown: true,  otherModifiersPresent: false, at: t(0.40))

        XCTAssertEqual(log.value.triggers, 0)
    }

    func test_otherModifierJoined_duringFirstDown_resetsToIdle() {
        let (monitor, log) = makeMonitor(trigger: .command, gap: 0.30)

        monitor.tickKeyboard(matchedKeyDown: true,  otherModifiersPresent: false, at: t(0.00))
        // ⌘ still down, ⇧ joined → reset.
        monitor.tickKeyboard(matchedKeyDown: true,  otherModifiersPresent: true,  at: t(0.05))
        monitor.tickKeyboard(matchedKeyDown: false, otherModifiersPresent: true,  at: t(0.10))
        monitor.tickKeyboard(matchedKeyDown: true,  otherModifiersPresent: false, at: t(0.20))

        XCTAssertEqual(log.value.triggers, 0)
    }

    /// Once the second tap has fired (`.secondDown`), the user is
    /// expected to layer on ⇧ to open the Action Arc. Adding the
    /// modifier must NOT drop the state machine back to idle — that
    /// would swallow the `onReleased` and force the user to click to
    /// commit instead of release-to-commit.
    func test_otherModifierJoined_duringSecondDown_stillFiresRelease() {
        let (monitor, log) = makeMonitor(trigger: .command, gap: 0.30)

        monitor.tickKeyboard(matchedKeyDown: true,  otherModifiersPresent: false, at: t(0.00))
        monitor.tickKeyboard(matchedKeyDown: false, otherModifiersPresent: false, at: t(0.10))
        monitor.tickKeyboard(matchedKeyDown: true,  otherModifiersPresent: false, at: t(0.15))
        XCTAssertEqual(log.value.triggers, 1)
        // Second ⌘ still held; user adds ⇧ (opens Action Arc).
        monitor.tickKeyboard(matchedKeyDown: true,  otherModifiersPresent: true,  at: t(0.20))
        // ⇧ still held when the user releases ⌘ — release must fire.
        monitor.tickKeyboard(matchedKeyDown: false, otherModifiersPresent: true,  at: t(0.30))

        XCTAssertEqual(log.value.releases, 1)
    }

    func test_suppressionGate_blocksTrigger_andResetsState() {
        let (monitor, log) = makeMonitor(trigger: .command, gap: 0.30)
        monitor.suppressionGate = { true }

        monitor.tickKeyboard(matchedKeyDown: true,  otherModifiersPresent: false, at: t(0.00))
        monitor.tickKeyboard(matchedKeyDown: false, otherModifiersPresent: false, at: t(0.10))
        monitor.tickKeyboard(matchedKeyDown: true,  otherModifiersPresent: false, at: t(0.20))

        XCTAssertEqual(log.value.triggers, 0, "suppression gate should swallow the trigger")
        XCTAssertEqual(monitor.state, .idle)
    }

    // MARK: middle-mouse path

    func test_middleMouse_doubleTap_triggersThenReleases() {
        let (monitor, log) = makeMonitor(trigger: .middleMouse, gap: 0.30)

        monitor.tickMouse(pressed: true,  at: t(0.00))
        monitor.tickMouse(pressed: false, at: t(0.10))
        monitor.tickMouse(pressed: true,  at: t(0.20))
        XCTAssertEqual(log.value.triggers, 1)
        monitor.tickMouse(pressed: false, at: t(0.30))
        XCTAssertEqual(log.value.releases, 1)
    }

    func test_middleMouse_secondPress_beyondGap_restartsCount() {
        let (monitor, log) = makeMonitor(trigger: .middleMouse, gap: 0.30)

        monitor.tickMouse(pressed: true,  at: t(0.00))
        monitor.tickMouse(pressed: false, at: t(0.10))
        monitor.tickMouse(pressed: true,  at: t(0.50))

        XCTAssertEqual(log.value.triggers, 0)
    }

    func test_middleMouse_firstHeldTooLong_resetsToIdle() {
        let (monitor, log) = makeMonitor(trigger: .middleMouse, gap: 0.30)

        monitor.tickMouse(pressed: true,  at: t(0.00))
        // Hold for 0.25s → exceeds firstTapMax (0.20s).
        monitor.tickMouse(pressed: false, at: t(0.25))
        monitor.tickMouse(pressed: true,  at: t(0.35))

        XCTAssertEqual(log.value.triggers, 0)
    }

    // MARK: helpers

    private struct CallLog {
        var triggers = 0
        var releases = 0
    }
    private final class Box<T> { var value: T; init(_ v: T) { self.value = v } }

    private func makeMonitor(trigger: DoubleTapTrigger, gap: TimeInterval) -> (DoubleTapMonitor, Box<CallLog>) {
        let monitor = DoubleTapMonitor(trigger: trigger, gap: gap)
        let log = Box(CallLog())
        monitor.onTriggered = { log.value.triggers += 1 }
        monitor.onReleased = { log.value.releases += 1 }
        return (monitor, log)
    }

    private func t(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }
}
