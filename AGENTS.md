# Halo — Project Instructions

Halo is an on-device macOS radial app launcher built with Swift 6, SwiftPM, SwiftUI, and a Carbon hotkey. Communicate in Chinese; keep code, paths, and tool output in English. Prefix the first line of replies with 🍃 inline.

## Working scope

- Carry an authorized task through implementation and relevant verification. Make routine decisions within scope; ask when missing information changes the intended behavior or when an action needs authorization that the user has not already given.
- Keep changes focused. Follow nearby conventions and reuse existing utilities; do not use a local inconsistency as a reason to refactor unrelated code.
- Report what changed, what was actually verified, and any remaining limitation. If a required environment is unavailable, distinguish that gap from a passing check.

## Architecture and product constraints

- `Sources/HaloCore`: UI-free engine, preferences, profiles, usage, actions, and diagnostics. Do not import AppKit, SwiftUI, or Carbon. Prefer value types and pure functions; explain new global state.
- `Sources/HaloUI`: views, geometry, UI state, hotkeys, and launcher windows. May depend on HaloCore; keep launcher window implementation here.
- `Sources/HaloApp`: executable entry point, app lifecycle, and Settings. Depends on HaloCore and HaloUI; SwiftPM resource processing belongs only to HaloApp. It is also the only target that links PermissionFlow, the project's sole third-party dependency (pinned exactly in `Package.swift`), used for Accessibility authorization guidance.
- Keep the core switching loop Accessibility-free: Wheel, double-tap, menu bar, and NSWorkspace paths must not require AX. AX is limited to the Action Arc's Fullscreen and keyboard-shortcut chips.
- Keep Halo on-device: no networking, telemetry, or third-party analytics.
- Halo supports macOS 13 and later (`Package.swift`, `LSMinimumSystemVersion`), the floor PermissionFlow requires. Guard newer APIs with availability checks or `Sources/HaloUI/PlatformCompat.swift`; retain the older-system material fallback.

## Read for the task

Read relevant sections when needed, rather than loading every document before an edit.

- Product scope and interaction: [PRODUCT.md](docs/PRODUCT.md) and [INTERACTION.md](docs/INTERACTION.md).
- Appearance and materials: [VISUAL.md](docs/VISUAL.md). For Liquid Glass or adaptive-material implementation/review, use [.agents/skills/liquid-glass/SKILL.md](.agents/skills/liquid-glass/SKILL.md).
- Settings behavior: [SETTING.md](docs/SETTING.md). Persistence and diagnostic logs: [STORAGE.md](docs/STORAGE.md).
- Packaging, signing, notarization, and distribution: [RELEASE.md](docs/RELEASE.md) and the relevant targets in `Makefile`.
- Existing feature decisions: the relevant document under `docs/superpowers/specs/` or `docs/superpowers/plans/`.

## Implementation conventions

- Keep geometry and hit-testing in `*Geometry.swift`, separate from views. Update matching geometry tests when behavior changes.
- Localize user-facing strings in both English and `zh-Hans` `Localizable.strings`.
- Reuse `HaloLog` / `DiagnosticLog` and existing error types. Instrument new performance-sensitive paths with `PerfSignpost` (`com.halo.launcher / perf`) instead of scattered `print` calls.

## Build and verification

Use Xcode 26.x and Swift 6; CI runs on `macos-26`. The Swift compiler provides type checking; there is no npm or separate lint step.

| Change | Verification |
| --- | --- |
| Documentation or agent instructions only | Check accuracy, local links, and diff whitespace; validate skill frontmatter when a skill changes. No app build or launch is needed. |
| Swift logic or state | Run affected tests with `swift test --filter <test-name>`; use `make test` for changes spanning modules or shared behavior. `make build` compiles the debug target. |
| UI or interaction | Run affected tests and `make app`, then open this checkout's `dist/Halo.app` and exercise the changed flow. In a worktree, use that worktree's bundle. |
| Layout or geometry | Include the affected geometry tests. Report `HoneycombGeometryTests` / `RadialGeometryHitTestTests` results when those paths change. |
| Visual or material behavior | Capture before/after screenshots and check macOS 26 Liquid Glass and macOS 13–25 fallback behavior where those environments are available. Explicitly report any untested branch. |
| Performance | Compare the affected path against a baseline with `HALO_PERF_LOG=1`; inspect timings in `~/Library/Logs/Halo/halo.log` (for example `refreshSlots`, `adaptiveSpiralLayout`, or `DCE.extract`). |
| Release | Follow `docs/RELEASE.md`; run `HALO_SIGNING_IDENTITY=… make release` and verify `spctl --assess -vv dist/Halo.app`. |

For changes spanning launcher interactions, exercise the golden path: summon Wheel → direction → release; Tab into ALL → search → Return; ⇧ to open Action Arc. A successful build does not establish that UI behavior works.

Fix failures caused by the change and rerun affected checks. Once relevant checks pass, broaden testing only for a new failure or unresolved concern.

## Authorization and delivery

- Editing `Resources/Info.plist`, `Halo.entitlements`, `scripts/notarize.sh`, CI workflows, or the LaunchAgent plist requires explicit user authorization. An instruction already authorizing that edit is sufficient; do not ask again.
- Before committing, show the diff and complete the applicable verification above. Never force-push `main`.
- Keep `Resources/Info.plist` versions and `CHANGELOG.md` aligned for version changes. Update `CHANGELOG.md` for user-visible changes and the relevant README sections for new capabilities.
- For small, locally verified changes pushed to `main`, use `[skip ci]` only when there is nothing new for CI to verify.
- When a task needs a durable design or review record, use `docs/superpowers/specs/` or `docs/superpowers/plans/YYYY-MM-DD-<slug>.md` respectively; include scope, decisions, and risks. Small edits do not require a separate plan document.
