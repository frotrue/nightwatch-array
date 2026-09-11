# Tests and Probes

Run commands from the repository root in PowerShell. Set `$godot` to the console
binary shown in the [README](../README.md#실행과-빌드). Tests are `SceneTree` scripts;
no GUT/gdUnit installation is needed.

## Routine validation

```powershell
.\tools\validate.ps1 -GodotPath $godot -Build
```

This runs the 23 fast gates below, then exports Windows. Add `-FullEconomy` for
changes to progression, rewards, spawning or target logic. Omit `-Build` to test only.
The economy run inherits its seed/strategy environment; it does not force three strategies.

Success requires exit 0, the exact expected PASS line, and no unexpected engine,
script or parse errors. Stop at the first failure/timeout. Logs and `summary.json`
are retained in a unique `build/validation/<run ID>/`. A validated staged export
replaces `build/windows/NightwatchArray.exe`; a failed export is not completion.

Default timeouts are 180s per fast gate, 900s for economy and 300s for export.
Overrides are `-TimeoutSeconds`, `-EconomyTimeoutSeconds` and `-BuildTimeoutSeconds`.
Timeout cleanup targets only that invocation's PID tree, including the console
launcher's engine child. `tools/validate_test.ps1` tests runner success/failure and
timeout isolation without Godot. Keep the exact intentional missing-Git OS error
exemption confined to the reference-capture gate.

| Change | Additional evidence |
|---|---|
| UI, markers, fonts or palette | Relevant desktop captures; compare with a pre-change corpus |
| Chart/render performance | Sequential windowed probes with unchanged source hashes |
| Spawn, reward, progression or target logic | Full-tree economy and relevant paired-seed probes |
| Sound | Audition artifact and listening |
| Core interaction | A human slice/playtest in addition to mechanical checks |

Commands and acceptance boundaries: [visual/audio validation](visual-validation.md),
[performance/economy probes](performance-probes.md).

## Diagnostic isolation

`tests/support/game_fixture.gd::configure_before_ready(game)` replaces save/settings
services before the scene enters the tree. It rejects persistence and avoids reading
the player's locale, bindings, audio, display or chart rotation. Disabling only the
startup-slot prompt is insufficient. Stateful storage tests use unique temporary paths.
Tests that mutate global InputMap/audio/display/pause state must restore it.

The silent audio fixture is opt-in; do not use it for listening tests.
Synthetic poses and scripted drivers are diagnostic inputs, not player behavior.
Mechanical passes establish behavior, screenshots establish layout, and measured
frame/observation times do not establish fun, comfort or real playthrough duration.

## Fast gates

Each file below is under `tests/`. Run one while iterating with:

```powershell
& $godot --headless --path . --script res://tests/smoke_test.gd
```

| Script | Expected marker | Main coverage |
|---|---|---|
| `threaded_simulation_test.gd` | `THREADED_SIMULATION_PASS` | Live, batched single-thread and parallel motion/contact equivalence; worker cap, real worker execution, equipment/hitstop, pause and thread joins |
| `research_contract_test.gd` | `RESEARCH_CONTRACT_PASS` | 95 definitions, 26 executable contracts, exact 69 unverified IDs, bidirectional en/ko claims, opening budgets |
| `save_integrity_test.gd` | `SAVE_INTEGRITY_PASS` | Atomic replacement, injected write/rename failures, invalid slots/payloads, prior bytes and summary preservation |
| `smoke_test.gd` | `SMOKE_TEST_PASS` | Main loop, saves, localization, held tracking/sweep, input/modals/settings, round accounting; immediate echo unlock/legacy channels, additive dish forecasts, screen-space survey counts and manual-only spectral rewards |
| `deep_sky_test.gd` | `DEEP_SKY_PASS` | Original 95-node path, coordinate-based module unlock, chart purchases, five-slot pointer/input flow, pause recovery, effects and migration |
| `expansion_state_test.gd` | `EXPANSION_STATE_PASS` | Predecessor research, replacement draw determinism, additive copies and malformed saves |
| `module_expansion_test.gd` | `MODULE_EXPANSION_PASS` | Eight-module catalogue, swept line geometry, live field slowdown, burst lifecycle, copy persistence and retired inventory |
| `module_inventory_test.gd` | `MODULE_INVENTORY_PASS` | Eight active entries, categories, ownership, scroll/focus controls, tooltip anchors, keyboard disclosures, condensed result context, tutorial/HUD ownership and routine banner suppression |
| `deep_sky_chart_expansion_test.gd` | `DEEP_SKY_CHART_EXPANSION_PASS` | Dedicated draw view, animation/skip/double-click/reduced-motion, save failure and modal return |
| `constellation_extension_test.gd` | `CONSTELLATION_EXTENSION_PASS` | Original geometry preserved, shared Alpheratz, forty-two mapped stars across nine figures, real hold purchases, permanent growth/target unlocks, save compatibility and bilingual navigation |
| `expansion_integration_test.gd` | `EXPANSION_INTEGRATION_PASS` | Real rare targets and all research without specimen modules, duplicate rewards, transactional failure, active save/load, all seven active permanent growth roles and round context; manual/automatic split pairs, seeded hit/miss, reward, recursion exclusion, reserved capacity and expiry; mixed completion overcharge, rare-target slowdown and obsolete saved hold rejection and chart pause |
| `observation_span_probe.gd` | `OBSERVATION_SPAN_PASS` | Fixed-seed atmospheric equality, screen/world bounds, input/effect scaling, forecast suppression |
| `content_retirement_test.gd` | `CONTENT_RETIREMENT_PASS` | Retired layers/research/ending absent; old-save and debug isolation; eight-module pool; inactive ownership retained |
| `probe_layer2_test.gd` | `PROBE_TEST_PASS` | Independent Layer 2 signals, uncertainty, commitment, abandonment and completion |
| `sound_feedback_test.gd` | `SOUND_FEEDBACK_PASS` | Event dispatch, PCM distinctions, 1,000 automatic events aggregated into 63 pulses, timing and queue clearing |
| `effect_feedback_test.gd` | `EFFECT_FEEDBACK_PASS` | Routine/accent routing, real visible installation rule, pause/selection cancellation, capacity limits and dawn/summary pause, load, next-round and zero-motion lifecycle |
| `reference_capture_test.gd` | `REFERENCE_CAPTURE_TEST_PASS` | Thirteen isolated scenario states, malformed image/manifest/Git rejection; no PNG rendering |
| `research_visual_test.gd` | `RESEARCH_VISUAL_PASS` | Actual marker draw paths, branch/state color bindings, alpha/radii and tutorial claims |
| `ui_presentation_test.gd` | `UI_PRESENTATION_PASS` | Authored readout fonts/ink, independent scene state, collapsed summary defaults, initial slot localization, procedural type conversion, full integer formatting and compact/scientific notation |
| `game_fixture_test.gd` | `GAME_FIXTURE_PASS` | Pre-ready isolation, rejected persistence, settings/binding schemas, conflict checks, notation persistence/live refresh and pointer-through numeric tooltips |
| `meteor_render_cache_test.gd` | `METEOR_RENDER_CACHE_PASS` | Packed geometry against independent pre-optimization arithmetic across types, trails and direct mutation |

The runner accepts each marker as an exact line prefix followed by a colon or line end.
A marker alone cannot override an error or nonzero exit. Dispatch/arithmetic tests
do not replace actual rendering or listening.

Research's 69 unverified IDs are an exact baseline, not permission to add arbitrary
unverified effects. Retired Local Group records have no runtime or chart definitions.
The deep-sky gate independently tests current modules/capacity; the legacy economy
driver does not measure the new module progression's full-run pacing.

## Additional entry points

| Need | Script / reference |
|---|---|
| Real display settings (focus, FPS cap, VSync) | `settings_windowed_test.gd` without `--headless` |
| Main game and palette reference corpus | `capture_reference.gd` / [visual guide](visual-validation.md#reference-corpus) |
| Batched meteor rendering and lifecycle | `meteor_batch_render_test.gd` with the real Windows/OpenGL renderer; `METEOR_BATCH_RENDER_PASS` |
| Instanced completion particles | `effect_instances_render_test.gd` with the real Windows/OpenGL renderer; `EFFECT_INSTANCES_RENDER_PASS` |
| Sky/chart/module states | `deep_sky_preview.gd` / [targeted previews](visual-validation.md#targeted-previews) |
| Settings pages in both languages | `settings_preview.gd` / [settings capture](visual-validation.md#settings-and-display) |
| Sound audition | `sound_feedback_preview.gd` / [audio](visual-validation.md#audio-audition) |
| New module geometry, bilingual UI and paired workloads | `module_overhaul_review.gd`; desktop default, `-- --probe` for 8 seeds × 5 configurations, `-- --slice` for a save-free 60-second human session |
| Real held tracking/sweep comfort | `survey_slice.gd` without `--headless` |
| Legacy economy acceptance | `full_tree_economy_test.gd` / [economy guide](performance-probes.md#full-tree-economy) |
| Spawn density and frame costs | [Performance probes](performance-probes.md) |

The human-driven survey slice runs a save-free 60-second opening sky with Sky Sweep.
`SURVEY_SLICE_READY` and `SURVEY_SLICE_RESULT` identify the session; neither is a pass/fail verdict.
The [old reference](history/probes-through-2026-09-07.md) preserves detailed historical
coverage and earlier measurement rationale. Current workflow starts with this page.

Run `meteor_batch_render_test.gd` when changing meteor geometry/submission or
interpolation. Use the reference-capture Windows/OpenGL flags and replace the
script path. It pairs immediate and shared rendering in two equal viewports:
11 types, alternating opaque/light overlaps, moving topology, unchanged-frame
reuse, interpolation reset, fading, visibility and removal. A separate 1,000-object
case exceeds 65,536 vertices in one batch and compares actual pixels, covering
32-bit index submission. It also checks run/target counts and releases target/RID
caches. The headless `meteor_render_cache_test` remains the independent arithmetic
oracle; neither test substitutes for the other. No performance threshold belongs
in this correctness check.

Its native reference also retains the pre-cache planet surface and pre-instancing
scan arcs. Additional cases cover age-only reuse, radius/palette invalidation,
planet translucency, fractional radii at both camera spans and stopping/restarting
automatic scans. Keep the existing pixel bounds: they caught Compatibility's
float16 custom-data radius rounding, fixed with high/residual encoding.

Run `effect_instances_render_test.gd` with those real-renderer flags when changing
completion-particle submission. Its nine paired poses compare native filled
circles against instancing: full capacity, colored alpha overlap, three movement/
fade steps, canvas scaling, expiry, refill, late-game camera span and reset.
It checks visible counts and idle processing; native rings/text remain in both
views to catch ordering changes. The bounded pixel tolerance covers subpixel/color
rounding, not omitted particles. PNGs for the first moving pose are written to
`build/effects-{reference,instanced}-fade_0.17.png`.

`module_overhaul_review.gd -- --debug-draw` also captures the immediate debug draw
result and F9 shortcut legend in Korean and English. The draw-window gate checks
free grant accounting, animation exclusion and save-failure rollback; the smoke
gate dispatches Ctrl+Shift+G through the live and paused viewport, including repeat
and rebinding exclusion. These debug-only grants do not change normal economy rules.

`module_overhaul_review.gd -- --survey-feedback` adds matched linear charge,
cooldown, wide/overcharge and circular-control captures. Survey mechanics and
progress values stay unchanged; only the linear indicator moves onto the cursor.

`solar_target_review.gd` captures a save-free six-target size comparison, linear
observation field and the three replacement research inspectors in Korean/English
(9 desktop frames). The comparison labels are fixture-only. `module_expansion_test`
checks solid-body edge contacts with circular/single/double LINE fields at two
camera spans. `meteor_render_cache_test` retains the full 539-case matrix, with
147 solid-body cases explicitly requiring no meteor ribbons.

`solar_target_review.gd -- --live-sky` runs a save-free moving sky with up to 24
initial targets (respecting reserved deep-sky capacity) and captures two density
frames. Use the editor engine with `--main-pack build/windows/NightwatchArray.exe
--script res://tests/solar_target_review.gd -- --live-sky` after export, setting
`NIGHTWATCH_ART_CAPTURE_DIR` to an absolute writable output directory. The release
EXE itself does not support `--script`. It isolates auto-completion for visibility,
so this is art review, not a player-input, economy, performance or comfort verdict.


`constellation_geometry_test.gd` compares every pair of the 139 runtime markers
against independent great-circle separations from the checked-in J2000 catalogue,
checks handedness and rejects crossing edges in the Pegasus square/Little Dipper
bowl. `python tools/project_constellations.py --check` also catches stale generated
local positions. `constellation_extension_test.gd` checks hit ownership and both
hold purchases in the unresolved Alpha/8 Vul pair.

`constellation_geometry_preview.gd` captures 21 focused game-chart frames and two
ordinary navigation views. Focused frames change only chart zoom/pan; markers stay
at their actual positions. Compare them with the IAU maps linked in
[the geometry reference](constellation-geometry.md). A shape match does not imply
whole-sky placement, identical stick-figure conventions or photometric fidelity.

## Fixed simulation ticks

`tests/fixed_tick_test.gd` / `FIXED_TICK_PASS`: 30/60/144/240 FPS render schedules
with identical timestamped input, independent occurrence/entry RNG state,
bounded capacity and forecast deferral, local hitstop and active-save replay.
Run with `tools/validate.ps1`; it is part of the required fast gates.
