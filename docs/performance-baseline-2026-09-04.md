# Performance pass — 2026-09-04

This is a local engineering comparison, not an FPS guarantee, a balance change,
or a human input-feel verdict. Visual quality, effect density, object caps,
research data, rewards, tracking rules and save format are unchanged.

## Changes and environment

- Research definition lookup uses one read-only ID index instead of a linear
  scan of 107 constant definitions. Ordered enumeration is unchanged; no
  progression/affordability state is cached.
- Meteor ribbons reuse five Float64 weights per current station count. Type,
  age, positions, normals and visibility remain live. Turbulence profile/phase
  and fragment debris-envelope work move out of their per-station loops.
- No draw calls, vertices, colors, effects or specimens were removed.

Machine: Windows, Godot 4.7.2-stable `ed1daf0bf`, OpenGL 3.3 Compatibility,
NVIDIA RTX 3060 / driver 591.74, 1152×648, 144.05 Hz, VSync enabled, Dummy audio.
All timed runs were sequential, using an off-screen window on the logged-in
desktop; no concurrent Godot tests or other GPU benchmark ran. This is one
machine and three samples per condition, without a controlled CPU clock or a
statistical confidence interval.

Before production source: `347dcf09699337e00617980790cccd2b65673f3b`, with the new
probe instrumentation on both sides. After: that revision plus this uncommitted
performance patch, not a claim that the clean commit contains the optimization.
The baseline's `game_balance.gd` differs from the original disk hash only in
line endings; its Git diff was empty before measurements.

| Source | Before SHA-256 | After SHA-256 |
|---|---|---|
| `scripts/game_balance.gd` | `f0342536fd6b2f0e3d404017b0d6859662f7f06ea9055ffe76c494efe217f9ab` | `35e1ac75c96917a8da431aeaf5b85b49d2961a1cd1385750686be2c48f38c46e` |
| `scripts/meteor.gd` | `2194c3000305859680fbd1ad14629ec71a55c87abad18ceb57a9fb5aedbeda65` | `635045251afcdf1b695e7901c9b2d529dc5ccfda10e925e9aaf9f455eb1ed44b` |

The UI probe hash on both sides is
`b022b03595e1b575e3226c7c06eacb9b65bad7a9c687f3a4fd30193a6cbdf960`;
the observation probe hash is
`836a2730bf71275637c1ac6ff8d4445321ac21f6e5c536b1bb93947bd8704ecf`.
Every accepted run completed with unchanged measured-source hashes. Among
recorded UI sources only `game_balance.gd` changed; among observation sources
only `game_balance.gd` and `meteor.gd` changed.

## Accepted runs and exclusions

Logs are local derived artifacts in `build/performance-20260904-002109/`:

- Before UI: `baseline-v2-ui-1.log`, `-2.log`, `-3.log`.
- After UI: `optimized-v2-ui-1.log`, `-3.log`, `-4.log`.
- Before/after observation: `baseline-v2-observation-{1,2,3}.log` and
  `optimized-v2-observation-{1,2,3}.log`.

The entire `optimized-v2-ui-2.log` run is excluded: it ended after the inspector
phase without `RESEARCH_UI_PROBE_COMPLETE`, despite the console launcher's
zero exit status. No matching Windows Application Error was found. The cause
was not established; a replacement run launched the same engine worker directly
and required both a zero exit and the completion marker. This is not a license
to discard slow completed samples. If an incomplete run recurs, investigate it
before using the result. Accepted UI logs contain all five phases; accepted
observation logs contain all six valid phases and `OBSERVATION_PERF_PASS`.

Earlier `before-ui-*`, `after-lookup-ui.log` and `before-observation-*` runs are
also excluded. Independent review found that replacement nodes had lost the
scene-authored chart layer / observer z-index. Both probes were fixed to preserve
and check the shipped draw order (chart 100 above HUD 80, observer z-index 50),
production code was restored, and all baseline-v2 runs were collected again.
The uninstrumented `baseline-research-*` and headless logs are exploratory only,
not mixed into this comparison.

## Research chart

The existing wall-clock phases are unchanged: idle, eight wheel events per
frame, alternating inspector selections, the 3.6-second pull-back, and its
static final frame. Faster runs can process more input/layout calls, so compare
average CPU time per call, not accumulated totals. Timings below are medians
of the three runs. All times are milliseconds; lower is better.

| Phase | Mean frame before → after | p95 before → after | p99 before → after |
|---|---|---|---|
| Idle | 6.94 → 6.94 | 7.07 → 7.11 | 7.49 → 7.77 |
| Wheel burst | 13.34 → 13.58 | 17.83 → 16.43 | 19.82 → 18.74 |
| Inspector selection | 10.51 → 11.01 | 14.45 → 14.26 | 16.47 → 16.45 |
| Galaxy pull-back | 11.06 → 11.03 | 15.93 → 16.46 | 18.90 → 17.81 |
| Final galaxy frame | 6.94 → 6.94 | 7.21 → 7.08 | 7.91 → 7.92 |

| CPU metric, wheel burst | Before avg/call | After avg/call | Reduction |
|---|---|---|---|
| Layout, inclusive | 4.3416 | 2.7294 | 37.1% |
| Ledger refresh, included in layout | 3.3867 | 1.6261 | 52.0% |

The ledger reduction is the clear chart CPU result. Do **not** describe this as
a 52% whole-frame or FPS improvement: drawing and UI work remain, the average
wheel/inspector frame did not improve, and the pull-back p95 slightly increased.
Wheel p95 ranged 17.43–18.70 before and 15.13–18.31 after; it is not uniformly
below 16.7 ms. All three final pull-back p95 samples (16.46, 15.10, 16.52) and
all final-frame samples stayed below the documented 16.7 ms candidate limit.

`RESEARCH_UI_CPU` values overlap and cannot be added. `_draw_tree()` timing
does not include child marker drawing or GPU work. Layout remained one pass
per wheel frame, and inspector content refreshes matched selection frames.
Static draw counts stayed 602/31,803 primitives at chart idle and 710/52,253
in the final galaxy view. Dynamic ending counts depend on rotation/selection.

## Synthetic observation

Each phase uses 60 warm-up + 360 measured frames, exactly 1/60 simulated second
per rendered frame, fixed seed 20260904 and exactly 18 or 32 live meteors.
The 32-object workload includes one Major. `sweep` is **unpressed cursor hover**,
not the game's Sky Sweep summon mechanic. The single synthetic multi-target
feature, bounded ages and in-place replenishment are documented in
[probes.md](probes.md#synthetic-observation-ab-workload--observation_performance_probegd).
These workloads are not a legal fully researched playthrough or normal spawn
density. The same three-run median convention applies.

| Objects / phase | Mean frame before → after | p95 before → after | p99 before → after |
|---|---|---|---|
| 18 / still | 7.000 → 6.994 | 8.038 → 7.420 | 13.721 → 12.445 |
| 18 / sweep | 7.080 → 7.000 | 8.414 → 8.108 | 13.636 → 13.312 |
| 18 / hold | 7.238 → 7.221 | 9.867 → 9.748 | 13.546 → 13.894 |
| 32 / still | 9.006 → 8.505 | 11.907 → 11.002 | 13.304 → 12.780 |
| 32 / sweep | 9.555 → 8.306 | 12.532 → 10.349 | 13.901 → 11.357 |
| 32 / hold | 10.339 → 9.334 | 13.497 → 12.051 | 15.263 → 13.683 |

The strongest frame result is at 32 objects: sweep p95 decreased 17.4% and
hold p95 decreased 10.7%. There is little mean-frame change at 18 objects,
near this display's VSync interval. Some maxima/p99 values worsen: the worst
32/sweep frame was 15.383 → 17.196 ms, so isolated stalls have not been
eliminated. `sync_work_ms` excludes draw submission and is not a meteor-render
CPU timer; its mean did not improve consistently. No whole-game speedup or
input-latency guarantee follows from these synthetic samples.

Across all six runs for each workload, live/head-in-viewport counts, trail
presence, cursor travel, tracking/hover counts, completions, packets, peak
particles, and the reported draw-call/primitive distributions matched exactly.
Every hold row had 351 tracking frames, 9 manual completions, 9 landed packets
and 43 peak particles. No objects or effects were removed to improve timing.
Hardware cursor input, audio, spawn cadence, survey summons, distant targets,
phenomena, expiry and completion linger are outside this probe's scope.

## Correctness and visual evidence

- The same expanded meteor oracle passed before and after: 539 packed-geometry
  cases, 264 direct getter mutations, all eleven meteor types, and fragment
  sparks. Root independently reran it; the complete suite includes it as gate 12.
- Research lookup checks preserve every field, read-only definitions,
  case-sensitive IDs and fresh mutable misses.
- The validation runner self-test passed all 76 checks after adding the gate.
- All 13 PNG files match the pre-change corpus byte for byte, including dense
  observation, both meteor-family plates, charts and the ending. Baseline:
  `build/reference/347dcf096993_1788448871062/`; optimized comparison:
  `build/reference/347dcf096993_dirty_1788450186720/`. Their manifests identify
  exact source snapshots and image hashes. Later documentation-only changes do
  not retroactively change those manifests.

## Final validation and Windows build

The [routine validation command](probes.md#routine-validation) completed with
`-FullEconomy -Build`: all 12 fast gates, the full-tree economy test, and the
Windows export passed. The economy run used the `cheapest` strategy and seeds
`20260821,20260837,20260853`; all 107 research systems and five galactic
phenomena completed, with reconciled income and no research-arrival gap above
120 seconds. This is three seeded simulations, not every purchase strategy.

The machine-readable result is
`build/validation/20260903T154513043Z_d301637b/summary.json` (UTC-stamped;
2026-09-04 in Korea). The exported file is
`build/windows/NightwatchArray.exe`, 119,506,968 bytes, SHA-256
`f7bad1b083a8548581661668ecb3c56a412165cdc2f35cfe4aca26e6e29443d0`.
It also started from its export directory with Windows/OpenGL Compatibility
and Dummy audio, then exited cleanly after `--quit-after 120`, with no engine
or script errors (`build/performance-20260904-002109/exported-startup.log`).
This checks startup/renderer/exit, not a manual playthrough.

An earlier attempt to run a fixture with the exported EXE's `--script` option
is **not** a test pass: that editor-only option is absent from this release
template's local help and the fixture never ran. The owned process was stopped;
the supported normal-startup check above replaced it. Fixture and geometry
tests passed separately under the editor binary in the validation suite.

The current pass changes no game-design decision or performance acceptance
threshold; any further draw batching should be measured and visually rechecked
as a separate change.
