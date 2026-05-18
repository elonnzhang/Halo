# Halo storage reference

Where Halo writes on disk and how to wipe it. All paths assume the current user.

## User defaults

`~/Library/Preferences/com.halo.launcher.plist`, written via `UserDefaults`.

| Key | Type | What it holds |
|---|---|---|
| `halo.prefs.slotCount` | Int | Configured slot count (4 / 6 / 8 / 10 / 12) |
| `halo.prefs.profile` | String | Frequency profile (`mfuOnly` / `balanced` / `mruOnly`) |
| `halo.prefs.summonPosition` | String | `mouse` or `center` |
| `halo.prefs.hotkey.keyCode` | Int | Primary hotkey key code |
| `halo.prefs.hotkey.mods` | Int | Primary hotkey modifier bitmask |
| `halo.prefs.cmdDoubleTapGap` | Double | Double-tap window, seconds |
| `halo.prefs.cmdHoldDuration` | Double | Legacy long-press duration (migration only) |
| `halo.prefs.autostart` | Bool | LaunchAgent installed |
| `halo.prefs.languageOverride` | String? | `nil` = follow system, or `"en"` / `"zh-Hans"` |
| `AppleLanguages` | [String] | Mirrored from `languageOverride` so Foundation picks up the override on next launch |
| `halo.prefs.doubleTapTrigger` | String | `leftOption` / `rightOption` / `command` / `control` / `middleMouse` |
| `halo.prefs.scrollToSwitch` | Bool | Scroll-wheel cycles highlighted slot |
| `halo.prefs.numberKeyCommit` | Bool | Digit keys 1–9 0 - = commit a slot directly |
| `halo.prefs.highlightFrontmostOnSummon` | Bool | First scroll-tick lands on the previous frontmost app's slot |
| `halo.prefs.showAllProfile` | Bool | Show the built-in ALL pill that opens the honeycomb grid |
| `halo.prefs.layout.hudDiameter` | Double | Halo outer diameter, 280–440 pt (legacy key) |
| `halo.prefs.layout.iconSize` | Double | Slot icon size, 36–64 pt |
| `halo.prefs.layout.iconRadius` | Double | Icon-to-center distance |
| `halo.prefs.layout.panelScale` | Double | Renderer-time uniform scale, 0.80–1.50× |
| `halo.prefs.pinnedSlots.v1` | Data (JSON) | `[String?]` — bundle ID pinned per slot |
| `halo.prefs.overflowPins.v1` | Data (JSON) | `[String]` — pins that don't fit the current slot count |
| `halo.prefs.identityOverride.v1` | Data (JSON) | `{ bundleID → OKLCH }` — per-app identity colour override |
| `halo.prefs.whitelist.v1` | Data (JSON) | `[String]` — bundle IDs where Halo's triggers are suppressed |
| `halo.prefs.profiles.v1` | Data (JSON) | Binding profiles (pins + overrides per named profile) |
| `halo.prefs.actions.v1` | Data (JSON) | Per-app Action Arc custom actions |
| `halo.usage.v1` | Data (JSON) | Rolling 7-day activation log, pruned on every write |
| `halo.welcome.shown` | Bool | First-launch welcome overlay seen |
| `halo.onboarding.shown` | Bool | First-summon Halo tip seen |

## Diagnostic log

`~/Library/Logs/Halo/`:

| File | Contents |
|---|---|
| `halo.log` | Plain-text activity log. ISO-8601 timestamp + category + message — hotkey registrations, summon / commit / cancel, switcher results, identity-colour extraction, settings mutations. Includes bundle identifiers of the apps you switch to. No app contents, keystrokes, window titles, or screenshots. |
| `halo.log.1` | Rotated previous file (rolls over at 5 MB). |

## LaunchAgent

`~/Library/LaunchAgents/com.halo.launcher.plist` — only present when **Launch Halo at login** is enabled. Standard launchd plist pointing at `/Applications/Halo.app/Contents/MacOS/Halo`. Written by `LaunchAgentManager`; removed when you disable autostart.

## What is NOT recorded

- Keystrokes outside Halo's own hotkey monitor
- Window titles or document names
- Screen contents, screenshots, accessibility-tree data
- Network activity (Halo makes none)
- Timing or duration in an app — only the moment of activation

## Reset to first-launch state

Leaves slot count / hotkey / language / autostart untouched; wipes onboarding flags, usage log, pins, overrides, diagnostic log.

```sh
killall Halo
defaults delete com.halo.launcher halo.welcome.shown
defaults delete com.halo.launcher halo.onboarding.shown
defaults delete com.halo.launcher halo.usage.v1
defaults delete com.halo.launcher halo.prefs.pinnedSlots.v1
defaults delete com.halo.launcher halo.prefs.overflowPins.v1
defaults delete com.halo.launcher halo.prefs.identityOverride.v1
rm -f ~/Library/Logs/Halo/halo.log ~/Library/Logs/Halo/halo.log.1
open /Applications/Halo.app
```

## Full uninstall

```sh
killall Halo
rm -rf /Applications/Halo.app
defaults delete com.halo.launcher
rm -rf ~/Library/Logs/Halo
rm -f  ~/Library/LaunchAgents/com.halo.launcher.plist
```

## Live log inspection

```sh
tail -F ~/Library/Logs/Halo/halo.log
log stream --predicate 'subsystem == "com.halo.launcher"' --level debug
```

**Settings → General → Export diagnostic log…** bundles `halo.log` + `halo.log.1` plus a header (Halo version, macOS version, hardware model) into `~/Downloads/Halo-diagnostic-<timestamp>.log` for sharing on a bug report.

## Perf instrumentation

Halo ships with an `OSSignposter`-based perf layer (`HaloCore/PerfSignpost.swift`) under the `com.halo.launcher / perf` category. Always emits signposts (zero-cost when nobody is recording). Set `HALO_PERF_LOG=1` in the launch environment to also write ms-precision timings to `halo.log`:

```sh
HALO_PERF_LOG=1 /Applications/Halo.app/Contents/MacOS/Halo
```

Measured sites: `applicationDidFinishLaunching`, `applyPreferences`, `refreshSlots`, `DCE.extract`, `enterGridMode`, `GridState.scanInstalledApps`, `adaptiveSpiralLayout`.
