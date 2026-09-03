# Tests and Probes

Top-level entry points in `tests/` are `SceneTree` scripts run through `--script`,
not a GUT/gdUnit suite; `tests/support/` contains shared fixtures. There is no
test framework to install. This directory contains
twelve fast pass/fail gates, eight measurement probes, visual/audio review utilities, and
a human-driven survey slice. The full-tree economy gate is documented with
the pacing probes below because it reports both acceptance and diagnostic data.

Commands are PowerShell, matching the rest of the repo. `$godot` below is the
console build:

```powershell
$godot = "C:\Users\user\AppData\Local\Temp\codex-godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe"
```

See the [README](../README.md) for why that path is fragile.

**What the measurement probes measure.** The eight probes measure *productivity
and performance* — density, price, pacing, frame time. None of them measures
whether the game is fun, and none of them can. `tests/probe_layer2_test.gd`
says so in its own header. Fun decisions are made by playing a build. See
[design.md](design.md).

The correctness gates are different: they are mechanical checks, not feel
measurements.

## Routine validation

From the repository root, run all twelve fast gates and refresh the Windows
executable with the checked-in PowerShell runner:

```powershell
.\tools\validate.ps1 -GodotPath $godot -Build
```

Omit `-Build` for just the gates. Add `-FullEconomy` when a change can affect
progression, rewards, spawning, or target logic. The economy driver inherits
the seed/strategy environment described below; it does not silently become a
three-strategy run. Individual `--script` commands remain useful while iterating.
Default per-process limits are 180 seconds for a fast gate, 900 seconds for the
economy gate, and 300 seconds for export. Larger seed/strategy matrices may need
an explicit `-EconomyTimeoutSeconds` override.

The runner requires both exit code zero and the expected PASS line, rejects
script/parse failures and unexpected engine errors even when a PASS line also appears, and stops on the first
failed or timed-out process. Each run retains stdout/stderr and `summary.json`
under a unique `build/validation/` directory. A successful export is verified in
that run directory before replacing `build/windows/NightwatchArray.exe`.
On timeout, cleanup targets only that invocation's PID and its child process
tree: the Windows console launcher starts a separate engine process. It never
terminates other Godot instances by executable name.
Warnings and the reference gate's exact intentional missing-Git OS error stay
visible in the logs; only that gate-specific error line is exempt. Run `tools/validate_test.ps1`
to check the runner's success, failure, and wrapper/worker timeout handling
without Godot, including survival of an unrelated same-name process.

| Change | Additional evidence beyond the fast gates |
|---|---|
| UI, marker rendering, shared fonts/palette | Desktop-rendered reference corpus; compare against a pre-change corpus |
| Chart layout/animation performance | Windowed research UI probe; no parallel GPU measurements |
| Spawn/reward/progression | Full-tree economy gate and the relevant paired-seed probes |
| Sound | Audition recording and listening; dispatch tests alone do not judge audio |
| Core interaction | Human-driven slice/playtest; automated timing is not a fun verdict |

## Diagnostic isolation

`tests/support/game_fixture.gd` owns reusable no-persistence settings/slot
services and the silent sound fixture. `configure_before_ready(game)` replaces
services before the main scene enters the tree. Turning off the startup slot
prompt alone is insufficient: the ordinary settings node still reads disk and
closing the chart can save its rotation. Fixture slots cannot save, load, reset,
or create a directory; locale/tutorial/rotation setters remain in-memory.

The effect and visual gates, reference scenarios, HUD/chart previews, all three
main-game frame probes, and survey slice use this helper. Preview defaults are
English with onboarding disabled, independent of the player's saved settings;
the ending preview still supports an explicit locale. The silent sound fixture
is opt-in, not applied to listening tests. Stateful save/round tests retain their
own dedicated storage fixtures. No test imports a whole effect gate merely to
reuse these services; compatibility aliases remain for older local drivers.

### Blank-sky survey slice — `survey_slice.gd`

Runs one save-free, human-driven 60-second window with only Sky Sweep added
to the opening sky. Track meteors and sweep empty sky with the same left button;
successful distance rolls call a meteor at the cursor. Release before changing
intent. It prints `SURVEY_SLICE_READY` and
one `SURVEY_SLICE_RESULT` line, but does not pass or fail because it measures
feel rather than correctness.

```powershell
& $godot --path . --script res://tests/survey_slice.gd
```

## Gates

### UI presentation gate

`ui_presentation_test.gd` checks the shared spec-label/font/spacing contract and
grouped integer formatting, including HUD/chart compatibility wrappers and the
extracted marker alias. It does not replace pixel comparison.

```powershell
& $godot --headless --path . --script res://tests/ui_presentation_test.gd
```

- Pass: `UI_PRESENTATION_PASS`

### Diagnostic fixture gate

`game_fixture_test.gd` checks pre-ready replacement, deterministic in-memory
settings, rejected save/load/reset operations, cache-miss isolation, no save
directory creation, and silent dispatch through inactive pooled audio voices.

```powershell
& $godot --headless --path . --script res://tests/game_fixture_test.gd
```

- Pass: `GAME_FIXTURE_PASS`

### Meteor render arithmetic gate

`meteor_render_cache_test.gd` compares production ribbon coordinates, colors,
triangle indices and fragment-spark coordinates bit for bit with independent
arithmetic frozen from `347dcf0`. It exercises all eleven types, growing and
shrinking trails, curved/stationary paths, both sides of the head-sample skip
threshold, split/fade/linger poses, and direct type/age/lifetime mutations. The
same meteor instance is reused so stale caches are observable. Native drawing
runs inside its actual `_draw` callback, whose completion is required for PASS.

```powershell
& $godot --headless --path . --script res://tests/meteor_render_cache_test.gd
```

- Pass: `METEOR_RENDER_CACHE_PASS`

This is an arithmetic/call-path gate, not a GPU performance or pixel-quality
verdict. Keep the desktop reference corpus comparison for visual changes.

### Research visual gate

`research_visual_test.gd` checks every live branch binding through the chart's
production refresh route, all thirteen branch/state colour combinations,
unchanged alpha and marker radii, and luminance ordering across branches.
It also records actual `CanvasItem._draw` calls for star, cluster and galaxy
markers, including hover/hold foreground ink. This detects a helper that exists
but is not called by the renderer. Tutorial checks distinguish the obsolete
three-branch claim from the valid three-manual-save-slot statement in both
languages. Save/settings services are replaced before startup.

```powershell
& $godot --headless --path . --script res://tests/research_visual_test.gd
```

Passing prints `RESEARCH_VISUAL_PASS`. Mechanical RGB separation is not a claim
that a player can name all thirteen branches from hue alone. Use the reference
chart and synthetic palette plates for the visual hierarchy review.

### Sound feedback gate

`sound_feedback_test.gd` records production dispatch without playing it. It checks
research/slot/rare/environment routing, distinct PCM attacks and durations,
1,000 automatic events represented by 63 bounded-volume pulses, minimum 160 ms
spacing, sparse-tail drain, reset/pause isolation, and hitstop-independent time.
Its game fixture replaces slot storage with an in-memory controller before
startup; no user save is written. These are mechanical contracts, not a listening
verdict.

```powershell
& $godot --headless --path . --script res://tests/sound_feedback_test.gd
```

- Pass: `SOUND_FEEDBACK_PASS:`

For a listening check, run the save-free live audition without `--headless`:

```powershell
& $godot --path . --script res://tests/sound_feedback_preview.gd
```

The minimized helper plays research, slot, rare-target, and environment cues in
that order, then one isolated automatic completion and 1,000 automatic completions over ten seconds with four manual
successes. It records only its own Master bus (no microphone or OS loopback) to
`build/audio_feedback_audition.wav`, with cue timestamps and the SoundSynth source
hash in `build/audio_feedback_audition.json`. It leaves bus gain/mute and user
settings/saves untouched, removes its record effect, and quits. `SOUND_AUDITION_SAVED`
confirms non-silent PCM and a complete schedule, not perceptual quality; listen
for distinct event roles and gaps between automatic pulses.

On this machine WASAPI uses four stereo pairs: live playback has nonzero Master
peak, but `AudioEffectRecord` captures the last (silent) pair. Do not change OS
speaker settings to work around it. An explicit software-mixer recording is available:

```powershell
$env:NIGHTWATCH_AUDITION_ALLOW_DUMMY = "1"
try {
    & $godot --headless --audio-driver Dummy --path . --script res://tests/sound_feedback_preview.gd
} finally {
    Remove-Item Env:NIGHTWATCH_AUDITION_ALLOW_DUMMY
}
```

Its manifest explicitly marks `driver: Dummy` and `hardware_output: false`.
This produces a listenable stereo artifact, not proof of hardware output or a
perceptual verdict. The isolated completion deliberately retains the 160 ms
aggregation latency; manual success remains immediate.

### Effect feedback gate

`effect_feedback_test.gd` checks the routine/accent matrix through the main-game
completion handlers. Rare fireball/major identities and high manual grades keep
their explicit accent eligibility; combo, economy and proc origin cannot promote
a routine completion. It verifies directional particle cones, ring/flash/motion
thresholds, shared capacity caps, distant-target events, galaxy-stage flash
suppression and the pause-safe, replaceable installation-rule tween. The fixture
uses actual chart-open purchases at both scales and checks that the visible
inspector rule survives deferred container layout while paused. Selection,
context, close and scale changes cancel stale tweens; Reference Frame keeps its
pull-back without a hidden pulse. Save storage and settings are replaced before
startup. A mechanical pass is not a visual verdict.

```powershell
& $godot --headless --path . --script res://tests/effect_feedback_test.gd
```

- Pass: `EFFECT_FEEDBACK_PASS:`

For a narrow rendered stage-2 check, run without `--headless`:

```powershell
& $godot --path . --script res://tests/effect_feedback_preview.gd
```

This creates eight uniquely named PNG/JSON pairs in
`build/effect_feedback_review`: routine/accented observation poses and both
chart inspectors at installation-tween start, midpoint and end. The fixture
uses real completion/purchase routes without reading or writing saves/settings,
then freezes animation after deferred layout settles. Each sidecar records
viewport, renderer, base HEAD, dirty status, relevant source hashes and measured
state. A missing display, blank image, unexpected state/count or write failure
exits nonzero. `EFFECT_PREVIEW_PASS` means the eight diagnostic images were
written, not that animation feel was approved. This windowed diagnostic is not
the stage-3 headless capture gate.

### Research contract test

Checks 107 installable research definitions against the three-layer effect
schema, while the chart independently asserts 17 non-interactive Local Group
records. It requires every literal
`has_upgrade("id")` reference to resolve, every functional research
node to have one declared implementation connection, and the only production
parameter keys to have live consumers. Thirty-eight nodes have executable contracts:
ten global observation-value multipliers, four duration bonuses, four legacy
plus three Canis plus one Draco regular active-contact capacity deltas, and
three Canis plus one Draco regular-arrival floors, three simple Local Group
observation profiles, four chapter milestones, and five phenomenon contracts.
The other 69 functional ids are held as an exact
unverified baseline that may shrink but cannot silently grow or exchange ids.
The 17 decorative galaxies are separately required to remain chart records
rather than upgrade definitions.

Every ID lookup must preserve all definition fields and their read-only
contract. Unknown and empty IDs remain misses; each miss returns a fresh mutable
empty dictionary, and ID matching remains case-sensitive. These checks protect
the immutable ID index without changing the ordered research data or saves.

For each executable contract, the test compares independent expected behavior
against a public runtime accessor. It also checks English and Korean player
claims in both directions: every contract must be advertised, and every
advertised numeric claim must have a contract. The reverse check exists because
a 2026-08-26 copy audit verified all eight real `×2` claims but missed a ninth
false claim on Storm Zenith.

```powershell
& $godot --headless --path . --script res://tests/research_contract_test.gd
```

- Pass: `RESEARCH_CONTRACT_PASS: 107 installable research nodes, 38 executable contracts, 69 exact unverified ids, and bidirectional en/ko claims`
- Fail: `RESEARCH_CONTRACT:` error lines, then `RESEARCH_CONTRACT_FAIL: N failure(s)`

### Smoke test

`AGENTS.md` requires the *relevant* tests before reporting a task complete.
This is the main-game gate: run it for any change that can affect the main
game. The Layer 2 gate below is the relevant one for changes touching that
testbed.

```powershell
& $godot --headless --path . --script res://tests/smoke_test.gd
```

Covers tutorial, saves, localization, phase summary, compact HUD, observation,
the identity screen/world routing, fixed atmospheric rectangle, and background
coverage above the single galactic span ceiling, progression, events,
catalogue-ending eligibility and final-watch flow, ending finish/continue
actions and their saved state, the eight-second completed-map coda (the chart's
95 stars, twelve constellation shapes, and all 30 galaxy markers), the
presentation-only inclusion of 17 decorative galaxies, the two-second skip
boundary and identical natural/skip final frame, keyboard focus, save-failure
retry, active-final-watch resume/signature validation, corrupt-slot recovery, the non-destructive
ending-preview debug chord, performance caps, stale references, and reset.

- Pass: a single `SMOKE_TEST_PASS:` line
- Fail: `SMOKE:` error lines, then `SMOKE_TEST_FAIL: N failure(s)`

### Observation span gate

Runs identical fixed-seed atmospheric plans at span `1.0` and `1.1025`, requiring
exact serialized equality. It also checks the expanded visible rectangle,
screen-fixed input/effect/meteor budgets, background/flash coverage, and that
the sky gradient and horizon span the visible frame rather than stopping at the
fixed atmospheric boundary. The completed-tree row also requires common/fast
forecast visuals and hover targets to disappear while their internal contact
and automatic-dish assignment remain active.

```powershell
& $godot --headless --path . --script res://tests/observation_span_probe.gd
```

- Pass: `OBSERVATION_SPAN_PASS`

### Galactic vertical-slice gate

Checks the 12-functional/17-decoration Local Group topology, exact four-step
span, one-to-two distant-target capacities, and four presentation-only chapter-one
profiles. It asserts that removed comparison, decoy, reveal, linked-priority,
and forecast rules cannot re-enter those profiles; one hold both completes and
pays a target without a second harvest gesture; M31 drifts visibly; and the
two-target state survives save/load. It also covers persistent supernova
recovery, the two-item phenomenon queue, ordinary hold observation on
full/partial lens shapes, fixed-endpoint
visual lens curves with automation still enabled, unchanged meteor cap 32,
unchanged global `×8192`, the canonical five-record completion predicate and
its save/load filtering, and the 436.8 px/s dish regression.

```powershell
& $godot --headless --path . --script res://tests/galactic_slice_test.gd
```

- Pass: `GALACTIC_SLICE_PASS`

### Layer 2 probe test

Checks that the standalone Layer 2 testbed still holds together mechanically.
Deterministic at seed `20260821`.

```powershell
& $godot --headless --path . --script res://tests/probe_layer2_test.gd
```

- Pass: `PROBE_TEST_PASS: signals, uncertainty, commitment, abandonment, misses, and completion`
- Fail: `PROBE:` error lines, then `PROBE_TEST_FAIL: N`

## Measurement probes

The ordinary probes print tables. They do not pass or fail, except that they
`push_error` when a measurement invariant breaks — a cutoff object leaking
between rounds, or a shower crossing a round boundary. Treat those errors as a
broken sample, not as a balance result. The full-tree economy driver is the
exception: it is also a gate for mechanical completion, source-ledger
reconciliation, complete node timelines, and the approved 120-second maximum
research-arrival gap. It does not gate on a target completion time.

Each probe prints an `*_ENV` header line first, recording the engine version
plus the run parameters that apply to it — seed and step size for the
simulation probes, renderer and duration for the frame probes. Quote that line
when you record results, or the numbers are not reproducible.

### Duration ladder — `duration_ladder_probe.gd`

Re-measures the 20 → 30 → 40 → 50 → 60-second ladder. 18 rounds per rung,
`0.05s` steps, seed `20260821`, pacing denominator 40. The linked baseline keeps
the historical 21-node / denominator-20 result for before-and-after comparison.

```powershell
& $godot --headless --path . --script res://tests/duration_ladder_probe.gd
```

Header: `DURATION_LADDER_PROBE_ENV`. No environment variables.

[duration-ladder-baseline.md](duration-ladder-baseline.md) preserves the formerly
accepted 21-node baseline and is explicitly stale after the 2026-08-26 economy
change. Use it for historical comparisons, not as a current price or completion
target. Use the full-tree driver for the live 107-node graph. Keep both old and
new evidence when comparing a change; do not overwrite historical measurements.

### Duration pricing — `duration_pricing_probe.gd`

Measures the marginal Data a duration node buys at its minimum prerequisite
build, which is where the approved prices came from. 600 simulated seconds per
cell, `0.05s` steps, base seed `20260821`.

```powershell
& $godot --headless --path . --script res://tests/duration_pricing_probe.gd
```

| Variable | Default | Effect |
|---|---|---|
| `NIGHTWATCH_PRICING_SEEDS` | `10` | Seed count per cell |

Header: `DURATION_PRICING_ENV`.

### Full-tree economy gate — `full_tree_economy_test.gd`

This is the current 107-functional-node economy driver. It runs deterministic,
scripted-engaged watches at `0.05s` steps until all research and all five
galactic phenomena are complete. One primary cursor handles phenomena, distant
hosts, and uncovered meteors in that order;
Multi-target Analysis can affect additional targets only from that same cursor
point and inside the production tracking radius. Predictive dishes, survey
summons, purchased Lyra calibration, Taurus combo speed, Gemini echoes, Leo
storms, immediate-pay hosts, supernova clocks, and lens contact shapes all run
through their production controllers.

That `107/107 + 5/5` stop is the content/economy measurement boundary, not a
simulation of the shipped catalogue-ending presentation. The driver stops as
soon as the conjunction is reached. It does not play the required fully
researched final watch, traverse `phase summary → completed chart → ending`,
press Finish or Continue, or test the ending's saved seen/pending state. Those
contracts belong to the main-game correctness gate.

The three purchase strategies are greedy intermission heuristics. `cheapest`
uses price only. `automation_first` and `manual_first` rank nodes that are
affordable at that moment, but neither reserves Data for a preferred node that
is still unaffordable. They are comparison scenarios, not optimized builds or
human behavior models. All three use the same fixed target priority; the probe
records supernova phase outcomes but does not compare alternate phase-timing
strategies.

Each node records R/A/F/P: revealed, prerequisites-satisfied available, first
affordable, and purchased. The driver separately accounts for manual meteors,
automatic meteors, hosts, and phenomena, then reconciles both source total and
`earned - purchased cost - bank`. Hosts are manual-only in the current runtime,
so the automatic-host field is expected to remain zero.

Every sample must satisfy:

- 107/107 functional research and five/five phenomena;
- a research completion time and a content completion time no earlier than it;
- exact final `×8192` observation value and `1.4774554` observation span;
- non-zero manual-meteor, automatic-meteor, host, and phenomenon income;
- source and bank reconciliation errors no larger than `0.5` Data;
- non-negative bank and complete R/A/F/P records for all 107 nodes; and
- no pre-completion newly-available-node gap above the approved
  `2 × MAX_OBSERVATION_DURATION` ceiling, currently 120 seconds.

Completion time, strategy deltas, purchase-batch size, affordable-to-purchase
delay, Local Group purchase gaps, phenomenon experience delay, round rates, and
cursor shares are diagnostics rather than acceptance targets. The 14,400-second
watchdog detects a stalled script without turning duration into balance policy.

```powershell
& $godot --headless --path . --script res://tests/full_tree_economy_test.gd
```

| Variable | Default | Effect |
|---|---|---|
| `NIGHTWATCH_ECONOMY_SEEDS` | `20260821,20260837,20260853` | Comma-separated integer seeds |
| `NIGHTWATCH_ECONOMY_STRATEGIES` | `cheapest` | Comma-separated subset of `cheapest`, `automation_first`, `manual_first` |

Output prefixes are `FULL_TREE_ECONOMY_ENV`, `RESULT`, `INCOME`, `PACING`,
`LOCAL_GROUP`, `TIMELINE`, and `SUMMARY`, followed by
`FULL_TREE_ECONOMY_PASS`. `TIMELINE` preserves all 107 raw R/A/F/P records.
Failures use `FULL_TREE_ECONOMY_INVALID` and `FULL_TREE_ECONOMY_FAIL`.

[full-tree-economy-baseline.md](full-tree-economy-baseline.md) records the
2026-08-30 three-strategy, three-seed result and its interpretation limits.

[`constellation-research-baseline.md`](constellation-research-baseline.md) is a
stale historical 41-system snapshot; it is not a live acceptance target.

### Duration matrix — `duration_matrix_probe.gd`

Sweeps all five durations against a synthetic 1080-second timeline for several
builds. This is a historical comparison horizon from before the content-driven
catalogue ending. Its fixed 1080-second cutoff is not the live ending condition
and does not model the final full-research watch or ending UI. Use this probe
only when a change needs comparison with the old duration matrix.

```powershell
& $godot --headless --path . --script res://tests/duration_matrix_probe.gd
```

| Variable | Default | Effect |
|---|---|---|
| `NIGHTWATCH_MATRIX_SEEDS` | `5` | Seed count per cell |

Header: `DURATION_MATRIX_ENV`.

### Contact density — `contact_density_probe.gd`

Counts what is on screen over a 30-second phase: pending forecast contacts,
live meteors, and combined workload, per type. Behind
[legacy-density-be11e42.md](legacy-density-be11e42.md).

The legacy completed-tree regular capacity is eight. Canis Major raises the
live endpoint to twelve and lowers the regular-arrival floor from 1.15 to 0.70
seconds; Draco raises the final endpoint to eighteen and lowers the floor to
0.45 seconds. The linked legacy baseline froze a four/six-cap tree and is not a
current density or performance acceptance target. The probe deliberately keeps
`EventController` stopped, so its completed row isolates the new regular
floor/cap and excludes the once-per-round Major Fireball.

```powershell
& $godot --headless --path . --script res://tests/contact_density_probe.gd
```

Eleven driver modes:

| Mode | |
|---|---|
| `no-input` | does nothing |
| `scripted-engaged` | scripted manual driver |
| `baseline-engaged` | manual driver with no hidden research |
| `fast-manual-placement-one-dish` / `-two-dish` | hand-placed dishes |
| `fast-predictive-auto-one-dish` / `-two-dish` | automatic idle-dish pre-positioning |
| `all-eligible-two-dish` | every dish-trackable type assigned |
| `fragment-assigned-one-dish` | fragment handling |
| `selector-partner-first` / `selector-bank-first` | lane selector ordering |

| Variable | Default | Effect |
|---|---|---|
| `NIGHTWATCH_CONTACT_PROBE_SEED` | `20260821` | Spawn seed; invalid values warn and fall back |

Header: `CONTACT_DENSITY_PROBE_ENV`.

`no-input` rows are control observations, not acceptance targets. Burnout
planning deliberately distributes endpoints across the whole sky, so a dish
left at its central home position no longer earns accidental unattended
completions. Evaluate workload and completion acceptance on the engaged,
placement, automatic-assignment, and selector rows. Keep printing the
`no-input` rows so that the control remains visible; do not tune trajectories
back toward the center merely to restore those numbers.

The probe also prints `realized_objects_by_type`. Use its `fragment_piece`
bucket when a fragment split or lifetime change could alter child density.

Do not accept or reject trajectory, dish, or burnout changes from the default
single seed. The engaged/assignment rows often contain only single-digit
completions in 30 seconds, so one changed endpoint can look like a large
percentage regression. Run at least 8–10 paired seeds for the old and new
builds, then aggregate `observations_completed`, `dish_acquisitions_by_type`,
`dish_completions_by_type`, and `opportunistic_dropped_without_completion` for
the engaged, placement, automatic-assignment, and selector rows. In the
2026-08-22 burnout review, the default seed made the two-dish manual row look
like a 9→4 collapse, while ten paired seeds produced 59→60. The same aggregate
still exposed a real fast dish-conversion change (92.3%→84.9%), showing why
both total completions and conversion/drop counts are required.

```powershell
20260821..20260830 | ForEach-Object {
    $env:NIGHTWATCH_CONTACT_PROBE_SEED = $_
    & $godot --headless --path . --script res://tests/contact_density_probe.gd
}
Remove-Item Env:NIGHTWATCH_CONTACT_PROBE_SEED -ErrorAction SilentlyContinue
```

### Frame pacing — `frame_pacing_probe.gd`

Frame-time distribution of the main game. Exists because input-driven frame
spikes were a real regression once.

**This probe is human-driven, not scripted.** It reads the real cursor and
prints `FRAME_PROBE_READY` with instructions you are expected to follow: hold
still during seconds 1–7 and 19–24, move rapidly during seconds 8–18. Run it
windowed and actually do that, or the input-load half of the sample is empty.

The isolated fixture extends only its synthetic observation window to at least
the requested measurement duration plus one second. This keeps the final samples
on the live sky instead of the ordinary 20-second opening round's paused summary.
The ENV line reports `observation_window_seconds`; old 20–24-second samples
that included the summary are not a comparable live-sky baseline. Production
round duration and research are unchanged.

```powershell
& $godot --path . --script res://tests/frame_pacing_probe.gd
```

A `--headless` run still completes, but it is a CPU fixture with zero draw
calls. It does not measure the real GL render ceiling —
[legacy-density-be11e42.md](legacy-density-be11e42.md) notes the same limit.
Use headless for regression comparison between two headless runs only.

| Variable | Default | Effect |
|---|---|---|
| `NIGHTWATCH_PROBE_SECONDS` | `24` | Probe duration |
| `NIGHTWATCH_RENDER_STRESS_OBJECTS` | `18` | Visible stress objects; set to `32` to exercise the global ceiling, including one Major Fireball |

Header: `FRAME_PROBE_ENV`.

### Synthetic observation A/B workload — `observation_performance_probe.gd`

Runs still, unpressed cursor sweep, and held tracking at exactly 18 or 32 live
meteors, including one Major at 32. Each rendered frame advances one fixed
1/60-second simulation step: 60 warm-up frames, then 360 measured frames per
phase by default. Six simulated seconds are not six seconds of wall time.
The replacement cursor sampler preserves the scene's `z_index = 50`; hardware
input is disabled and no OS cursor movement is injected.

Bounded ages, disabled splitting and immediate in-place replenishment keep the
workload constant, intentionally excluding normal spawning, expiry and
completion linger. The isolated `multi_target_analysis` feature exercises
additional-target scanning but is not a legal completed research build. Real
observation, meteor, completion feedback, HUD and twinkle code still execute.
Automation, Sky Sweep summons, distant targets, phenomena and audio playback
are excluded. In particular, `sweep` means moving hover selection, not the
game's held-button Sky Sweep mechanic or a human input-feel test.

```powershell
& $godot --display-driver windows --rendering-driver opengl3 `
    --rendering-method gl_compatibility --audio-driver Dummy `
    --position '-4000,-4000' --resolution 1152x648 `
    --path . --script res://tests/observation_performance_probe.gd
```

`NIGHTWATCH_OBSERVATION_PERF_FRAMES` accepts 180..1800 measured frames per phase;
compare identical frame counts and environments. `OBSERVATION_PERF_ENV` records
the workload, source hashes and limitations; six `OBSERVATION_PERF_RESULT` JSON
rows report frame percentiles, synchronous work, render monitors and actual
counts. `OBSERVATION_PERF_PASS` validates workload integrity, not a speed target:
source hashes must stay unchanged, every declared meteor must remain live with
its head inside the viewport and more than one trail sample, sweep must move
and find targets, and hold must track, complete and
land packets. A 180-second watchdog bounds the run.

Windowed OpenGL provides rendering evidence. `--headless` is explicitly
CPU-only and useful for mechanical validation. `sync_work_ms` excludes draw
submission and probe bookkeeping; wall-frame intervals include bookkeeping.
`TIME_PROCESS` is a coarse end-of-phase monitor, not per-frame timings. The
production hover ring uses real time, so its pulse phase is not a deterministic
pixel oracle. Use the reference capture tool for fixed-pose pixel comparisons.

### Layer 2 frame pacing — `probe_frame_pacing_probe.gd`

Same measurement for `scenes/probe_layer2.tscn`, with the same windowed-versus-
headless caveat.

```powershell
& $godot --path . --script res://tests/probe_frame_pacing_probe.gd
```

| Variable | Default | Effect |
|---|---|---|
| `NIGHTWATCH_PROBE_SECONDS` | `8` | Probe duration |
| `NIGHTWATCH_PROBE_FINISHED` | unset | Set to `1` to measure the finished-state probe |

Header: `LAYER2_FRAME_PROBE_ENV`.

### Research UI frame pacing — `research_ui_frame_probe.gd`

Measures the research chart in five automated phases: open idle, an
eight-wheel-event burst on every rendered frame, alternating fixed-inspector selections,
the 3.6-second Galaxy Map pull-back, and the static final galaxy
frame. It reports frame-time percentiles, the synchronous workload time, and
the number of chart layout passes. The burst deliberately sends more wheel
events than a frame should commit; `layout_passes` should stay at roughly one
per rendered frame rather than eight. The candidate pull-back accepts only a
windowed `galactic_transition` and `galactic_final` p95 below 16.7 ms. The ENV
line separately records 12 galactic research nodes, 17 non-interactive
decorative records, 74 faint non-interactive
galactic background points, and pull-back duration. The final phase also includes
the miniature 95-node decorative core, radial halos, dashed orbits, code labels,
completion ledger, and fixed inspector introduced by the galaxy-map redesign.

The probe uses the no-persistence fixture and scripted input with hardware
events disabled. `inspector_selection` alternates two real node selections;
the previous node receives an unhover before the next hover, and
`inspector_refreshes` records the real content updates. The old `tooltip_motion`
phase called a now-fixed positioning method and no
longer represented moving UI. These two phase labels are not comparable
performance samples. The other phase contracts are unchanged. A headless run
remains a CPU-only comparison, not rendered frame-time evidence.

The profiling subclass preserves the scene's chart layer (100, above HUD 80)
and reports `RESEARCH_UI_CPU` totals/calls/average-call milliseconds for layout,
ledger, inspector and `_draw_tree()`. These timings are inclusive and overlap;
do not add them. Draw timing excludes child star-marker `_draw()` calls and GPU
work. Compare average-call time rather than totals when frame counts differ.
The last deferred draw can fall outside its input phase, so draw calls need not
equal layout passes. `RESEARCH_UI_PROBE_SOURCES` records the relevant hashes;
source changes during a run invalidate it.

Run it windowed so the draw-call and primitive counts represent the shipped
renderer:

```powershell
& $godot --path . --script res://tests/research_ui_frame_probe.gd
```

Header: `RESEARCH_UI_PROBE_ENV`.

## Setting an environment variable

PowerShell has no inline variable prefix:

```powershell
$env:NIGHTWATCH_PRICING_SEEDS = "20"; & $godot --headless --path . --script res://tests/duration_pricing_probe.gd
```

## Research chart preview

`tests/research_chart_preview.gd` writes `build/research_chart_preview.png` for
design review. Run windowed, not `--headless`. Its synthetic reference state
contains 81/107 installed research (ten complete constellations and three Canis
nodes), 1,284,000 Data, and fifth-round/80-second context for mock-up comparison.
This is a diagnostic pose, not a playable 80-second observation round.

```powershell
& "C:\Users\user\AppData\Local\Temp\codex-godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe" --path . --script res://tests/research_chart_preview.gd
```

`PREVIEW_SAVED:` means an image was written, not that its design passed review.

`NIGHTWATCH_GALACTIC_RESEARCH_PREVIEW=1` selects the final galaxy scale and writes
`build/galactic_research_preview.png`. Add a time between 0 and 3.6 seconds, such
as `NIGHTWATCH_GALACTIC_RESEARCH_PREVIEW_TIME=0.65`, to inspect an intermediate
pull-back pose in `build/galactic_research_transition_065.png`.

```powershell
$env:NIGHTWATCH_GALACTIC_RESEARCH_PREVIEW = "1"
& $godot --path . --script res://tests/research_chart_preview.gd
Remove-Item Env:NIGHTWATCH_GALACTIC_RESEARCH_PREVIEW -ErrorAction SilentlyContinue
```

## Main HUD preview

`tests/hud_preview.gd` writes `build/hud_preview.png`. Like the chart preview,
it requires a windowed renderer.

```powershell
& "C:\Users\user\AppData\Local\Temp\codex-godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe" --path . --script res://tests/hud_preview.gd
```

Set `NIGHTWATCH_SURVEY_PREVIEW=1` to install Sky Sweep and capture its partially
charged cursor arc in `build/survey_preview.png`.

```powershell
$env:NIGHTWATCH_SURVEY_PREVIEW = "1"
& "C:\Users\user\AppData\Local\Temp\codex-godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe" --path . --script res://tests/hud_preview.gd
Remove-Item Env:NIGHTWATCH_SURVEY_PREVIEW -ErrorAction SilentlyContinue
```

`NIGHTWATCH_GALACTIC_PREVIEW=1` installs all research and captures the galaxy-stage
observation sky in `build/galactic_preview.png`.

```powershell
$env:NIGHTWATCH_GALACTIC_PREVIEW = "1"
& "C:\Users\user\AppData\Local\Temp\codex-godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe" --path . --script res://tests/hud_preview.gd
Remove-Item Env:NIGHTWATCH_GALACTIC_PREVIEW -ErrorAction SilentlyContinue
```

`NIGHTWATCH_TRANSIT_PREVIEW=1` uses that completed build with the first host's
first transit window at 48% and writes `build/transit_preview.png`. It does not
perform a prior confirmation or a separate harvest; those interactions were
removed in the approved Local Group simplification.

### Catalogue-ending capture

`NIGHTWATCH_ENDING_PREVIEW=1` selects the non-persistent ending preview in the
same HUD capture script and writes `build/ending_preview.png`.
`NIGHTWATCH_ENDING_PREVIEW_STEP` advances the paused reveal by a deterministic
number of seconds; its default is `8.1`, the completed frame. Use `2.8` for the
completed constellations, `5.2` for the galaxy transition, and `8.1` for the
final map-and-record layout. Each run replaces the same image, so inspect or
copy it before capturing another frame. Set `NIGHTWATCH_ENDING_PREVIEW_LOCALE`
to `en` or `ko` to inspect either layout without changing saved settings.
These are visual checks, not proof of
real-time animation pacing or a replacement for the smoke gate.

```powershell
$env:NIGHTWATCH_ENDING_PREVIEW = "1"
$env:NIGHTWATCH_ENDING_PREVIEW_STEP = "8.1"
& $godot --path . --script res://tests/hud_preview.gd
Remove-Item Env:NIGHTWATCH_ENDING_PREVIEW -ErrorAction SilentlyContinue
Remove-Item Env:NIGHTWATCH_ENDING_PREVIEW_STEP -ErrorAction SilentlyContinue
```

## Reference capture gate (stage 3)

`tests/capture_reference.gd` regenerates thirteen visual references in one run:
eleven scene states from stage 3 and two diagnostic palette plates from stage 4.
Each run gets a new `build/reference/<revision12>[_dirty]_<timestamp>/` directory;
existing captures are never overwritten. Its manifest and every PNG's JSON
sidecar identify the full Git HEAD, dirty flag, SHA-256 of every tracked and
non-ignored untracked source file, source digest, Godot version, viewport,
display driver, scenario contract, observed state and actual PNG hash.

This replaces `build/claude_design_screenshots/`, a hand-made corpus whose
files were named `*_current_*` with no generator in the repository. Five days
and twenty-four script changes after it was made, three separate reviewers
still read those files as current and misdiagnosed the shipped screens from
them. A semantic filename is a claim nothing enforces, so the revision now
travels with the pixels and the corpus is reproducible from one command.

The old directory is retained, with a `STALE.md` notice, as historical evidence.
Do not treat its `current` filenames as current screenshots.
The rejected prototype's twelve loose files were also moved out of the reference
root into `build/reference-legacy-unstamped-20260903/` with a stale notice.

The verified Windows Godot 4.7.2 binary exposes only dummy rendering with the
headless display driver. The generator explicitly rejects `--headless` with
exit 1 before creating a run directory. This supported capture path uses a real
Windows/OpenGL renderer and moves its window off-screen; it requires a logged-in
desktop session, not a display-less CI worker. This is not a claim about every
possible Godot platform/backend. See the official
[RenderingServer documentation](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html)
and inspect the actual binary's `--help` for its supported driver combinations.

```powershell
& $godot --display-driver windows --rendering-driver opengl3 `
    --rendering-method gl_compatibility --audio-driver Dummy `
    --position '-4000,-4000' --resolution 1152x648 `
    --path . --script res://tests/capture_reference.gd
```

Passing prints `REFERENCE_CAPTURE_PASS: <n>/<n> at <revision>`. A capture taken
over uncommitted work additionally prints `REFERENCE_CAPTURE_DIRTY:` and sets
`source.revision_dirty` in the manifest; that is useful while iterating, but
must be described as that base revision plus the recorded working tree, never
as the clean commit. Refresh the corpus after committing and verify the clean
flag before using it as a revision baseline.

The eleven scenarios cover an actively tracked observation HUD (67%), an
eleven-object synthetic density plate with active tracking (42%),
both meteor families, the sky sweep, the round summary, the research chart,
the pulled-back galactic sky, the exoplanet transit, the Local Group map and
the catalogue ending. `meteor_family_special` captures the five late
silhouettes — comet, satellite, variable star, binary star and galaxy — which
the old corpus never contained. These are controlled diagnostic states, not
measurements of live spawn density, economy or pacing. The mid-run research
chart installs 81 nodes through real purchase requests; the galactic scenarios
install all 107. The transit is explicitly at 48% of its first window and the
ending reveals all five recorded phenomena.

`palette_active` and `palette_inactive` are explicitly synthetic, labelled
plates, not gameplay charts. Each uses 117 real `StarNodeVisual` instances:
thirteen branch columns, three marker kinds and three states per plate.
Purchased/affordable/unaffordable are separated from locked/hidden/teaser.
The manifest records every cell's rectangle, input colour, kind and state for
pixel comparisons. Compare the active cells before/after the colour change;
the complete inactive plate must remain byte-identical. Existing scene states
remain the context for judging the actual screen, not just isolated marks.

`tests/support/reference_capture_scenarios.gd` replaces save/settings services
before `_ready`, disables hardware input, seeds RNGs and freezes processes,
tweens and visual clocks. Synthetic positions, trail ages and a 30-second
diagnostic target lifetime are declared fixture inputs. Supernova rendering
uses `capture_time_override_msec = 0` only in this fixture; its production
default of -1 preserves the live clock. Expected counts, research state,
selection, tracking, overlays and isolation are checked before and after
rendering. Empty state inspection is an error, including after a script error.

The image gate requires the expected dimensions, visible light/dark pixels and
two consecutive identical pixel hashes within twelve frames. The run checks
unchanged source identity before publishing sidecars and a passed manifest;
missing Git, changing source, a blank/unstable frame, a missing scenario or a
failed write exits nonzero. A 90-second watchdog bounds stalled rendering.
Consumers must require the run manifest's `status: passed`, matching sidecars
and matching PNG hashes; a partial directory is not a valid corpus.

The companion headless gate checks malformed image/manifest/Git rejection and
all thirteen isolated scenario states across engine frames:

```powershell
& $godot --headless --path . --script res://tests/reference_capture_test.gd
```

Passing prints `REFERENCE_CAPTURE_TEST_PASS`. Its missing-Git negative case
intentionally emits an OS child-process error before the PASS marker. It does
not render PNGs or replace the desktop-rendered gate.

`REFERENCE_CAPTURE_PASS` means all declared states and their stable, nonblank
images passed the mechanical checks. It is not a judgement of focal hierarchy,
silhouette
legibility, overlap or semantic colour separation; those remain human review
against the captured frames.
