# Changelog

All notable changes to Halo.

## Unreleased

### Action Ring (二段手势, layer 2)

- Hold ⇧ while hovering an app slot to surface the **Action Ring** — a second layer of the same wheel that exposes per-app local actions. Release ⇧ to drop back to the slot ring (same angular position preserved); release the trigger to commit. Layer 1 hot path is unchanged.
- Three action kinds in v1, all shell-free and local: **Open folder** (NSWorkspace.open on a path; `~` expanded at run time), **Open URL** (any scheme NSWorkspace accepts), **Run Shortcut** (routes through `shortcuts://run-shortcut?name=<url-encoded>` via URLComponents so reserved chars like `&` round-trip cleanly).
- Settings → **Actions** (new sidebar tab): left column lists configured apps, right column shows that app's action list with reorder / edit / delete. Add-action sheet picks kind + label + payload + optional SF Symbol override. Committing an empty layer-2 sector opens this tab pre-targeted to the right bundleID via `SettingsFocusCoordinator`.
- Visual differentiation from layer 1: hub shows the target app icon + an "ACTIONS" subtitle in the identity colour, idle sectors carry a warmer 6 % accent fill (vs layer 1's 1.5 % white), and a thin accent rim ring sits inside the visible disc edge.
- Storage: `halo.prefs.actionBindings.v1` UserDefaults key holds `[bundleID: [HaloAction]]`. Render takes the first `slotCount` per app; storage is cap-free and doesn't shuffle when the user changes slot count.
- 19 new unit tests across `HaloActionStoreTests` / `ActionExecutorTests` / `HaloStateLayerTests`.

## [1.1.2] — 2026-05-14

### Wheel UX

- Hover hit-test reach extended to 1.5× the wheel diameter. The cursor now counts as hovering a sector anywhere within `reachDiameter` (= `haloDiameter × 1.5`) of the wheel centre — about a quarter wheel-radius of invisible cushion outside the visible disc. Pointing at the rim is no longer finicky; pulling the cursor far past the cushion still cancels on trigger release. Lives behind a single `HaloUI.Geometry.reachDiameter` constant so the factor can be retuned (or surfaced to Settings) without touching the geometry layer.
- 6 new tests (`RadialReachHitTestTests`) cover hits outside the wheel but inside reach, misses past the reach radius, deadzone misses, the cardinal-direction sweep, and the boundary case.

## [1.1.1] — 2026-05-14

### Build consistency

- Removed the `#if compiler(>=6.3)` guards around every Liquid Glass call site (`RadialView`, `OnboardingOverlay`, `WelcomeWindow`, `GeneralSettingsTab`). The `glassEffect()` API ships with the macOS 26 SDK in any Xcode 26.x, so the compile-time gate was excluding Xcode 26.0–26.3 builds (including the GitHub `macos-26` runner's default Xcode 26.2 / Swift 6.2.3) and shipping a v1.1.0 release binary with **zero** Liquid Glass symbols — the wheel silently fell back to a flat `NSVisualEffectView(.hudWindow)`. Liquid Glass now reaches macOS 26 users regardless of which Xcode 26.x compiled the binary.
- CI (ci.yml + release.yml) now explicitly `xcode-select`s the newest `Xcode_26.*.app` on the runner before showing the toolchain, so future GitHub runner image changes can't silently downgrade the SDK.

### Visual

- macOS 12–15 hover tint on the wheel boosted from 6 % → 14 % (only on the legacy `NSVisualEffectView` path; macOS 26 stays at 6 % because Liquid Glass already produces content-aware refraction). Compensates for the inert legacy material so the hovered identity colour still reads on the disc.

## [1.1.0] — 2026-05-14

### Settings panel

- Rebuilt around a sidebar (General / Apps / Whitelist / About). On macOS 13+ uses native `NavigationSplitView` + `Form(.grouped)` — translucent sidebar, accent-tinted selection pill, Liquid Glass on macOS 26. macOS 12 falls back to a custom HStack. Default frame 880×720, min 760×600, resizable.
- General → Navigation: scroll-to-switch-slots / digit-key commit (now via keyCode table covering `1–9 0 - =`) / highlight-frontmost-on-summon (refactored to a non-rendering `scrollAnchor` after a hover-flash regression — see hit-test fix below).
- General → Appearance: `Panel size` slider applies a renderer-time scale (0.80–1.50x) to the whole wheel; live hit-test now divides gesture coords by the scale (regression fix; pre-fix a 1.3x panel caused the next slot to flash and silently commit the wrong app).
- General → Trigger: double-tap picker now offers five keys (⌥ Left, ⌥ Right, ⌘, ⌃, Mouse 3 Middle). State machine moved into `DoubleTapMonitor`; keyboard path uses `flagsChanged` with keyCode discrimination (kVK 58/61/54/55/59/62) since `NSEvent.ModifierFlags` doesn't expose a stable left/right bit. `CommandLongPressMonitor` removed.
- Arrow-key navigation now shares the same `SlotCycle` anchor logic as the scroll wheel.
- Display language picker localises in-app — restart required to apply.

### Whitelist (new)

- New `Whitelist` tab + preference key `halo.prefs.whitelist.v1` (`[String]` of bundle IDs). When the frontmost app is whitelisted, both `HaloHotkey` and `DoubleTapMonitor` short-circuit before firing — Halo is silent in that app. Carbon registration stays installed so the chord never escapes to other apps mid-session.
- `WhitelistSuggestions.installedSubset()` seeds Xcode / VS Code family / JetBrains / Figma / Sketch / Adobe / Blender / Unity / Roblox Studio / Parallels / VMware / Microsoft RDC — only apps actually installed get included via `NSWorkspace.urlForApplication`. No auto-seed on first launch; user-driven "Apply recommended" only.

### Runtime safety

- DoubleTapMonitor + AppDelegate global `NSEvent` monitors now extract sendable primitives in the closure and hop to MainActor via `Task { @MainActor in }` instead of `MainActor.assumeIsolated`. Fixes Swift 6 strict-concurrency drift and silent main-thread requirements.
- `Switcher.switchToAsync` awaits `NSWorkspace.openApplication`'s real completion handler — corrupt / moved / quarantined bundles now drop into shake-and-dismiss instead of optimistic ripple-and-vanish.
- `UsageStore` prunes the 7-day window on every write (was read-only filtered, JSON grew unbounded).
- `AppPreferences` whitelist is cached as a `Set<String>` inside AppDelegate; hot-path gate no longer decodes JSON per keypress. `registerHotkey()` now only fires when the chord actually changed (was running ~10×/sec while dragging Panel Size slider).
- `DoubleTapMonitor` switched back to passive state polling (25 Hz Timer reading `CGEventSource.keyState` for keyboard, `NSEvent.pressedMouseButtons` for middle mouse) instead of `NSEvent.addGlobalMonitorForEvents`. **Halo no longer requires Accessibility permission for any trigger path** — the global-monitor approach was an interim v1.1 implementation choice; `CGEventSource.keyState` is keyCode-aware so left/right Option/Control distinctions are preserved. Drops the launch-time AX alert and `AXIsProcessTrusted()` probe.

### Localization

- en + zh-Hans translations added for every new section (sidebar, navigation toggles, trigger picker, panel size, whitelist UI, DoubleTapTrigger labels).
- zh-Hans Frequency profile uses Chinese short labels (`最常用 / 平衡 / 最近用`).

### Tests

- 57+ tests across `HaloCoreTests` + new `HaloUITests` target. Regression coverage for `SlotCycle` anchor priority, `RadialGeometry.sectorIndex(forGestureLocation:…)` panelScale hit-test, and `HaloState.scrollAnchor` lifecycle. v1.0 had 27 tests.

## [1.0.0] — 2026-05-13

First public release.

### Halo

- Radial Halo wheel with 4 / 6 / 8 / 10 / 12 configurable slots; slot 0 is always at 12 o'clock, the rest sweep clockwise.
- **Liquid Glass** disc + label chip on macOS 26 (Tahoe): native `glassEffect` surfaces, `GlassEffectContainer` so the label morphs between slots via `glassEffectID`. macOS 14 / 15 fall back to a hand-composed `NSVisualEffectView` (`.hudWindow` / `.behindWindow`) with the same visual recipe.
- Feathered radial-alpha disc edge: no hard rim stroke; the wheel dissolves into the desktop.
- Pie-slice `SectorShape` with 1° angular gaps between slots — no overlapping strokes. Full-colour app icons at 48 pt; running-state dots; empty-slot dashed marks with a breathing pulse.
- Identity-colour-driven hover treatment: per-slot accent stroke + inner glow + radial halo glow + 5 % whole-disc tint, all `plusLighter` blended so the brand colour lights the glass rather than painting on top.
- Centre hub previews the hovered app's icon; falls back to the system frontmost app when nothing is hovered.
- 60 fps cursor timer in the host `NSPanel` drives hover updates — `.onContinuousHover` doesn't fire reliably for non-activating panels.
- Arrow-key cycling, digit-key direct selection, click to commit, `ESC` to cancel, drag-out to dead-zone to cancel.
- Vignette ripple on commit in the slot's identity colour.

### Triggers

- Primary global hotkey via Carbon `RegisterEventHotKey`. Default `⌘⌥Space`. Press to summon, release to commit the highlighted slot.
- **Double-tap ⌘** as a single-handed alternative: tap ⌘ alone (≤ 200 ms), release, tap again within the configurable window (default 300 ms, range 0.15–0.50 s). Hold the second press to navigate, release to commit. State-machine implementation that's robust against ⌘+key chords held a little long.
- Menu-bar icon for keyboard-less summon and quick access to Settings.

### Identity colour

- Chroma-weighted hue histogram extractor (24 bins) replaces the earlier CIKMeans pipeline. K-means at k=3 collapsed small brand glyphs into white-background clusters; the histogram preserves every chromatic pixel and lets the dominant hue win on its own merit. Handles premultiplied alpha; ignores near-greyscale and near-extreme-lightness pixels.
- OKLCH-space conflict resolver: lower-frequency slots whose extracted hue lands within `360°/N × 0.6` of a previously locked neighbour are pushed by `360°/N × 0.4`, **at most once per resolve pass** so the cascade can't turn a green icon into pink.
- Locked Hue-8 palette is available as a fallback when N=8.
- Per-pinned-app override via a native `ColorPicker` in Settings → Colors.

### Settings

- `NSWindow` + `NSHostingController` Settings panel with five tabs: Behavior / Hotkey / Pins / Colors / About.
- Form-grouped controls (Picker, Toggle, Slider, ColorPicker) per macOS HIG.
- Hotkey tab uses a `KeyCaptureView` to rebind the primary chord live; the displayed key cap is a Liquid Glass surface that tints accent during capture.
- Pins app picker uses `NavigationStack` + `.searchable` in the toolbar, with `Cancel` as a `ToolbarItem(.cancellationAction)` — no hand-rolled search bar.
- Slot pins survive slot-count changes; overflow is preserved and surfaced in a "Hidden pins" section.

### Activation tracking

- 7-day rolling activation log per app, stored in `UserDefaults`.
- Three frequency profiles: MFU-only (count), Balanced (count × recency), MRU-only (timestamp).
- System processes (`loginwindow`, `WindowManager`, `Dock`, `controlcenter`, `systemuiserver`, `notificationcenterui`, `SecurityAgent`, `coreservices.uiagent`, `Spotlight`, `PowerChime`) are filtered out twice: at write time via `NSRunningApplication.activationPolicy == .regular`, and at read time via an explicit blocklist so stale records can't haunt the Top-N.

### Build / distribute

- Pure Swift Package, single `Package.swift`. Deployment target **macOS 12**.
- Ships as a **universal binary** (`arm64` + `x86_64`) via `lipo` inside `scripts/build-app.sh`.
- Settings UI uses macOS-13-and-up APIs (`formStyle(.grouped)`, `NavigationStack`, two-arg `onChange`) where available, with compat shims in `Sources/HaloUI/PlatformCompat.swift` for macOS 12.
- `make app` produces an ad-hoc-signed `dist/Halo.app`.
- `make dist` packages a redistributable zip.
- `make install` copies into `/Applications`.
- Launch-at-login via a generated LaunchAgent `.plist`.

### Permissions

None. No Accessibility, no Input Monitoring, no Full Disk Access. The whole switching loop runs on `NSWorkspace` notifications, Carbon hotkeys, and synchronous `NSEvent.modifierFlags` polling.

### Tests

- 27 unit tests covering: usage store TTL & rollup, switcher launch / activate paths, OKLCH round-trip, identity conflict resolution (single-push cap regression), preference clamping.
