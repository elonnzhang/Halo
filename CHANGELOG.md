# Changelog

All notable changes to Halo.

## [1.2.1] — 2026-05-19

### Fix

- `HoneycombGeometry.resolvedCenter` now pushes the resolved cell centre 0.5pt past the inflated avoid rect rather than landing exactly on its edge. `CGRect.intersects` counts edge-touch as intersecting, so the previous implementation could leave a cell visually flush with the keep-out boundary after `resolvedProjectedCenter`'s fisheye iteration loop converged. The 0.5pt epsilon also absorbs the 0.25pt convergence threshold so post-resolution sub-pixel drift can't pull the rendered cell back onto the boundary. Visually invisible (sub-pixel); fixes 5 `HoneycombGeometryTests` failures that had been blocking the Release CI workflow since v1.2.0.

## [1.2.0] — 2026-05-18

### ALL grid (layer 0 — watchOS-style full-screen launcher)

- New built-in **ALL profile** that opens a full-screen, watchOS-inspired honeycomb of every installed app. Enter by Tab from the wheel's top pill bar (or by clicking the 9-dots pill that prepends the bar when Settings → General → Show ALL profile is on).
- Apps are gathered from `/Applications`, `/System/Applications`, and `~/Applications` (depth-2 recursion), deduped by bundle ID. Scan runs once on first entry inside a `Task.detached`, then publishes on the main actor; subsequent entries reuse the cached catalogue.
- **Usage-ranked sort**: apps are scored by recency × frequency × running-bonus (running apps get a small boost) and rendered in spiral order from the centre out. A stronger-than-desktop fisheye lifts the focal core and compresses the rim — large catalogues read as a single focal constellation, not a uniform sheet.
- **Search**: just start typing. Substring match against name + bundle ID; matched icons pull toward the centre via a search-focused projection. Backspace trims, ESC clears.
- **Keyboard navigation**: arrow keys step the selection through neighbouring hex cells using a spatial nearest-in-direction heuristic, not row-major order — keyboard motion lines up with what the user sees after the fisheye projection. Return / Space / Click launches.
- **Pinch + pan**: trackpad pinch zooms 0.5×–2.5× around the cluster centre; two-finger drag or scroll-wheel pans, with bounds clamped so the last icon's visible edge can't disappear past the viewport.
- **Drop-target visual** during a drag (folders / order tweaks land in a follow-up).
- **Drop-shadow gating during pan/pinch**: per-cell shadows render at radius 0 while a gesture is in flight (auto-clears 120 ms after the last gesture event), so SwiftUI skips the offscreen blur pass on ~60 visible cells at high zoom. Restores full polish within one frame of release.
- ProfileTabBar above the cluster locks to the wheel's pre-grid screen position so toggling between wheel and grid leaves the strip visually still.
- Spec: `docs/superpowers/specs/2026-05-18-halo-launch-and-grid-perf-design.md`.

### Perf instrumentation

- New `HaloCore/PerfSignpost.swift` — thin `OSSignposter` wrapper. Always emits signposts under `com.halo.launcher / perf` (zero cost when nothing is recording in Instruments). Set `HALO_PERF_LOG=1` in the launch env to also write ms-precision lines to `~/Library/Logs/Halo/halo.log` for triage without Xcode.
- Measured sites: `applicationDidFinishLaunching`, `applyPreferences`, `refreshSlots`, `DCE.extract` (per icon), `enterGridMode`, `GridState.scanInstalledApps`, `adaptiveSpiralLayout` (per render).
- On-device baseline (Apple Silicon, fresh launch + first ALL entry): cold launch 116–211 ms total; `refreshSlots` first call 13–72 ms then 2 ms on subsequent calls; `DCE.extract` ≈ 1 ms/icon (not the ~100 ms older code comments assumed); `GridState.scanInstalledApps` ≈ 89 ms off-main; `adaptiveSpiralLayout` median 0.09 ms during a 5-second pan (p99 0.11 ms).

### Render-path tightening

- `AppIconResolver` now caches `NSImage` references in a 256-entry process-lifetime `NSCache` keyed by bundle ID. Repeat lookups across the ~15 call sites (wheel, grid, settings, picker, arc) collapse to a dict hit and reuse the already-decoded bitmap rep.
- `GridState.loadApps` warms the icon cache for the top 80 ordered apps on the same detached task after the scan + sort step, so the first ALL render's `IconCell.task` finds icons already memory-resident.
- `cellFrames = nextFrames` is no longer re-published on `panOffset` or `zoomLevel` changes. The dict is only read by hover-repel (selected bundle's centre) and drag drop-target lookup, both of which read RELATIVE offsets that translate / scale together — a one-frame stale dict is invariant under pure pan or pure zoom. Updating per gesture frame was doubling grid()'s body work via @State invalidation. Refresh now happens only on bundle-list change and onAppear.

### Fixes

- `panelScale` now applies to the ALL grid: icon size, hex spacing, and the ProfileTabBar all scale with the user's Settings → Appearance → Panel size slider. Previously only the wheel honoured it, so flipping to ALL at 1.3× snapped everything back to 1.0×.
- Removed the free-floating `SpecularArc` from the ALL grid's atmosphere layer. The wheel pairs it with a halo rim where it reads as glass reflecting off a known edge; on a full-screen panel with no rim it floated as a stray curve in mid-air. Soft centre `RadialGradient` is retained for focus.
- Honeycomb grid pan constraints + icon spacing pass (watchOS feel): cluster centred without the legacy halo cleanup hack, pan limits derived from the layout bounds rather than a fixed margin.
- Summon-to-slot hover jump fix: synchronous seed of `scrollAnchor` from `lastFrontmostBundleID` no longer writes to `state.phase`, eliminating a 1/60s flash through an unrelated slot before settling on the frontmost app's pinned slot.
- macOS 12 / 13 Settings window close no longer crashes — the legacy `SettingsWindowController` teardown path now matches the macOS 14+ flow.

### Docs

- READMEs (English + Chinese) refreshed and slimmed (197 → 113 lines each). New layered Use section: **Wheel · Action Arc · ALL grid**. v1.1.2 + post-v1.1.2 status callout.
- New `docs/STORAGE.md` consolidating the UserDefaults reference table, diagnostic log layout, reset / uninstall recipes, and the `HALO_PERF_LOG` env var. READMEs link out instead of inlining 90 lines of storage detail.
- New `docs/superpowers/specs/2026-05-18-halo-launch-and-grid-perf-design.md` recording the perf instrumentation + Caches plan and D-list of measurement-driven follow-ups.

## [1.1.2] — 2026-05-15

### Action Arc (二段手势, layer 2)

- Tap **⇧** or right-click (also two-finger tap on trackpad when "Secondary click" is enabled) to open an **Action Arc** — a small fan of 4 chips that pops out from a single app's slot. Layer 1 (the wheel) stays visible underneath. Tap the same trigger again to dismiss; tap on a different slot to re-anchor in one press.
- Fixed chip layout: **Quit · Fullscreen-toggle · Hide · Custom**. Position and colour are stable across every app (red / yellow / blue / green) so the muscle memory carries between contexts.
- Fullscreen reads / writes the focused window's `AXFullScreen` attribute (same path Magnet / Rectangle / Raycast use). Requires Accessibility; the chip dims with a yellow indicator until permission is granted, and the first commit triggers the system trust prompt. The rest of Halo's core path stays AX-free.
- Custom chip is one user-defined action per app. Three kinds:
  - **Keyboard shortcut** — Halo activates the bound app then posts a `CGEvent` for the parsed combo (`cmd+shift+n` / `⌃⌥F` / `F12` etc.). Needs Accessibility.
  - **Run Shortcut** — `shortcuts://run-shortcut?name=…`, no extra permission.
  - **AppleScript** — `NSAppleScript` dispatched off the main thread, so long scripts don't freeze Halo.
- Commit semantics: chip hovered → run chip; otherwise the cursor's slot wins (layer-1 commit dismisses the arc and switches to that app). Empty custom chip → opens Settings → Actions pre-targeted to the bundleID.
- Cursor always lands at Halo's geometric centre on summon, even when the panel is clamped by a screen edge (cursor warp via `CGWarpMouseCursorPosition`).
- New Settings → **Actions** tab: left column lists configured apps, right column shows the chip preview + single-action editor.
- Arc geometry scales with the user's wheel layout (`arcRadius = visibleOuterRadius + 110`). Chip pop-in animation replays on re-anchor.
- Spec: `docs/superpowers/specs/2026-05-14-action-ring-design.md`. Mockup: `mockups/halo-action-arc.html`.

### Animation + Liquid Glass polish

- New **`Sources/HaloUI/Animation+Halo.swift`** centralises every wheel-side ease and spring (`snap` / `echo` / `surface` / `chipPop` / `confirmBounce` + `arcChipStagger`) with a single `reduceMotion` branch. Adjusting the wheel's "feel" is now a one-file change instead of scattered `easeOut(duration:)` calls across `RadialView` / `ActionArcView`.
- **Animation timings tightened**: hover-tracking reactions (sector reveal, slot icon scale, halo glow, key-hint scale) standardised at 100ms (down from 120-140ms). Action Arc chip pop-in spring is now `response 0.30 / damping 0.72` with 22ms stagger (was 0.36 / 0.78 / 30ms) so four chips read as a quick fan-in. Hub icon crossfade uses a single `echo` (140ms easeOut) instead of the default transition.
- **Empty-slot breathing is now lazy**: the dashed `+` placeholder only animates while the cursor is on the wheel; idle Halo no longer drives a `repeatForever` per empty slot. Reduce Motion path stays fully static.
- **Soft-edge anti-aliasing**: introduced `HaloUI.Geometry.softEdgeStart = 0.80` (independent from `visibleOuterFactor = 0.84` which still anchors icons / digit-key hints / Arc geometry) plus a `LegacyAntialiased` modifier wrapping `drawingGroup()` on macOS < 26 (Liquid Glass on 26+ already composites at high quality and the offscreen pass would forfeit content-aware refraction). Combined with merging the wheel disc's double-shadow stack into one (`radius 28 / y 14 / 0.34`), this kills the visible "tire tread" rim stair-stepping in both light and dark mode.
- **`WheelChrome` token tweaks**: `hub-fill` 48 → 32 % (dark) / 16 → 10 % (light); `hub-inner-shadow` 55 → 40 % (dark) / 30 → 22 % (light) so the hub reads as a depression rather than a punched hole. `halo-specular-peak` 78 → 88 % (dark) so the 12-o'clock highlight survives the weight-shadow on OLED backdrops. `slot-idle-stroke` removed entirely; the `slot active` 1.4pt accent stroke removed too — the inner glow blur (4 → 8 pt) carries the "lit from within" reading.
- **Action Arc chip light-mode**: new `ArcChipChrome` mirrors `WheelChrome`'s split. Light mode goes translucent-white glass + neutral grey idle glyphs (so the yellow Fullscreen icon stays legible on a near-white wheel); dark mode keeps the original black glass + accent-tinted glyph reading. Hovered chip still tints the glyph to its accent in both modes.
- **Anchored slot label suppression** (correctness fix): the `labelOverlay` guard was three branches under `@ViewBuilder` + `GlassEffectContainer`'s `glassEffectID` morph, which leaked the anchored slot's label on top of arc chips on macOS 26+ even after its content was gone. Flattened to a single boolean expression. Suppression is now scoped to *only* the anchored slot — hovering a different sector while the arc is up still shows that sector's app name (the user is now reading "what's this neighbour?", and the arc's chips are far enough off-axis to not collide).

### 多 Profile / 场景环 (Apps tab)

- New: **Binding profiles** — named bundles of pinned apps and their identity-colour overrides, switchable from a pill bar at the top of Settings → Apps. Click a pill to switch; click `+` to create (Blank or Clone of active); right-click / long-press for rename / duplicate / delete. Active pill is materialized and accent-bordered.
- Scope is intentionally minimal: a profile owns *pins + overflow + identity overrides only*. **Slot count, frequency profile, whitelist, hotkey, layout, language, sound** — all stay user-global and apply across every profile. The General / Whitelist / About tabs, the sidebar, and the menu bar are unchanged.
- Migration is automatic: existing v1.1.x users see their prior pins / overrides under a single `Default` profile on first launch. Legacy `UserDefaults` keys (`pinnedSlots.v1` / `overflowPins.v1` / `identityOverride.v1`) are kept as a rollback safety net through the next minor and removed afterwards.
- The global `slotCount` setter resizes the active profile's pin array in-line so overflow behaviour is identical to v1.1. Inactive profiles keep their previous pin-array length and lazily realign on next mutation.
- 19 new tests (`BindingProfileTests` + `AppPreferencesProfileTests`). Existing `AppPreferencesTests` (12/12) and `AppPreferencesBoundsTests` pass unchanged. Total suite 115/115.

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
