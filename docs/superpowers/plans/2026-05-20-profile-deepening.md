# v1.3.0 — Profile Deepening Implementation Plan

> **Scope decision (2026-05-20):** Scope B from the /think proposal —
> finish the per-profile UI handoff for `slotCount` + `tint`, lower
> `frequencyProfile` into `BindingProfile`, plus the two §9 follow-ups
> (color dot + reorder) and the legacy-key cleanup.
>
> This reverses one decision from `2026-05-14-multi-profile-design.md`
> §3: `frequencyProfile` was global; it becomes per-profile. That spec
> must be updated as part of this work (Task 8).

**Goal:** Make a Profile feel like a full *scene*, not just a pin
bundle. Each Profile owns its own slot count, ranking strategy, ambient
tint, and identity-colour overrides — switchable from the Apps tab pill
bar. Other globals (hotkey, layout, whitelist, language, sound) stay
user-global.

**Reference design:** `docs/superpowers/specs/2026-05-14-multi-profile-design.md`
(to be amended; see Task 8). New ambient-tint and per-profile ranking
behaviour lifted from `docs/BRAINSTORM.md` §"场景环 Profiles".

---

## What changes

| Concern                            | v1.2.1 state | v1.3.0 state |
|------------------------------------|:------------:|:------------:|
| Pinned slots                       | per-profile  | per-profile |
| Overflow pins                      | per-profile  | per-profile |
| Identity-color overrides           | per-profile  | per-profile |
| Slot count                         | per-profile (data) / **global UI** | per-profile (data + UI) |
| Ambient tint                       | per-profile (data) / **no UI** | per-profile (data + UI) |
| **Frequency profile**              | **global**   | **per-profile** |
| Profile pill color dot             | —            | derived from tint |
| Pill drag-to-reorder               | —            | yes |
| Whitelist / hotkey / layout / etc. | global       | global (unchanged) |

---

## File structure

**Create:**
- `Tests/HaloCoreTests/BindingProfileFrequencyTests.swift`

**Modify:**
- `Sources/HaloCore/BindingProfile.swift` — add `frequencyProfile: FrequencyProfile` field with `decodeIfPresent` fallback in custom decoder.
- `Sources/HaloCore/AppPreferences.swift` — project `frequencyProfile` from active profile, add `setFrequencyProfile(_:for:)` and `reorderProfile(_:to:)` APIs, drop legacy read paths for `pinnedSlots.v1` / `overflowPins.v1` / `identityOverride.v1` (keep the one-shot `migrateLegacyKeysIntoDefaultProfile` path so v1.0 → v1.3.0 jumps still work).
- `Sources/HaloApp/ProfileBar.swift` — color dot per pill, drag-to-reorder, anchor for slot count + tint + frequency controls.
- `Sources/HaloApp/SettingsWindow.swift::AppsTab` — insert slot count slider, tint picker, frequency picker into the section that already hosts `ProfileBar`.
- `Sources/HaloApp/GeneralSettingsTab.swift` — remove the slot count slider and the frequency picker from this tab; add a one-line read-only label that says "Per profile — set under Apps" with a link that activates the Apps tab.
- `Tests/HaloCoreTests/AppPreferencesProfileTests.swift` — extend with frequency + reorder + drop-legacy coverage.
- `Resources/en.lproj/Localizable.strings` + `zh-Hans.lproj/Localizable.strings` — new keys (≈ 7 each).
- `Resources/Info.plist` — `CFBundleShortVersionString` → `1.3.0`, bump `CFBundleVersion`.
- `Sources/HaloCore/HaloCore.swift` — `Halo.version` → `1.3.0`.
- `CHANGELOG.md` — graduate Unreleased section.
- `docs/superpowers/specs/2026-05-14-multi-profile-design.md` — annotate §3 table that `frequencyProfile` moved per-profile in v1.3.0, with rationale.

**Do NOT touch:**
- `Sources/HaloApp/WhitelistTab.swift` — whitelist stays global this release.
- `Sources/HaloUI/HaloHotkey.swift` / `DoubleTapMonitor.swift` — triggers stay global.
- `Sources/HaloUI/MenuBarController.swift` — menu bar gets no new affordances.
- Anything under `Sources/HaloCore/HaloEngine.swift` / `Switcher.swift` / `UsageStore.swift`.
- `Sources/HaloUI/HaloGridWindow.swift` — ALL grid unaffected; it reads usage scores, not `frequencyProfile`.

---

## Task 1: `BindingProfile.frequencyProfile`

Add a `frequencyProfile: FrequencyProfile` field, default `.balanced`.

```swift
public struct BindingProfile: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    public var pinnedBundleIDs: [String?]
    public var overflowPinnedBundleIDs: [String]
    public var identityOverrides: [String: IdentityColor]
    public var slotCount: Int
    public var tint: IdentityColor?
    public var frequencyProfile: FrequencyProfile   // NEW
    // …
}
```

- Init parameter is optional with default `.balanced` so existing
  callers (`freshDefault`, clones) keep working unchanged.
- Custom `init(from:)`: `decodeIfPresent(FrequencyProfile.self, forKey: .frequencyProfile)`
  falls back to `.balanced` so v1.2 plists still load. The
  `AppPreferences` migration path (Task 2) overwrites the fallback
  with the legacy global key value so users don't silently lose their
  ranking choice.
- `Equatable` synthesis covers the new field.

**Test:** `BindingProfileFrequencyTests.swift`
- Round-trip Codable: encode, decode, equal.
- Plist without `frequencyProfile` decodes with `.balanced`.
- Clones inherit `frequencyProfile`.

## Task 2: `AppPreferences` projection + frequency migration

```swift
public var frequencyProfile: FrequencyProfile {
    get {
        if _profilesLoaded {
            return activeProfile.frequencyProfile
        }
        let raw = defaults.string(forKey: Keys.profile) ?? FrequencyProfile.balanced.rawValue
        return FrequencyProfile(rawValue: raw) ?? .balanced
    }
    set {
        guard newValue != frequencyProfile else { return }
        objectWillChange.send()
        // Mirror to legacy global key for v1.2 rollback safety, same
        // pattern slotCount uses.
        defaults.set(newValue.rawValue, forKey: Keys.profile)
        updateActiveProfile { profile in
            profile.frequencyProfile = newValue
        }
    }
}

public func setFrequencyProfile(_ profile: FrequencyProfile, for profileID: UUID) {
    loadProfilesIfNeeded()
    guard let idx = _profiles.firstIndex(where: { $0.id == profileID }) else { return }
    guard _profiles[idx].frequencyProfile != profile else { return }
    objectWillChange.send()
    _profiles[idx].frequencyProfile = profile
    if profileID == _activeProfileID {
        defaults.set(profile.rawValue, forKey: Keys.profile)
    }
    writeProfiles(_profiles, activeID: _activeProfileID)
}
```

**Migration backfill** (one-time, runs on first load after upgrade):
- In `loadProfilesIfNeeded`, after decoding profiles from
  `Keys.profilesV1`, check if **any** profile has the explicit
  `frequencyProfile` key present in its decoded JSON. Because the
  custom decoder defaults to `.balanced` when missing, we instead
  detect "this plist was written by ≤ v1.2.x" via a sentinel:
  add a one-time migration flag `halo.prefs.profilesFrequencyMigrated.v1`
  in `UserDefaults`. If absent:
  1. Read legacy `Keys.profile` once.
  2. Overwrite every profile's `frequencyProfile` with that value.
  3. Write profiles back, set the flag.

This avoids the "user had MFU globally, opens v1.3.0, profiles all
silently revert to Balanced" failure mode.

`HaloLog.settings.info` line on migration: how many profiles updated, source value.

## Task 3: `reorderProfile(_:to:)` API

```swift
public func reorderProfile(_ id: UUID, to newIndex: Int) {
    loadProfilesIfNeeded()
    guard let current = _profiles.firstIndex(where: { $0.id == id }) else { return }
    let target = max(0, min(_profiles.count - 1, newIndex))
    guard current != target else { return }
    objectWillChange.send()
    let moved = _profiles.remove(at: current)
    _profiles.insert(moved, at: target)
    writeProfiles(_profiles, activeID: _activeProfileID)
}
```

No active-id change; reordering is pure presentation.

## Task 4: Drop legacy read paths

Spec §9 cutoff: v1.1.2 shipped multi-profile; v1.3.0 is "the minor after the initial release". Stop reading:
- `halo.prefs.pinnedSlots.v1`
- `halo.prefs.overflowPins.v1`
- `halo.prefs.identityOverride.v1`

What stays:
- `migrateLegacyKeysIntoDefaultProfile()` — needed for users who skipped v1.1.x / v1.2.x and jump straight from v1.0.x to v1.3.0.
- The legacy `Keys.slotCount` and `Keys.profile` UserDefaults entries — these are still mirrored on writes (above) for v1.2 rollback safety. Reads from them only fire on cold path before `_profilesLoaded`.

Remove dead code: the projection getters for `pinnedBundleIDs` /
`overflowPinnedBundleIDs` no longer have a "fall back to legacy keys"
branch. Tests must still cover the migration path.

## Task 5: `ProfileBar` — color dot + drag-to-reorder

`Sources/HaloApp/ProfileBar.swift` additions:

**Color dot:**
- 6pt circle inset 4pt to the left of the pill label.
- Color comes from `profile.tint?.swiftUIColor ?? fallbackPalette[profileIndex % palette.count]`.
- Fallback palette = 6 OKLCH-tuned hues (red, amber, green, teal, blue, magenta), defined in `ProfileBar.swift` as a private `static let` of `Color` values.
- When `tint == nil`, dot uses fallback at 60% opacity (signals "unset").

**Drag-to-reorder:**
- Wrap each pill in `.onDrag { NSItemProvider(object: profile.id.uuidString as NSString) }`.
- `.onDrop(of: [UTType.text], delegate: …)` on each pill provides
  insertion logic. The delegate calls `prefs.reorderProfile(_:to:)`.
- Drag affordance: pill scales to 1.04× while being dragged
  (`.scaleEffect(isDragging ? 1.04 : 1)`).
- macOS 12 compat: `.onDrag` / `.onDrop(of:delegate:)` are available
  since macOS 11; no `PlatformCompat` branch needed. Verify with
  `swift build` against `.macOS(.v12)` constraint.

## Task 6: AppsTab — slot count + tint + frequency picker

Layout, top to bottom in the Apps tab:

```
┌─ Apps ─────────────────────────────────────────────┐
│ ProfileBar                                         │
│   [• Default] [• Work] [• Gaming]  [+]    3 profiles │
│                                                    │
│ Profile settings for "{active.name}":              │
│   Slots:   [4 ─●──────── 12]  current: 8           │
│   Tint:    [○○○○○○○○ + no tint]                    │  ← new
│   Ranking: [ MFU | Balanced | MRU ]                │  ← moved from General
│                                                    │
│ (existing binding-card unchanged)                  │
│ (existing BindingWheelView unchanged)              │
│ (existing Hidden Pins section unchanged)           │
└────────────────────────────────────────────────────┘
```

Implementation notes:
- Slot count slider binds via:
  ```swift
  Slider(value: Binding(
    get: { Double(prefs.activeProfile.slotCount) },
    set: { prefs.setSlotCount(Int($0), for: prefs.activeProfileID) }
  ), in: 4...12, step: 1)
  ```
- Tint picker: 8-swatch row from a fixed OKLCH palette + a "✕" no-tint
  cell. Selected swatch has a 2pt outer ring. Selecting writes via
  `prefs.setTint(_:for: prefs.activeProfileID)`.
- Frequency segmented picker: same three-way segmented control that
  General tab used; binds via `prefs.setFrequencyProfile(_:for:)`.
- All three controls observe `prefs.activeProfile.id` for redraw on
  profile switch.

## Task 7: GeneralSettingsTab — remove slot + frequency controls

- Delete the slot count `Slider` row and the frequency `Picker` row.
- Add a single-line `HStack` in their place: `Text("Slots and ranking are per profile — set under Apps")`. On click, posts a `Notification.Name("halo.settings.switchTo")` with payload `"Apps"`; `SettingsWindow` listens and switches sidebar selection. (Reuse the existing sidebar selection binding — see `SettingsSidebar.swift`.)
- The label uses the tertiary text color so it doesn't read as an action button.

## Task 8: Update the multi-profile design spec

Edit `docs/superpowers/specs/2026-05-14-multi-profile-design.md`:

- §3 table: change `Ranking profile (MFU/Balanced/MRU)` row from `Global ✓` to `Per-profile ✓ (since v1.3.0)`.
- §3 rationale paragraph: add one sentence — "Updated in v1.3.0: ranking moved per-profile after observation that users with multiple profiles also wanted distinct ranking strategies (Coding favoured MFU; Personal favoured MRU)."
- §9 "Open follow-ups": tick off `Profile colour / dot`, `Drag-to-reorder pills`, `Drop legacy UserDefaults keys`. Add a note pointing at this plan as the implementation.

This is the only spec amendment. The non-goals list in §2 stays
otherwise intact — whitelist remains global, no hotkey-to-switch, no
auto-detect, no import/export.

## Task 9: Localization

`Resources/en.lproj/Localizable.strings` — append:

```
/* v1.3.0 Profile deepening */
"Profile settings for %@" = "Profile settings for %@";
"Tint" = "Tint";
"No tint" = "No tint";
"Ranking" = "Ranking";
"Slots and ranking are per profile — set under Apps" = "Slots and ranking are per profile — set under Apps";
"Drag profiles to reorder" = "Drag profiles to reorder";
```

`zh-Hans.lproj/Localizable.strings` — append:

```
/* v1.3.0 Profile deepening */
"Profile settings for %@" = "%@ 的设置";
"Tint" = "环境色";
"No tint" = "无";
"Ranking" = "排序方式";
"Slots and ranking are per profile — set under Apps" = "槽位数和排序方式按 Profile 设置，请到 Apps 标签内调整";
"Drag profiles to reorder" = "拖拽排序 Profile";
```

## Task 10: Version + CHANGELOG

- `Resources/Info.plist`: `CFBundleShortVersionString` → `1.3.0`. `CFBundleVersion` → next sequential build number (current 17 → 18).
- `Sources/HaloCore/HaloCore.swift`: `Halo.version = "1.3.0"`.
- `CHANGELOG.md`: graduate Unreleased section. Suggested heading:

```
## [1.3.0] — 2026-05-?? (replace at release-cut time)

### Profile deepening

- Profiles now own **slot count**, **ambient tint**, and **frequency
  ranking** (MFU / Balanced / MRU) per scene. Switching profile
  re-sizes the wheel, re-tints the idle glow, and re-ranks Top-N
  immediately.
- Apps tab gains an in-place editor for the active profile's slot
  count, tint, and ranking. General tab no longer carries those
  three controls; it shows a one-line pointer label instead.
- Profile pills carry a **color dot** derived from the profile's
  tint (or an auto-assigned hue if none is set), so the active
  scene reads at a glance.
- Profile pills are **drag-to-reorder**.
- One-time migration backfills every existing profile's ranking
  from the previous global value; users keep their MFU / MRU
  choice across the upgrade.
- Drops the three legacy v1.0 binding keys
  (`pinnedSlots.v1`, `overflowPins.v1`, `identityOverride.v1`) from
  the read path — they were superseded by `profiles.v1` in v1.1.2.
  Direct v1.0 → v1.3.0 jumps still migrate via the one-shot
  default-profile builder.
```

## Task 11: Build, launch, verify

Per `feedback_test_build_open.md`: `make test && make app && open dist/Halo.app` from this branch's worktree (not `/Applications/Halo.app`).

Walk:

1. **In-place upgrade**: existing profile + pins + slot count load
   intact. `~/Library/Logs/Halo/halo.log` shows the frequency-backfill
   line ("Migrated N profiles to per-profile frequency: balanced" or
   similar).
2. **Slot count is per-profile**: in Apps tab, set Default profile to
   12 slots. Switch to "Work" profile (or create one). Slot count
   independently set to 4. Switching back to Default shows 12 again,
   wheel resnaps live.
3. **Tint flows through**: set Default tint = red. Pill dot turns red.
   Summon the wheel — idle halo glow has a faint red wash. Set tint
   = "No tint". Pill dot reverts to grey fallback, glow goes neutral.
4. **Ranking is per-profile**: set Default = MFU. Set Work = MRU.
   Switch between them, watch the wheel re-rank.
5. **Pill drag**: drag Work pill before Default. Order persists across
   restart (`defaults read com.halo.launcher halo.prefs.profiles.v1`
   shows the new order).
6. **General tab cleanup**: open General — no slot slider, no frequency
   picker. The "set under Apps" hint reads and clicking it switches
   sidebar selection.
7. **Profile delete**: delete a non-active profile. Pill ordering on
   the remaining profiles preserved.
8. **Cold start**: quit and relaunch Halo. Active profile + ordering +
   tint + per-profile slot count + per-profile ranking all persist.
9. **Legacy-jump check**: defaults-delete `halo.prefs.profilesFrequencyMigrated.v1`,
   relaunch; confirm the migration backfill re-runs without
   double-writing values.
10. **Skip-CI commit**: this is a UI-only minor; if the run is locally
    green the commit can carry `[skip ci]` per CLAUDE.md ALWAYS.

---

## Risks & rollback

- **Risk: User loses their global frequency setting after upgrade.**
  Mitigation: explicit backfill (Task 2), one-time migration flag.
  Verification step 1 above confirms.
- **Risk: User looks for the slot slider in General tab and can't find it.**
  Mitigation: the inline pointer label (Task 7). Verification step 6.
- **Risk: Drag-to-reorder lands a profile in an unexpected position on
  macOS 12 (older SwiftUI drop semantics).**
  Mitigation: clamp `newIndex` in `reorderProfile`. Test on macOS 12
  VM before release-cut (note: project's CI is macos-26 only, so
  manual check matters).
- **Risk: `frequencyProfile` migration runs twice and overwrites a
  user's deliberate per-profile setting.**
  Mitigation: the `halo.prefs.profilesFrequencyMigrated.v1` sentinel
  flag. Once set, never overwrites.
- **Rollback**: this is data-additive. Existing `BindingProfile`
  decoder falls back to `.balanced` on missing key — v1.2.x can read
  v1.3.0 plists without crashing, but profiles will all show
  `.balanced` ranking (the legacy global key is still mirrored, so the
  *active* profile's ranking is preserved on rollback). UI revert =
  revert `AppsTab` + `GeneralSettingsTab` edits.

---

## Self-review

- **Spec coverage**: §3 table reversal (Task 8) is the only behavioural-spec
  change. Everything else is implementation of fields the data layer
  already carries.
- **Placeholders**: none. Migration sentinel, fallback palette, drag
  delegate, slider binding — all concrete.
- **Type consistency**: `setSlotCount(_:for:)`, `setTint(_:for:)`,
  `setFrequencyProfile(_:for:)`, `reorderProfile(_:to:)` — same shape,
  consistent naming.
- **Boundary check**: WhitelistTab / HaloHotkey / MenuBarController /
  HaloEngine all in the `do-not-touch` list. If a task drags in any of
  them, stop and escalate.
- **Verification owner**: implementer runs `make test && make app &&
  open dist/Halo.app` per CLAUDE.md Workflow §3, walks Task 11 list,
  pastes results.
- **CI**: `[skip ci]` allowed for the final UI-polish commit; the
  first commit on this branch (data + tests) should run CI.
