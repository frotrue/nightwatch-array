extends SceneTree

# Captures the main HUD for design review. Run windowed, not --headless.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var game: Node = scene.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	game.upgrade_tree.close_tree()
	game.hud.close_settings() if game.hud.has_method("close_settings") else null
	game.progression.add_debug_data(1284.0)
	game.hud.set_observation_phase(3, 24.0, 40.0)
	var centre: Vector2 = root.get_visible_rect().size * Vector2(0.5, 0.62)
	game.hud.set_tracking(0.67, "fast", 1.34, 1, centre)
	for _index in range(8):
		await process_frame
	var image := root.get_texture().get_image()
	print("PREVIEW_SAVED" if image.save_png("res://build/hud_preview.png") == OK else "PREVIEW_FAILED")
	quit()
