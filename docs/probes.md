# Tests and Probes

Every file in `tests/` is a `SceneTree` script run through `--script`, not a
GUT/gdUnit suite. There is no test runner to install. Twelve files: two
pass/fail gates, seven measurement probes, two visual capture utilities, and
one human-driven survey slice.

Commands are PowerShell, matching the rest of the repo. `$godot` below is the
console build:

```powershell
$godot = "C:\Users\user\AppData\Local\Temp\codex-godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe"
```

See the [README](../README.md) for why that path is fragile.

**What the measurement probes measure.** The seven probes measure *productivity
and performance* — density, price, pacing, frame time. None of them measures
whether the game is fun, and none of them can. `tests/probe_layer2_test.gd`
says so in its own header. Fun decisions are made by playing a build. See
[design.md](design.md).

The two gates below are different: they are mechanical correctness checks, not
measurements.

### Blank-sky survey slice — `survey_slice.gd`

Runs one save-free, human-driven 60-second window with only Polar Survey added
to the opening sky. Track meteors and sweep empty sky with the same left button;
successful distance rolls call a meteor at the cursor. Release before changing
intent. It prints `SURVEY_SLICE_READY` and
one `SURVEY_SLICE_RESULT` line, but does not pass or fail because it measures
feel rather than correctness.

```powershell
& $godot --path . --script res://tests/survey_slice.gd
```

## Gates

### Smoke test

`AGENTS.md` requires the *relevant* tests before reporting a task complete.
This is the main-game gate: run it for any change that can affect the main
game. The Layer 2 gate below is the relevant one for changes touching that
testbed.

```powershell
& $godot --headless --path . --script res://tests/smoke_test.gd
```

Covers tutorial, saves, localization, phase summary, compact HUD, observation,
progression, events, performance caps, stale references, and reset.

- Pass: a single `SMOKE_TEST_PASS:` line
- Fail: `SMOKE:` error lines, then `SMOKE_TEST_FAIL: N failure(s)`

### Layer 2 probe test

Checks that the standalone Layer 2 testbed still holds together mechanically.
Deterministic at seed `20260821`.

```powershell
& $godot --headless --path . --script res://tests/probe_layer2_test.gd
```

- Pass: `PROBE_TEST_PASS: signals, uncertainty, commitment, abandonment, misses, and completion`
- Fail: `PROBE:` error lines, then `PROBE_TEST_FAIL: N`

## Measurement probes

These print tables. They do not pass or fail, except that they `push_error`
when a measurement invariant breaks — a cutoff object leaking between rounds,
or a shower crossing a round boundary. Treat those errors as a broken sample,
not as a balance result.

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

[duration-ladder-baseline.md](duration-ladder-baseline.md) records the accepted
baseline. When pacing or spawn logic changes, **compare against that baseline
first** and report the delta. Replace the document only when a new baseline has
been approved — silently overwriting it destroys the before/after comparison it
exists to provide.

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

Pass/fail gate for the expanded 78-system graph. It runs three deterministic
scripted-engaged watches at `0.05s` steps until all research is purchased. It
buys the cheapest currently available research at each intermission, applies
purchased Lyra calibration automatically, reproduces purchased Taurus combo
speed, Gemini echo bursts, and Leo storm charge, and uses predictive dishes
when installed. The engaged driver sweeps blank sky only while no manual meteor
target is available.

Every seed must reach 78/78, finish with exact unconditional `×256` observation
value, and keep the longest pre-completion interval without a newly available
node at or below `2 × MAX_OBSERVATION_DURATION` (currently 120 seconds).
Completion time is reported, not asserted. A 14,400-second watchdog catches a
stalled simulation without turning a target duration into design policy. Output
also includes total earned/banked Data, 270/540/810-second success checkpoints,
the purchase time of each `×2` leaf, the longest interval between those leaves,
purchase batches, and arrival gaps. Multiplier spacing and purchase-batch size
are playtest diagnostics, not automated pass/fail thresholds. This is the
authoritative economy-tuning gate for the live graph.

```powershell
& $godot --headless --path . --script res://tests/full_tree_economy_test.gd
```

Header: `FULL_TREE_ECONOMY_ENV`. Pass line: `FULL_TREE_ECONOMY_PASS`.

[`constellation-research-baseline.md`](constellation-research-baseline.md) is a
stale historical 41-system snapshot; it is not a live acceptance target.

### Duration matrix — `duration_matrix_probe.gd`

Sweeps all five durations against a synthetic 1080-second timeline for several
builds. This is a historical comparison horizon, not the live finale condition.
The live run now ends from research completion at a round boundary. Use this
probe only when a change needs comparison with the old duration matrix.

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

Header: `FRAME_PROBE_ENV`.

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

Measures the research chart in three automated three-second phases: open idle,
an eight-wheel-event burst on every rendered frame, and cursor motion over a
tooltip. It reports frame-time percentiles, the synchronous workload time, and
the number of chart layout passes. The burst deliberately sends more wheel
events than a frame should commit; `layout_passes` should stay at roughly one
per rendered frame rather than eight.

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

## 연구 성도 캡처

`tests/research_chart_preview.gd`는 설계 검토용으로 연구 화면을 캡처해
`build/research_chart_preview.png`로 저장한다. 렌더된 프레임이 필요하므로
`--headless` 없이 창 모드로 실행한다.

```powershell
& "C:\Users\user\AppData\Local\Temp\codex-godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe" --path . --script res://tests/research_chart_preview.gd
```

성공하면 `PREVIEW_SAVED:` 한 줄이 나온다. 이것은 통과/실패 게이트가 아니라
그림을 보고 판단하기 위한 도구다.

## 메인 HUD 캡처

`tests/hud_preview.gd`는 메인 HUD를 캡처해 `build/hud_preview.png`로 저장한다.
연구 성도 캡처와 같이 창 모드로 실행한다.

```powershell
& "C:\Users\user\AppData\Local\Temp\codex-godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe" --path . --script res://tests/hud_preview.gd
```

같은 스크립트에 `NIGHTWATCH_SURVEY_PREVIEW=1`을 설정하면 북극권 조사를 구매하고
부분 충전된 커서 호를 `build/survey_preview.png`에 저장한다.

```powershell
$env:NIGHTWATCH_SURVEY_PREVIEW = "1"
& "C:\Users\user\AppData\Local\Temp\codex-godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe" --path . --script res://tests/hud_preview.gd
Remove-Item Env:NIGHTWATCH_SURVEY_PREVIEW -ErrorAction SilentlyContinue
```
