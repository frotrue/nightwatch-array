# Systems Reference

How the running game is wired. Written for someone about to change code who
needs to know what talks to what. For *why* the game is shaped this way, read
[design.md](design.md) first.

Engine: Godot 4.7.2-stable, `gl_compatibility` renderer, 1152x648 viewport.

## Scene tree

`scenes/main.tscn`:

```
Game (Node2D)                      scripts/game.gd
├── Starfield (Node2D)             scripts/starfield.gd
├── TwinkleStars (Node2D)          scripts/star_twinkle.gd
├── MeteorLayer (Node2D)           (plain container; holds meteor.gd instances)
├── EffectsLayer (Node2D)          scripts/effects_layer.gd
├── ObservationController (Node2D) scripts/observation_controller.gd
├── ProgressionController (Node)   scripts/progression_controller.gd
├── MeteorSpawner (Node)           scripts/meteor_spawner.gd
├── SkyContacts (Node2D)           scripts/sky_contacts.gd
├── SurveyController (Node2D)      scripts/survey_controller.gd
├── EventController (Node)         scripts/event_controller.gd
├── GameSettings (Node)            scripts/game_settings.gd
├── SaveGameController (Node)      scripts/save_game_controller.gd
├── HUD (CanvasLayer)              scripts/hud.gd
├── UpgradeTree (CanvasLayer)      scripts/upgrade_tree.gd
└── Tutorial (CanvasLayer)         scripts/tutorial_controller.gd
```

`SoundSynth` (`scripts/sound_synth.gd`) is **not** in the scene. `game.gd`
instantiates it in `_ready()` and adds it as a child at runtime.

`scenes/probe_layer2.tscn` is a standalone Layer 2 testbed driven by
`scripts/probe/probe_controller.gd` and `scripts/probe/probe_hud.gd`. It does
not share the main scene's nodes and is kept as an experiment, not as shipped
content.

## Responsibilities

| Script | Owns |
|---|---|
| `game.gd` | Round lifecycle, save/load orchestration, feedback dispatch (kick/shake/hitstop), debug keys. The only node that knows about all the others. |
| `progression_controller.gd` | Data balance, purchased nodes, discovery gates, transient Taurus manual combo, persistent Leo storm charge, survey catalog count, and systemic derived upgrade effects. Single source of truth: consumers ask it, not `game_balance.gd`. |
| `game_balance.gd` | Static data only: the 78 upgrade definitions and the meteor/deep-target spec table. `RefCounted`, no state. |
| `meteor_spawner.gd` | Spawn cadence, type rolls (including same-round satellites, variable stars, comets, binary stars, and galaxy fields), delayed/forecast Gemini observation echoes, paced Leo meteor-storm queues, sky-wide burnout endpoint planning, forecast contact announcements, fragment spawning, shower and finale spawns, support-lane assignment. |
| `meteor.gd` | One object's burn-progress motion, trail and terminal fade, observation progress, quality grading, split behaviour, and passive spectral calibration result. |
| `observation_controller.gd` | Cursor sampling, the tracking-versus-survey input latch, manual tracking, swept-path hit detection, tracking and hover rings, and the software cursor. |
| `sky_contacts.gd` | Low-chrome forecast contact rendering and steerable dishes. Right-click moves the nearest dish; Predictive Dish Control automatically pre-positions an idle dish. Contact Ledger narrows the uncertainty ring instead of adding value/time text. |
| `survey_controller.gd` | Round-local stationary sky samples, isolated deterministic placement, 7x7 coverage timestamps, survey reward completion, and red-light field rendering. It never calls the meteor spawner. |
| `event_controller.gd` | Meteor showers and the 18-minute finale, including round-boundary deferral. |
| `effects_layer.gd` | Success bursts, data packets, incoming markers, forecast markers, screen kick and shake. |
| `hud.gd` | All in-round UI, round summary, settings, save-slot dialogs, banners. |
| `upgrade_tree.gd` | Research tree rendering and purchase interaction. |
| `tutorial_controller.gd` | Four-step first-run guidance. |
| `save_game_controller.gd` | Three save slots under `user://saves`, versioned at `SAVE_VERSION = 1`. |
| `game_settings.gd` | Locale and tutorial-completed flag in `user://settings.cfg`. |

## Setup calls

`game.gd::_ready()` performs dependency injection by hand. There are no
autoloads.

```
hud.bind_progression(progression)      upgrade_tree.bind_progression(progression)
hud.bind_settings(settings)            upgrade_tree.bind_settings(settings)
hud.bind_save_games(save_games)        tutorial.setup(settings, progression)

sky_contacts.setup(meteor_layer, progression)
survey.setup(progression)
observer.setup(meteor_layer, progression, hud, survey)
spawner.setup(meteor_layer, progression)
events.setup(spawner, progression)
```

## Signal wiring

These are the top-level cross-controller connections, all made in
`game.gd::_ready()`. Controllers also connect their own internal signals inside
their `setup` and `bind` methods; those are not listed here.

```
spawner.meteor_spawned        → game._on_meteor_spawned
spawner.rare_spawned          → game._on_rare_spawned
spawner.contact_announced     → sky_contacts.on_contact_announced
spawner.contact_resolved      → sky_contacts.on_contact_resolved

progression.upgrade_purchased → game._on_upgrade_purchased
effects.packet_landed         → game._on_packet_landed

events.banner_requested       → game._on_event_banner
events.sky_activity_changed   → game._on_sky_activity_changed
events.forecast_requested     → game._on_shower_forecast_requested
events.shower_started         → game._on_shower_started

settings.language_changed     → game._on_language_changed
upgrade_tree.tree_opened      → tutorial.notify_upgrade_tree_opened
upgrade_tree.tree_closed      → game._on_upgrade_tree_closed

hud.restart_requested / phase_summary_continue_requested /
    save_slot_requested / load_slot_requested / startup_slot_selected /
    new_game_slot_requested / reset_slot_requested /
    tutorial_replay_requested → game handlers
```

Per meteor, connected in `game._on_meteor_spawned` and in the spawner:

```
meteor.observed           → game._on_meteor_observed
meteor.expired            → game._on_meteor_expired
meteor.fragment_requested → spawner._on_fragment_requested
```

## Round lifecycle

A run is a sequence of observation rounds separated by a paused research
intermission. `game.gd` drives it.

```
_begin_observation_phase()
    duration = progression.get_observation_duration()   (20s base, 60s max)
    spawner.start_spawning(); survey.begin_round(); events.start()
    ↓  _process() counts down; elapsed_time accrues
_end_observation_phase()
    _build_round_result()   → data, rate, manual/automatic split, build signature
    clears meteors, contacts, survey fields, effects, pending forecasts
    autosave, get_tree().paused = true
    hud.show_phase_summary(...)
    ↓  player presses U / Enter / Space
_on_phase_summary_continue_requested() → upgrade_tree.open_tree()
    ↓  player closes the tree
_on_upgrade_tree_closed() → _begin_observation_phase(advance_round = true)
```

The run ends when `elapsed_time` reaches `Balance.FINAL_EVENT_TIME` (1080s).
`EventController` fires the finale, and observing or losing the major fireball
resolves the run through `_complete_prototype()`.

### Time invariants

These are load-bearing. Breaking them silently corrupts the Data/min series.

- `elapsed_time` accrues **only** while an observation phase is active. An
  intermission costs no run time.
- `_process` divides by `Engine.time_scale` to convert back to real seconds, so
  a hitstop freeze cannot buy the player extra observation time.
- The finale is checked in **both** `game.gd` and `event_controller.gd` so that
  parent/child process order cannot insert an intermission exactly at 18:00.
- Every round clears unfinished objects and pending forecasts at zero rather
  than letting them leak into the next sample.
- Long Andromeda targets are announced only while their own centered manual
  analysis time still fits after the forecast lead; they never carry progress
  or a live object across an intermission.
- A shower starts only if its warning plus active phase fits before zero.
  Otherwise it stays due and starts in the next viable round
  (`event_controller.gd::_shower_fits_current_observation`).

## Observation flow

1. `observation_controller.gd::_process` samples the cursor once per rendered
   frame. It does **not** subscribe to raw mouse-motion events; input is
   coalesced via `Input.set_use_accumulated_input(true)`.
2. While the left button is held, `_update_manual_tracking` latches a target and
   calls `meteor.apply_manual_observation(delta, distance, radius, speed)`. Purchased
   Lyra bands are matched automatically by the spawner; observation adds no
   filter-selection input or persistent spectral overlay.
3. Hit testing uses swept point-to-segment distance
   (`_distance_to_cursor_path`), so a fast flick cannot tunnel through a target
   between frames. Sweep contact is scaled by the estimated fraction of the
   frame actually spent inside the radius, so a flick can acquire a target but
   cannot grant free progress.
4. `meteor.gd` accumulates `observation_progress`. Centering raises
   `tracking_speed` from `0.72` to `1.42` and feeds `quality_integral`, which
   produces the `PERFECT` / `EXCELLENT` grade.
5. At progress `>= 1.0` the meteor emits `observed`, and
   `game._on_meteor_observed` computes one `strength` scalar that drives every
   feedback channel — particles, audio, kick, shake, hitstop — so they cannot
   drift apart.

Successful manual observations also advance one transient combo in
`progression_controller.gd`. Taurus research lengthens its window and turns its
effective stacks into manual-only analysis speed and tracking-radius bonuses.
Automatic completions neither advance nor clear it; elapsed observation time,
round transitions, and save loads do. The software cursor renders its timer arc
and stack count directly around the changing observation radius.

Automatic progress (passive automation, dish assist, support lanes) adds into
the same `observation_progress`. Manual and automatic completions are separated
at the reward and feedback layer, not at the progress layer.

After `polar_survey`, one left-button press is latched as `PENDING`, then as
either `TRACKING` or `SCANNING`. A meteor swept hit wins while pending; otherwise
14 px of blank travel selects scanning until release. `SurveyController` samples
that cursor segment over only the round's stationary fields. Its 7x7 cell ages
and 2.4-second active integration requirement are independent from meteor
observation progress. Completion calls `progression.add_survey_data()`, which
deliberately does not increment meteor success, combo, discovery, or storm state.

## Purchase flow

`upgrade_tree.gd` → `progression.request_purchase(node_id)` validates state and
cost, then emits `upgrade_purchased`. `game._on_upgrade_purchased` refreshes
dishes and spawner features, plays feedback, and autosaves.

Upgrade effects are **never** read from `game_balance.gd` by gameplay code.
They go through named accessors on `progression_controller.gd`
(`get_tracking_radius`, `get_max_active`, `get_dish_count`,
`get_automation_strength`, and so on). Add new effects as accessors there.

## Save format

`game.gd::_build_save_data()` writes a flat dictionary containing run timing,
round bookkeeping, the clean-round baseline, and a nested
`progression.get_save_data()`, plus the active survey round's completed-slot
mask. Loading routes through `_apply_save_data`, which
sanitizes every field: unknown upgrade ids are dropped by
`_validated_signature`, and `_sanitize_round_result` clamps a restored round
result into legal ranges.

Unfinished survey coverage is live round state and is discarded on load like
live meteors. The completed-slot mask prevents a saved reward from being paid
again; `survey_catalog_count` is optional progression data so pre-survey saves
default cleanly to zero.

A resumed round sets `phase_resumed_from_save`, which makes that round its own
comparison baseline instead of presenting pre-load installs as fresh growth.

Autosave runs every 60 seconds of observation time, and on every purchase,
round end, and slot change.
