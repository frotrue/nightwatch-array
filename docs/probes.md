# Tests and Probes

Run commands from the repository root in PowerShell. Set `$godot` to the console
binary shown in the [README](../README.md#실행과-빌드). Tests are `SceneTree` scripts;
no GUT/gdUnit installation is needed.

## Routine validation

```powershell
.\tools\validate.ps1 -GodotPath $godot -Build
```

This runs the 20 fast gates below, then exports Windows. Add `-FullEconomy` for
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
| `research_contract_test.gd` | `RESEARCH_CONTRACT_PASS` | 107 definitions, 38 executable contracts, exact 69 unverified IDs, bidirectional en/ko claims, opening budgets |
| `save_integrity_test.gd` | `SAVE_INTEGRITY_PASS` | Atomic replacement, injected write/rename failures, invalid slots/payloads, prior bytes and summary preservation |
| `smoke_test.gd` | `SMOKE_TEST_PASS` | Main loop, saves, localization, held tracking/sweep, input/modals/settings, round accounting and legacy ending |
| `deep_sky_test.gd` | `DEEP_SKY_PASS` | Original 95-node path, real M31 observation/accounting, chart purchases, five-slot pointer/input flow, pause recovery, effects and migration |
| `expansion_state_test.gd` | `EXPANSION_STATE_PASS` | Predecessor research, replacement draw determinism, additive copies and malformed saves |
| `module_expansion_test.gd` | `MODULE_EXPANSION_PASS` | Conditional effects, split chance/copy persistence, composed multipliers, trail contact, sweep and contribution eligibility |
| `module_inventory_test.gd` | `MODULE_INVENTORY_PASS` | Fourteen entries, categories, ownership, acquisition routes and scroll/focus controls |
| `deep_sky_chart_expansion_test.gd` | `DEEP_SKY_CHART_EXPANSION_PASS` | Dedicated draw view, animation/skip/double-click/reduced-motion, save failure and modal return |
| `constellation_extension_test.gd` | `CONSTELLATION_EXTENSION_PASS` | Original geometry preserved, shared Alpheratz, forty-seven mapped stars across ten figures, real hold purchases, permanent growth/target unlocks, save compatibility and bilingual navigation |
| `expansion_integration_test.gd` | `EXPANSION_INTEGRATION_PASS` | Real rare targets and all research without specimen modules, duplicate rewards, transactional failure, active save/load, all eight permanent growth roles, integrated M31 equipment and round context; manual/automatic split pairs, seeded hit/miss, reward, recursion exclusion, reserved capacity and expiry |
| `observation_span_probe.gd` | `OBSERVATION_SPAN_PASS` | Fixed-seed atmospheric equality, screen/world bounds, input/effect scaling, forecast suppression |
| `galactic_slice_test.gd` | `GALACTIC_SLICE_PASS` | Legacy 12+17 topology, target/phenomenon behavior, lens automation, span and save contracts |
| `probe_layer2_test.gd` | `PROBE_TEST_PASS` | Independent Layer 2 signals, uncertainty, commitment, abandonment and completion |
| `sound_feedback_test.gd` | `SOUND_FEEDBACK_PASS` | Event dispatch, PCM distinctions, 1,000 automatic events aggregated into 63 pulses, timing and queue clearing |
| `effect_feedback_test.gd` | `EFFECT_FEEDBACK_PASS` | Routine/accent routing, real visible installation rule, pause/selection cancellation, capacity limits and dawn/summary pause, load, next-round and zero-motion lifecycle |
| `reference_capture_test.gd` | `REFERENCE_CAPTURE_TEST_PASS` | Thirteen isolated scenario states, malformed image/manifest/Git rejection; no PNG rendering |
| `research_visual_test.gd` | `RESEARCH_VISUAL_PASS` | Actual marker draw paths, branch/state color bindings, alpha/radii and tutorial claims |
| `ui_presentation_test.gd` | `UI_PRESENTATION_PASS` | Shared font/spec/spacing, full integer formatting, compact/scientific thresholds, rounding carries and signed rates |
| `game_fixture_test.gd` | `GAME_FIXTURE_PASS` | Pre-ready isolation, rejected persistence, settings/binding schemas, conflict checks, notation persistence/live refresh and pointer-through numeric tooltips |
| `meteor_render_cache_test.gd` | `METEOR_RENDER_CACHE_PASS` | Packed geometry against independent pre-optimization arithmetic across types, trails and direct mutation |

The runner accepts each marker as an exact line prefix followed by a colon or line end.
A marker alone cannot override an error or nonzero exit. Dispatch/arithmetic tests
do not replace actual rendering or listening.

Research's 69 unverified IDs are an exact baseline, not permission to add arbitrary
unverified effects. The 17 decorative Local Group records have no research definitions.
The deep-sky gate independently tests current modules/capacity; the legacy economy
driver does not measure the new module progression's full-run pacing.

## Additional entry points

| Need | Script / reference |
|---|---|
| Real display settings (focus, FPS cap, VSync) | `settings_windowed_test.gd` without `--headless` |
| Main game and palette reference corpus | `capture_reference.gd` / [visual guide](visual-validation.md#reference-corpus) |
| M31/chart/module states | `deep_sky_preview.gd` / [targeted previews](visual-validation.md#targeted-previews) |
| Settings pages in both languages | `settings_preview.gd` / [settings capture](visual-validation.md#settings-and-display) |
| Sound audition | `sound_feedback_preview.gd` / [audio](visual-validation.md#audio-audition) |
| Real held tracking/sweep comfort | `survey_slice.gd` without `--headless` |
| Legacy economy acceptance | `full_tree_economy_test.gd` / [economy guide](performance-probes.md#full-tree-economy) |
| Spawn density and frame costs | [Performance probes](performance-probes.md) |

The human-driven survey slice runs a save-free 60-second opening sky with Sky Sweep.
`SURVEY_SLICE_READY` and `SURVEY_SLICE_RESULT` identify the session; neither is a pass/fail verdict.
The [old reference](history/probes-through-2026-09-07.md) preserves detailed historical
coverage and earlier measurement rationale. Current workflow starts with this page.
