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
| `late_game_render_performance_probe.gd` | Real-time natural spawning, full research or `NIGHTWATCH_PERF_SAVE` read-only copy, one noncompleting planet, effects and sound. `NIGHTWATCH_PERF_INPUT_SAMPLES` selects 1–134 raw samples per tick (default 17); 5s warm-up + 25s measurement |
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

## Completion-particle instancing (2026-09-11)

Remaining real-play drops were profiled with all 95 base and 42 outer research
nodes, five modules (focus, linear observation, slowdown, overcharge and wide),
natural spawning, automatic observation and completion feedback. A second pose
also triggered a shower. A scripted cursor feeds 17 samples per fixed tick;
three wall seconds warm up and eight are measured, uncapped, at 1152×648 on
the same Ryzen 9 5950X / RTX 3060 Windows/OpenGL editor binary. Saves/settings
are isolated; Dummy audio still runs sound synthesis code.

Even with only about 22 live targets, feedback reached the unchanged 220-particle
cap. Native particle circles repeatedly rebuilt/submitted their 64-segment mesh.
`circle_instances.gd` now keeps that same mesh resident and submits position,
radius and color in one MultiMesh buffer, preserving order, fade and camera scale.
Rings, labels, completion behavior, particle limits and the worker cap are unchanged.

Exploratory instrumented runs (`build/live-profile-before.log` and
`build/live-profile-after.log`) showed late-game FPS 87.99 → 164.30 and shower
FPS 64.87 → 99.82; p99 frame times were 24.01 → 13.65 ms and 46.53 → 21.39 ms.
These are directional evidence, not equal-work benchmarks: the wall-time runs
had different natural target/completion mixes. Baseline shutdown also reported
two leaked objects after sampling; the follow-up allows pending sound timers to
finish before freeing the fixture. Do not treat that diagnostic as a clean gate.

The checked-in `observation_performance_probe.gd` provides a fixed-work comparison.
Sequential before (`680aa1e`) and after runs each completed all six default
360-frame phases with one 60 Hz step per frame and the same completion counts.
It excludes automatic observation, natural spawning and audio, so it exercises a
smaller particle load than the live diagnostic. Logs:
`build/frame-drop-observation-{before,after}.log`.

| Fixed workload | Mean frame ms before → after | p99 ms before → after |
|---|---:|---:|
| 18 targets, held observation | 8.852 → 7.421 | 14.237 → 11.447 |
| 32 targets, held observation | 12.438 → 10.195 | 17.158 → 12.399 |

Both held phases completed ten manual observations and reached 49 particles in
both versions. The 32-target mean fell about 18%; frames over 16.7 ms fell from
6/360 to 0/360 in these samples. This does not establish a release-build FPS floor:
meteor geometry and simulation still cost time, and the live shower sample still
had frames above 16.7 ms. The paired real-GPU particle test passed all nine poses,
with at most one 8-bit color step of difference and identical expiry/reset images.
Validation/export: `build/validation/20260911T095636363Z_c827789d/summary.json`
passed all 24 checks (23 fast gates and Windows export).

## Persistent late-game rendering costs (2026-09-11)

The previous synthetic 32-target input probe did not reproduce the user's slow
late game. A read-only copy of the latest slot showed 95/42 research and modules
`overcharge, focus, sweep_optics, capture_hold, focus`. An instrumented natural
30-second run with that build reached 29 targets/220 particles, 46.45 average
FPS and 159.89 ms p99. After surface caching and scan instancing, a directional
rerun reached 86.36 FPS and 21.31 ms p99. These wall-time runs had slightly
different completions/target mixes; they are not equal-work throughput estimates.
Logs: `build/player-profile-before.log`, `build/player-profile-arcs-after.log`.
The player's save is not part of the committed fixture and was not modified.

`late_game_render_performance_probe.gd` now keeps this fuller workload reproducible:
all research, that duplicate-module build, natural spawning, 17 input samples per
60 Hz tick, automatic scans, completion effects and sound code. One explicitly
seeded, noncompleting moving planet guarantees sustained surface rendering;
other objects retain normal completion and spawn rules. Warm-up is five wall
seconds, followed by 25 measured seconds. It uses isolated settings/saves and a
90-second watchdog. Optionally point `NIGHTWATCH_PERF_SAVE` at a read-only CFG
copy to load a build before starting a fresh observation phase. Remove the
variable afterwards. No performance threshold is a gameplay acceptance gate.

Use the README editor binary with the Windows/OpenGL flags in visual-validation,
at 1152×648, sequentially. The final A/B used `--verbose` in both runs, baseline
`ec30cbf` exported into an isolated source folder, and the same probe. Both logs
have `LATE_RENDER_PASS`, exit 0 and no engine errors or leaked-object warnings:

| Diagnostic | Baseline | Cached surface + instanced scans |
|---|---:|---:|
| Mean FPS | 7.41 | 50.13 |
| p99 frame time | 250.28 ms | 48.04 ms |
| Achieved simulation ticks/sec | 45.99 | 59.97 |
| Draw calls at sample end | 1,656 | 507 |

Logs: `build/late-render-before.log`, `build/late-render-after.log`. The overloaded
baseline advanced fewer ticks (218 vs 260 completions); this table measures
frame pacing under the same scenario, not identical completed work. Earlier
runs varied considerably, so neither this table nor the saved-build diagnostic
establishes a minimum FPS. Ordinary meteor geometry/input work still costs time.

The planet now submits its original 576 cells as one cached triangle array.
The two native five-point dashed arcs formerly issued 15 arcs/45 AA strips per
scanning meteor; two MultiMesh submissions reuse those exact feather templates.
The paired renderer test retains native oracles for both and checks fractional
radius, camera span, palette/size changes, fades, stop/restart and removal without
relaxing its pixel limits. The final 26 poses differed by at most one 8-bit color
step. The main-plus-three-worker cap and all gameplay timing remain unchanged.
Validation: `build/validation/20260911T120606968Z_356979eb/summary.json`, 24 passes.

### Why the tick migration can expose drops

Comparison of `fe3e69f` with `4de7625` confirms that input changed from one
accumulated cursor sample per render frame to raw timestamped motion samples.
Secondary-camera reassignment also changed from a 0.35-second timer to every
simulation tick. Low rendered FPS can now require multiple fixed steps in one
frame (up to the configured eight-step catch-up ceiling). Those are additional
costs, not a claim that fixed 60 Hz inherently performs worse. This renderer
change leaves those simulation/input contracts intact; investigate their work
frequency before changing the fixed timestep or dropping input segments.

Stock release templates do not support `--script` unless compiled with path
overrides enabled. The attempted direct-EXE probe was stopped after failing to
produce a result; it is not release-performance evidence. Use the editor binary
for these scripts. See the [official command-line availability legend](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html#command-line-reference).

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


## Observation selection optimization (2026-09-11)

Retain all timestamped input segments and the fixed 60 Hz simulation. While
survey keeps a valid primary, do not rank additional targets whose ranking cannot
change that selection. Compute the soft-break distance only after a contact miss,
and reuse the caller's immediately preceding validity check. Direct diagnostic
calls still validate their target. No sampling/coalescing, worker-count or geometry
change is involved.

`tests/support/reference_observation_selection.gd` retains the old selection pass
from `f7a84f0`. The threaded gate compares primary identity, tracked order, grace,
quality and credited work, with 17/67 samples, LINE/circle, survey off/on, burst,
hitstop and release. This reference is test-only and should stay independent.

Paired CPU-only dense probe on Ryzen 5950X, Godot 4.7.2, 22 fixed targets:

| Raw samples/tick | Before mean ms | After mean ms |
|---|---:|---:|
| 1 | 1.295 | 1.150 |
| 17 | 3.704 | 2.833 |
| 67 | 13.454 | 8.595 |

Both runs retained 44.0 credited manual seconds and passed their workload checks.
The 67-sample reduction in this pair is 36%; other baseline runs were closer to
11ms, so this is not a promised gain for every machine or play session.
Logs: `build/input-optimization-dense-{before,after}.log`.

Natural-spawn windowed measurements did not establish a consistent FPS gain.
The copied 95+42 research save at 1152x648/OpenGL, 5s warm-up + 25s measurement,
measured before/after 94.25/73.02 FPS with 17 samples; reversing execution order
measured after/before 93.72/84.52 FPS. A 67-sample pair measured 80.31/77.25 FPS
with 282 completions on each side. Each run maintained approximately 60 ticks/s.
These variable whole-game results must not be presented as a rendering improvement.
Logs: `build/input-optimization-render-*.log`, `build/input-optimization-67-*.log`.

An isolated `--render-thread separate` trial failed before completion with a fatal
`cowdata.h` bounds error and a VSync warning. Do not enable it based on this trial;
the project keeps its existing render thread model. The trial is not a performance
sample. Engine rendering/driver work remains a separate optimization target.

## Vulkan backend and background batches (2026-09-11)

Windows now defaults to Mobile/Vulkan, retaining the safe render thread model.
Vulkan initialization failure can fall back to Compatibility/OpenGL; D3D12
fallback is disabled to avoid an unvalidated additional deployment path. Explicit
OpenGL launch arguments remain available in the README. The unsupported-hardware
automatic transition was not exercised on this Vulkan-capable RTX 3060.
See the engine's [renderer fallback documentation](https://github.com/godotengine/godot-docs/blob/master/tutorials/rendering/renderers.rst).

Both background star layers now reuse the existing native-circle MultiMesh
helper. The sunrise halo submits the same 64 colored triangles in one command.
Circle order, soft rims, 30 Hz twinkling, sky colors, dawn timing and camera
compensation are preserved. No simulation, research, density, input or quality
reduction accompanies the renderer change.

Same Ryzen 9 5950X / RTX 3060 / NVIDIA 591.74, Godot 4.7.2 editor engine,
1152×648 Windows windows positioned offscreen, VSync/FPS cap disabled. The
late-game fixture reads the isolated `build/player-frame-drop.cfg` copy (95 + 42
research), seeds the streams, guarantees one moving noncompleting planet, and
supplies 17 input samples per tick. Each run has 5s warm-up and 25s measurement.
Runs were sequential. The unchanged baseline is `d2021b5`; the second baseline
ran from its separately imported archive in `build/backend-baseline`.

| Run | Mean FPS | p95 / p99 ms | Completions | Peak targets / particles | End draw calls |
|---|---:|---:|---:|---:|---:|
| Baseline OpenGL 1 | 75.55 | 19.07 / 23.35 | 319 | 27 / 220 | 568 |
| Final Vulkan + batches 1 | 206.04 | 10.26 / 13.37 | 313 | 28 / 220 | 320 |
| Final Vulkan + batches 2 | 239.16 | 9.75 / 11.72 | 290 | 28 / 220 | 327 |
| Baseline OpenGL 2, after final | 87.49 | 18.28 / 20.63 | 308 | 27 / 220 | 550 |

All sustained approximately 60 ticks/s. This is about 2.7× mean FPS in these
repeated late-game workloads, not a universal FPS guarantee or identical
frame-by-frame trajectories: natural completion counts still vary across runs.
Logs: `build/backend-pair-gl-{1,2}.log`,
`build/backend-final-vulkan-{1,2}.log`. Renderer-only preliminary Vulkan runs
were 138.62 and 192.80 FPS; D3D12 was 107.86 FPS. The combined improvement must
not be attributed exclusively to the background batching.

The separate-thread Vulkan experiment reached 407.14 FPS but produced repeated
empty texture upload errors and wrong-thread finalization errors. It is invalid
as a passing performance sample and is not shipped. These match open upstream
[glyph atlas upload](https://github.com/godotengine/godot/issues/122206) and
[render-device shutdown](https://github.com/godotengine/godot/issues/119000)
issues. Log: `build/render-structure-vulkan-thread-trial.log`.

The capacity-bypassing thousand-meteor diagnostic remains heavily overloaded:
final Vulkan was 6.22 FPS without observation and 1.14 FPS with observation
(9.10 ticks/s). The synthetic 100-target observation case was 28.88 FPS and
maintained 59.95 ticks/s. These are deliberately larger workloads than the
27–28-target natural fixture. This patch does **not** establish 300 FPS at
1,000 targets. Log: `build/backend-final-thousand.log`.

Real-GPU background, meteor and particle pixel comparisons pass on both Vulkan
and explicit OpenGL. All nine background frames match the native oracle exactly
on Vulkan; OpenGL differs in at most 30 channels by one 8-bit level. The paired
meteor test also covers >65,536 vertices, solid/additive ordering, subpixel scan
arcs, interpolation and object deletion. Logs:
`build/backend-{mobile,gl_compatibility}-*_render_test.log`.

Cross-backend Korean/English solar and research captures (nine each) also pass:
`build/solar_target_review/1789138367` (Vulkan) and `1789138380` (OpenGL).
The size/observation images differ by at most 2/255 per RGB channel; research
images by at most 9/255. Visual review found matching geometry, palette and
readable labels. These cross-backend numeric differences are not a pixel-identity
claim. Screenshots and probes are diagnostics, not a player comfort verdict.

Validation/export: `build/validation/20260911T145314548Z_2ff242b1/summary.json`
passed all 25 checks (24 fast gates and Windows export). The editor engine also
loaded the exported EXE's pack and ran the isolated live sky fixture with 24
moving targets on its default Vulkan backend: `build/backend-packed-live.log`
and captures in `build/backend-packed-live/`. This checks packed resources and
settings; it is not a benchmark of the stock release engine binary.

## GPU usage stuck at zero (2026-09-12)

After the Vulkan switch, the helper still filtered counter instance names for
`engtype_3D`. A reproduced late-game run had 0% in this game's 3D engine while
Windows reported 17% on its `Graphics_1` engine. Consequently the monitor kept
displaying a valid-looking 0%. The helper now selects the busiest valid engine
for the exact game PID, across all engine types/adapters, without summing them.
This follows Microsoft's [per-process GPU utilization definition](https://devblogs.microsoft.com/directx/gpus-in-the-task-manager/).
The label is now `GPU`, and missing/invalid data still displays unavailable.

The isolated live Vulkan reproduction changed from constant 0% to varying
17–40% samples, with Windows independently identifying `Graphics_1` as active.
Windows/CIM and helper readings have different sampling windows and are not
claimed to match sample-for-sample. Logs: `build/gpu-usage-{before,after}.log`
and `build/gpu-usage-after-windows.json`. The same scripted natural workload
remained about 256 FPS after the fix versus 257 before; these runs establish
no material observed sampling overhead, not a new performance improvement.

The native counter selection regressions pass. Real-renderer monitor lifecycle,
settings and sampling tests with `NIGHTWATCH_MONITOR_GPU_TEST=1` also pass on
both backends: Vulkan 7.15% and OpenGL 14.05% at the printed sampling point.
Logs: `build/gpu-monitor-{vulkan,opengl}.log`; inspected Vulkan screenshot:
`build/gpu-monitor-vulkan.png` (9.2% at capture time).

Validation/export: `build/validation/20260911T150510326Z_b7755fe7/summary.json`
passed all 25 checks (24 fast gates and Windows export), with the native counter
regression test also passing during helper compilation. Both the game EXE and
its adjacent `NightwatchMetrics.exe` were refreshed.

## Meteor submission isolation

`meteor_submission_performance_probe.gd` isolates pose-only rendering of 1,000
frozen-shape targets. Use a real renderer, 1152x648, with sequential A/B runs:

```powershell
& $godot --path . --resolution 1152x648 --script res://tests/meteor_submission_performance_probe.gd
```

See [probe scope](probes.md), the [earlier shared-buffer baseline](history/render-pro-review-2026-09-12.md#local-measurements),
and the [retained-target measurements and candidate decisions](history/render-candidates-2026-09-12.md).
This measures batch submission, not natural late-game or fully observed target FPS.
