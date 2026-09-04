extends SceneTree

const GameSettings = preload("res://scripts/game_settings.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name().to_lower() == "headless":
		push_error("SETTINGS_WINDOWED: run without --headless so display policies can be verified")
		quit(1)
		return
	var original_max_fps := Engine.max_fps
	var original_vsync := DisplayServer.window_get_vsync_mode()
	var temp_path := "user://nightwatch_settings_windowed_%d.cfg" % OS.get_process_id()
	var settings := GameSettings.new(temp_path)
	root.add_child(settings)
	await process_frame
	_check(
		settings._application_focused == DisplayServer.window_is_focused(),
		"startup focus state matches the real main window before policies are applied"
	)
	settings._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	settings.set_fps_limit(60, false)
	_check(Engine.max_fps == 60, "configured frame cap reaches Engine.max_fps")
	settings._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(Engine.max_fps == 60, "focus loss leaves the configured engine cap unchanged")
	settings._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_check(Engine.max_fps == 60, "focus return leaves the configured engine cap unchanged")
	settings.set_vsync_enabled(false, false)
	_check(
		DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_DISABLED,
		"VSync off reaches DisplayServer"
	)
	settings.set_vsync_enabled(true, false)
	_check(
		DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_ENABLED,
		"VSync on reaches DisplayServer"
	)
	settings.queue_free()
	await process_frame
	Engine.max_fps = original_max_fps
	DisplayServer.window_set_vsync_mode(original_vsync)
	if FileAccess.file_exists(temp_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
	if failures.is_empty():
		print("SETTINGS_WINDOWED_PASS: startup focus, VSync, and the focus-independent frame cap reach the live display runtime")
		quit(0)
	else:
		print("SETTINGS_WINDOWED_FAIL: %d failure(s)" % failures.size())
		quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures.append(message)
	push_error("SETTINGS_WINDOWED: %s" % message)
