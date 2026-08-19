extends Node2D

const Balance = preload("res://scripts/game_balance.gd")
const SoundSynth = preload("res://scripts/sound_synth.gd")

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
	tutorial.setup(settings, progression)
	settings.language_changed.connect(_on_language_changed)
	hud.restart_requested.connect(reset_run)
	hud.upgrade_tree_requested.connect(upgrade_tree.open_tree)
	hud.save_slot_requested.connect(_on_save_slot_requested)
	hud.load_slot_requested.connect(_on_load_slot_requested)
	hud.tutorial_replay_requested.connect(_on_tutorial_replay_requested)
	upgrade_tree.tree_opened.connect(tutorial.notify_upgrade_tree_opened)
	observer.setup(meteor_layer, progression, hud)
	spawner.setup(meteor_layer, progression)
	events.setup(spawner, progression)

	spawner.meteor_spawned.connect(_on_meteor_spawned)
	spawner.rare_spawned.connect(_on_rare_spawned)
	progression.upgrade_purchased.connect(_on_upgrade_purchased)
	events.banner_requested.connect(_on_event_banner)
	events.sky_activity_changed.connect(_on_sky_activity_changed)
	events.forecast_requested.connect(_on_shower_forecast_requested)

	start_run()


func start_run() -> void:
	elapsed_time = 0.0
	completed = false
	last_completion_success = false
	hud.hide_end()
	hud.reset_tutorial()
	hud.set_runtime(0.0)
	starfield.set_activity(0.0)
	spawner.start_spawning()
	events.start()


func reset_run() -> void:
	completed = false
	upgrade_tree.close_tree()
	observer.reset()
	effects.reset()
	events.reset()
	spawner.reset()
	progression.reset()
	hud.hide_end()
	hud.reset_tutorial()
	start_run()
	hud.show_banner(tr("BANNER_RESET"), Color("9bcde5"), 2.0)


func _process(delta: float) -> void:
	if completed:
		return
	elapsed_time += delta
	hud.set_runtime(elapsed_time)


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
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
	effects.spawn_upgrade_pulse()
	sound.play_upgrade()
	hud.show_banner(tr("BANNER_SYSTEM_ONLINE") % _upgrade_name(definition), Color("80e6d2"), 2.4)
	starfield.set_activity(progression.get_progression_ratio() * 0.16)


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
	events.finish_final()
	observer.release_target()
	if success:
		sound.play_complete()
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
		hud.show_save_feedback(tr("SAVE_SUCCESS") % slot, Color("7ee9dc"))
		sound.play_upgrade()
	else:
		hud.show_save_feedback(tr("SAVE_FAILURE") % slot, Color("ff9a86"))


func _on_load_slot_requested(slot: int) -> void:
	var data: Dictionary = save_games.load_slot(slot)
	if data.is_empty():
		hud.show_save_feedback(tr("LOAD_FAILURE") % slot, Color("ff9a86"))
		return
	_apply_save_data(data)
	hud.close_settings()
	hud.show_banner(tr("BANNER_SLOT_LOADED") % slot, Color("80e6d2"), 2.2)
	sound.play_upgrade()


func _on_tutorial_replay_requested() -> void:
	hud.close_settings()
	tutorial.start_tutorial()


func _build_save_data() -> Dictionary:
	return {
		"elapsed_time": elapsed_time,
		"progression": progression.get_save_data(),
	}


func _apply_save_data(data: Dictionary) -> void:
	upgrade_tree.close_tree()
	observer.reset()
	effects.reset()
	events.reset()
	spawner.reset()
	completed = false
	last_completion_success = false
	elapsed_time = maxf(0.0, float(data.get("elapsed_time", 0.0)))
	var progression_data = data.get("progression", {})
	progression.load_save_data(progression_data if progression_data is Dictionary else {})
	hud.hide_end()
	hud.restore_tutorial(progression.success_count > 0)
	hud.set_runtime(elapsed_time)
	starfield.set_activity(progression.get_progression_ratio() * 0.16)
	spawner.start_spawning()
	events.start()
	events.run_time = elapsed_time
	spawner.refresh_active_features()


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
		"completed": completed
	}
