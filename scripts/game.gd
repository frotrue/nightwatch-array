extends Node2D

const Balance = preload("res://scripts/game_balance.gd")
const SoundSynth = preload("res://scripts/sound_synth.gd")
const AUTOSAVE_INTERVAL_SECONDS := 60.0

@onready var starfield: Node2D = $Starfield
@onready var meteor_layer: Node2D = $MeteorLayer
@onready var effects: Node2D = $EffectsLayer
@onready var observer: Node2D = $ObservationController
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
var suppress_phase_transition: bool = false


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
	hud.tutorial_replay_requested.connect(_on_tutorial_replay_requested)
	upgrade_tree.tree_opened.connect(tutorial.notify_upgrade_tree_opened)
	upgrade_tree.tree_closed.connect(_on_upgrade_tree_closed)
	observer.setup(meteor_layer, progression, hud)
	spawner.setup(meteor_layer, progression)
	events.setup(spawner, progression)

	spawner.meteor_spawned.connect(_on_meteor_spawned)
	spawner.rare_spawned.connect(_on_rare_spawned)
	progression.upgrade_purchased.connect(_on_upgrade_purchased)
	events.banner_requested.connect(_on_event_banner)
	events.sky_activity_changed.connect(_on_sky_activity_changed)
	events.forecast_requested.connect(_on_shower_forecast_requested)

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
	hud.hide_end()
	hud.hide_phase_summary()
	hud.reset_tutorial()
	hud.set_runtime(0.0)
	starfield.set_activity(0.0)
	_begin_observation_phase()


func reset_run() -> void:
	completed = false
	_close_upgrade_tree_without_transition()
	get_tree().paused = false
	observer.reset()
	effects.reset()
	events.reset()
	spawner.reset()
	progression.reset()
	hud.hide_end()
	hud.hide_phase_summary()
	hud.reset_tutorial()
	start_run()
	_autosave_active_slot()
	hud.show_banner(tr("BANNER_RESET"), Color("9bcde5"), 2.0)


func _process(delta: float) -> void:
	if completed or not observation_phase_active:
		return
	elapsed_time += delta
	observation_phase_remaining = maxf(0.0, observation_phase_remaining - delta)
	hud.set_runtime(elapsed_time)
	hud.set_observation_phase(observation_round, observation_phase_remaining)
	if active_save_slot > 0:
		autosave_elapsed += delta
		if autosave_elapsed >= AUTOSAVE_INTERVAL_SECONDS:
			autosave_elapsed = fmod(autosave_elapsed, AUTOSAVE_INTERVAL_SECONDS)
			_autosave_active_slot()
	if observation_phase_remaining <= 0.0 and not events.final_started and events.shower_state == "idle":
		_end_observation_phase()


func _observation_duration() -> float:
	return progression.get_observation_duration()


func _begin_observation_phase(advance_round: bool = false, remaining_override: float = -1.0, resume_game: bool = false) -> void:
	if advance_round:
		observation_round += 1
	var duration := _observation_duration()
	observation_phase_duration = duration
	observation_phase_remaining = duration if remaining_override < 0.0 else clampf(remaining_override, 0.05, duration)
	observation_phase_active = true
	phase_start_successes = progression.success_count
	phase_start_manual_successes = progression.manual_successes
	phase_start_automatic_successes = progression.automatic_successes
	phase_start_total_data = progression.total_data_earned
	upgrade_tree.clear_intermission_context()
	hud.hide_phase_summary()
	hud.set_observation_phase(observation_round, observation_phase_remaining)
	spawner.start_spawning()
	events.start()
	events.run_time = elapsed_time
	spawner.refresh_active_features()
	if resume_game:
		get_tree().paused = false


func _end_observation_phase() -> void:
	if completed or not observation_phase_active:
		return
	observation_phase_active = false
	observation_phase_remaining = 0.0
	observer.reset()
	effects.reset()
	events.reset()
	spawner.reset()
	starfield.set_activity(progression.get_progression_ratio() * 0.16)
	hud.set_upgrade_phase(observation_round)
	var next_round := observation_round + 1
	var next_duration := int(_observation_duration())
	upgrade_tree.set_intermission_context(next_round, next_duration)
	var observations := maxi(0, progression.success_count - phase_start_successes)
	var manual_observations := maxi(0, progression.manual_successes - phase_start_manual_successes)
	var automatic_observations := maxi(0, progression.automatic_successes - phase_start_automatic_successes)
	var data_earned := maxi(0, int(round(progression.total_data_earned - phase_start_total_data)))
	_autosave_active_slot()
	get_tree().paused = true
	hud.show_phase_summary(
		observation_round,
		int(round(observation_phase_duration)),
		data_earned,
		observations,
		manual_observations,
		automatic_observations,
		next_duration
	)


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
			hud.show_banner(tr("BANNER_DEBUG_DATA"), Color("d8c6ff"), 1.2)
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
		effects.spawn_incoming(meteor.global_position, meteor.velocity, meteor.get_visual_color())


func _on_meteor_observed(meteor, reward: float, multiplier: float, was_manual: bool, quality_grade: String) -> void:
	observer.release_target(meteor)
	var final_reward: float = progression.add_observation(reward, was_manual, multiplier)
	effects.spawn_success(meteor.global_position, final_reward, meteor.get_visual_color(), multiplier)
	sound.play_success(multiplier)
	if progression.has_upgrade("perfect_observation") and was_manual and quality_grade in ["EXCELLENT", "PERFECT"]:
		hud.show_banner(tr("BANNER_QUALITY") % [tr("QUALITY_%s" % quality_grade), multiplier], meteor.get_visual_color(), 1.5)
	if progression.success_count == 1:
		hud.mark_first_success()
	tutorial.notify_observation_completed()
	if meteor.is_major():
		_complete_prototype(true)


func _on_meteor_expired(meteor, was_major: bool) -> void:
	observer.release_target(meteor)
	if was_major and not completed:
		_complete_prototype(false)


func _on_upgrade_purchased(definition: Dictionary) -> void:
	tutorial.notify_upgrade_purchased()
	spawner.refresh_active_features()
	if not observation_phase_active:
		upgrade_tree.set_intermission_context(observation_round + 1, int(_observation_duration()))
	effects.spawn_upgrade_pulse()
	sound.play_upgrade()
	hud.show_banner(tr("BANNER_SYSTEM_ONLINE") % _upgrade_name(definition), Color("80e6d2"), 2.4)
	starfield.set_activity(progression.get_progression_ratio() * 0.16)
	_autosave_active_slot()


func _on_rare_spawned(type_id: String) -> void:
	if type_id == "major":
		return
	var prefix_key := "BANNER_SECONDARY_ALERT" if progression.has_upgrade("rare_detection") and progression.has_upgrade("secondary_camera") else "BANNER_UNUSUAL_SIGNATURE"
	hud.show_banner("%s  •  %s" % [tr(prefix_key), tr("METEOR_%s" % type_id.to_upper())], Color("ffc58c"), 2.0)
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
		hud.show_save_feedback(tr("SAVE_SUCCESS") % slot, Color("7ee9dc"))
		sound.play_upgrade()
	else:
		hud.show_save_feedback(tr("SAVE_FAILURE") % slot, Color("ff9a86"))


func _on_load_slot_requested(slot: int) -> void:
	var data: Dictionary = save_games.load_slot(slot)
	if data.is_empty():
		hud.show_save_feedback(tr("LOAD_FAILURE") % slot, Color("ff9a86"))
		return
	active_save_slot = slot
	autosave_elapsed = 0.0
	hud.set_active_save_slot(slot)
	_apply_save_data(data)
	hud.close_settings()
	hud.show_banner(tr("BANNER_SLOT_LOADED") % slot, Color("80e6d2"), 2.2)
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
		hud.show_banner(tr("BANNER_SLOT_LOADED") % slot, Color("80e6d2"), 2.2)
	_start_tutorial_after_slot_if_needed()


func _on_new_game_slot_requested(slot: int) -> void:
	var summary: Dictionary = save_games.get_slot_summary(slot)
	if bool(summary.get("exists", false)):
		return
	_on_startup_slot_selected(slot)
	hud.close_settings()


func _start_fresh_slot() -> void:
	completed = false
	_close_upgrade_tree_without_transition()
	observer.reset()
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
	hud.show_banner(tr("AUTOSAVE_FAILURE") % active_save_slot, Color("ff9a86"), 2.0)
	return false


func _on_tutorial_replay_requested() -> void:
	hud.close_settings()
	tutorial.start_tutorial()


func _build_save_data() -> Dictionary:
	return {
		"elapsed_time": elapsed_time,
		"observation_round": observation_round,
		"observation_phase_active": observation_phase_active,
		"observation_phase_remaining": observation_phase_remaining,
		"observation_phase_duration": observation_phase_duration,
		"phase_start_successes": phase_start_successes,
		"phase_start_manual_successes": phase_start_manual_successes,
		"phase_start_automatic_successes": phase_start_automatic_successes,
		"phase_start_total_data": phase_start_total_data,
		"progression": progression.get_save_data(),
	}


func _apply_save_data(data: Dictionary) -> void:
	_close_upgrade_tree_without_transition()
	observer.reset()
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
		observation_phase_duration = maxf(0.05, float(data.get("observation_phase_duration", _observation_duration())))
		phase_start_successes = maxi(0, int(data.get("phase_start_successes", progression.success_count)))
		phase_start_manual_successes = maxi(0, int(data.get("phase_start_manual_successes", progression.manual_successes)))
		phase_start_automatic_successes = maxi(0, int(data.get("phase_start_automatic_successes", progression.automatic_successes)))
		phase_start_total_data = maxf(0.0, float(data.get("phase_start_total_data", progression.total_data_earned)))
	else:
		observation_phase_active = false
		observation_phase_remaining = 0.0
		hud.set_upgrade_phase(observation_round)
		var next_round := observation_round + 1
		upgrade_tree.set_intermission_context(next_round, int(_observation_duration()))
		call_deferred("_resume_upgrade_intermission")


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
