# Systems Reference

Implementation map for the original sky, constellation chart, and M31/module
continuation. Read the relevant section after [design.md](design.md).
Current values live in [design-details.md](design-details.md); old Local Group
and ending behavior lives in [legacy-contracts.md](legacy-contracts.md).

## Scene and ownership

Godot 4.7.2, Compatibility renderer, 1152×648. The root of
[main.tscn](../scenes/main.tscn) is `Game` / `scripts/game.gd`.
There are no autoloads. `Game._ready()` binds controllers and connects their signals.
It also creates SoundSynth, GameInputRouter, DeepSkyResearch and ModulePopup at runtime.

All script names below are under `scripts/`.

| Area | Owner |
|---|---|
| Composition, rounds, accounting, save/load, feedback routing | `game.gd` |
| World/screen conversion and camera feedback | `observation_view.gd` |
| Background sky and stars | `starfield.gd`, `star_twinkle.gd` |
| Data, installed research, derived effects, streak, storm charge | `progression_controller.gd` |
| Static research/meteor definitions and immutable ID lookup | `game_balance.gd` |
| Spawn cadence, forecasts, fragments, echo/storm queues | `meteor_spawner.gd` |
| One meteor's lifetime, motion, progress and grading | `meteor.gd` |
| Cursor, tracking, additional targets, observation/sweep transitions | `observation_controller.gd` |
| Forecast contacts, dish movement and automatic tracking | `sky_contacts.gd` |
| Blank-sky travel charge, summon RNG and cooldown | `survey_controller.gd` |
| Showers, Perseid events and scheduled Canis events | `event_controller.gd` |
| Particles, packets, kick and shake | `effects_layer.gd` |
| Synthesized cues and automatic-success aggregation | `sound_synth.gd` |
| Global dispatch and binding metadata | `game_input_router.gd`, `game_input_bindings.gd` |
| HUD, settings, dialogs, summary and legacy ending UI | `hud.gd` |
| Research layout, selection, purchase and chart input | `upgrade_tree.gd` |
| Shared astronomical records; marker rendering | `research_chart_data.gd`; `research_star_visual.gd` |
| M31 lifecycle, first record, module validation and accounting | `deep_sky_research.gd`, `andromeda_target.gd` |
| Stable extension catalogue, research graph, currency and draw state | `expansion_data.gd`, `expansion_state.gd` |
| Independent anomaly scheduler, persistent tickets and concrete targets | `anomaly_director.gd`, `anomaly_target.gd` |
| Outer figure geometry and stable research/star mapping | `constellation_extension_data.gd` |
| Module definitions, ownership, five slots, capacity and effect cache | `observation_modules.gd` |
| Chart-owned loadout/draw modal, reveal animation and shared glyphs | `module_popup.gd`, `module_draw_window.gd`, `module_visual.gd` |
| Palette, fonts, spec coordinates and integer formatting | `ui_theme.gd` |
| Onboarding steps and tutorial modal focus | `tutorial_controller.gd` |
| Slot files; persisted settings | `save_game_controller.gd`; `game_settings.gd` |
| Retained distant-target / phenomenon paths | `host_star_controller.gd`, `galactic_phenomena_controller.gd`, `supernova_target.gd`, `black_hole_target.gd` |
| Presentation-only legacy ending animation | `catalogue_ending_coda.gd` |

The round summary's fixed hierarchy and presentation live in
`scenes/ui/phase_summary.tscn`. HUD instantiates the scene and binds its named
nodes, retaining result formatting, disclosure and reveal lifecycle. Continue
still emits the HUD request to Game. See [scene authoring](scene-authoring.md).

The independent Layer 2 scene uses `scripts/probe/probe_controller.gd` and
`probe_hud.gd`; it is a testbed, not another stage of the main game.

## Setup calls

`Game` injects progression and the observation view into consumers; consumers
query progression for effective upgrades rather than duplicating balance logic.
HUD/chart bind settings and progression; tutorial also binds to chart events.

The observer's additional target layers include hosts, phenomena and DeepSkyResearch.
The survey discovery guard also includes these layers. `observer.modules` points
to `deep_sky.modules`; the chart's continuation binds DeepSkyResearch and the chart.
ModulePopup receives the game and is exposed to the chart for input/modal ownership.
UpgradeTree merges the outer figure records into its existing coordinate cache,
star buttons, hold controller, renderer, ledger and inspector. It dispatches
outer purchases to DeepSkyResearch while preserving the original progression owner.
Alpheratz is one shared coordinate/state at the Andromeda/Pegasus corner.
The original 95-star geometry stays intact when the wider sky is revealed.
ModulePopup owns the shared pause/focus boundary. Its equipment surface and ModuleDrawWindow
are separate views with separate chart launchers; closing preserves chart rotation/zoom.
DeepSkyResearch owns all 47 extension research IDs. ProgressionController references its
ExpansionState for cached permanent effects, so equipment cannot remove research gains.

## Signal wiring

| Source | Consumer / purpose |
|---|---|
| `spawner.meteor_spawned` | Game attaches each meteor's observation/expiry handlers |
| `meteor.observed` / `expired` / `fragment_requested` | Accounting and feedback / expiry / child spawning |
| `spawner.contact_announced` / `contact_resolved` | SkyContacts forecast lifecycle |
| `progression.upgrade_purchased` | Game refreshes features, dispatches installation feedback and autosaves |
| `deep_sky.changed` | HUD objective/specimens and ready notice; sticky round equipment history; chart/popup refresh |
| `effects.packet_landed` | Game's packet feedback |
| `events.banner_requested` / `sky_activity_changed` | Game updates HUD and background |
| `events.forecast_requested` / `shower_started` | Game's shower presentation |
| `upgrade_tree.tree_opened` / `tree_closed` | Tutorial / Game's resume-or-next-round routing |
| `upgrade_tree.galactic_pullback_finished` | Game persists the presentation flag |
| HUD slot, summary, tutorial and ending requests | Game owns state transitions |
| Settings language/accessibility changes | UI refresh / effects configuration |

Signals within a controller remain local to its `setup` or `bind` method.
Ordinary Data changes use progression's existing signal, not duplicate deep-sky events.

## Round lifecycle

```text
_begin_observation_phase
  → live observation, spawning, events and accounting
_end_observation_phase
  → finalize result, clear round-local objects, autosave, pause
  → presentation-only sunrise, reveal summary (summary owns input/pause immediately)
_on_phase_summary_continue_requested
  → open research chart
_on_upgrade_tree_closed
  → next round after summary, or resume an already active round
```

- `elapsed_time` advances only during observation. Dividing delta by
  `Engine.time_scale` prevents hitstop from extending a round's real duration.
- Round end clears atmospheric meteors, contacts, survey charge, forecasts and
  spawn queues. Persistent storm charge and saved target progress follow their own contracts.
- Starfield derives dawn from the round's remaining fraction and fades TwinkleStars
  through `background_visibility_changed`. Its sunrise tween and HUD summary reveal
  run during intermission pause, ignoring hitstop time scale. Active load/new round
  cancels the old sky tween; HUD hide/replacement cancels the old reveal. Intermission
  load restores finished dawn directly. These are unsaved presentation states.
- Canis scheduling begins with a new round. Showers and the 2.6-second Sirius
  warning plus 14-second Major lifetime must fit, or defer to a viable round.
- Atmospheric long-watch objects do not carry across rounds. M31 records,
  partial progress and cooldown are separate deep-sky state.
- Loading an active save over an intermission reconciles stale pause state.
  Resume only when settings, startup slots, summary, ending, tutorial and module
  popup no longer own a pause.

The retained catalogue ending adds a completion branch after the final chart;
its conditions and final-watch rules are in [legacy contracts](legacy-contracts.md#이전-카탈로그-엔딩).

## Observation flow

The observer samples once per rendered frame with accumulated input.
Swept path hit detection prevents cursor tunnelling; contact time limits progress
to the fraction actually spent within the target radius. A valid primary target
and its tracking grace take priority over additional targets and sky sweep.

While held, tracking and sweep alternate. A frame used for tracking/completion
cannot also charge sweep travel. Mode changes preserve partial charge; actual
release, reset and load follow [the sweep contract](design-details.md#관측과-자동화).
Survey RNG is independent of spawn RNG, and summon-origin guards prevent recursion.

Targets accumulate observation progress. Completion routes rewards through the
appropriate controller and ordinary round accounting. Manual technique and
research value multipliers remain distinct; automatic and manual results are
separated in accounting/feedback, even when they contribute to the same progress.

Feedback eligibility is semantic: rare impact types or high manual grades,
not economy multipliers or proc origin. Rings require strength ≥0.22; shake ≥0.50;
hitstop requires a manual fireball/major, strength ≥0.66 and its 400ms cooldown.
Galaxy common/fast flashes and phenomenon-completion flashes remain suppressed.
The current event and audio presentation is in [feature details](design-details.md#표현과-설명).

## Purchase flow

Chart purchases call `progression.request_purchase(id)`, which validates state
and price, then emits `upgrade_purchased`. The chart does not maintain its own balance.
`runtime_parameters` is production data; `effect_notes` is explanatory;
`effect_contract` is an independent test oracle and must not drive gameplay.

Deep-sky research purchases are chart-only, equipment changes are loadout-only, and draws
are draw-window-only. Thirty-seven permanent observation upgrades occupy eight figures;
ten module/sample support upgrades occupy Pegasus and Lacerta.
Research does not grant or equip modules. Capacity research opens slots directly. Closing the popup restores chart canvas, focus and prior
pause; closing the chart dismisses the popup first. Its canvas sits one layer
above the chart and temporarily hides only the chart canvas, not its logical open state.
The chart yields first-refusal input while the popup is active.

`observation_modules.gd` caches effects against all slots, ownership and capacity.
Reads detect direct fixture mutation, duplicate/unowned slots and capacity changes.
Manual speed/radius can have positive penalties below one; dishes keep their own rules.
Record and revisit are integrated by actual M31 exposure progress; completion
uses those accumulated weights for income and the next cooldown.
Definitions, prerequisites and placement behavior are in [module details](design-details.md#m31과-모듈).

The expansion catalogue separates research, quantities and installed copies. A draw
spends eight specimens (six after efficiency research) for one uniformly selected
module from fourteen, with replacement. Transactions persist currency, quantity and RNG
together, restoring all three on failure. Same-ID bonuses/penalties add; different
IDs retain multiplicative composition. The loadout displays owned/installed counts. ModuleDrawWindow only presents an already
committed draw: its 1.8s scan/align animation can be skipped or closed, and reduced motion
reveals immediately. It never performs an extra transaction while closing/reopening.
`AnomalyDirector` schedules one conventional rare meteor kind after the first M31.
It reserves three components including module-created archive afterglows, defers
around Major warnings and insufficient round time, and awards 2/3 samples per
completed natural rare meteor for both manual and automatic work. Persistent tickets
prevent duplicate Data/samples. Targets are direct DeepSkyResearch children for
observer/dish acquisition and do not enter the atmospheric proc/fragment path.
The full contract is [expansion-design.md](expansion-design.md).

## Save format

`SAVE_VERSION = 1`; three slots under `user://saves/`.
The writer flushes a sibling `slot_N.cfg.tmp.<pid>` and renames it over the destination.
Write/rename failures preserve the last committed file and cached summary.
Uncommitted staging files are ignored; corrupt existing slots are occupied, not empty.

Game owns run timing, round bookkeeping, clean-round baseline and presentation flags.
Nested payloads belong to progression, host targets, phenomena and deep sky.
Validate version, containers, numbers and IDs before applying state; restore target
progress/clocks rather than rerolling them. A resumed round becomes its own comparison baseline.

Deep sky saves unique module IDs plus quantities, five slots, research, specimens,
M31 partial progress/weighted reward/cooldown and live rare targets. Its nested version
is 3; the outer slot version stays 1. Extension catalogue version 3 separates permanent
research IDs from the five legacy direct-purchase module IDs. Old saves copy those
completed IDs and preserve their three research-granted modules once; current-catalogue
module ownership never implies research. The progression effect-state reference is
rebound on every reset/load, including failed-transaction rollback. Unknown future
catalogues are rejected before mutation. Version 1 keeps its existing equipment and
capacity. Version 2 preserves research/currency/modules, refunds paid pending offers
once, and converts in-flight legacy events to one rare meteor per ticket while
preserving normalized progress and payment flags. Unknown nested versions are
rejected before mutation or replacement. Duplicate slots are accepted up to owned
quantity; missing quantities mean one. Load restores research before the round and
then resumes targets. Mid-round equipment changes are sticky, including A→B→A;
uninstalled acquisition has a separate growth field.
Legacy `equipped`/`secondary` or two-slot arrays restore the first two slots;
the old `andromeda.modules` payload is a fallback, and its active-stage flag is ignored.
Invalid/excess-copy/unowned entries are sanitized; missing data grants no purchases.
Popup-open state is never persisted.

Autosave runs every 60 observation seconds, on purchases, round end and slot changes.
Quick start uses the newest valid slot, then the first empty slot. If all existing
slots are invalid, show recovery instead of starting an unsavable slot-zero run.
Presentation flags such as `galactic_pullback_seen` are distinct from progression.
The legacy seen/pending/final-watch flags remain covered by [compatibility rules](legacy-contracts.md#저장과-검증).

Settings use separate `SETTINGS_VERSION = 3` data in `user://settings.cfg`.
Input schemas, fixed fallbacks, focus and modal dispatch are in [settings.md](settings.md).

## Performance and test boundaries

Immutable ID lookup and constellation geometry are cached. Meteor ribbon weights
rebuild when station count changes, while position/type/age remain live.
M31 art redraws on visual changes; hidden panels refresh when opened or when needed.
These caches must tolerate the direct mutations covered by their regression gates.

Use the pre-ready no-persistence fixture for tests, captures and probes.
See [probes.md](probes.md) for required gates and [performance probes](performance-probes.md)
for controlled measurements. The [previous reference](history/systems-through-2026-09-07.md)
preserves old rationale and detailed legacy descriptions; it is not required reading.
