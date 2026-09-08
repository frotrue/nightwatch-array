extends SceneTree

const Fixtures = preload("res://tests/support/game_fixture.gd")
const MainScene = preload("res://scenes/main.tscn")
const GameSettings = preload("res://scripts/game_settings.gd")
const InputBindings = preload("res://scripts/game_input_bindings.gd")
var failures: Array[String] = []

class GuardedSettings:

	extends Fixtures.NoSettings

	var disk_load_attempts := 0

	func _load_locale() -> String:
		disk_load_attempts += 1
		return "ko"

	func _load_tutorial_completed() -> bool:
		disk_load_attempts += 1
		return false

	func _load_research_chart_rotation() -> float:
		disk_load_attempts += 1
		return 1.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game: Node = MainScene.instantiate()
	Fixtures.configure_before_ready(game)
	_check(not game.startup_slot_prompt_enabled and not game.get_node("Tutorial").auto_start_enabled, "diagnostics skip startup interaction")
	_check(game.get_node("SaveGameController") is Fixtures.NoSaveSlots, "save service is replaced before ready")
	_check(game.get_node("GameSettings") is Fixtures.NoSettings, "settings service is replaced before ready")
	var settings := GuardedSettings.new()
	Fixtures.replace_child(game, "GameSettings", settings)
	# Even if a future caller sets a directory, fixture operations must not create it.
	var forbidden_directory := "res://build/fixture-must-not-create-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	game.get_node("SaveGameController").save_directory = forbidden_directory
	root.add_child(game)
	game.process_mode = Node.PROCESS_MODE_DISABLED
	var slots: Node = game.save_games
	_check(settings.disk_load_attempts == 0, "ready never calls production settings readers")
	_check(settings.locale == "en" and settings.tutorial_completed, "fixture starts in a deterministic locale without onboarding")
	_check(settings.process_mode == Node.PROCESS_MODE_ALWAYS, "settings retains the UI pause contract")
	for slot in range(1, 4):
		_check(slots.get_slot_summary(slot) == {"exists": false, "valid": true}, "fixture reports an empty slot")
		_check(slots.save_slot(slot, {"sentinel": true}) == ERR_UNAVAILABLE, "saving cannot silently claim persistence")
		_check(slots.load_slot(slot).is_empty(), "loading cannot read a real slot")
		_check(slots.reset_slot(slot) == ERR_UNAVAILABLE, "reset cannot delete a real slot")
	_check(slots.get_slot_summary(0) == {"exists": false, "valid": false}, "invalid slots retain the production validation contract")
	slots.slot_summaries.clear()
	_check(not slots.get_slot_summary(1).exists, "a cache miss still uses the isolated summary reader")
	slots.set_save_directory(forbidden_directory + "/nested")
	slots._ensure_save_directory()
	slots._reload_slot_summaries()
	_check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(forbidden_directory)), "no fixture operation creates a save directory")
	settings.set_language("ko")
	_check(settings.locale == "ko" and TranslationServer.get_locale().left(2) == "ko", "language remains functional in memory")
	settings.set_research_chart_rotation(TAU + 0.25)
	_check(is_equal_approx(settings.research_chart_rotation, 0.25), "rotation is wrapped without persistence")
	settings.set_tutorial_completed(false)
	_check(not settings.is_tutorial_completed(), "tutorial state can be varied in memory")
	settings.set_language("en")
	await _check_number_notation(game)
	await _check_settings_persistence()
	var silent := Fixtures.SilentSound.new()
	root.add_child(silent)
	var voice_count := silent.get_child_count()
	silent.play_upgrade()
	silent.play_rare_target()
	_check(silent.get_child_count() == voice_count, "silent dispatch does not allocate additional voices")
	for voice in silent.voice_pool:
		_check(not voice.playing, "silent fixture never starts a pooled audio voice")
	silent.free()
	game.free()
	paused = false
	await process_frame
	if failures.is_empty():
		print("GAME_FIXTURE_PASS: pre-ready isolation, nonpersistent slots/settings and silent diagnostics")
		quit(0)
	else:
		print("GAME_FIXTURE_FAIL: %d failure(s)" % failures.size())
		quit(1)


func _check_number_notation(game: Node) -> void:
	var hud: Node = game.hud
	game.progression.observation_data = 1234567890.0
	game.progression.state_changed.emit()
	game.upgrade_tree._refresh()
	_check(hud.data_label.text == "1.23B" and game.upgrade_tree.data_readout.text == "1.23B", "live HUD and chart abbreviate the same balance")
	_check(hud.data_label.tooltip_text == "1,234,567,890" and game.upgrade_tree.data_readout.tooltip_text == "1,234,567,890", "live balance hovers preserve full values")
	await process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = hud.data_label.get_global_rect().get_center()
	motion.global_position = motion.position
	root.push_input(motion, true)
	await process_frame
	game.observer.cursor_position = game.observer._screen_to_world(motion.position)
	_check(root.gui_get_hovered_control() == hud.data_label and not game.observer._cursor_is_on_ui(), "hovering the actual exact-value label does not block observation")
	motion.position = hud.settings_button.get_global_rect().get_center()
	motion.global_position = motion.position
	root.push_input(motion, true)
	await process_frame
	game.observer.cursor_position = game.observer._screen_to_world(motion.position)
	_check(game.observer._cursor_is_on_ui(), "interactive settings button still blocks sky observation")
	hud._show_data_gain(1200000.0)
	_check(hud.data_gain_label.text.contains("1.20M") and hud.data_gain_label.tooltip_text == "1,200,000", "actual gain feedback uses the shared format and exact tooltip")
	hud.show_phase_summary({"data": 1200000000, "rate": 3600000000.0}, {"rate": 2400000000.0}, "comparable", false)
	_check(hud.phase_summary_data.text.contains("1.20B") and hud.phase_summary_comparison.text.contains("3.60B"), "summary output and rates use the compact format")
	hud.open_settings("general")
	var overlay_order: int = hud.settings_overlay.get_index()
	hud.number_notation_selector.item_selected.emit(1)
	_check(game.settings.number_notation == "scientific" and hud.data_label.text == "1.23e9" and game.upgrade_tree.data_readout.text == "1.23e9", "settings selector immediately updates both data readouts")
	_check(hud.phase_summary_data.text.contains("1.20e9") and hud.phase_summary_comparison.text.contains("+1.20e9"), "open summary refreshes its output and signed rate comparison")
	_check(hud.settings_overlay.get_index() == overlay_order and hud.is_settings_open(), "notation change does not bring the summary in front of settings")
	_check(game.progression.observation_data == 1234567890.0, "format changes never round or mutate the real balance")
	hud.number_notation_selector.item_selected.emit(0)
	hud.close_settings()
	hud.hide_phase_summary()


func _check_settings_persistence() -> void:
	var temp_path := "user://nightwatch_settings_fixture_%d_%d.cfg" % [OS.get_process_id(), Time.get_ticks_usec()]
	var input_snapshot := _snapshot_nightwatch_input()
	var original_locale := TranslationServer.get_locale()
	var master_bus := AudioServer.get_bus_index("Master")
	var original_volume_db := AudioServer.get_bus_volume_db(master_bus) if master_bus >= 0 else 0.0
	var original_muted := AudioServer.is_bus_mute(master_bus) if master_bus >= 0 else false
	var original_max_fps := Engine.max_fps
	var original_vsync := DisplayServer.window_get_vsync_mode()
	var sentinel_action := &"fixture_foreign_action"
	if InputMap.has_action(sentinel_action):
		InputMap.erase_action(sentinel_action)
	InputMap.add_action(sentinel_action)
	var sentinel_event := _key_event(KEY_Q)
	InputMap.action_add_event(sentinel_action, sentinel_event)

	var first := GameSettings.new(temp_path)
	root.add_child(first)
	await process_frame
	_check(first.settings_path == temp_path, "settings accept an injected test-only path before ready")
	_check(first.number_notation == "compact", "existing or missing settings default to compact numbers")
	first.set_number_notation("scientific")
	first.set_number_notation("invalid")
	_check(first.number_notation == "scientific", "unsupported notation cannot replace a valid preference")
	_check(
		is_equal_approx(first.get_master_volume_linear(), 1.0)
		and not first.is_muted()
		and not first.should_mute_when_unfocused()
		and first.is_vsync_enabled()
		and first.get_fps_limit() == 0
		and is_equal_approx(first.get_motion_intensity(), 1.0)
		and first.are_screen_flashes_enabled(),
		"missing settings use validated audio, display, performance, and accessibility defaults"
	)
	_check(not bool(first.validate_binding_conflict(&"nw_chart", _key_event(KEY_F9)).get("ok", true)), "raw F9 cannot be saved as an inert editable binding")
	var debug_chord := _key_event(KEY_D)
	debug_chord.ctrl_pressed = true
	debug_chord.shift_pressed = true
	_check(not bool(first.validate_binding_conflict(&"nw_chart", debug_chord).get("ok", true)), "raw Ctrl+Shift debug chords are reserved")
	_check(not bool(first.validate_binding_conflict(&"nw_chart", _key_event(KEY_TAB)).get("ok", true)), "GUI focus-navigation keys are reserved")
	_check(not bool(first.validate_binding_conflict(&"nw_fullscreen", _key_event(KEY_ENTER)).get("ok", true)), "global fullscreen rejects GUI activation keys")
	_check(bool(first.validate_binding_conflict(&"nw_chart", _key_event(KEY_ENTER)).get("ok", false)), "chart may use Enter because its active gameplay context has no competing focused GUI")
	var chart_k := _key_event(KEY_K)
	var chart_result: Dictionary = first.set_editable_binding(&"nw_chart", chart_k)
	_check(bool(chart_result.get("ok", false)), "an editable chart binding can be replaced")
	_check(chart_k.is_action(&"nw_chart") and not _key_event(KEY_U).is_action(&"nw_chart"), "replacing chart U removes the old gameplay binding")
	_check(_key_event(KEY_U).is_action(&"nw_continue"), "the context-separated summary U fallback remains valid")
	var conflict: Dictionary = first.set_editable_binding(&"nw_fullscreen", chart_k)
	_check(not bool(conflict.get("ok", true)) and String(conflict.get("conflict_action", "")) == "nw_chart", "a global fullscreen key cannot collide with a contextual binding")
	first.set_master_volume_linear(0.37)
	first.set_muted(false)
	first.set_mute_when_unfocused(true)
	first._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(not first.is_muted() and AudioServer.is_bus_mute(master_bus), "focus muting overlays the user mute without changing it")
	first._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_check(not AudioServer.is_bus_mute(master_bus), "returning focus restores the user's unmuted state")
	first.set_muted(true)
	first.set_vsync_enabled(false)
	first.set_fps_limit(60)
	first._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(first.get_fps_limit() == 60, "focus loss leaves the configured frame cap unchanged")
	first._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_check(first.get_fps_limit() == 60, "focus return leaves the configured frame cap unchanged")
	first.set_motion_intensity(0.4)
	first.set_screen_flashes_enabled(false)
	var fullscreen_f10 := _key_event(KEY_F10)
	_check(bool(first.set_editable_binding(&"nw_fullscreen", fullscreen_f10).get("ok", false)), "fullscreen has an editable primary key")
	var config := ConfigFile.new()
	_check(config.load(temp_path) == OK, "settings save to the injected path")
	_check(int(config.get_value("settings", "version", 0)) == first.SETTINGS_VERSION, "settings persistence carries a schema version")
	_check(config.get_value("input", "nw_chart", null) is Array, "bindings persist as a per-action descriptor array")
	config.set_value("performance", "background_throttle", true)
	_check(config.save(temp_path) == OK, "fixture can seed the retired background throttle key")
	first.queue_free()
	await process_frame

	var second := GameSettings.new(temp_path)
	root.add_child(second)
	await process_frame
	_check(second.number_notation == "scientific" and second.format_data(1200000000.0) == "1.20e9", "notation preference round-trips through the isolated settings file")
	_check(
		is_equal_approx(second.get_master_volume_linear(), 0.37)
		and second.is_muted()
		and second.should_mute_when_unfocused(),
		"audio values and the unfocused policy round-trip through the injected file"
	)
	_check(
		not second.is_vsync_enabled()
		and second.get_fps_limit() == 60
		and is_equal_approx(second.get_motion_intensity(), 0.4)
		and not second.are_screen_flashes_enabled(),
		"display, performance, and accessibility values round-trip through the injected file"
	)
	_check(_key_event(KEY_K).is_action(&"nw_chart") and _key_event(KEY_F10).is_action(&"nw_fullscreen"), "valid editable bindings round-trip")
	_check(second.save_settings() == OK, "current settings can rewrite a legacy settings file")
	config = ConfigFile.new()
	_check(config.load(temp_path) == OK and not config.has_section_key("performance", "background_throttle"), "saving schema v3 removes the retired background throttle key")
	second.queue_free()
	await process_frame

	# Corrupt one action only; a valid action beside it must still load.
	config.set_value("input", "nw_chart", [{"kind": "key", "logical": -1, "modifiers": {"shift": false, "alt": false, "ctrl": false, "meta": false}}])
	config.set_value("performance", "fps_limit", 45)
	config.set_value("display", "number_notation", 42)
	config.set_value("accessibility", "motion_intensity", "too much")
	config.set_value("accessibility", "screen_flashes_enabled", 1)
	_check(config.save(temp_path) == OK, "fixture can prepare one invalid action payload")
	var third := GameSettings.new(temp_path)
	root.add_child(third)
	await process_frame
	_check(third.number_notation == "compact", "malformed notation falls back without discarding other settings")
	_check(_key_event(KEY_U).is_action(&"nw_chart"), "an invalid action falls back to its own project default")
	_check(_key_event(KEY_F10).is_action(&"nw_fullscreen"), "one invalid action does not discard another valid override")
	_check(
		third.get_fps_limit() == third.DEFAULT_FPS_LIMIT
		and is_equal_approx(third.get_motion_intensity(), third.DEFAULT_MOTION_INTENSITY)
		and third.are_screen_flashes_enabled() == third.DEFAULT_SCREEN_FLASHES_ENABLED,
		"invalid convenience values fall back independently to safe defaults"
	)
	third.reset_nightwatch_bindings(false)
	_check(InputMap.has_action(sentinel_action) and sentinel_event.is_action(sentinel_action), "resetting Nightwatch keys leaves unrelated InputMap actions intact")
	third.queue_free()
	await process_frame

	_restore_nightwatch_input(input_snapshot)
	TranslationServer.set_locale(original_locale)
	InputMap.erase_action(sentinel_action)
	if master_bus >= 0:
		AudioServer.set_bus_volume_db(master_bus, original_volume_db)
		AudioServer.set_bus_mute(master_bus, original_muted)
	Engine.max_fps = original_max_fps
	if DisplayServer.get_name().to_lower() != "headless":
		DisplayServer.window_set_vsync_mode(original_vsync)
	var absolute_path := ProjectSettings.globalize_path(temp_path)
	if FileAccess.file_exists(temp_path):
		DirAccess.remove_absolute(absolute_path)


func _key_event(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	return event


func _snapshot_nightwatch_input() -> Dictionary:
	var snapshot := {}
	for action_value in InputBindings.action_names():
		var action := StringName(action_value)
		var events: Array[InputEvent] = []
		for event in InputMap.action_get_events(action):
			events.append(event.duplicate())
		snapshot[action] = events
	return snapshot


func _restore_nightwatch_input(snapshot: Dictionary) -> void:
	for action_value in InputBindings.action_names():
		var action := StringName(action_value)
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		for event in snapshot.get(action, []):
			InputMap.action_add_event(action, event)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("GAME_FIXTURE: " + message)
