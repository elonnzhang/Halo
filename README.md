# Halo

A radial app launcher for macOS, inspired by the colour-wheel mechanic of the puzzle game *Hue*. Switch between your most-used apps with a single gesture: press the hotkey, point a direction, release.

Single, self-contained macOS app. **No Accessibility permission** required for the core switching loop.

## Status

**v1.0** — first public release. Full Liquid Glass HUD on macOS 26, NSVisualEffectView fallback on macOS 14/15. Double-tap ⌘ second-trigger. Chroma-weighted hue histogram identity colour extraction. See [CHANGELOG.md](CHANGELOG.md).

## Install

Requires macOS 14 (Sonoma) or later. The Liquid Glass surfaces light up on macOS 26 (Tahoe).

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

## Language

Primary working language for the spec docs is Chinese. English mirrors come once the implementation has soaked in.

## License

MIT — see [LICENSE](LICENSE).
