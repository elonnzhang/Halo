# Halo: launch + ALL grid performance — design

**Author:** elonnzhang (with Claude)
**Date:** 2026-05-18
**Status:** Draft, awaiting user review

## Problem

Halo's cold launch and the first entry into the ALL profile (watchOS
honeycomb grid) feel sluggish to the user. No measurements have been
taken yet — the perception is subjective. Three paths are in scope:

1. **Cold launch** — from double-clicking `Halo.app` to the menu-bar
   item appearing + the first wheel summon feeling responsive.
2. **First ALL entry** — Tab to ALL after a cold launch, until the
   ~140 app icons are all rendered and the cluster is interactive.
3. **ALL interaction** — scroll/zoom/search latency once the grid is
   on screen.

## Approach: measure first, then cut the biggest bottleneck

Adopted after user agreed to Plan C (measure once, fix the biggest
one or two, re-measure).

Two PRs:

- **PR 1 (this design)**: instrument the three paths with
  `OSSignposter` + a text log channel, plus two safe, no-cost
  improvements that don't depend on measurement results.
- **PR 2+**: pick from a pre-scoped candidate list (D-items below)
  based on the numbers PR 1 surfaces.

## §1 — Instrumentation layer

**New file:** `Sources/HaloCore/PerfSignpost.swift`

A thin wrapper over `OSSignposter` with a parallel text channel:

- **Signposts** — emitted via `OSSignposter`, zero-cost when nobody
  is listening. Visible in Instruments → Logging → Signposts so a
  developer can scroll a flame-chart of the launch window.
- **Text log** — gated on env var `HALO_PERF_LOG=1`. When set, each
  measured section logs a single line like
  `[perf] refreshSlots took 312ms` via `HaloLog.perf` (a new
  category) so any user can capture numbers from `Console.app`
  without installing Xcode.

API:

```swift
public enum PerfSignpost {
    public static func measure<T>(_ name: StaticString,
                                  _ body: () throws -> T) rethrows -> T
    public static func measureAsync<T>(_ name: StaticString,
                                       _ body: () async throws -> T)
        async rethrows -> T
}
```

**Instrumented sites (10 total):**

| Path | Site |
|------|------|
| Cold launch | `main.swift` entry → `applicationDidFinishLaunching` first line (AppKit own time) |
| Cold launch | `applicationDidFinishLaunching` total |
| Cold launch | `applyPreferences` |
| Cold launch | `refreshSlots` |
| Cold launch | single `DominantColorExtractor.extract` |
| Cold launch | single `AppIconResolver.icon` |
| ALL first entry | `enterGridMode` → grid on screen |
| ALL first entry | `GridState.scanInstalledApps` total |
| ALL first entry | single `Bundle(url:)` parse (sample 5%) |
| ALL first entry | `HoneycombGridView` first ForEach build |
| ALL first entry | single `IconCell` icon load |
| ALL interaction | single search filter pass |
| ALL interaction | single pan-clamp frame (sample 5%) |

Sampling on hot per-frame paths (`Bundle(url:)`, pan-clamp) keeps the
text channel readable when `HALO_PERF_LOG=1` is on.

## §2 — Safe no-cost improvements (PR 1)

These two ship with §1 because they're high-confidence wins that
don't depend on measurement results.

### §2.1 — `AppIconResolver` NSCache

`AppIconResolver.icon(for:)` calls `NSWorkspace.shared.icon(forFile:)`
on every invocation. NSWorkspace has internal caching but each return
is a fresh `NSImage` instance that lazy-loads bitmaps from disk on
first render. Add an explicit `NSCache<NSString, NSImage>` (count
limit 200) so repeat lookups inside a session collapse to a dict
hit. Same key (bundleID) is read by ~15 call sites across the codebase.

### §2.2 — `GridState.loadApps` background icon prefetch

`GridState.loadApps` already runs `scanInstalledApps` on
`Task.detached`. Extend that detached task: after the sort+order
step, walk the top 80 entries and call `AppIconResolver.icon` on
each (which now hits the §2.1 NSCache). When the user Tabs into ALL,
the first viewport's worth of icons are already memory-resident, so
`IconCell.task(id:)` reduces to a cache lookup.

## §3 — Measurement-driven candidates (PR 2+, not in this PR)

Listed in approximate decreasing order of confidence. Final picks
will be decided by the §1 numbers.

- **D1 — `identityColorCache` disk persistence.** Today's cache is
  in-memory only; every cold launch re-runs
  `DominantColorExtractor.extract` (~100ms/icon per existing code
  comment). Persist to a small JSON or `UserDefaults` blob keyed by
  `bundleID + icon-file-mtime`. Cold launch reads the file, skips
  extraction on cache hits.
- **D2 — `IconCell` true async load.** Today's `.task(id:)` runs on
  `MainActor`, blocking the UI for each cell's `NSWorkspace.icon`
  call. Replace with `Task.detached` + a placeholder
  `RoundedRectangle`, swap the image in on completion.
- **D3 — `refreshSlots` DCE off main.** Same as D1's root cause but
  attacks it from the other end: instead of avoiding extraction via
  cache, move the extraction itself onto a background actor and
  publish results back to `state.slots` when ready.
- **D4 — Lazy init of non-critical AppDelegate properties.**
  `OnboardingOverlay`, `WelcomeWindowController`,
  `SettingsWindowController` are all built at `init` time but used
  rarely. Convert to lazy properties so cold launch skips their
  construction cost.
- **D5 — `Bundle(url:)` parse cache.** `scanInstalledApps` opens
  ~140 bundles to read `CFBundleDisplayName`/`CFBundleName`. Cache
  the result by `(url, mtime)` so subsequent scans skip the plist
  parse.

## §4 — Delivery

### PR 1 contents

- `Sources/HaloCore/PerfSignpost.swift` (new)
- `Sources/HaloCore/HaloLog.swift` — add `perf` category
- 10 measurement sites in `main.swift`, `AppDelegate`,
  `DominantColorExtractor`, `GridState`, `AppIconResolver`,
  `HoneycombGridView`
- `Sources/HaloUI/AppIconResolver.swift` — add NSCache wrapper
- `Sources/HaloUI/GridState.swift` — prefetch top-80 inside detached
  task
- `Tests/HaloUITests/AppIconResolverCacheTests.swift` (new) —
  cache hit/miss, eviction-at-limit
- PR body: before/after numbers for the three paths

### Verification

- `make test` — existing suite + new cache tests pass
- `make app && open dist/Halo.app` — manual cold-launch + ALL entry
  + search + scroll smoke test
- Compare baseline vs after numbers; require visible wins on
  whichever path dominates the baseline

### Out of scope for PR 1

- All D-items (D1–D5)
- Settings/Whitelist tab perf (separate path, no current complaint)
- Wheel-time render perf (already feels fine per user)

## §5 — Risks

- **§2.1 cache invalidation**: app updates change the icon but keep
  the bundleID. Mitigation: cache lives only for the process
  lifetime (NSCache, no disk persistence in PR 1), so a relaunch
  refreshes everything. D5 would extend this with mtime keying.
- **§2.2 prefetch on background actor**: `NSWorkspace.icon(forFile:)`
  is documented main-thread-only on older macOS versions. Need to
  verify on macOS 12–14 in the build; if it warns, gate the
  prefetch behind a `@MainActor` hop with a small concurrency limit
  to avoid stalling the scan task.
- **Signpost overhead**: `OSSignposter` is zero-cost when no one is
  listening, but the text log path always allocates a string.
  Mitigation: log gated on env var so production users pay nothing.

## §6 — Open questions

None blocking. Future work questions get answered by the §1 numbers.
