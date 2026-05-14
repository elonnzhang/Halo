# Halo 多 Profile / 场景环 — Design Spec

- **Date:** 2026-05-14
- **Target release:** v1.2.0 (additive feature, no behavior change for non-users)
- **Author:** session 多profile
- **Status:** Draft — awaiting user review

## 1. Goal

Let users keep multiple named bundles of Halo bindings ("场景环 Profiles")
— e.g. `Default`, `Coding`, `Meeting`, `Writing` — and switch between them
manually from the menu bar or Settings. Each profile owns its own pins,
slot count, ranking model, identity-color overrides and whitelist. The
hotkey, layout, language, sound and other ergonomics stay global.

This is the v1 of the brainstorm's #1 candidate (`docs/BRAINSTORM.md →
场景环 Profiles`). The "minimum: profile list + clone-current" target from
that doc is met; auto-switching by front-most app is explicitly out of
scope and deferred to v1.x.

## 2. Non-goals (v1)

- No auto-detection of active profile from the frontmost app.
- No hotkey to switch profile (menu bar + settings only).
- No iCloud / sync of profiles across machines.
- No per-profile sound, hotkey, layout, language, autostart, summon
  position. Those remain user-global preferences.
- No profile export / import file format. (May follow as part of the
  separate "可分享配置卡片" brainstorm item.)

## 3. What travels with a profile vs stays global

| Concern                    | Per-profile | Global |
|----------------------------|:-----------:|:------:|
| Pinned slots               | ✓           |        |
| Overflow pins              | ✓           |        |
| Slot count (4 – 12)        | ✓           |        |
| Ranking profile (MFU / Balanced / MRU) | ✓ |        |
| Identity-color overrides   | ✓           |        |
| Whitelist                  | ✓           |        |
| Hotkey chord & modifiers   |             | ✓      |
| Double-tap trigger + gap   |             | ✓      |
| Layout sliders + panel scale |           | ✓      |
| Summon position            |             | ✓      |
| Scroll / digit-key commit / frontmost-seed |  | ✓ |
| Sound effects              |             | ✓      |
| Language override          |             | ✓      |
| Autostart                  |             | ✓      |
| Onboarding state           |             | ✓      |

Rationale: anything that defines *how Halo behaves in this work context*
is per-profile; anything about *how Halo is shaped for your fingers and
display* is global.

## 4. Architecture

### 4.1 New type `BindingProfile`

Lives in `Sources/HaloCore/BindingProfile.swift`:

```swift
public struct BindingProfile: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    public var slotCount: Int                      // 4…12, clamped on decode
    public var rankingProfile: FrequencyProfile    // the field is renamed for
                                                   // readability inside the new
                                                   // type; see naming note below
    public var pinnedBundleIDs: [String?]          // length == slotCount
    public var overflowPinnedBundleIDs: [String]
    public var identityOverrides: [String: IdentityColor]
    public var whitelistedBundleIDs: [String]
}
```

**Naming note.** Inside `BindingProfile`, the MFU/Balanced/MRU enum is
called `rankingProfile` to disambiguate from the surrounding "profile"
concept (`BindingProfile` itself). The existing public API
`AppPreferences.frequencyProfile` is kept; its getter / setter projects
from / to `activeProfile.rankingProfile`. Engine call sites
(`AppDelegate.swift:235` etc.) need no changes.

Internal helpers (file-private):

```swift
extension BindingProfile {
    static func freshDefault() -> BindingProfile
    func resizing(slotCount newN: Int) -> BindingProfile
}
```

`freshDefault()` creates the canonical "Default" profile used both at
first launch and during migration when legacy keys are absent.

### 4.2 `AppPreferences` projection layer

`AppPreferences` keeps its existing scalar surface; the implementation
becomes a projection over the active profile:

- New stored backing: `profiles: [BindingProfile]`, `activeProfileID: UUID`.
- Existing getters (`slotCount`, `pinnedBundleIDs`, `overflowPinnedBundleIDs`,
  `frequencyProfile`, `identityOverride(for:)`, `whitelistedBundleIDs`)
  read from the active profile.
- Existing setters mutate the active profile and persist `profiles.v1`.
- `resizePinned(from:to:)` continues to operate on the active profile's
  pins via the same JSON encode/decode path.

New API on `AppPreferences`:

```swift
public var profiles: [BindingProfile] { get }
public var activeProfile: BindingProfile { get }
public var activeProfileID: UUID { get }

public func switchToProfile(_ id: UUID)
public func addProfile(name: String, cloning sourceID: UUID?) -> BindingProfile
public func renameProfile(_ id: UUID, to newName: String)
public func deleteProfile(_ id: UUID)
public func reorderProfiles(_ orderedIDs: [UUID])
```

`addProfile(name:cloning:)` with `sourceID == nil` produces a profile via
`BindingProfile.freshDefault()`; with a source it deep-clones pins,
overrides and whitelist (`UUID()` for the new id, copied otherwise).

`deleteProfile(_:)` refuses if it would leave zero profiles; if the
deleted id was active, activates the first remaining profile.

### 4.3 Storage keys

| Key                              | Lifetime | Notes |
|----------------------------------|----------|-------|
| `halo.prefs.profiles.v1`         | Persistent | JSON `[BindingProfile]`. Source of truth. |
| `halo.prefs.activeProfileID`     | Persistent | UUID string. |
| `halo.prefs.pinnedSlots.v1` …    | Read-only after v1.2 migration; dropped in v1.3. |
| `halo.prefs.overflowPins.v1`     | Read-only after v1.2 migration; dropped in v1.3. |
| `halo.prefs.identityOverride.v1` | Read-only after v1.2 migration; dropped in v1.3. |
| `halo.prefs.whitelist.v1`        | Read-only after v1.2 migration; dropped in v1.3. |
| `halo.prefs.slotCount`           | Read-only after v1.2 migration; dropped in v1.3. |
| `halo.prefs.frequencyProfile`    | Read-only after v1.2 migration; dropped in v1.3. |

All global keys (hotkey, layout, language, sound, autostart, summon
position, scroll/digit/frontmost, onboarding) are untouched.

### 4.4 Migration

Runs once during `AppPreferences.init`:

1. If `halo.prefs.profiles.v1` exists → already migrated, no-op.
2. Otherwise build a single `BindingProfile` named `"Default"` by
   reading the legacy keys **directly from `UserDefaults`** (not via the
   new projection getters, which aren't safe to call before
   `profiles.v1` is initialised). Use the same defaults the codebase
   applies today for missing keys (slot count 8, ranking `.balanced`,
   empty pins / overrides / whitelist).
3. Write `[default]` to `halo.prefs.profiles.v1`, set
   `activeProfileID` to its UUID.
4. Do **not** delete the legacy keys yet. Keep them for one release as
   a rollback safety net (so v1.1.x can still read the user's pins if
   they revert).
5. Drop legacy keys in v1.3 (separate one-line migration).

A `HaloLog.settings.info` line records the migration with the populated
counts so we can verify on diagnostic logs.

### 4.5 Engine integration

No engine changes. `HaloEngine` and `AppDelegate.recomputeSlots()`
continue to read `prefs.pinnedBundleIDs`, `prefs.slotCount`,
`prefs.frequencyProfile`. Because those getters now read the active
profile, switching profiles works through the existing
`objectWillChange.send() → recomputeSlots()` path.

The whitelist hot path (`prefs.isHaloSuppressed(forFrontmost:)`) and the
`whitelistSet` cache in `AppDelegate` already invalidate on
`whitelistedBundleIDs` change. Profile switch fires the same change
notification, so no extra wiring is required.

## 5. UX

### 5.1 Settings → new `Profiles` section

New entry in `SettingsSection` (between `.apps` and `.whitelist`):

- Sidebar label: `Profiles`, system image `square.stack.3d.up`.
- Detail view: a `List` of profiles, each row showing name, slot-count
  badge, ranking-profile chip, pin count. Active profile gets a
  left-accent bar and check glyph.
- Toolbar / footer: `+ New profile` button. Opens a sheet with name
  field + `Start from` segmented control: `Blank` / `Clone of {active}`.
- Row context: rename inline; `Duplicate` / `Delete` buttons; delete
  shows confirmation alert.
- Drag-to-reorder (uses `.onMove` on the List).

### 5.2 Settings — sidebar header gets an active-profile picker

Above the section list:

- Compact `Picker` showing the active profile name.
- Switching from the picker calls `prefs.switchToProfile(_:)`; the
  General / Apps / Whitelist tabs re-render automatically because they
  read scalar prefs.
- Note that the **General** tab today mixes global controls
  (layout sliders, panel scale, sound, hotkey, language) with two
  per-profile controls (`Slot count`, `Frequency profile`). After this
  change, the two per-profile controls visibly reflect the active
  profile while the rest do not. The two rows get a small accent
  badge (subtle `profile.name` chip) so users notice that those two
  values are scoped. No layout reshuffle in v1.
- `AppsTab.bindingHeader` swaps its "Default binding" title for the
  active profile name, leaves the summary as `{n} pinned · {m} slots`.

On macOS 12 (legacy `HStack` split), the picker sits at the top of
`SettingsSidebar`.

### 5.3 Menu bar — new `Profile` submenu

`MenuBarController` adds a `Profile ▸` item between `Summon Halo` and
`Settings…`:

- One item per profile, current one with `state = .on`.
- Click → `prefs.switchToProfile(_:)`.
- Trailing separator + `Edit Profiles…` item that opens Settings and
  programmatically selects the `Profiles` section.

### 5.4 Onboarding / Welcome

Unchanged for v1. First-run users see only `Default`. No tutorial step.

## 6. Edge cases & errors

- **`profiles.v1` decode failure** → fall back to the migration path as
  if first run. Logged at `error`. The user loses unmigrated edits made
  on the corrupt profile file, but their legacy keys still produce a
  working `Default` (until v1.3 drops them; from then on they get a
  blank `Default`).
- **`activeProfileID` references missing profile** → fall back to first
  profile in the array, persist the correction, log warning.
- **Empty `profiles` array** → fall back to `BindingProfile.freshDefault()`
  and persist immediately. This can only happen if a user manually
  edits the plist.
- **`slotCount` mutation inside a profile** → existing
  `resizePinned(from:to:)` runs against the active profile's pins;
  overflow spills behave exactly as today.
- **Renaming to an existing name** → allowed (names need not be unique);
  the Profiles list shows the UUID short-hash next to duplicates.
- **Deleting the only profile** → button is disabled and the action
  refuses (`HaloLog.settings.error("Refusing to delete the last profile")`).
- **Concurrency** → all mutation goes through `@MainActor AppPreferences`.
  No new threading.

## 7. Testing

### 7.1 New unit tests (`Tests/HaloCoreTests`)

- `BindingProfileTests`
  - Codable round-trip for a fully-populated profile.
  - `resizing(slotCount:)` preserves prefix pins, spills suffix into
    overflow, restores overflow when growing.
  - Equatable / Identifiable semantics.

- `AppPreferencesProfileTests`
  - First-run migration: legacy keys → single `Default` profile with
    matching contents.
  - Idempotent migration: running twice produces identical state.
  - `addProfile(name:cloning:nil)` produces a fresh profile.
  - `addProfile(name:cloning:active)` deep-copies pins / overrides /
    whitelist; ids differ.
  - `switchToProfile(_:)` swaps the scalar projections (pins, slot
    count, ranking, whitelist) and emits `objectWillChange`.
  - `deleteProfile(active)` falls back to the next profile.
  - `deleteProfile(last)` refuses.
  - Mutating `slotCount` only affects the active profile, not the
    others.

Existing `AppPreferencesTests` (clamping, bounds, layout math) must
continue to pass without edits.

### 7.2 UI tests (`Tests/HaloUITests`)

- One additional test in `HaloState` coverage: when `slotCount` changes
  via a profile switch, `HaloState.slotCount` updates and any pending
  highlight clamps inside the new range. (We already test slot-count
  mutation; this just adds a "via profile switch" path through
  `AppDelegate.recomputeSlots()`.)

### 7.3 Manual QA

Per project memory rule (`feedback_test_build_open.md`), build the .app
and walk these scenarios before handoff:

1. Upgrade-in-place: start with a v1.1.2 prefs directory, run the new
   build, open Settings → Profiles. Verify exactly one `Default`
   profile exists with the user's prior pins / colors / whitelist /
   slot count / ranking.
2. Duplicate `Default` → `Work`. Remove a pin in `Work`. Switch to
   `Default`. The pin is still there.
3. Set `Work` to 12 slots, `Default` to 8. Switching between them
   resizes the wheel.
4. Summon Halo. Use the menu bar to switch profile. Re-summon. The new
   pins are shown without restarting the app.
5. Delete the active profile. The first remaining becomes active. No
   crash.
6. Whitelist Steam in a `Gaming` profile. Switch off. The Halo chord
   still summons when Steam is frontmost.

### 7.4 Release

Ship as **v1.2.0**. `CHANGELOG.md` gets an entry under `## v1.2`. The
public README needs no rewrite — a 1-sentence note in the Apps section
mentioning that pins live under profiles.

## 8. Open follow-ups (post-v1)

- v1.x: keyboard shortcut to cycle profile.
- v1.x: lightweight auto-recommend by frontmost app (BRAINSTORM
  explicit roadmap item).
- v1.3: drop legacy `UserDefaults` keys after the one-release rollback
  window.
- v2: integrate with the planned `.halo-profile` import/export format
  from the "可分享主题与配置卡片" brainstorm item.
