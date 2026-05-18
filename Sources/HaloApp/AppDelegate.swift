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
    /// Full-screen panel that replaces the wheel while the built-in
    /// "ALL" virtual profile is active. Lives alongside `window`; only
    /// one of the two is visible at a time. Wired up in
    /// `applicationDidFinishLaunching`, summoned/dismissed via
    /// `enterGridMode` / `leaveGridMode`.
    private var gridWindow: HaloGridWindow!
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
        PerfSignpost.measure("applicationDidFinishLaunching") {
            applicationDidFinishLaunchingBody()
        }
    }

    private func applicationDidFinishLaunchingBody() {
        HaloLog.lifecycle.info("Halo \(Halo.version) launching")
        installActivationObserver()

        state.slotCount = prefs.slotCount
        state.onCommit = { [weak self] in self?.commitSelection() }
        // Tap handler for the wheel's top-strip profile pills. Routes
        // through the same path Tab / ⇧Tab uses so transient state
        // (scroll anchor, arc) gets reset.
        state.onSwitchProfile = { [weak self] id in
            guard let self = self else { return }
            // Built-in ALL profile: enter grid mode (no real prefs
            // mutation — `switchToProfile` would refuse the id since
            // it's not in `_profiles`). Cycle path goes through
            // `cycleProfileWhileSummoned` which handles the same case.
            if id == GridProfile.id {
                guard !self.state.isGridMode else { return }
                self.state.scrollAnchor = nil
                self.state.hideArc()
                self.state.phase = .idle
                self.enterGridMode()
                SoundEffectPlayer.shared.play(.slide)
                return
            }
            // Currently in grid mode and the user clicked a real
            // profile pill — leave grid mode and switch.
            if self.state.isGridMode {
                self.state.scrollAnchor = nil
                self.state.hideArc()
                self.leaveGridMode()
                self.prefs.switchToProfile(id)
                SoundEffectPlayer.shared.play(.slide)
                return
            }
            guard id != self.prefs.activeProfileID else { return }
            self.state.scrollAnchor = nil
            self.state.hideArc()
            self.state.phase = .idle
            self.prefs.switchToProfile(id)
            SoundEffectPlayer.shared.play(.slide)
        }
        window = HaloWindow(state: state)
        gridWindow = HaloGridWindow(state: state)
        menuBar = MenuBarController(
            onSummon: { [weak self] in self?.summonFromMenu() },
            onSettings: { [weak self] in self?.openSettings() },
            onProfileSelect: { [weak self] id in
                self?.prefs.switchToProfile(id)
            },
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
        monitor.onReleased = { [weak self] in self?.commitFromHold() }
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
        PerfSignpost.measure("applyPreferences") { applyPreferencesBody() }
    }

    private func applyPreferencesBody() {
        if state.slotCount != prefs.slotCount {
            state.slotCount = prefs.slotCount
        }
        // Push the active profile's ambient tint through to the wheel so
        // a profile switch or tint-picker edit lights the idle halo
        // immediately.
        let nextTint = prefs.activeProfile.tint
        if state.profileTint != nextTint {
            state.profileTint = nextTint
        }
        // Sync the top-strip pill model. Always rewrite when shape /
        // names / tints change; we compare via Equatable so a no-op
        // mutation doesn't churn the SwiftUI animation.
        var pills = prefs.profiles.map {
            ProfilePill(id: $0.id, name: $0.name, tint: $0.tint)
        }
        // Built-in "ALL" profile (watchOS-style honeycomb grid). When
        // the user has the toggle on, we prepend a virtual pill at
        // position 0 that the cycle / tap path special-cases — the id
        // is never written into `prefs.profiles`, so Settings, the
        // menu-bar Profile submenu, and serialization remain
        // unaffected.
        if prefs.showAllProfile {
            pills.insert(
                ProfilePill(id: GridProfile.id, name: GridProfile.displayName, tint: nil),
                at: 0
            )
        }
        if state.profilePills != pills {
            state.profilePills = pills
        }
        // While grid mode is on, leave `state.activeProfileID` pinned
        // to `GridProfile.id` so the pill highlight follows. Otherwise
        // any prefs mutation (Settings tint edit, slotCount slide)
        // would knock the highlight back to the real active profile.
        if state.isGridMode {
            // No-op for activeProfileID; we still want every other
            // mirroring above (slotCount, tint) to flow through so
            // the wheel is correctly configured for when the user
            // leaves grid mode.
        } else if state.activeProfileID != prefs.activeProfileID {
            state.activeProfileID = prefs.activeProfileID
        }
        // If the user just turned `showAllProfile` off while ALL was
        // on screen, fall back to the real active profile so the
        // panel doesn't get stuck rendering a hidden pill's view.
        if state.isGridMode && !prefs.showAllProfile {
            leaveGridMode()
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
        applyAppearance()
        // Keep the menu-bar Profile submenu in sync with prefs. The
        // submenu is hidden when there's only one profile so users
        // don't see a degenerate single-item switcher.
        menuBar.setProfiles(prefs.profiles.map {
            (id: $0.id, name: $0.name, isActive: $0.id == prefs.activeProfileID)
        })
        refreshSlots()
    }

    /// Push `prefs.appearanceMode` onto `NSApp.appearance` so Settings, the
    /// Pin picker, alerts, and any other non-HUD window flip live. The Halo
    /// wheel and Welcome overlay set their own `NSPanel.appearance` and
    /// stay dark by design.
    private func applyAppearance() {
        let appearance: NSAppearance?
        switch prefs.appearanceMode {
        case .system: appearance = nil
        case .light:  appearance = NSAppearance(named: .aqua)
        case .dark:   appearance = NSAppearance(named: .darkAqua)
        }
        NSApp.appearance = appearance
    }

    private func registerHotkey() {
        let modifiers = prefs.hotkeyModifiers.carbonMask
        let keyCode = prefs.hotkeyKeyCode
        let ok = hotkey.register(keyCode: keyCode, carbonModifiers: modifiers) { [weak self] event in
            guard let self = self else { return }
            switch event {
            case .holdEngaged:   self.summon()
            case .holdReleased:  self.commitFromHold()
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
        PerfSignpost.measure("refreshSlots") { refreshSlotsBody() }
    }

    private func refreshSlotsBody() {
        // Wheel slots aren't visible while the ALL grid is on — skip
        // the work so the activation observer doesn't churn through
        // identity-color extraction during a grid session.
        guard !state.isGridMode else { return }
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
        // Always start a summon on layer 1 (the wheel), even if the
        // last session ended on the ALL grid. The user can Tab back
        // into ALL after summon if they want it.
        if state.isGridMode { leaveGridMode() }
        state.hideArc()
        shiftHeld = NSEvent.modifierFlags.contains(.shift)
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

    /// Hotkey hold-release path. The wheel uses release-to-commit
    /// (slot under cursor launches when the user lets go), but the
    /// grid intentionally does NOT — Launchpad-style browsing should
    /// only launch on an explicit click or Return. Pressing-and-
    /// releasing the hotkey while in grid mode just dismisses Halo,
    /// leaving the previously-frontmost app active.
    private func commitFromHold() {
        if state.isGridMode {
            cancel()
            return
        }
        commitSelection()
    }

    private func commitSelection() {
        // Tear down the first-summon onboarding chip as soon as the user
        // commits — the lesson is over, no need to keep the hint floating.
        onboarding.dismiss()
        scrollAccumDelta = 0
        state.scrollAnchor = nil

        // Grid mode (built-in ALL profile): launch the icon under the
        // cursor / keyboard selection, then dismiss the grid panel.
        // No slot, no arc — these don't apply to the honeycomb view.
        //
        // Visually we play a press burst on the selected icon (driven
        // by `committingBundleID`) before the panel fades — the user
        // sees the cell snap up then collapse, mirroring the watchOS
        // app-launch micro-animation, while we wait ~180ms for the
        // hop into the target app.
        if state.isGridMode {
            HaloLog.summon.debug("commit grid bundleID=\(self.state.gridState.selectedBundleID ?? "nil")")
            guard let bundleID = state.gridState.selectedBundleID else {
                cancel()
                return
            }
            SoundEffectPlayer.shared.play(.commit)
            state.gridState.committingBundleID = bundleID
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 180_000_000)
                guard let self = self else { return }
                // If the user cancelled (ESC) during the burst animation
                // committingBundleID will have been cleared by resetViewport();
                // bail so the app doesn't launch after an explicit cancel.
                guard self.state.gridState.committingBundleID == bundleID else { return }
                // Reset transient grid state and start the cross-fade.
                self.gridWindow.dismiss(animated: true)
                self.state.isGridMode = false
                self.state.activeProfileID = self.prefs.activeProfileID
                self.state.phase = .hidden
                self.state.gridState.resetViewport()
                let outcome = self.switcher.switchTo(bundleID: bundleID)
                if outcome == .failed {
                    HaloLog.switcher.info("grid commit failed bundleID=\(bundleID)")
                }
            }
            return
        }

        HaloLog.summon.debug("commit phase=\(String(describing: self.state.phase)) hover=\(String(describing: self.state.currentHoverSlot)) arc=\(self.state.activeArc != nil) chip=\(String(describing: self.state.arcHoverChip))")

        // Arc up. Priority:
        //   1. cursor on a chip → run the chip (arc commit)
        //   2. cursor on a slot → user changed their mind; dismiss the arc
        //      and fall through to the regular layer-1 slot commit
        //   3. nothing → cancel (handled by the existing layer-1 fallthrough)
        if let arc = state.activeArc {
            if let chipIdx = state.arcHoverChip, arc.chips.indices.contains(chipIdx) {
                commitArcChip(chipIdx, arc: arc)
                return
            }
            // Drop the arc and let the layer-1 path below handle the slot.
            state.hideArc()
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

    /// Execute the chip at `chipIdx`. Callers must have verified the index
    /// is in-bounds. Empty custom chip routes to Settings → Actions;
    /// AX-gated fullscreen chip (without permission) triggers the system
    /// trust prompt instead of executing.
    private func commitArcChip(_ chipIdx: Int, arc: ActiveArc) {
        let chip = arc.chips[chipIdx]

        // AX gate: if the chip needs AX and we don't have it, ask. Fire
        // the trust prompt FIRST, then dismiss Halo — otherwise we
        // re-activate the previous frontmost app, and the system's
        // Accessibility prompt sometimes mis-attributes to that app
        // rather than to Halo.
        if case .builtin(let kind) = chip, kind.requiresAX, !AXPermissionGate.isTrusted {
            AXPermissionGate.requestTrust(prompt: true)
            state.hideArc()
            window.dismiss(animated: true, restorePreviousFront: true)
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
        // Grid path: dismiss the full-screen panel, reset transient
        // grid state, and don't re-summon the wheel (cancel = full
        // dismiss, the wheel is already orderOut-ed under the grid).
        if state.isGridMode {
            state.isGridMode = false
            state.activeProfileID = prefs.activeProfileID
            state.phase = .hidden
            state.gridState.resetViewport()
            gridWindow.dismiss(animated: true)
            return
        }
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
            // ESC → cancel (works for both wheel and grid mode)
            if keyCode == 53 { self.cancel(); return nil }
            // Tab / ⇧Tab → next / previous Profile. Routes through
            // `cycleProfileWhileSummoned`, which knows how to flip
            // between the wheel and the grid (ALL profile).
            if keyCode == 48 { // Tab
                let delta = event.modifierFlags.contains(.shift) ? -1 : 1
                self.cycleProfileWhileSummoned(by: delta)
                return nil
            }
            // Grid mode: route keystrokes to search + arrow nav.
            // Return / Space commit the icon under the cursor /
            // keyboard focus. ESC and Tab were handled above.
            if self.state.isGridMode {
                if keyCode == 36 || keyCode == 49 || keyCode == 76 {
                    self.commitSelection()
                    return nil
                }
                // Backspace → trim the search query.
                if keyCode == 51 {
                    self.state.gridState.backspaceSearch()
                    return nil
                }
                // Arrow keys → step the keyboard selection. Delta
                // ±1 for ←→, ±columns for ↑↓ so the user can walk
                // the cluster row-by-row in addition to mousing.
                if [123, 124, 125, 126].contains(keyCode) {
                    let cols = self.gridColumnsEstimate()
                    let delta: Int
                    switch keyCode {
                    case 123: delta = -1                   // ←
                    case 124: delta =  1                   // →
                    case 126: delta = -cols                // ↑
                    case 125: delta =  cols                // ↓
                    default: delta = 0
                    }
                    let next = self.state.gridState.neighbourBundleID(
                        of: self.state.gridState.selectedBundleID,
                        delta: delta,
                        columns: cols
                    )
                    self.state.gridState.selectedBundleID = next
                    return nil
                }
                // Cmd-anything stays a shortcut; don't capture as
                // search input. Live-key character routing for the
                // remaining keystrokes goes through `characters`
                // (NOT charactersIgnoringModifiers) so ⇧ produces
                // capital letters. Filter to printable ASCII so we
                // don't pollute the query with control glyphs.
                if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                    return nil
                }
                if let chars = event.characters, !chars.isEmpty {
                    for ch in chars where ch.isLetter || ch.isNumber
                        || ch == " " || ch == "-" || ch == "."
                        || ch == "_" {
                        self.state.gridState.appendSearch(ch)
                    }
                }
                return nil
            }
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

    /// Cycle the active profile while Halo is summoned. Resets per-summon
    /// transient state (highlight phase, scroll anchor, arc) so the new
    /// profile's first slot lights up cleanly when the wheel re-renders
    /// at the new slot count.
    ///
    /// When `prefs.showAllProfile` is on, an extra virtual "ALL"
    /// position is prepended so Tab traverses `[ALL, Default, …]`. ALL
    /// can't go through `prefs.switchToProfile` (its id isn't in
    /// `_profiles`) so the AppDelegate handles entry / exit directly.
    private func cycleProfileWhileSummoned(by delta: Int) {
        var ids: [UUID] = prefs.profiles.map(\.id)
        if prefs.showAllProfile {
            ids.insert(GridProfile.id, at: 0)
        }
        guard ids.count > 1 else { return }

        let currentID = state.isGridMode ? GridProfile.id : prefs.activeProfileID
        guard let idx = ids.firstIndex(of: currentID) else { return }
        let n = ids.count
        let next = ((idx + delta) % n + n) % n
        let nextID = ids[next]

        // Drop transient state before the profile flip so the old slot
        // index doesn't leak through to the new (possibly shorter) wheel.
        state.scrollAnchor = nil
        state.hideArc()
        state.phase = .idle
        SoundEffectPlayer.shared.play(.slide)

        if nextID == GridProfile.id {
            enterGridMode()
        } else if state.isGridMode {
            leaveGridMode()
            prefs.switchToProfile(nextID)
        } else {
            prefs.cycleActiveProfile(by: delta)
        }
    }

    // MARK: - Grid mode (built-in ALL profile)

    /// Mirror of the column formula in `HoneycombGridView`: 7-9 columns most
    /// of the time, clamped to 5..13. Lives here so the keyMonitor can step
    /// the keyboard selection by full rows without re-rendering.
    private func gridColumnsEstimate() -> Int {
        let count = max(state.gridState.filteredApps.count, 1)
        let raw = Int(ceil(Double(count).squareRoot() * 1.35))
        return min(13, max(5, raw))
    }

    /// Hide the wheel and surface the full-screen honeycomb grid.
    /// Idempotent: a no-op when grid mode is already on.
    ///
    /// Cross-fade rather than swap: the wheel panel fades out
    /// concurrently with the grid panel fading in so the user sees a
    /// single continuous transition, not a flash-cut. Both fades use
    /// matched easeOut/easeIn timings (0.16s) so they meet at ~50 %
    /// alpha at the midpoint.
    private func enterGridMode() {
        PerfSignpost.measure("enterGridMode") { enterGridModeBody() }
    }

    private func enterGridModeBody() {
        guard !state.isGridMode else { return }
        // Trigger an app scan on first entry. Subsequent entries reuse
        // the cached list so cycle Tab → ALL → Tab → ALL doesn't churn
        // the disk.
        let records = usageStore.allRecords().filter {
            !Self.systemBundleBlocklist.contains($0.app.bundleID)
        }
        let runningIDs = Set(NSWorkspace.shared.runningApplications.compactMap { app -> String? in
            guard app.activationPolicy == .regular,
                  let bundleID = app.bundleIdentifier,
                  !Self.systemBundleBlocklist.contains(bundleID)
            else { return nil }
            return bundleID
        })
        state.gridState.loadApps(usageRecords: records, runningBundleIDs: runningIDs)
        state.isGridMode = true
        state.activeProfileID = GridProfile.id
        // Bring up the grid panel first so its alpha animation can run
        // alongside the wheel's fade-out.
        gridWindow.summon()
        // Fade the wheel panel out in parallel. After the fade we
        // orderOut so it doesn't intercept clicks under the grid.
        let wheelPanel = window.panel
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            wheelPanel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in
                wheelPanel.orderOut(nil)
                // Restore alpha so a future re-entry (leaveGridMode →
                // wheel) doesn't have to reset it before fading in.
                wheelPanel.alphaValue = 1
            }
        })
    }

    /// Restore the wheel panel and dismiss the grid.
    /// Idempotent: a no-op when grid mode is already off.
    ///
    /// We deliberately do NOT call `HaloWindow.summon()` here — that
    /// would recapture `previousFrontApp` (now Halo itself, since the
    /// grid is frontmost), warp the cursor, and replay the explode
    /// curve. We just want the wheel back where it was, with its
    /// pre-grid context intact, so the user can ESC and land back on
    /// the app they originally summoned from.
    private func leaveGridMode() {
        guard state.isGridMode else { return }
        state.isGridMode = false
        state.activeProfileID = prefs.activeProfileID
        // Cross-fade: bring the wheel panel back at alpha 0, animate
        // up while the grid animates down. orderOut preserved the
        // wheel's frame, so it returns to exactly where it was.
        let wheelPanel = window.panel
        wheelPanel.alphaValue = 0
        wheelPanel.orderFrontRegardless()
        wheelPanel.makeKey()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            wheelPanel.animator().alphaValue = 1
        }
        gridWindow.dismiss(animated: true)
        state.gridState.resetViewport()
    }

    // MARK: - Action Arc (layer 2 — tap-toggle, not hold)

    /// ⇧ flagsChanged monitor. A ⇧ press (off→on edge) toggles the arc:
    /// show if it's hidden, hide if it's already up. Releasing ⇧ does
    /// nothing — the arc stays put until the user toggles it again, hits
    /// ESC, or commits via main-hotkey release.
    private func installFlagsMonitor() {
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            guard let self = self, self.state.phase != .hidden else { return event }
            // Action Arc is a wheel-only affordance — silence the ⇧
            // toggle while grid mode is up.
            if self.state.isGridMode { return event }
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
            // Right-click is for the Action Arc — wheel only. Let the
            // event flow normally in grid mode (the grid view doesn't
            // currently use right-click but might gain a context menu
            // later, and we don't want a global swallow here).
            if self.state.isGridMode { return event }
            self.toggleArc()
            // Swallow so the right-click can't drop a context menu onto
            // whatever's behind Halo.
            return nil
        }
    }

    /// One-shot tap-trigger handler. Three branches:
    ///   - Arc not up → show for the hovered/origin slot.
    ///   - Arc up, cursor on a DIFFERENT app slot → re-anchor in one tap
    ///     (user pointed at another app, they want its arc).
    ///   - Arc up, cursor on same slot / empty slot / deadzone → toggle off.
    private func toggleArc() {
        guard let currentArc = state.activeArc else {
            tryShowArc()
            return
        }
        if let newSlotIdx = state.currentHoverSlot,
           newSlotIdx != currentArc.slotIndex,
           let slot = state.slots.first(where: { $0.id == newSlotIdx }),
           slot.app != nil,
           let newArc = buildArc(forSlot: newSlotIdx, slot: slot) {
            state.showArc(newArc)
            HaloLog.summon.debug("toggle arc → re-anchor slot=\(newSlotIdx) app=\(newArc.bundleID)")
            return
        }
        state.hideArc()
        HaloLog.summon.debug("toggle arc → hidden")
    }

    /// Try to show the Action Arc. Picks the anchor slot in this order:
    ///   1. The slot the cursor is currently hovering (if it has an app)
    ///   2. The slot whose app matches the pre-summon frontmost app
    ///      (so triggering ⇧/right-click from the deadzone surfaces the
    ///      current app's actions)
    /// Snapshots the target's fullscreen + AX state so render doesn't
    /// re-query during a redraw.
    private func tryShowArc() {
        guard state.activeArc == nil else { return }
        guard let target = arcAnchorSlot() else { return }
        guard let arc = buildArc(forSlot: target.0, slot: target.1) else { return }
        state.showArc(arc)
        HaloLog.summon.debug("show arc app=\(arc.bundleID) fs=\(arc.appIsFullscreen) ax=\(arc.axGranted) slot=\(arc.slotIndex)")
    }

    /// Builds an `ActiveArc` snapshot — chip list, fullscreen state, AX
    /// trust — for a given slot. Used only by `tryShowArc`; the arc is a
    /// one-shot snapshot frozen at trigger time. Sweeping the cursor onto
    /// a different slot afterwards does NOT re-anchor; the user has to
    /// tap-toggle off and re-trigger on the new slot.
    private func buildArc(forSlot slotIdx: Int, slot: HaloSlot) -> ActiveArc? {
        guard let app = slot.app else { return nil }
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
        return ActiveArc(
            slotIndex: slotIdx,
            bundleID: app.bundleID,
            appName: app.name,
            chips: chips,
            appIsFullscreen: isFs,
            axGranted: AXPermissionGate.isTrusted
        )
    }

    /// Resolves which slot the arc should anchor to. The hover takes
    /// priority; when the cursor is in the deadzone we look up the
    /// summon-origin app so a "summon + ⇧" sequence surfaces the actions
    /// for the app the user came from without having to move the mouse.
    private func arcAnchorSlot() -> (Int, HaloSlot)? {
        // 1. Cursor on an app slot → that's the anchor.
        if let i = state.currentHoverSlot,
           let slot = state.slots.first(where: { $0.id == i }),
           slot.app != nil {
            return (i, slot)
        }
        // 2. Cursor in deadzone → use the pre-summon frontmost app.
        guard let originID = state.summonOriginBundleID else { return nil }
        if let slot = state.slots.first(where: { $0.app?.bundleID == originID }) {
            return (slot.id, slot)
        }
        return nil
    }

    /// Local monitor that translates scrollWheel events into slot-cycle
    /// steps while Halo is up. Halo `NSApp.activate()`s on summon, so a
    /// local monitor catches both touchpad and mouse-wheel input.
    /// Accumulates `scrollingDeltaY` and ticks one slot per ±32 pixel-
    /// equivalents to ride out touchpad inertia (spec §2.3 deadband).
    private func installScrollMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            guard let self = self,
                  self.state.phase != .hidden
            else { return event }

            // Grid mode: route the scroll through to the grid's pan
            // offset. Two-finger trackpad scroll and mouse-wheel both
            // feed `scrollingDelta{X,Y}`. Disregard `scrollToSwitch`
            // here — that toggle gates slot cycling; grid pan is a
            // separate affordance.
            if self.state.isGridMode {
                let dx = event.scrollingDeltaX
                let dy = event.scrollingDeltaY
                if dx != 0 || dy != 0 {
                    guard self.state.gridState.draggingBundleID == nil else { return nil }
                    let gs = self.state.gridState
                    let proposed = CGSize(
                        width:  gs.panOffset.width  + dx,
                        height: gs.panOffset.height + dy
                    )
                    // Clamp inline — same limits the pan gesture uses.
                    // viewSize comes from the live panel frame so this
                    // stays correct across screen / zoom changes.
                    let viewSize = self.gridWindow.panel.contentView?.bounds.size ?? .zero
                    let zoomLevel = gs.zoomLevel
                    let panelScale = HaloUI.Geometry.panelScale
                    let spacing   = HoneycombGridView.baseSpacing * zoomLevel * panelScale
                    let iconSize  = HoneycombGridView.baseIconSize * zoomLevel * panelScale
                    let vStretch: CGFloat = 1.18
                    let count = max(gs.filteredApps.count, 1)
                    let layout = HoneycombGeometry.spiralLayout(count: count)
                    let bounds = HoneycombGeometry.layoutBounds(
                        layout: layout, spacing: spacing, verticalStretch: vStretch)
                    let maxX = max(0, viewSize.width  / 2 + bounds.width  / 2 - iconSize / 2)
                    let maxY = max(0, viewSize.height / 2 + bounds.height / 2 - iconSize / 2)
                    gs.panOffset = CGSize(
                        width:  max(-maxX, min(maxX,  proposed.width)),
                        height: max(-maxY, min(maxY, proposed.height))
                    )
                }
                return nil
            }

            guard self.prefs.scrollToSwitch else { return event }
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
                // In grid mode the panel covers the whole screen, so
                // a global click is always inside one of our windows;
                // local taps are handled by the grid view's own gesture.
                // Skip the cancel-on-outside-click path entirely.
                if self.state.isGridMode { return }
                if !self.window.panel.frame.contains(mouse) {
                    self.cancel()
                }
            }
        }
    }
}
