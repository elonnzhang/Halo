# 2026-05-29 — ALL grid pan/zoom smoothness

## What

Two behaviour-preserving optimizations to cut per-frame work on the ALL grid's
pan/zoom hot path:

1. **Memoize `HoneycombGeometry.spiralLayout(count:)`** — a pure function of
   `count`. Added a process-lifetime `[Int: [(row,col)]]` cache (NSLock-guarded,
   `nonisolated(unsafe)`, mirrors `AppIconResolver`), capped at 128 entries.
2. **Lift the `cellFrames` hit-test reduce out of `grid()`'s body** into a
   `refreshCellFrames(...)` method called only from the `onAppear` /
   list-change handlers — where the result was already the only thing that
   consumed it.

## Why

`HoneycombGridView.grid(in:)` re-evaluates on every `panOffset` / `zoomLevel`
change (i.e. every gesture frame). Each evaluation called `spiralLayout(count)`
for the cluster bounds and `adaptiveSpiralLayout(count)` (which internally calls
`spiralLayout(count + buffer)`). `spiralLayout` builds and **sorts** a
`(2·radius+1)²` candidate grid (~1000+ entries for a large catalogue) — that
sort was the dominant per-frame cost, recomputed 60–120×/s during a drag even
though its output never changes while `count` is fixed.

Separately, `grid()` built a full `[bundleID: CGRect]` hit-test dictionary every
render, but only *assigned* it to `cellFrames` on appear / app-list change (it is
deliberately not refreshed during pan). So on every pan frame it allocated and
populated a dictionary that was immediately discarded — pure allocator churn.

## Scope

- `Sources/HaloUI/HoneycombGeometry.swift` — memo cache + `spiralLayout` body.
- `Sources/HaloUI/HoneycombGridView.swift` — remove inline `nextFrames` reduce;
  add `refreshCellFrames(...)`; call it from `onAppear` / `onChange(filteredApps)`.
- `CHANGELOG.md` — `### Performance` entry under [Unreleased].

No public API change. No HaloCore change. No AX / networking. macOS 12 safe
(`NSLock` only).

## Behaviour preservation

- Memoization is referentially transparent: same `count` → same output. Verified
  by the existing `HoneycombGeometryTests` (which call `spiralLayout` at counts
  1/7/19/48 interleaved in one process — they pass, proving the cache keys
  strictly by count with no cross-contamination).
- The `cellFrames` value is computed by the same reduce from the same `cells` at
  the same moments (appear / list-change); it was never updated during pan
  before, and still isn't. Identical observable hit-testing.

## Verification

- `make build` — all targets compile (Swift 6 strict-concurrency clean).
- `make test` — **203 tests, 0 failures**. Geometry suites:
  `HoneycombGeometryTests` 32/0, `RadialGeometryHitTestTests` 5/0.
- `make app` + launched with `HALO_PERF_LOG=1` (self): runs clean.
  - `adaptiveSpiralLayout`: **~0.12 ms (pre) → ~0.00–0.01 ms (post)** per call.
  - No regression in `refreshSlots` (18 ms cold / 1.6 ms warm) or `DCE.extract`
    (sub-ms).

## Risks / rollback

- Memo cache growth: bounded (distinct `count` values are few; hard cap 128 then
  clear). Worst case a few hundred KB.
- The interactive feel (actual pan smoothness on a large catalogue) is best
  judged live — open ALL (Tab from the wheel) and drag/pinch. The mechanism and
  the signpost drop confirm the win; the eyeball confirms the feel.
- Rollback: revert the two source edits; both are self-contained.

## Noted, not done (future)

- `adaptiveSpiralLayout` still re-runs Pass 1 / Pass 2 every frame (cheap after
  the sort is cached). Could be skipped entirely on frames where the keep-out
  classification is unchanged, but the win is marginal now.
