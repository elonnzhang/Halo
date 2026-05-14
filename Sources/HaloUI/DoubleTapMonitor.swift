import AppKit
import HaloCore

/// Detects a double-tap on the configured `DoubleTapTrigger` and emits
/// `onTriggered` on the second press, `onReleased` on the second release.
///
/// Keyboard paths listen to `flagsChanged` (with keyCode discrimination
/// for L/R Option / L/R Control / L/R Command — macOS doesn't publish a
/// stable left/right bit in `NSEvent.ModifierFlags`, so we match the raw
/// keyCode). The middle-mouse path listens to `otherMouseDown` /
/// `otherMouseUp` filtered to `buttonNumber == 2`.
///
/// Both local AND global monitors are installed for every path so the
/// detector fires regardless of which app is frontmost. Local catches
/// events when Halo/Settings is key; global catches everything else.
/// The Carbon hotkey path (`HaloHotkey`) is unaffected — this monitor is
/// strictly the second, single-handed trigger.
@MainActor
public final class DoubleTapMonitor {
    public var onTriggered: (() -> Void)?
    public var onReleased: (() -> Void)?

    /// Max delay between releasing the first tap and pressing the second.
    /// Mutable at runtime so Settings changes take effect without
    /// rebuilding the monitor.
    public var gap: TimeInterval

    /// Which physical key/button this monitor watches. Changing it tears
    /// down + reinstalls the underlying event monitors so we never tap
    /// `.flagsChanged` and `.otherMouseDown` at the same time.
    public var trigger: DoubleTapTrigger {
        didSet {
            if oldValue != trigger {
                let wasRunning = (localFlagsMonitor != nil
                    || globalFlagsMonitor != nil
                    || localMouseDownMonitor != nil
                    || globalMouseDownMonitor != nil)
                if wasRunning { rebuildMonitors() }
            }
        }
    }

    /// Optional gate: when this returns true, the monitor swallows the
    /// gesture without firing `onTriggered`. Used by AppDelegate to
    /// enforce the whitelist suppression.
    public var suppressionGate: (() -> Bool)?

    /// Longest the first tap can be held before we stop counting it as
    /// a tap. Real chord presses hold longer than this; pure taps don't.
    private let firstTapMax: TimeInterval = 0.20

    private enum State {
        case idle
        case firstDown(since: Date)
        case firstReleased(at: Date)
        case secondDown
    }
    private var state: State = .idle

    private var localFlagsMonitor: Any?
    private var globalFlagsMonitor: Any?
    private var localMouseDownMonitor: Any?
    private var globalMouseDownMonitor: Any?
    private var localMouseUpMonitor: Any?
    private var globalMouseUpMonitor: Any?

    public init(trigger: DoubleTapTrigger, gap: TimeInterval) {
        self.trigger = trigger
        self.gap = gap
    }

    public func start() {
        rebuildMonitors()
    }

    public func stop() {
        for token in [localFlagsMonitor, globalFlagsMonitor,
                      localMouseDownMonitor, globalMouseDownMonitor,
                      localMouseUpMonitor, globalMouseUpMonitor] {
            if let token = token { NSEvent.removeMonitor(token) }
        }
        localFlagsMonitor = nil
        globalFlagsMonitor = nil
        localMouseDownMonitor = nil
        globalMouseDownMonitor = nil
        localMouseUpMonitor = nil
        globalMouseUpMonitor = nil
        state = .idle
    }

    private func rebuildMonitors() {
        stop()
        if trigger.isKeyboard {
            installFlagsMonitors()
        } else {
            installMouseMonitors()
        }
    }

    // MARK: - Keyboard path

    /// kVK_LeftOption=58, kVK_RightOption=61,
    /// kVK_RightCommand=54, kVK_Command=55,
    /// kVK_Control=59, kVK_RightControl=62.
    private func keyCodeMatches(_ code: UInt16) -> Bool {
        switch trigger {
        case .leftOption:   return code == 58
        case .rightOption:  return code == 61
        case .command:      return code == 54 || code == 55
        case .control:      return code == 59 || code == 62
        case .middleMouse:  return false
        }
    }

    private func installFlagsMonitors() {
        let handler: (NSEvent) -> Void = { [weak self] event in
            guard let self = self else { return }
            self.handleFlagsChanged(event)
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { event in
            handler(event)
            return event
        }
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { event in
            handler(event)
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let keyCode = event.keyCode
        let isMatchedKey = keyCodeMatches(keyCode)
        let now = Date()

        let pressed = matchedFlagPresent(in: event.modifierFlags)
        let onlyMatchedDown = pressed && !otherModifierPresent(matched: trigger, flags: event.modifierFlags)

        switch state {
        case .idle:
            if isMatchedKey && onlyMatchedDown {
                state = .firstDown(since: now)
            }
        case .firstDown(let since):
            if pressed && !onlyMatchedDown {
                state = .idle
                return
            }
            if isMatchedKey && !pressed {
                let held = now.timeIntervalSince(since)
                state = (held <= firstTapMax) ? .firstReleased(at: now) : .idle
            }
        case .firstReleased(let at):
            if now.timeIntervalSince(at) > gap {
                state = .idle
                return
            }
            if isMatchedKey && onlyMatchedDown {
                if suppressionGate?() == true {
                    state = .idle
                    return
                }
                state = .secondDown
                onTriggered?()
            }
        case .secondDown:
            if isMatchedKey && !pressed {
                onReleased?()
                state = .idle
            } else if !isMatchedKey && pressed {
                // Another modifier joined; abandon without commit.
                state = .idle
            }
        }
    }

    private func matchedFlagPresent(in flags: NSEvent.ModifierFlags) -> Bool {
        switch trigger {
        case .leftOption, .rightOption: return flags.contains(.option)
        case .command:                  return flags.contains(.command)
        case .control:                  return flags.contains(.control)
        case .middleMouse:              return false
        }
    }

    private func otherModifierPresent(matched: DoubleTapTrigger, flags: NSEvent.ModifierFlags) -> Bool {
        var others: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        switch matched {
        case .leftOption, .rightOption: others.remove(.option)
        case .command:                  others.remove(.command)
        case .control:                  others.remove(.control)
        case .middleMouse:              break
        }
        return !flags.intersection(others).isEmpty
    }

    // MARK: - Mouse path

    private func installMouseMonitors() {
        let downHandler: (NSEvent) -> Void = { [weak self] event in
            guard let self = self, event.buttonNumber == 2 else { return }
            self.handleMiddleMouseDown(at: Date())
        }
        let upHandler: (NSEvent) -> Void = { [weak self] event in
            guard let self = self, event.buttonNumber == 2 else { return }
            self.handleMiddleMouseUp(at: Date())
        }
        localMouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown]) { event in
            downHandler(event); return event
        }
        globalMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.otherMouseDown]) { event in
            downHandler(event)
        }
        localMouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseUp]) { event in
            upHandler(event); return event
        }
        globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.otherMouseUp]) { event in
            upHandler(event)
        }
    }

    private func handleMiddleMouseDown(at now: Date) {
        switch state {
        case .idle:
            state = .firstDown(since: now)
        case .firstReleased(let at):
            if now.timeIntervalSince(at) <= gap {
                if suppressionGate?() == true { state = .idle; return }
                state = .secondDown
                onTriggered?()
            } else {
                state = .firstDown(since: now)
            }
        default:
            break
        }
    }

    private func handleMiddleMouseUp(at now: Date) {
        switch state {
        case .firstDown(let since):
            let held = now.timeIntervalSince(since)
            state = (held <= firstTapMax) ? .firstReleased(at: now) : .idle
        case .secondDown:
            onReleased?()
            state = .idle
        default:
            break
        }
    }
}
