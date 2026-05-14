import AppKit
import ApplicationServices
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

    /// Internal access so HaloUITests can drive the state machine
    /// synthetically without needing real NSEvent monitors.
    enum State: Equatable {
        case idle
        case firstDown(since: Date)
        case firstReleased(at: Date)
        case secondDown
    }
    var state: State = .idle

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

    /// True after `start()` if the OS reports that Halo lacks the
    /// Accessibility permission. Global event monitors silently
    /// receive nothing without AX — exposing this so the AppDelegate
    /// can route a one-shot user prompt instead of leaving the user
    /// wondering why their double-tap doesn't work.
    public private(set) var lacksAccessibilityPermission: Bool = false

    public func start() {
        // Global NSEvent monitors deliver `.flagsChanged` / `.otherMouseDown`
        // events only when Halo has the macOS Accessibility permission.
        // Probe non-interactively (no prompt) and remember the result;
        // local monitors still work without AX so the in-app paths
        // continue to function, just not the cross-app trigger.
        lacksAccessibilityPermission = !AXIsProcessTrusted()
        if lacksAccessibilityPermission {
            HaloLog.hotkey.error("AXIsProcessTrusted() == false — global double-tap monitor will be inert until the user grants Accessibility access in System Settings → Privacy & Security → Accessibility.")
        }
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
        // NSEvent monitors fire on the main runloop, but the closure
        // signature is non-isolated `Sendable`. NSEvent itself is not
        // Sendable, so we extract the primitive fields synchronously
        // (cheap, off-actor-safe) and hop back to MainActor before
        // touching state. Avoids `MainActor.assumeIsolated` at hot path.
        let localToken = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            let keyCode = event.keyCode
            let modifierFlags = event.modifierFlags
            let now = Date()
            Task { @MainActor in
                self?.handleFlagsChanged(keyCode: keyCode, modifierFlags: modifierFlags, at: now)
            }
            return event
        }
        let globalToken = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            let keyCode = event.keyCode
            let modifierFlags = event.modifierFlags
            let now = Date()
            Task { @MainActor in
                self?.handleFlagsChanged(keyCode: keyCode, modifierFlags: modifierFlags, at: now)
            }
        }
        localFlagsMonitor = localToken
        globalFlagsMonitor = globalToken
    }

    /// Internal so HaloUITests can synthesize input events.
    func handleFlagsChanged(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags, at now: Date) {
        let isMatchedKey = keyCodeMatches(keyCode)

        let pressed = matchedFlagPresent(in: modifierFlags)
        let onlyMatchedDown = pressed && !otherModifierPresent(matched: trigger, flags: modifierFlags)

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
        // Same threading discipline as `installFlagsMonitors`: extract
        // sendable primitives in the monitor closure, hop to MainActor
        // before mutating state.
        localMouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown]) { [weak self] event in
            guard event.buttonNumber == 2 else { return event }
            let now = Date()
            Task { @MainActor in self?.handleMiddleMouseDown(at: now) }
            return event
        }
        globalMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.otherMouseDown]) { [weak self] event in
            guard event.buttonNumber == 2 else { return }
            let now = Date()
            Task { @MainActor in self?.handleMiddleMouseDown(at: now) }
        }
        localMouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseUp]) { [weak self] event in
            guard event.buttonNumber == 2 else { return event }
            let now = Date()
            Task { @MainActor in self?.handleMiddleMouseUp(at: now) }
            return event
        }
        globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.otherMouseUp]) { [weak self] event in
            guard event.buttonNumber == 2 else { return }
            let now = Date()
            Task { @MainActor in self?.handleMiddleMouseUp(at: now) }
        }
    }

    func handleMiddleMouseDown(at now: Date) {
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

    func handleMiddleMouseUp(at now: Date) {
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
