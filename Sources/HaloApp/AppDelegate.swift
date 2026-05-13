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
    private var settingsWindowController: SettingsWindowController?

    private var lastFrontmostBundleID: String?

    private let usageStore = UsageStore()
    private let resolver = IdentityConflictResolver()
    private let extractor = DominantColorExtractor()
    private let switcher = Switcher.live()

    private var keyMonitor: Any?
    private var clickOutsideMonitor: Any?
    private var prefsObserver: AnyCancellable?
    private var nameCache: [String: String] = [:]
    private var identityColorCache: [String: IdentityColor] = [:]
    private var commandLongPress: CommandLongPressMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        installClickOutsideMonitor()

        // Re-react whenever the user touches prefs.
        prefsObserver = prefs.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.applyPreferences() }
            }
        }
        applyPreferences()
        refreshSlots()

        let monitor = CommandLongPressMonitor(gap: prefs.cmdDoubleTapGap)
        monitor.onTriggered = { [weak self] in self?.summon() }
        monitor.onReleased = { [weak self] in self?.commitSelection() }
        monitor.start()
        commandLongPress = monitor
    }

    // MARK: - Preferences sync

    private func applyPreferences() {
        if state.slotCount != prefs.slotCount {
            state.slotCount = prefs.slotCount
        }
        // Re-register hotkey if it changed.
        registerHotkey()
        commandLongPress?.gap = prefs.cmdDoubleTapGap
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
        if !ok {
            NSLog("Halo: failed to register hotkey \(prefs.hotkeyModifiers.symbols)+\(prefs.hotkeyKeyCode)")
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
            MainActor.assumeIsolated {
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
        let n = prefs.slotCount
        let records = usageStore.allRecords().filter {
            !Self.systemBundleBlocklist.contains($0.app.bundleID)
        }
        let pinned = pinnedAppRefs(from: prefs.pinnedBundleIDs)

        let engine = HaloEngine(profile: prefs.frequencyProfile, pinned: pinned)
        let topApps = engine.top(n: n, from: records)

        let candidates: [IdentityColor?] = topApps.indices.map { i in
            let app = topApps[i]
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
        let usageOrder = Array(0..<topApps.count)
        let padded = candidates + Array(repeating: nil as IdentityColor?, count: max(0, n - candidates.count))
        let palette = resolver.resolve(
            candidates: padded,
            usageOrder: usageOrder + Array(usageOrder.count..<n),
            n: n,
            useHue8: n == 8
        )

        let runningIDs = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        state.slots = (0..<n).map { i in
            if i < topApps.count {
                let app = topApps[i]
                let runState: HaloSlot.RunState = runningIDs.contains(app.bundleID) ? .running : .launchable
                return HaloSlot(id: i, app: app, identityColor: palette[i], runState: runState)
            }
            return HaloSlot.emptySlot(id: i, fallback: palette[i])
        }
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
        // Slots are kept current by the activation observer and by prefs
        // changes; we don't need to re-extract dominant colors here — that
        // burns ~100ms/icon and makes the HUD feel sluggish.
        let position = prefs.summonPosition
        switch position {
        case .mouse:
            window.summon(at: nil)  // window picks up mouse pos
        case .center:
            let frame = NSScreen.main?.frame ?? .zero
            window.summon(at: CGPoint(x: frame.midX, y: frame.midY))
        }
        onboarding.showIfNeeded(over: window.panel)
    }

    private func summonFromMenu() {
        // Use the screen where the mouse currently lives so multi-display users
        // see the HUD where they expect it.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let frame = screen?.visibleFrame ?? .zero
        window.summon(at: CGPoint(x: frame.midX, y: frame.midY))
    }

    private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(prefs: prefs, refreshHandler: { [weak self] in
                self?.refreshSlots()
            })
        }
        settingsWindowController?.show()
    }

    private func commitSelection() {
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

        state.phase = .committing(i)

        // If the app isn't running, mark the petal as launching, hold the HUD a
        // bit so the spinner is visible, then commit-ripple + dismiss. Failed
        // launches do not ripple and shake the HUD.
        if slot.runState == .launchable {
            updateSlot(slotID: i) { $0.runState = .launching }
            let outcome = switcher.switchTo(bundleID: app.bundleID)
            if outcome == .failed {
                updateSlot(slotID: i) { $0.runState = .failed }
                shakeAndDismiss()
                return
            }
            // Give the launch ~0.9s to surface before we fire the commit ripple.
            let color = slot.identityColor
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self = self else { return }
                    self.window.fireRipple(color: color)
                    self.window.dismiss()
                }
            }
            return
        }

        // Running-app path: kick the fade-out BEFORE the switch so CoreAnimation
        // starts drawing immediately. The target app taking focus would yank
        // the HUD off-screen otherwise, eating the fade.
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

    private func cancel() {
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
            // Digits 1-9 / 0 → direct pick
            if let chars = event.charactersIgnoringModifiers, let first = chars.first,
               let digit = first.wholeNumberValue {
                let target = (digit == 0) ? 9 : (digit - 1)
                if target < self.state.slotCount {
                    self.state.phase = .previewing(target)
                    self.commitSelection()
                    return nil
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

    private func cycleHighlight(by delta: Int) {
        let n = state.slotCount
        guard n > 0 else { return }
        let current = state.currentHoverSlot
        let next: Int
        if let c = current {
            next = (c + delta + n) % n
        } else {
            next = delta >= 0 ? 0 : n - 1
        }
        state.phase = .hovering(next)
    }

    private func installClickOutsideMonitor() {
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self, self.state.phase != .hidden else { return }
                let mouse = NSEvent.mouseLocation
                if !self.window.panel.frame.contains(mouse) {
                    self.cancel()
                }
            }
        }
    }
}
