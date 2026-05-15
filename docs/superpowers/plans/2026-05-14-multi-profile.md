# Multi-Profile / 场景环 Implementation Plan (v2, 最小版)

> Supersedes the v1 plan which added pickers across 5 surfaces.
> v2 confines the entire UI to a `ProfileBar` at the top of
> Settings → Apps.

**Goal:** Named Binding Profiles for pinned apps + identity colour
overrides, switchable from a pill bar at the top of the Apps tab.

**Architecture:** New `BindingProfile { id, name, pinnedBundleIDs,
overflowPinnedBundleIDs, identityOverrides }`. `AppPreferences` projects
only those four fields from the active profile; every other pref stays
user-global. Existing engine + view code unchanged.

**Reference spec:** [`docs/superpowers/specs/2026-05-14-multi-profile-design.md`](../specs/2026-05-14-multi-profile-design.md)
**Mockups:** `mockups/halo-settings.html` §2, `mockups/multi-profile.html`

---

## File structure

**Create:**
- `Sources/HaloCore/BindingProfile.swift`
- `Sources/HaloApp/ProfileBar.swift` — the pill bar + sheet + alert
- `Tests/HaloCoreTests/BindingProfileTests.swift`
- `Tests/HaloCoreTests/AppPreferencesProfileTests.swift`

**Modify:**
- `Sources/HaloCore/AppPreferences.swift` — projection of pins +
  overrides, migration, profile management API
- `Sources/HaloApp/SettingsWindow.swift` — `AppsTab` inserts
  `ProfileBar(prefs:)` above `bindingHeader`; swap `"Default binding"`
  for the active profile name
- `Resources/en.lproj/Localizable.strings` — Apps-tab-only new keys
- `Resources/zh-Hans.lproj/Localizable.strings` — same
- `Resources/Info.plist` — version bump
- `Sources/HaloCore/HaloCore.swift` — `Halo.version`
- `CHANGELOG.md`

**Do NOT touch:**
- `Sources/HaloApp/SettingsSidebar.swift`
- `Sources/HaloApp/GeneralSettingsTab.swift`
- `Sources/HaloApp/WhitelistTab.swift`
- `Sources/HaloApp/AboutTab.swift`
- `Sources/HaloUI/MenuBarController.swift`
- `Sources/HaloApp/AppDelegate.swift`

---

## Task 1: `BindingProfile` + tests

Pure value type, slimmed payload (no slotCount, no rankingProfile, no
whitelist). Codable round-trip + resizing(slotCount:) shrink/grow/identity.

## Task 2: `AppPreferences` projection + migration

- Add `profiles` / `activeProfile` / `activeProfileID` backing storage.
- Migration: legacy `pinnedSlots.v1` + `overflowPins.v1` +
  `identityOverride.v1` → single `Default` profile.
- Route only `pinnedBundleIDs`, `overflowPinnedBundleIDs`,
  `identityOverride(for:)`, `setPinnedBundleID`, `setIdentityOverride`,
  `clearAllBindings` through `updateActiveProfile`.
- `slotCount` setter additionally calls
  `updateActiveProfile { $0 = $0.resizing(slotCount: clamped) }` so the
  active profile's pin array tracks the global slot count.
- Everything else (`frequencyProfile`, `whitelistedBundleIDs`, …)
  stays exactly as today.

## Task 3: Profile management API

`addProfile(name:cloning:)`, `renameProfile(_:to:)`, `deleteProfile(_:)`,
`switchToProfile(_:)`. Self-heal stale activeID + empty profiles array.
Refuse to delete the last profile.

## Task 4: `ProfileBar` view + AppsTab wiring

`Sources/HaloApp/ProfileBar.swift`:

```swift
struct ProfileBar: View {
    @ObservedObject var prefs: AppPreferences
    @State private var renamingID: UUID?
    @State private var renameDraft: String = ""
    @State private var showingNewSheet = false
    @State private var newName: String = ""
    @State private var newCloneActive = true
    @State private var deletingID: UUID?

    // Layout: HStack of pills, then +, spacer, meta text.
    // Each pill: text label, context menu (Switch / Rename / Duplicate / Delete).
    // Active pill: bg + subtle border.
    // Rename mode: pill replaced by inline TextField with matching size.
    // + button: dashed border square that opens the sheet.
    // Sheet: name field + Blank/Clone segmented picker.
    // Alert: delete confirm.
}
```

Edit `Sources/HaloApp/SettingsWindow.swift`:
- Insert `ProfileBar(prefs: prefs).padding(.bottom, 4)` immediately
  inside the `Form` in `AppsTab.body`, before `bindingHeader`.
- Change `Text("Default binding")` → `Text(prefs.activeProfile.name)`.

## Task 5: Localization

`Resources/en.lproj/Localizable.strings` (append):
```
/* Profile bar (Apps tab) */
"New profile" = "New profile";
"New profile…" = "New profile…";
"Start from" = "Start from";
"Blank" = "Blank";
"Clone of %@" = "Clone of %@";
"Switch to %@" = "Switch to %@";
"Rename…" = "Rename…";
"Duplicate" = "Duplicate";
"Delete profile?" = "Delete profile?";
"This profile's pins and identity colours will be removed. Global settings are unaffected." = …;
"%d profile" = "%d profile";
"%d profiles" = "%d profiles";
```

`zh-Hans.lproj/Localizable.strings`: 同样的 keys，中文翻译。

## Task 6: Version bump + CHANGELOG

- `Resources/Info.plist`: `CFBundleShortVersionString` bumped to the next minor on top of v1.1.2 (the actual number gets picked at release-cut time, not pre-bumped while the work sits in `Unreleased`).
- `Sources/HaloCore/HaloCore.swift`: `version` matches the bump above.
- `CHANGELOG.md`: graduate the relevant section out of `Unreleased`. Explicitly call out the minimal scope.

## Task 7: Build + launch + verify migration

`make app && open dist/Halo.app`. Check `~/Library/Logs/Halo/halo.log`
for the migration line. Walk the 8-step manual QA from spec §7.

---

## Self-review

- Spec coverage:
  - §3 per-profile fields → covered by Tasks 1+2.
  - §4.1 BindingProfile → Task 1.
  - §4.2 projection → Task 2.
  - §4.3 storage keys → Task 2.
  - §4.4 migration → Task 2.
  - §4.5 engine integration → no task needed (no engine code touched).
  - §5 UX → Task 4.
  - §6 edge cases → Tasks 2+3 self-heal paths.
  - §7 tests → Tasks 1+2+3.
  - §8 release → Task 6.

- Placeholders: none. Code paths are concrete.

- Type consistency: `addProfile(name:cloning:)`,
  `switchToProfile(_:)`, `renameProfile(_:to:)`, `deleteProfile(_:)`,
  `resizing(slotCount:)` — all referenced identically across tasks.

- Boundary check: file `do-not-touch` list keeps the scope honest. If
  during implementation I find I need to edit
  e.g. `SettingsSidebar.swift`, stop and escalate before scope-creeping.
