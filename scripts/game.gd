extends Node2D

const UITheme = preload("res://scripts/ui_theme.gd")
const Balance = preload("res://scripts/game_balance.gd")
const SoundSynth = preload("res://scripts/sound_synth.gd")
const AUTOSAVE_INTERVAL_SECONDS := 60.0
# A manual chain expires on rhythm, not on a miss. Late rounds carry more
# meteors than anyone can reach, so resetting on every expiry would pin the
# streak near zero exactly when the array is at its busiest.
const STREAK_TIMEOUT := 2.6
const HITSTOP_TIME_SCALE := 0.06
# Every manual observation gets a directional kick; the rumble and the freeze
# are reserved for the top of the value range so a big hit still has something
# quieter to stand out against.
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
@onready var meteor_layer: Node2D = $MeteorLayer
@onready var effects: Node2D = $EffectsLayer
@onready var observer: Node2D = $ObservationController
@onready var sky_contacts: Node2D = $SkyContacts
@onready var progression: Node = $ProgressionController
@onready var spawner: Node = $MeteorSpawner
@onready var events: Node = $EventController
@onready var settings: Node = $GameSettings
@onready var save_games: Node = $SaveGameController
@onready var hud: CanvasLayer = $HUD
@onready var upgrade_tree: CanvasLayer = $UpgradeTree
@onready var tutorial: CanvasLayer = $Tutorial

var sound: Node
var elapsed_time: float = 0.0
var completed: bool = false
var last_completion_success: bool = false
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
var phase_had_shower: bool = false
var phase_resumed_from_save: bool = false
var last_clean_round_result: Dictionary = {}
var best_round_rate: float = 0.0
var suppress_phase_transition: bool = false
var success_streak: int = 0
var streak_remaining: float = 0.0
var hitstop_active: bool = false


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
	hud.restart_requested.connect(reset_run)
	hud.phase_summary_continue_requested.connect(_on_phase_summary_continue_requested)
	hud.save_slot_requested.connect(_on_save_slot_requested)
	hud.load_slot_requested.connect(_on_load_slot_requested)
	hud.startup_slot_selected.connect(_on_startup_slot_selected)
	hud.new_game_slot_requested.connect(_on_new_game_slot_requested)
	hud.reset_slot_requested.connect(_on_reset_slot_requested)
	hud.tutorial_replay_requested.connect(_on_tutorial_replay_requested)
	upgrade_tree.tree_opened.connect(tutorial.notify_upgrade_tree_opened)
	upgrade_tree.tree_closed.connect(_on_upgrade_tree_closed)
	sky_contacts.setup(meteor_layer, progression)
	observer.setup(meteor_layer, progression, hud)
	spawner.setup(meteor_layer, progression)
	events.setup(spawner, progression)

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
		start_run()
		_start_tutorial_after_slot_if_needed()
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
	last_completion_success = false
	observation_round = 1
	last_clean_round_result.clear()
	best_round_rate = 0.0
	hud.hide_end()
	hud.hide_phase_summary()
	hud.reset_tutorial()
	hud.set_runtime(0.0)
	starfield.set_activity(0.0)
	_begin_observation_phase()


func reset_run() -> void:
	completed = false
	_release_hitstop()
	_close_upgrade_tree_without_transition()
	get_tree().paused = false
	observer.reset()
	sky_contacts.reset()
	effects.reset()
	events.reset()
	spawner.reset()
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
	if streak_remaining > 0.0:
		streak_remaining = maxf(0.0, streak_remaining - real_delta)
		if streak_remaining <= 0.0:
			success_streak = 0
	if active_save_slot > 0:
		autosave_elapsed += real_delta
		if autosave_elapsed >= AUTOSAVE_INTERVAL_SECONDS:
			autosave_elapsed = fmod(autosave_elapsed, AUTOSAVE_INTERVAL_SECONDS)
			_autosave_active_slot()
	# The finale is the sole terminal exception to an observation window. Trigger
	# it here as well as in EventController so parent/child process order cannot
	# insert a research break at exactly 18:00.
	if elapsed_time >= Balance.FINAL_EVENT_TIME and not events.final_started:
		events.trigger_final()
	if observation_phase_remaining <= 0.0 and not events.final_started:
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
	success_streak = 0
	streak_remaining = 0.0
	phase_start_successes = progression.success_count
	phase_start_manual_successes = progression.manual_successes
	phase_start_automatic_successes = progression.automatic_successes
	phase_start_total_data = progression.total_data_earned
	phase_start_upgrade_signature = _current_build_signature()
	phase_had_shower = false
	phase_resumed_from_save = false
	upgrade_tree.clear_intermission_context()
	hud.hide_phase_summary()
	hud.set_observation_phase(observation_round, observation_phase_remaining, observation_phase_duration)
	spawner.start_spawning()
	events.run_time = elapsed_time
	events.start()
	var pending_leonid_count := _try_start_leonid_storm()
	if pending_leonid_count > 0:
		hud.show_banner(tr("BANNER_LEONID_STORM") % pending_leonid_count, UITheme.INK_MAX, 1.8)
	spawner.refresh_active_features()
	if resume_game:
		get_tree().paused = false


func _end_observation_phase() -> void:
	if completed or not observation_phase_active:
		return
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
	events.pause_for_intermission()
	observer.reset()
	sky_contacts.reset()
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
	_begin_observation_phase(true, -1.0, true)


func _close_upgrade_tree_without_transition() -> void:
	suppress_phase_transition = true
	upgrade_tree.close_tree()
	suppress_phase_transition = false


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
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
			if events.trigger_shower():
				sound.play_warning()
		KEY_F:
			events.trigger_final()
			sound.play_warning()
		KEY_BACKSPACE:
			reset_run()
		_:
			return
	get_viewport().set_input_as_handled()


func _on_meteor_spawned(meteor) -> void:
	meteor.observed.connect(_on_meteor_observed)
	meteor.expired.connect(_on_meteor_expired)
	if progression.has_upgrade("wide_field"):
		# The edge marker is an instrument annotation, not the object, so it takes
		# red light. The meteor keeps its own colour: the sky is what is being
		# observed and the instrument is what does the observing.
		var marker_ink: Color = UITheme.INK_MAX if meteor.type_id in ["fireball", "major"] else UITheme.ACCENT_PIP
		effects.spawn_incoming(meteor.global_position, meteor.velocity, marker_ink)


func _on_meteor_observed(meteor, reward: float, multiplier: float, was_manual: bool, quality_grade: String) -> void:
	observer.release_target(meteor)
	# The emitting target marks itself inactive immediately before this signal;
	# count it explicitly so a three-contact finish means the player saw three.
	var active_target_count := 1
	for candidate in meteor_layer.get_children():
		if candidate.has_method("can_be_tracked") and candidate.can_be_tracked():
			active_target_count += 1
	var research_multiplier: float = progression.get_observation_value_multiplier(
		String(meteor.type_id), active_target_count
	)
	reward = round(reward * research_multiplier)
	multiplier *= research_multiplier
	var final_reward: float = progression.add_observation(reward, was_manual, multiplier)
	var is_proc_meteor := (
		bool(meteor.get_meta("gemini_echo", false))
		or bool(meteor.get_meta("leonid_storm", false))
		or bool(meteor.get_meta("perseid_outburst", false))
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
	if was_manual:
		success_streak += 1
		streak_remaining = STREAK_TIMEOUT
	var strength := _observation_strength(final_reward, was_manual, quality_grade)
	effects.spawn_success(
		meteor.global_position,
		final_reward,
		meteor.get_visual_color(),
		multiplier,
		strength,
		quality_grade,
		hud.get_data_anchor()
	)
	if was_manual:
		sound.play_success(multiplier, success_streak, strength)
	else:
		# Automation gets its own quiet voice. Routing it through the manual
		# ladder would hold the chain at the top note for free and erase the one
		# signal that reports the player is still the one keeping rhythm.
		sound.play_automatic_tick()
	# View motion answers "you did that", so it is manual only. An automatic
	# completion is the payoff of a research decision made minutes ago, not an
	# action taken now, and once the array is built they fire continuously: a
	# permanently moving screen would leave a real hit nothing to stand against.
	# The audio channels split on the same line. Automatic strength peaks at 0.45
	# and could not reach either floor today, but that is arithmetic, not intent,
	# and it would break silently the first time either number is tuned.
	if was_manual:
		effects.add_kick(meteor.global_position, lerpf(KICK_MIN_PIXELS, KICK_MAX_PIXELS, strength))
		if strength >= SHAKE_STRENGTH_FLOOR:
			var weight := clampf((strength - SHAKE_STRENGTH_FLOOR) / (1.0 - SHAKE_STRENGTH_FLOOR), 0.0, 1.0)
			effects.add_shake(lerpf(SHAKE_TRAUMA_FLOOR, SHAKE_TRAUMA_CEILING, weight))
		if strength >= HITSTOP_STRENGTH_FLOOR:
			var freeze_weight := clampf((strength - HITSTOP_STRENGTH_FLOOR) / (1.0 - HITSTOP_STRENGTH_FLOOR), 0.0, 1.0)
			_apply_hitstop(lerpf(0.05, 0.11, freeze_weight))
	if progression.has_upgrade("perfect_observation") and was_manual and quality_grade in ["EXCELLENT", "PERFECT"]:
		hud.show_banner(tr("BANNER_QUALITY") % [tr("QUALITY_%s" % quality_grade), multiplier], meteor.get_visual_color(), 1.5)
	if echo_spawn_count > 0:
		hud.show_banner(tr("BANNER_GEMINI_ECHO") % echo_spawn_count, UITheme.INK_MAX, 1.5)
	if leonid_spawn_count > 0:
		hud.show_banner(tr("BANNER_LEONID_STORM") % leonid_spawn_count, UITheme.INK_MAX, 1.8)
	if progression.success_count == 1:
		hud.mark_first_success()
	tutorial.notify_observation_completed()
	if meteor.is_major():
		_complete_prototype(true)


func _try_start_leonid_storm() -> int:
	if not progression.leonid_storm_ready():
		return 0
	var storm_count: int = progression.get_leonid_storm_count()
	if not spawner.try_start_leonid_storm():
		return 0
	progression.consume_leonid_storm_charge()
	return storm_count


func _observation_strength(reward: float, was_manual: bool, quality_grade: String) -> float:
	# One scalar drives every feedback channel so they cannot drift apart. Log
	# scaled: a 14-point common sits near the floor and a 650-point major at the
	# ceiling, which is the spread the reward table actually has.
	var span: float = log(300.0) - log(10.0)
	var strength := clampf((log(maxf(reward, 10.0)) - log(10.0)) / span, 0.0, 1.0)
	if not was_manual:
		return strength * 0.45
	match quality_grade:
		"PERFECT":
			strength = minf(1.0, strength + 0.30)
		"EXCELLENT":
			strength = minf(1.0, strength + 0.15)
	return minf(1.0, strength + minf(float(success_streak), 12.0) * 0.015)


func _apply_hitstop(duration: float) -> void:
	if hitstop_active:
		return
	hitstop_active = true
	Engine.time_scale = HITSTOP_TIME_SCALE
	# Real-time timer. A scaled one would stretch a 70 ms freeze past a second.
	get_tree().create_timer(duration, true, false, true).timeout.connect(_release_hitstop)


func _release_hitstop() -> void:
	hitstop_active = false
	Engine.time_scale = 1.0


func _on_packet_landed(amount: float) -> void:
	hud.pulse_data_counter(amount)


func _on_meteor_expired(meteor, was_major: bool) -> void:
	observer.release_target(meteor)
	if was_major and not completed:
		_complete_prototype(false)


func _on_upgrade_purchased(definition: Dictionary) -> void:
	tutorial.notify_upgrade_purchased()
	sky_contacts.refresh_dishes()
	spawner.refresh_active_features()
	if not observation_phase_active:
		upgrade_tree.set_intermission_context(observation_round + 1, int(_observation_duration()))
	effects.spawn_upgrade_pulse()
	sound.play_upgrade()
	hud.show_banner(tr("BANNER_SYSTEM_ONLINE") % _upgrade_name(definition), UITheme.BANNER_TITLE, 2.4)
	starfield.set_activity(progression.get_progression_ratio() * 0.16)
	_autosave_active_slot()


func _on_rare_spawned(type_id: String) -> void:
	if type_id == "major":
		return
	var prefix_key := "BANNER_SECONDARY_ALERT" if progression.has_upgrade("rare_detection") and progression.has_upgrade("secondary_camera") else "BANNER_UNUSUAL_SIGNATURE"
	hud.show_banner("%s  •  %s" % [tr(prefix_key), tr("METEOR_%s" % type_id.to_upper())], UITheme.ACCENT_TEXT, 2.0)
	sound.play_warning()


func _on_event_banner(text_key: String, color: Color) -> void:
	hud.show_banner(tr(text_key), color, 2.5)
	if text_key in ["EVENT_SHOWER_INCOMING", "EVENT_ATMOSPHERIC_BLOOM"]:
		sound.play_warning()


func _on_sky_activity_changed(value: float) -> void:
	var progression_floor: float = progression.get_progression_ratio() * 0.16
	starfield.set_activity(maxf(value, progression_floor))


func _on_shower_forecast_requested(entry_points: Array) -> void:
	effects.spawn_forecast(entry_points)


func _on_shower_started() -> void:
	if observation_phase_active:
		phase_had_shower = true


func _complete_prototype(success: bool) -> void:
	if completed:
		return
	completed = true
	last_completion_success = success
	hud.hide_phase_summary()
	events.finish_final()
	observer.release_target()
	if success:
		sound.play_complete()
	_autosave_active_slot()
	hud.show_end(success, _build_end_stats())


func _on_language_changed(_locale: String) -> void:
	if completed:
		hud.show_end(last_completion_success, _build_end_stats())


func _build_end_stats() -> String:
	return "\n\n".join([
		tr("END_RUN_TIME") % [int(elapsed_time) / 60, int(elapsed_time) % 60],
		"\n".join([
			tr("END_OBSERVATIONS") % progression.success_count,
			tr("END_MANUAL_AUTO") % [progression.manual_successes, progression.automatic_successes],
			tr("END_TOTAL_DATA") % int(progression.total_data_earned),
			tr("END_SYSTEMS") % [progression.upgrade_level, Balance.UPGRADE_NODES.size()],
			tr("END_BEST_MULTIPLIER") % progression.best_multiplier
		])
	])


func _upgrade_name(definition: Dictionary) -> String:
	return tr("UPGRADE_%s_NAME" % String(definition.id).to_upper())


func _on_save_slot_requested(slot: int) -> void:
	var error: Error = save_games.save_slot(slot, _build_save_data())
	if error == OK:
		active_save_slot = slot
		autosave_elapsed = 0.0
		hud.set_active_save_slot(slot)
		hud.show_save_feedback(tr("SAVE_SUCCESS") % slot, UITheme.BANNER_TITLE)
		sound.play_upgrade()
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
	sound.play_upgrade()


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
	effects.reset()
	events.reset()
	spawner.reset()
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
		"phase_had_shower": phase_had_shower,
		"last_clean_round_result": last_clean_round_result.duplicate(true),
		"best_round_rate": best_round_rate,
		"progression": progression.get_save_data(),
	}


func _apply_save_data(data: Dictionary) -> void:
	_close_upgrade_tree_without_transition()
	observer.reset()
	sky_contacts.reset()
	effects.reset()
	events.reset()
	spawner.reset()
	completed = false
	last_completion_success = false
	elapsed_time = maxf(0.0, float(data.get("elapsed_time", 0.0)))
	autosave_elapsed = 0.0
	observation_round = maxi(1, int(data.get("observation_round", 1)))
	var progression_data = data.get("progression", {})
	progression.load_save_data(progression_data if progression_data is Dictionary else {})
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
	var saved_phase_active := bool(data.get("observation_phase_active", true))
	if saved_phase_active:
		var saved_remaining := float(data.get(
			"observation_phase_remaining",
			_observation_duration()
		))
		_begin_observation_phase(false, saved_remaining)
		phase_start_successes = maxi(0, int(data.get("phase_start_successes", progression.success_count)))
		phase_start_manual_successes = maxi(0, int(data.get("phase_start_manual_successes", progression.manual_successes)))
		phase_start_automatic_successes = maxi(0, int(data.get("phase_start_automatic_successes", progression.automatic_successes)))
		phase_start_total_data = maxf(0.0, float(data.get("phase_start_total_data", progression.total_data_earned)))
		phase_start_upgrade_signature = _validated_signature(data.get("phase_start_upgrade_signature", _current_build_signature()))
		phase_had_shower = bool(data.get("phase_had_shower", false))
		phase_resumed_from_save = true
	else:
		observation_phase_active = false
		observation_phase_remaining = 0.0
		hud.set_upgrade_phase(observation_round)
		var next_round := observation_round + 1
		upgrade_tree.set_intermission_context(next_round, int(_observation_duration()))
		call_deferred("_resume_upgrade_intermission")


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
		"shower_state": events.shower_state,
		"final_started": events.final_started,
		"observation_round": observation_round,
		"observation_phase_active": observation_phase_active,
		"observation_phase_remaining": observation_phase_remaining,
		"completed": completed
	}
