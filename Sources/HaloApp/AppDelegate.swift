import AppKit
import SwiftUI
import Combine
import HaloCore
import HaloUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let prefs = AppPreferences.shared
    private let state = HaloState()
    private var window: HaloWindow!
    private var menuBar: MenuBarController!
    private var hotkey: HaloHotkey!
    private var onboarding = OnboardingOverlay()
    private var welcome = WelcomeWindowController()
    private var settingsWindowController: SettingsWindowController?

    private var lastFrontmostBundleID: String?

    private let usageStore = UsageStore()
    private let resolver = IdentityConflictResolver()
    private let extractor = DominantColorExtractor()
    private let switcher = Switcher.live()
    private let actionExecutor = ActionExecutor.live()
    private let arcExecutor = ArcExecutor.live()

    private var keyMonitor: Any?
    private var flagsMonitor: Any?
    private var rightMouseMonitor: Any?
    private var clickOutsideMonitor: Any?
    private var scrollMonitor: Any?
    private var scrollAccumDelta: Double = 0
    /// Tracks ⇧ press/release transitions in `installFlagsMonitor` so we
    /// only react on edges. NSEvent.modifierFlags reads the live HID
    /// state; flagsChanged fires on every modifier delta (including the
    /// ⌘ that arrives during the user's double-tap), so we filter for
    /// ⇧ explicitly.
    private var shiftHeld: Bool = false
    /// Tracks the right-mouse button (or two-finger trackpad tap, when
    /// macOS's secondary-click is configured for that gesture) state for
    /// the arc trigger.
    private var rightMouseHeld: Bool = false
    private var prefsObserver: AnyCancellable?
    private var nameCache: [String: String] = [:]
    private var identityColorCache: [String: IdentityColor] = [:]
    private var doubleTapMonitor: DoubleTapMonitor?

    /// Snapshots of prefs the hot-path needs without going through
    /// `AppPreferences` (which decodes JSON or hits UserDefaults). Rebuilt
    /// by `applyPreferences()` and read inside event-tap closures.
    private var whitelistSet: Set<String> = []
    private var lastRegisteredHotkeyKeyCode: UInt32?
    private var lastRegisteredHotkeyMods: HotkeyModifiers?

    func applicationDidFinishLaunching(_ notification: Notification) {
        HaloLog.lifecycle.info("Halo \(Halo.version) launching")
        installActivationObserver()

        state.slotCount = prefs.slotCount
        state.onCommit = { [weak self] in self?.commitSelection() }
        window = HaloWindow(state: state)
        menuBar = MenuBarController(
            onSummon: { [weak self] in self?.summonFromMenu() },
            onSettings: { [weak self] in self?.openSettings() },
            onQuit: { NSApp.terminate(nil) }
        )

        hotkey = HaloHotkey()
        registerHotkey()

        installKeyMonitor()
        installFlagsMonitor()
        installRightMouseMonitor()
        installClickOutsideMonitor()
        installScrollMonitor()

        // Re-react whenever the user touches prefs. `objectWillChange`
        // fires synchronously *before* the value changes, so we defer
        // through the MainActor queue to see the post-mutation state.
        prefsObserver = prefs.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.applyPreferences() }
        }
        applyPreferences()
        refreshSlots()

        let monitor = DoubleTapMonitor(
            trigger: prefs.doubleTapTrigger,
            gap: prefs.cmdDoubleTapGap
        )
        monitor.onTriggered = { [weak self] in self?.summon() }
        monitor.onReleased = { [weak self] in self?.commitSelection() }
        monitor.suppressionGate = { [weak self] in
            guard let self = self else { return false }
            guard let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                  frontmost != Bundle.main.bundleIdentifier
            else { return false }
            return self.whitelistSet.contains(frontmost)
        }
        monitor.start()
        doubleTapMonitor = monitor

        // First-launch welcome card. Deferred one runloop tick so the menu
        // bar item finishes mounting and the user sees it referenced from
        // the card's "Customize" tip without it being absent from the bar.
        DispatchQueue.main.async { [weak self] in
            self?.welcome.showIfNeeded()
        }
    }

    /// Public so Settings → General can replay the welcome card on demand.
    func replayWelcome() {
        welcome.showAgain()
    }

    /// Suspend global hotkey + double-tap processing while the welcome
    /// card is up. Otherwise pressing the configured chord summons Halo
    /// and steals focus from the welcome window. Called by `WelcomeView`'s
    /// `onAppear` / `onDisappear`.
    func pauseHotkeyForOnboarding() {
        hotkey.unregister()
        doubleTapMonitor?.stop()
    }

    func resumeHotkey() {
        registerHotkey()
        doubleTapMonitor?.start()
    }

    // MARK: - Preferences sync

    private func applyPreferences() {
        if state.slotCount != prefs.slotCount {
            state.slotCount = prefs.slotCount
        }
        // Re-register the Carbon hotkey ONLY when the chord changed.
        // Pre-fix this fired on every prefs mutation (slider drag → 10
        // re-registrations per second), each one a short race where the
        // chord wasn't claimed and could leak to other apps.
        let currentKeyCode = prefs.hotkeyKeyCode
        let currentMods = prefs.hotkeyModifiers
        if currentKeyCode != lastRegisteredHotkeyKeyCode
            || currentMods != lastRegisteredHotkeyMods {
            registerHotkey()
            lastRegisteredHotkeyKeyCode = currentKeyCode
            lastRegisteredHotkeyMods = currentMods
        }
        doubleTapMonitor?.gap = prefs.cmdDoubleTapGap
        doubleTapMonitor?.trigger = prefs.doubleTapTrigger
        // Cache the whitelist as a Set so the hotkey/double-tap gates
        // don't decode JSON on every keypress.
        whitelistSet = Set(prefs.whitelistedBundleIDs)
        refreshSlots()
    }

    private func registerHotkey() {
        let modifiers = prefs.hotkeyModifiers.carbonMask
        let keyCode = prefs.hotkeyKeyCode
        let ok = hotkey.register(keyCode: keyCode, carbonModifiers: modifiers) { [weak self] event in
            guard let self = self else { return }
            switch event {
            case .holdEngaged:   self.summon()
            case .holdReleased:  self.commitSelection()
            }
        }
        // Wire the whitelist gate on every (re)registration — Carbon
        // recreates the hotkey ref each time so the gate has to be
        // re-installed alongside the new listener. Reads the cached
        // `whitelistSet` instead of decoding prefs JSON on every press.
        hotkey.suppressionGate = { [weak self] in
            guard let self = self else { return false }
            guard let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                  frontmost != Bundle.main.bundleIdentifier
            else { return false }
            return self.whitelistSet.contains(frontmost)
        }
        let chord = "\(self.prefs.hotkeyModifiers.symbols)key:\(self.prefs.hotkeyKeyCode)"
        if ok {
            HaloLog.hotkey.info("Registered hotkey \(chord)")
        } else {
            HaloLog.hotkey.error("Failed to register hotkey \(chord)")
        }
    }

    // MARK: - Activation observer

    private func installActivationObserver() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bid = app.bundleIdentifier,
                  let name = app.localizedName
            else { return }
            // Only record real GUI apps the user can switch to.
            // `loginwindow`, `WindowManager`, `Dock`, etc. emit activation
            // notifications during lock/unlock and lockscreen transitions; if
            // we count them they trend high enough to land in the MFU top-N.
            guard app.activationPolicy == .regular else { return }
            // The notification fires on the queue we passed (.main), so
            // we're already on the main runloop. Sendable hop is the
            // Swift 6 idiom — extract primitives before crossing the
            // isolation boundary (Notification + NSRunningApplication
            // are not Sendable).
            Task { @MainActor in
                guard let self = self, bid != Bundle.main.bundleIdentifier else { return }
                let ref = AppRef(bundleID: bid, name: name)
                self.usageStore.recordActivation(of: ref)
                self.nameCache[bid] = name
                self.lastFrontmostBundleID = bid
                self.refreshSlots()
            }
        }
    }

    // MARK: - Slot refresh

    /// System processes that emit `didActivateApplicationNotification` during
    /// lock / unlock / Mission Control / Spotlight but aren't real apps the
    /// user can switch into. Filtered both at record time (above) and at
    /// rank time (below) so stale entries recorded before the activation-
    /// policy gate landed don't keep haunting the MFU.
    private static let systemBundleBlocklist: Set<String> = [
        "com.apple.loginwindow",
        "com.apple.WindowManager",
        "com.apple.dock",
        "com.apple.controlcenter",
        "com.apple.systemuiserver",
        "com.apple.notificationcenterui",
        "com.apple.SecurityAgent",
        "com.apple.coreservices.uiagent",
        "com.apple.Spotlight",
        "com.apple.PowerChime",
    ]

    private func refreshSlots() {
        let userMaxN = prefs.slotCount
        let records = usageStore.allRecords().filter {
            !Self.systemBundleBlocklist.contains($0.app.bundleID)
        }
        let pinSlots = prefs.pinnedBundleIDs           // [String?] length == userMaxN
        let pinnedBundleIDs = Set(pinSlots.compactMap { $0 })
        let hasPins = !pinnedBundleIDs.isEmpty

        // Frequency-sorted apps. Compute the full top-N once; reuse it
        // for (a) filling unpinned slots and (b) building the resolver's
        // frequencyRanking dict. Pre-fix this called `freqEngine.top`
        // twice — fine for ~10 apps but it doubled the work on every
        // workspace activation event and prefs `objectWillChange`.
        let freqEngine = HaloEngine(profile: prefs.frequencyProfile, pinned: [])
        let freqTopN = freqEngine.top(n: userMaxN, from: records)
        let freqApps = freqTopN.filter { !pinnedBundleIDs.contains($0.bundleID) }

        // Decide what app (if any) sits at each visible slot.
        let placed: [AppRef?]
        let displayN: Int

        if hasPins {
            // Honour the user's explicit pin → slot mapping. Wheel is the
            // full configured `userMaxN` so a slot 5 pin actually lands at
            // visual slot 5 (6 o'clock for N=10), not collapsed to the
            // first available position. Unpinned indices get filled by
            // the freq-sorted list in order; anything left over is empty.
            displayN = userMaxN
            var freqIter = freqApps.makeIterator()
            placed = (0..<userMaxN).map { i in
                if i < pinSlots.count, let id = pinSlots[i] {
                    return appRef(forBundleID: id)
                }
                return freqIter.next()
            }
        } else {
            // No pins → dynamic `apps + 1` so the user sees only a single
            // "+" placeholder until they fill the wheel.
            displayN = max(1, min(freqApps.count + 1, userMaxN))
            placed = (0..<displayN).map { i in
                i < freqApps.count ? freqApps[i] : nil
            }
        }

        let candidates: [IdentityColor?] = (0..<displayN).map { i in
            guard let app = placed[i] else { return nil }
            if let override = prefs.identityOverride(for: app.bundleID) {
                return override
            }
            if let cached = identityColorCache[app.bundleID] {
                return cached
            }
            if let icon = AppIconResolver.icon(for: app.bundleID),
               let extracted = extractor.extract(from: icon) {
                identityColorCache[app.bundleID] = extracted
                return extracted
            }
            return nil
        }
        // Rank slots by their app's real activation frequency, not slot
        // index — the resolver locks earlier entries first, so a pinned but
        // rarely-used app at slot 0 used to shadow a high-frequency app at
        // slot 3 when their hues collided. `freqEngine.top` is preconditioned
        // to N ∈ 4...12, and `userMaxN` is already clamped to that range;
        // pinned apps that don't make it into the top-N (and empty slots)
        // fall back to `Int.max`, tiebroken by slot index.
        let frequencyRanking = freqTopN
            .enumerated()
            .reduce(into: [String: Int]()) { acc, pair in
                acc[pair.element.bundleID] = pair.offset
            }
        let usageOrder = (0..<displayN).sorted { lhs, rhs in
            let lr = placed[lhs].flatMap { frequencyRanking[$0.bundleID] } ?? Int.max
            let rr = placed[rhs].flatMap { frequencyRanking[$0.bundleID] } ?? Int.max
            return lr == rr ? lhs < rhs : lr < rr
        }
        let palette = resolver.resolve(
            candidates: candidates,
            usageOrder: usageOrder,
            n: displayN
        )

        if state.slotCount != displayN {
            state.slotCount = displayN
        }

        let runningIDs = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        state.slots = (0..<displayN).map { i in
            if let app = placed[i] {
                let runState: HaloSlot.RunState = runningIDs.contains(app.bundleID) ? .running : .launchable
                return HaloSlot(id: i, app: app, identityColor: palette[i], runState: runState)
            }
            return HaloSlot.emptySlot(id: i, fallback: palette[i])
        }
    }

    private func appRef(forBundleID id: String) -> AppRef {
        let name = nameCache[id] ?? lookupAppName(bundleID: id) ?? id
        return AppRef(bundleID: id, name: name)
    }

    private func pinnedAppRefs(from bundleIDs: [String?]) -> [AppRef] {
        bundleIDs.compactMap { id -> AppRef? in
            guard let id = id else { return nil }
            let name = nameCache[id] ?? lookupAppName(bundleID: id) ?? id
            return AppRef(bundleID: id, name: name)
        }
    }

    private func lookupAppName(bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        let name = (url.lastPathComponent as NSString).deletingPathExtension
        nameCache[bundleID] = name
        return name
    }

    // MARK: - Hotkey handlers

    private func summon() {
        HaloLog.summon.info("summon position=\(self.prefs.summonPosition.rawValue)")
        // Slots are kept current by the activation observer and by prefs
        // changes; we don't need to re-extract dominant colors here — that
        // burns ~100ms/icon and makes Halo feel sluggish.
        // Always start a summon on layer 1. Seed the trigger-state
        // mirrors so the first ⇧/right-click after summon is treated as
        // a fresh tap, not a "still held from last time" no-op.
        state.hideArc()
        shiftHeld = NSEvent.modifierFlags.contains(.shift)
        rightMouseHeld = NSEvent.pressedMouseButtons & (1 << 1) != 0
        let position = prefs.summonPosition
        switch position {
        case .mouse:
            window.summon(at: nil)  // window picks up mouse pos
        case .center:
            let frame = NSScreen.main?.frame ?? .zero
            window.summon(at: CGPoint(x: frame.midX, y: frame.midY))
        }
        applyFrontmostHighlight()
        scrollAccumDelta = 0
        onboarding.showIfNeeded(over: window.panel)
        SoundEffectPlayer.shared.play(.summon)
    }

    /// When Settings → Navigation → Highlight frontmost on summon is on,
    /// store the frontmost app's pinned slot as the scroll anchor so a
    /// single scroll tick lands on it. Does NOT write to `state.phase` —
    /// the 1/60s gap between this synchronous seed and the first cursor
    /// poll would otherwise drive the 0.14s sector animation through an
    /// unrelated slot before settling under the cursor (visible as a
    /// brief "next slot lights up" flash). The "highlight" is therefore
    /// virtual: it influences scroll routing only, never rendering.
    private func applyFrontmostHighlight() {
        guard prefs.highlightFrontmostOnSummon else {
            state.scrollAnchor = nil
            return
        }
        // Search the rendered slots (pinned + freq-filled) rather than
        // only the pinned array — otherwise a frontmost app that's
        // showing up via the frequency model gets ignored and the
        // anchor falls back to slot 0.
        if let bundleID = lastFrontmostBundleID,
           let idx = state.slots.firstIndex(where: { $0.app?.bundleID == bundleID }),
           idx < state.slotCount {
            state.scrollAnchor = idx
        } else {
            state.scrollAnchor = nil
        }
    }

    private func summonFromMenu() {
        // Use the screen where the mouse currently lives so multi-display users
        // see Halo where they expect it.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let frame = screen?.visibleFrame ?? .zero
        window.summon(at: CGPoint(x: frame.midX, y: frame.midY))
    }

    private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(prefs: prefs)
        }
        settingsWindowController?.show()
    }

    private func commitSelection() {
        // Tear down the first-summon onboarding chip as soon as the user
        // commits — the lesson is over, no need to keep the hint floating.
        onboarding.dismiss()
        scrollAccumDelta = 0
        state.scrollAnchor = nil
        HaloLog.summon.debug("commit phase=\(String(describing: self.state.phase)) hover=\(String(describing: self.state.currentHoverSlot)) arc=\(self.state.activeArc != nil)")
        // Arc up: dispatch to ArcExecutor instead of Switcher.
        if let arc = state.activeArc {
            commitArcSelection(arc: arc)
            return
        }
        guard let i = state.currentHoverSlot,
              let slot = state.slots.first(where: { $0.id == i })
        else {
            cancel()
            return
        }
        // Committing onto an empty slot → open a Pin picker so the user can
        // adopt this slot for a specific app (no switch happens this turn).
        guard let app = slot.app else {
            window.dismiss(animated: true)
            openPinPickerForEmptySlot(i)
            return
        }

        SoundEffectPlayer.shared.play(.commit)
        state.phase = .committing(i)

        // If the app isn't running, mark the petal as launching, then
        // await the real `openApplication` outcome so a corrupt /
        // quarantined / moved bundle drops into shake-and-dismiss
        // instead of optimistic ripple-and-vanish. The Task suspends
        // while waiting; the main thread keeps drawing the fade-out.
        if slot.runState == .launchable {
            updateSlot(slotID: i) { $0.runState = .launching }
            let color = slot.identityColor
            let bundleID = app.bundleID
            let switcher = self.switcher
            Task { @MainActor [weak self] in
                // Hold Halo for ~0.9s so the spinner is visible even
                // when the launch resolves faster than that.
                async let dwell: () = Task.sleep(nanoseconds: 900_000_000)
                async let outcome = switcher.switchToAsync(bundleID: bundleID)
                let result = await outcome
                _ = try? await dwell
                guard let self = self else { return }
                if result == .failed {
                    self.updateSlot(slotID: i) { $0.runState = .failed }
                    self.shakeAndDismiss()
                } else {
                    self.window.fireRipple(color: color)
                    self.window.dismiss()
                }
            }
            return
        }

        // Running-app path: kick the fade-out BEFORE the switch so CoreAnimation
        // starts drawing immediately. The target app taking focus would yank
        // Halo off-screen otherwise, eating the fade.
        window.fireRipple(color: slot.identityColor)
        window.dismiss()
        let outcome = switcher.switchTo(bundleID: app.bundleID)
        if outcome == .failed {
            updateSlot(slotID: i) { $0.runState = .failed }
        }
    }

    private func updateSlot(slotID: Int, mutator: (inout HaloSlot) -> Void) {
        guard let idx = state.slots.firstIndex(where: { $0.id == slotID }) else { return }
        var s = state.slots[idx]
        mutator(&s)
        state.slots[idx] = s
    }

    /// Execute the chip currently under the cursor when the user releases
    /// the main hotkey while the arc is up. Empty custom chip routes to
    /// Settings → Actions; AX-gated fullscreen chip (without permission)
    /// triggers the system trust prompt instead of executing.
    private func commitArcSelection(arc: ActiveArc) {
        guard let chipIdx = state.arcHoverChip,
              arc.chips.indices.contains(chipIdx)
        else {
            cancel()
            return
        }
        let chip = arc.chips[chipIdx]

        // AX gate: if the chip needs AX and we don't have it, ask. The
        // user's trigger release is interpreted as "yes I want to use
        // this" so jumping into the system prompt is consensual.
        if case .builtin(let kind) = chip, kind.requiresAX, !AXPermissionGate.isTrusted {
            window.dismiss(animated: true, restorePreviousFront: true)
            AXPermissionGate.requestTrust(prompt: true)
            state.hideArc()
            return
        }

        // Empty custom chip → open Settings, pre-target this bundleID.
        if case .emptyCustom = chip {
            window.dismiss(animated: true)
            openActionEditor(forBundleID: arc.bundleID)
            state.hideArc()
            return
        }

        SoundEffectPlayer.shared.play(.commit)
        state.phase = .committing(arc.slotIndex)

        // Match layer-1's running-app commit order: fire fade first so the
        // ripple plays, then dispatch the action (synchronous / fire-and-forget).
        window.fireRipple(color: rippleColor(forChip: chip, arc: arc))
        window.dismiss()

        let outcome = arcExecutor.execute(chip: chip, forBundleID: arc.bundleID)
        if outcome == .failed {
            HaloLog.switcher.info("arc commit failed bundleID=\(arc.bundleID) chip=\(chipIdx)")
        }
        state.hideArc()
    }

    /// Chip's accent for the ripple. Built-ins have fixed colours so
    /// quit always ripples red, fullscreen yellow, hide blue. Custom
    /// falls back to the slot's identity color.
    private func rippleColor(forChip chip: ArcChip, arc: ActiveArc) -> IdentityColor {
        switch chip {
        case .builtin(.quit):
            return IdentityColor(lightness: 0.62, chroma: 0.22, hue: 24)   // red
        case .builtin(.fullscreenToggle):
            return IdentityColor(lightness: 0.78, chroma: 0.18, hue: 75)   // yellow
        case .builtin(.hide):
            return IdentityColor(lightness: 0.62, chroma: 0.20, hue: 240)  // blue
        case .custom, .emptyCustom:
            // Use the slot's color; lookup by slotIndex.
            return state.slots
                .first(where: { $0.id == arc.slotIndex })?.identityColor
                ?? IdentityColor(lightness: 0.6, chroma: 0.18, hue: 140)
        }
    }

    private func openActionEditor(forBundleID bundleID: String) {
        openSettings()
        settingsWindowController?.focusActionsTab(bundleID: bundleID)
    }

    private func cancel() {
        HaloLog.summon.debug("cancel")
        onboarding.dismiss()
        scrollAccumDelta = 0
        state.scrollAnchor = nil
        state.hideArc()
        window.dismiss(animated: true, restorePreviousFront: true)
    }

    private func openPinPickerForEmptySlot(_ slot: Int) {
        if pinPickerController == nil {
            pinPickerController = PinPickerWindowController()
        }
        pinPickerController?.show(forSlot: slot) { [weak self] picked in
            guard let self = self else { return }
            if let id = picked {
                self.prefs.setPinnedBundleID(id, at: slot)
                self.refreshSlots()
            }
        }
    }

    private var pinPickerController: PinPickerWindowController?

    private func shakeAndDismiss() {
        let win = window.panel
        let origin = win.frame.origin
        var step = 0
        func tick() {
            step += 1
            let offset: CGFloat = (step % 2 == 0) ? 3 : -3
            win.setFrameOrigin(NSPoint(x: origin.x + offset, y: origin.y))
            if step < 4 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: tick)
            } else {
                win.setFrameOrigin(origin)
                self.window.dismiss()
            }
        }
        tick()
    }

    // MARK: - Key and click monitors

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self = self, self.state.phase != .hidden else { return event }
            let keyCode = Int(event.keyCode)
            // ESC → cancel
            if keyCode == 53 { self.cancel(); return nil }
            // ←↑ cycle -1, →↓ cycle +1
            if keyCode == 123 || keyCode == 126 { self.cycleHighlight(by: -1); return nil }
            if keyCode == 124 || keyCode == 125 { self.cycleHighlight(by:  1); return nil }
            // Digit-key commit gated by Settings → Navigation. KeyCode
            // table covers `1–9 0 - =` so the layout is stable across
            // international keyboards (no `characters` lookup).
            //
            // While the Action Arc is up, digits 1–4 commit the arc chip
            // at that index instead of a slot. The 5–12 keys are silently
            // ignored in arc mode (no chip at that index).
            if self.prefs.numberKeyCommit {
                let target: Int?
                switch keyCode {
                case 18: target = 0   // 1
                case 19: target = 1   // 2
                case 20: target = 2   // 3
                case 21: target = 3   // 4
                case 23: target = 4   // 5
                case 22: target = 5   // 6
                case 26: target = 6   // 7
                case 28: target = 7   // 8
                case 25: target = 8   // 9
                case 29: target = 9   // 0
                case 27: target = 10  // -
                case 24: target = 11  // =
                default: target = nil
                }
                if let target = target {
                    if let arc = self.state.activeArc {
                        // Arc mode: route 0..3 to chip commit, swallow the rest.
                        guard arc.chips.indices.contains(target) else { return nil }
                        self.state.arcHoverChip = target
                        self.commitSelection()
                        return nil
                    } else if target < self.state.slotCount {
                        self.state.phase = .previewing(target)
                        self.commitSelection()
                        return nil
                    }
                }
            }
            // Return / Space → commit whatever is highlighted
            if keyCode == 36 || keyCode == 49 || keyCode == 76 {
                self.commitSelection()
                return nil
            }
            return event
        }
    }

    /// Arrow-key navigation. Routes through `advanceSelection` so the
    /// keyboard path honours `scrollAnchor` (frontmost slot) on the
    /// first press, matching the scroll-wheel path. Pre-fix the two
    /// paths used different anchor logic — left/right always seeded
    /// from slot 0/n-1 even when frontmost-highlight was on.
    private func cycleHighlight(by delta: Int) {
        state.advanceSelection(by: delta)
    }

    // MARK: - Action Arc (layer 2 — tap-toggle, not hold)

    /// ⇧ flagsChanged monitor. A ⇧ press (off→on edge) toggles the arc:
    /// show if it's hidden, hide if it's already up. Releasing ⇧ does
    /// nothing — the arc stays put until the user toggles it again, hits
    /// ESC, or commits via main-hotkey release.
    private func installFlagsMonitor() {
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            guard let self = self, self.state.phase != .hidden else { return event }
            let nowHeld = event.modifierFlags.contains(.shift)
            // Only react on the off→on edge; ignore the release edge and
            // ignore other modifier deltas (⌘ during double-tap, ⌥, ⌃).
            guard nowHeld, !self.shiftHeld else {
                self.shiftHeld = nowHeld
                return event
            }
            self.shiftHeld = nowHeld
            self.toggleArc()
            return event
        }
    }

    /// Right-mouse / two-finger-tap monitor. A press toggles the arc;
    /// release is ignored. Trackpad secondary click (System Settings →
    /// Trackpad → Secondary click = two-finger tap/click) is dispatched
    /// as `.rightMouseDown` by AppKit, so this single monitor catches
    /// both physical right-click and the trackpad gesture.
    private func installRightMouseMonitor() {
        rightMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.rightMouseDown]
        ) { [weak self] event in
            guard let self = self, self.state.phase != .hidden else { return event }
            self.toggleArc()
            // Swallow so the right-click can't drop a context menu onto
            // whatever's behind Halo.
            return nil
        }
    }

    /// One-shot: show the arc if it isn't up, hide it if it is. Used by
    /// every tap-trigger (⇧, right-click, two-finger tap) so the model
    /// is uniform.
    private func toggleArc() {
        if state.activeArc != nil {
            state.hideArc()
            HaloLog.summon.debug("toggle arc → hidden")
        } else {
            tryShowArc()
        }
    }

    /// Try to show the Action Arc for the hovered slot. Snapshots the
    /// target app's fullscreen state + AX trust status so the renderer
    /// can pick the right toggle icon and gated styling without
    /// re-querying during render.
    private func tryShowArc() {
        guard state.activeArc == nil else { return }
        guard let i = state.currentHoverSlot,
              let slot = state.slots.first(where: { $0.id == i }),
              let app = slot.app
        else { return }
        let customAction = prefs.actions(forBundleID: app.bundleID).first
        let chips: [ArcChip] = [
            .builtin(.quit),
            .builtin(.fullscreenToggle),
            .builtin(.hide),
            customAction.map { .custom($0) } ?? .emptyCustom,
        ]
        let runningApp = NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == app.bundleID
        }
        let isFs: Bool = {
            guard let runningApp = runningApp else { return false }
            return FullScreenToggler.isFullscreen(forPID: runningApp.processIdentifier)
        }()
        let arc = ActiveArc(
            slotIndex: i,
            bundleID: app.bundleID,
            appName: app.name,
            chips: chips,
            appIsFullscreen: isFs,
            axGranted: AXPermissionGate.isTrusted
        )
        state.showArc(arc)
        HaloLog.summon.debug("show arc app=\(app.bundleID) fs=\(isFs) ax=\(arc.axGranted)")
    }

    /// (Kept for API symmetry with cancel() — the tap-toggle model no
    /// longer drives this from trigger releases.)
    private func hideArcIfActive() {
        guard state.activeArc != nil else { return }
        state.hideArc()
    }

    /// Local monitor that translates scrollWheel events into slot-cycle
    /// steps while Halo is up. Halo `NSApp.activate()`s on summon, so a
    /// local monitor catches both touchpad and mouse-wheel input.
    /// Accumulates `scrollingDeltaY` and ticks one slot per ±32 pixel-
    /// equivalents to ride out touchpad inertia (spec §2.3 deadband).
    private func installScrollMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            guard let self = self,
                  self.prefs.scrollToSwitch,
                  self.state.phase != .hidden
            else { return event }

            let dy: Double
            if event.hasPreciseScrollingDeltas {
                dy = event.scrollingDeltaY
            } else {
                dy = event.scrollingDeltaY * 8  // lines → ~pixels
            }
            self.scrollAccumDelta += dy
            let step: Double = 32
            while self.scrollAccumDelta >= step {
                self.scrollAccumDelta -= step
                self.state.advanceSelection(by: -1)  // up → counter-clockwise
            }
            while self.scrollAccumDelta <= -step {
                self.scrollAccumDelta += step
                self.state.advanceSelection(by: 1)   // down → clockwise
            }
            return nil   // Halo is overlay-focused; no one else needs this
        }
    }

    private func installClickOutsideMonitor() {
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            // Hop to MainActor instead of `assumeIsolated`: global event
            // monitors are documented to fire on main, but
            // `assumeIsolated` is a runtime trap if that ever changes,
            // and Swift 6 strict concurrency wants explicit isolation.
            let mouse = NSEvent.mouseLocation
            Task { @MainActor in
                guard let self = self, self.state.phase != .hidden else { return }
                if !self.window.panel.frame.contains(mouse) {
                    self.cancel()
                }
            }
        }
    }
}
