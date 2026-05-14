# Changelog

All notable changes to Halo.

## [1.1.0] — Unreleased

### Settings panel

- Rebuilt around a sidebar (General / Apps / Whitelist / About). 720×620 fixed window, matches `mockups/halo-settings.html`. Replaces the v1.0 `TabView` shell.
- General → Navigation: scroll-to-switch-slots / digit-key commit (now via keyCode table covering `1–9 0 - =`) / highlight-frontmost-on-summon.
- General → Appearance: `Panel size` slider applies a renderer-time scale (0.80–1.50x) to the whole wheel; live hit-test divides cursor offset by the scale.
- General → Trigger: double-tap picker now offers five keys (⌥ Left, ⌥ Right, ⌘, ⌃, Mouse 3 Middle). State machine moved into `DoubleTapMonitor`; the keyboard path uses `flagsChanged` with keyCode discrimination (kVK 58/61/54/55/59/62) since `NSEvent.ModifierFlags` doesn't expose a stable left/right bit. `CommandLongPressMonitor` removed.

### Whitelist (new)

- New `Whitelist` tab + preference key `halo.prefs.whitelist.v1` (`[String]` of bundle IDs). When the frontmost app is whitelisted, both `HaloHotkey` and `DoubleTapMonitor` short-circuit before firing — Halo is silent in that app.
- `WhitelistSuggestions.installedSubset()` seeds Xcode / VS Code family / JetBrains / Figma / Sketch / Adobe / Blender / Unity / Roblox Studio / Parallels / VMware / Microsoft RDC — only apps actually installed get included via `NSWorkspace.urlForApplication`.

### Localization

- en + zh-Hans translations added for every new section (sidebar, navigation toggles, trigger picker, panel size, whitelist UI, DoubleTapTrigger labels).

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
