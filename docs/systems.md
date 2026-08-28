# Systems Reference

How the running game is wired. Written for someone about to change code who
needs to know what talks to what. For *why* the game is shaped this way, read
[design.md](design.md) first.

Engine: Godot 4.7.2-stable, `gl_compatibility` renderer, 1152x648 viewport.

## Scene tree

`scenes/main.tscn`:

```
Game (Node2D)                      scripts/game.gd
├── ObservationView (Camera2D)     scripts/observation_view.gd
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
| `game.gd` | Round lifecycle, save/load orchestration, economy-independent feedback dispatch (kick/shake/hitstop), debug keys. The only node that knows about all the others. |
| `observation_view.gd` | The fixed atmospheric playfield, laterally expanding meteor-activity rectangle, dynamic camera-visible world rectangle, screen/world point conversion, interaction-length conversion, partial meteor visual scaling, and the Camera2D feedback offset. Eight Local Group steps expand its span from 1.0 to the 1.4774554 ceiling. |
| `progression_controller.gd` | Data balance, purchased nodes, discovery gates, transient Taurus manual combo, persistent Leo storm charge, and systemic derived upgrade effects. Single source of truth: consumers ask it, not `game_balance.gd`. |
| `game_balance.gd` | Static data only: the 124 upgrade definitions, six Local Group rule-family profiles, the meteor/long-watch-target spec table, and the final galactic observation-span ceiling. `RefCounted`, no state. |
| `meteor_spawner.gd` | Spawn cadence, type rolls (including same-round satellites, variable stars, comets, binary stars, and distant galaxies), delayed/forecast Gemini observation echoes, paced Leo meteor-storm queues, sky-wide burnout endpoint planning, forecast contact announcements, fragment spawning, survey-requested custom-start spawns, shower and round-guarded Canis Major spawns, support-lane assignment. |
| `meteor.gd` | One object's burn-progress motion, trail and terminal fade, observation progress, quality grading, split behaviour, and passive spectral calibration result. |
| `observation_controller.gd` | Cursor sampling, the tracking-versus-survey input latch, manual tracking, swept-path hit detection, tracking and hover rings, and the software cursor. |
| `sky_contacts.gd` | Low-chrome forecast contact rendering and steerable dishes. Right-click moves the nearest dish; Predictive Dish Control automatically pre-positions an idle dish. Forecast Log narrows the expected-position ring instead of adding value/time text. |
| `survey_controller.gd` | Round-local blank-sky sweep charge, the 150 px live-meteor guard, isolated deterministic summon rolls, custom-start spawner calls, cooldown, and the cursor-local red-light arc. |
| `event_controller.gd` | Meteor showers, Perseid outbursts, and the randomized warned Canis Major event schedule. |
| `effects_layer.gd` | Success bursts, data packets, incoming markers, forecast markers, screen kick and shake. |
| `hud.gd` | All in-round UI, round summary, settings, save-slot dialogs, banners. |
| `upgrade_tree.gd` | Research Chart rendering and purchase interaction. |
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

starfield.setup(observation_view)         twinkle_stars.setup(observation_view)
effects.setup(observation_view)
sky_contacts.setup(meteor_layer, progression, observation_view)
spawner.setup(meteor_layer, progression, observation_view)
survey.setup(progression, spawner, meteor_layer, observation_view)
observer.setup(meteor_layer, progression, hud, survey, observation_view)
events.setup(spawner, progression, observation_view)
```

The main scene also injects `ObservationView` into the star layers, effects,
contacts, spawner, survey, observer, and events. Optional view arguments keep
standalone probes on their original identity coordinate system.

## Observation coordinates

The main sky now has an identity-scaled `Camera2D` even though stage 0 does not
zoom. `ObservationView` exposes the coordinate and scale routing methods:

- `atmospheric_rect()` stays at the shipped 1152×648 playfield.
- `meteor_activity_rect()` keeps that height but follows the full visible width.
- `visible_world_rect()` is the camera-visible area around the same centre.
- `screen_to_world()` and `world_to_screen()` cross the input/HUD boundary.
- `screen_length_to_world()` preserves pixel-sized interaction and drawing
  contracts when a later stage raises the span.
- `meteor_visual_scale()` applies square-root rather than full compensation, so
  meteor drawings recede while their interaction radii remain screen-fixed.
- `meteor_screen_scale()` gives meteor-generated kick and shake the exact same
  on-screen reduction; upgrade pulses and hitstop keep their own contracts.

Meteor entry, burnout planning, and shower entry previews use the meteor
activity rectangle. Dish homes keep the atmospheric rectangle. Background
coverage and full-screen feedback use the visible rectangle.

Meteors always entered from the true edges, but `BURNOUT_SAFE_MIN/MAX` and the
per-cell `BURNOUT_JITTER_MIN/MAX` stacked into a second inset that kept every
deadline inside roughly 12–88% horizontally and 18–82% vertically, so the outer
sky held no burnout and read as dead. The horizontal inset guarded nothing and
is now nearly gone; the vertical one is only relaxed as far as the phase clock
above and the controls below allow, because a burnout under either is a target
the player cannot hit. `EffectsLayer` sends shake and kick through the camera
instead of writing `Viewport.canvas_transform` in the main scene; the
standalone Layer 2 probe retains the legacy fallback because it has no
`ObservationView`.

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
    clears meteors, contacts, survey charge/cooldown, effects, pending forecasts
    autosave, get_tree().paused = true
    hud.show_phase_summary(...)
    ↓  player presses U / Enter / Space
_on_phase_summary_continue_requested() → upgrade_tree.open_tree()
    ↓  player closes the tree
_on_upgrade_tree_closed() → _begin_observation_phase(advance_round = true)
```

The run currently has no ending. Installing the 86 non-Draco systems reveals
Draco's root; installing all 95 original systems opens the saved Galactic
Reference Frame state. The open chart also performs one saved 3.6-second
pull-back: constellation structure and decorative background stars fade while
the 95-node chart collapses into the interactive Galactic Reference Frame node
at the Milky Way centre. Before that collapse completes, a constant-speed route
head traces the installed Local Group path; each real node lights near its final
screen position when the route reaches it and settles over only the last few
percent of its radius. Its radial chart position compensates for the live camera
zoom, so the revealed map does not contract after it appears. There is no
centre-only hold or second expanding-map beat. The installed curved route and
current frontier are the only research lines retained there. It is a
non-terminal presentation state: it does not interrupt the active observation
round or a later one, and Ctrl+wheel travels between the galaxy and completed
chart scales after the one-time sequence. At galaxy scale, a non-interactive
104-spec-pixel miniature of the twelve completed constellations remains at the
Milky Way centre; one 112-spec-pixel core target replaces the overlapping legacy
buttons. The 29 Local Group positions preserve the data angles and normalized
distance order while remapping into a 0.52-tilted 124–548-spec-pixel disc. Their
Catmull-Rom route has a glow underlay, two dashed reference orbits, two cached
radial halo textures, edge-on rotated galaxy markers, and permanent code labels.
Seventy-four deterministic, non-interactive blue-grey background points occupy
the area outside the route ellipse. A galaxy-scale-only completion ledger and
fixed inspector replace the cursor tooltip; chart scale retains the existing
tooltip. Twenty-nine Local Group nodes extend that chart to 124 systems and
build the host-star/transit layer from six reusable rule families. Sirius Bloom still schedules one warned Major Fireball
at a randomized viable time in each subsequent round. Observing or losing it
does not stop the night.

### Time invariants

These are load-bearing. Breaking them silently corrupts the Data/min series.

- `elapsed_time` accrues **only** while an observation phase is active. An
  intermission costs no run time.
- `_process` divides by `Engine.time_scale` to convert back to real seconds, so
  a hitstop freeze cannot buy the player extra observation time.
- Canis Major scheduling happens only in `EventController.start()`, after the
  tree closes and a new round begins. Buying Sirius cannot inject the event
  into the middle of the current observation.
- Every round clears unfinished objects and pending forecasts at zero rather
  than letting them leak into the next sample.
- Long Andromeda targets are announced only while their own centered manual
  analysis time still fits after the forecast lead; they never carry progress
  or a live object across an intermission.
- A shower starts only if its warning plus active phase fits before zero.
  Otherwise it stays due and starts in the next viable round
  (`event_controller.gd::_shower_fits_current_observation`).
- Sirius Bloom is likewise deferred unless its 2.6-second warning and the
  Major Fireball's full 14-second lifetime fit before zero. It does not pause
  regular spawning; `MeteorSpawner` resets and enforces its once-per-round
  guard.

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
   `game._on_meteor_observed` computes one economy-independent `strength` from
   the target's base value, manual grade, and combo. It drives particle, audio,
   kick, shake, and hitstop amplitudes without reading the research value
   multiplier. Shake and hitstop additionally require a `fireball` or `major`
   target, and hitstop has a 400 ms real-time cooldown after release so burst
   completions cannot chain freezes.

The observation's intrinsic multiplier is likewise kept separate from the
research economy multiplier. The actual Data packet reports the full awarded
amount, while its suffix, the success pitch, the quality banner, and the saved
best-manual-multiplier statistic report only observation technique. Legacy
best-multiplier values are clamped to the maximum possible intrinsic value on
load because old saves did not retain enough information to reconstruct which
part came from research.

Successful manual observations also advance one transient combo in
`progression_controller.gd`. Taurus research lengthens its window and turns its
effective stacks into manual-only observation speed and tracking-radius bonuses.
Automatic completions neither advance nor clear it; elapsed observation time,
round transitions, and save loads do. The software cursor renders its timer arc
and stack count directly around the changing observation radius.

Automatic progress (passive automation, dish assist, support lanes) adds into
the same `observation_progress`. Manual and automatic completions are separated
at the reward and feedback layer, not at the progress layer.

After `polar_survey`, one left-button press is latched as `PENDING`, then as
either `TRACKING` or `SCANNING`. A meteor swept hit wins while pending; otherwise
14 px of blank travel selects scanning until release. While no live meteor is
within 150 px, `SurveyController` accumulates cursor distance and rolls a summon
chance at the purchased threshold. A success calls `MeteorSpawner.spawn_meteor`
with the cursor as `custom_start` and a velocity within 60 degrees of the screen
centre, then starts its cooldown. The survey RNG is round-seeded and independent
from every spawner RNG stream.

Summoned meteors carry `polar_summoned` metadata. They use normal observation
rewards, success counts, and Taurus momentum, but the proc tag
prevents them from charging Leo or opening Gemini echoes. Base partial charge is
lost on release; `sustained_sweep` preserves it only inside the current round.
The charge/cooldown arc stays red and cursor-local; neutral white still belongs
only to live meteor tracking.

## Purchase flow

`upgrade_tree.gd` → `progression.request_purchase(node_id)` validates state and
cost, then emits `upgrade_purchased`. `game._on_upgrade_purchased` refreshes
dishes and spawner features, plays feedback, and autosaves.

Galaxy Map is the presentation exception. If its purchase occurs
while the chart is open, `game.gd` asks the chart to begin the pull-back before
the progression refresh. A deliberate key, mouse-button, joypad-button, or
wheel press skips to the same final state; the mouse release that completed the
hold and passive motion do not. `upgrade_tree.gd` emits
`galactic_pullback_finished` only after completion or skip, and `game.gd` then
marks the flat save flag and autosaves again.

All prerequisite-free roots are visible from time zero. Internal nodes reveal
only from prerequisite IDs; the live graph contains no success-count reveal
gates. Eight approved branch leaves contribute unconditional `×2` observation
value each. Draco adds unconditional `×4` and `×8` steps after all other
research, so the original 95-node Galactic Reference Frame endpoint has exact
global `×8192` growth before
the four existing target-conditional multipliers are applied.

The 29 Local Group nodes extend the live graph to 124 without changing that
product. `ProgressionController.get_observation_span()` counts eight stable
galaxy ids and compounds exact five-percent steps up to `1.4774554`.
`ObservationView` owns that span and routes world/screen rectangles and lengths;
starfield, twinkle, input, effects, and spawner consumers continue to derive
their geometry from it. The starfield's gradient bands and horizon ridge follow
the current visible-world frame, so the fixed atmospheric rectangle remains a
vertical safety boundary and never appears as a rendered edge.

`HostStarLayer` is a separate `HostStarController`, not a child of
`MeteorLayer`. LMC starts with one `HostStar` and one active window; M32 raises
the stationary-host cap to two and M110 independently raises the overlapping-
window cap to two. It schedules an 8–12 second transit, then 4–6 and 3–5 second
follow-up transits, and gives each one an 8-second manual window. A miss returns
the same host to idle without erasing confirmations. A catch records one of
three confirmations and returns it to idle. After the
player releases and explicitly holds the idle star, harvest pays the current
1/2/3-confirmation tier; the third confirmation schedules no further transit.
Harvest schedules a 6–8 second respawn. Completed confirmations persist across
round boundaries, while an active transit at the boundary becomes a miss. The
observer combines children from both layers only for pointing and manual tracking. Host
objects never consume the atmospheric `MAX_TOTAL_METEORS = 32` budget.

The later hosts rotate through profiles assembled from six verbs: R1 reference
placement, R2 brightening-decoy rejection, R3 comparison-star baseline lock,
R4 blank-sky sweep reveal, R5 transit forecast notches, and R6 multi-host
priority. The final ten contracts all combine two learned rules. NGC 147 is the
non-host profile: its three permanent reference anchors pay only `×1.10`, below
a live host's `×1.25`. Leo II re-hides after 12 seconds, clears its old sweep
directions, and is always recoverable with a fresh sweep.

Completed meteor rewards ask `HostStarController` for one reference match
before the global meteor multiplier is applied. The resolver uses a 132-screen-
pixel radius, closest normalized distance, and stable-id tie break, so reference
benefits cannot stack. A nearest live host pays `×1.25`; an NGC 147 permanent
anchor pays `×1.10`. Transit rewards use
`record_transit_confirmation()` without paying Data, then explicit harvest uses
`add_transit_harvest()` and the SMC-only `get_transit_value_multiplier()`.
Harvest tiers are `×1.0/×1.35/×1.65` of the quality-adjusted base, and they
deliberately bypass global `×8192` and manual meteor combo growth.

Regular active-sky capacity begins at four. Array Planning, Multi-Target
Tracking, Cascade Sampling, and Perseid Watch each add one permanent slot, so
the completed legacy cap is eight. Canis Major then raises it 8 → 9 → 10 →
12 while lowering the regular-arrival floor 1.15 → 1.00 → 0.85 → 0.70
seconds. Draco's final-power sequence raises the endpoint to 18 and lowers the
floor to 0.45 seconds. The scheduler charges only live
atmospheric targets (`common`, `fast`, `fragment`, `fragment_piece`, and
`fireball`) against that budget. Pending forecasts are future information and
same-round long-watch targets are long-dwell catalog work, so neither suppresses the
regular arrival stream. Atmospheric objects created by events, echoes, storms,
and fragments do count once live; every source still shares the separate global
`MAX_TOTAL_METEORS = 32` cap.

Research metadata has three deliberately separate layers in `game_balance.gd`:

- `runtime_parameters` is production input. Only
  `observation_duration_bonus` and `observation_value_multiplier` are currently
  data-driven, and both are consumed by `progression_controller.gd`.
- `effect_notes` records non-executing design context. Gameplay code must never
  read it.
- `effect_contract` is an independent test oracle. Gameplay code must never
  read it or derive expected values from `runtime_parameters`.

The remaining effects go through named accessors on
`progression_controller.gd` (`get_tracking_radius`, `get_max_active`,
`get_dish_count`, `get_automation_strength`, and so on) or through bespoke
consumers. `tests/research_contract_test.gd` verifies every node has a literal
upgrade reference, a runtime parameter, a declared dynamic-id connection, or a
declared prerequisite-only role. Calibration Framework is intentionally the
last kind: it opens downstream band and binary-star research without a direct
runtime toggle.

The 55 executable contracts cover ten global value multipliers, four
observation-duration bonuses, eight regular active-contact capacity increases,
four regular-arrival floors, the LMC unlock, SMC transit multiplier, six later
span steps, the M32/M110 capacities, and 19 Local Group rule profiles. The exact
69-node unverified set is a hard baseline, not a wildcard; follow-up work may
shrink it, and adding or exchanging an id requires an explicit test diff.

## Save format

`game.gd::_build_save_data()` writes a flat dictionary containing run timing,
round bookkeeping, the clean-round baseline, and nested progression and host-
star payloads. Each saved host retains its stable id, lifecycle/profile state,
position, observation and comparison state, transit/respawn/re-hide clocks,
confirmation count, accumulated quality, and measurements, so active windows
resume rather than being rerolled and completed evidence is not lost. The loader
also accepts the previous single-host payload. Loading routes through
`_apply_save_data`, which
sanitizes every field: unknown upgrade ids are dropped by
`_validated_signature`, and `_sanitize_round_result` clamps a restored round
result into legal ranges.

Sweep charge, cooldown, and live summoned meteors are round state and are
discarded on load. The Canis once-per-round consumed flag is retained so loading
a save made after Sirius cannot emit it twice in one observation. Removed
stationary-survey fields in an old same-day fixture are ignored; the required
71-node pre-Ursa-Minor saves still validate normally.

Because purchases are saved by stable id, an 86-node completed save remains
valid and resumes with Draco's first node revealed rather than receiving any
of the eleven later nodes automatically. A 95-node Galactic Reference Frame
save likewise receives none of the 29 Local Group nodes automatically.

A resumed round sets `phase_resumed_from_save`, which makes that round its own
comparison baseline instead of presenting pre-load installs as fresh growth.

Autosave runs every 60 seconds of observation time, and on every purchase,
round end, and slot change.

`galactic_pullback_seen` is a flat game-save presentation flag, separate from
the ID-based progression payload. A missing field is false. A legacy save that
already owns `galactic_reference_frame` therefore plays the sequence once on
its next chart open; a save with the flag true opens directly at the galaxy
scale. Resetting a run clears both progression and this flag. If the process
ends between the purchase autosave and the completion autosave, replaying the
short sequence is the safe fallback.
