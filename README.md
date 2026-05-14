# Halo

A radial app launcher for macOS, inspired by the colour-wheel mechanic of the puzzle game *Hue*. Switch between your most-used apps with a single gesture: press the hotkey, point a direction, release.

Single, self-contained macOS app. **No Accessibility permission** required for the core switching loop.

[中文 README](README_zh.md)

## Status

**v1.1** (2026-05-14) — Settings panel rebuilt around native `NavigationSplitView` + `Form(.grouped)`; five-way double-tap trigger picker (⌥ Left / ⌥ Right / ⌘ / ⌃ / Mouse 3); new Whitelist tab that suppresses Halo inside chosen apps; panel-size renderer scale (0.80–1.50×); scroll-wheel slot cycling; full Liquid Glass on macOS 26. Async `Switcher` outcome so corrupt bundles shake-and-fail instead of silently vanishing. See [CHANGELOG.md](CHANGELOG.md).

## Install

Requires **macOS 12 (Monterey) or later**. Ships as a **universal binary** (Apple Silicon + Intel). The Liquid Glass surfaces light up on macOS 26 (Tahoe); macOS 12 / 13 / 14 / 15 fall back to `NSVisualEffectView` with the same visual recipe.

```sh
make install      # release-build + ad-hoc sign + copy into /Applications
open /Applications/Halo.app
```

Or build the redistributable zip:

```sh
make dist         # produces dist/Halo-v1.1.0.zip (or whatever Info.plist's CFBundleShortVersionString says)
```

## Use

1. **Press `⌘ ⌥ Space`** (or double-tap `⌘` alone) to summon Halo at the cursor.
2. **Move the cursor** — or press a direction / digit key — to highlight a slot.
3. **Release the hotkey** — or click / press `Return` — to switch. `ESC` cancels.
4. **Menu-bar icon** for keyboard-less summon and Settings.

The top **N** slots (configurable 4 / 6 / 8 / 10 / 12) are filled by the apps you've activated most in the last 7 days. Frequency profile (MFU-only / Balanced / MRU-only) is tunable from Settings. Pin a specific app to a slot, or override its identity colour, from the Pins / Colours tabs.

## Settings (menu bar → Settings…)

Four sections in a native sidebar (`NavigationSplitView` on macOS 13+, custom HStack on macOS 12). Resizable 880 × 720 default, 760 × 600 minimum.

- **General**
  - *Summon position & ranking* — slot count (4 / 6 / 8 / 10 / 12), at-cursor vs screen-center, frequency profile (MFU / Balanced / MRU).
  - *Trigger* — rebind the primary chord live (Liquid Glass key cap on macOS 26); pick the double-tap auxiliary key (⌥ Left / ⌥ Right / ⌘ / ⌃ / Mouse 3 Middle); tune the gap window (0.15–0.50 s).
  - *Navigation* — toggles for scroll-wheel slot cycling, digit-key commit (1–9, 0, −, =), and seeding the highlighted slot from the previous frontmost app.
  - *Appearance & wheel layout* — **Panel size** renderer scale (0.80–1.50×) plus the three base sliders (Halo diameter, icon size, icon distance) and a reset.
  - *Startup & diagnostics* — autostart, replay welcome, reset onboarding, export diagnostic log.
  - *Language* — system / English / 简体中文 (restart required).
- **Apps** — pin specific apps to specific slots via the binding wheel; per-slot popover for identity-colour override / clear. Pins survive slot-count changes (overflow preserved).
- **Whitelist** — list of bundle IDs where Halo's chord + double-tap are suppressed (IDEs, design tools, remote desktop, games). "Apply recommended" seeds from `WhitelistSuggestions.installedSubset()`. Carbon registration stays installed so the chord never leaks to other apps mid-session.
- **About** — gradient app-icon badge, version, GitHub / License links, runtime metadata, inline diagnostic-log export.

## Develop

```sh
make build        # debug build
make test         # 88 unit tests across HaloCoreTests + HaloUITests
make app          # produce dist/Halo.app (release, ad-hoc signed)
make clean        # remove .build and dist
```

## Project layout

```
Sources/HaloCore        UI-free core: engine, usage store, AppRuntime / Switcher, OKLCH, prefs, SlotCycle, WhitelistSuggestions
Sources/HaloUI          SwiftUI views + Carbon hotkey + DoubleTapMonitor + NSPanel + NSWorkspaceRuntime
Sources/HaloApp         AppDelegate, Settings window (NavigationSplitView), Whitelist tab, Pin picker, LaunchAgent
Tests/HaloCoreTests     Pure logic: engine, store, switcher, OKLCH, prefs, SlotCycle, whitelist, AppPreferences bounds
Tests/HaloUITests       View-layer: RadialGeometry hit-test, HaloState transitions, DoubleTapMonitor state machine, scrollAnchor lifecycle
Resources/              Info.plist, *.lproj/Localizable.strings (en + zh-Hans), Halo.icns, Halo.iconset
scripts/                build-app.sh, render-icon.swift
docs/                   Product / interaction / visual / settings specs (Chinese, v1.1 stamps inline)
mockups/                Clickable UI mockups — halo.html (live wheel), halo-settings.html, halo-redesign.html
```

## Docs

- [产品设计 / Product design](docs/PRODUCT.md)
- [交互规格 / Interaction spec](docs/INTERACTION.md)
- [视觉规格 / Visual spec](docs/VISUAL.md)
- [CHANGELOG.md](CHANGELOG.md)

## Permissions

The **primary chord** (`⌘⌥ Space`) needs **no Accessibility permission** — Carbon `RegisterEventHotKey` works without it. Activation tracking uses `NSWorkspace` notifications; switching uses `NSWorkspace.openApplication` (cooperative activation on macOS 14+).

The **double-tap auxiliary trigger** (⌥ / ⌘ / ⌃ / Mouse 3) does need **Accessibility permission** because it listens to global `NSEvent.flagsChanged` / `.otherMouseDown`. Halo probes `AXIsProcessTrusted()` on launch and surfaces a one-shot alert with a deep link to System Settings if access is denied. The chord path keeps working either way.

## Language

Display language is settable in **Settings → General → Language** (System / English / 简体中文). Restart required to apply.

## Data & privacy

Halo runs **entirely on-device**. No network calls, no telemetry, no analytics, nothing sent to any third party. The Settings → General → "Export diagnostic log…" button is the only path that ever surfaces local data, and even then it only writes a file to `~/Downloads/` for you to manually share if you want.

### What's stored, and where

All paths assume the current user.

**User defaults — `~/Library/Preferences/com.halo.launcher.plist`** (managed by macOS, written via `UserDefaults`):

| Key | Type | What it holds |
|---|---|---|
| `halo.prefs.slotCount` | Int | Configured slot count (4 / 6 / 8 / 10 / 12) |
| `halo.prefs.profile` | String | Frequency profile (`mfuOnly` / `balanced` / `mruOnly`) |
| `halo.prefs.summonPosition` | String | `mouse` or `center` |
| `halo.prefs.hotkey.keyCode` | Int | Primary hotkey key code |
| `halo.prefs.hotkey.mods` | Int | Primary hotkey modifier bitmask |
| `halo.prefs.cmdDoubleTapGap` | Double | Double-tap ⌘ window, seconds |
| `halo.prefs.cmdHoldDuration` | Double | Legacy long-press duration (retained for migration only) |
| `halo.prefs.autostart` | Bool | Whether the LaunchAgent is installed |
| `halo.prefs.languageOverride` | String? | `nil` = follow system, or `"en"` / `"zh-Hans"` |
| `AppleLanguages` | [String] | Mirrored from `languageOverride` (system-recognised key) so Foundation picks up the override on next launch |
| `halo.prefs.doubleTapTrigger` | String | One of `leftOption` / `rightOption` / `command` / `control` / `middleMouse` |
| `halo.prefs.scrollToSwitch` | Bool | Scroll-wheel cycles highlighted slot |
| `halo.prefs.numberKeyCommit` | Bool | Digit keys 1–9 0 - = commit a slot directly |
| `halo.prefs.highlightFrontmostOnSummon` | Bool | First scroll-tick lands on the previous frontmost app's pinned slot |
| `halo.prefs.layout.hudDiameter` | Double | Halo outer diameter, 280–440 pt (legacy storage key) |
| `halo.prefs.layout.iconSize` | Double | Slot icon size, 36–64 pt |
| `halo.prefs.layout.iconRadius` | Double | Icon-to-center distance, bounded by hub + outer fade |
| `halo.prefs.layout.panelScale` | Double | Renderer-time uniform scale, 0.80–1.50× |
| `halo.prefs.pinnedSlots.v1` | Data (JSON) | `[String?]` — bundle ID pinned to each slot, indexed by slot |
| `halo.prefs.overflowPins.v1` | Data (JSON) | `[String]` — pins that don't fit the current slot count |
| `halo.prefs.identityOverride.v1` | Data (JSON) | `{ bundleID → OKLCH }` — per-app identity colour override |
| `halo.prefs.whitelist.v1` | Data (JSON) | `[String]` — bundle IDs where Halo's triggers are suppressed |
| `halo.usage.v1` | Data (JSON) | **Rolling 7-day activation log.** For each app the user has switched to: bundle ID, display name, and an array of activation timestamps. Pruned on every write (no longer grows unbounded). |
| `halo.welcome.shown` | Bool | First-launch welcome overlay has been seen |
| `halo.onboarding.shown` | Bool | First-summon Halo tip has been seen |

**Diagnostic log — `~/Library/Logs/Halo/`**:

| File | Contents |
|---|---|
| `halo.log` | Plain-text activity log (current). ISO-8601 timestamps + category + message — hotkey registrations, Halo summon / commit / cancel, switcher results, identity-colour extraction, settings mutations, onboarding events. **Includes bundle identifiers of the apps you switch to.** No app contents, no keystrokes, no window titles, no screenshots. |
| `halo.log.1` | Rotated previous file (rolls over at 5 MB). |

**LaunchAgent — `~/Library/LaunchAgents/com.halo.launcher.plist`** (only when "Launch Halo at login" is enabled):

Standard launchd plist pointing at `/Applications/Halo.app/Contents/MacOS/Halo`. Written by `LaunchAgentManager`; removed when you disable autostart.

### What is **not** recorded

- Keystrokes outside Halo's own hotkey monitor (no keylogger)
- Window titles or document names
- Screen contents, screenshots, accessibility-tree data
- Network activity (Halo makes none)
- Timing or duration of how long you stayed in an app — only the moment of activation
- The contents of any app — Halo only sees that you switched to a bundle ID

### Reset to a first-launch state

For testing the new-user flow or recovering from corrupted state:

```sh
# Stop Halo
killall Halo

# Wipe transient state (onboarding flags + 7-day usage log + pins + overrides + diagnostic log).
# Leaves slot count, hotkey binding, language, autostart untouched.
defaults delete com.halo.launcher halo.welcome.shown
defaults delete com.halo.launcher halo.onboarding.shown
defaults delete com.halo.launcher halo.usage.v1
defaults delete com.halo.launcher halo.prefs.pinnedSlots.v1
defaults delete com.halo.launcher halo.prefs.overflowPins.v1
defaults delete com.halo.launcher halo.prefs.identityOverride.v1
rm -f ~/Library/Logs/Halo/halo.log ~/Library/Logs/Halo/halo.log.1

open /Applications/Halo.app
```

### Full uninstall (every byte Halo wrote)

```sh
killall Halo
rm -rf /Applications/Halo.app
defaults delete com.halo.launcher
rm -rf ~/Library/Logs/Halo
rm -f  ~/Library/LaunchAgents/com.halo.launcher.plist
```

### Inspecting the log live (developer)

```sh
# Follow our text log
tail -F ~/Library/Logs/Halo/halo.log

# Or via the unified-logging stream (Console.app filter shortcut)
log stream --predicate 'subsystem == "com.halo.launcher"' --level debug
```

Settings → General → **Export diagnostic log…** bundles `halo.log` + `halo.log.1` plus a header (Halo version, macOS version, hardware model) into `~/Downloads/Halo-diagnostic-<timestamp>.log` for sharing on a bug report.

## Spec docs

Primary working language for the spec docs (`docs/PRODUCT.md`, `docs/INTERACTION.md`, `docs/VISUAL.md`, `docs/SETTING.md`) is Chinese. The READMEs are bilingual. See [v1.1 status banners](docs/SETTING.md) inline in each spec for what has shipped vs. what is still roadmap.

## License

MIT — see [LICENSE](LICENSE).
