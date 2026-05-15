# Halo 多 Profile / 场景环 — Design Spec (v2, 最小版)

- **Date:** 2026-05-14
- **Target release:** Unreleased (next minor on top of v1.1.2)
- **Status:** Draft v2 — supersedes v1 (which over-engineered profile scope across 5 tabs/surfaces)
- **Mockup:** [`mockups/halo-settings.html`](../../../mockups/halo-settings.html) §2 + [`mockups/multi-profile.html`](../../../mockups/multi-profile.html)

## 1. Goal

Let users keep multiple named profiles of *Halo bindings* — pinned apps
and their identity-colour overrides. Switch between them from a profile
bar at the top of **Settings → Apps**. Everything else (slot count,
ranking, whitelist, hotkey, layout, language, sound) stays user-global.

## 2. Non-goals (initial scope)

The v1 spec landed pickers and chips across the sidebar, menu bar, and
the General tab. v2 drops all of that. None of the following ship in
this release:

- No new sidebar entry. The Apps tab owns the entire feature surface.
- No sidebar-header profile picker.
- No menu-bar Profile submenu.
- No General-tab chips marking which controls are per-profile.
- No per-profile slot count, ranking profile, or whitelist. Those stay
  user-global and apply across all profiles.
- No profile colors / dots in this scope (the mockup shows them; deferred —
  pure-text pills only).
- No auto-detect of active profile from frontmost app.
- No hotkey to switch profile.
- No iCloud / sync.
- No profile export/import file format.

## 3. What travels with a profile vs stays global

| Concern                       | Per-profile | Global |
|-------------------------------|:-----------:|:------:|
| Pinned slots                  | ✓           |        |
| Overflow pins                 | ✓           |        |
| Identity-color overrides      | ✓           |        |
| Slot count (4 – 12)           |             | ✓      |
| Ranking profile (MFU/Balanced/MRU) |        | ✓      |
| Whitelist                     |             | ✓      |
| Hotkey + double-tap trigger   |             | ✓      |
| Layout sliders + panel scale  |             | ✓      |
| Summon position               |             | ✓      |
| Scroll / digit / frontmost-seed |           | ✓      |
| Sound effects                 |             | ✓      |
| Language                      |             | ✓      |
| Autostart                     |             | ✓      |
| Onboarding state              |             | ✓      |

Rationale: a profile is "this set of pinned apps and their colours."
Everything else is part of the user's general Halo configuration.

## 4. Architecture

### 4.1 `BindingProfile` (narrow payload)

`Sources/HaloCore/BindingProfile.swift`:

```swift
public struct BindingProfile: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    public var pinnedBundleIDs: [String?]
    public var overflowPinnedBundleIDs: [String]
    public var identityOverrides: [String: IdentityColor]
}
```

Helpers:

```swift
extension BindingProfile {
    static func freshDefault() -> BindingProfile
    func resizing(slotCount newN: Int) -> BindingProfile
}
```

`resizing(slotCount:)` mirrors the existing
`AppPreferences.resizePinned(from:to:)` behaviour. `slotCount` is **not**
stored on the profile — it's read from the global pref — but the pin
array length must track it, so when global `slotCount` changes
`AppPreferences` resizes the active profile's pins.

### 4.2 `AppPreferences` projection (narrow)

`AppPreferences` keeps its existing scalar API. Only the *binding*
fields project from the active profile:

| Reader / writer                    | Projects from / writes to active profile? |
|------------------------------------|:----------------------------------------:|
| `pinnedBundleIDs`                  | ✓ |
| `overflowPinnedBundleIDs`          | ✓ |
| `identityOverride(for:)`           | ✓ |
| `setPinnedBundleID(_:at:)`         | ✓ |
| `setIdentityOverride(_:for:)`      | ✓ |
| `clearAllBindings()`               | ✓ |
| `slotCount` (setter)               | reads/writes the global key, **and** calls `profile.resizing(slotCount:)` so the active profile's pin array tracks the new length |
| every other field                  | unchanged |

New API:

```swift
public var profiles: [BindingProfile] { get }
public var activeProfile: BindingProfile { get }
public var activeProfileID: UUID { get }

public func switchToProfile(_ id: UUID)
public func addProfile(name: String, cloning sourceID: UUID?) -> BindingProfile
public func renameProfile(_ id: UUID, to newName: String)
public func deleteProfile(_ id: UUID)   // refuses if it would leave 0
```

No `reorderProfiles` in this scope — the profile bar doesn't support drag,
keeping the UI minimal.

### 4.3 Storage

| Key                              | Lifetime | Notes |
|----------------------------------|----------|-------|
| `halo.prefs.profiles.v1`         | Persistent | JSON `[BindingProfile]`. Source of truth. |
| `halo.prefs.activeProfileID`     | Persistent | UUID string. |
| `halo.prefs.pinnedSlots.v1`      | Read-only after migration; dropped in the minor after that. |
| `halo.prefs.overflowPins.v1`     | Read-only after migration; dropped in the minor after that. |
| `halo.prefs.identityOverride.v1` | Read-only after migration; dropped in the minor after that. |

All other legacy keys (`slotCount`, `frequencyProfile`, `whitelist.v1`,
hotkey, layout, sound, language, …) stay untouched — they remain the
single source of truth for global state.

### 4.4 Migration

Runs once during `AppPreferences.init`:

1. If `halo.prefs.profiles.v1` exists → no-op.
2. Otherwise read raw legacy keys (`pinnedSlots.v1`,
   `overflowPins.v1`, `identityOverride.v1`) directly from
   `UserDefaults`. Use the current global `slotCount` for the pin array
   length.
3. Build a single `BindingProfile` named `"Default"`, write
   `[default]` to `halo.prefs.profiles.v1`, set `activeProfileID`.
4. Keep the legacy keys as a rollback safety net through the initial multi-profile release; drop in the minor after that.

### 4.5 Engine integration

No engine changes. `HaloEngine`, `AppDelegate.recomputeSlots()`,
`BindingWheelView`, every other consumer all keep reading
`prefs.pinnedBundleIDs` / `prefs.identityOverride(for:)`. Those getters
now project from the active profile, so a profile switch fires
`objectWillChange` and the existing `recomputeSlots()` listener re-snaps
the wheel.

## 5. UX — the **only** UI change

`Sources/HaloApp/SettingsWindow.swift::AppsTab` gets one new view inserted
between the section header and the existing `bindingHeader`: a
`ProfileBar(prefs:)`.

```
┌─ Apps ─────────────────────────────────────────────┐
│  [ Default ]  [ Work ]  [ Gaming ]   [+]    3 profiles │  ← new
│  ──────────────────────────────────────────────    │
│  (existing binding-card unchanged)                 │
│  (existing BindingWheelView unchanged)             │
│  (existing Hidden Pins section unchanged)          │
└────────────────────────────────────────────────────┘
```

**ProfileBar composition:**

- One pill per profile. Active profile uses an inset/elevated style
  (matches the existing `.profile.active` from `mockups/halo-settings.html`).
- Click a pill → `prefs.switchToProfile(_:)`.
- Right-click / long-press / `⋯`-on-hover opens a context menu:
  - "Switch to" (disabled if already active)
  - "Rename…" — flips the pill to an inline `TextField`; Return commits,
    Esc cancels.
  - "Duplicate" — creates a clone with name `"{original} copy"`.
  - "Delete" — opens a confirm alert; disabled if `profiles.count == 1`.
- `+` button at the end of the row opens a new-profile sheet.
- Trailing meta text: `"{n} profiles · current {name}"`.

**New-profile sheet:**

- Name field (focused on appear, default `"Profile N"`).
- Segmented picker: `Blank` / `Clone of {active}`.
- Cancel / Create.

**AppsTab `bindingHeader`:** swap the literal `"Default binding"` for
`prefs.activeProfile.name` (only that one string change).

**Onboarding / Welcome / About:** unchanged. The General tab, Whitelist
tab, sidebar, menu bar — none touched.

## 6. Edge cases & errors

- **Decode failure on `profiles.v1`** → re-run migration as if first
  run. Logged at `error`.
- **Stale `activeProfileID`** (refers to a deleted profile) → fall back
  to first profile, persist correction, log warning.
- **Empty `profiles`** → seed a fresh `Default`, persist.
- **`slotCount` change while profile is active** → setter calls
  `updateActiveProfile { $0 = $0.resizing(slotCount: newN) }`. Inactive
  profiles' pin arrays stay at their previous length; they're resized
  lazily the next time they become active and `slotCount` is read.

  *Open question:* should inactive profiles also resize? Decision:
  **no** in this scope. Pin arrays for inactive profiles can be out of sync
  with global `slotCount`; when switching to them, projector clamps
  pinnedBundleIDs to the current slotCount on read and lazily resizes
  on next mutation. Simpler than walking every profile on a global
  setter.

- **Deletion of the last profile** → button disabled, log warning,
  refuse the call defensively.
- **Concurrency** → all mutation goes through `@MainActor
  AppPreferences`; no new threading.

## 7. Testing

### Unit (new)

- `BindingProfileTests` — Codable round-trip, `resizing(slotCount:)`
  shrink/grow/identity, Equatable.
- `AppPreferencesProfileTests` —
  - first-run from blank defaults creates a `Default` profile
  - legacy keys migrate into a single `Default` with matching pins +
    overrides
  - migration is idempotent
  - `setPinnedBundleID` writes through to active profile, not legacy keys
  - `setIdentityOverride` writes through; nil removes
  - `addProfile(name: cloning: nil)` appends fresh
  - `addProfile(name: cloning: active)` deep-clones pins + overrides
  - `renameProfile` updates name
  - `switchToProfile` swaps pin projection
  - `deleteProfile(active)` falls back to first remaining
  - `deleteProfile(last)` refuses
  - persistence survives recreating `AppPreferences`
  - **NEW:** changing global `slotCount` resizes the active profile's
    pin array
  - **NEW:** legacy global `whitelist.v1` / `frequencyProfile` /
    `slotCount` stay readable through the existing scalar API (they are
    *not* per-profile)

### Existing tests

`AppPreferencesTests` (12 tests) and `AppPreferencesBoundsTests` must
pass unchanged.

### UI tests

No new UI tests for this scope. The new SwiftUI view is mostly state-binding
glue; the underlying `prefs.*Profile` methods carry the load and are
unit-tested.

### Manual QA (per `feedback_test_build_open.md`)

Build the `.app`, launch, walk:

1. Upgrade-in-place: pins still visible under a single `Default` profile.
2. Click `+`, create `Work` as Clone-of-Default. Removing a pin in
   `Work` keeps `Default` intact.
3. Switch from Work back to Default — wheel re-snaps without restart.
4. Rename via context menu inline.
5. Delete Work → falls back to Default.
6. Try to delete Default when it's the only profile — option disabled.
7. Change global slot count (General tab) from 8 → 12. Active profile's
   pin array grows; overflow pins return.
8. Restart Halo. Active profile + profile list persist.

## 8. Release

Ship as part of the next minor on top of v1.1.2. CHANGELOG entry summarises the feature, the
explicit non-goals, and the migration.

## 9. Open follow-ups (post initial scope)

- v1.x: profile colour / dot (mockup shows it; auto-assigned from a 6-tone
  palette by index, or user-pickable).
- v1.x: drag-to-reorder pills.
- v1.x: drop legacy `UserDefaults` keys (the minor after the initial multi-profile release).
- v1.x: auto-detect active profile from frontmost app (BRAINSTORM
  roadmap item).
- v2: integrate with the planned `.halo-profile` import/export from
  the "可分享主题与配置卡片" brainstorm item.
