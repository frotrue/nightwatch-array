# Systems Reference

Implementation map for the original sky, constellation chart, and module
continuation. Read the relevant section after [design.md](design.md).
Current values live in [design-details.md](design-details.md); retired-content save handling lives in [legacy-contracts.md](legacy-contracts.md).

## Scene and ownership

Godot 4.7.2, Mobile/Vulkan on Windows with Compatibility/OpenGL fallback,
1152×648. The safe render thread model remains in use; experimental separate
rendering reproduces upstream font-upload and shutdown errors. The root of
[main.tscn](../scenes/main.tscn) is `Game` / `scripts/game.gd`.
There are no autoloads. `Game._ready()` binds controllers and connects their signals.
It also creates SoundSynth, GameInputRouter, DeepSkyResearch and ModulePopup at runtime.

All script names below are under `scripts/`.

| Area | Owner |
|---|---|
| Composition, rounds, accounting, save/load, feedback routing | `game.gd` |
| World/screen conversion and camera feedback | `observation_view.gd` |
| Background sky and stars; instanced circles and one sunrise triangle batch | `starfield.gd`, `star_twinkle.gd`, `circle_instances.gd` |
| Data, installed research, derived effects, streak, storm charge | `progression_controller.gd` |
| Static research/meteor definitions and immutable ID lookup | `game_balance.gd` |
| Independent spawn rolls, forecasts, fragments, echo/storm queues | `spawn_policy.gd`, `meteor_spawner.gd` |
| Fixed 60 Hz clock, buffered pointer segments, tick ordering | `simulation_clock.gd`, `simulation_input.gd`, `game.gd` |
| Bounded numerical jobs (main + at most three workers); motion/contact snapshots | `simulation_workers.gd`, `meteor_motion_batch.gd`, `observation_contact_batch.gd`; pool owned by `observation_controller.gd` |
| One meteor's lifetime, motion, progress and grading | `meteor.gd` |
| Retained additive light buffers, local index caches and native pose inheritance | `meteor_render_layer.gd`, `meteor_triangle_batch.gd` |
| Cursor, tracking, additional targets, observation/sweep transitions | `observation_controller.gd` |
| Forecast contacts, dish movement and automatic tracking | `sky_contacts.gd` |
| Blank-sky travel charge, summon RNG and cooldown | `survey_controller.gd` |
| Showers, Perseid events and scheduled Canis events | `event_controller.gd` |
| Particles, packets, kick and shake; shared instanced particle circles | `effects_layer.gd`, `circle_instances.gd` |
| Synthesized cues and automatic-success aggregation | `sound_synth.gd` |
| Global dispatch and binding metadata | `game_input_router.gd`, `game_input_bindings.gd` |
| HUD, settings, dialogs and summary UI | `hud.gd` |
| Research layout, selection, purchase and chart input | `upgrade_tree.gd` |
| Shared astronomical records; marker rendering | `research_chart_data.gd`; `research_star_visual.gd` |
| Module unlock, validation and accounting | `deep_sky_research.gd` |
| Stable extension catalogue, research graph, currency and draw state | `expansion_data.gd`, `expansion_state.gd` |
| Independent anomaly scheduler, persistent tickets and concrete targets | `anomaly_director.gd`, `anomaly_target.gd` |
| Outer figure geometry and stable research/star mapping | `constellation_extension_data.gd` |
| Module definitions, ownership, five slots, capacity and effect cache | `observation_modules.gd` |
| Chart-owned loadout/draw modal, reveal animation and shared glyphs | `module_popup.gd`, `module_draw_window.gd`, `module_visual.gd` |
| Per-save first-module guide, target input gating and settings access | `module_tutorial.gd`, `scenes/ui/module_tutorial.tscn`; durable stage/result in `expansion_state.gd` |
| Palette, fonts, spec coordinates and integer formatting | `ui_theme.gd` |
| Onboarding steps and tutorial modal focus | `tutorial_controller.gd` |
| Slot files; persisted settings | `save_game_controller.gd`; `game_settings.gd` |

Fixed UI hierarchy and presentation live in `scenes/ui/`, with shared styles
and fonts in `resources/ui/`. HUD, chart, loadout/draw, tutorial and probe
controllers instantiate authored views and bind their named nodes. Repeated
research stars/module tiles use scene instances with catalogue data. Game keeps
the existing transition/pause/save ownership. Custom drawing in `scripts/ui/`
retains the original ring, glyph and tracking behavior. See the complete
[surface and ownership map](scene-authoring.md#authored-surfaces).

The independent Layer 2 scene uses `scripts/probe/probe_controller.gd` and
`probe_hud.gd`; it is a testbed, not another stage of the main game.

### Meteor rendering

The authored `MeteorLayer` owns one retained native canvas RID per non-solid
meteor, without extra scene children. Trails and non-atlas heads generate local
procedural triangles; `meteor_triangle_batch.gd` combines each target's light.
A geometry publication uploads that target's triangles once. Its retained RID
is a native child of the meteor, behind the meteor's own commands. Godot inherits
pose, interpolation, visibility and sibling order without a GDScript transform
loop on every render frame. Native filaments and opaque target surfaces keep their
CanvasItem commands and original order. Geometry and child/visibility signals
invalidate layer bookkeeping; unchanged frames return without scanning targets.
`render_batch_count` counts visible light items, not actual GPU draw calls.

Common/fast heads use `meteor_head_texture.gd`: one shared 1024x2048 atlas,
immutable quad and bounded shared palette materials. One native child RID per
head follows the meteor's normal canvas interpolation; no scene nodes are added.
The RGB channels store glow/core/hotspot contributions, so the shader retains
the live palette, inherited tint, self-modulation and visibility. Sixty-four
frames per type interpolate over a repeating 8π optical phase; subtle shape
motion is a sampled approximation of the procedural head, not pixel-identical.
Only common/fast heads use it. Trails, collision, size/pulse, burn timing and
other body types retain their existing paths. The procedural switch remains for
independent comparisons and atlas baking. Type changes hide stale head items;
owner destruction frees their RIDs. Palette caches retain at most 16 materials.

`scenes/planet_surface.tscn` owns a scene-local cloud shader and a single sprite
quad. `planet_surface.gd` binds simulation age, radius, palette, observation progress,
completion and accessibility settings; material changes do not rebuild the quad.
The former static latitude-cell mesh has been replaced by rotating cloud belts.
Asteroids retain their native polygon silhouettes and completion faces, with a
per-body copy of `resources/asteroid_surface.tres` adding rock grain or layered ice.
These materials use ordinary alpha blending and do not sample the background.
Dust/frost remains transient drawing within the existing linger, never a new target.

`scan_arc_instances.gd` owns one child canvas RID per
scanning meteor and two instanced arc templates. The shader expands radius and
width separately using the native five-point AA feather topology. Compatibility
compresses custom instance attributes to float16, so high/residual pairs preserve
subpixel motion. Real expanded bounds drive culling. Clearing an inactive scan
removes its commands; destroying its owner releases the RID. Wider/nonstandard
arcs use the native fallback. Scan arcs introduce no scene children.

Tick resolution, changed age/linger, feature changes and camera scale invalidate
meteor geometry. Intervening render frames reuse it. The native meteor parent
owns interpolation resets and paused-tick convergence for both lines and light.
Trail station weights retain only the two most recent point counts: sampling
alternates between N and N+1, and returning to either reuses the immutable Float64
coefficients. Eviction allocates a new array rather than mutating the other entry.
Local topology caches duplicate source indices
because GDScript packed arrays share mutable storage. Fan indices depend only on
point count and are reused without changing shape/color arithmetic. The layer no
longer merges/rebases vertices across targets. Hiding a target hides its light;
removing it immediately frees its RID and metadata. Geometry changes mark only
that target dirty, and pose changes never upload its unchanged triangles.

Scene exit disconnects the render callback and frees every retained RID.
Standalone meteors keep immediate submission for previews and independent
geometry tests. Target capacity, motion/rewards, saves and the main-plus-three
worker ceiling are unchanged; GPU transforms do not move simulation off CPU.

### Retained arrival marks

`EffectsLayer` owns `retained_arrival_marks.gd`, a bounded set of native polyline
RIDs for transient entry strokes. Position, direction, camera scale, ink and reach
invalidate the geometry; opacity alone updates modulation. The flash has a later
child draw index, preserving the original particles/popups → marks → flash order.
No scene children are introduced. Reset clears visible commands, and scene exit
releases all RIDs. See the independent arrival-mark pixel test for the contract.

### HUD and effect updates

The extension readout refreshes on observation entry/exit, `deep_sky.changed`,
locale application and explicit load synchronization. Frame/second countdown
updates do not poll it. Overlay transitions retain their own visibility refresh;
sample text is shown in the module UI, so the hidden HUD sample label is not formatted.
Particle and popup damping coefficients are shared within each frame update.
Position integration, expiry order and packet delivery signals are unchanged.

## Setup calls

### White-hole target and Phoenix research

`debug_celestial_layer.gd` routes the W shortcut through `meteor_spawner.gd` into
the normal meteor layer. `white_hole_meteor.gd` extends Meteor and owns optical
time, a birth heading, a held completion pose, and a single burst after a
one-second completion animation. Successful sources defer deletion until resolve
so the final motion tick cannot discard the pending burst.
Its scene-owned `white_hole_preview.tscn` supplies the surface and sky lens.
The old standalone optical fixture remains available for material comparisons.

Release signals are resolved after observation, so newborn bodies receive no
work on their birth tick. The spawner uses ordinary specifications, accounting
and the atmospheric safety budget for ejecta. SpawnPolicy appends an independent
white-hole stream and unlocks it through Phoenix research after black-hole analysis.
White holes reserve three late slots inside the unchanged overall cap of 70.
The source snapshots the 24/36/48 burst size on spawn; ejected bodies receive
the current ejecta-value research multiplier before their first work tick. The actor cancels its release when removed at a round/load/reset
boundary. The worker motion path also advances the actor's optical clock.

`Game` injects progression and the observation view into consumers; consumers
query progression for effective upgrades rather than duplicating balance logic.
HUD/chart bind settings and progression; tutorial also binds to chart events.

The observer's additional target layers include DeepSkyResearch.
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
DeepSkyResearch owns all 42 active extension research IDs. ProgressionController references its
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
| HUD slot, summary, tutorial requests | Game owns state transitions |
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
- Atmospheric long-watch objects do not carry across rounds. Retired M31 records
  remain inert save data.
- Loading an active save over an intermission reconciles stale pause state.
  Resume only when settings, startup slots, summary, tutorial and module
  popup no longer own a pause.

The retired catalogue ending has no runtime entry point. Save migration is
documented in [legacy contracts](legacy-contracts.md).

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
Linear observation uses a swept rectangle, with a matching procedural cursor; every
contacted target is observed. Observation Slowdown retains the capture_hold inventory ID.
Targets query the observer's current field/input/equipment for a motion multiplier;
motion and burnout slow together while observation work continues at its normal rate.
No per-target timer or saved capture flag survives the replacement. Overcharge counts completion signals once,
uses Game's active real-time clock, and saves remaining time separately from equipment.
A new round or a changed overcharge installation clears it. Removed module effects,
interaction-trail buffers, dish relay modifiers and archive targets no longer execute.


The expansion catalogue separates research, quantities and installed copies. A draw
spends eight specimens (six after efficiency research) for one uniformly selected
module from eight, with replacement. Transactions persist currency, quantity and RNG
together, restoring all three on failure. Same-ID bonuses/penalties add; different
IDs retain multiplicative composition. The loadout displays owned/installed counts. ModuleDrawWindow only presents an already
committed draw: its 1.8s scan/align animation can be skipped or closed, and reduced motion
reveals immediately. It never performs an extra transaction while closing/reopening.
`AnomalyDirector` schedules one conventional rare meteor kind after coordinate research.
It reserves three components for rare meteors, defers
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
Nested payloads belong to progression and module/rare-target state.
Validate version, containers, numbers and IDs before applying state; restore target
progress/clocks rather than rerolling them. A resumed round becomes its own comparison baseline.

Deep sky saves unique module IDs plus quantities, five slots, research, specimens,
inert M31 records and live rare targets. Its nested version
is 4; the outer slot version stays 1. Extension catalogue version 4 removes M31-only research; version 3 separated permanent
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
Retired ending flags are ignored and omitted from new saves.

Settings use separate `SETTINGS_VERSION = 3` data in `user://settings.cfg`.
Input schemas, fixed fallbacks, focus and modal dispatch are in [settings.md](settings.md).

## Performance and test boundaries

Immutable ID lookup and constellation geometry are cached. Meteor ribbon weights
rebuild when station count changes, while position/type/age remain live.
Hidden panels refresh when opened or when needed.
These caches must tolerate the direct mutations covered by their regression gates.

Use the pre-ready no-persistence fixture for tests, captures and probes.
See [probes.md](probes.md) for required gates and [performance probes](performance-probes.md)
for controlled measurements. The [previous reference](history/systems-through-2026-09-07.md)
preserves old rationale and detailed legacy descriptions; it is not required reading.

## Fixed simulation ownership

`Game._physics_process()` is the sole gameplay update driver. Controllers expose
explicit tick methods; their `_process` callbacks only present the current state.
Targets split motion, observation and completion so manual and automatic work
resolve before expiry and the round boundary. See [the fixed-tick contract](fixed-tick-simulation.md).
