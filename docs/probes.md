# Tests and Probes

Every file in `tests/` is a `SceneTree` script run through `--script`, not a
GUT/gdUnit suite. There is no test runner to install. Sixteen files: six
pass/fail gates, seven measurement probes, two visual capture utilities, and
one human-driven survey slice. The full-tree economy gate is documented with
the pacing probes below because it reports both acceptance and diagnostic data.

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

The correctness gates are different: they are mechanical checks, not feel
measurements.

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
actions and their saved state, the six-second reveal and keyboard focus,
save-failure retry, active-final-watch resume/signature validation, corrupt-slot
recovery, the non-destructive ending-preview debug chord, performance caps,
stale references, and reset.

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

This is the current 107-functional-node economy driver. It runs deterministic,
scripted-engaged watches at `0.05s` steps until all research and all five
galactic phenomena are complete. One primary cursor handles phenomena, correct
comparison stars, distant hosts, and uncovered meteors in that order;
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
eight-wheel-event burst on every rendered frame, cursor motion over a tooltip,
the 3.6-second Galaxy Map pull-back, and the static final galaxy
frame. It reports frame-time percentiles, the synchronous workload time, and
the number of chart layout passes. The burst deliberately sends more wheel
events than a frame should commit; `layout_passes` should stay at roughly one
per rendered frame rather than eight. The candidate pull-back accepts only a
windowed `galactic_transition` and `galactic_final` p95 below 16.7 ms. The ENV
line records 12 rendered galactic research nodes plus 17 explicit muted
placeholders, 74 faint non-interactive
galactic background points, and pull-back duration. The final phase also includes
the miniature 95-node decorative core, radial halos, dashed orbits, code labels,
completion ledger, and fixed inspector introduced by the galaxy-map redesign.

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
`--headless` 없이 창 모드로 실행한다. 기본 캡처는 목업과 직접 비교할 수 있도록
앞의 열 계열을 완료하고 큰개자리 세 노드를 설치한 81/107 상태, 데이터
1,284,000, 5차 관측 80초 문맥을 재현한다.

```powershell
& "C:\Users\user\AppData\Local\Temp\codex-godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe" --path . --script res://tests/research_chart_preview.gd
```

성공하면 `PREVIEW_SAVED:` 한 줄이 나온다. 이것은 통과/실패 게이트가 아니라
그림을 보고 판단하기 위한 도구다.

`NIGHTWATCH_GALACTIC_RESEARCH_PREVIEW=1`은 최종 은하 축척을
`build/galactic_research_preview.png`로 저장한다. 여기에
`NIGHTWATCH_GALACTIC_RESEARCH_PREVIEW_TIME=0.65`처럼 0~3.6초 값을 함께 주면
해당 전환 프레임을 `build/galactic_research_transition_065.png` 형식으로
저장해 네 박자의 중간 상태를 확인할 수 있다.

```powershell
$env:NIGHTWATCH_GALACTIC_RESEARCH_PREVIEW = "1"
& $godot --path . --script res://tests/research_chart_preview.gd
Remove-Item Env:NIGHTWATCH_GALACTIC_RESEARCH_PREVIEW -ErrorAction SilentlyContinue
```

## 메인 HUD 캡처

`tests/hud_preview.gd`는 메인 HUD를 캡처해 `build/hud_preview.png`로 저장한다.
연구 성도 캡처와 같이 창 모드로 실행한다.

```powershell
& "C:\Users\user\AppData\Local\Temp\codex-godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe" --path . --script res://tests/hud_preview.gd
```

같은 스크립트에 `NIGHTWATCH_SURVEY_PREVIEW=1`을 설정하면 하늘 훑기를 구매하고
부분 충전된 커서 호를 `build/survey_preview.png`에 저장한다.

```powershell
$env:NIGHTWATCH_SURVEY_PREVIEW = "1"
& "C:\Users\user\AppData\Local\Temp\codex-godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe" --path . --script res://tests/hud_preview.gd
Remove-Item Env:NIGHTWATCH_SURVEY_PREVIEW -ErrorAction SilentlyContinue
```

`NIGHTWATCH_GALACTIC_PREVIEW=1`은 전체 연구를 설치하고 은하 지도가 열린 메인
하늘을 `build/galactic_preview.png`에 저장한다.

```powershell
$env:NIGHTWATCH_GALACTIC_PREVIEW = "1"
& "C:\Users\user\AppData\Local\Temp\codex-godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe" --path . --script res://tests/hud_preview.gd
Remove-Item Env:NIGHTWATCH_GALACTIC_PREVIEW -ErrorAction SilentlyContinue
```

`NIGHTWATCH_TRANSIT_PREVIEW=1`은 같은 완성 빌드에서 첫 확인을 마치고 두 번째
통과를 절반쯤 진행시켜 기준별 반경, 확인 점, 광도 하락, 행성 점을
`build/transit_preview.png`에 저장한다.
