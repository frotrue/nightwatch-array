extends Node2D

const SimulationClock = preload("res://scripts/simulation_clock.gd")
const MeteorMotionBatch = preload("res://scripts/meteor_motion_batch.gd")
const PARALLEL_MOTION_THRESHOLD := 128
var parallel_motion_enabled := true
const UITheme = preload("res://scripts/ui_theme.gd")
const Balance = preload("res://scripts/game_balance.gd")
const SoundSynth = preload("res://scripts/sound_synth.gd")
const GameInputRouter = preload("res://scripts/game_input_router.gd")
const DeepSkyResearch = preload("res://scripts/deep_sky_research.gd")
const ModulePopup = preload("res://scripts/module_popup.gd")
const AUTOSAVE_INTERVAL_SECONDS := 60.0
const COMBO_STRENGTH_STEP := 0.045
const IMPACT_TARGET_TYPES := ["fireball", "major"]
const FLASHLESS_METEOR_TYPES := ["common", "fast"]
const FRAGMENT_PIECE_FEEDBACK_SCALE := 0.50
# Routine observations use particles and packets only. Accented manual hits
# may move the view; only impact target types may halt simulation.
const KICK_MIN_PIXELS := 1.3
const KICK_MAX_PIXELS := 3.0
const SHAKE_STRENGTH_FLOOR := 0.50
const HITSTOP_STRENGTH_FLOOR := 0.66
# Trauma reaches pixels squared, so the rumble has to enter near the kick's
# ceiling. Entering lower would make crossing the floor a downgrade in felt
# impact rather than an escalation.
const SHAKE_TRAUMA_FLOOR := 0.54
const SHAKE_TRAUMA_CEILING := 0.88

@onready var starfield: Node2D = $Starfield
@onready var twinkle_stars: Node2D = $TwinkleStars
@onready var meteor_layer: Node2D = $MeteorLayer
@onready var black_hole_lens: Node2D = $BlackHoleLens
@onready var debug_celestials: Node2D = $DebugCelestialLayer
@onready var effects: Node2D = $EffectsLayer
@onready var observer: Node2D = $ObservationController
@onready var sky_contacts: Node2D = $SkyContacts
@onready var survey: Node2D = $SurveyController
@onready var progression: Node = $ProgressionController
@onready var spawner: Node = $MeteorSpawner
@onready var events: Node = $EventController
@onready var settings: Node = $GameSettings
@onready var save_games: Node = $SaveGameController
@onready var hud: CanvasLayer = $HUD
@onready var upgrade_tree: CanvasLayer = $UpgradeTree
@onready var tutorial: CanvasLayer = $Tutorial
@onready var module_tutorial: CanvasLayer = $ModuleTutorial
@onready var observation_view: Camera2D = $ObservationView

var sound: Node
var input_router: Node
var deep_sky: Node2D
var module_popup: CanvasLayer
var simulation_clock := SimulationClock.new()
var _in_simulation_tick := false
var _save_after_tick := false
var next_simulation_id := 1
var previous_spawn_model_record: Dictionary = {}

var elapsed_time: float = 0.0
var completed: bool = false
var startup_slot_prompt_enabled: bool = true
var tutorial_auto_start_after_slot: bool = false
var active_save_slot: int = 0
var autosave_elapsed: float = 0.0
var observation_round: int = 1
var observation_phase_active: bool = false
var observation_phase_remaining: float = Balance.BASE_OBSERVATION_DURATION
var observation_phase_duration: float = Balance.BASE_OBSERVATION_DURATION
var phase_start_successes: int = 0
var phase_start_manual_successes: int = 0
var phase_start_automatic_successes: int = 0
var phase_start_total_data: float = 0.0
var phase_start_upgrade_signature: Array[String] = []
var phase_start_equipment: Array[String] = []
var phase_start_owned_modules: Array[String] = []
var phase_start_extension_research: Array[String] = []
var phase_build_mutated := false
var _loading_save := false
var phase_had_shower: bool = false
var phase_resumed_from_save: bool = false
var last_clean_round_result: Dictionary = {}
var best_round_rate: float = 0.0
var suppress_phase_transition: bool = false
var hitstop_active: bool = false
var galactic_pullback_seen: bool = false


func _ready() -> void:
	print("NIGHTWATCH_ENGINE_VERSION: ", Engine.get_version_info())
	starfield.background_visibility_changed.connect(func(alpha: float): twinkle_stars.modulate.a = alpha)
	sound = SoundSynth.new()
	sound.name = "SoundSynth"
	add_child(sound)
	input_router = GameInputRouter.new()
	input_router.name = "GameInputRouter"
	input_router.setup(self, hud, settings, tutorial, upgrade_tree)
	add_child(input_router)

	hud.bind_progression(progression)
	hud.bind_settings(settings)
	hud.performance_monitor.bind_game(self)
	hud.bind_save_games(save_games)
	upgrade_tree.bind_progression(progression)
	upgrade_tree.bind_settings(settings)
	upgrade_tree.bind_tutorial(tutorial)
	tutorial_auto_start_after_slot = startup_slot_prompt_enabled and tutorial.auto_start_enabled
	if startup_slot_prompt_enabled:
		tutorial.auto_start_enabled = false
	tutorial.setup(settings, progression)
	tutorial.tutorial_started.connect(hud.set_guided_tutorial_active.bind(true))
	tutorial.tutorial_completed.connect(hud.set_guided_tutorial_active.bind(false))
	if settings.has_signal("accessibility_changed"):
		settings.accessibility_changed.connect(_on_accessibility_changed)
	hud.phase_summary_continue_requested.connect(_on_phase_summary_continue_requested)
	hud.save_slot_requested.connect(_on_save_slot_requested)
	hud.load_slot_requested.connect(_on_load_slot_requested)
	hud.startup_slot_selected.connect(_on_startup_slot_selected)
	hud.new_game_slot_requested.connect(_on_new_game_slot_requested)
	hud.reset_slot_requested.connect(_on_reset_slot_requested)
	hud.tutorial_replay_requested.connect(_on_tutorial_replay_requested)
	upgrade_tree.tree_opened.connect(tutorial.notify_upgrade_tree_opened)
	upgrade_tree.tree_closed.connect(_on_upgrade_tree_closed)
	upgrade_tree.galactic_pullback_finished.connect(_on_galactic_pullback_finished)
	starfield.setup(observation_view)
	twinkle_stars.setup(observation_view)
	effects.setup(observation_view)
	_apply_accessibility_settings()
	sky_contacts.setup(meteor_layer, progression, observation_view)
	spawner.setup(meteor_layer, progression, observation_view)
	survey.setup(progression, spawner, meteor_layer, observation_view, [])
	observer.setup(meteor_layer, progression, hud, survey, observation_view, [])
	events.setup(spawner, progression, observation_view)
	deep_sky = DeepSkyResearch.new()
	deep_sky.name = "DeepSkyResearch"
	add_child(deep_sky)
	deep_sky.setup(self)
	hud.deep_sky = deep_sky
	deep_sky.changed.connect(hud._refresh_ready_notice)
	deep_sky.changed.connect(hud._refresh_extension)
	deep_sky.changed.connect(_on_deep_sky_changed)
	observer.additional_target_layers.append(deep_sky)
	survey.discovery_layers.append(deep_sky)
	observer.modules = deep_sky.modules
	sky_contacts.additional_target_layers.append(deep_sky)
	survey.modules = deep_sky.modules
	spawner.extension_owner = deep_sky
	module_popup = ModulePopup.new()
	module_popup.name = "ModulePopup"
	add_child(module_popup)
	module_popup.setup(self)
	upgrade_tree.module_popup = module_popup
	module_tutorial.setup(self)
	upgrade_tree.bind_extension(deep_sky)
	upgrade_tree.observatory_requested.connect(_return_to_observatory)

	spawner.meteor_spawned.connect(_on_meteor_spawned)
	spawner.rare_spawned.connect(_on_rare_spawned)
	spawner.contact_announced.connect(sky_contacts.on_contact_announced)
	spawner.contact_resolved.connect(sky_contacts.on_contact_resolved)
	progression.upgrade_purchased.connect(_on_upgrade_purchased)
	effects.packet_landed.connect(_on_packet_landed)
	events.banner_requested.connect(_on_event_banner)
	events.sky_activity_changed.connect(_on_sky_activity_changed)
	events.forecast_requested.connect(_on_shower_forecast_requested)
	events.shower_started.connect(_on_shower_started)

	if startup_slot_prompt_enabled:
		call_deferred("_enter_preferred_save")
	else:
		start_run()


func _enter_preferred_save() -> void:
	var slot := _preferred_startup_slot()
	if slot == 0:
		active_save_slot = 0
		hud.set_active_save_slot(0)
		# No valid or empty slot means every record is corrupt. Keep the player on
		# the recovery surface so one can be explicitly reset; starting an unsaved
		# slot-zero run here would make every later autosave and ending choice fail.
		hud.open_startup_slots()
		return
	_on_startup_slot_selected(slot)


func _preferred_startup_slot() -> int:
	var newest_slot := 0
	var newest_timestamp := -1
	var first_empty_slot := 0
	for slot in range(1, 4):
		var summary: Dictionary = save_games.get_slot_summary(slot)
		var exists := bool(summary.get("exists", false))
		var valid := bool(summary.get("valid", false))
		if exists and valid:
			var saved_at := int(summary.get("saved_at", 0))
			if saved_at > newest_timestamp:
				newest_timestamp = saved_at
				newest_slot = slot
		elif not exists and first_empty_slot == 0:
			first_empty_slot = slot
	return newest_slot if newest_slot > 0 else first_empty_slot


func start_run() -> void:
	debug_celestials.reset()
	module_tutorial.cancel()
	module_popup.close()
	deep_sky.reset()
	elapsed_time = 0.0
	autosave_elapsed = 0.0
	completed = false
	observation_round = 1
	last_clean_round_result.clear()
	previous_spawn_model_record.clear()
	best_round_rate = 0.0
	galactic_pullback_seen = false
	hud.hide_phase_summary()
	hud.reset_tutorial()
	hud.set_runtime(0.0)
	starfield.set_activity(0.0)
	_sync_galactic_systems()
	starfield.set_galactic_mode(progression.galaxy_unlocked())
	upgrade_tree.configure_galactic_state(progression.galaxy_unlocked(), galactic_pullback_seen)
	_begin_observation_phase()


func reset_run() -> void:
	module_tutorial.cancel()
	module_popup.close()
	completed = false
	_release_hitstop()
	_close_upgrade_tree_without_transition()
	get_tree().paused = false
	observer.reset()
	sky_contacts.reset()
	survey.reset()
	effects.reset()
	events.reset()
	spawner.reset()
	progression.reset()
	hud.hide_phase_summary()
	hud.reset_tutorial()
	start_run()
	_autosave_active_slot()
	hud.show_banner(tr("BANNER_RESET"), UITheme.BANNER_SUB, 2.0)


func _process(_delta: float) -> void:
	if completed or not observation_phase_active: return
	starfield.set_watch_progress(1.0 - observation_phase_remaining / observation_phase_duration)
	hud.set_runtime(elapsed_time)
	hud.set_observation_phase(observation_round, observation_phase_remaining, observation_phase_duration)

func _physics_process(_delta: float) -> void:
	simulate_tick()

func allocate_simulation_id() -> int:
	var id := next_simulation_id
	next_simulation_id += 1
	return id


func _tick_target_motion(targets: Array, delta: float) -> void:
	var snapshots: Array = []
	var indices: Dictionary = {}
	if parallel_motion_enabled and targets.size() >= PARALLEL_MOTION_THRESHOLD:
		for target in targets:
			if target.is_queued_for_deletion() or not target.alive or not target.has_method("motion_snapshot"): continue
			if target.gravity_capture != null: continue
			indices[target] = snapshots.size()
			snapshots.append(target.motion_snapshot(delta))
	var results: Array = []
	if not snapshots.is_empty():
		results = observer.simulation_workers.map_chunks(snapshots.size(), MeteorMotionBatch.calculate.bind(snapshots))
	for target in targets:
		if target.is_queued_for_deletion(): continue
		if indices.has(target):
			target.apply_motion_result(results[indices[target]], delta, simulation_clock.tick)
		else:
			target.tick_motion(SimulationClock.STEP if target.type_id == "anomaly_rare" else delta, simulation_clock.tick)

func simulate_tick() -> void:
	if completed or not observation_phase_active or get_tree().paused: return
	_in_simulation_tick = true
	var scale: float = simulation_clock.begin_tick()
	var motion_delta := SimulationClock.STEP * scale
	debug_celestials.simulate_tick(motion_delta)
	hitstop_active = simulation_clock.hitstop_ticks > 0
	spawner.set_phase_time_remaining(observation_phase_remaining)
	# Existing timers expire before this tick's completions can start new effects.
	deep_sky.modules.advance_time(SimulationClock.STEP)
	progression.update_manual_combo(SimulationClock.STEP)
	survey.advance_time(SimulationClock.STEP)
	observer.prepare_tick()
	events.simulate_tick(SimulationClock.STEP)
	spawner.simulate_tick(SimulationClock.STEP)
	deep_sky.director.simulate_tick(SimulationClock.STEP)
	var targets: Array = meteor_layer.get_children() + deep_sky.director.targets()
	targets.sort_custom(func(a, b): return a.simulation_id < b.simulation_id)
	_tick_target_motion(targets, motion_delta)
	sky_contacts.simulate_tick(motion_delta)
	spawner._refresh_secondary_camera()
	# Rebuild transient beam work from this tick's snapshot before observation/resolve.
	# This also clears assistance when a source departs; newborns wait until next tick.
	for target in targets:
		if target.type_id != "anomaly_rare": target.pulsar_assist_rate = 0.0
	var beam_bounds: Rect2 = observation_view.atmospheric_rect()
	for source in targets:
		if source.type_id == "neutron_star": source.illuminate_targets(targets, beam_bounds)
	observer.simulate_tick(motion_delta)
	for target in targets:
		if not target.is_queued_for_deletion():
			target.tick_observation(SimulationClock.STEP if target.type_id == "anomaly_rare" else motion_delta)
	# Snapshot iteration prevents fragments/procs from receiving work on their birth tick.
	for target in targets:
		if not target.is_queued_for_deletion(): target.tick_resolve()
	elapsed_time += SimulationClock.STEP
	observation_phase_remaining = maxf(0.0, observation_phase_remaining - SimulationClock.STEP)
	if observation_phase_remaining < 0.000001: observation_phase_remaining = 0.0
	spawner.set_phase_time_remaining(observation_phase_remaining)
	_in_simulation_tick = false
	if active_save_slot > 0:
		autosave_elapsed += SimulationClock.STEP
		if autosave_elapsed >= AUTOSAVE_INTERVAL_SECONDS:
			autosave_elapsed = fmod(autosave_elapsed, AUTOSAVE_INTERVAL_SECONDS)
			_autosave_active_slot()
	if observation_phase_remaining <= 0.0:
		_end_observation_phase()

	if _save_after_tick:
		_save_after_tick = false
		_autosave_active_slot()


func _observation_duration() -> float:
	return progression.get_observation_duration()


func _begin_observation_phase(advance_round: bool = false, remaining_override: float = -1.0, resume_game: bool = false) -> void:
	if advance_round:
		observation_round += 1
	var duration := _observation_duration()
	observation_phase_duration = duration
	simulation_clock.reset_boundary()
	observer.reset()
	observation_phase_remaining = duration if remaining_override < 0.0 else clampf(remaining_override, 0.0, duration)
	starfield.set_watch_progress(1.0 - observation_phase_remaining / duration)
	spawner.set_phase_time_remaining(observation_phase_remaining)
	observation_phase_active = true
	progression.reset_manual_combo()
	deep_sky.modules.reset_round()
	sound.reset_streak_audio()
	phase_start_successes = progression.success_count
	phase_start_manual_successes = progression.manual_successes
	phase_start_automatic_successes = progression.automatic_successes
	phase_start_total_data = progression.total_data_earned
	phase_start_upgrade_signature = _current_build_signature()
	phase_start_equipment = _current_equipment_signature()
	phase_start_owned_modules = _validated_module_ids(deep_sky.modules.purchased)
	phase_start_extension_research = deep_sky.state.research_ids.duplicate()
	phase_start_extension_research.sort()
	phase_build_mutated = false
	phase_had_shower = false
	phase_resumed_from_save = false
	upgrade_tree.clear_intermission_context()
	hud.hide_phase_summary()
	hud.set_observation_phase(observation_round, observation_phase_remaining, observation_phase_duration)
	spawner.start_spawning()
	survey.begin_round(observation_round)
	events.run_time = elapsed_time
	events.start()
	# Canis Major remains a recurrent round event.
	var pending_leonid_count := _try_start_leonid_storm()
	if pending_leonid_count > 0:
		hud.show_discovery_banner("leonid_storm", tr("BANNER_LEONID_STORM") % pending_leonid_count, UITheme.INK_MAX, 1.8)
	spawner.refresh_active_features()
	if resume_game:
		get_tree().paused = false


func _end_observation_phase() -> void:
	if completed or not observation_phase_active:
		return
	debug_celestials.reset()
	deep_sky.end_round()
	progression.reset_manual_combo()
	deep_sky.modules.reset_round()
	sound.reset_streak_audio()
	var result := _build_round_result()
	var previous_result := last_clean_round_result.duplicate(true)
	var build_changed := bool(result.get("build_changed", false))
	result["systems_since_baseline"] = _systems_since_baseline(result, previous_result)
	var comparison_state := "comparison"
	if bool(result.get("equipment_changed", false)) or (not previous_result.is_empty() and previous_result.get("equipment_signature", []) != result.equipment_signature):
		comparison_state = "equipment_changed"
	elif build_changed:
		comparison_state = "systems_changed"
	elif phase_resumed_from_save:
		comparison_state = "session_resumed"
	elif previous_result.is_empty():
		comparison_state = "first_baseline"
	var round_rate := float(result.get("rate", 0.0))
	var new_best := round_rate > best_round_rate
	best_round_rate = maxf(best_round_rate, round_rate)
	# Mixed-build rounds are honest total-output achievements, but they do not
	# replace the clean before/after baseline. A resumed sample establishes a new
	# baseline because loading necessarily resets the live sky.
	if not build_changed:
		last_clean_round_result = result.duplicate(true)
	observation_phase_active = false
	observation_phase_remaining = 0.0
	events.pause_for_intermission()
	observer.reset()
	sky_contacts.reset()
	survey.end_round()
	effects.reset()
	spawner.reset()
	starfield.set_activity(progression.get_progression_ratio() * 0.16)
	hud.set_upgrade_phase(observation_round)
	var next_round := observation_round + 1
	upgrade_tree.set_intermission_context(next_round, int(_observation_duration()))
	_autosave_active_slot()
	get_tree().paused = true
	var sunrise_delay: float = starfield.finish_watch(settings.get_motion_intensity() > 0.0)
	hud.show_phase_summary(
		result,
		previous_result,
		comparison_state,
		new_best,
		sunrise_delay
	)


func _build_round_result() -> Dictionary:
	var current_signature := _current_build_signature()
	var extension_signature: Array[String] = deep_sky.state.research_ids.duplicate()
	extension_signature.sort()
	var equipment := _current_equipment_signature()
	var equipment_changed := phase_build_mutated or equipment != phase_start_equipment
	var acquired: Array[String] = []
	for id in _validated_module_ids(deep_sky.modules.purchased):
		if id not in phase_start_owned_modules:
			acquired.append(id)
	var extension_acquired: Array[String] = []
	for id in deep_sky.state.research_ids:
		if id not in phase_start_extension_research:
			extension_acquired.append(id)
	var duration := maxf(0.05, observation_phase_duration)
	var data_earned := maxi(0, int(round(progression.total_data_earned - phase_start_total_data)))
	return {
		"round": observation_round,
		"duration": duration,
		"data": data_earned,
		"rate": float(data_earned) * 60.0 / duration,
		"observations": maxi(0, progression.success_count - phase_start_successes),
		"manual": maxi(0, progression.manual_successes - phase_start_manual_successes),
		"automatic": maxi(0, progression.automatic_successes - phase_start_automatic_successes),
		"systems_installed": maxi(0, current_signature.size() - phase_start_upgrade_signature.size()),
		"shower": phase_had_shower,
		"build_changed": current_signature != phase_start_upgrade_signature or equipment_changed or extension_signature != phase_start_extension_research,
		"build_signature": current_signature,
		"build_measurement_version": 2,
		"equipment_signature": equipment,
		"extension_research_signature": extension_signature,
		"equipment_changed": equipment_changed,
		"modules_acquired": acquired,
		"extension_research_acquired": extension_acquired,
	}


func _current_equipment_signature() -> Array[String]:
	var ids: Array[String] = deep_sky.modules.installed_ids()
	ids.sort()
	return ids


func _on_deep_sky_changed() -> void:
	if module_tutorial.debug_preview:
		return
	if not _loading_save:
		sky_contacts.refresh_dishes()
		spawner.refresh_active_features()
	if _loading_save or not observation_phase_active:
		return
	phase_build_mutated = phase_build_mutated or _current_equipment_signature() != phase_start_equipment


func _current_build_signature() -> Array[String]:
	var signature: Array[String] = []
	for node_variant in progression.purchased_nodes.keys():
		signature.append(String(node_variant))
	signature.sort()
	return signature


func _systems_since_baseline(result: Dictionary, previous_result: Dictionary) -> Array[String]:
	# A resumed sky becomes its own baseline, so pre-load installs are not
	# presented as fresh growth. A live purchase after resuming still takes the
	# mixed-build path and retains its context.
	if phase_resumed_from_save and not bool(result.get("build_changed", false)):
		return []
	var current_signature := _validated_signature(result.get("build_signature", []))
	var baseline_signature := _validated_signature(previous_result.get("build_signature", []))
	var installed: Array[String] = []
	for node_id in current_signature:
		if node_id not in baseline_signature:
			installed.append(node_id)
	return installed


func _on_phase_summary_continue_requested() -> void:
	if completed or observation_phase_active or not hud.is_phase_summary_open():
		return
	hud.hide_phase_summary()
	upgrade_tree.open_tree()


func _on_upgrade_tree_closed() -> void:
	if suppress_phase_transition or completed:
		return
	if observation_phase_active:
		_resume_observation_if_unblocked()
		return
	_begin_observation_phase(true, -1.0, true)


func _resume_observation_if_unblocked() -> void:
	# Loading a live round can remove a summary that originally owned the pause.
	# Reconcile against visible owners instead of retaining that obsolete pause.
	if not observation_phase_active or completed or upgrade_tree.is_open() or module_popup.is_open():
		return
	if hud.is_settings_open() or hud.is_controls_open() or hud.is_startup_slots_open() or hud.is_phase_summary_open() or tutorial.is_modal_step():
		return
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


func _close_upgrade_tree_without_transition() -> void:
	suppress_phase_transition = true
	upgrade_tree.close_tree()
	suppress_phase_transition = false


func _return_to_observatory() -> void:
	_close_upgrade_tree_without_transition()
	if not observation_phase_active:
		_begin_observation_phase(true, -1.0, true)
	else:
		get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


func handle_debug_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if completed:
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_F9:
		hud.toggle_debug()
		get_viewport().set_input_as_handled()
		return
	if not (event.ctrl_pressed and event.shift_pressed):
		return
	match event.keycode:
		KEY_T:
			module_tutorial.start_debug_preview()
		KEY_D:
			progression.add_debug_data(100.0)
			hud.show_banner(tr("BANNER_DEBUG_DATA"), UITheme.INK_MID, 1.2)
		KEY_N:
			var available: Array[String] = progression.get_available_nodes()
			if not available.is_empty():
				progression.debug_purchase_node(available[0])
		KEY_A:
			if progression.upgrade_level < Balance.research_node_count():
				progression.debug_purchase_all()
			deep_sky.debug_purchase_all_research()
		KEY_G:
			var id: String = deep_sky.debug_draw_module()
			if not id.is_empty():
				if module_popup.is_draw_open():
					module_popup.draw_window.show_debug_result(id)
				hud.show_banner(tr("BANNER_DEBUG_MODULE") % tr("MODULE_%s_NAME" % id.to_upper()), UITheme.INK_MID, 2.0)
		KEY_M:
			spawner.spawn_meteor("common")
		KEY_B:
			spawner.spawn_meteor("black_hole")
		KEY_W:
			var preview = debug_celestials.spawn_observable_white_hole(get_global_mouse_position(), observation_view.screen_length_to_world(1.0))
			var key := "DEBUG_WHITE_HOLE_SPAWNED" if preview != null else "DEBUG_WHITE_HOLE_LIMIT"
			hud.show_banner(tr(key), UITheme.INK_MID, 2.0)
		KEY_E:
			debug_celestials.cycle_effect()
			var key := "DEBUG_WHITE_HOLE_WAVES" if debug_celestials.effect_mode == 0 else "DEBUG_WHITE_HOLE_JETS"
			hud.show_banner(tr(key), UITheme.INK_MID, 2.0)
		KEY_R:
			spawner.spawn_meteor("fireball")
		KEY_S:
			events.trigger_shower()
		KEY_F:
			events.trigger_canis_major_warning()
		KEY_BACKSPACE:
			reset_run()
		_:
			return
	get_viewport().set_input_as_handled()


func _on_meteor_spawned(meteor) -> void:
	meteor.observation_controller = observer
	meteor.completion_motion_scale = effects.motion_intensity
	meteor.completion_glint_enabled = effects.screen_flashes_enabled
	meteor.optical_lens = black_hole_lens
	if meteor.type_id == "black_hole":
		meteor.z_index = 2 # Above the lens at 11; ordinary meteors remain at 10.
		black_hole_lens.track(meteor)
	meteor.observed.connect(_on_meteor_observed)
	meteor.expired.connect(_on_meteor_expired)
	if progression.has_upgrade("wide_field") and progression.forecast_type_visible(String(meteor.type_id)):
		# The edge marker is an instrument annotation, not the object, so it takes
		# red light. The meteor keeps its own colour: the sky is what is being
		# observed and the instrument is what does the observing.
		var marker_ink: Color = UITheme.INK_MAX if meteor.type_id in ["fireball", "major"] else UITheme.ACCENT_PIP
		effects.spawn_incoming(meteor.global_position, meteor.velocity, marker_ink)


func _complete_supernova(source) -> void:
	var radius: float = source.SUPERNOVA_RADIUS * observation_view.screen_length_to_world(1.0) * progression.extension_effect("supernova_radius")
	source.supernova_radius = radius
	# Freeze membership before any completion callback can create new fragments.
	# Only live, on-screen bodies count; forecasts are never completed early.
	var candidates: Array = meteor_layer.get_children() + deep_sky.director.targets()
	var targets: Array = []
	var bounds: Rect2 = observation_view.atmospheric_rect()
	for target in candidates:
		if not target.alive or target.is_queued_for_deletion() or target.type_id in ["stellar", "black_hole", "white_hole", "neutron_star"]: continue
		if target.has_method("can_be_tracked") and not target.can_be_tracked(): continue
		if not bounds.has_point(target.global_position): continue
		if target.global_position.distance_squared_to(source.global_position) <= radius * radius:
			targets.append(target)
	for target in targets:
		target.complete_from_supernova()


func _on_meteor_observed(meteor, reward: float, multiplier: float, was_manual: bool, quality_grade: String) -> void:
	meteor.completion_motion_scale = effects.motion_intensity
	meteor.completion_glint_enabled = effects.screen_flashes_enabled
	if meteor.type_id == "stellar" and observation_phase_active:
		_complete_supernova(meteor)
		spawner.prepare_stellar_remnant(meteor)
	if meteor.type_id == "black_hole" and observation_phase_active:
		var world_scale: float = observation_view.screen_length_to_world(1.0)
		var radius: float = meteor.BLACK_HOLE_PULL_RADIUS * world_scale * progression.extension_effect("gravity_radius")
		var extra_slow: float = progression.extension_effect("gravity_slow_seconds", 0.0)
		for target in meteor_layer.get_children():
			if target.global_position.distance_squared_to(meteor.global_position) <= radius * radius:
				target.begin_gravity_capture(meteor.position, world_scale, extra_slow)
	if observation_phase_active:
		deep_sky.modules.record_completion(meteor)
	observer.release_target(meteor)
	# Observation technique belongs to feedback and the end-of-run manual stat;
	# research value growth belongs only to the economy. Keeping the two values
	# separate prevents an x2 research leaf from changing how the same hit feels.
	var intrinsic_multiplier := multiplier
	var active_target_count: int = observer.get_visible_atmospheric_target_count(meteor)
	var research_multiplier: float = progression.get_observation_value_multiplier(
		String(meteor.type_id), active_target_count
	)
	reward = round(reward * research_multiplier)
	var final_reward: float = progression.add_observation(reward, was_manual, intrinsic_multiplier)
	var is_proc_meteor: bool = (
		bool(meteor.get_meta("gemini_echo", false))
		or bool(meteor.get_meta("leonid_storm", false))
		or bool(meteor.get_meta("perseid_outburst", false))
		or bool(meteor.get_meta("polar_summoned", false))
		or bool(meteor.get_meta("module_fragment", false))
		or bool(meteor.get_meta("white_hole_ejecta", false))
		or meteor.type_id in ["white_hole", "neutron_star"]
	)
	var leonid_spawn_count := 0
	if was_manual and not is_proc_meteor and not meteor.is_major():
		progression.record_leonid_manual_success()
		leonid_spawn_count = _try_start_leonid_storm()
	var echo_spawn_count := 0
	if not meteor.is_major():
		echo_spawn_count = spawner.try_spawn_observation_echo(
			was_manual,
			is_proc_meteor,
			meteor
		)
	spawner.try_spawn_module_fragments(meteor, float(deep_sky.modules.effect("split_chance")))
	# Base value is target identity, not economy. Quality and the live manual
	# chain remain explicit feedback inputs inside _observation_strength.
	var strength := _observation_strength(float(meteor.base_value), was_manual, quality_grade)
	var meteor_type_id := String(meteor.type_id)
	var accented := _is_accented_observation(meteor_type_id, was_manual, quality_grade)
	var meteor_screen_scale: float = observation_view.meteor_screen_scale()
	effects.spawn_success(
		meteor.global_position,
		final_reward,
		meteor.get_visual_color(),
		intrinsic_multiplier,
		strength,
		quality_grade,
		hud.get_data_anchor(),
		_meteor_flash_scale(meteor_type_id),
		accented,
		meteor.velocity
	)
	if was_manual:
		sound.play_success(intrinsic_multiplier, progression.manual_combo_count, strength)
	else:
		# Automation gets its own quiet voice. Routing it through the manual
		# ladder would hold the chain at the top note for free and erase the one
		# signal that reports the player is still the one keeping rhythm.
		sound.play_automatic_tick()
	# View motion answers "you did that", so it is manual only. An automatic
	# completion is the payoff of a research decision made minutes ago, not an
	# action taken now, and once the array is built they fire continuously: a
	# permanently moving screen would leave a real hit nothing to stand against.
	# A chain still raises particle/sound weight, but cannot promote a routine
	# target to an accent by itself. High quality or rare identity is required.
	if was_manual and accented:
		effects.add_kick(
			meteor.global_position,
			lerpf(KICK_MIN_PIXELS, KICK_MAX_PIXELS, strength),
			meteor_screen_scale
		)
		var is_impact_target := meteor_type_id in IMPACT_TARGET_TYPES
		if strength >= SHAKE_STRENGTH_FLOOR:
			var weight := clampf((strength - SHAKE_STRENGTH_FLOOR) / (1.0 - SHAKE_STRENGTH_FLOOR), 0.0, 1.0)
			effects.add_shake(
				lerpf(SHAKE_TRAUMA_FLOOR, SHAKE_TRAUMA_CEILING, weight),
				_meteor_shake_scale(meteor_type_id)
			)
		if is_impact_target and strength >= HITSTOP_STRENGTH_FLOOR:
			var freeze_weight := clampf((strength - HITSTOP_STRENGTH_FLOOR) / (1.0 - HITSTOP_STRENGTH_FLOOR), 0.0, 1.0)
			_apply_hitstop(lerpf(0.05, 0.11, freeze_weight))
	if progression.has_upgrade("perfect_observation") and was_manual and quality_grade in ["EXCELLENT", "PERFECT"]:
		hud.show_discovery_banner("quality", tr("BANNER_QUALITY") % [tr("QUALITY_%s" % quality_grade), intrinsic_multiplier], meteor.get_visual_color(), 1.5)
	if echo_spawn_count > 0:
		hud.show_discovery_banner("gemini_echo", tr("BANNER_GEMINI_ECHO") % echo_spawn_count, UITheme.INK_MAX, 1.5)
	if leonid_spawn_count > 0:
		hud.show_discovery_banner("leonid_storm", tr("BANNER_LEONID_STORM") % leonid_spawn_count, UITheme.INK_MAX, 1.8)
	if progression.success_count == 1:
		hud.mark_first_success()
	tutorial.notify_observation_completed()


func _try_start_leonid_storm() -> int:
	if not progression.leonid_storm_ready():
		return 0
	var storm_count: int = progression.get_leonid_storm_count()
	if not spawner.try_start_leonid_storm():
		return 0
	progression.consume_leonid_storm_charge()
	return storm_count


func _observation_strength(base_value: float, was_manual: bool, quality_grade: String) -> float:
	# One economy-independent scalar keeps feedback amplitudes in agreement. Log
	# scaled: a 14-point common sits near the floor and a 650-point major at the
	# ceiling, which is the target-identity spread in the base reward table.
	var span: float = log(300.0) - log(10.0)
	var strength := clampf((log(maxf(base_value, 10.0)) - log(10.0)) / span, 0.0, 1.0)
	if not was_manual:
		return strength * 0.45
	match quality_grade:
		"PERFECT":
			strength = minf(1.0, strength + 0.30)
		"EXCELLENT":
			strength = minf(1.0, strength + 0.15)
	# Chains strengthen particles and audio. Motion eligibility is a separate
	# semantic gate, so a long chain of ordinary GOOD hits keeps the view still.
	return minf(1.0, strength + minf(float(progression.manual_combo_count), 12.0) * COMBO_STRENGTH_STEP)


func _is_accented_observation(type_id: String, was_manual: bool, quality_grade: String) -> bool:
	# Keep rare membership identical to MeteorSpawner. Proc/echo/shower origin
	# alone does not elevate each of its many routine completions to an event.
	return type_id in IMPACT_TARGET_TYPES or (was_manual and quality_grade in ["EXCELLENT", "PERFECT"])


func _meteor_flash_scale(type_id: String) -> float:
	if progression.galaxy_unlocked() and type_id in FLASHLESS_METEOR_TYPES:
		return 0.0
	return observation_view.meteor_screen_scale() * _fragment_feedback_scale(type_id)


func _meteor_shake_scale(type_id: String) -> float:
	return observation_view.meteor_shake_scale() * _fragment_feedback_scale(type_id)


func _fragment_feedback_scale(type_id: String) -> float:
	return FRAGMENT_PIECE_FEEDBACK_SCALE if type_id == "fragment_piece" else 1.0


func _apply_hitstop(duration: float) -> void:
	if simulation_clock.request_hitstop(duration): hitstop_active = true


func _release_hitstop() -> void:
	simulation_clock.reset_boundary()
	hitstop_active = false
	Engine.time_scale = 1.0


func _on_packet_landed(amount: float) -> void:
	hud.pulse_data_counter(amount)


func _on_meteor_expired(meteor, _was_major: bool) -> void:
	observer.release_target(meteor)


func _on_upgrade_purchased(definition: Dictionary) -> void:
	# Persist the unlock and its one-time first-draw grant in the same save.
	deep_sky._sync_protocol()
	tutorial.notify_upgrade_purchased()
	sky_contacts.refresh_dishes()
	spawner.refresh_active_features()
	if not observation_phase_active:
		upgrade_tree.set_intermission_context(observation_round + 1, int(_observation_duration()))
	sound.play_upgrade()
	_sync_galactic_systems()
	if String(definition.id) == "galactic_reference_frame":
		hud.show_banner(tr("BANNER_GALACTIC_FRAME"), UITheme.INK_MAX, 3.2)
		upgrade_tree.begin_galactic_pullback()
	else:
		hud.show_banner(tr("BANNER_SYSTEM_ONLINE") % _upgrade_name(definition), UITheme.BANNER_TITLE, 2.4)
	starfield.set_activity(progression.get_progression_ratio() * 0.16)
	starfield.set_galactic_mode(progression.galaxy_unlocked())
	if upgrade_tree.is_open():
		upgrade_tree.pulse_installation_rule()
	else:
		hud.pulse_installation_rule()
	_autosave_active_slot()


func _on_galactic_pullback_finished() -> void:
	if galactic_pullback_seen:
		return
	galactic_pullback_seen = true
	_autosave_active_slot()


func _on_rare_spawned(type_id: String) -> void:
	if type_id == "major":
		return
	var prefix_key := "BANNER_SECONDARY_ALERT" if progression.has_upgrade("rare_detection") and progression.has_upgrade("secondary_camera") else "BANNER_UNUSUAL_SIGNATURE"
	hud.show_banner("%s  •  %s" % [tr(prefix_key), tr("METEOR_%s" % type_id.to_upper())], UITheme.ACCENT_TEXT, 2.0)
	sound.play_rare_target()


func _on_event_banner(text_key: String, color: Color) -> void:
	hud.show_banner(tr(text_key), color, 2.5)
	if text_key in ["EVENT_SHOWER_INCOMING", "EVENT_ATMOSPHERIC_BLOOM", "EVENT_PERSEID_OUTBURST_INCOMING"]:
		sound.play_environment_change()


func _on_sky_activity_changed(value: float) -> void:
	var progression_floor: float = progression.get_progression_ratio() * 0.16
	starfield.set_activity(maxf(value, progression_floor))


func _on_shower_forecast_requested(entry_points: Array) -> void:
	effects.spawn_forecast(entry_points)


func _on_shower_started() -> void:
	if observation_phase_active:
		phase_had_shower = true


func _on_accessibility_changed(_motion_intensity: float, _screen_flashes_enabled: bool) -> void:
	_apply_accessibility_settings()


func _apply_accessibility_settings() -> void:
	if effects == null or not effects.has_method("set_accessibility_effects"):
		return
	var motion_scale := 1.0
	var flashes_enabled := true
	if settings != null and settings.has_method("get_motion_intensity"):
		motion_scale = float(settings.get_motion_intensity())
	if settings != null and settings.has_method("are_screen_flashes_enabled"):
		flashes_enabled = bool(settings.are_screen_flashes_enabled())
	effects.set_accessibility_effects(motion_scale, flashes_enabled)
	if black_hole_lens != null: black_hole_lens.motion_scale = motion_scale
	if debug_celestials != null: debug_celestials.set_accessibility(motion_scale, flashes_enabled)
	if meteor_layer != null:
		for meteor in meteor_layer.get_children():
			meteor.completion_motion_scale = motion_scale
			meteor.completion_glint_enabled = flashes_enabled
			meteor.queue_redraw()


func _upgrade_name(definition: Dictionary) -> String:
	return tr("UPGRADE_%s_NAME" % String(definition.id).to_upper())


func _on_save_slot_requested(slot: int) -> void:
	if module_tutorial.debug_preview:
		return
	var error: Error = save_games.save_slot(slot, _build_save_data())
	if error == OK:
		active_save_slot = slot
		autosave_elapsed = 0.0
		hud.set_active_save_slot(slot)
		hud.show_save_feedback(tr("SAVE_SUCCESS") % slot, UITheme.BANNER_TITLE)
		sound.play_slot_confirm()
	else:
		hud.show_save_feedback(tr("SAVE_FAILURE") % slot, UITheme.ALERT)


func _on_load_slot_requested(slot: int) -> void:
	var data: Dictionary = save_games.load_slot(slot)
	if data.is_empty():
		hud.show_save_feedback(tr("LOAD_FAILURE") % slot, UITheme.ALERT)
		return
	if not _supports_deep_sky_save(data):
		hud.show_save_feedback(tr("EXT_SAVE_NEWER_VERSION"), UITheme.ALERT)
		return
	active_save_slot = slot
	autosave_elapsed = 0.0
	hud.set_active_save_slot(slot)
	_apply_save_data(data)
	hud.close_settings()
	_resume_observation_if_unblocked()
	hud.show_banner(tr("BANNER_SLOT_LOADED") % slot, UITheme.BANNER_TITLE, 2.2)
	sound.play_slot_confirm()


func _on_startup_slot_selected(slot: int) -> void:
	var summary: Dictionary = save_games.get_slot_summary(slot)
	var exists := bool(summary.get("exists", false))
	var valid := bool(summary.get("valid", false))
	if exists and not valid:
		return
	var slot_data: Dictionary = save_games.load_slot(slot) if exists else {}
	if exists and (slot_data.is_empty() or not _supports_deep_sky_save(slot_data)):
		hud.show_banner(tr("EXT_SAVE_NEWER_VERSION"), UITheme.ALERT, 5.0)
		return
	active_save_slot = slot
	autosave_elapsed = 0.0
	hud.set_active_save_slot(slot)
	if exists:
		_apply_save_data(slot_data)
	else:
		_start_fresh_slot()
		_autosave_active_slot()
	hud.close_startup_slots()
	if exists:
		hud.show_banner(tr("BANNER_SLOT_LOADED") % slot, UITheme.BANNER_TITLE, 2.2)
	_start_tutorial_after_slot_if_needed()
	_resume_observation_if_unblocked()


func _on_new_game_slot_requested(slot: int) -> void:
	var summary: Dictionary = save_games.get_slot_summary(slot)
	if bool(summary.get("exists", false)):
		return
	_on_startup_slot_selected(slot)
	hud.close_settings()
	_resume_observation_if_unblocked()


func _on_reset_slot_requested(slot: int) -> void:
	var reset_from_startup: bool = hud.is_startup_slots_open()
	var was_active: bool = slot == active_save_slot
	var error: Error = save_games.reset_slot(slot)
	if error != OK:
		hud.show_slot_reset_feedback(tr("SAVE_RESET_FAILURE") % slot, UITheme.ALERT)
		return
	if reset_from_startup:
		if was_active:
			active_save_slot = 0
			hud.set_active_save_slot(0)
		hud.show_slot_reset_feedback(tr("SAVE_RESET_SUCCESS") % slot, UITheme.BANNER_TITLE)
		return
	if not was_active:
		hud.show_slot_reset_feedback(tr("SAVE_RESET_SUCCESS") % slot, UITheme.BANNER_TITLE)
		return
	hud.close_settings()
	get_tree().paused = false
	_start_fresh_slot()
	_autosave_active_slot()
	_start_tutorial_after_slot_if_needed()


func _start_fresh_slot() -> void:
	module_tutorial.cancel()
	module_popup.close()
	completed = false
	_close_upgrade_tree_without_transition()
	observer.reset()
	sky_contacts.reset()
	survey.reset()
	effects.reset()
	events.reset()
	spawner.reset()
	progression.reset()
	hud.reset_tutorial()
	start_run()


func _start_tutorial_after_slot_if_needed() -> void:
	if tutorial_auto_start_after_slot and progression.success_count == 0 and not settings.is_tutorial_completed():
		tutorial.start_tutorial()
	tutorial_auto_start_after_slot = false


func _autosave_active_slot() -> bool:
	if module_tutorial.debug_preview:
		return true
	if _in_simulation_tick:
		_save_after_tick = true
		return true
	if active_save_slot < 1 or active_save_slot > 3:
		return false
	var error: Error = save_games.save_slot(active_save_slot, _build_save_data())
	if error == OK:
		hud.show_autosaved(active_save_slot)
		return true
	if hud.has_method("show_autosave_failed"):
		hud.show_autosave_failed(active_save_slot)
	hud.show_banner(tr("AUTOSAVE_FAILURE") % active_save_slot, UITheme.ALERT, 2.0)
	return false


func _on_tutorial_replay_requested() -> void:
	if module_popup.is_open() or module_tutorial.active:
		return
	# The round summary already owns the intermission pause. Starting a modal
	# tutorial on top would leave that pause owner behind when the tutorial moves
	# into its live observation step.
	if hud.is_phase_summary_open():
		return
	hud.close_settings()
	tutorial.start_tutorial()


func _build_save_data() -> Dictionary:
	return {
		"rate_measurement_version": 1,
		"spawn_model_version": 2,
		"previous_spawn_model_record": previous_spawn_model_record.duplicate(true),
		"simulation": {"tick": simulation_clock.tick, "epoch": simulation_clock.epoch, "remaining_ticks": roundi(observation_phase_remaining * 60.0),
			"hitstop": simulation_clock.hitstop_ticks, "cooldown": simulation_clock.cooldown_ticks,
			"spawner": spawner.get_simulation_save(), "events": events.get_simulation_save()},
		"elapsed_time": elapsed_time,
		"observation_round": observation_round,
		"observation_phase_active": observation_phase_active,
		"observation_phase_remaining": observation_phase_remaining,
		"observation_phase_duration": observation_phase_duration,
		"phase_start_successes": phase_start_successes,
		"phase_start_manual_successes": phase_start_manual_successes,
		"phase_start_automatic_successes": phase_start_automatic_successes,
		"phase_start_total_data": phase_start_total_data,
		"phase_start_upgrade_signature": phase_start_upgrade_signature.duplicate(),
		"phase_start_equipment": phase_start_equipment.duplicate(),
		"phase_start_owned_modules": phase_start_owned_modules.duplicate(),
		"phase_start_extension_research": phase_start_extension_research.duplicate(),
		"phase_build_mutated": phase_build_mutated,
		"phase_had_shower": phase_had_shower,
		"canis_major_spawned_this_round": spawner.canis_major_spawned_this_round,
		"last_clean_round_result": last_clean_round_result.duplicate(true),
		"best_round_rate": best_round_rate,
		"galactic_pullback_seen": galactic_pullback_seen,
		"progression": progression.get_save_data(),
		"deep_sky": deep_sky.get_save_data(),
		"module_runtime": deep_sky.modules.get_round_state(),
	}


func _apply_save_data(data: Dictionary) -> void:
	var deep_data = data.get("deep_sky", {})
	if not _supports_deep_sky_save(data):
		hud.show_banner(tr("EXT_SAVE_NEWER_VERSION"), UITheme.ALERT, 5.0)
		return
	_loading_save = true
	debug_celestials.reset()
	module_tutorial.cancel()
	module_popup.close()
	sound.reset_streak_audio()
	_close_upgrade_tree_without_transition()
	observer.reset()
	sky_contacts.reset()
	survey.reset()
	effects.reset()
	events.reset()
	spawner.reset()
	completed = false
	elapsed_time = maxf(0.0, float(data.get("elapsed_time", 0.0)))
	autosave_elapsed = 0.0
	observation_round = maxi(1, int(data.get("observation_round", 1)))
	var progression_data = data.get("progression", {})
	progression.load_save_data(progression_data if progression_data is Dictionary else {})
	var legacy_stage = data.get("andromeda", {})
	deep_sky.load_save_data(deep_data if deep_data is Dictionary else {}, legacy_stage if legacy_stage is Dictionary else {})
	galactic_pullback_seen = progression.galaxy_unlocked() and bool(data.get("galactic_pullback_seen", false))
	upgrade_tree.configure_galactic_state(progression.galaxy_unlocked(), galactic_pullback_seen)
	last_clean_round_result = _sanitize_round_result(data.get(
		"last_clean_round_result",
		data.get("last_round_result", {})
	))
	best_round_rate = maxf(0.0, float(data.get(
		"best_round_rate",
		data.get("best_round_data", 0.0)
	)))
	previous_spawn_model_record = data.get("previous_spawn_model_record", {}).duplicate(true) if data.get("previous_spawn_model_record", {}) is Dictionary else {}
	if int(data.get("spawn_model_version", 1)) < 2:
		previous_spawn_model_record = {"last_round": last_clean_round_result.duplicate(true), "best_rate": best_round_rate}
		last_clean_round_result.clear()
		best_round_rate = 0.0
	sky_contacts.refresh_dishes()
	hud.hide_phase_summary()
	hud.restore_tutorial(progression.success_count > 0)
	hud.set_runtime(elapsed_time)
	starfield.set_activity(progression.get_progression_ratio() * 0.16)
	_sync_galactic_systems()
	starfield.set_galactic_mode(progression.galaxy_unlocked())
	var saved_phase_active := bool(data.get("observation_phase_active", true))
	if saved_phase_active:
		var saved_remaining := float(data.get(
			"observation_phase_remaining",
			_observation_duration()
		))
		_begin_observation_phase(false, saved_remaining)
		var saved_duration := float(data.get("observation_phase_duration", _observation_duration()))
		if is_finite(saved_duration):
			observation_phase_duration = clampf(saved_duration, Balance.BASE_OBSERVATION_DURATION, Balance.MAX_OBSERVATION_DURATION)
			observation_phase_remaining = clampf(ceil(saved_remaining * 60.0 - 0.000001) / 60.0, 0.0, observation_phase_duration) if is_finite(saved_remaining) else observation_phase_duration
		var simulation = data.get("simulation", {})
		if not simulation is Dictionary: simulation = {}
		if simulation.get("remaining_ticks") is int or simulation.get("remaining_ticks") is float:
			observation_phase_remaining = clampi(int(simulation.remaining_ticks), 0, roundi(observation_phase_duration * 60.0)) / 60.0
		simulation_clock.tick = maxi(0, int(simulation.get("tick", 0)))
		simulation_clock.hitstop_ticks = clampi(int(simulation.get("hitstop", 0)), 0, 7)
		simulation_clock.cooldown_ticks = clampi(int(simulation.get("cooldown", 0)), 0, 24)
		spawner.restore_simulation_save(simulation.get("spawner", {}) if simulation.get("spawner", {}) is Dictionary else {}, not simulation.has("spawner"))
		if simulation.get("events") is Dictionary: events.restore_simulation_save(simulation.events)
		deep_sky.resume_targets()
		var module_runtime = data.get("module_runtime", {})
		deep_sky.modules.restore_round_state(module_runtime if module_runtime is Dictionary else {})
		if bool(data.get("canis_major_spawned_this_round", false)):
			spawner.canis_major_spawned_this_round = true
			events.canis_major_state = "resolved"
			events.canis_major_timer = 0.0
		phase_start_successes = maxi(0, int(data.get("phase_start_successes", progression.success_count)))
		phase_start_manual_successes = maxi(0, int(data.get("phase_start_manual_successes", progression.manual_successes)))
		phase_start_automatic_successes = maxi(0, int(data.get("phase_start_automatic_successes", progression.automatic_successes)))
		phase_start_total_data = maxf(0.0, float(data.get("phase_start_total_data", progression.total_data_earned)))
		phase_start_upgrade_signature = _validated_signature(data.get("phase_start_upgrade_signature", _current_build_signature()))
		phase_start_equipment = _validated_module_ids(data.get("phase_start_equipment", _current_equipment_signature()), true)
		phase_start_owned_modules = _validated_module_ids(data.get("phase_start_owned_modules", deep_sky.modules.purchased))
		phase_start_extension_research = _validated_extension_ids(data.get("phase_start_extension_research", deep_sky.state.research_ids))
		phase_build_mutated = bool(data.get("phase_build_mutated", false)) or phase_start_equipment != _current_equipment_signature()
		phase_had_shower = bool(data.get("phase_had_shower", false))
		phase_resumed_from_save = true
	else:
		observation_phase_active = false
		observation_phase_remaining = 0.0
		starfield.finish_watch(false)
		survey.end_round()
		hud.set_upgrade_phase(observation_round)
		var next_round := observation_round + 1
		upgrade_tree.set_intermission_context(next_round, int(_observation_duration()))
		call_deferred("_resume_upgrade_intermission")
	_loading_save = false
	spawner.set_phase_time_remaining(observation_phase_remaining)
	# Intermission already restored the completed presentation above. Resetting
	# its clock here would erase either the dawn or the expanded-sky dimming.
	if observation_phase_active:
		starfield.set_watch_progress(1.0 - observation_phase_remaining / observation_phase_duration)
	if observation_phase_active and observation_phase_remaining <= 0.0: _end_observation_phase()
	hud._refresh_extension()


func _supports_deep_sky_save(data: Dictionary) -> bool:
	if int(data.get("spawn_model_version", 1)) > 2: return false
	var deep = data.get("deep_sky", {})
	return deep is Dictionary and DeepSkyResearch.supports_save(deep)


func _validated_module_ids(value, allow_copies: bool = false) -> Array[String]:
	var ids: Array[String] = []
	if value is Array:
		for id in value:
			if id is String and DeepSkyResearch.Modules.DEFINITIONS.has(id) and (ids.size() < 5 if allow_copies else id not in ids):
				ids.append(id)
	ids.sort()
	return ids


func _validated_extension_ids(value) -> Array[String]:
	var ids: Array[String] = []
	if value is Array:
		for id in value:
			if id is String and DeepSkyResearch.Data.RESEARCH.has(id) and id not in ids:
				ids.append(id)
	ids.sort()
	return ids


func _sync_galactic_systems() -> void:
	observation_view.set_observation_span(progression.get_observation_span())


func _validated_signature(value) -> Array[String]:
	var signature: Array[String] = []
	if value is Array:
		for node_variant in value:
			var node_id := String(node_variant)
			if not Balance.upgrade_definition(node_id).is_empty() and node_id not in signature:
				signature.append(node_id)
	signature.sort()
	return signature


func _sanitize_round_result(value) -> Dictionary:
	if not (value is Dictionary) or value.is_empty():
		return {}
	var duration := clampf(
		float(value.get("duration", Balance.MAX_OBSERVATION_DURATION)),
		Balance.BASE_OBSERVATION_DURATION,
		Balance.MAX_OBSERVATION_DURATION
	)
	var data_earned := maxi(0, int(value.get("data", 0)))
	return {
		"round": maxi(1, int(value.get("round", 1))),
		"duration": duration,
		"data": data_earned,
		"rate": maxf(0.0, float(value.get("rate", float(data_earned) * 60.0 / duration))),
		"observations": maxi(0, int(value.get("observations", 0))),
		"manual": maxi(0, int(value.get("manual", 0))),
		"automatic": maxi(0, int(value.get("automatic", 0))),
		"systems_installed": maxi(0, int(value.get("systems_installed", 0))),
		"systems_since_baseline": _validated_signature(value.get("systems_since_baseline", [])),
		"shower": bool(value.get("shower", false)),
		"build_changed": bool(value.get("build_changed", false)),
		"build_signature": _validated_signature(value.get("build_signature", [])),
		"build_measurement_version": 2,
		"equipment_signature": _validated_module_ids(value.get("equipment_signature", []), true),
		"extension_research_signature": _validated_extension_ids(value.get("extension_research_signature", [])),
		"equipment_changed": bool(value.get("equipment_changed", false)),
		"modules_acquired": _validated_module_ids(value.get("modules_acquired", [])),
		"extension_research_acquired": _validated_extension_ids(value.get("extension_research_acquired", [])),
	}


func _resume_upgrade_intermission() -> void:
	if completed or observation_phase_active:
		return
	hud.hide_phase_summary()
	get_tree().paused = true
	upgrade_tree.open_tree()


func get_debug_snapshot() -> Dictionary:
	return {
		"elapsed": elapsed_time,
		"data": progression.observation_data,
		"successes": progression.success_count,
		"upgrade_level": progression.upgrade_level,
		"purchased_nodes": progression.purchased_nodes.keys(),
		"meteor_count": meteor_layer.get_child_count(),
		"survey_summoned": survey.summoned_this_round,
		"survey_charge": survey.get_charge_progress(),
		"shower_state": events.shower_state,
		"canis_major_state": events.canis_major_state,
		"observation_round": observation_round,
		"observation_phase_active": observation_phase_active,
		"observation_phase_remaining": observation_phase_remaining,
		"completed": completed
	}
