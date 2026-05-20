# Halo — Project Contract

## WHO YOU ARE

You are a collaborating developer on Halo — a single-binary macOS radial app launcher built on Swift 6 / SwiftPM / SwiftUI with a Carbon hotkey. The core switching loop is Accessibility-free, fully on-device, with no network and no telemetry. Working language with the user is Chinese; keep code, paths, and tool output in their original English.

<IMPORTANT>
Prefix your first line with 🍃 inline, not as its own paragraph.</IMPORTANT>

## Build And Test

Toolchain: Xcode 26.x + Swift 6 (CI runs on `macos-26`). There is no npm, no separate lint/typecheck step — the Swift compiler is the type checker.

- Build:   `make build`            # debug build (`swift build`)
- Test:    `make test`             # HaloCoreTests + HaloUITests (`swift test`)
- App:     `make app`              # release build → universal binary → assemble `dist/Halo.app` → ad-hoc sign
- Run:     `make run`              # equivalent to `make app && open dist/Halo.app`
- Install: `make install`          # copy `dist/Halo.app` into `/Applications/`
- Dist:    `make dist`             # package `dist/Halo-vX.Y.Z.zip` + sha256 (version read from `Resources/Info.plist`)
- Release: `HALO_SIGNING_IDENTITY=… make release`  # clean + test + app + notarize + staple (requires notarytool profile `halo-notary`)
- Icon:    `make icon`             # rebuild `Resources/Halo.icns` via `scripts/render-icon.swift`
- Clean:   `make clean`            # remove `.build` and `dist`

## Architecture Boundaries

Three SwiftPM targets with a strict, one-way dependency direction (see `Package.swift`):

- `Sources/HaloCore` — **UI-free kernel**: engine (HaloEngine / Switcher / SlotCycle), usage stats (UsageStore), preferences and binding profiles (AppPreferences / BindingProfile), action execution (ActionExecutor / ArcExecutor / HaloAction / BuiltInAction), double-tap trigger (DoubleTapTrigger), OKLCH colour extraction (DominantColorExtractor / IdentityColor), logging and signposting (HaloLog / DiagnosticLog / PerfSignpost). **Do not import AppKit / SwiftUI / Carbon.**
- `Sources/HaloUI`   — SwiftUI views, geometry, and state: Wheel (RadialGeometry / RadialView), ALL grid (HoneycombGeometry / HoneycombGridView / GridState / HaloGridWindow), Action Arc (ActionArcGeometry / ActionArcView), hotkey (HaloHotkey via Carbon `RegisterEventHotKey`), DoubleTapMonitor, NSPanel (HaloWindow), menu bar (MenuBarController), AX gates (AXPermissionGate / FullScreenToggler), Liquid Glass / VisualEffect. May depend on HaloCore.
- `Sources/HaloApp`  — Executable entry point and Settings: `main.swift`, AppDelegate, SettingsWindow, the five tabs (General / Apps + BindingWheel / Actions / Whitelist / About), PinPickerWindow, WelcomeWindow, LaunchAgentManager. **Resources are processed only on the HaloApp target** (Info.plist, `*.lproj/Localizable.strings`, Halo.icns).

Tests: `Tests/HaloCoreTests` (pure logic — engine / profiles / usage / actions / whitelist) and `Tests/HaloUITests` (view-layer geometry and state — RadialGeometry / HoneycombGeometry / HaloState / IconResolverCache).

See `docs/PRODUCT.md` / `docs/INTERACTION.md` / `docs/VISUAL.md` / `docs/SETTING.md`.


## Workflow (IMPORTANT)

1. When you receive a task, restate your understanding in Chinese, list a plan, and **wait for my confirmation** before starting.
2. Change only one concern at a time; do not opportunistically clean up unrelated code or styling.
3. After changes, run the verification commands below. For UI / interaction changes you must `make app` and then `open dist/Halo.app` **yourself** (in a worktree, open the worktree's `dist/Halo.app`, not `/Applications/Halo.app`) and walk through the golden path before declaring the task done.
4. Write the post-change review under the project's existing convention: `docs/superpowers/plans/YYYY-MM-DD-<slug>.md` with what / why / scope / risks. Durable specs land under `docs/superpowers/specs/`.

## Code of Conduct

The 12 quality standards. Order = workflow; standards = how to do each step properly.

1. **Think before writing code** — state your assumptions first, do not guess.
2. **Simplicity first** — least code, YAGNI over DRY.
3. **Surgical changes** — change only what must be changed.
4. **Goal-driven execution** — define verifiable success criteria first.
5. **Use the model only for judgment tasks** — leave deterministic work to code.
6. **The token budget is not a suggestion** — when approaching the budget, checkpoint or start a new session, and use `/handoff` to hand off work.
7. **Expose conflicts, do not average them out** — pick one pattern and unify everything to it.
8. **Read before writing** — first grep exports, callers, and shared utilities.
9. **Tests should verify intent, not just behavior** — when business logic changes, tests should fail.
10. **Checkpoint at every important step** — run tests, confirm state, then continue.
11. **Match codebase conventions** — do not silently rewrite existing style.
12. **Fail loudly** — prefer a visible error over a silent skip.

<details>
<summary>Detailed reference</summary>

read PRINCIPLES.md

</details>

## Coding Conventions

- Keep HaloCore pure-function / value-type first; justify any new global state explicitly.
- Reuse the existing logging and error types (`HaloLog` / `DiagnosticLog`); do not invent a parallel one.
- Put SwiftUI geometry and hit-testing into `*Geometry.swift`; keep views thin. Any geometry change must update the matching `Tests/HaloUITests/*GeometryTests.swift`.
- Visual / material changes follow `docs/VISUAL.md` (Liquid Glass on macOS 26 + `NSVisualEffectView` fallback).
- Strings go through localization: update both the English and `zh-Hans` `Localizable.strings`.
- Wrap new performance-sensitive paths with `PerfSignpost` under `com.halo.launcher / perf`; do not scatter `print` calls.

## Safety Rails

### NEVER

- **Do not pull Accessibility into the core loop.** Wheel / double-tap / menu bar / NSWorkspace paths must stay AX-free. AX is allowed only in the Action Arc's Fullscreen and keyboard-shortcut chips.
- **Do not introduce networking, telemetry, or third-party analytics.** Halo is on-device only.
- **Do not regress macOS 12 compatibility** (`Package.swift` `.macOS(.v12)`). Guard new APIs behind `if #available` or behind `PlatformCompat.swift`.
- **Do not violate the dependency direction**: HaloCore must not import AppKit/SwiftUI/Carbon; HaloApp must not bypass HaloUI to draw windows directly.
- Do not modify `Resources/Info.plist`, `Halo.entitlements`, `scripts/notarize.sh`, CI workflows, or the LaunchAgent plist without explicit approval.
- Do not commit without running tests; do not `git push --force` to `main`.
- Do not skip the "open `dist/Halo.app` yourself and exercise the change" step before declaring done.

### ALWAYS

- Show the diff before committing; keep `Resources/Info.plist`'s version number and `CHANGELOG.md` in sync.
- Update `CHANGELOG.md` for any user-visible change; reflect new capabilities back into the README where the feature is mentioned.
- For small, locally verified changes pushed to `main`, append `[skip ci]` to the commit message (CI runs on `macos-26` — skip when there is nothing new for it to verify).
- For any change touching performance, layout, or geometry, run `make test` and report the result of `HoneycombGeometryTests` / `RadialGeometryHitTestTests`.

## Verification

- HaloCore-only changes: `make test`.
- HaloUI / HaloApp changes: `make test` + `make app` + you yourself `open dist/Halo.app` and walk the golden path (summon the Wheel → direction → release; Tab into ALL → search → Return; ⇧ to open the Action Arc).
- Visual / material changes: capture before/after screenshots, covering both the Liquid Glass branch (macOS 26) and the `NSVisualEffectView` branch (macOS 12–25).
- Performance changes: launch once with `HALO_PERF_LOG=1` and confirm `~/Library/Logs/Halo/halo.log` shows no regression in `refreshSlots` / `adaptiveSpiralLayout` / `DCE.extract`.
- Release path: `HALO_SIGNING_IDENTITY=… make release` must be Gatekeeper-clean — `spctl --assess -vv dist/Halo.app` should pass.

## Compact Instructions

When compacting history, preserve:

1. Architecture decisions (the three invariants: HaloCore UI-free / core loop AX-free / on-device only) — **never summarize away**.
2. Modified files and the key diff points.
3. Current verification status (which command passed/failed).
4. Open risks, TODOs, and rollback notes.
