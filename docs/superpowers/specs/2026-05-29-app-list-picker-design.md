# 2026-05-29 — Unified Finder-style app-list picker

## Problem

Two near-identical app pickers exist:

- `AppPickerSheet` (`SettingsWindow.swift:435`) — a sheet opened from Settings →
  Apps when tapping an empty wheel slot. `List` + `.searchable`, single-line
  rows showing icon + name + **bundleID** (monospaced, right-aligned).
- `PinPickerView` (`PinPickerWindow.swift:57`) — a standalone `NSWindow` opened
  when the user commits onto an empty slot live. Custom search field, two-line
  rows (name over **bundleID**).

Both:

- duplicate the scan + filter + row code (and a third copy of app-scanning logic
  lives in `GridState`);
- scan only `/Applications` + `/System/Applications` (miss `~/Applications`,
  `/Applications/Utilities`) — inconsistent with the ALL grid;
- scan synchronously in `.onAppear` and load icons synchronously via
  `NSWorkspace.shared.icon(forFile:)` on the main thread → a hitch on open;
- show the technical `bundleID` in every row (not Finder-like).

## Goal

One shared, Finder-style app-list component used by both hosts:

- **Row**: single line, app icon (20pt) + name only. No bundleID. Native
  selection highlight.
- **Open**: no main-thread jank — scan + icon prefetch happen off the open path.
- **Coverage**: `/Applications`, `/System/Applications`, `~/Applications` with
  depth-2 recursion (so Utilities surface) — parity with the ALL grid.
- **Order**: alphabetical (Finder).

## Decisions (from brainstorming)

1. Scope — **unify** both pickers into one shared component.
2. Row — **Finder-minimal**: icon + name, no inline bundleID.
3. Extent — **visual + performance + coverage** (not visual-only).

## Approach: reuse-first

Reuse the pieces the ALL grid already ships rather than writing a third copy.

- **Scan**: `GridState.scanInstalledApps()` (`HaloUI`, `nonisolated public
  static`, returns `[GridApp]` — `Sendable`). Already covers the three roots
  with depth-2 recursion, dedups by bundleID, prefers `CFBundleDisplayName` /
  `CFBundleName`, and returns alphabetically sorted. Run it on a
  `Task.detached`, publish on `MainActor`.
- **Icons**: `AppIconResolver.icon(for:)` (`HaloUI`, NSCache-backed). After the
  scan publishes, prefetch the first ~80 bundleIDs on `MainActor` (same pattern
  as `GridState.loadApps`) so the first viewport hits warm cache. Rows read
  `AppIconResolver.icon(for:)`.
- **Search**: a custom top search field (the existing `PinPickerView` pattern),
  not `.searchable`. Works identically in a sheet and a bare `NSWindow` without
  a navigation container / toolbar; auto-focused on open via `@FocusState`.
  Filters by name (and bundleID under the hood, not shown). `onSubmit` picks the
  first filtered result; Cancel / Esc → `onPick(nil)`.
- **Loading state**: a centered `ProgressView` while `isLoading`, so the bare
  window doesn't flash empty (keep the explicit `.frame`).

Rejected alternative (B): a self-contained scanner inside the picker — a third
copy of scan logic, against DRY, with no upside given the dependency direction
already allows `HaloApp → HaloUI`.

## Components

- **`Sources/HaloApp/AppListPicker.swift`** (new) — the shared view.
  - `init(onPick: @escaping (String?) -> Void)`.
  - `@State apps: [GridApp]`, `@State search: String`, `@State isLoading`,
    `@FocusState searchFocused`.
  - `body`: `VStack(spacing: 0) { searchRow; Divider(); content }`.
    `content` = `ProgressView` while loading, else `List(filtered)` of
    `AppListRow`.
  - `AppListRow`: `HStack { Image(nsImage: AppIconResolver.icon(for:) ?? blank)
    20pt; Text(name); Spacer() }` inside a `.plain` Button → `onPick(bundleID)`.
  - `load()`: `Task.detached { GridState.scanInstalledApps() }` →
    `MainActor.run { apps = …; isLoading = false; prefetch top 80 }`.
- **`AppPickerSheet`** (`SettingsWindow.swift`) → thin wrapper:
  `AppListPicker(onPick:).frame(width: 480, height: 460)`. Keeps its `onPick`
  contract so `BindingWheelView`'s `.sheet { AppPickerSheet { … } }` is
  unchanged. Delete its `apps`/`search`/`filtered`/`load`/row code.
- **`PinPickerView`** (`PinPickerWindow.swift`) → thin wrapper:
  `AppListPicker(onPick:).frame(width: 480, height: 520)`. Delete its
  `Item`/`apps`/`search`/`filtered`/`load`/row code; `PinPickerWindowController`
  unchanged.

## Strings

`"Search apps"` and `"Cancel"` already exist in `en` + `zh-Hans`
`Localizable.strings`; SwiftUI resolves the literals as `LocalizedStringKey`
automatically. **No `Localizable.strings` change needed.**

## Architecture / invariants

- `HaloApp → HaloUI` dependency only (allowed). No `HaloCore` change.
- No Accessibility, no networking, no telemetry. Pure file I/O + AppKit icons.
- macOS 12 safe: no new gated APIs; `Task.detached` / `@FocusState` /
  `ProgressView` are all ≥ 12. `AppIconResolver` already handles the
  main-thread `NSWorkspace.icon` contract.

## Verification

- `make test` — `AppIconResolverCacheTests` + all others stay green (no logic
  change to tested units).
- `make app`, then open **both** hosts myself:
  - Settings → Apps → tap an empty slot → the sheet.
  - Double-tap summon → commit onto an empty slot → the live window.
- Confirm: Finder-minimal rows (icon + name, no bundleID); no hitch on open;
  `~/Applications` + Utilities apps present; search filters; `onSubmit` /
  click / Cancel / Esc all pick correctly.

## Risks / rollback

- If a bare `NSWindow` mishandles `@FocusState` auto-focus, drop the auto-focus
  (search still works on click). Low risk.
- Rollback: delete `AppListPicker.swift` and restore the two original structs
  (single commit, easy revert).
- Scope guard: do not touch `GridState` / `AppIconResolver` (consume only); do
  not change the ALL grid.
