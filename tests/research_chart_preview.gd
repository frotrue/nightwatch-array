extends SceneTree

# Captures the research chart for design review. Run windowed (not --headless);
# a headless run has no rendered frame to capture.
#
#   Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/research_chart_preview.gd


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var game: Node = scene.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame

	game.progression.add_debug_data(100.0)
	game.progression.request_purchase("better_lens")
	game.upgrade_tree.open_tree()
	await process_frame
	await process_frame

	# Hover a node so the cursor tooltip is part of the capture. The script has no
	# real pointer, so the tooltip is placed at the hovered star by hand.
	var tree = game.upgrade_tree
	tree._on_node_hovered("long_exposure")
	for _index in range(4):
		await process_frame
	var star: Control = tree.node_buttons["long_exposure"]
	var overlay_control: Control = tree.overlay
	var cursor: Vector2 = star.global_position + star.size * 0.5 - overlay_control.global_position
	tree._position_node_tooltip(cursor)
	await process_frame

	var image := root.get_texture().get_image()
	var output := "res://build/research_chart_preview.png"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	var error := image.save_png(output)
	if error == OK:
		print("PREVIEW_SAVED: %s" % ProjectSettings.globalize_path(output))
	else:
		print("PREVIEW_FAILED: %d" % error)
	quit()
