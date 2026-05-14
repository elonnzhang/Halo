import XCTest
import AppKit
@testable import HaloCore
@testable import HaloUI

/// Drives `DoubleTapMonitor`'s state machine directly via the internal
/// `handleFlagsChanged` / `handleMiddleMouseDown` / `handleMiddleMouseUp`
/// methods. NSEvent monitor wiring is not exercised; this is the pure
/// transition logic. Before this file landed the state machine had
/// **zero** coverage despite holding 5 states × 2 input paths × clock
/// gating — a swap or off-by-one would have shipped silently.
@MainActor
final class DoubleTapMonitorStateTests: XCTestCase {

    // MARK: keyboard path — ⌘ Command (keyCode 54/55)

    func test_singleTap_doesNotTrigger() {
        let (monitor, log) = makeCommandMonitor(gap: 0.30)

        // First press (matched only) → firstDown
        monitor.handleFlagsChanged(keyCode: 55, modifierFlags: [.command], at: t(0.00))
        // Release in time → firstReleased
        monitor.handleFlagsChanged(keyCode: 55, modifierFlags: [], at: t(0.10))

        XCTAssertEqual(log.value.triggers, 0)
        XCTAssertEqual(log.value.releases, 0)
    }

    func test_doubleTap_inWindow_firesTriggerThenRelease() {
        let (monitor, log) = makeCommandMonitor(gap: 0.30)

        monitor.handleFlagsChanged(keyCode: 55, modifierFlags: [.command], at: t(0.00))
        monitor.handleFlagsChanged(keyCode: 55, modifierFlags: [], at: t(0.10))
        // Second press within the 0.30s gap → triggered
        monitor.handleFlagsChanged(keyCode: 55, modifierFlags: [.command], at: t(0.20))
        XCTAssertEqual(log.value.triggers, 1)
        XCTAssertEqual(log.value.releases, 0)
        // Second release → released
        monitor.handleFlagsChanged(keyCode: 55, modifierFlags: [], at: t(0.40))
        XCTAssertEqual(log.value.releases, 1)
    }

    func test_secondPress_beyondGap_doesNotTrigger() {
        let (monitor, log) = makeCommandMonitor(gap: 0.30)

        monitor.handleFlagsChanged(keyCode: 55, modifierFlags: [.command], at: t(0.00))
        monitor.handleFlagsChanged(keyCode: 55, modifierFlags: [], at: t(0.10))
        // Second press AFTER the gap window
        monitor.handleFlagsChanged(keyCode: 55, modifierFlags: [.command], at: t(0.50))

        XCTAssertEqual(log.value.triggers, 0)
    }

    func test_firstTapHeldTooLong_resetsToIdle() {
        let (monitor, log) = makeCommandMonitor(gap: 0.30)

        monitor.handleFlagsChanged(keyCode: 55, modifierFlags: [.command], at: t(0.00))
        // Release at 0.25s → exceeds firstTapMax of 0.20s → idle, not firstReleased
        monitor.handleFlagsChanged(keyCode: 55, modifierFlags: [], at: t(0.25))
        // Even an "in-window" second press should NOT trigger
        monitor.handleFlagsChanged(keyCode: 55, modifierFlags: [.command], at: t(0.40))

        XCTAssertEqual(log.value.triggers, 0)
    }

    func test_otherModifierJoined_duringFirstDown_resetsToIdle() {
        let (monitor, log) = makeCommandMonitor(gap: 0.30)

        // Press ⌘
        monitor.handleFlagsChanged(keyCode: 55, modifierFlags: [.command], at: t(0.00))
        // ⌘ still down but user added ⇧ → state should drop to idle
        monitor.handleFlagsChanged(keyCode: 56, modifierFlags: [.command, .shift], at: t(0.05))
        // Now release ⌘
        monitor.handleFlagsChanged(keyCode: 55, modifierFlags: [.shift], at: t(0.10))
        // Second press would be a fresh start; not a trigger
        monitor.handleFlagsChanged(keyCode: 55, modifierFlags: [.command], at: t(0.20))

        XCTAssertEqual(log.value.triggers, 0)
    }

    func test_otherModifierJoined_duringSecondDown_resetsWithoutRelease() {
        let (monitor, log) = makeCommandMonitor(gap: 0.30)

        monitor.handleFlagsChanged(keyCode: 55, modifierFlags: [.command], at: t(0.00))
        monitor.handleFlagsChanged(keyCode: 55, modifierFlags: [], at: t(0.10))
        monitor.handleFlagsChanged(keyCode: 55, modifierFlags: [.command], at: t(0.15))
        XCTAssertEqual(log.value.triggers, 1)
        // Second ⌘ still held; user adds ⇧. Should reset without firing released.
        monitor.handleFlagsChanged(keyCode: 56, modifierFlags: [.command, .shift], at: t(0.20))
        // Subsequent release should NOT count as a commit.
        monitor.handleFlagsChanged(keyCode: 55, modifierFlags: [.shift], at: t(0.30))

        XCTAssertEqual(log.value.releases, 0)
    }

    func test_leftOption_doesNotMatch_rightOptionPath() {
        let (monitor, log) = makeMonitor(trigger: .leftOption, gap: 0.30)

        // Right Option = keyCode 61 — wrong key
        monitor.handleFlagsChanged(keyCode: 61, modifierFlags: [.option], at: t(0.00))
        monitor.handleFlagsChanged(keyCode: 61, modifierFlags: [], at: t(0.10))
        monitor.handleFlagsChanged(keyCode: 61, modifierFlags: [.option], at: t(0.20))

        XCTAssertEqual(log.value.triggers, 0)
    }

    func test_leftOption_matches_only_leftOption() {
        let (monitor, log) = makeMonitor(trigger: .leftOption, gap: 0.30)

        // Left Option = keyCode 58
        monitor.handleFlagsChanged(keyCode: 58, modifierFlags: [.option], at: t(0.00))
        monitor.handleFlagsChanged(keyCode: 58, modifierFlags: [], at: t(0.10))
        monitor.handleFlagsChanged(keyCode: 58, modifierFlags: [.option], at: t(0.20))

        XCTAssertEqual(log.value.triggers, 1)
    }

    func test_command_matches_eitherSideKeyCode() {
        let (monitor, log) = makeCommandMonitor(gap: 0.30)

        // First tap: left ⌘ (55), second tap: right ⌘ (54) — both should count
        monitor.handleFlagsChanged(keyCode: 55, modifierFlags: [.command], at: t(0.00))
        monitor.handleFlagsChanged(keyCode: 55, modifierFlags: [], at: t(0.10))
        monitor.handleFlagsChanged(keyCode: 54, modifierFlags: [.command], at: t(0.15))

        XCTAssertEqual(log.value.triggers, 1)
    }

    func test_suppressionGate_blocksTrigger() {
        let (monitor, log) = makeCommandMonitor(gap: 0.30)
        monitor.suppressionGate = { true }

        monitor.handleFlagsChanged(keyCode: 55, modifierFlags: [.command], at: t(0.00))
        monitor.handleFlagsChanged(keyCode: 55, modifierFlags: [], at: t(0.10))
        monitor.handleFlagsChanged(keyCode: 55, modifierFlags: [.command], at: t(0.20))

        XCTAssertEqual(log.value.triggers, 0, "suppression gate should swallow the trigger")
        // State should be back to idle after suppression
        XCTAssertEqual(monitor.state, .idle)
    }

    // MARK: middle-mouse path

    func test_middleMouse_doubleTap_triggersThenReleases() {
        let (monitor, log) = makeMonitor(trigger: .middleMouse, gap: 0.30)

        monitor.handleMiddleMouseDown(at: t(0.00))
        monitor.handleMiddleMouseUp(at: t(0.10))
        monitor.handleMiddleMouseDown(at: t(0.20))
        XCTAssertEqual(log.value.triggers, 1)
        monitor.handleMiddleMouseUp(at: t(0.30))
        XCTAssertEqual(log.value.releases, 1)
    }

    func test_middleMouse_secondPress_beyondGap_restartsCount() {
        let (monitor, log) = makeMonitor(trigger: .middleMouse, gap: 0.30)

        monitor.handleMiddleMouseDown(at: t(0.00))
        monitor.handleMiddleMouseUp(at: t(0.10))
        // Beyond gap → treated as new "firstDown"
        monitor.handleMiddleMouseDown(at: t(0.50))

        XCTAssertEqual(log.value.triggers, 0)
    }

    func test_middleMouse_firstHeldTooLong_resetsToIdle() {
        let (monitor, log) = makeMonitor(trigger: .middleMouse, gap: 0.30)

        monitor.handleMiddleMouseDown(at: t(0.00))
        // Hold for 0.25s → exceeds firstTapMax of 0.20s
        monitor.handleMiddleMouseUp(at: t(0.25))
        monitor.handleMiddleMouseDown(at: t(0.35))

        XCTAssertEqual(log.value.triggers, 0)
    }

    // MARK: helpers

    private struct CallLog {
        var triggers = 0
        var releases = 0
    }
    private final class Box<T> { var value: T; init(_ v: T) { self.value = v } }

    private func makeCommandMonitor(gap: TimeInterval) -> (DoubleTapMonitor, Box<CallLog>) {
        makeMonitor(trigger: .command, gap: gap)
    }

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
