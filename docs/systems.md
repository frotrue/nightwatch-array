# Systems Reference

How the running game is wired. Written for someone about to change code who
needs to know what talks to what. For *why* the game is shaped this way, read
[design.md](design.md) first.

Engine: Godot 4.7.2-stable, `gl_compatibility` renderer, 1152x648 viewport.

This is the current implementation reference, not the chronological design log.
The [documentation map](README.md) separates current contracts from historical
baselines and superseded decisions. Start with the responsibility table for code
ownership, then the relevant flow and save contract below.

## Scene tree

`scenes/main.tscn`:

```
Game (Node2D)                      scripts/game.gd
├── ObservationView (Camera2D)     scripts/observation_view.gd
├── Starfield (Node2D)             scripts/starfield.gd
├── TwinkleStars (Node2D)          scripts/star_twinkle.gd
├── HostStarLayer (Node2D)         scripts/host_star_controller.gd
├── GalacticPhenomenaLayer         scripts/galactic_phenomena_controller.gd
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

`SoundSynth` (`scripts/sound_synth.gd`) and `GameInputRouter`
(`scripts/game_input_router.gd`) are **not** in the scene. `game.gd` instantiates
both in `_ready()` and adds them as children at runtime. The router receives the
game, HUD, settings, tutorial, and chart references through `setup()` and uses
`PROCESS_MODE_ALWAYS`, so pause-owned UI does not lose its global actions.

SoundSynth processes through UI pauses so research and slot confirmations remain
audible. Research owns its original dyad; save/load share a quiet unpitched latch;
rare-target notices use a sharp double note; shower/bloom/Perseid notices use a slow swell.
Automatic observations accumulate in a 160 ms window and emit one 70 ms pulse,
with logarithmic batch weight capped at -12 dB. The queue is cleared on pauses,
round boundaries, and loads; it never affects observation accounting or rewards.

`scenes/probe_layer2.tscn` is a standalone Layer 2 testbed driven by
`scripts/probe/probe_controller.gd` and `scripts/probe/probe_hud.gd`. It does
not share the main scene's nodes and is kept as an experiment, not as shipped
content.

## Responsibilities

| Script | Owns |
|---|---|
| `game.gd` | Round lifecycle, catalogue-ending eligibility and final-watch routing, save/load orchestration, economy-independent feedback dispatch (kick/shake/hitstop), debug keys. The only node that knows about all the others. |
| `game_input_router.gd` | Pause-safe global input dispatch, HUD rebind capture before GUI handling, modal navigation precedence, summary/chart transitions, and fullscreen routing. Raw debug chords remain owned by `game.gd`. |
| `game_input_bindings.gd` | The six `nw_*` action definitions, fixed/editable slot metadata, active conflict contexts, descriptor validation/labels, project-default restoration, and editable override application. |
| `observation_view.gd` | The fixed atmospheric playfield, laterally expanding meteor-activity rectangle, dynamic camera-visible world rectangle, screen/world point conversion, interaction-length conversion, partial meteor visual scaling, and the Camera2D feedback offset. Four Local Group chapter milestones expand its span from 1.0 to the 1.4774554 ceiling. |
| `progression_controller.gd` | Data balance, purchased nodes, discovery gates, transient manual Observation Streak, the Perseid three-target predicate, persistent Leo storm charge, and systemic derived upgrade effects. Single source of truth: consumers ask it, not `game_balance.gd`. |
| `game_balance.gd` | Static data: 107 installable research definitions, their immutable ID index, four simple Local Group observation profiles, the meteor/long-watch-target spec table, and the final galactic observation-span ceiling. `RefCounted`, no mutable progression state. |
| `meteor_spawner.gd` | Spawn cadence, type rolls (including same-round satellites, variable stars, comets, binary stars, and distant galaxies), delayed/forecast Gemini observation echoes, paced Leo meteor-storm queues, sky-wide burnout endpoint planning, forecast contact announcements, fragment spawning, survey-requested custom-start spawns, shower and round-guarded Canis Major spawns, support-lane assignment. |
| `meteor.gd` | One object's burn-progress motion, optional fixed-endpoint quadratic lens curve, explicit in-zone lensed state, trail and terminal fade, observation progress, quality grading, split behaviour, and passive spectral calibration result. |
| `galactic_phenomena_controller.gd` | Persistent supernova and black-hole target lifecycle, semantic five-record completion queries, active-observation-time phase advancement, save/load, lens-zone rendering, and lensed-meteor curve assignment. |
| `supernova_target.gd` | Peak/fade/remnant timing choice. A missed light-curve phase always ends in a trackable remnant. |
| `black_hole_target.gd` | Full-ring and partial-arc contact distance with ordinary aim-and-hold progress, not angular travel. Releasing does not erase progress. The coda target also carries the supernova phase state. |
| `observation_controller.gd` | Cursor sampling, held-button tracking/survey transitions with primary-target priority, manual tracking across meteor/host/phenomena layers, point or annulus swept-path hit detection, tracking and hover rings, the raw Observation Streak counter, the cursor-local Perseid three-target indicator, and the software cursor. |
| `sky_contacts.gd` | Low-chrome forecast contact rendering and steerable dishes. Right-click moves the nearest dish; Predictive Dish Control automatically pre-positions an idle dish. Forecast Log narrows the expected-position ring instead of adding value/time text. After galaxy entry, common/fast contacts remain in the simulation and automatic assignment but omit their ring, label, countdown, hover target, and automatic-assignment tether. |
| `survey_controller.gd` | Round-local blank-sky sweep charge, the 150 px live-meteor guard, isolated deterministic summon rolls, custom-start spawner calls, cooldown, and the cursor-local red-light arc. |
| `event_controller.gd` | Meteor showers, Perseid outbursts, and the randomized warned Canis Major event schedule. |
| `effects_layer.gd` | Success bursts, data packets, incoming markers, forecast markers, screen kick and shake. |
| `hud.gd` | All in-round UI, round summary, neutral catalogue-completion record and its finish/continue actions, settings and Controls surfaces, keyboard-rebind capture, save-slot dialogs, focus restoration, and banners. |
| `catalogue_ending_coda.gd` | Presentation-only ending plate: the chart's actual 95 stars and twelve constellation shapes light, collapse into the Milky Way, and reveal a connected 30-marker galaxy map. Owns no research, eligibility, or save state. |
| `research_chart_data.gd` | Shared constellation records, shape edges, Local Group records, and galaxy-disc projection used by both the interactive research chart and the ending plate. |
| `upgrade_tree.gd` | Research Chart rendering and purchase interaction, chart/back first-refusal input, binding-labelled close actions, and the final-watch-pending and ending-ready completion detail shown at galaxy scale. |
| `research_star_visual.gd` | One star, cluster, or galaxy research marker: state/branch ink, pulse, hover and hold drawing. The chart retains `StarNodeVisual` as a compatibility alias. |
| `ui_theme.gd` | Shared palette, embedded font selection, 1920-spec coordinate conversion, spec-label construction, and grouped integer formatting for the HUD and chart. |
| `tutorial_controller.gd` | Four-step first-run guidance, including the public modal-step query and focus-owned welcome/completion cards. |
| `save_game_controller.gd` | Three save slots under `user://saves`, versioned at `SAVE_VERSION = 1`. |
| `game_settings.gd` | Validated locale, tutorial, chart rotation, audio, display, and editable input settings in versioned `user://settings.cfg`; applies settings and emits UI synchronization signals. |

## Setup calls

`game.gd::_ready()` performs dependency injection by hand. There are no
autoloads.

```
input_router.setup(game, hud, settings, tutorial, upgrade_tree)
upgrade_tree.bind_tutorial(tutorial)

hud.bind_progression(progression)      upgrade_tree.bind_progression(progression)
hud.bind_settings(settings)            upgrade_tree.bind_settings(settings)
hud.bind_save_games(save_games)        tutorial.setup(settings, progression)

starfield.setup(observation_view)         twinkle_stars.setup(observation_view)
effects.setup(observation_view)
host_stars.setup(progression, observation_view)
galactic_phenomena.setup(progression, observation_view, meteor_layer)
sky_contacts.setup(meteor_layer, progression, observation_view)
spawner.setup(meteor_layer, progression, observation_view)
survey.setup(progression, spawner, meteor_layer, observation_view,
    [host_stars, galactic_phenomena])
observer.setup(meteor_layer, progression, hud, survey, observation_view,
    [host_stars, galactic_phenomena])
events.setup(spawner, progression, observation_view)
```

The main scene also injects `ObservationView` into the star layers, effects,
contacts, spawner, survey, observer, and events. Optional view arguments keep
standalone probes on their original identity coordinate system.

## Input routing, pause, and settings

`project.godot` declares the six shipped actions before any scene runs.
`game_input_bindings.gd` repeats the same defaults as canonical metadata so a
settings reload can first rebuild a known baseline and then apply only editable
overrides. Fixed slots are never removed by a reset or a malformed settings
entry.

| Action | Shipped slots | Declared active contexts |
|---|---|---|
| `nw_observe` | locked left mouse button | observation |
| `nw_dish` | locked right mouse button | observation |
| `nw_chart` | editable `U` | observation, Research Chart |
| `nw_menu_back` | locked `Esc`, plus one optional editable alternate | observation, Research Chart, settings, dialog, phase summary, catalogue |
| `nw_continue` | locked `Enter` and `Space`, plus editable `U` | phase summary |
| `nw_fullscreen` | editable `F11` | global |

The shared `U` defaults are intentional: `nw_chart` and `nw_continue` have
separate conflict contexts, and the router accepts either action as the same
continue transition while a phase summary is open. Observation polls
`Input.is_action_pressed("nw_observe")`; dish placement handles the
`nw_dish` event without exact modifier matching so `Shift+RMB` remains the same
manual placement gesture. The four editable slots are keyboard-only in this
version. There are no controller defaults or controller-rebinding UI.

Input is split by Godot propagation stage:

- `GameInputRouter._input()` gives an active HUD rebind capture the event before
  a focused `Control` can consume it. Outside capture it does not take
  pre-GUI ownership.
- `UpgradeTree._input()` owns chart close and the one-time pull-back's
  skip-plus-close behavior. `HUD._input()` retains first refusal for the
  catalogue reveal and its debug-preview close chord.
- After GUI handling, `GameInputRouter._unhandled_input()` routes exact editable
  key chords. An active capture blocks navigation; raw `F9` and `Ctrl+Shift`
  debug chords are left to `game.gd`; fullscreen precedes menu/back, then phase
  summary continue, then ordinary chart open.

The router, HUD, tutorial, and settings process while paused; the chart processes
while paused. A component records whether it introduced a pause and only releases
that pause on close. This preserves an existing summary or chart pause when a
second surface is layered above it.

Menu/back has state-dependent ownership. An open chart gets first refusal. HUD
then closes one level in this order: active capture, confirmation dialog, or
the consolidated Settings console. The catalogue ending, startup slots, and modal tutorial
welcome/completion steps block global navigation. A phase summary deliberately
does not: menu/back opens Settings over the still-paused summary, while
`nw_continue` or `nw_chart` advances into the chart. Ordinary gameplay
menu/back opens Settings. Chart actions are blocked behind ending, startup,
Settings, and modal tutorial surfaces.
Tutorial replay is unavailable while a phase summary owns the intermission;
both the HUD control and the game transition guard enforce that boundary.

`HUD.open_settings()` remembers the prior gameplay focus, pauses only when
necessary, makes the mouse visible, synchronizes persisted values, reopens the
last selected page, and restores that page's last valid focus target. One fixed
instrument console contains a left navigation rail and six mutually exclusive
pages: General, Audio, Display, Accessibility, Controls, and Save. Controls is
not a nested overlay; `Esc` from any ordinary page closes the whole console in
one action. Active key capture and confirmation dialogs still consume `Esc`
first. Closing Settings cancels capture/dialog state and restores both pause
ownership and the previous valid gameplay focus target.

The header explicitly says the observation is paused. Audio has master volume,
master mute, and an effective unfocused mute that never changes the stored user
mute. Display owns window/fullscreen, VSync, and a 30/60/120/unlimited frame
cap. Accessibility owns camera impact
intensity (kick and shake) and full-screen observation flashes. A zero impact
value removes both camera channels; disabling flashes leaves rings, particles,
banners, and sound intact. Save reports the active slot, the 60-second autosave
policy, last-save time or failure, then exposes the existing confirmed slot
operations.

Rebinding is an explicit capture state. `Esc` cancels; modifier-only, pointer,
and controller input is swallowed without completing the keyboard-only capture.
A successful key press or cancel records its keycode until the matching release
is also consumed, preventing that release from activating the newly bound
action or the focused button. Conflict checks compare fixed and editable slots
only where their declared contexts overlap. GUI-navigation keys and the raw
debug chords are reserved because they would be consumed before or instead of
the configurable route. `Enter`, keypad `Enter`, and `Space` are additionally
reserved for the editable menu/back and fullscreen slots so a focused GUI
control cannot activate itself before those global routes run. Locked
mouse/`Esc`/`Enter`/`Space` fallbacks survive rebinding, per-action load
fallback, and reset; unrelated project `InputMap` actions are never erased.
The optional menu/back alternate has its own Remove action, which clears only
that slot and leaves locked `Esc` plus every other customized action intact.

Binding changes have two notification levels. `binding_changed(action)` updates
the chart's action labels selectively. `input_bindings_changed` refreshes HUD
controls/readouts and the tutorial's current binding-labelled step. Audio and
audio policy, display/performance, accessibility, and fullscreen signals
likewise resynchronize the Settings controls. `game.gd` applies accessibility
signals to `EffectsLayer`; scalar settings never alter target identity or
economy.

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
- Once `galactic_reference_frame` makes `galaxy_unlocked()` true, common and
  fast meteors stop dispatching even high-grade success flashes. Before then,
  only semantically accented completions are eligible for a flash.
  `meteor_screen_scale()` gives meteor-generated kick and all active success
  flashes the same `1 / sqrt(span)` on-screen reduction as the drawing.
- `meteor_shake_scale()` attenuates repeated meteor shake more strongly at
  `1 / span`; HUD installation rules and hitstop keep their own contracts.
- `game.gd` applies one additional `0.5` feedback scale to `fragment_piece`
  success flashes and shake. Parent fragments, kick, audio, and reward keep
  their existing paths.

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

host_stars.transit_confirmed / host_harvested / transit_missed
                              → game handlers
galactic_phenomena.phenomenon_observed
                              → game._on_galactic_phenomenon_observed

progression.upgrade_purchased → game._on_upgrade_purchased
effects.packet_landed         → game._on_packet_landed

events.banner_requested       → game._on_event_banner
events.sky_activity_changed   → game._on_sky_activity_changed
events.forecast_requested     → game._on_shower_forecast_requested
events.shower_started         → game._on_shower_started

settings.language_changed     → game._on_language_changed
upgrade_tree.tree_opened      → tutorial.notify_upgrade_tree_opened
upgrade_tree.tree_closed      → game._on_upgrade_tree_closed
upgrade_tree.galactic_pullback_finished
                              → game._on_galactic_pullback_finished

hud.catalogue_finish_requested   → game._on_catalogue_finish_requested
hud.catalogue_continue_requested → game._on_catalogue_continue_requested
hud.phase_summary_continue_requested /
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

## Research-node colour ownership

`upgrade_tree._apply_node_visual` binds the definition's `Balance.BRANCHES`
colour to `StarNodeVisual` (implemented in `research_star_visual.gd`). Its
`state_ink` helper is read by the actual star,
cluster and galaxy draw paths, not merely stored in an unused field. A small
branch component is mixed into the existing warm state ink: 28% for an
affordable frontier, 12% for an open but unaffordable node, 6% for an installed
node, and none for hidden/locked/teaser states. Alpha, geometry, filling,
halo sizes and pulse timing remain state-owned. The shared legend remains a
neutral warm explanation of state, not a thirteen-colour branch key.

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
_on_upgrade_tree_closed()
    → show the catalogue ending when a qualified final watch has completed
    → otherwise _begin_observation_phase(advance_round = true)
```

The catalogue ending requires both semantic completion predicates: all 107
functional research nodes are installed and all five canonical galactic
phenomena are recorded. The 17 decorative Local Group records are presentation
only and never participate in this predicate. Merely reaching either half does
not end a round.

The qualifying final watch must have **started with all research installed**.
If the last research is bought during the preceding intermission, the next full
round is therefore still played with the completed array. If the fifth
phenomenon is recorded during a fully researched round, that same round can be
the final watch. It finishes normally, preserves its ordinary phase summary,
then routes through the completed chart. Closing that chart shows the neutral
catalogue record instead of starting another round. `SoundSynth.play_complete()`
plays the completion chord while the always-processing HUD owns input and runs
an eight-second procedural coda: the actual 95 chart stars and twelve
constellation shapes light, pull back into the Milky Way, then connect and light
all 30 galaxy-map markers (the Milky Way plus 29 Local Group records). The coda
uses the chart's shared records, shape edges, and galaxy-disc projection instead
of an invented route. Its 12 functional and 17 decorative Local Group records
participate equally in this presentation only; no research, purchase, unlock,
eligibility, or save state changes. The completed map settles on the left while
record copy and choices appear on the right. The choices stay disabled until
the reveal completes. Deliberate keyboard, mouse, or controller input
after two seconds skips to the exact completed frame without also activating a
choice. Both actions persist the ending acknowledgement before
leaving that screen. A failed acknowledgement save therefore leaves the ending
open. Finishing returns to the slot screen without deleting the run; continuing
starts the next ordinary open-night round in the same save.
Neither choice grants prestige or a replay bonus.

`Ctrl+Shift+E` opens the same completion chord, procedural coda, statistics, and
choice layout as a non-persistent debug preview. It does not alter catalogue
eligibility, the seen flag, the current round, or save data. Pressing the chord
again—or either ending choice—closes the preview and restores the previous
pause and mouse state.

`game.gd` remains the owner of the state machine. It passes the two display
facts to `upgrade_tree.configure_catalogue_ending_state()`: during an
intermission while a final watch is still owed, the galaxy-scale completion
line tells the player to close the chart and begin it; if that watch is already
active, the chart reverts to ordinary close/resume copy. Once the qualified
watch has ended, the same line and both close actions say that they will seal
the record. The chart does not derive completion from node counts itself.

Installing the 86 non-Draco systems reveals Draco's root; installing all 95
original systems opens the saved Galactic Reference Frame state. The open chart
also performs one saved 3.6-second
pull-back: constellation structure and decorative background stars fade while
the 95-node chart collapses into the interactive Galactic Reference Frame node
at the Milky Way centre. Before that collapse completes, a constant-speed route
head traces the installed Local Group path; each real node lights near its final
screen position when the route reaches it and settles over only the last few
percent of its radius. Its radial chart position compensates for the live camera
zoom, so the revealed map does not contract after it appears. There is no
centre-only hold or second expanding-map beat. The installed curved route and
current frontier are the only research lines retained there. It is a
non-terminal presentation state by itself: it does not interrupt an active
observation round, and Ctrl+wheel travels between the galaxy and completed
chart scales after the one-time sequence. Only the separate catalogue-ending
predicate can turn a later chart close into the ending. At galaxy scale, a non-interactive
104-spec-pixel miniature of the twelve completed constellations remains at the
Milky Way centre; one 112-spec-pixel core target replaces the overlapping legacy
buttons. The 29 Local Group positions preserve the data angles and normalized
distance order while remapping into a 0.52-tilted 124–548-spec-pixel disc. Their
Catmull-Rom route has a glow underlay, two dashed reference orbits, two cached
radial halo textures, edge-on rotated galaxy markers, and permanent code labels.
Seventy-four deterministic, non-interactive blue-grey background points occupy
the area outside the route ellipse. Both scales use fixed information columns:
constellation scale owns a 13-row install ledger and a selected-star inspector
with state legend, while galaxy scale swaps in its completion record and
galaxy-profile inspector. Hover changes the persistent selection instead of moving a
cursor tooltip; the constellation sky itself stays free of node-name text, and
the fixed right inspector alone identifies the selection. The Local Group disc
contains 12 functional research nodes and 17 non-interactive astronomical
records, bringing the installable total to 107. Sirius Bloom still schedules one warned Major Fireball at a randomized
viable time in each subsequent round. Observing or losing it does not stop the
night.

### Time invariants

These are load-bearing. Breaking them silently corrupts the Data/min series.

- `elapsed_time` accrues **only** while an observation phase is active. An
  intermission or ending screen costs no run time. The required fully researched
  final watch does count because it is a normal observation round.
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
   multiplier. The semantic accent gate is independent of that strength:
   `fireball`/`major` or a manual `EXCELLENT`/`PERFECT` grade. Routine hits keep
   directional particles and a packet even at maximum combo; only accents may
   add rings (strength >= 0.22) and flashes. Manual accents may kick, and shake
   additionally requires strength >= 0.50. Hitstop still requires a manual
   `fireball`/`major` with strength >= 0.66 and has a 400 ms real-time cooldown
   after release. Existing galaxy-stage common/fast flash suppression remains.

Host harvests and galactic-phenomenon completions explicitly request accent
particles/rings, but the latter retain their zero-flash contract. Proc origins
(shower, echo, storm, survey) do not promote individual routine targets.

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
and raw Observation Streak count directly around the changing observation radius
as soon as `observation_streak` is installed. Taurus keeps a separate 4/5/7/10
cap for the stacks that affect its buffs; it does not change the meaning of the
displayed count.

Perseid Watch keeps its three-live-target reward threshold. The controller counts
the same trackable atmospheric children used by the completion reward path and
draws three cursor-local red-light pips; filled pips show progress to the threshold
and all three brighten when it is active. No multiplier text or persistent panel
is added.

Automatic progress (passive automation, dish assist, support lanes) adds into
the same `observation_progress`. Manual and automatic completions are separated
at the reward and feedback layer, not at the progress layer.

After `polar_survey`, a held left button automatically alternates between
`TRACKING` and `SCANNING`, with 14 px of `PENDING` travel before scanning starts.
Tracking gets first refusal on every held frame, including existing target
grace, swept-path hits and non-meteor targets. Multi-target observation keeps a
valid primary target selected. A completion or grace-expiry frame cannot also
charge its travel as a survey stroke. A newly summoned target can be tracked on
the next frame without releasing the button. While no live meteor is
within 150 px, `SurveyController` accumulates cursor distance and rolls a summon
chance at the purchased threshold. A success calls `MeteorSpawner.spawn_meteor`
with the cursor as `custom_start` and a velocity within 60 degrees of the screen
centre, then starts its cooldown. The survey RNG is round-seeded and independent
from every spawner RNG stream.

Summoned meteors carry `polar_summoned` metadata. They use normal observation
rewards, success counts, and Taurus momentum, but the proc tag
prevents them from charging Leo or opening Gemini echoes. Switching modes while
held calls `set_scanning(false, position, true)` to suspend without losing charge.
Base partial charge is lost on actual release, including release while tracking
has already suspended scanning; `sustained_sweep` preserves it only inside the
current round. Round/load/reset boundaries still clear round-local charge.
The charge/cooldown arc stays red and cursor-local; neutral white still belongs
only to live meteor tracking.

### Meteor rendering cache

Each meteor keeps Float64 ribbon weights for its current station count: the
normalized index, taper, shoulder, opacity falloff and turbulence envelope.
Only a count change rebuilds these values. Position/normal, type profile, age
phase, burn visibility and width are still evaluated live; direct age/lifetime
changes do not require invalidation or a process tick. Fragment sparks share
one same-draw debris-envelope calculation. The two triangle ribbons, all
vertices/colors, additive material, object caps and gameplay getters retain
their previous behavior. `meteor_render_cache_test.gd` compares the packed
geometry against the pre-optimization arithmetic.

## Purchase flow

`upgrade_tree.gd` → `progression.request_purchase(node_id)` validates state and
cost, then emits `upgrade_purchased`. `game._on_upgrade_purchased` refreshes
dishes and spawner features, plays the research dyad, extends an existing rule
from 20% to full width over 0.28 seconds, and autosaves. The open chart owns the
visible constellation/galaxy inspector rule; the closed-chart path uses the HUD
banner rule. A HUD-only pulse is occluded by the chart's opaque higher layer.
Installation does not emit meteor particles, rings, flashes, kick, or shake.
Replacement announcements, selection, context, close, resize, and scale changes
cancel stale rule tweens and restore full width. The Reference Frame purchase
keeps its existing pull-back transition without animating a hidden inspector.

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

The Local Group chart still renders 29 astronomical records, but only 12 are
functional research. The other 17 live only in `research_chart_data.gd` with
`decorative = true`; they have no `UPGRADE_NODES` definition, button, state,
cost, research-route edge, or inspector. The ending plate alone may connect
and light these records as part of its completed 30-marker map. That visual
exception does not change the interactive chart or the live research total of 107.
`ProgressionController.get_observation_span()` counts the last node of
each of the four chapters and compounds exact `×1.1025` steps up to
`1.4774554`.
`ObservationView` owns that span and routes world/screen rectangles and lengths;
starfield, twinkle, input, effects, and spawner consumers continue to derive
their geometry from it. The starfield's gradient bands and horizon ridge follow
the current visible-world frame, so the fixed atmospheric rectangle remains a
vertical safety boundary and never appears as a rendered edge.

`MeteorSpawner` chooses the entry boundary before solving the burnout geometry:
30% top, 35% left, and 35% right, with bottom entry still forbidden by the HUD
shelf. A low-discrepancy 20-entry cycle spreads the six top and seven entries
from each side instead of allowing short random streaks. It intersects the
chosen boundary's exact travel-distance circle with
the safe 4×3 burnout cell interior instead of counting whatever point
candidates happen to survive. This keeps the same entry mix at both opening and
final observation spans, including after lifetime upgrades, and prevents the
wider late-game sky from converting lateral entries into top entries.

`HostStarLayer` is a separate `HostStarController`, not a child of
`MeteorLayer`. `lmc_transit_watch` starts one distant target and one active
window; `m33_transit_network` raises both caps to two. A target schedules on the
existing 8–12 second cadence and gives one 8-second manual window. Completing
the ordinary hold pays immediately, removes that target, and schedules a 6–8
second replacement. There is no second harvest gesture, comparison target,
blank-sky reveal, decoy, linked abandonment, or reference-star reward rule.
Host objects never consume the atmospheric `MAX_TOTAL_METEORS = 32` budget.

Chapter one rotates through four presentation profiles while preserving the
same observation API. LMC is the baseline. SMC uses `×1.35` required tracking
time, `0.82` visual scale, and `0.70` brightness. M31 uses `1.36` visual scale
and a slow 30-screen-pixel drift at `0.34` radians per second. M33 is another
ordinary profile while its milestone permits two targets to be active at once.

`GalacticPhenomenaLayer` is another independent target layer. Chapter two owns
two persistent supernova targets. Their `discovered → peak → fading → remnant`
clocks advance only while an observation round is active; intermissions and
offline time do not advance them. The remnant is indefinitely trackable, so a
miss changes reward quality but cannot permanently lose catalogue completion.
`is_record_complete()`, `get_completed_record_count()`, and
`get_record_target_count()` enumerate the canonical `TARGET_SPECS` keys rather
than trusting the raw saved dictionary; unknown ids cannot satisfy or inflate
the ending record.
The layer exposes at most the first two unlocked incomplete phenomena. Once
both supernovae are recorded, the full and partial lens shapes take their
places; once those are recorded, the lensed supernova becomes visible.
Chapter three adds full-ring then partial-ring shapes. `ObservationController`
uses each target's annulus hit distance but otherwise calls the same
`apply_manual_observation()` hold API used by meteors, hosts, and supernovae.
There is no cursor-path or angular-distance accumulator.

After `phoenix_lensed_meteors`, any meteor whose straight plan intersects the
lens zone receives a quadratic control point. Entry, burnout, lifetime and the
safe activity-rectangle bound remain fixed. `lensed_active` remains a visual
position fact only: base, dish, and lane automation continue normally inside
the zone. The global meteor cap remains 32, and dish tracking speed remains
above the 436.8 px/s fast-meteor regression. Distant-target rewards pay in the
same completion that ends their observation and deliberately bypass global
`×8192` and manual meteor combo growth.

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

Player copy groups the permanent capacity steps and the explicit regular-arrival
floors under `Sky Activity` while retaining each exact delta or floor. This is a
terminology layer only: `get_max_active()` and
`get_regular_spawn_interval_floor()` remain separate scheduling inputs. It is
also unrelated to `EventController.sky_activity_changed`, which controls only
the event-driven starfield tint and brightness.

`game_balance.gd::upgrade_definition()` uses a read-only ID index built once
from the constant `UPGRADE_NODES` array. Ordered enumeration still uses that
array, and no research fields are copied into a separate editable source. The
index caches definitions only, never purchased/revealed/affordable state, so
progression resets, save loads and locale changes need no invalidation. Unknown
IDs keep the previous fresh mutable empty result. Meteor specs remain fresh
dictionaries because their callers customize them.

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

The 38 executable contracts cover ten global value multipliers, four
observation-duration bonuses, eight regular active-contact capacity increases,
four regular-arrival floors, three chapter-one observation profiles, four
chapter milestones, and five phenomenon contracts. M33's fourth profile and
two-target capacity are verified as part of its chapter milestone. The exact
69-node unverified set is a hard baseline, not a wildcard; follow-up work may
shrink it, and adding or exchanging an id requires an explicit test diff.

## Save format

`game.gd::_build_save_data()` writes a flat dictionary containing run timing,
round bookkeeping, the clean-round baseline, and nested progression, host-star,
and galactic-phenomena payloads. Each saved distant target retains its stable id,
visual profile, position, observation progress, transit/respawn clocks, accumulated
quality, and measurements, so active windows
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
save receives none of the 12 functional Local Group nodes automatically.
Compatibility with the removed 29 Local Group research IDs is intentionally not
provided by the approved redesign; unknown old IDs are discarded rather than
migrated.

A resumed round sets `phase_resumed_from_save`, which makes that round its own
comparison baseline instead of presenting pre-load installs as fresh growth.

Autosave runs every 60 seconds of observation time, and on every purchase,
round end, and slot change.

Quick start selects the newest valid record or, when no record exists, the
first empty slot. If all three files exist but fail validation, it opens the
startup recovery surface so the player can reset one explicitly; it never
starts an unsavable slot-zero run.

`galactic_pullback_seen` is a flat game-save presentation flag, separate from
the ID-based progression payload. A missing field is false. A legacy save that
already owns `galactic_reference_frame` therefore plays the sequence once on
its next chart open; a save with the flag true opens directly at the galaxy
scale. Resetting a run clears both progression and this flag. If the process
ends between the purchase autosave and the completion autosave, replaying the
short sequence is the safe fallback.

The catalogue ending uses three flat fields. `catalogue_ending_seen` suppresses
automatic replay after either Finish or Continue. `ending_final_watch_pending`
means the complete catalogue still owes a round that began with all research
installed; a completed-at-intermission record clears it when that qualifying
round ends, while a fifth phenomenon recorded during an already-qualified round
never needs to set it. The saved
`phase_started_with_complete_research` bit lets a resumed in-progress round
retain that qualification. Load accepts that bit only when the validated saved
phase-start signature also contains every functional research node, preventing
a stale flag from qualifying a mixed-build round. A complete save from the
former open-night build has none of these fields, so load deliberately marks
the final watch pending instead of opening an ending over the load screen. A
pending, unseen ending is resumed through the ordinary intermission/chart
boundary; it is never injected mid-round.

Settings are separate from the run-save payload. `game_settings.gd` reads and
writes `user://settings.cfg` with `SETTINGS_VERSION = 3`:

| Section | Keys |
|---|---|
| `settings` | `version` |
| `accessibility` | `language`, `motion_intensity`, `screen_flashes_enabled` |
| `onboarding` | `tutorial_completed` |
| `research_chart` | `rotation` |
| `audio` | `master_linear`, `muted`, `mute_when_unfocused` |
| `display` | `fullscreen`, `vsync_enabled` |
| `performance` | `fps_limit` |
| `input` | one editable-descriptor array for each of the six `nw_*` actions |

Only editable slots are serialized. Loading starts from validated scalar
defaults and the canonical fixed input slots. A malformed or conflicting input
entry falls back only for that action, leaving other valid overrides intact;
missing optional slots remain empty. Applying or resetting Nightwatch bindings
rebuilds those six actions without touching unrelated `InputMap` actions.

Focus notifications change only effective process state. Audio uses
`muted || (mute_when_unfocused && !application_focused)`, so returning to the
game restores the player's explicit mute choice. Frame pacing never changes on
focus transitions; the configured cap applies continuously. Headless fixtures
and timing probes do not apply display pacing side effects.

Tests can inject a path before `_ready()` with `GameSettings.new(path)` or
`set_settings_path(path)`. The production scene uses the default path. This is
the settings equivalent of replacing save services before startup: a fixture
that changes the path after `_ready()` has already allowed the real player file
to be read.
