import Foundation
import CoreGraphics

#if canImport(AppKit)
import AppKit
#endif

public enum SummonPosition: String, Codable, Sendable, CaseIterable {
    case mouse
    case center
}

/// Bitmask of supported hotkey modifiers, mirroring NSEvent.ModifierFlags / Carbon.
public struct HotkeyModifiers: OptionSet, Codable, Sendable, Hashable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let command: HotkeyModifiers = .init(rawValue: 1 << 0)
    public static let option:  HotkeyModifiers = .init(rawValue: 1 << 1)
    public static let control: HotkeyModifiers = .init(rawValue: 1 << 2)
    public static let shift:   HotkeyModifiers = .init(rawValue: 1 << 3)

    /// Translate this set into Carbon's modifier mask.
    public var carbonMask: UInt32 {
        var m: UInt32 = 0
        if contains(.command) { m |= 1 << 8 }   // cmdKey
        if contains(.option)  { m |= 1 << 11 }  // optionKey
        if contains(.control) { m |= 1 << 12 }  // controlKey
        if contains(.shift)   { m |= 1 << 9 }   // shiftKey
        return m
    }

    /// Display label, ⌘⌥⌃⇧-style.
    public var symbols: String {
        var s = ""
        if contains(.control) { s += "⌃" }
        if contains(.option)  { s += "⌥" }
        if contains(.shift)   { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }
}

/// All user-tunable knobs, persisted in UserDefaults. ObservableObject so
/// SwiftUI views in HaloUI / HaloApp can bind directly.
///
/// All mutation goes through this single object so the AppDelegate can
/// react via `objectWillChange` and trigger a slot refresh.
@MainActor
public final class AppPreferences: ObservableObject {
    public static let shared = AppPreferences()

    private enum Keys {
        static let slotCount       = "halo.prefs.slotCount"
        static let profile         = "halo.prefs.frequencyProfile"
        static let summonPosition  = "halo.prefs.summonPosition"
        static let pinnedSlots     = "halo.prefs.pinnedSlots.v1"
        static let overflowPins    = "halo.prefs.overflowPins.v1"
        static let identityOver    = "halo.prefs.identityOverride.v1"
        static let hotkeyKeyCode   = "halo.prefs.hotkey.keyCode"
        static let hotkeyMods      = "halo.prefs.hotkey.mods"
        static let cmdHoldDuration = "halo.prefs.cmdHoldDuration"
        static let cmdDoubleTapGap = "halo.prefs.cmdDoubleTapGap"
        static let autostart       = "halo.prefs.autostart"
        static let languageOverride = "halo.prefs.languageOverride"
        // Storage key keeps its legacy `hudDiameter` suffix so v1.0 user
        // prefs continue to load after the rename.
        static let haloDiameter    = "halo.prefs.layout.hudDiameter"
        static let iconSize        = "halo.prefs.layout.iconSize"
        static let iconRadius      = "halo.prefs.layout.iconRadius"
        static let panelScale      = "halo.prefs.layout.panelScale"
        static let scrollToSwitch  = "halo.prefs.scrollToSwitch"
        static let numberKeyCommit = "halo.prefs.numberKeyCommit"
        static let highlightFront  = "halo.prefs.highlightFrontmostOnSummon"
        static let doubleTapTrigger = "halo.prefs.doubleTapTrigger"
        static let whitelist       = "halo.prefs.whitelist.v1"
        static let soundEffects    = "halo.prefs.soundEffectsEnabled"
        static let actionBindings  = "halo.prefs.actionBindings.v1"
        static let onboardingShown = "halo.onboarding.shown"
    }

    // MARK: - Layout defaults

    public static let defaultHaloDiameter: CGFloat = 380
    public static let defaultIconSize: CGFloat = 48
    /// Default deadzone (centre hub) diameter — not user-tunable yet but
    /// referenced from the icon-radius bounds math.
    public static let layoutDeadzoneDiameter: CGFloat = 112
    /// Fraction of `haloDiameter / 2` where the soft-edge alpha mask
    /// starts fading. Icons should sit inside this; the default
    /// `iconRadius` centres them between the hub edge and this value.
    public static let visibleOuterFactor: CGFloat = 0.84

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        registerDefaults()
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            Keys.slotCount: 8,
            Keys.profile: FrequencyProfile.balanced.rawValue,
            Keys.summonPosition: SummonPosition.mouse.rawValue,
            Keys.hotkeyKeyCode: 49,                                    // Space
            Keys.hotkeyMods: Int(HotkeyModifiers([.command, .option]).rawValue),
            Keys.cmdHoldDuration: 1.5,
            Keys.cmdDoubleTapGap: 0.30,
            Keys.autostart: false,
            Keys.panelScale: 1.0,
            Keys.scrollToSwitch: true,
            Keys.numberKeyCommit: true,
            Keys.highlightFront: true,
            Keys.doubleTapTrigger: DoubleTapTrigger.command.rawValue,
            Keys.soundEffects: true,
        ])
    }

    // MARK: - Simple scalars

    public var slotCount: Int {
        get { max(4, min(12, defaults.integer(forKey: Keys.slotCount))) }
        set {
            objectWillChange.send()
            let clamped = max(4, min(12, newValue))
            let old = slotCount
            defaults.set(clamped, forKey: Keys.slotCount)
            resizePinned(from: old, to: clamped)
        }
    }

    public var frequencyProfile: FrequencyProfile {
        get {
            let raw = defaults.string(forKey: Keys.profile) ?? FrequencyProfile.balanced.rawValue
            return FrequencyProfile(rawValue: raw) ?? .balanced
        }
        set {
            objectWillChange.send()
            defaults.set(newValue.rawValue, forKey: Keys.profile)
        }
    }

    public var summonPosition: SummonPosition {
        get {
            let raw = defaults.string(forKey: Keys.summonPosition) ?? SummonPosition.mouse.rawValue
            return SummonPosition(rawValue: raw) ?? .mouse
        }
        set {
            objectWillChange.send()
            defaults.set(newValue.rawValue, forKey: Keys.summonPosition)
        }
    }

    public var hotkeyKeyCode: UInt32 {
        get { UInt32(defaults.integer(forKey: Keys.hotkeyKeyCode)) }
        set {
            objectWillChange.send()
            defaults.set(Int(newValue), forKey: Keys.hotkeyKeyCode)
        }
    }

    public var hotkeyModifiers: HotkeyModifiers {
        get { HotkeyModifiers(rawValue: UInt32(defaults.integer(forKey: Keys.hotkeyMods))) }
        set {
            objectWillChange.send()
            defaults.set(Int(newValue.rawValue), forKey: Keys.hotkeyMods)
        }
    }

    /// How long the user must hold ⌘ alone before Halo is summoned. Clamped
    /// to [0.5, 3.0] seconds so the second-hotkey can never be instant (which
    /// would fight with system ⌘ chords) or unreasonably long.
    ///
    /// Retained for migration; the active second-trigger gesture is now
    /// `cmdDoubleTapGap`. Reading this lets old plists carry their stored
    /// value forward without surfacing it in UI.
    public var cmdHoldDuration: TimeInterval {
        get {
            let raw = defaults.double(forKey: Keys.cmdHoldDuration)
            let value = raw == 0 ? 1.5 : raw
            return max(0.5, min(3.0, value))
        }
        set {
            objectWillChange.send()
            let clamped = max(0.5, min(3.0, newValue))
            defaults.set(clamped, forKey: Keys.cmdHoldDuration)
        }
    }

    /// Maximum allowed delay between releasing ⌘ after the first tap and
    /// pressing it again to register a double-tap. Clamped to [0.15, 0.50]
    /// seconds — tight enough that ⌘+c → ⌘+v in rapid succession only
    /// triggers if both presses are pure (no other key in between) AND
    /// happen within the window.
    public var cmdDoubleTapGap: TimeInterval {
        get {
            let raw = defaults.double(forKey: Keys.cmdDoubleTapGap)
            let value = raw == 0 ? 0.30 : raw
            return max(0.15, min(0.50, value))
        }
        set {
            objectWillChange.send()
            let clamped = max(0.15, min(0.50, newValue))
            defaults.set(clamped, forKey: Keys.cmdDoubleTapGap)
        }
    }

    /// User-facing language override. `nil` means follow the system locale.
    /// Writing also mirrors into `AppleLanguages` so the override survives
    /// across launches and is picked up by SwiftUI / Foundation localization.
    /// Takes effect on next launch — SwiftUI's `Text("key")` resolves at view
    /// build time against `Bundle.main`'s current localization, which only
    /// re-evaluates after process restart.
    public var appLanguageOverride: String? {
        get { defaults.string(forKey: Keys.languageOverride) }
        set {
            objectWillChange.send()
            if let value = newValue {
                defaults.set(value, forKey: Keys.languageOverride)
                defaults.set([value], forKey: "AppleLanguages")
            } else {
                defaults.removeObject(forKey: Keys.languageOverride)
                defaults.removeObject(forKey: "AppleLanguages")
            }
        }
    }

    public var autostart: Bool {
        get { defaults.bool(forKey: Keys.autostart) }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: Keys.autostart)
        }
    }

    /// Which physical key (or button) drives the auxiliary double-tap
    /// trigger. The Carbon hotkey chord is independent of this; see
    /// `DoubleTapTrigger` for the available paths.
    public var doubleTapTrigger: DoubleTapTrigger {
        get {
            let raw = defaults.string(forKey: Keys.doubleTapTrigger) ?? DoubleTapTrigger.command.rawValue
            return DoubleTapTrigger(rawValue: raw) ?? .command
        }
        set {
            objectWillChange.send()
            defaults.set(newValue.rawValue, forKey: Keys.doubleTapTrigger)
        }
    }

    /// When true, the scroll wheel / two-finger swipe rotates Halo's
    /// highlighted slot while Halo is summoned. Off makes scrolls inert.
    public var scrollToSwitch: Bool {
        get { defaults.bool(forKey: Keys.scrollToSwitch) }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: Keys.scrollToSwitch)
        }
    }

    /// When true, pressing a digit / `0` / `-` / `=` commits the matching
    /// slot directly.
    public var numberKeyCommit: Bool {
        get { defaults.bool(forKey: Keys.numberKeyCommit) }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: Keys.numberKeyCommit)
        }
    }

    /// When true, Halo seeds its highlight on summon to the slot index of
    /// the frontmost app (if pinned), so a "Halo → scroll once → switch
    /// back" gesture is one tick away. Falls back to slot 0.
    public var highlightFrontmostOnSummon: Bool {
        get { defaults.bool(forKey: Keys.highlightFront) }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: Keys.highlightFront)
        }
    }

    /// Master switch for the three UX sound effects (summon / commit /
    /// slide). Defaults on so first-launch users hear feedback at least
    /// once and can discover the toggle in Settings → Sound.
    public var soundEffectsEnabled: Bool {
        get { defaults.bool(forKey: Keys.soundEffects) }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: Keys.soundEffects)
        }
    }

    // MARK: - Pinned slots

    /// `nil` at index i means "let the engine fill this slot from Top-N".
    public var pinnedBundleIDs: [String?] {
        if let data = defaults.data(forKey: Keys.pinnedSlots),
           let decoded = try? JSONDecoder().decode([String?].self, from: data),
           decoded.count == slotCount {
            return decoded
        }
        return Array(repeating: nil, count: slotCount)
    }

    /// Bundle IDs that were pinned at a higher slot index than the current
    /// `slotCount` allows; preserved per VISUAL §11 ("Pin 超出部分保留但暂不显示").
    public var overflowPinnedBundleIDs: [String] {
        guard let data = defaults.data(forKey: Keys.overflowPins),
              let arr = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return arr
    }

    public func setPinnedBundleID(_ id: String?, at slot: Int) {
        var current = pinnedBundleIDs
        guard (0..<current.count).contains(slot) else { return }
        objectWillChange.send()
        current[slot] = id
        savePinned(current, overflow: overflowPinnedBundleIDs)
    }

    private func resizePinned(from oldN: Int, to newN: Int) {
        guard oldN != newN else { return }
        var existing = (try? JSONDecoder().decode([String?].self,
                                                  from: defaults.data(forKey: Keys.pinnedSlots) ?? Data()))
            ?? Array(repeating: nil, count: oldN)
        var overflow = overflowPinnedBundleIDs

        if newN < existing.count {
            // Shrinking: spill trailing pins into overflow.
            let spilled = existing[newN...].compactMap { $0 }
            overflow.append(contentsOf: spilled)
            existing = Array(existing.prefix(newN))
        } else {
            // Growing: append nils, then re-place overflow entries into the first nil slots.
            existing.append(contentsOf: Array(repeating: nil, count: newN - existing.count))
            var remaining: [String] = []
            for id in overflow {
                if let firstEmpty = existing.firstIndex(where: { $0 == nil }) {
                    existing[firstEmpty] = id
                } else {
                    remaining.append(id)
                }
            }
            overflow = remaining
        }
        savePinned(existing, overflow: overflow)
    }

    private func savePinned(_ slots: [String?], overflow: [String]) {
        if let data = try? JSONEncoder().encode(slots) {
            defaults.set(data, forKey: Keys.pinnedSlots)
        }
        if let data = try? JSONEncoder().encode(overflow) {
            defaults.set(data, forKey: Keys.overflowPins)
        }
    }

    // MARK: - Identity color override

    private struct OverrideMap: Codable {
        var entries: [String: IdentityColor]
    }

    public func identityOverride(for bundleID: String) -> IdentityColor? {
        guard let data = defaults.data(forKey: Keys.identityOver),
              let map = try? JSONDecoder().decode(OverrideMap.self, from: data)
        else { return nil }
        return map.entries[bundleID]
    }

    public func setIdentityOverride(_ color: IdentityColor?, for bundleID: String) {
        var map: OverrideMap = (try? JSONDecoder().decode(OverrideMap.self,
                                                         from: defaults.data(forKey: Keys.identityOver) ?? Data()))
            ?? OverrideMap(entries: [:])
        objectWillChange.send()
        if let color = color {
            map.entries[bundleID] = color
        } else {
            map.entries.removeValue(forKey: bundleID)
        }
        if let data = try? JSONEncoder().encode(map) {
            defaults.set(data, forKey: Keys.identityOver)
        }
    }

    // MARK: - Layout (user-tunable wheel sizing)

    /// Outer diameter of the radial Halo, in points. Clamped to a usable
    /// range so users can't shrink the wheel below sector legibility or
    /// blow it past a small display.
    public var haloDiameter: CGFloat {
        get {
            let raw = CGFloat(defaults.double(forKey: Keys.haloDiameter))
            let value = raw == 0 ? Self.defaultHaloDiameter : raw
            return max(280, min(440, value))
        }
        set {
            objectWillChange.send()
            let clamped = max(280, min(440, newValue))
            defaults.set(Double(clamped), forKey: Keys.haloDiameter)
        }
    }

    /// Slot icon dimension, in points.
    public var iconSize: CGFloat {
        get {
            let raw = CGFloat(defaults.double(forKey: Keys.iconSize))
            let value = raw == 0 ? Self.defaultIconSize : raw
            return max(36, min(64, value))
        }
        set {
            objectWillChange.send()
            let clamped = max(36, min(64, newValue))
            defaults.set(Double(clamped), forKey: Keys.iconSize)
        }
    }

    /// Distance from the wheel centre to each slot icon's centre, in
    /// points. Bounds depend on `haloDiameter` and `iconSize` — icons
    /// must clear the hub on the inside and the feathered rim on the
    /// outside. Stored value is auto-clamped on read so a stored value
    /// from a larger Halo configuration won't render off-screen if the
    /// user shrinks the wheel later.
    public var iconRadius: CGFloat {
        get {
            let raw = CGFloat(defaults.double(forKey: Keys.iconRadius))
            let value = raw == 0 ? defaultIconRadius : raw
            let bounds = iconRadiusBounds
            return max(bounds.min, min(bounds.max, value))
        }
        set {
            objectWillChange.send()
            let bounds = iconRadiusBounds
            let clamped = max(bounds.min, min(bounds.max, newValue))
            defaults.set(Double(clamped), forKey: Keys.iconRadius)
        }
    }

    /// What `iconRadius` would compute to from the current `haloDiameter`
    /// + the layout deadzone, mid-balanced between hub edge and the
    /// soft-mask fade-start. Used as the auto value when the user
    /// hasn't set an override yet, and as the target of `resetLayout()`.
    public var defaultIconRadius: CGFloat {
        let visibleOuter = haloDiameter / 2 * Self.visibleOuterFactor
        let hubR = Self.layoutDeadzoneDiameter / 2
        return (visibleOuter + hubR) / 2
    }

    /// Allowed range for `iconRadius` given current `haloDiameter` /
    /// `iconSize`. The 4 pt padding on each end keeps the icon glyph
    /// from kissing the hub or the fade.
    public var iconRadiusBounds: (min: CGFloat, max: CGFloat) {
        let hubR = Self.layoutDeadzoneDiameter / 2
        let visibleOuter = haloDiameter / 2 * Self.visibleOuterFactor
        let halfIcon = iconSize / 2
        let lower = hubR + halfIcon + 4
        let upper = max(lower, visibleOuter - halfIcon - 4)
        return (lower, upper)
    }

    /// Renderer-time uniform multiplier applied at the Halo panel root —
    /// scales every layout dimension together so visually-impaired users
    /// can enlarge the wheel without re-tuning the three base sliders.
    /// Clamped to 0.80–1.50: smaller breaks sector hit-test precision;
    /// larger overflows a 13" display.
    public var panelScale: CGFloat {
        get {
            let raw = CGFloat(defaults.double(forKey: Keys.panelScale))
            let value = raw == 0 ? 1.0 : raw
            return max(0.80, min(1.50, value))
        }
        set {
            objectWillChange.send()
            let clamped = max(0.80, min(1.50, newValue))
            defaults.set(Double(clamped), forKey: Keys.panelScale)
        }
    }

    /// Restore all layout values (including panelScale) to their defaults.
    public func resetLayout() {
        objectWillChange.send()
        defaults.removeObject(forKey: Keys.haloDiameter)
        defaults.removeObject(forKey: Keys.iconSize)
        defaults.removeObject(forKey: Keys.iconRadius)
        defaults.removeObject(forKey: Keys.panelScale)
        HaloLog.settings.info("Reset wheel layout to defaults")
    }

    // MARK: - Whitelist

    /// Bundle IDs of frontmost apps where Halo's triggers (chord +
    /// double-tap) are suppressed entirely. Edits dedupe in stable order
    /// so the UI's row order matches storage order.
    public var whitelistedBundleIDs: [String] {
        get {
            guard let data = defaults.data(forKey: Keys.whitelist),
                  let arr = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return arr
        }
        set {
            objectWillChange.send()
            var seen: Set<String> = []
            let deduped = newValue.filter { seen.insert($0).inserted }
            if let data = try? JSONEncoder().encode(deduped) {
                defaults.set(data, forKey: Keys.whitelist)
            }
        }
    }

    /// O(1) suppression check for the event-tap hot path. Frontmost may
    /// be `nil` during transitions (lockscreen, app launch); treat that
    /// as "not whitelisted" so we don't drop the trigger when the user
    /// is trying to recover focus.
    public func isHaloSuppressed(forFrontmost bundleID: String?) -> Bool {
        guard let bundleID = bundleID else { return false }
        return whitelistedBundleIDs.contains(bundleID)
    }

    // MARK: - Action bindings (Action Ring layer 2)

    /// JSON-encoded map of bundleID → ordered list of HaloAction. Stored as
    /// a single Data blob so the existing `objectWillChange` plumbing fires
    /// on any edit and so we don't pollute UserDefaults with one key per
    /// bundle. Cap-free at storage; the renderer takes the first
    /// `slotCount` entries (spec §7).
    public func actions(forBundleID bundleID: String) -> [HaloAction] {
        loadActionMap()[bundleID] ?? []
    }

    /// All bundleIDs that currently have at least one bound action.
    /// Used by Settings to list configured apps. Order is the JSON dictionary's
    /// iteration order (undefined), so callers sort however they need.
    public var actionBoundBundleIDs: [String] {
        Array(loadActionMap().keys)
    }

    public func setActions(_ actions: [HaloAction], forBundleID bundleID: String) {
        objectWillChange.send()
        var map = loadActionMap()
        if actions.isEmpty {
            map.removeValue(forKey: bundleID)
        } else {
            map[bundleID] = actions
        }
        saveActionMap(map)
    }

    /// Convenience: replace the action at `index`. No-op when out of bounds.
    public func updateAction(_ action: HaloAction, at index: Int, forBundleID bundleID: String) {
        var current = actions(forBundleID: bundleID)
        guard current.indices.contains(index) else { return }
        current[index] = action
        setActions(current, forBundleID: bundleID)
    }

    public func removeAction(at index: Int, forBundleID bundleID: String) {
        var current = actions(forBundleID: bundleID)
        guard current.indices.contains(index) else { return }
        current.remove(at: index)
        setActions(current, forBundleID: bundleID)
    }

    private func loadActionMap() -> [String: [HaloAction]] {
        guard let data = defaults.data(forKey: Keys.actionBindings),
              let decoded = try? JSONDecoder().decode([String: [HaloAction]].self, from: data)
        else { return [:] }
        return decoded
    }

    private func saveActionMap(_ map: [String: [HaloAction]]) {
        if map.isEmpty {
            defaults.removeObject(forKey: Keys.actionBindings)
            return
        }
        if let data = try? JSONEncoder().encode(map) {
            defaults.set(data, forKey: Keys.actionBindings)
        }
    }

    // MARK: - Bindings

    // TODO: Apps 布局支持多 profile —— 把 pinnedSlots / overflowPins /
    // identityOverride 都按 profile name 分桶（"default" / "work" /
    // "gaming" ...），Settings 上加 profile 切换器。当前所有键都隐含在
    // "default" 这一个 profile 下；未来重构时只需把 storage key 改成
    // `halo.prefs.bindings.<profile>.<key>` 并把 currentProfile 持久化。
    public func clearAllBindings() {
        objectWillChange.send()
        let n = slotCount
        savePinned(Array(repeating: nil, count: n), overflow: [])
        defaults.removeObject(forKey: Keys.identityOver)
        HaloLog.settings.info("Cleared all pins + identity overrides (slot count \(n))")
    }

    // MARK: - Onboarding

    public func resetOnboarding() {
        objectWillChange.send()
        defaults.removeObject(forKey: Keys.onboardingShown)
    }
}
