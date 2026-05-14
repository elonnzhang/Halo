# Multi-Profile / 场景环 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add named, switchable Binding Profiles (Default / Coding / Meeting / …) that bundle pins, slot count, ranking model, identity-color overrides and whitelist; hotkey / layout / language / sound stay global.

**Architecture:** A new `BindingProfile` value type holds the per-context state. `AppPreferences` keeps its existing scalar API surface, but internally projects every per-profile field from the active profile. Existing engine call sites are untouched; the change propagates through the existing `objectWillChange → recomputeSlots()` path. Migration runs once on init to fold legacy `UserDefaults` keys into a single "Default" profile.

**Tech Stack:** Swift / SwiftUI, AppKit (`NSMenu` for the menu-bar submenu), XCTest. macOS 12+ compatibility maintained.

**Reference spec:** [`docs/superpowers/specs/2026-05-14-multi-profile-design.md`](../specs/2026-05-14-multi-profile-design.md)

---

## File Structure

**Create:**
- `Sources/HaloCore/BindingProfile.swift` — value type, ~120 lines
- `Sources/HaloApp/ProfilesTab.swift` — Settings → Profiles section view
- `Tests/HaloCoreTests/BindingProfileTests.swift`
- `Tests/HaloCoreTests/AppPreferencesProfileTests.swift`

**Modify:**
- `Sources/HaloCore/AppPreferences.swift` — projection layer, migration, profile management API; remove the multi-profile TODO comment
- `Sources/HaloApp/SettingsSidebar.swift` — add `.profiles` case to `SettingsSection`
- `Sources/HaloApp/SettingsWindow.swift` — route `.profiles` to `ProfilesTab`, add active-profile picker, swap "Default binding" label, drop the multi-profile TODO comment
- `Sources/HaloApp/GeneralSettingsTab.swift` — small "{profile.name}" chip on the slot-count and frequency-profile rows
- `Sources/HaloUI/MenuBarController.swift` — new `onProfileList` / `onProfileSelect` / `onEditProfiles` callbacks + dynamic submenu
- `Sources/HaloApp/AppDelegate.swift` — wire new MenuBarController callbacks; expose `openSettingsAtProfiles()` helper
- `CHANGELOG.md` — v1.2.0 entry
- `Resources/Info.plist` — `CFBundleShortVersionString` bump
- `Resources/*.lproj/Localizable.strings` — new strings used by `ProfilesTab`, picker, menu

---

### Task 1: `BindingProfile` value type

**Files:**
- Create: `Sources/HaloCore/BindingProfile.swift`
- Test: `Tests/HaloCoreTests/BindingProfileTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/HaloCoreTests/BindingProfileTests.swift`:

```swift
import XCTest
@testable import HaloCore

final class BindingProfileTests: XCTestCase {
    func test_freshDefault_hasSlotCount8AndEmptyBindings() {
        let p = BindingProfile.freshDefault()
        XCTAssertEqual(p.name, "Default")
        XCTAssertEqual(p.slotCount, 8)
        XCTAssertEqual(p.rankingProfile, .balanced)
        XCTAssertEqual(p.pinnedBundleIDs.count, 8)
        XCTAssertTrue(p.pinnedBundleIDs.allSatisfy { $0 == nil })
        XCTAssertTrue(p.overflowPinnedBundleIDs.isEmpty)
        XCTAssertTrue(p.identityOverrides.isEmpty)
        XCTAssertTrue(p.whitelistedBundleIDs.isEmpty)
    }

    func test_codable_roundTripPreservesAllFields() throws {
        var p = BindingProfile.freshDefault()
        p.name = "Coding"
        p.slotCount = 10
        p.rankingProfile = .mfuOnly
        p.pinnedBundleIDs = Array(repeating: nil, count: 10)
        p.pinnedBundleIDs[0] = "com.apple.Terminal"
        p.pinnedBundleIDs[3] = "com.microsoft.VSCode"
        p.overflowPinnedBundleIDs = ["com.figma.Desktop"]
        p.identityOverrides = ["com.apple.Terminal": IdentityColor(hue: 200, chroma: 0.4, lightness: 0.5)]
        p.whitelistedBundleIDs = ["com.valvesoftware.steam"]

        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(BindingProfile.self, from: data)
        XCTAssertEqual(decoded, p)
    }

    func test_resizingSmaller_spillsTailPinsIntoOverflow() {
        var p = BindingProfile.freshDefault()
        p.pinnedBundleIDs[0] = "a"
        p.pinnedBundleIDs[5] = "f"
        p.pinnedBundleIDs[7] = "h"
        let smaller = p.resizing(slotCount: 6)
        XCTAssertEqual(smaller.slotCount, 6)
        XCTAssertEqual(smaller.pinnedBundleIDs.count, 6)
        XCTAssertEqual(smaller.pinnedBundleIDs[0], "a")
        XCTAssertEqual(smaller.pinnedBundleIDs[5], "f")
        XCTAssertEqual(smaller.overflowPinnedBundleIDs, ["h"])
    }

    func test_resizingLarger_replacesOverflowIntoLeadingEmptySlots() {
        var p = BindingProfile.freshDefault()
        p.slotCount = 4
        p.pinnedBundleIDs = ["a", nil, "c", nil]
        p.overflowPinnedBundleIDs = ["e", "f"]
        let larger = p.resizing(slotCount: 8)
        XCTAssertEqual(larger.slotCount, 8)
        XCTAssertEqual(larger.pinnedBundleIDs.count, 8)
        XCTAssertEqual(larger.pinnedBundleIDs[0], "a")
        XCTAssertEqual(larger.pinnedBundleIDs[1], "e")
        XCTAssertEqual(larger.pinnedBundleIDs[2], "c")
        XCTAssertEqual(larger.pinnedBundleIDs[3], "f")
        XCTAssertTrue(larger.pinnedBundleIDs[4..<8].allSatisfy { $0 == nil })
        XCTAssertTrue(larger.overflowPinnedBundleIDs.isEmpty)
    }

    func test_resizingToSameSize_isIdentity() {
        var p = BindingProfile.freshDefault()
        p.pinnedBundleIDs[3] = "x"
        let same = p.resizing(slotCount: 8)
        XCTAssertEqual(same, p)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter BindingProfileTests`
Expected: FAIL with "no such module member 'BindingProfile'" / type not found.

- [ ] **Step 3: Implement `BindingProfile`**

Create `Sources/HaloCore/BindingProfile.swift`:

```swift
import Foundation

/// One named scene's worth of bindings — what travels with a profile
/// (pins, slot count, ranking, identity colours, whitelist). Anything
/// not in this struct stays global to the user.
public struct BindingProfile: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    public var slotCount: Int
    public var rankingProfile: FrequencyProfile
    public var pinnedBundleIDs: [String?]
    public var overflowPinnedBundleIDs: [String]
    public var identityOverrides: [String: IdentityColor]
    public var whitelistedBundleIDs: [String]

    public init(
        id: UUID = UUID(),
        name: String,
        slotCount: Int = 8,
        rankingProfile: FrequencyProfile = .balanced,
        pinnedBundleIDs: [String?]? = nil,
        overflowPinnedBundleIDs: [String] = [],
        identityOverrides: [String: IdentityColor] = [:],
        whitelistedBundleIDs: [String] = []
    ) {
        self.id = id
        self.name = name
        let n = max(4, min(12, slotCount))
        self.slotCount = n
        self.rankingProfile = rankingProfile
        if let pins = pinnedBundleIDs, pins.count == n {
            self.pinnedBundleIDs = pins
        } else {
            self.pinnedBundleIDs = Array(repeating: nil, count: n)
        }
        self.overflowPinnedBundleIDs = overflowPinnedBundleIDs
        self.identityOverrides = identityOverrides
        self.whitelistedBundleIDs = whitelistedBundleIDs
    }
}

extension BindingProfile {
    /// Canonical empty profile used at first launch and during migration
    /// when no legacy keys exist.
    public static func freshDefault() -> BindingProfile {
        BindingProfile(name: "Default")
    }

    /// Return a new profile resized to `newN`. Same semantics as
    /// `AppPreferences.resizePinned(from:to:)`:
    /// - shrinking: trailing non-nil pins spill into `overflow`
    /// - growing: overflow entries refill leading nil slots in order
    public func resizing(slotCount newN: Int) -> BindingProfile {
        let clamped = max(4, min(12, newN))
        guard clamped != slotCount else { return self }

        var pins = pinnedBundleIDs
        var overflow = overflowPinnedBundleIDs

        if clamped < pins.count {
            let spilled = pins[clamped...].compactMap { $0 }
            overflow.append(contentsOf: spilled)
            pins = Array(pins.prefix(clamped))
        } else {
            pins.append(contentsOf: Array(repeating: nil, count: clamped - pins.count))
            var remaining: [String] = []
            for id in overflow {
                if let firstEmpty = pins.firstIndex(where: { $0 == nil }) {
                    pins[firstEmpty] = id
                } else {
                    remaining.append(id)
                }
            }
            overflow = remaining
        }

        var copy = self
        copy.slotCount = clamped
        copy.pinnedBundleIDs = pins
        copy.overflowPinnedBundleIDs = overflow
        return copy
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter BindingProfileTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/HaloCore/BindingProfile.swift Tests/HaloCoreTests/BindingProfileTests.swift
git commit -m "feat(core): introduce BindingProfile value type

Per-context bundle: pins, slot count, ranking profile, identity
overrides, whitelist. resizing(slotCount:) mirrors the existing
shrink/grow + overflow semantics so the projection layer can reuse it."
```

---

### Task 2: `AppPreferences` migration to profile-projected reads

This task switches every *read* path in `AppPreferences` to go through the active profile, while leaving setter behaviour unchanged in observable terms. Migration runs in `init` if `profiles.v1` is absent.

**Files:**
- Modify: `Sources/HaloCore/AppPreferences.swift`
- Test: `Tests/HaloCoreTests/AppPreferencesProfileTests.swift` (new)

- [ ] **Step 1: Write the failing test (migration + projection)**

Create `Tests/HaloCoreTests/AppPreferencesProfileTests.swift`:

```swift
import XCTest
@testable import HaloCore

@MainActor
final class AppPreferencesProfileTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let suite = "halo.prefs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// Seed legacy keys directly, simulate a v1.1.x install upgrading.
    private func seedLegacyKeys(into defaults: UserDefaults) {
        defaults.set(10, forKey: "halo.prefs.slotCount")
        defaults.set("mfuOnly", forKey: "halo.prefs.frequencyProfile")
        let pins: [String?] = ["com.apple.Terminal", nil, "com.microsoft.VSCode",
                               nil, nil, nil, nil, nil, nil, nil]
        defaults.set(try? JSONEncoder().encode(pins), forKey: "halo.prefs.pinnedSlots.v1")
        defaults.set(try? JSONEncoder().encode(["com.figma.Desktop"]),
                     forKey: "halo.prefs.overflowPins.v1")
        defaults.set(try? JSONEncoder().encode(["com.valvesoftware.steam"]),
                     forKey: "halo.prefs.whitelist.v1")
    }

    func test_firstLaunchFromBlankDefaults_createsOneDefaultProfile() {
        let prefs = AppPreferences(defaults: freshDefaults())
        XCTAssertEqual(prefs.profiles.count, 1)
        XCTAssertEqual(prefs.activeProfile.name, "Default")
        XCTAssertEqual(prefs.slotCount, 8)
        XCTAssertEqual(prefs.frequencyProfile, .balanced)
        XCTAssertTrue(prefs.whitelistedBundleIDs.isEmpty)
    }

    func test_legacyKeysMigrateIntoSingleDefaultProfile() {
        let defaults = freshDefaults()
        seedLegacyKeys(into: defaults)

        let prefs = AppPreferences(defaults: defaults)
        XCTAssertEqual(prefs.profiles.count, 1)
        let p = prefs.activeProfile
        XCTAssertEqual(p.name, "Default")
        XCTAssertEqual(p.slotCount, 10)
        XCTAssertEqual(p.rankingProfile, .mfuOnly)
        XCTAssertEqual(p.pinnedBundleIDs.count, 10)
        XCTAssertEqual(p.pinnedBundleIDs[0], "com.apple.Terminal")
        XCTAssertEqual(p.pinnedBundleIDs[2], "com.microsoft.VSCode")
        XCTAssertEqual(p.overflowPinnedBundleIDs, ["com.figma.Desktop"])
        XCTAssertEqual(p.whitelistedBundleIDs, ["com.valvesoftware.steam"])

        // Scalar projection reads same values.
        XCTAssertEqual(prefs.slotCount, 10)
        XCTAssertEqual(prefs.frequencyProfile, .mfuOnly)
        XCTAssertEqual(prefs.pinnedBundleIDs[0], "com.apple.Terminal")
        XCTAssertEqual(prefs.whitelistedBundleIDs, ["com.valvesoftware.steam"])
    }

    func test_migrationIsIdempotent() {
        let defaults = freshDefaults()
        seedLegacyKeys(into: defaults)
        _ = AppPreferences(defaults: defaults)
        let firstID = AppPreferences(defaults: defaults).activeProfile.id

        // Second pass over the same defaults reads the persisted
        // profiles.v1 instead of re-running migration.
        let again = AppPreferences(defaults: defaults)
        XCTAssertEqual(again.profiles.count, 1)
        XCTAssertEqual(again.activeProfile.id, firstID)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AppPreferencesProfileTests`
Expected: FAIL with missing symbols (`profiles`, `activeProfile`).

- [ ] **Step 3: Add storage keys + profile-aware initialiser**

In `Sources/HaloCore/AppPreferences.swift`, extend the `Keys` enum (after `Keys.onboardingShown`):

```swift
        static let profilesV1     = "halo.prefs.profiles.v1"
        static let activeProfile  = "halo.prefs.activeProfileID"
```

Replace `public init(defaults: UserDefaults = .standard) { … }` with:

```swift
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        registerDefaults()
        if defaults.data(forKey: Keys.profilesV1) == nil {
            migrateLegacyKeysIntoDefaultProfile()
        }
    }

    private func migrateLegacyKeysIntoDefaultProfile() {
        // Read raw legacy keys directly; the projection getters are
        // not safe to call before profiles.v1 is initialised.
        let slot = max(4, min(12, defaults.integer(forKey: Keys.slotCount).nonzeroOr(8)))
        let rankingRaw = defaults.string(forKey: Keys.profile)
            ?? FrequencyProfile.balanced.rawValue
        let ranking = FrequencyProfile(rawValue: rankingRaw) ?? .balanced

        let pins: [String?] = {
            if let data = defaults.data(forKey: Keys.pinnedSlots),
               let decoded = try? JSONDecoder().decode([String?].self, from: data),
               decoded.count == slot {
                return decoded
            }
            return Array(repeating: nil, count: slot)
        }()

        let overflow: [String] = {
            guard let data = defaults.data(forKey: Keys.overflowPins),
                  let arr = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return arr
        }()

        let overrides: [String: IdentityColor] = {
            struct M: Codable { var entries: [String: IdentityColor] }
            guard let data = defaults.data(forKey: Keys.identityOver),
                  let map = try? JSONDecoder().decode(M.self, from: data)
            else { return [:] }
            return map.entries
        }()

        let whitelist: [String] = {
            guard let data = defaults.data(forKey: Keys.whitelist),
                  let arr = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return arr
        }()

        let migrated = BindingProfile(
            name: "Default",
            slotCount: slot,
            rankingProfile: ranking,
            pinnedBundleIDs: pins,
            overflowPinnedBundleIDs: overflow,
            identityOverrides: overrides,
            whitelistedBundleIDs: whitelist
        )
        writeProfiles([migrated], activeID: migrated.id)
        HaloLog.settings.info("Migrated legacy prefs into Default profile (slots: \(slot), pins: \(pins.compactMap{$0}.count), whitelist: \(whitelist.count))")
    }
```

Add this tiny helper at the bottom of the file (above the closing brace):

```swift
private extension Int {
    func nonzeroOr(_ fallback: Int) -> Int { self == 0 ? fallback : self }
}
```

- [ ] **Step 4: Add backing storage + projection helpers**

In `AppPreferences`, just below `private let defaults: UserDefaults`, add:

```swift
    /// In-memory cache, persisted to `Keys.profilesV1` on every mutation.
    private var _profiles: [BindingProfile] = []
    private var _activeProfileID: UUID = UUID()
    private var _profilesLoaded = false

    public var profiles: [BindingProfile] {
        loadProfilesIfNeeded()
        return _profiles
    }

    public var activeProfileID: UUID {
        loadProfilesIfNeeded()
        return _activeProfileID
    }

    public var activeProfile: BindingProfile {
        loadProfilesIfNeeded()
        if let p = _profiles.first(where: { $0.id == _activeProfileID }) { return p }
        // Self-heal: persisted activeID points at a missing profile.
        if let first = _profiles.first {
            HaloLog.settings.warning("activeProfileID \(_activeProfileID) missing; falling back to \(first.id)")
            _activeProfileID = first.id
            persistActiveID()
            return first
        }
        // Last-resort: empty array — should only happen if the user
        // hand-edited the plist. Re-seed.
        let fresh = BindingProfile.freshDefault()
        _profiles = [fresh]
        _activeProfileID = fresh.id
        writeProfiles(_profiles, activeID: _activeProfileID)
        return fresh
    }

    private func loadProfilesIfNeeded() {
        guard !_profilesLoaded else { return }
        _profilesLoaded = true
        if let data = defaults.data(forKey: Keys.profilesV1),
           let decoded = try? JSONDecoder().decode([BindingProfile].self, from: data),
           !decoded.isEmpty {
            _profiles = decoded
            if let raw = defaults.string(forKey: Keys.activeProfile),
               let uuid = UUID(uuidString: raw) {
                _activeProfileID = uuid
            } else {
                _activeProfileID = decoded[0].id
            }
        } else {
            // No persisted profile and migration didn't run (e.g. brand-new
            // launch where init's migrate path also found nothing). Seed.
            let fresh = BindingProfile.freshDefault()
            _profiles = [fresh]
            _activeProfileID = fresh.id
            writeProfiles(_profiles, activeID: _activeProfileID)
        }
    }

    private func writeProfiles(_ profiles: [BindingProfile], activeID: UUID) {
        _profiles = profiles
        _activeProfileID = activeID
        _profilesLoaded = true
        if let data = try? JSONEncoder().encode(profiles) {
            defaults.set(data, forKey: Keys.profilesV1)
        }
        defaults.set(activeID.uuidString, forKey: Keys.activeProfile)
    }

    private func persistActiveID() {
        defaults.set(_activeProfileID.uuidString, forKey: Keys.activeProfile)
    }

    /// Mutate the active profile in place + persist. Caller provides the
    /// mutation closure. Caller is responsible for `objectWillChange.send()`.
    fileprivate func updateActiveProfile(_ mutate: (inout BindingProfile) -> Void) {
        loadProfilesIfNeeded()
        guard let idx = _profiles.firstIndex(where: { $0.id == _activeProfileID }) else {
            // self-heal as above
            _ = activeProfile
            return updateActiveProfile(mutate)
        }
        var profile = _profiles[idx]
        mutate(&profile)
        _profiles[idx] = profile
        writeProfiles(_profiles, activeID: _activeProfileID)
    }
```

- [ ] **Step 5: Switch the four projected getters to read from active profile**

Locate `public var slotCount: Int { … }` and replace the getter so only `get` changes; `set` is rewritten in Task 3. For now, keep the existing `set` exactly as-is:

```swift
    public var slotCount: Int {
        get { max(4, min(12, activeProfile.slotCount)) }
        set { /* unchanged for this task */
            objectWillChange.send()
            let clamped = max(4, min(12, newValue))
            let old = slotCount
            defaults.set(clamped, forKey: Keys.slotCount)
            resizePinned(from: old, to: clamped)
        }
    }
```

Locate `public var frequencyProfile: FrequencyProfile { … }` and replace the getter:

```swift
    public var frequencyProfile: FrequencyProfile {
        get { activeProfile.rankingProfile }
        set { /* unchanged for this task */ … }
    }
```

Locate `public var pinnedBundleIDs: [String?] { … }` and replace it:

```swift
    public var pinnedBundleIDs: [String?] {
        let pins = activeProfile.pinnedBundleIDs
        if pins.count == activeProfile.slotCount { return pins }
        return Array(repeating: nil, count: activeProfile.slotCount)
    }
```

Locate `public var overflowPinnedBundleIDs: [String] { … }` and replace it:

```swift
    public var overflowPinnedBundleIDs: [String] {
        activeProfile.overflowPinnedBundleIDs
    }
```

Locate `public func identityOverride(for bundleID: String) -> IdentityColor?` and replace:

```swift
    public func identityOverride(for bundleID: String) -> IdentityColor? {
        activeProfile.identityOverrides[bundleID]
    }
```

Locate `public var whitelistedBundleIDs: [String] { … }` getter and replace:

```swift
    public var whitelistedBundleIDs: [String] {
        get { activeProfile.whitelistedBundleIDs }
        set { /* unchanged for this task */ … }
    }
```

- [ ] **Step 6: Run tests to verify Task 2 tests pass and existing tests stay green**

Run: `swift test --filter AppPreferencesProfileTests`
Expected: PASS, 3 tests.

Run: `swift test --filter AppPreferencesTests`
Expected: PASS — existing tests must still pass. They mutate prefs and read back; setters still write the legacy keys, but reads now go via `activeProfile`. **If any existing test fails, that's the signal Task 3 is now required to keep them green.** Note any failure in the commit message; Task 3 will fix it.

Run: `swift test --filter AppPreferencesBoundsTests`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/HaloCore/AppPreferences.swift Tests/HaloCoreTests/AppPreferencesProfileTests.swift
git commit -m "feat(core): project per-profile getters from active BindingProfile

Reads route through the new profiles.v1 store. Setters still write
the legacy keys; Task 3 wires them through the active profile so
mutations survive a relaunch."
```

---

### Task 3: `AppPreferences` setters mutate active profile

After Task 2 the readers project from the active profile but writers still hit the legacy `UserDefaults` keys — meaning a `prefs.slotCount = 10` does not update the active profile and the next read returns the old projected value. This task routes every setter through `updateActiveProfile { … }`.

**Files:**
- Modify: `Sources/HaloCore/AppPreferences.swift`
- Test: `Tests/HaloCoreTests/AppPreferencesProfileTests.swift`

- [ ] **Step 1: Add the failing tests**

Append to `Tests/HaloCoreTests/AppPreferencesProfileTests.swift`:

```swift
    func test_slotCountSet_resizesActiveProfileNotLegacyKeys() {
        let prefs = AppPreferences(defaults: freshDefaults())
        prefs.slotCount = 12
        XCTAssertEqual(prefs.slotCount, 12)
        XCTAssertEqual(prefs.activeProfile.slotCount, 12)
        XCTAssertEqual(prefs.activeProfile.pinnedBundleIDs.count, 12)
    }

    func test_setPinnedBundleID_writesThroughToActiveProfile() {
        let prefs = AppPreferences(defaults: freshDefaults())
        prefs.setPinnedBundleID("com.apple.Safari", at: 2)
        XCTAssertEqual(prefs.pinnedBundleIDs[2], "com.apple.Safari")
        XCTAssertEqual(prefs.activeProfile.pinnedBundleIDs[2], "com.apple.Safari")
    }

    func test_frequencyProfileSet_writesActiveProfileRanking() {
        let prefs = AppPreferences(defaults: freshDefaults())
        prefs.frequencyProfile = .mruOnly
        XCTAssertEqual(prefs.activeProfile.rankingProfile, .mruOnly)
    }

    func test_setIdentityOverride_writesActiveProfileOverrides() {
        let prefs = AppPreferences(defaults: freshDefaults())
        let color = IdentityColor(hue: 30, chroma: 0.5, lightness: 0.6)
        prefs.setIdentityOverride(color, for: "com.apple.Safari")
        XCTAssertEqual(prefs.identityOverride(for: "com.apple.Safari"), color)
        XCTAssertEqual(prefs.activeProfile.identityOverrides["com.apple.Safari"], color)

        prefs.setIdentityOverride(nil, for: "com.apple.Safari")
        XCTAssertNil(prefs.identityOverride(for: "com.apple.Safari"))
        XCTAssertNil(prefs.activeProfile.identityOverrides["com.apple.Safari"])
    }

    func test_whitelistedBundleIDsSet_writesActiveProfileAndDedupes() {
        let prefs = AppPreferences(defaults: freshDefaults())
        prefs.whitelistedBundleIDs = ["a", "b", "a", "c", "b"]
        XCTAssertEqual(prefs.whitelistedBundleIDs, ["a", "b", "c"])
        XCTAssertEqual(prefs.activeProfile.whitelistedBundleIDs, ["a", "b", "c"])
    }

    func test_clearAllBindings_clearsOnlyActiveProfileBindings() {
        let prefs = AppPreferences(defaults: freshDefaults())
        prefs.setPinnedBundleID("a", at: 0)
        prefs.setIdentityOverride(IdentityColor(hue: 1, chroma: 0.1, lightness: 0.5),
                                  for: "a")
        prefs.clearAllBindings()
        XCTAssertTrue(prefs.activeProfile.pinnedBundleIDs.allSatisfy { $0 == nil })
        XCTAssertTrue(prefs.activeProfile.identityOverrides.isEmpty)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AppPreferencesProfileTests`
Expected: FAIL (slot count writes don't survive, pin sets don't update activeProfile).

- [ ] **Step 3: Re-route each setter through `updateActiveProfile`**

Replace `public var slotCount: Int { … }` in full with:

```swift
    public var slotCount: Int {
        get { max(4, min(12, activeProfile.slotCount)) }
        set {
            let clamped = max(4, min(12, newValue))
            guard clamped != activeProfile.slotCount else { return }
            objectWillChange.send()
            updateActiveProfile { profile in
                profile = profile.resizing(slotCount: clamped)
            }
        }
    }
```

Replace `public var frequencyProfile: FrequencyProfile { … }` in full:

```swift
    public var frequencyProfile: FrequencyProfile {
        get { activeProfile.rankingProfile }
        set {
            objectWillChange.send()
            updateActiveProfile { $0.rankingProfile = newValue }
        }
    }
```

Replace `public func setPinnedBundleID(_:at:)` in full:

```swift
    public func setPinnedBundleID(_ id: String?, at slot: Int) {
        guard (0..<activeProfile.slotCount).contains(slot) else { return }
        objectWillChange.send()
        updateActiveProfile { profile in
            profile.pinnedBundleIDs[slot] = id
        }
    }
```

Delete the now-unused `private func resizePinned(from:to:)` and `private func savePinned(_:overflow:)`. They are dead code: `resizing(slotCount:)` on `BindingProfile` is the new home.

Replace `public func setIdentityOverride(_:for:)` in full:

```swift
    public func setIdentityOverride(_ color: IdentityColor?, for bundleID: String) {
        objectWillChange.send()
        updateActiveProfile { profile in
            if let color = color {
                profile.identityOverrides[bundleID] = color
            } else {
                profile.identityOverrides.removeValue(forKey: bundleID)
            }
        }
    }
```

Delete the now-unused `private struct OverrideMap`. The active profile holds the dictionary directly.

Replace `public var whitelistedBundleIDs: [String] { … }` setter:

```swift
    public var whitelistedBundleIDs: [String] {
        get { activeProfile.whitelistedBundleIDs }
        set {
            objectWillChange.send()
            var seen: Set<String> = []
            let deduped = newValue.filter { seen.insert($0).inserted }
            updateActiveProfile { $0.whitelistedBundleIDs = deduped }
        }
    }
```

Replace `public func clearAllBindings()` in full:

```swift
    public func clearAllBindings() {
        objectWillChange.send()
        let n = activeProfile.slotCount
        updateActiveProfile { profile in
            profile.pinnedBundleIDs = Array(repeating: nil, count: n)
            profile.overflowPinnedBundleIDs = []
            profile.identityOverrides = [:]
        }
        HaloLog.settings.info("Cleared bindings in profile '\(activeProfile.name)' (slots: \(n))")
    }
```

- [ ] **Step 4: Drop the multi-profile TODO comment**

In `AppPreferences.swift`, delete the comment block at lines 522-526 starting `// TODO: Apps 布局支持多 profile`. The feature it described is now implemented.

- [ ] **Step 5: Run all HaloCore tests**

Run: `swift test --filter HaloCoreTests`
Expected: PASS. The existing `AppPreferencesTests` should now pass without any changes: their `prefs.slotCount = 6` etc. patterns go through `updateActiveProfile` and the read-back matches.

- [ ] **Step 6: Commit**

```bash
git add Sources/HaloCore/AppPreferences.swift Tests/HaloCoreTests/AppPreferencesProfileTests.swift
git commit -m "feat(core): route AppPreferences setters through active profile

Pin / colour / whitelist / slot count / ranking mutations now update
the active BindingProfile in place and persist profiles.v1. Existing
tests pass unchanged; resizePinned / OverrideMap are deleted (their
job is done by BindingProfile.resizing(slotCount:))."
```

---

### Task 4: Profile management API on `AppPreferences`

**Files:**
- Modify: `Sources/HaloCore/AppPreferences.swift`
- Test: `Tests/HaloCoreTests/AppPreferencesProfileTests.swift`

- [ ] **Step 1: Add failing tests**

Append to `AppPreferencesProfileTests.swift`:

```swift
    func test_addProfileBlank_appendsFreshDefaultRenamed() {
        let prefs = AppPreferences(defaults: freshDefaults())
        let p = prefs.addProfile(name: "Coding", cloning: nil)
        XCTAssertEqual(prefs.profiles.count, 2)
        XCTAssertEqual(p.name, "Coding")
        XCTAssertEqual(p.slotCount, 8)
        XCTAssertTrue(p.pinnedBundleIDs.allSatisfy { $0 == nil })
    }

    func test_addProfileCloningActive_deepCopiesBindings() {
        let prefs = AppPreferences(defaults: freshDefaults())
        prefs.setPinnedBundleID("com.apple.Safari", at: 0)
        prefs.whitelistedBundleIDs = ["com.example.x"]

        let original = prefs.activeProfile
        let clone = prefs.addProfile(name: "Work", cloning: original.id)
        XCTAssertNotEqual(clone.id, original.id)
        XCTAssertEqual(clone.pinnedBundleIDs, original.pinnedBundleIDs)
        XCTAssertEqual(clone.whitelistedBundleIDs, original.whitelistedBundleIDs)
    }

    func test_renameProfile_updatesName() {
        let prefs = AppPreferences(defaults: freshDefaults())
        let id = prefs.activeProfile.id
        prefs.renameProfile(id, to: "Home")
        XCTAssertEqual(prefs.activeProfile.name, "Home")
    }

    func test_switchToProfile_swapsScalarProjections() {
        let prefs = AppPreferences(defaults: freshDefaults())
        prefs.slotCount = 6
        prefs.frequencyProfile = .mfuOnly

        let work = prefs.addProfile(name: "Work", cloning: nil)
        prefs.switchToProfile(work.id)
        XCTAssertEqual(prefs.activeProfileID, work.id)
        XCTAssertEqual(prefs.slotCount, 8)            // fresh defaults
        XCTAssertEqual(prefs.frequencyProfile, .balanced)
    }

    func test_deleteActiveProfile_fallsBackToFirstRemaining() {
        let prefs = AppPreferences(defaults: freshDefaults())
        let secondID = prefs.addProfile(name: "Work", cloning: nil).id
        prefs.switchToProfile(secondID)
        prefs.deleteProfile(secondID)
        XCTAssertEqual(prefs.profiles.count, 1)
        XCTAssertEqual(prefs.activeProfile.name, "Default")
    }

    func test_deleteLastProfile_refusesAndLeavesStateIntact() {
        let prefs = AppPreferences(defaults: freshDefaults())
        let onlyID = prefs.activeProfile.id
        prefs.deleteProfile(onlyID)
        XCTAssertEqual(prefs.profiles.count, 1)
        XCTAssertEqual(prefs.activeProfile.id, onlyID)
    }

    func test_reorderProfiles_movesEntriesAndKeepsActiveID() {
        let prefs = AppPreferences(defaults: freshDefaults())
        let b = prefs.addProfile(name: "B", cloning: nil)
        let c = prefs.addProfile(name: "C", cloning: nil)
        let a = prefs.profiles[0].id

        prefs.reorderProfiles([c.id, a, b.id])
        XCTAssertEqual(prefs.profiles.map { $0.name }, ["C", "Default", "B"])
        XCTAssertEqual(prefs.activeProfileID, a)
    }

    func test_persistedProfilesSurviveRecreate() {
        let defaults = freshDefaults()
        do {
            let prefs = AppPreferences(defaults: defaults)
            _ = prefs.addProfile(name: "Coding", cloning: nil)
            _ = prefs.addProfile(name: "Meeting", cloning: nil)
            prefs.switchToProfile(prefs.profiles[1].id)
        }
        let prefs2 = AppPreferences(defaults: defaults)
        XCTAssertEqual(prefs2.profiles.map { $0.name },
                       ["Default", "Coding", "Meeting"])
        XCTAssertEqual(prefs2.activeProfile.name, "Coding")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AppPreferencesProfileTests`
Expected: FAIL with missing methods (`addProfile`, `renameProfile`, …).

- [ ] **Step 3: Implement the management API**

In `Sources/HaloCore/AppPreferences.swift`, just below the projection helpers (`updateActiveProfile`), add:

```swift
    @discardableResult
    public func addProfile(name: String, cloning sourceID: UUID?) -> BindingProfile {
        loadProfilesIfNeeded()
        let new: BindingProfile
        if let sourceID = sourceID,
           let source = _profiles.first(where: { $0.id == sourceID })
        {
            new = BindingProfile(
                id: UUID(),
                name: name,
                slotCount: source.slotCount,
                rankingProfile: source.rankingProfile,
                pinnedBundleIDs: source.pinnedBundleIDs,
                overflowPinnedBundleIDs: source.overflowPinnedBundleIDs,
                identityOverrides: source.identityOverrides,
                whitelistedBundleIDs: source.whitelistedBundleIDs
            )
        } else {
            var fresh = BindingProfile.freshDefault()
            fresh.name = name
            new = fresh
        }
        objectWillChange.send()
        _profiles.append(new)
        writeProfiles(_profiles, activeID: _activeProfileID)
        HaloLog.settings.info("Added profile '\(name)' (clone of: \(sourceID?.uuidString ?? "blank"))")
        return new
    }

    public func renameProfile(_ id: UUID, to newName: String) {
        loadProfilesIfNeeded()
        guard let idx = _profiles.firstIndex(where: { $0.id == id }) else { return }
        objectWillChange.send()
        _profiles[idx].name = newName
        writeProfiles(_profiles, activeID: _activeProfileID)
    }

    public func deleteProfile(_ id: UUID) {
        loadProfilesIfNeeded()
        guard _profiles.count > 1 else {
            HaloLog.settings.error("Refusing to delete the last profile (id: \(id))")
            return
        }
        guard let idx = _profiles.firstIndex(where: { $0.id == id }) else { return }
        objectWillChange.send()
        _profiles.remove(at: idx)
        if _activeProfileID == id {
            _activeProfileID = _profiles[0].id
        }
        writeProfiles(_profiles, activeID: _activeProfileID)
    }

    public func switchToProfile(_ id: UUID) {
        loadProfilesIfNeeded()
        guard _profiles.contains(where: { $0.id == id }) else {
            HaloLog.settings.warning("switchToProfile(\(id)) — id not found")
            return
        }
        guard id != _activeProfileID else { return }
        objectWillChange.send()
        _activeProfileID = id
        persistActiveID()
        HaloLog.settings.info("Switched to profile '\(activeProfile.name)'")
    }

    public func reorderProfiles(_ orderedIDs: [UUID]) {
        loadProfilesIfNeeded()
        var reordered: [BindingProfile] = []
        for id in orderedIDs {
            if let p = _profiles.first(where: { $0.id == id }) {
                reordered.append(p)
            }
        }
        // Append any profiles the caller forgot, so we never silently drop one.
        for p in _profiles where !reordered.contains(where: { $0.id == p.id }) {
            reordered.append(p)
        }
        guard reordered != _profiles else { return }
        objectWillChange.send()
        writeProfiles(reordered, activeID: _activeProfileID)
    }
```

- [ ] **Step 4: Run all HaloCore tests**

Run: `swift test --filter HaloCoreTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/HaloCore/AppPreferences.swift Tests/HaloCoreTests/AppPreferencesProfileTests.swift
git commit -m "feat(core): add profile management API (add/rename/delete/switch/reorder)

Includes self-heal paths (missing active id, deleted active profile)
and a guard against deleting the last profile."
```

---

### Task 5: Settings `Profiles` section + `ProfilesTab` view

**Files:**
- Modify: `Sources/HaloApp/SettingsSidebar.swift` (lines 7-31, 65)
- Modify: `Sources/HaloApp/SettingsWindow.swift` (lines 144-152, plus drop TODO at 157-160)
- Create: `Sources/HaloApp/ProfilesTab.swift`

- [ ] **Step 1: Add `.profiles` case to `SettingsSection`**

In `Sources/HaloApp/SettingsSidebar.swift`, replace the enum + extensions (lines 7-58):

```swift
enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case apps
    case profiles
    case whitelist
    case about

    var id: String { rawValue }

    var localizedTitle: LocalizedStringKey {
        switch self {
        case .general:   return "General"
        case .apps:      return "Apps"
        case .profiles:  return "Profiles"
        case .whitelist: return "Whitelist"
        case .about:     return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general:   return "gearshape.fill"
        case .apps:      return "square.grid.2x2.fill"
        case .profiles:  return "square.stack.3d.up.fill"
        case .whitelist: return "shield.fill"
        case .about:     return "info.circle.fill"
        }
    }

    var tileGradient: LinearGradient {
        let colors: [Color]
        switch self {
        case .general:
            colors = [Color(red: 0.56, green: 0.56, blue: 0.58),
                      Color(red: 0.39, green: 0.39, blue: 0.40)]
        case .apps:
            colors = [Color(red: 0.04, green: 0.52, blue: 1.00),
                      Color(red: 0.37, green: 0.36, blue: 0.90)]
        case .profiles:
            colors = [Color(red: 0.55, green: 0.36, blue: 0.96),
                      Color(red: 0.30, green: 0.22, blue: 0.80)]
        case .whitelist:
            colors = [Color(red: 0.19, green: 0.82, blue: 0.35),
                      Color(red: 0.20, green: 0.78, blue: 0.35)]
        case .about:
            colors = [Color(red: 0.39, green: 0.82, blue: 1.00),
                      Color(red: 0.04, green: 0.52, blue: 1.00)]
        }
        return LinearGradient(
            gradient: Gradient(colors: colors),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
```

Update the `ForEach` in `SettingsSidebar.body` (was line 65) to include `.profiles`:

```swift
            ForEach([SettingsSection.general, .apps, .profiles, .whitelist], id: \.id) { section in
                row(section)
            }
```

- [ ] **Step 2: Route the new section in `SettingsRootView.content`**

In `Sources/HaloApp/SettingsWindow.swift`, update the switch (was at lines 145-152):

```swift
    @ViewBuilder
    private var content: some View {
        switch selection {
        case .general:   GeneralTab(prefs: prefs)
        case .apps:      AppsTab(prefs: prefs)
        case .profiles:  ProfilesTab(prefs: prefs)
        case .whitelist: WhitelistTab(prefs: prefs)
        case .about:     AboutTab()
        }
    }
```

Delete the TODO comment block at lines 157-160 (the one starting `// TODO: Apps 布局支持多 profile`). Replace `Text("Default binding")` at line 222 with `Text(prefs.activeProfile.name)`.

- [ ] **Step 3: Build the `ProfilesTab` view**

Create `Sources/HaloApp/ProfilesTab.swift`:

```swift
import SwiftUI
import HaloCore

struct ProfilesTab: View {
    @ObservedObject var prefs: AppPreferences
    @State private var renamingID: UUID?
    @State private var renameDraft: String = ""
    @State private var newSheetVisible = false
    @State private var newName: String = ""
    @State private var newCloneActive = true
    @State private var deletingID: UUID?

    var body: some View {
        Form {
            header
            Section {
                ForEach(prefs.profiles, id: \.id) { profile in
                    row(profile)
                }
                .onMove { source, destination in
                    var ids = prefs.profiles.map { $0.id }
                    ids.move(fromOffsets: source, toOffset: destination)
                    prefs.reorderProfiles(ids)
                }
            } header: {
                Text("Profiles bundle pins, slot count, ranking model, identity colours and whitelist. Switching a profile re-snaps the wheel.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            Section {
                Button {
                    newName = "Profile \(prefs.profiles.count + 1)"
                    newCloneActive = true
                    newSheetVisible = true
                } label: {
                    Label("New profile…", systemImage: "plus.circle")
                }
            }
        }
        .compatGroupedFormStyle()
        .sheet(isPresented: $newSheetVisible) {
            newProfileSheet
        }
        .alert(
            "Delete profile?",
            isPresented: Binding(
                get: { deletingID != nil },
                set: { if !$0 { deletingID = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { deletingID = nil }
            Button("Delete", role: .destructive) {
                if let id = deletingID { prefs.deleteProfile(id) }
                deletingID = nil
            }
        } message: {
            Text("Pins, identity colours and whitelist for this profile will be removed. Global settings (hotkey, layout, language) are unaffected.")
        }
    }

    // MARK: - Header

    private var header: some View {
        Section {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.accentColor.opacity(0.18))
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Active profile")
                        .font(.headline)
                    Text(prefs.activeProfile.name)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func row(_ profile: BindingProfile) -> some View {
        let isActive = profile.id == prefs.activeProfileID

        HStack(spacing: 10) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .frame(width: 16)

            if renamingID == profile.id {
                TextField("Name", text: $renameDraft, onCommit: {
                    let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        prefs.renameProfile(profile.id, to: trimmed)
                    }
                    renamingID = nil
                })
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
            } else {
                Text(profile.name)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                    .onTapGesture(count: 2) {
                        renameDraft = profile.name
                        renamingID = profile.id
                    }
            }

            Spacer()

            Text("\(profile.slotCount) slots")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(profile.rankingProfile.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(profile.pinnedBundleIDs.compactMap{$0}.count) pinned")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Menu {
                if !isActive {
                    Button("Make active") { prefs.switchToProfile(profile.id) }
                }
                Button("Rename…") {
                    renameDraft = profile.name
                    renamingID = profile.id
                }
                Button("Duplicate") {
                    _ = prefs.addProfile(name: "\(profile.name) copy",
                                        cloning: profile.id)
                }
                Divider()
                Button("Delete", role: .destructive) {
                    deletingID = profile.id
                }
                .disabled(prefs.profiles.count <= 1)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 32)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isActive { prefs.switchToProfile(profile.id) }
        }
    }

    // MARK: - New profile sheet

    private var newProfileSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New profile").font(.headline)

            TextField("Name", text: $newName)
                .textFieldStyle(.roundedBorder)

            Picker("Start from", selection: $newCloneActive) {
                Text("Blank").tag(false)
                Text("Clone of \(prefs.activeProfile.name)").tag(true)
            }
            .pickerStyle(.segmented)

            HStack {
                Spacer()
                Button("Cancel") { newSheetVisible = false }
                Button("Create") {
                    let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    _ = prefs.addProfile(
                        name: trimmed,
                        cloning: newCloneActive ? prefs.activeProfileID : nil
                    )
                    newSheetVisible = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}

private extension FrequencyProfile {
    var displayName: String {
        switch self {
        case .mfuOnly:  return "MFU"
        case .balanced: return "Balanced"
        case .mruOnly:  return "MRU"
        }
    }
}
```

- [ ] **Step 4: Build to verify the view compiles**

Run: `make build`
Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Sources/HaloApp/SettingsSidebar.swift Sources/HaloApp/SettingsWindow.swift Sources/HaloApp/ProfilesTab.swift
git commit -m "feat(settings): add Profiles section + ProfilesTab view

List with reorder / rename / duplicate / delete / activate.
Drops the multi-profile TODO comment in SettingsWindow."
```

---

### Task 6: Active-profile picker in the Settings sidebar header

**Files:**
- Modify: `Sources/HaloApp/SettingsWindow.swift` (`nativeSplit` and `legacySplit` builders)
- Modify: `Sources/HaloApp/SettingsSidebar.swift` (add picker above the rows in the legacy path)

- [ ] **Step 1: Add picker view to `SettingsRootView`**

In `Sources/HaloApp/SettingsWindow.swift`, insert this `ActiveProfilePicker` view just after the closing `}` of `SettingsRootView`:

```swift
/// Compact picker that swaps the active profile from any Settings tab.
/// Placed at the top of the sidebar so the user sees the current scope
/// from every tab; switching causes General / Apps / Whitelist to
/// re-render against the new profile's values.
struct ActiveProfilePicker: View {
    @ObservedObject var prefs: AppPreferences

    var body: some View {
        Picker(selection: Binding(
            get: { prefs.activeProfileID },
            set: { prefs.switchToProfile($0) }
        )) {
            ForEach(prefs.profiles, id: \.id) { p in
                Text(p.name).tag(p.id)
            }
        } label: {
            Label("Profile", systemImage: "square.stack.3d.up.fill")
                .labelStyle(.iconOnly)
        }
        .pickerStyle(.menu)
        .controlSize(.small)
    }
}
```

In `SettingsRootView.nativeSplit`, wrap the sidebar `List(...)` in a `VStack(alignment: .leading, spacing: 0)` with the picker on top:

```swift
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    ActiveProfilePicker(prefs: prefs)
                    Text(prefs.activeProfile.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

                List(SettingsSection.allCases, selection: $selection) { section in
                    Label {
                        Text(section.localizedTitle)
                    } icon: {
                        Image(systemName: section.systemImage)
                            .foregroundStyle(.tint)
                    }
                    .tag(section)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            content
                .frame(minWidth: 560)
        }
```

- [ ] **Step 2: Add picker to the legacy sidebar**

In `Sources/HaloApp/SettingsSidebar.swift`, change `SettingsSidebar` to accept prefs and render a picker at the top. Replace its declaration:

```swift
struct SettingsSidebar: View {
    @Binding var selection: SettingsSection
    @ObservedObject var prefs: AppPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                ActiveProfilePicker(prefs: prefs)
                Text(prefs.activeProfile.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 8)

            ForEach([SettingsSection.general, .apps, .profiles, .whitelist], id: \.id) { section in
                row(section)
            }
            Divider().padding(.vertical, 6).padding(.horizontal, 6)
            row(.about)
            Spacer(minLength: 0)
            Text("Halo v\(Halo.version)")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .frame(width: 220, alignment: .leading)
        .background(sidebarBackground)
    }
    // sidebarBackground, row(_:) unchanged
```

Update the `legacySplit` call site in `SettingsRootView` to pass `prefs`:

```swift
    @ViewBuilder
    private var legacySplit: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $selection, prefs: prefs)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 740, height: 620)
    }
```

- [ ] **Step 3: Build + open Settings to eyeball the picker**

Run: `make app && open dist/Halo.app`
Expected: Settings → sidebar shows the picker with "Default"; switching is wired (no other profiles to switch to yet — verify after Task 7 manual QA).

- [ ] **Step 4: Commit**

```bash
git add Sources/HaloApp/SettingsWindow.swift Sources/HaloApp/SettingsSidebar.swift
git commit -m "feat(settings): active-profile picker in sidebar header

Visible from every Settings tab; switching re-renders General /
Apps / Whitelist against the new profile's projection."
```

---

### Task 7: Per-profile chip on the two General-tab rows

The General tab today mixes global ergonomics (hotkey, layout, sound, language) with two per-profile knobs (slot count, frequency profile). Add a small chip next to those two rows so users notice that those values are scoped to the active profile.

**Files:**
- Modify: `Sources/HaloApp/GeneralSettingsTab.swift` (the two slider/picker rows around line 31 and line 48; and their `legacy` mirrors around line 273 and line 288)

- [ ] **Step 1: Add a `ProfileScopeChip` private view**

At the bottom of `Sources/HaloApp/GeneralSettingsTab.swift` (above the last `}`), add:

```swift
private struct ProfileScopeChip: View {
    let profileName: String
    var body: some View {
        Text(profileName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
            .foregroundStyle(Color.accentColor)
            .help("This setting is scoped to the active profile.")
    }
}
```

- [ ] **Step 2: Place the chip next to slot count + frequency rows**

Around the `Picker("Slot count", …)` block (line 31 area), wrap its row label:

```swift
                HStack {
                    Text("Slot count")
                    ProfileScopeChip(profileName: prefs.activeProfile.name)
                }
                Picker(selection: …) { … } label: { EmptyView() }
```

Do the same for the `Picker("Frequency profile", …)` block (line 48 area) and the two legacy mirrors (lines ~273 and ~288). If the existing layout uses `Picker("Slot count", selection: …)` directly with an inline label, change it to the explicit `Picker(selection: …) { … } label: { HStack { Text("Slot count"); ProfileScopeChip(…) } }` shape so the chip can sit beside the label.

- [ ] **Step 3: Build + open Settings**

Run: `make app && open dist/Halo.app`
Expected: General tab shows "Default" chip on Slot count and Frequency profile rows. Add a second profile via Profiles tab, switch to it, the chips update.

- [ ] **Step 4: Commit**

```bash
git add Sources/HaloApp/GeneralSettingsTab.swift
git commit -m "feat(settings): chip on General rows scoped to the active profile

Slot count + frequency profile show a small profile-name chip so
users notice those rows scope to the active profile."
```

---

### Task 8: Menu-bar `Profile` submenu

**Files:**
- Modify: `Sources/HaloUI/MenuBarController.swift`
- Modify: `Sources/HaloApp/AppDelegate.swift`

- [ ] **Step 1: Extend MenuBarController callbacks + dynamic submenu**

Replace the entirety of `Sources/HaloUI/MenuBarController.swift` with:

```swift
import AppKit

@MainActor
public final class MenuBarController {
    public let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let profileMenu = NSMenu()
    private let profileItem: NSMenuItem
    private let menuBox: MenuBox

    public init(onSummon: @escaping () -> Void,
                onSettings: @escaping () -> Void,
                onProfileList: @escaping () -> [(id: UUID, name: String, isActive: Bool)],
                onProfileSelect: @escaping (UUID) -> Void,
                onEditProfiles: @escaping () -> Void,
                onQuit: @escaping () -> Void)
    {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "circle.dashed.inset.filled",
                                   accessibilityDescription: "Halo")
            button.image?.isTemplate = true
        }

        let box = MenuBox(
            onSummon: onSummon,
            onSettings: onSettings,
            onProfileList: onProfileList,
            onProfileSelect: onProfileSelect,
            onEditProfiles: onEditProfiles,
            onQuit: onQuit
        )
        menuBox = box

        let summon = NSMenuItem(title: "Summon Halo",
                                action: #selector(MenuBox.fire(_:)),
                                keyEquivalent: "")
        summon.target = box
        summon.representedObject = HaloMenuAction.summon

        profileItem = NSMenuItem(title: "Profile", action: nil, keyEquivalent: "")
        profileItem.submenu = profileMenu
        profileMenu.delegate = box

        let settings = NSMenuItem(title: "Settings…",
                                  action: #selector(MenuBox.fire(_:)),
                                  keyEquivalent: ",")
        settings.target = box
        settings.representedObject = HaloMenuAction.settings

        let quit = NSMenuItem(title: "Quit Halo",
                              action: #selector(MenuBox.fire(_:)),
                              keyEquivalent: "q")
        quit.target = box
        quit.representedObject = HaloMenuAction.quit

        menu.addItem(summon)
        menu.addItem(.separator())
        menu.addItem(profileItem)
        menu.addItem(.separator())
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(quit)
        statusItem.menu = menu
    }
}

private enum HaloMenuAction {
    case summon, settings, quit, editProfiles
}

@MainActor
private final class MenuBox: NSObject, NSMenuDelegate {
    let onSummon: () -> Void
    let onSettings: () -> Void
    let onProfileList: () -> [(id: UUID, name: String, isActive: Bool)]
    let onProfileSelect: (UUID) -> Void
    let onEditProfiles: () -> Void
    let onQuit: () -> Void

    init(onSummon: @escaping () -> Void,
         onSettings: @escaping () -> Void,
         onProfileList: @escaping () -> [(id: UUID, name: String, isActive: Bool)],
         onProfileSelect: @escaping (UUID) -> Void,
         onEditProfiles: @escaping () -> Void,
         onQuit: @escaping () -> Void)
    {
        self.onSummon = onSummon
        self.onSettings = onSettings
        self.onProfileList = onProfileList
        self.onProfileSelect = onProfileSelect
        self.onEditProfiles = onEditProfiles
        self.onQuit = onQuit
    }

    @objc func fire(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? HaloMenuAction else { return }
        switch action {
        case .summon: onSummon()
        case .settings: onSettings()
        case .editProfiles: onEditProfiles()
        case .quit: onQuit()
        }
    }

    @objc func fireProfile(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        onProfileSelect(id)
    }

    // Repopulate the profile submenu the moment AppKit is about to show it.
    nonisolated func menuWillOpen(_ menu: NSMenu) {
        MainActor.assumeIsolated { rebuildProfileMenu(menu) }
    }

    private func rebuildProfileMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        for entry in onProfileList() {
            let item = NSMenuItem(title: entry.name,
                                  action: #selector(MenuBox.fireProfile(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = entry.id
            item.state = entry.isActive ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let edit = NSMenuItem(title: "Edit Profiles…",
                              action: #selector(MenuBox.fire(_:)),
                              keyEquivalent: "")
        edit.target = self
        edit.representedObject = HaloMenuAction.editProfiles
        menu.addItem(edit)
    }
}
```

- [ ] **Step 2: Wire the new callbacks in AppDelegate**

In `Sources/HaloApp/AppDelegate.swift`, replace the existing `MenuBarController(…)` construction (around lines 48-52):

```swift
        menuBar = MenuBarController(
            onSummon: { [weak self] in self?.summonFromMenu() },
            onSettings: { [weak self] in self?.openSettings() },
            onProfileList: { [weak self] in
                guard let self = self else { return [] }
                return self.prefs.profiles.map {
                    (id: $0.id, name: $0.name, isActive: $0.id == self.prefs.activeProfileID)
                }
            },
            onProfileSelect: { [weak self] id in
                self?.prefs.switchToProfile(id)
            },
            onEditProfiles: { [weak self] in
                self?.openSettings(selecting: .profiles)
            },
            onQuit: { NSApp.terminate(nil) }
        )
```

Extend `openSettings()` (around line 395) to accept an optional section:

```swift
    func openSettings(selecting section: SettingsSection? = nil) {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(prefs: prefs)
        }
        settingsWindowController?.show(selecting: section)
    }
```

In `Sources/HaloApp/SettingsWindow.swift`, extend `SettingsWindowController`:

```swift
    private var pendingSection: SettingsSection?

    func show(selecting section: SettingsSection? = nil) {
        pendingSection = section
        let host = NSHostingController(
            rootView: SettingsRootView(prefs: prefs, initialSection: section)
        )
        window.contentViewController = host
        NSApp.setActivationPolicy(.regular)
        centerOnCurrentScreen()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        WindowCloseObserver.attach(window: window) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
```

…and add `initialSection` to `SettingsRootView`:

```swift
struct SettingsRootView: View {
    @ObservedObject var prefs: AppPreferences
    @State private var selection: SettingsSection

    init(prefs: AppPreferences, initialSection: SettingsSection? = nil) {
        self.prefs = prefs
        self._selection = State(initialValue: initialSection ?? .general)
    }
    // … rest unchanged
}
```

- [ ] **Step 3: Build + walk the menu**

Run: `make app && open dist/Halo.app`
Expected: clicking the menu-bar icon shows the Profile submenu. With only "Default" it shows one checked item + "Edit Profiles…". Clicking Edit Profiles opens Settings on the Profiles section.

- [ ] **Step 4: Commit**

```bash
git add Sources/HaloUI/MenuBarController.swift Sources/HaloApp/AppDelegate.swift Sources/HaloApp/SettingsWindow.swift
git commit -m "feat(menubar): Profile submenu + Edit Profiles route

Submenu repopulates on menuWillOpen so it always reflects current
profiles. Edit Profiles opens Settings directly on the Profiles tab."
```

---

### Task 9: Localizable strings + version bump

**Files:**
- Modify: `Resources/Localizable.strings` (en) — add new keys
- Modify: `Resources/zh-Hans.lproj/Localizable.strings` — Chinese translations
- Modify: `Resources/Info.plist` — bump `CFBundleShortVersionString` to `1.2.0`
- Modify: `CHANGELOG.md` — v1.2.0 entry

- [ ] **Step 1: Add English strings**

Read `Resources/*.lproj/Localizable.strings` to find the existing pattern, then append a Profiles block:

```
/* Profiles tab */
"Profiles" = "Profiles";
"Active profile" = "Active profile";
"Profiles bundle pins, slot count, ranking model, identity colours and whitelist. Switching a profile re-snaps the wheel." =
  "Profiles bundle pins, slot count, ranking model, identity colours and whitelist. Switching a profile re-snaps the wheel.";
"New profile…" = "New profile…";
"New profile" = "New profile";
"Start from" = "Start from";
"Blank" = "Blank";
"Clone of %@" = "Clone of %@";
"Make active" = "Make active";
"Rename…" = "Rename…";
"Duplicate" = "Duplicate";
"Delete profile?" = "Delete profile?";
"Pins, identity colours and whitelist for this profile will be removed. Global settings (hotkey, layout, language) are unaffected." =
  "Pins, identity colours and whitelist for this profile will be removed. Global settings (hotkey, layout, language) are unaffected.";
"This setting is scoped to the active profile." = "This setting is scoped to the active profile.";
"Profile" = "Profile";
"Edit Profiles…" = "Edit Profiles…";
```

- [ ] **Step 2: Add Chinese strings**

In `Resources/zh-Hans.lproj/Localizable.strings`, mirror the keys with Chinese values:

```
"Profiles" = "场景环";
"Active profile" = "当前场景";
"Profiles bundle pins, slot count, ranking model, identity colours and whitelist. Switching a profile re-snaps the wheel." =
  "场景环打包固定槽位、槽位数、排序模型、身份色与白名单。切换场景后轮盘会自动重排。";
"New profile…" = "新建场景…";
"New profile" = "新建场景";
"Start from" = "起点";
"Blank" = "空白";
"Clone of %@" = "复制 %@";
"Make active" = "切换为当前";
"Rename…" = "重命名…";
"Duplicate" = "复制";
"Delete profile?" = "删除该场景？";
"Pins, identity colours and whitelist for this profile will be removed. Global settings (hotkey, layout, language) are unaffected." =
  "该场景的固定槽位、身份色和白名单将被移除。全局设置（热键、布局、语言）不会受影响。";
"This setting is scoped to the active profile." = "此项仅作用于当前场景。";
"Profile" = "场景";
"Edit Profiles…" = "管理场景…";
```

- [ ] **Step 3: Bump version**

In `Resources/Info.plist`, find the `<key>CFBundleShortVersionString</key>` value (currently `1.1.2`) and change to `1.2.0`. Bump `CFBundleVersion` by 1.

- [ ] **Step 4: CHANGELOG entry**

In `CHANGELOG.md`, insert above the v1.1.2 entry:

```markdown
## v1.2 (2026-05-14) — 多 Profile / 场景环

- New: named Binding Profiles (Default / Coding / Meeting / …) bundle pins,
  slot count, ranking model, identity colours and whitelist. Switch
  between them from the menu bar's Profile submenu or the Settings →
  Profiles tab.
- Migration is automatic: existing users see all their prior bindings
  under a single "Default" profile. Legacy `UserDefaults` keys are
  kept as a rollback safety net through v1.2 and removed in v1.3.
- Global ergonomics (hotkey, layout, language, sound, autostart) stay
  user-wide and do not switch with the profile.
```

- [ ] **Step 5: Build**

Run: `make build`
Expected: PASS, no warnings about missing strings.

- [ ] **Step 6: Commit**

```bash
git add Resources/Localizable.strings Resources/zh-Hans.lproj/Localizable.strings Resources/Info.plist CHANGELOG.md
git commit -m "chore(release): v1.2.0 — multi-profile / 场景环 strings + version"
```

(If `Resources/Localizable.strings` is actually at `Resources/en.lproj/Localizable.strings`, adjust the path. The repo layout in README says `Resources/*.lproj/Localizable.strings (en + zh-Hans)`.)

---

### Task 10: Manual QA walkthrough

This task enforces the project memory rule (`feedback_test_build_open.md`): build the .app and exercise it before declaring done.

- [ ] **Step 1: Build the release app**

Run: `make app`
Expected: `dist/Halo.app` written, ad-hoc signed.

- [ ] **Step 2: Launch**

Run: `open dist/Halo.app`

Verify Halo's menu-bar icon appears.

- [ ] **Step 3: Upgrade-in-place sanity**

Skip this step if running on a clean test account. Otherwise: in the running app, open Settings → Profiles. Confirm exactly one "Default" profile is present and its slot count + pin count match what the user had before.

- [ ] **Step 4: Walk the matrix**

For each scenario, record outcome inline:

1. Settings → Profiles → New → "Coding", Start from = Clone of Default. Profile appears. ✓ / ✗
2. Switch to Coding (click the row or menu-bar Profile → Coding). Apps tab pins reflect Coding's clone. ✓ / ✗
3. Apps tab: remove one pin while in Coding. Switch to Default. The pin is still there. ✓ / ✗
4. Profiles: set Coding's slot count to 12 via General tab while Coding active. Switch to Default. Default is still 8. ✓ / ✗
5. Add Steam to whitelist while in a new "Gaming" profile. Switch to Default. Halo chord still fires when Steam is frontmost. ✓ / ✗
6. Settings → Profiles → delete Coding. Falls back to first remaining. No crash. ✓ / ✗
7. Try to delete the last remaining profile. Delete option is disabled. ✓ / ✗
8. Summon Halo, switch profile from the menu bar, re-summon. New pins. ✓ / ✗
9. Quit Halo, relaunch. Active profile + all profiles persisted. ✓ / ✗
10. Settings → General → slot count chip shows the active profile name. ✓ / ✗

- [ ] **Step 5: If any scenario fails, file fix-up tasks**

For each failure, write a TaskCreate entry naming the symptom + suspected file. Don't proceed to Task 11 until all scenarios are green.

- [ ] **Step 6: Commit (only if QA produced ad-hoc fixes)**

```bash
git add <touched files>
git commit -m "fix: QA round 1 follow-ups (see plan task 10)"
```

---

### Task 11: PR + handoff

**Files:**
- None (git only)

- [ ] **Step 1: Push the branch**

Run: `git push -u origin worktree-multi-profile`

- [ ] **Step 2: Open PR with a self-contained body**

Run:

```bash
gh pr create --title "Multi-Profile / 场景环 v1" --body "$(cat <<'EOF'
## Summary
- Adds named Binding Profiles (Default / Coding / Meeting / …) bundling pins, slot count, ranking, identity colours and whitelist.
- Switch from the menu bar's Profile submenu or Settings → Profiles.
- Hotkey, layout, language, sound and autostart stay global.
- Automatic migration: existing users see their prior bindings under a single "Default" profile.

## Spec
docs/superpowers/specs/2026-05-14-multi-profile-design.md

## Test plan
- [x] swift test (HaloCoreTests, HaloUITests)
- [x] Manual QA matrix in plan Task 10 — all 10 scenarios green
- [x] Upgrade-in-place against a v1.1.2 prefs domain — Default profile populated with prior pins
- [x] Both nativeSplit (macOS 13+) and legacySplit (macOS 12) Settings paths visually checked

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: Hand back to the user**

Print the PR URL and exit. Do not auto-merge; the user reviews.

---

## Self-Review (post-write checklist)

Spec coverage:
- §1 Goal — covered by Tasks 1-8.
- §2 Non-goals — observed: no auto-detect, no profile hotkey, no sync, no per-profile global controls, no export format.
- §3 Per-profile vs global table — Task 2 / 3 (read + write projection) + Task 7 chip.
- §4.1 BindingProfile — Task 1.
- §4.2 AppPreferences projection — Tasks 2 + 3.
- §4.2 Management API — Task 4.
- §4.3 Storage keys — Tasks 2 (write `profiles.v1` + `activeProfileID`; leave legacy keys read-only).
- §4.4 Migration — Task 2 step 3.
- §4.5 Engine integration — unchanged code paths; Task 8 picks up `recomputeSlots` via `objectWillChange`.
- §5.1 Profiles section — Task 5.
- §5.2 Sidebar picker — Task 6.
- §5.3 Menu bar — Task 8.
- §5.4 Onboarding unchanged — explicitly no task.
- §6 Edge cases — Task 4 (delete-active, delete-last, missing-active-id self-heal).
- §7.1 Unit tests — Tasks 1, 2, 3, 4.
- §7.2 UI tests — explicitly noted as no-op for v1.
- §7.3 Manual QA — Task 10.
- §7.4 Release / changelog — Task 9.
- §8 Open follow-ups — unchanged.

Placeholders: none. Code shown in every step.

Type consistency: `addProfile(name:cloning:)` signature is identical across the test, implementation, and call sites. `switchToProfile(_:)`, `renameProfile(_:to:)`, `deleteProfile(_:)`, `reorderProfiles(_:)` likewise. `BindingProfile.resizing(slotCount:)` is the only resize entry point and is referenced by exactly that name.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-14-multi-profile.md`. Two execution options:

**1. Subagent-Driven (recommended)** — Fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
