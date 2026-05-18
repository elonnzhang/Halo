# Halo

A radial app launcher for macOS, inspired by the colour-wheel mechanic of the puzzle game *Hue*. Switch between your most-used apps with a single gesture: press the hotkey, point a direction, release.

Single, self-contained macOS app. **No Accessibility permission** required for the core switching loop.

[中文 README](README_zh.md) · [CHANGELOG](CHANGELOG.md)

## Status

**v1.1.2** (2026-05-15) — Action Arc (⇧ / right-click to open a 4-chip fan: Quit / Fullscreen / Hide / Custom). Multi-profile pins (named pin bundles, switchable from a top pill bar). Settings rebuilt around `NavigationSplitView`. Whitelist tab. Panel-size renderer scale (0.80–1.50×). Scroll-wheel slot cycling. Full Liquid Glass on macOS 26.

Post-v1.1.2 on `main`: watchOS-style ALL grid (see [Use](#use) below), `panelScale` now applies to the ALL grid, `OSSignposter` perf instrumentation, icon NSCache + grid prefetch, pan/zoom shadow gating.

## Install

Requires **macOS 12 (Monterey) or later**. Universal binary (Apple Silicon + Intel). Liquid Glass surfaces light up on macOS 26 (Tahoe); older macOS falls back to `NSVisualEffectView` with the same recipe.

```sh
make install           # release build + ad-hoc sign + copy into /Applications
open /Applications/Halo.app
```

Or build a redistributable zip:

```sh
make dist              # produces dist/Halo-vX.Y.Z.zip (version from Info.plist)
```

## Use

### Wheel (layer 1)

1. Press **`⌘ ⌥ Space`** (or double-tap your configured trigger — ⌥L / ⌥R / ⌘ / ⌃ / Mouse 3).
2. Move the cursor — or press an arrow / digit key — to highlight a slot.
3. Release the hotkey — or click / press `Return` — to switch. `ESC` cancels.

The top **N** slots (4 / 6 / 8 / 10 / 12) are filled by the apps you've activated most in the last 7 days. Frequency profile (MFU / Balanced / MRU) is tunable from Settings. Pin a specific app to a slot or override its identity colour from Settings → Apps.

### Action Arc (layer 2)

While the wheel is summoned, tap **⇧** or right-click to fan out four chips around the slot under the cursor: **Quit · Fullscreen · Hide · Custom**. Hover a chip and release the trigger to run it; click anywhere else to dismiss. The custom chip is one user-defined action per app (keyboard shortcut, Run Shortcut, or AppleScript), edited under Settings → Actions.

Fullscreen / keyboard-shortcut chips require Accessibility; the chip dims with a yellow indicator until granted. The rest of Halo stays AX-free.

### ALL grid (layer 0)

A full-screen watchOS-style honeycomb of every installed app, for when the wheel's top-N isn't enough.

- **Enter** — Tab to the ALL profile while the wheel is up, or click the 9-dots pill at the top of the wheel.
- **Search** — start typing. Substring match against name + bundle ID; matched icons pull toward the centre via a fisheye projection.
- **Navigate** — arrow keys step the keyboard selection through neighbouring cells; cursor hover does the same.
- **Launch** — `Return` / `Space` / click; or release the hotkey on a hovered icon.
- **Zoom** — trackpad pinch (0.5×–2.5×).
- **Pan** — trackpad two-finger drag, or scroll-wheel.
- **Cancel** — `ESC`.

Apps are ranked by usage (most-used cluster near the centre, with the focal core enlarged via fisheye). Toggle the ALL pill on/off under Settings → General → Show ALL profile.

### Menu bar

Click the menu-bar item for keyboard-less summon, profile switching, or Settings.

## Settings (menu bar → Settings…)

Five sections in a native sidebar (`NavigationSplitView` on macOS 13+, custom HStack on macOS 12). Default 880 × 720, min 760 × 600, resizable.

- **General** — slot count, summon position, frequency profile, primary chord, double-tap trigger, scroll-wheel toggle, digit-key commit, frontmost-on-summon, ALL profile toggle, panel size, language, autostart, diagnostics export.
- **Apps** — pin apps to slots via a binding wheel; per-slot popover for identity-colour override. Top pill bar switches between named **profiles** (separate pin sets, sharing all other settings).
- **Actions** — per-app custom chip for the Action Arc (keyboard shortcut / Run Shortcut / AppleScript).
- **Whitelist** — bundle IDs where Halo's triggers are suppressed (IDEs, design tools, remote desktop, games). "Apply recommended" seeds from installed apps in a curated list.
- **About** — version, GitHub / License links, runtime metadata, diagnostic-log export.

Spec docs: [产品设计](docs/PRODUCT.md) · [交互规格](docs/INTERACTION.md) · [视觉规格](docs/VISUAL.md) · [设置规格](docs/SETTING.md). Working language is Chinese.

## Develop

```sh
make build             # debug build
make test              # unit tests across HaloCoreTests + HaloUITests
make app               # produce dist/Halo.app (release, ad-hoc signed)
make clean             # remove .build and dist
```

## Project layout

```
Sources/HaloCore        UI-free core: engine, usage store, OKLCH, prefs, profiles, actions, perf signpost
Sources/HaloUI          SwiftUI views + Carbon hotkey + DoubleTapMonitor + grid + arc + NSPanel
Sources/HaloApp         AppDelegate, Settings window, tabs, Pin picker, LaunchAgent
Tests/Halo{Core,UI}Tests  Pure logic + view-layer geometry / state tests
Resources/              Info.plist, *.lproj/Localizable.strings (en + zh-Hans), Halo.icns
scripts/                build-app.sh, render-icon.swift
docs/                   Product / interaction / visual / settings specs (Chinese)
```

## Permissions

Halo's core switching needs **no Accessibility permission**. Both trigger paths are passive state queries: Carbon `RegisterEventHotKey` for the primary chord; `CGEventSource.keyState` and `NSEvent.pressedMouseButtons` polling for the double-tap auxiliary. Activation tracking uses `NSWorkspace` notifications. No event taps, accessibility-tree reads, or input monitoring.

Accessibility is requested only when you commit an Action Arc chip that needs it (Fullscreen toggle, custom keyboard shortcut). The chip is dimmed with a yellow indicator until permission is granted.

## Data & privacy

Halo runs **entirely on-device**. No network calls, no telemetry, no analytics. The only path that surfaces local data is Settings → General → **Export diagnostic log…**, which writes a file to `~/Downloads/` for you to share manually.

What's stored: user defaults under `com.halo.launcher` (slot config, hotkey, pins, overrides, profiles, custom actions, 7-day usage log), a text activity log under `~/Library/Logs/Halo/`, and a LaunchAgent plist when autostart is on. The activity log includes bundle identifiers of apps you switch to — no app contents, no keystrokes, no window titles, no screenshots.

Full storage breakdown, reset and uninstall recipes, perf instrumentation env var: [docs/STORAGE.md](docs/STORAGE.md).

## License

MIT — see [LICENSE](LICENSE).
