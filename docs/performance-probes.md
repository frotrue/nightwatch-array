# Performance and Economy Probes

Run from the repository root with `$godot` from the [README](../README.md#실행과-빌드).
Choose probes for the changed subsystem; [probes.md](probes.md) defines the normal gates.
Keep each `*_ENV` header, source identity, seed/configuration, logs and exclusions with results.
Use matching workloads before/after; run GPU measurements sequentially.

## Full-tree economy

```powershell
.\tools\validate.ps1 -GodotPath $godot -FullEconomy -Build
# Direct iteration:
& $godot --headless --path . --script res://tests/full_tree_economy_test.gd
```

This checks all 95 base research nodes; outer research and module collection are
covered by separate integration gates. Simulation uses fixed 1/60s steps and a scripted
engaged cursor targeting uncovered meteors. Additional-target analysis uses the
same cursor position and real radius. Production dishes, sweep, research effects
and meteor clocks execute. Retired celestial objects no longer run.

| Environment | Default | Meaning |
|---|---|---|
| `NIGHTWATCH_ECONOMY_SEEDS` | `20260821,20260837,20260853` | Comma-separated seeds |
| `NIGHTWATCH_ECONOMY_STRATEGIES` | `cheapest` | Subset of `cheapest,automation_first,manual_first` |

Strategies rank currently affordable research at intermissions. They do not reserve
money for a preferred unaffordable node or optimize human behavior. Sweep transitions
preserve held-button charge, but direct target calls do not test the input state machine.

Each sample must have 95/95 purchases, a complete research time, final ×8192
value and 1.0 span, positive manual/automatic meteor income, nonnegative bank,
complete R/A/F/P timelines and source/bank reconciliation within 0.5 Data.
New-research availability gaps must stay within twice the maximum observation duration
(currently 120s). A 14,400s simulated watchdog detects stalls.

R/A/F/P means revealed / prerequisites available / first affordable / purchased.
Output includes `FULL_TREE_ECONOMY_ENV`, JSON result records, `SUMMARY`, then
`FULL_TREE_ECONOMY_PASS`; errors use `INVALID`/`FAIL` suffixes.
The normal runner also checks exit status and unexpected errors.

The clock counts active observation only. It omits reading, decisions, intermissions,
and optional observation after completing base research. Completion time, strategy deltas and purchase
batches are diagnostics, not approved price/playtime targets. The historical
[2026-08-30 baseline](history/full-tree-economy-baseline.md) is a dated comparison.

## Contact density

`contact_density_probe.gd` measures a 30s phase's forecasts, live objects and workload
by type. `NIGHTWATCH_CONTACT_PROBE_SEED` defaults to `20260821`; invalid values warn and fall back.
Events remain stopped so completed-tree rows isolate regular spawn floor/cap.
`no-input` is a control; use engaged, manual placement, predictive assignment and
selector rows to assess behavior. Include `realized_objects_by_type.fragment_piece` for splitting changes.

One seed's single-digit completion counts are insufficient for trajectory/dish decisions.
Run at least 8–10 paired seeds on both versions, for example:

```powershell
try {
    20260821..20260830 | ForEach-Object {
        $env:NIGHTWATCH_CONTACT_PROBE_SEED = $_
        & $godot --headless --path . --script res://tests/contact_density_probe.gd
    }
} finally {
    Remove-Item Env:NIGHTWATCH_CONTACT_PROBE_SEED -ErrorAction SilentlyContinue
}
```

Aggregate completions, dish acquisitions/completions by type, and opportunistic drops.
Do not tune trajectories toward stationary dishes merely to restore no-input totals.
The [old density baseline](history/legacy-density-be11e42.md) uses a different workload.

## Frame pacing

Headless runs measure CPU fixtures with zero real draw calls. Render claims require
a windowed renderer. All three main-game frame fixtures isolate player persistence.

| Script under `tests/` | Parameters and workload |
|---|---|
| `frame_pacing_probe.gd` | Human input: still at 1–7s and 19–24s, rapid motion at 8–18s. `NIGHTWATCH_PROBE_SECONDS=24`, `NIGHTWATCH_RENDER_STRESS_OBJECTS=18` (32 includes Major) |
| `observation_performance_probe.gd` | Scripted still, unpressed hover sweep and held tracking at exactly 18/32 live meteors. `NIGHTWATCH_OBSERVATION_PERF_FRAMES=360` (180–1800), 60 warm-up frames per phase |
| `dense_input_performance_probe.gd` | 4/22 common meteors, all base/extension research flags and LINE/SLOW/WIDE/BURST/CORRELATE. 1/17/67 raw samples per 60 Hz tick, 120 ticks per case. Optional windowed frame timing; completion and natural spawning excluded |
| `research_ui_frame_probe.gd` | Idle, eight wheel events per frame, alternating inspector selections, 3.6s pull-back and final continuation chart |
| `probe_frame_pacing_probe.gd` | Independent Layer 2 fixture. `NIGHTWATCH_PROBE_SECONDS=8`; `NIGHTWATCH_PROBE_FINISHED=1` selects finished state |

Example with the real renderer:

```powershell
& $godot --display-driver windows --rendering-driver opengl3 `
    --rendering-method gl_compatibility --audio-driver Dummy `
    --position '-4000,-4000' --resolution 1152x648 `
    --path . --script res://tests/observation_performance_probe.gd
```

For the human-driven probe, run visibly with `& $godot --path . --script res://tests/frame_pacing_probe.gd`
and follow `FRAME_PROBE_READY`. Its synthetic round extends beyond the measurement
window; old samples that timed a paused summary are not comparable.

### Synthetic observation A/B workload

Each rendered frame advances 1/60 simulation second. Six simulated seconds are not
six wall-clock seconds. Bounded ages, disabled splitting and replenishment keep object
count fixed; normal spawning/expiry, automation, survey summons, other target layers
and audio playback are excluded. The isolated multi-target feature is not a legal full build.
`sweep` means unpressed hover motion, not the game's held Sky Sweep mechanic.

`OBSERVATION_PERF_ENV` and six `OBSERVATION_PERF_RESULT` rows record sources, workload,
counts and timings. `OBSERVATION_PERF_PASS` checks stable sources, live visible heads/trails,
cursor travel/target discovery and real held completions/packets, not a speed target.
A 180s watchdog bounds execution. `sync_work_ms` excludes drawing and probe bookkeeping;
wall-frame time includes bookkeeping. `TIME_PROCESS` is a coarse phase-end monitor.
Live hover pulses use real time; use [fixed captures](visual-validation.md) for pixel comparison.

### Dense raw input regression (2026-09-11)

`dense_input_performance_probe.gd` supplements the one-sample observation fixture:
17 samples/tick approximates a 1,000 Hz mouse and 67 approximates 4,000 Hz.
It measures `Game.simulate_tick()` CPU time separately from rendered frame intervals.
Each target must receive exactly two seconds of held contact; stable object counts
and nonzero draw calls in windowed mode are checked. Speeds are diagnostic, not
hardware-independent assertions. The 120-tick sample includes startup and lacks
warm-up; it is a short stress reproduction, not a long-session FPS guarantee.

At 22 targets on this Windows host, before `4de7625` was optimized:

| Samples/tick | Before mean / p95 CPU ms | After mean / p95 CPU ms |
|---|---:|---:|
| 1 | 4.973 / 5.699 | 1.211 / 1.299 |
| 17 | 33.802 / 36.555 | 4.041 / 4.169 |
| 67 | 124.141 / 132.592 | 12.991 / 13.241 |

Raw segments previously repeated research, equipment and geometry derivation for
every target. Tick-local observation caches and shared installed-module counts
remove that repetition without coalescing input or changing spawn probabilities.
`fixed_tick_test.gd` also compares the cached and live paths through line/circle
changes, burst expiry, research mutation and release, including accumulated quality
and observation progress. It also checks mid-pass Sky Sweep target discovery. `module_expansion_test.gd` checks cache invalidation for
inventory, quantity and capacity changes, and protects the public returned array.

The windowed OpenGL sample at 22 targets measured mean / p95 frame intervals of
17.388 / 19.455 ms at 17 samples/tick and 26.940 / 28.900 ms at 67 samples/tick.
This demonstrates a large CPU fix, **not** a guarantee of 60 FPS in the densest
4,000 Hz case. Rendering remains an additional cost; the fixture omits completion
effects, natural spawning and audio. Logs: `build/dense-input-before.log`,
`build/dense-input-final-cpu.log`, `build/dense-input-final-render.log`.

### Research UI

The fixture preserves chart layer 100 over HUD 80 and checks unchanged sources.
Use real `inspector_selection` refreshes; old `tooltip_motion` samples did not exercise
the current fixed inspector. The final frame is the outer constellation continuation; older 29-marker
galaxy frames are not comparable workloads. The documented candidate limit is
windowed pull-back/final-frame p95 below 16.7ms.

Check that eight wheel events still cause roughly one layout per frame.
`RESEARCH_UI_CPU` timings overlap: do not add inclusive totals. Compare average/call,
not totals from differing frame counts. `_draw_tree()` excludes child markers and
the continuation's separate draw callback; rendered frame time includes them.
Retain `RESEARCH_UI_PROBE_ENV`, `RESEARCH_UI_PROBE_SOURCES`, and completion output.

## Bounded simulation workers (2026-09-11)

`threaded_simulation_probe.gd` compares the live path, the same numerical batch
on the main thread, and a batch split over main + at most three persistent workers.
Run headless with the standard Godot binary. All modes receive identical seeds
and 17 held pointer samples per 60 Hz tick; 15 ticks warm up and 60 are measured.
The fixture places eight meteor/body types in a viewport grid, bypasses production
capacity, and suppresses natural spawning. Initial targets cannot complete; at low
density Sky Sweep may still summon and complete additional targets. Final positions,
manual contact time and observation progress must match exactly across modes.

Ryzen 9 5950X CPU-only sample (`build/threaded-cpu-final.log`):

| Initial targets | Live mean ms/tick | Batch on main | Main + 3 workers |
|---|---:|---:|---:|
| 22 | 3.464 | 2.698 | 2.338 |
| 128 | 16.093 | 15.013 | 12.195 |
| 1,000 | 156.310 | 125.617 | 107.646 |

The 1,000-target reduction is about 31% versus the live path; about 14% versus
the same batched calculation on main. Batching/candidate filtering and threading
contribute separately. These are CPU tick costs, not rendered FPS. This change
does not batch GPU draw submission, and 1,000 targets still exceed the 60 Hz budget.

The pool is observer-owned and shared sequentially by motion and contact work.
Jobs receive only immutable numeric snapshots; each chunk owns its result arrays.
Results are joined before the existing ordered scene mutations and reward resolution.
Low workloads retain the live path. `threaded_simulation_test.gd` covers real worker
thread IDs, the hard three-worker cap, zero-worker fallback, mixed body motion and
trail samples, circle/line changes, hitstop, BURST, research changes, pause and exit.
Keep its live-path comparison when changing either the numerical kernels or the
small-workload methods so their duplicated hot-path formulas cannot drift silently.

The existing dense common-meteor fixture also passed headless and windowed
(`build/threaded-dense-cpu.log`, `build/threaded-dense-render.log`). With 22 targets,
windowed mean frame time was 17.124 ms at 17 samples/tick and 24.772 ms at 67.
The unchanged, capacity-bypassing `build/thousand_meteor_probe.gd` was rerun at
1152x648 OpenGL, VSync off, uncapped FPS, on the RTX 3060. Its short wall-time
samples reported 100 common meteors + observation at 13.27 FPS (previous 6.66),
and 1,000 + observation at 0.96 FPS (previous 0.64). The 100-target case sustained
60 ticks/sec; the 1,000-target case achieved only 7.70. These are editor-binary
diagnostics, and the final heavy sample contains only six frames. Different
achieved simulation rates advance different amounts of the scripted input;
use the fixed-tick CPU probe above for equal-work comparisons. Drawing-only at
1,000 remained about 4.62 FPS, consistent with the unaddressed render cost.
Log: `build/threaded-thousand-render.log`.

## Shared meteor light rendering (2026-09-11)

`meteor_render_performance_probe.gd` preserves the thousand-meteor diagnostic
used for the worker work, now checked in for repeatability. Run with the standard
Windows/OpenGL renderer at 1152×648; the script disables VSync and the FPS cap.
It isolates saves, enables research and five observation modules, bypasses normal
capacity, disables natural spawns and keeps initial targets from completing.
Each scenario warms up for two wall seconds and samples for five. Held observation
feeds 17 raw samples per 60 Hz tick, with at most eight catch-up steps per frame.
Retain `THOUSAND_RESULT` (including achieved tick rate) and `THOUSAND_PASS`.

Sequential editor-binary A/B on Ryzen 9 5950X / RTX 3060, NVIDIA 591.74:
baseline `3d349a2` was exported into an isolated source directory and imported
before measurement; the same fixture then ran on the renderer branch. Logs are
`build/render-final-baseline.log` and `build/render-final-current.log`.

| Workload | Previous FPS | Shared FPS | Previous → shared draw calls |
|---|---:|---:|---:|
| 100 common meteors + held observation | 13.34 | 28.67 | 1,312 → 713 |
| 1,000 common meteors, drawing only | 4.80 | 6.21 | 9,227 → 3,228 |
| 1,000 common meteors + held observation | 0.98 | 1.23 | 9,412 → 3,413 |

The drawing-only mean frame fell from 208.22 to 160.92 ms (about 23% lower).
The 100-target case sustained approximately 60 ticks/sec in both implementations.
The overloaded 1,000-target observation case achieved only 7.83 → 9.88 ticks/sec,
and measured just six/seven frames. Different amounts of scripted input advance
in those wall-time samples; use the fixed-work CPU probe for simulation comparisons.
These results do not establish release-build performance or 300 FPS feasibility.
Procedural geometry and observation calculations remain substantial CPU costs.

The new renderer batches contiguous additive triangle geometry across meteors,
caches index offsets and reuses geometry between simulation changes. Thin native
antialiased lines and opaque body drawing remain intact. Its paired real-GPU
correctness test matched immediate rendering for all 11 types, moving trail
topology, opaque overlaps, interpolation reset, fades/removal and a single
1,000-object batch exceeding the 16-bit index boundary. The independent 539-case
geometry oracle remains unchanged. No target counts or visual details were removed
to obtain these measurements, and the main-plus-three-worker cap is unchanged.

Final correctness/export run:
`build/validation/20260911T092255694Z_35355321/summary.json` passed 24 checks
(23 fast gates and Windows export). The GPU pair also passed frozen-scene and
reset-interpolation cases, and the reference corpus captured all ten scenarios.
The expiry smoke assertion now advances one explicit simulation tick: two
uncapped render frames can contain zero ticks. It still asserts the target is
expired and its tracking reference is cleared; production expiry logic is unchanged.

## Duration diagnostics

| Script | Fixed workload / environment | Use |
|---|---|---|
| `duration_ladder_probe.gd` | 18 rounds per duration, 1/60s steps, seed 20260821, denominator 40 | Compare the 20→60s ladder with its historical baseline |
| `duration_pricing_probe.gd` | 600 simulated seconds per cell, 1/60s steps, base seed 20260821; `NIGHTWATCH_PRICING_SEEDS=10` | Marginal Data at minimum prerequisite builds |
| `duration_matrix_probe.gd` | Five durations over a synthetic 1080s horizon; `NIGHTWATCH_MATRIX_SEEDS=5` | Historical matrix comparisons, not a live ending simulation |

Run these with `--headless --path . --script res://tests/<script>`.
Ordinary probe tables are measurements, not pass/fail gates. Any `push_error` invariant
failure invalidates the sample. Old 21/41-node prices and fixed 1080s horizons remain
in [the archive](history/README.md); do not use them as current balance acceptance targets.

The draw-window gate also now prepares BURST with `grant_copy`, the current
inventory path. The previous unseeded fixture sometimes used legacy `grant`
without a quantity; save normalization then changed the dictionary shape on
rollback. Both HEAD and the optimized module model reproduced this difference.
Production save handling and rollback assertions remain unchanged.

Final validation: `build/validation/20260911T082255455Z_23eaf32e/summary.json`
passed all 24 checks (22 fast gates, three-seed economy gate, Windows export).
The final CPU and windowed dense-input probes both passed their workload checks.

Bounded-worker validation: `build/validation/20260911T084705635Z_86b4ef24/summary.json`
passed 25 checks (23 fast gates, three-seed economy, Windows export).
