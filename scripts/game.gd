extends Node2D

const UITheme = preload("res://scripts/ui_theme.gd")
const Balance = preload("res://scripts/game_balance.gd")
const SoundSynth = preload("res://scripts/sound_synth.gd")
const AUTOSAVE_INTERVAL_SECONDS := 60.0
const HITSTOP_TIME_SCALE := 0.06
const HITSTOP_COOLDOWN_MSEC := 400
const COMBO_STRENGTH_STEP := 0.045
const IMPACT_TARGET_TYPES := ["fireball", "major"]
const FLASHLESS_METEOR_TYPES := ["common", "fast"]
const FRAGMENT_PIECE_FEEDBACK_SCALE := 0.50
# Every manual observation gets a directional kick; the rumble and the freeze
# are reserved for rare fireballs and the Canis Major event so the game's repeated core
# action never becomes a chain of camera motion and freezes.
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
@onready var host_stars: Node2D = $HostStarLayer
@onready var galactic_phenomena: Node2D = $GalacticPhenomenaLayer
@onready var meteor_layer: Node2D = $MeteorLayer
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
@onready var observation_view: Camera2D = $ObservationView

var sound: Node
var elapsed_time: float = 0.0
var completed: bool = false
var catalogue_ending_seen: bool = false
var ending_final_watch_pending: bool = false
var catalogue_ending_debug_preview: bool = false
var catalogue_debug_previous_pause: bool = false
var catalogue_debug_previous_mouse_mode: int = Input.MOUSE_MODE_HIDDEN
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
var phase_started_with_complete_research: bool = false
var phase_had_shower: bool = false
var phase_resumed_from_save: bool = false
var last_clean_round_result: Dictionary = {}
var best_round_rate: float = 0.0
var suppress_phase_transition: bool = false
var hitstop_active: bool = false
var hitstop_cooldown_until_msec: int = 0
var galactic_pullback_seen: bool = false


func _ready() -> void:
	print("NIGHTWATCH_ENGINE_VERSION: ", Engine.get_version_info())
	sound = SoundSynth.new()
	sound.name = "SoundSynth"
	add_child(sound)

	hud.bind_progression(progression)
	hud.bind_settings(settings)
	hud.bind_save_games(save_games)
	upgrade_tree.bind_progression(progression)
	upgrade_tree.bind_settings(settings)
	tutorial_auto_start_after_slot = startup_slot_prompt_enabled and tutorial.auto_start_enabled
	if startup_slot_prompt_enabled:
		tutorial.auto_start_enabled = false
	tutorial.setup(settings, progression)
	settings.language_changed.connect(_on_language_changed)
	hud.catalogue_finish_requested.connect(_on_catalogue_finish_requested)
	hud.catalogue_continue_requested.connect(_on_catalogue_continue_requested)
	hud.catalogue_debug_preview_close_requested.connect(_close_catalogue_ending_debug_preview)
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
	host_stars.setup(progression, observation_view)
	galactic_phenomena.setup(progression, observation_view, meteor_layer)
	sky_contacts.setup(meteor_layer, progression, observation_view)
	spawner.setup(meteor_layer, progression, observation_view)
	survey.setup(progression, spawner, meteor_layer, observation_view, [host_stars, galactic_phenomena])
	observer.setup(meteor_layer, progression, hud, survey, observation_view, [host_stars, galactic_phenomena])
	events.setup(spawner, progression, observation_view)

	spawner.meteor_spawned.connect(_on_meteor_spawned)
	host_stars.transit_confirmed.connect(_on_transit_confirmed)
	host_stars.host_harvested.connect(_on_host_harvested)
	host_stars.transit_missed.connect(_on_transit_missed)
	galactic_phenomena.phenomenon_observed.connect(_on_galactic_phenomenon_observed)
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
	elapsed_time = 0.0
	autosave_elapsed = 0.0
	completed = false
	catalogue_ending_seen = false
	ending_final_watch_pending = false
	catalogue_ending_debug_preview = false
	phase_started_with_complete_research = false
	observation_round = 1
	last_clean_round_result.clear()
	best_round_rate = 0.0
	galactic_pullback_seen = false
	hud.hide_end()
	hud.hide_phase_summary()
	hud.reset_tutorial()
	hud.set_runtime(0.0)
	starfield.set_activity(0.0)
	_sync_galactic_systems()
	starfield.set_galactic_mode(progression.galaxy_unlocked())
	upgrade_tree.configure_galactic_state(progression.galaxy_unlocked(), galactic_pullback_seen)
	_sync_catalogue_ending_presentation()
	_begin_observation_phase()


func reset_run() -> void:
	completed = false
	_release_hitstop()
	hitstop_cooldown_until_msec = 0
	_close_upgrade_tree_without_transition()
	get_tree().paused = false
	observer.reset()
	sky_contacts.reset()
	survey.reset()
	effects.reset()
	events.reset()
	spawner.reset()
	host_stars.reset()
	galactic_phenomena.reset()
	progression.reset()
	hud.hide_end()
	hud.hide_phase_summary()
	hud.reset_tutorial()
	start_run()
	_autosave_active_slot()
	hud.show_banner(tr("BANNER_RESET"), UITheme.BANNER_SUB, 2.0)


func _process(delta: float) -> void:
	if completed or not observation_phase_active:
		return
	# Hitstop scales the engine clock. The round is the measuring stick for
	# Data/min, so its countdown is converted back to real seconds and a freeze
	# cannot quietly buy the player extra observation time.
	var real_delta := delta / maxf(Engine.time_scale, 0.001)
	elapsed_time += real_delta
	observation_phase_remaining = maxf(0.0, observation_phase_remaining - real_delta)
	spawner.set_phase_time_remaining(observation_phase_remaining)
	hud.set_runtime(elapsed_time)
	hud.set_observation_phase(observation_round, observation_phase_remaining, observation_phase_duration)
	progression.update_manual_combo(real_delta)
	survey.advance_time(real_delta)
	host_stars.advance_time(real_delta)
	galactic_phenomena.advance_time(real_delta)
	if active_save_slot > 0:
		autosave_elapsed += real_delta
		if autosave_elapsed >= AUTOSAVE_INTERVAL_SECONDS:
			autosave_elapsed = fmod(autosave_elapsed, AUTOSAVE_INTERVAL_SECONDS)
			_autosave_active_slot()
	if observation_phase_remaining <= 0.0:
		_end_observation_phase()


func _observation_duration() -> float:
	return progression.get_observation_duration()


func _begin_observation_phase(advance_round: bool = false, remaining_override: float = -1.0, resume_game: bool = false) -> void:
	if advance_round:
		observation_round += 1
	var duration := _observation_duration()
	observation_phase_duration = duration
	observation_phase_remaining = duration if remaining_override < 0.0 else clampf(remaining_override, 0.05, duration)
	spawner.set_phase_time_remaining(observation_phase_remaining)
	observation_phase_active = true
	progression.reset_manual_combo()
	sound.reset_streak_audio()
	phase_start_successes = progression.success_count
	phase_start_manual_successes = progression.manual_successes
	phase_start_automatic_successes = progression.automatic_successes
	phase_start_total_data = progression.total_data_earned
	phase_start_upgrade_signature = _current_build_signature()
	phase_started_with_complete_research = progression.is_research_complete()
	phase_had_shower = false
	phase_resumed_from_save = false
	upgrade_tree.clear_intermission_context()
	hud.hide_phase_summary()
	hud.set_observation_phase(observation_round, observation_phase_remaining, observation_phase_duration)
	spawner.start_spawning()
	host_stars.begin_round()
	galactic_phenomena.begin_round()
	survey.begin_round(observation_round)
	events.run_time = elapsed_time
	events.start()
	# Canis Major remains a recurrent round event. Catalogue completion is handled
	# only after a full-research observation, its summary, and the completed chart.
	var pending_leonid_count := _try_start_leonid_storm()
	if pending_leonid_count > 0:
		hud.show_banner(tr("BANNER_LEONID_STORM") % pending_leonid_count, UITheme.INK_MAX, 1.8)
	spawner.refresh_active_features()
	if resume_game:
		get_tree().paused = false


func _end_observation_phase() -> void:
	if completed or not observation_phase_active:
		return
	host_stars.end_round()
	galactic_phenomena.end_round()
	progression.reset_manual_combo()
	sound.reset_streak_audio()
	var result := _build_round_result()
	var previous_result := last_clean_round_result.duplicate(true)
	var build_changed := bool(result.get("build_changed", false))
	result["systems_since_baseline"] = _systems_since_baseline(result, previous_result)
	var comparison_state := "comparison"
	if build_changed:
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
	if catalogue_ending_seen or not _catalogue_record_complete():
		ending_final_watch_pending = false
	else:
		# A mixed-build round can never seal the record. The next round must begin
		# with the complete research array before the ending becomes eligible.
		ending_final_watch_pending = not phase_started_with_complete_research
	_sync_catalogue_ending_presentation()
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
	hud.show_phase_summary(
		result,
		previous_result,
		comparison_state,
		new_best
	)


func _build_round_result() -> Dictionary:
	var current_signature := _current_build_signature()
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
		"build_changed": current_signature != phase_start_upgrade_signature,
		"build_signature": current_signature,
	}


func _current_build_signature() -> Array[String]:
	var signature: Array[String] = []
	for node_variant in progression.purchased_nodes.keys():
		signature.append(String(node_variant))
	signature.sort()
	return signature


func _catalogue_record_complete() -> bool:
	return progression.is_research_complete() and galactic_phenomena.is_record_complete()


func _catalogue_ending_ready() -> bool:
	return (
		not catalogue_ending_seen
		and not ending_final_watch_pending
		and not observation_phase_active
		and _catalogue_record_complete()
	)


func _refresh_catalogue_ending_requirement() -> void:
	if catalogue_ending_seen or not _catalogue_record_complete():
		ending_final_watch_pending = false
	elif observation_phase_active:
		# A final phenomenon found during a round that began with the full array
		# may use that same round. Research installed after the start may not.
		ending_final_watch_pending = not phase_started_with_complete_research
	else:
		ending_final_watch_pending = true
	_sync_catalogue_ending_presentation()


func _sync_catalogue_ending_presentation() -> void:
	upgrade_tree.configure_catalogue_ending_state(
		ending_final_watch_pending,
		_catalogue_ending_ready()
	)


func _show_catalogue_ending() -> void:
	if completed or not _catalogue_ending_ready():
		return
	catalogue_ending_debug_preview = false
	completed = true
	_release_hitstop()
	get_tree().paused = true
	sound.play_complete()
	hud.show_catalogue_ending(_catalogue_stats_text())
	# Save the unseen, ready state. If the application closes on this screen,
	# loading returns to the completed chart and presents the ending again.
	_autosave_active_slot()


func _on_catalogue_continue_requested() -> void:
	if not completed or not hud.is_end_open():
		return
	if catalogue_ending_debug_preview:
		_close_catalogue_ending_debug_preview()
		return
	catalogue_ending_seen = true
	ending_final_watch_pending = false
	_sync_catalogue_ending_presentation()
	# Persist the acknowledgement before leaving the one-time ending. A failed
	# save keeps the record on screen instead of letting the player believe the
	# choice was archived when it was not.
	if not _autosave_active_slot():
		catalogue_ending_seen = false
		_sync_catalogue_ending_presentation()
		hud.show_catalogue_save_failure()
		return
	completed = false
	hud.hide_end()
	_begin_observation_phase(true, -1.0, true)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	# This second save advances the persisted phase too. If it fails, the first
	# save still guarantees that the acknowledged ending will not replay.
	_autosave_active_slot()


func _on_catalogue_finish_requested() -> void:
	if not completed or not hud.is_end_open():
		return
	if catalogue_ending_debug_preview:
		_close_catalogue_ending_debug_preview()
		return
	catalogue_ending_seen = true
	ending_final_watch_pending = false
	_sync_catalogue_ending_presentation()
	if not _autosave_active_slot():
		catalogue_ending_seen = false
		_sync_catalogue_ending_presentation()
		hud.show_catalogue_save_failure()
		return
	completed = false
	hud.hide_end()
	# Startup slots are the project's title/records surface. Open them from an
	# unpaused tree so the HUD owns the pause and later slot selection resumes.
	get_tree().paused = false
	hud.open_startup_slots()


func _catalogue_stats_text() -> String:
	var active_seconds := maxi(0, int(floor(elapsed_time)))
	return "\n".join([
		tr("END_ACTIVE_TIME") % [active_seconds / 60, active_seconds % 60],
		tr("END_ROUNDS") % observation_round,
		tr("END_OBSERVATIONS") % progression.success_count,
		tr("END_MANUAL_AUTO") % [progression.manual_successes, progression.automatic_successes],
		tr("END_TOTAL_DATA") % int(round(progression.total_data_earned)),
		tr("END_RESEARCH") % [progression.upgrade_level, Balance.research_node_count()],
		tr("END_PHENOMENA") % [
			galactic_phenomena.get_completed_record_count(),
			galactic_phenomena.get_record_target_count(),
		],
	])


func _show_catalogue_ending_debug_preview() -> void:
	if completed:
		return
	catalogue_ending_debug_preview = true
	catalogue_debug_previous_pause = get_tree().paused
	catalogue_debug_previous_mouse_mode = Input.mouse_mode
	completed = true
	_release_hitstop()
	get_tree().paused = true
	sound.play_complete()
	hud.show_catalogue_ending(_catalogue_stats_text(), true)


func _close_catalogue_ending_debug_preview() -> void:
	if not catalogue_ending_debug_preview:
		return
	catalogue_ending_debug_preview = false
	completed = false
	hud.hide_end()
	get_tree().paused = catalogue_debug_previous_pause
	Input.mouse_mode = catalogue_debug_previous_mouse_mode


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
	if suppress_phase_transition or completed or observation_phase_active:
		return
	if _catalogue_ending_ready():
		_show_catalogue_ending()
		return
	_begin_observation_phase(true, -1.0, true)


func _close_upgrade_tree_without_transition() -> void:
	suppress_phase_transition = true
	upgrade_tree.close_tree()
	suppress_phase_transition = false


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if completed:
		if (
			catalogue_ending_debug_preview
			and event.ctrl_pressed
			and event.shift_pressed
			and event.keycode == KEY_E
		):
			_close_catalogue_ending_debug_preview()
		get_viewport().set_input_as_handled()
		return
	if hud.is_phase_summary_open():
		if event.keycode in [KEY_U, KEY_ENTER, KEY_SPACE]:
			_on_phase_summary_continue_requested()
			get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_F9:
		hud.toggle_debug()
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_U:
		upgrade_tree.open_tree()
		get_viewport().set_input_as_handled()
		return
	if not (event.ctrl_pressed and event.shift_pressed):
		return
	match event.keycode:
		KEY_D:
			progression.add_debug_data(100.0)
			hud.show_banner(tr("BANNER_DEBUG_DATA"), UITheme.INK_MID, 1.2)
		KEY_N:
			var available: Array[String] = progression.get_available_nodes()
			if not available.is_empty():
				progression.debug_purchase_node(available[0])
		KEY_A:
			progression.debug_purchase_all()
		KEY_M:
			spawner.spawn_meteor("common")
		KEY_R:
			spawner.spawn_meteor("fireball")
		KEY_S:
			events.trigger_shower()
		KEY_F:
			events.trigger_canis_major_warning()
		KEY_E:
			_show_catalogue_ending_debug_preview()
		KEY_BACKSPACE:
			reset_run()
		_:
			return
	get_viewport().set_input_as_handled()


func _on_meteor_spawned(meteor) -> void:
	meteor.observed.connect(_on_meteor_observed)
	meteor.expired.connect(_on_meteor_expired)
	galactic_phenomena.register_meteor(meteor)
	if progression.has_upgrade("wide_field"):
		# The edge marker is an instrument annotation, not the object, so it takes
		# red light. The meteor keeps its own colour: the sky is what is being
		# observed and the instrument is what does the observing.
		var marker_ink: Color = UITheme.INK_MAX if meteor.type_id in ["fireball", "major"] else UITheme.ACCENT_PIP
		effects.spawn_incoming(meteor.global_position, meteor.velocity, marker_ink)


func _on_meteor_observed(meteor, reward: float, multiplier: float, was_manual: bool, quality_grade: String) -> void:
	observer.release_target(meteor)
	# Observation technique belongs to feedback and the end-of-run manual stat;
	# research value growth belongs only to the economy. Keeping the two values
	# separate prevents an x2 research leaf from changing how the same hit feels.
	var intrinsic_multiplier := multiplier
	# The emitting target marks itself inactive immediately before this signal;
	# count it explicitly so a three-contact finish means the player saw three.
	var active_target_count := 1
	for candidate in meteor_layer.get_children():
		if candidate.has_method("can_be_tracked") and candidate.can_be_tracked():
			active_target_count += 1
	var research_multiplier: float = progression.get_observation_value_multiplier(
		String(meteor.type_id), active_target_count
	)
	var reference_result: Dictionary = host_stars.record_meteor_observation(meteor.global_position)
	var reference_multiplier := float(reference_result.get("multiplier", 1.0))
	reward = round(reward * reference_multiplier * research_multiplier)
	var final_reward: float = progression.add_observation(reward, was_manual, intrinsic_multiplier)
	var is_proc_meteor := (
		bool(meteor.get_meta("gemini_echo", false))
		or bool(meteor.get_meta("leonid_storm", false))
		or bool(meteor.get_meta("perseid_outburst", false))
		or bool(meteor.get_meta("polar_summoned", false))
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
	# Base value is target identity, not economy. Quality and the live manual
	# chain remain explicit feedback inputs inside _observation_strength.
	var strength := _observation_strength(float(meteor.base_value), was_manual, quality_grade)
	var meteor_type_id := String(meteor.type_id)
	var meteor_screen_scale: float = observation_view.meteor_screen_scale()
	effects.spawn_success(
		meteor.global_position,
		final_reward,
		meteor.get_visual_color(),
		intrinsic_multiplier * reference_multiplier,
		strength,
		quality_grade,
		hud.get_data_anchor(),
		_meteor_flash_scale(meteor_type_id)
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
	# The audio channels split on the same line. Shake and hitstop part ways
	# here: shake is view motion the player reads as accumulation, so a long
	# manual chain is allowed to earn it on any target. Hitstop halts the game,
	# and a chain of halts is the freeze this split was made to end, so it stays
	# with punctuation targets.
	if was_manual:
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
		hud.show_banner(tr("BANNER_QUALITY") % [tr("QUALITY_%s" % quality_grade), intrinsic_multiplier], meteor.get_visual_color(), 1.5)
	if echo_spawn_count > 0:
		hud.show_banner(tr("BANNER_GEMINI_ECHO") % echo_spawn_count, UITheme.INK_MAX, 1.5)
	if leonid_spawn_count > 0:
		hud.show_banner(tr("BANNER_LEONID_STORM") % leonid_spawn_count, UITheme.INK_MAX, 1.8)
	if progression.success_count == 1:
		hud.mark_first_success()
	tutorial.notify_observation_completed()


func _on_transit_confirmed(star, confirmation_count: int, _projected_reward: float, multiplier: float, was_manual: bool, _quality_grade: String) -> void:
	observer.release_target(star)
	progression.record_transit_confirmation(was_manual, multiplier)
	if sound != null:
		sound.play_success(multiplier, confirmation_count, 0.46)
	if progression.success_count == 1:
		hud.mark_first_success()
	tutorial.notify_observation_completed()


func _on_host_harvested(star, reward: float, multiplier: float, _was_manual: bool, quality_grade: String, confirmation_count: int) -> void:
	observer.release_target(star)
	var transit_multiplier: float = progression.get_transit_value_multiplier()
	var final_reward: float = progression.add_transit_harvest(round(reward * transit_multiplier))
	effects.spawn_success(
		star.global_position,
		final_reward,
		star.get_visual_color(),
		multiplier * transit_multiplier,
		1.0,
		quality_grade,
		hud.get_data_anchor()
	)
	if sound != null:
		sound.play_success(multiplier, confirmation_count, minf(1.0, 0.55 + float(confirmation_count) * 0.15))


func _on_transit_missed(star_id: int) -> void:
	var missed_star = host_stars.get_host_by_id(star_id)
	if missed_star != null:
		observer.release_target(missed_star)


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
	# A single common stays quiet; an unbroken chain is what earns the screen.
	# A 14-point common starts at 0.10, so twelve links at 0.045 carry it to
	# 0.64 and cross the shake floor on the ninth. Persistence reaches the
	# screen on its own, and a Perfect grade gets there in about half as many.
	return minf(1.0, strength + minf(float(progression.manual_combo_count), 12.0) * COMBO_STRENGTH_STEP)


func _meteor_flash_scale(type_id: String) -> float:
	if progression.galaxy_unlocked() and type_id in FLASHLESS_METEOR_TYPES:
		return 0.0
	return observation_view.meteor_screen_scale() * _fragment_feedback_scale(type_id)


func _meteor_shake_scale(type_id: String) -> float:
	return observation_view.meteor_shake_scale() * _fragment_feedback_scale(type_id)


func _fragment_feedback_scale(type_id: String) -> float:
	return FRAGMENT_PIECE_FEEDBACK_SCALE if type_id == "fragment_piece" else 1.0


func _apply_hitstop(duration: float) -> void:
	if hitstop_active or Time.get_ticks_msec() < hitstop_cooldown_until_msec:
		return
	hitstop_active = true
	Engine.time_scale = HITSTOP_TIME_SCALE
	# Real-time timer. A scaled one would stretch a 70 ms freeze past a second.
	get_tree().create_timer(duration, true, false, true).timeout.connect(_release_hitstop)


func _release_hitstop() -> void:
	if hitstop_active:
		hitstop_cooldown_until_msec = Time.get_ticks_msec() + HITSTOP_COOLDOWN_MSEC
	hitstop_active = false
	Engine.time_scale = 1.0


func _on_packet_landed(amount: float) -> void:
	hud.pulse_data_counter(amount)


func _on_meteor_expired(meteor, _was_major: bool) -> void:
	observer.release_target(meteor)


func _on_galactic_phenomenon_observed(target, reward: float, multiplier: float, quality_grade: String) -> void:
	observer.release_target(target)
	effects.spawn_success(
		target.global_position,
		reward,
		target.get_visual_color(),
		multiplier,
		0.72,
		quality_grade,
		hud.get_data_anchor(),
		0.0
	)
	sound.play_success(multiplier, progression.manual_combo_count, 0.72)
	hud.show_banner(tr("BANNER_GALACTIC_OBSERVATION"), UITheme.BANNER_TITLE, 2.2)
	_refresh_catalogue_ending_requirement()
	if _catalogue_record_complete():
		_autosave_active_slot()


func _on_upgrade_purchased(definition: Dictionary) -> void:
	tutorial.notify_upgrade_purchased()
	sky_contacts.refresh_dishes()
	spawner.refresh_active_features()
	if not observation_phase_active:
		upgrade_tree.set_intermission_context(observation_round + 1, int(_observation_duration()))
	effects.spawn_upgrade_pulse()
	sound.play_upgrade()
	_sync_galactic_systems()
	if String(definition.id) == "galactic_reference_frame":
		hud.show_banner(tr("BANNER_GALACTIC_FRAME"), UITheme.INK_MAX, 3.2)
		upgrade_tree.begin_galactic_pullback()
	else:
		hud.show_banner(tr("BANNER_SYSTEM_ONLINE") % _upgrade_name(definition), UITheme.BANNER_TITLE, 2.4)
	starfield.set_activity(progression.get_progression_ratio() * 0.16)
	starfield.set_galactic_mode(progression.galaxy_unlocked())
	_refresh_catalogue_ending_requirement()
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


func _on_language_changed(_locale: String) -> void:
	if completed and hud.is_end_open():
		hud.refresh_catalogue_ending_text(_catalogue_stats_text())


func _upgrade_name(definition: Dictionary) -> String:
	return tr("UPGRADE_%s_NAME" % String(definition.id).to_upper())


func _on_save_slot_requested(slot: int) -> void:
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
	active_save_slot = slot
	autosave_elapsed = 0.0
	hud.set_active_save_slot(slot)
	_apply_save_data(data)
	hud.close_settings()
	hud.show_banner(tr("BANNER_SLOT_LOADED") % slot, UITheme.BANNER_TITLE, 2.2)
	sound.play_slot_confirm()


func _on_startup_slot_selected(slot: int) -> void:
	var summary: Dictionary = save_games.get_slot_summary(slot)
	var exists := bool(summary.get("exists", false))
	var valid := bool(summary.get("valid", false))
	if exists and not valid:
		return
	active_save_slot = slot
	autosave_elapsed = 0.0
	hud.set_active_save_slot(slot)
	if exists:
		var data: Dictionary = save_games.load_slot(slot)
		if data.is_empty():
			active_save_slot = 0
			hud.set_active_save_slot(0)
			return
		_apply_save_data(data)
	else:
		_start_fresh_slot()
		_autosave_active_slot()
	hud.close_startup_slots()
	if exists:
		hud.show_banner(tr("BANNER_SLOT_LOADED") % slot, UITheme.BANNER_TITLE, 2.2)
	_start_tutorial_after_slot_if_needed()


func _on_new_game_slot_requested(slot: int) -> void:
	var summary: Dictionary = save_games.get_slot_summary(slot)
	if bool(summary.get("exists", false)):
		return
	_on_startup_slot_selected(slot)
	hud.close_settings()


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
	completed = false
	_close_upgrade_tree_without_transition()
	observer.reset()
	sky_contacts.reset()
	survey.reset()
	effects.reset()
	events.reset()
	spawner.reset()
	host_stars.reset()
	galactic_phenomena.reset()
	progression.reset()
	hud.hide_end()
	hud.reset_tutorial()
	start_run()


func _start_tutorial_after_slot_if_needed() -> void:
	if tutorial_auto_start_after_slot and progression.success_count == 0 and not settings.is_tutorial_completed():
		tutorial.start_tutorial()
	tutorial_auto_start_after_slot = false


func _autosave_active_slot() -> bool:
	if active_save_slot < 1 or active_save_slot > 3:
		return false
	var error: Error = save_games.save_slot(active_save_slot, _build_save_data())
	if error == OK:
		hud.show_autosaved(active_save_slot)
		return true
	hud.show_banner(tr("AUTOSAVE_FAILURE") % active_save_slot, UITheme.ALERT, 2.0)
	return false


func _on_tutorial_replay_requested() -> void:
	hud.close_settings()
	tutorial.start_tutorial()


func _build_save_data() -> Dictionary:
	return {
		"rate_measurement_version": 1,
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
		"phase_started_with_complete_research": phase_started_with_complete_research,
		"phase_had_shower": phase_had_shower,
		"canis_major_spawned_this_round": spawner.canis_major_spawned_this_round,
		"last_clean_round_result": last_clean_round_result.duplicate(true),
		"best_round_rate": best_round_rate,
		"galactic_pullback_seen": galactic_pullback_seen,
		"catalogue_ending_seen": catalogue_ending_seen,
		"ending_final_watch_pending": ending_final_watch_pending,
		"host_stars": host_stars.get_save_data(),
		"galactic_phenomena": galactic_phenomena.get_save_data(),
		"progression": progression.get_save_data(),
	}


func _apply_save_data(data: Dictionary) -> void:
	sound.reset_streak_audio()
	_close_upgrade_tree_without_transition()
	observer.reset()
	sky_contacts.reset()
	survey.reset()
	effects.reset()
	events.reset()
	spawner.reset()
	host_stars.reset()
	galactic_phenomena.reset()
	completed = false
	catalogue_ending_seen = false
	ending_final_watch_pending = false
	catalogue_ending_debug_preview = false
	phase_started_with_complete_research = false
	elapsed_time = maxf(0.0, float(data.get("elapsed_time", 0.0)))
	autosave_elapsed = 0.0
	observation_round = maxi(1, int(data.get("observation_round", 1)))
	var progression_data = data.get("progression", {})
	progression.load_save_data(progression_data if progression_data is Dictionary else {})
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
	sky_contacts.refresh_dishes()
	hud.hide_end()
	hud.hide_phase_summary()
	hud.restore_tutorial(progression.success_count > 0)
	hud.set_runtime(elapsed_time)
	starfield.set_activity(progression.get_progression_ratio() * 0.16)
	_sync_galactic_systems()
	var host_data = data.get("host_stars", {})
	host_stars.load_save_data(host_data if host_data is Dictionary else {})
	var phenomena_data = data.get("galactic_phenomena", {})
	galactic_phenomena.load_save_data(phenomena_data if phenomena_data is Dictionary else {})
	catalogue_ending_seen = bool(data.get("catalogue_ending_seen", false))
	if catalogue_ending_seen or not _catalogue_record_complete():
		ending_final_watch_pending = false
	elif data.has("ending_final_watch_pending"):
		ending_final_watch_pending = bool(data.get("ending_final_watch_pending", true))
	else:
		# A completed save from the former open-night build receives one safe
		# full-array observation instead of opening an ending during load.
		ending_final_watch_pending = true
	starfield.set_galactic_mode(progression.galaxy_unlocked())
	var saved_phase_active := bool(data.get("observation_phase_active", true))
	if saved_phase_active:
		var saved_remaining := float(data.get(
			"observation_phase_remaining",
			_observation_duration()
		))
		_begin_observation_phase(false, saved_remaining)
		if bool(data.get("canis_major_spawned_this_round", false)):
			spawner.canis_major_spawned_this_round = true
			events.canis_major_state = "resolved"
			events.canis_major_timer = 0.0
		phase_start_successes = maxi(0, int(data.get("phase_start_successes", progression.success_count)))
		phase_start_manual_successes = maxi(0, int(data.get("phase_start_manual_successes", progression.manual_successes)))
		phase_start_automatic_successes = maxi(0, int(data.get("phase_start_automatic_successes", progression.automatic_successes)))
		phase_start_total_data = maxf(0.0, float(data.get("phase_start_total_data", progression.total_data_earned)))
		phase_start_upgrade_signature = _validated_signature(data.get("phase_start_upgrade_signature", _current_build_signature()))
		var saved_phase_had_complete_research := (
			phase_start_upgrade_signature.size() == Balance.research_node_count()
		)
		if data.has("phase_started_with_complete_research"):
			# Never let a stale or edited flag claim that a mixed-build round began
			# with the full array. The validated phase signature is authoritative.
			phase_started_with_complete_research = (
				bool(data.get("phase_started_with_complete_research", false))
				and saved_phase_had_complete_research
			)
		elif data.has("phase_start_upgrade_signature"):
			phase_started_with_complete_research = saved_phase_had_complete_research
		else:
			phase_started_with_complete_research = false
		phase_had_shower = bool(data.get("phase_had_shower", false))
		phase_resumed_from_save = true
	else:
		observation_phase_active = false
		observation_phase_remaining = 0.0
		phase_started_with_complete_research = false
		survey.end_round()
		hud.set_upgrade_phase(observation_round)
		var next_round := observation_round + 1
		upgrade_tree.set_intermission_context(next_round, int(_observation_duration()))
		call_deferred("_resume_upgrade_intermission")
	_sync_catalogue_ending_presentation()


func _sync_galactic_systems() -> void:
	observation_view.set_observation_span(progression.get_observation_span())
	host_stars.refresh_unlock_state()
	galactic_phenomena.refresh_unlock_state()


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
		"galactic_phenomena": galactic_phenomena.get_metrics(),
		"survey_summoned": survey.summoned_this_round,
		"survey_charge": survey.get_charge_progress(),
		"shower_state": events.shower_state,
		"canis_major_state": events.canis_major_state,
		"observation_round": observation_round,
		"observation_phase_active": observation_phase_active,
		"observation_phase_remaining": observation_phase_remaining,
		"completed": completed
	}
