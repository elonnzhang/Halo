import AppKit

/// Fires `onTriggered` when the user **double-taps** ⌘ alone (no other
/// modifiers): tap once, release, tap again within `gap` seconds. Halo
/// then stays up while the second ⌘ remains held; releasing it fires
/// `onReleased` so the AppDelegate can commit the highlighted slot.
///
/// Why double-tap instead of long-press: long-press ⌘ was reported as
/// triggering during normal ⌘ chords held a touch too long. ⌘+c is a
/// "press, hit c, release" — there's no second isolated ⌘ press, so a
/// double-tap detector ignores it. The only realistic false-positive is
/// two adjacent ⌘ chords (⌘+c → ⌘+v) where the user releases ⌘ and
/// re-presses it within `gap` AND both presses are pure (no other key in
/// between the first ⌘ down/up); the `firstTapMax` ceiling rules out most
/// such sequences because real ⌘+key presses hold ⌘ noticeably longer
/// than a deliberate ⌘ tap.
///
/// Requires no Accessibility permission — reads `NSEvent.modifierFlags`
/// synchronously, same as the previous long-press monitor.
@MainActor
public final class CommandLongPressMonitor {
    public var onTriggered: (() -> Void)?
    /// Fires once after `onTriggered` has fired and the user has released
    /// the second ⌘ tap (or added any other modifier). Mirrors HaloHotkey's
    /// `.holdReleased`.
    public var onReleased: (() -> Void)?

    /// Max delay between releasing the first ⌘ tap and pressing the second.
    /// Adjustable at runtime so Settings changes take effect without
    /// rebuilding the monitor.
    public var gap: TimeInterval
    /// Longest the first ⌘ tap can be held before we stop counting it as
    /// a tap. Real ⌘+key chords hold ⌘ longer than this; pure taps are
    /// shorter. Not user-tunable — there's no good UX argument for it.
    private let firstTapMax: TimeInterval = 0.20

    private let pollInterval: TimeInterval = 0.04

    private enum State {
        case idle
        case firstDown(since: Date)
        case firstReleased(at: Date)
        case secondDown
    }

    private var state: State = .idle
    private var timer: Timer?

    public init(gap: TimeInterval = 0.30) {
        self.gap = gap
    }

    public func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        state = .idle
    }

    private func tick() {
        let flags = NSEvent.modifierFlags
        let commandOnly = flags.contains(.command)
            && !flags.contains(.option)
            && !flags.contains(.control)
            && !flags.contains(.shift)
        let anyOtherModifier = flags.contains(.option) || flags.contains(.control) || flags.contains(.shift)
        let commandDown = flags.contains(.command)
        let now = Date()

        switch state {
        case .idle:
            if commandOnly {
                state = .firstDown(since: now)
            }

        case .firstDown(let since):
            if anyOtherModifier {
                // The user added shift/option/ctrl — not a pure ⌘ tap.
                state = .idle
                return
            }
            if !commandDown {
                let held = now.timeIntervalSince(since)
                if held <= firstTapMax {
                    state = .firstReleased(at: now)
                } else {
                    // Held too long; not a tap. Discard.
                    state = .idle
                }
            }

        case .firstReleased(let at):
            if now.timeIntervalSince(at) > gap {
                state = .idle
                return
            }
            if anyOtherModifier {
                state = .idle
                return
            }
            if commandOnly {
                state = .secondDown
                onTriggered?()
            }

        case .secondDown:
            if anyOtherModifier {
                // User pressed another modifier on top — bail without commit.
                state = .idle
                return
            }
            if !commandDown {
                onReleased?()
                state = .idle
            }
        }
    }
}
