import Foundation

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
        static let onboardingShown = "halo.onboarding.shown"
    }

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

    /// How long the user must hold ⌘ alone before the HUD is summoned. Clamped
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

    // MARK: - Onboarding

    public func resetOnboarding() {
        objectWillChange.send()
        defaults.removeObject(forKey: Keys.onboardingShown)
    }
}
