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
covered by separate integration gates. Simulation uses 0.05s steps and a scripted
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

## Duration diagnostics

| Script | Fixed workload / environment | Use |
|---|---|---|
| `duration_ladder_probe.gd` | 18 rounds per duration, 0.05s steps, seed 20260821, denominator 40 | Compare the 20→60s ladder with its historical baseline |
| `duration_pricing_probe.gd` | 600 simulated seconds per cell, 0.05s steps, base seed 20260821; `NIGHTWATCH_PRICING_SEEDS=10` | Marginal Data at minimum prerequisite builds |
| `duration_matrix_probe.gd` | Five durations over a synthetic 1080s horizon; `NIGHTWATCH_MATRIX_SEEDS=5` | Historical matrix comparisons, not a live ending simulation |

Run these with `--headless --path . --script res://tests/<script>`.
Ordinary probe tables are measurements, not pass/fail gates. Any `push_error` invariant
failure invalidates the sample. Old 21/41-node prices and fixed 1080s horizons remain
in [the archive](history/README.md); do not use them as current balance acceptance targets.
