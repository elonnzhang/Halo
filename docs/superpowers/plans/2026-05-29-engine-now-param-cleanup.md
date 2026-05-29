# 2026-05-29 — Full-codebase bug review + `HaloEngine.top` dead-param cleanup

## What

- Conducted a full-codebase review (HaloCore read line-by-line; HaloUI / HaloApp
  swept by two audit subagents whose findings were each verified by hand).
- Removed the unused `now: Date = Date()` parameter from
  `HaloEngine.top(n:from:)` and dropped the `now: now` argument from the five
  `HaloEngineTests` call sites that passed it.
- Added a CHANGELOG `### Internal` note.

## Why

`HaloEngine.top` declared `now` but never referenced it in the body. The MFU /
MRU / balanced ranking sorts purely on absolute `activations` / `lastUsed`; the
7-day recency window is applied **upstream** in `UsageStore.allRecords()`
(`cutoff = now - windowSeconds`), so the engine genuinely has no use for `now`.
The five tests threaded `now: now` through as ceremony — every assertion holds
for any value of `now`, confirming it was dead.

Cost of keeping it: a misleading public API (the name implies recency weighting
that doesn't exist) and a redundant `Date()` allocation on every `refreshSlots`
(workspace-activation events + prefs `objectWillChange`). Per the project CoC
(#2 simplicity / YAGNI, #3 surgical), the fix is removal, not implementing a
recency-decay feature (that would be new product behaviour, not a bug fix).

## Scope

- `Sources/HaloCore/HaloEngine.swift` — signature only (1 line).
- `Tests/HaloCoreTests/HaloEngineTests.swift` — 5 call sites; the `now` locals
  remain in use for building `UsageRecord.lastUsed`, so no unused-var warnings.
- `CHANGELOG.md` — one Internal bullet.
- `AppDelegate.swift:378` already omitted `now` (used the default) → unchanged.

HaloCore-only behaviour-wise; no UI, geometry, or persistence touched.

## Verification

- `make test` → 203 tests, 0 failures.
- `make build` → all targets compile (confirms HaloApp builds against the new
  signature).
- No behaviour change: `now` never influenced output, so Top-N ranking is
  byte-for-byte identical.

## Risks / rollback

- Risk: negligible. Pure dead-code removal; no observable behaviour delta.
- If a future recency-decay feature wants a clock, reintroduce `now` *and* wire
  it into the sort comparators + tests — don't restore it as a no-op.
- Rollback: revert the three edits; the parameter had a default so any external
  caller (there are none outside this repo) would be unaffected either way.

## Audit findings that were investigated and REJECTED (false positives)

Recorded so future sessions don't re-chase them:

1. `GridState.neighbourBundleID` "array OOB at `layout[idx]` / `layout[candidateIndex]`"
   — **false.** `list` is a local snapshot (`let list = filteredApps`), `idx`
   comes from `list.firstIndex`, and `spiralLayout` uses `.prefix(count)` over a
   `(2r+1)²` candidate grid that always exceeds `count`, so
   `layout.count == list.count` and every index is in range. The guard's `else`
   is dead, and even if hit, in-bounds.
2. `AppDelegate.shakeAndDismiss` "retain cycle" — **false.** The nested `tick`
   is a transient strong capture held by `DispatchQueue.asyncAfter` for ~0.16s,
   then released (no re-schedule after step 4). No cycle; AppDelegate is an
   app-lifetime singleton regardless.
3. `AppDelegate.installActivationObserver` "leaked NSWorkspace observer" —
   **false.** Registered once at launch with `[weak self]` + `guard let self`,
   intended to live the whole app lifetime; not removing an app-lifetime
   singleton observer is correct.

Everything else read clean: `RadialPanelFrame` clamp math, `swapPins` /
`reorderProfile` / `BindingProfile.resizing` index handling, per-profile
`slotCount` projection, OKLCH conversion constants + histogram extraction,
`SlotCycle` positive-modulo, `UsageStore` serial-queue thread-safety + prune,
`KeyboardShortcut` parser, `HoneycombGeometry` (all divisions guarded), and the
AppDelegate slot-fill (pinned-in-topN ≤ pinCount ⇒ enough unpinned candidates).
