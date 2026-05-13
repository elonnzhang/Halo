# Halo

A radial app launcher for macOS, inspired by the colour-wheel mechanic of the puzzle game *Hue*. Switch between your most-used apps with a single gesture: press the hotkey, point a direction, release.

Single, self-contained macOS app. **No Accessibility permission** required for the core switching loop.

## Status

**v1.0** — first public release. Full Liquid Glass HUD on macOS 26, NSVisualEffectView fallback on macOS 14/15. Double-tap ⌘ second-trigger. Chroma-weighted hue histogram identity colour extraction. See [CHANGELOG.md](CHANGELOG.md).

## Install

Requires **macOS 12 (Monterey) or later**. Ships as a **universal binary** (Apple Silicon + Intel). The Liquid Glass surfaces light up on macOS 26 (Tahoe); macOS 12 / 13 / 14 / 15 fall back to `NSVisualEffectView` with the same visual recipe.

```sh
make install      # release-build + ad-hoc sign + copy into /Applications
open /Applications/Halo.app
```

Or build the redistributable zip:

```sh
make dist         # produces dist/Halo-v1.0.0.zip
```

## Use

1. **Press `⌘⌥Space`** (or double-tap `⌘` alone) to summon the HUD at the cursor.
2. **Move the cursor** — or press a direction / digit key — to highlight a slot.
3. **Release the hotkey** — or click / press `Return` — to switch. `ESC` cancels.
4. **Menu-bar icon** for keyboard-less summon and Settings.

The top **N** slots (configurable 4 / 6 / 8 / 10 / 12) are filled by the apps you've activated most in the last 7 days. Frequency profile (MFU-only / Balanced / MRU-only) is tunable from Settings. Pin a specific app to a slot, or override its identity colour, from the Pins / Colours tabs.

## Settings (menu bar → Settings…)

- **Behavior** — slot count, frequency profile, summon position, autostart, reset onboarding.
- **Hotkey** — rebind the primary chord live (Liquid Glass key cap), or tune the double-tap ⌘ window (0.15–0.50 s).
- **Pins** — lock specific apps to specific slots. App picker uses a native `.searchable` toolbar field. Pins survive slot-count changes.
- **Colors** — per-pinned-app identity colour override.
- **About** — version.

## Develop

```sh
make build        # debug build
make test         # 27 unit tests (engine, store, switcher, OKLCH math, prefs, conflict resolver)
make app          # produce dist/Halo.app (release, ad-hoc signed)
make clean        # remove .build and dist
```

## Project layout

```
Sources/HaloCore        UI-free core: engine, usage store, switcher, OKLCH, prefs
Sources/HaloUI          SwiftUI views + Carbon hotkey + transparent NSPanel
Sources/HaloApp         AppDelegate, Settings window, Pin picker, LaunchAgent
Tests/HaloCoreTests     27 unit tests
Resources/              Info.plist, Halo.icns, Halo.iconset
scripts/                build-app.sh, render-icon.swift
docs/                   Product / interaction / visual specs (Chinese)
mockups/halo.html       Single-file clickable UI mockup
```

## Docs

- [产品设计 / Product design](docs/PRODUCT.md)
- [交互规格 / Interaction spec](docs/INTERACTION.md)
- [视觉规格 / Visual spec](docs/VISUAL.md)
- [CHANGELOG.md](CHANGELOG.md)

## Permissions

Halo needs **no Accessibility permission**. Activation tracking uses `NSWorkspace` notifications; switching uses `NSWorkspace.activate` / `openApplication`; hotkeys use Carbon `RegisterEventHotKey` and `NSEvent.modifierFlags` polling. No event taps, no accessibility tree reads.

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
| `halo.prefs.pinnedSlots.v1` | Data (JSON) | `[String?]` — bundle ID pinned to each slot, indexed by slot |
| `halo.prefs.overflowPins.v1` | Data (JSON) | `[String]` — pins that don't fit the current slot count |
| `halo.prefs.identityOverride.v1` | Data (JSON) | `{ bundleID → OKLCH }` — per-app identity colour override |
| `halo.usage.v1` | Data (JSON) | **Rolling 7-day activation log.** For each app the user has switched to: bundle ID, display name, and an array of activation timestamps. Older than 7 days are dropped on read. |
| `halo.welcome.shown` | Bool | First-launch welcome overlay has been seen |
| `halo.onboarding.shown` | Bool | First-summon HUD tip has been seen |

**Diagnostic log — `~/Library/Logs/Halo/`**:

| File | Contents |
|---|---|
| `halo.log` | Plain-text activity log (current). ISO-8601 timestamps + category + message — hotkey registrations, HUD summon / commit / cancel, switcher results, identity-colour extraction, settings mutations, onboarding events. **Includes bundle identifiers of the apps you switch to.** No app contents, no keystrokes, no window titles, no screenshots. |
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

## Language

Primary working language for the spec docs is Chinese. English mirrors come once the implementation has soaked in.

## License

MIT — see [LICENSE](LICENSE).
