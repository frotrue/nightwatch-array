extends SceneTree

const Fixtures = preload("res://tests/support/game_fixture.gd")

# Captures the settings or controls surface at the project's 1152x648 contract.
# Run windowed; headless rendering does not provide a representative frame.
#
#   $env:NIGHTWATCH_SETTINGS_PREVIEW = "controls" # or "audio"
#   $env:NIGHTWATCH_SETTINGS_LOCALE = "ko"        # optional
#   Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/settings_preview.gd


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var game: Node = scene.instantiate()
	Fixtures.configure_before_ready(game)
	root.add_child(game)
	await process_frame
	await process_frame
	var locale := OS.get_environment("NIGHTWATCH_SETTINGS_LOCALE").to_lower().left(2)
	if locale in ["en", "ko"]:
		game.settings.set_language(locale, false)
	game.hud.open_settings()
	var surface := OS.get_environment("NIGHTWATCH_SETTINGS_PREVIEW").to_lower()
	if surface == "controls":
		game.hud.open_controls()
	else:
		game.hud._set_audio_display_expanded(true)
	for _index in range(5):
		await process_frame
	var image: Image = await _capture_settled_frame(root)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	var suffix := "controls" if surface == "controls" else "settings"
	if locale == "ko":
		suffix += "_ko"
	var output := "res://build/%s_preview.png" % suffix
	var error := image.save_png(output)
	if error == OK:
		print("SETTINGS_PREVIEW_SAVED: %s" % ProjectSettings.globalize_path(output))
	else:
		push_error("SETTINGS_PREVIEW_FAILED: %s" % error_string(error))
	quit(0 if error == OK else 1)


func _capture_settled_frame(viewport: Viewport) -> Image:
	var image: Image
	for _attempt in range(8):
		await process_frame
		await RenderingServer.frame_post_draw
		image = viewport.get_texture().get_image()
		if image != null and not image.is_empty():
			return image
	return image
