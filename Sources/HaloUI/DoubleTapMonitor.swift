import AppKit
import CoreGraphics
import HaloCore

/// Detects a double-tap on the configured `DoubleTapTrigger` and emits
/// `onTriggered` on the second press, `onReleased` on the second release.
///
/// Implementation: a 25 Hz `Timer` polls the live keyboard / mouse state.
///   - `CGEventSource.keyState(.combinedSessionState, key: <keyCode>)`
///     for keyboard triggers — keyCode-discriminated so left vs right
///     Option / Control are distinguishable.
///   - `NSEvent.pressedMouseButtons` bitmask for middle mouse.
///   - `NSEvent.modifierFlags` for the "other modifier joined" check
///     that rejects ⌘+key chords as accidental taps.
///
/// All three APIs are passive state queries — no Accessibility permission
/// needed, no event tap, no entitlement. v1.0's `CommandLongPressMonitor`
/// used the same idiom (just keyboard-only).
@MainActor
public final class DoubleTapMonitor {
    public var onTriggered: (() -> Void)?
    public var onReleased: (() -> Void)?

    /// Max delay between releasing the first tap and pressing the
    /// second. Mutable at runtime so Settings changes take effect
    /// without rebuilding the monitor.
    public var gap: TimeInterval

    /// Which physical key/button this monitor watches. Changing it
    /// resets the state machine so a half-completed tap on the old
    /// trigger doesn't survive the switch.
    public var trigger: DoubleTapTrigger {
        didSet {
            if oldValue != trigger { state = .idle }
        }
    }

    /// Optional gate: when this returns true the monitor swallows the
    /// gesture without firing `onTriggered`. Used by AppDelegate to
    /// enforce the whitelist suppression.
    public var suppressionGate: (() -> Bool)?

    /// Longest the first tap can be held before we stop counting it as
    /// a tap. Real chord presses hold longer than this; pure taps don't.
    private let firstTapMax: TimeInterval = 0.20
    private let pollInterval: TimeInterval = 0.04

    /// Internal access so HaloUITests can drive the state machine
    /// synthetically without spinning the real Timer.
    enum State: Equatable {
        case idle
        case firstDown(since: Date)
        case firstReleased(at: Date)
        case secondDown
    }
    var state: State = .idle

    private var timer: Timer?

    /// `NSEvent.pressedMouseButtons` bit position for the middle button
    /// (Mouse 3). Bit 0 = left, 1 = right, 2 = middle.
    private static let middleMouseMask: Int = 1 << 2

    public init(trigger: DoubleTapTrigger, gap: TimeInterval) {
        self.trigger = trigger
        self.gap = gap
    }

    public func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        state = .idle
    }

    private func tick() {
        let now = Date()
        switch trigger {
        case .leftOption:
            tickKeyboard(matchedKeyDown: Self.isKeyDown(58),
                         otherModifiersPresent: otherModifiers(excluding: .option),
                         at: now)
        case .rightOption:
            tickKeyboard(matchedKeyDown: Self.isKeyDown(61),
                         otherModifiersPresent: otherModifiers(excluding: .option),
                         at: now)
        case .command:
            // Accept either side of the Command key (54 / 55).
            let matched = Self.isKeyDown(54) || Self.isKeyDown(55)
            tickKeyboard(matchedKeyDown: matched,
                         otherModifiersPresent: otherModifiers(excluding: .command),
                         at: now)
        case .control:
            let matched = Self.isKeyDown(59) || Self.isKeyDown(62)
            tickKeyboard(matchedKeyDown: matched,
                         otherModifiersPresent: otherModifiers(excluding: .control),
                         at: now)
        case .middleMouse:
            let pressed = (NSEvent.pressedMouseButtons & Self.middleMouseMask) != 0
            tickMouse(pressed: pressed, at: now)
        }
    }

    /// `CGEventSource.keyState` reads HID-level keyboard state without
    /// needing Accessibility — same trust level as
    /// `NSEvent.modifierFlags`. Wrap into a typed helper for clarity.
    private static func isKeyDown(_ keyCode: CGKeyCode) -> Bool {
        CGEventSource.keyState(.combinedSessionState, key: keyCode)
    }

    private func otherModifiers(excluding match: NSEvent.ModifierFlags) -> Bool {
        var others: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        others.remove(match)
        return !NSEvent.modifierFlags.intersection(others).isEmpty
    }

    // MARK: - Keyboard state machine

    /// Visible internally so HaloUITests can drive transitions with
    /// synthetic (matchedDown, otherPresent) inputs + clock stamps.
    func tickKeyboard(matchedKeyDown: Bool, otherModifiersPresent: Bool, at now: Date) {
        let onlyMatched = matchedKeyDown && !otherModifiersPresent

        switch state {
        case .idle:
            if onlyMatched { state = .firstDown(since: now) }
        case .firstDown(let since):
            if matchedKeyDown && otherModifiersPresent {
                state = .idle
                return
            }
            if !matchedKeyDown {
                let held = now.timeIntervalSince(since)
                state = (held <= firstTapMax) ? .firstReleased(at: now) : .idle
            }
        case .firstReleased(let at):
            if now.timeIntervalSince(at) > gap {
                state = .idle
                return
            }
            if matchedKeyDown && otherModifiersPresent {
                state = .idle
                return
            }
            if onlyMatched {
                if suppressionGate?() == true {
                    state = .idle
                    return
                }
                state = .secondDown
                onTriggered?()
            }
        case .secondDown:
            if matchedKeyDown && otherModifiersPresent {
                state = .idle
                return
            }
            if !matchedKeyDown {
                onReleased?()
                state = .idle
            }
        }
    }

    // MARK: - Mouse state machine

    /// Internal entry for tests; the real Timer feeds the polled
    /// `NSEvent.pressedMouseButtons` bit mask result.
    func tickMouse(pressed: Bool, at now: Date) {
        switch state {
        case .idle:
            if pressed { state = .firstDown(since: now) }
        case .firstDown(let since):
            if !pressed {
                let held = now.timeIntervalSince(since)
                state = (held <= firstTapMax) ? .firstReleased(at: now) : .idle
            }
        case .firstReleased(let at):
            if now.timeIntervalSince(at) > gap {
                if pressed {
                    state = .firstDown(since: now)
                } else {
                    state = .idle
                }
                return
            }
            if pressed {
                if suppressionGate?() == true {
                    state = .idle
                    return
                }
                state = .secondDown
                onTriggered?()
            }
        case .secondDown:
            if !pressed {
                onReleased?()
                state = .idle
            }
        }
    }
}
