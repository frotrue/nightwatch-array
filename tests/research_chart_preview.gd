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
	game.startup_slot_prompt_enabled = false
	game.get_node("Tutorial").auto_start_enabled = false
	root.add_child(game)
	await process_frame
	await process_frame

	game.progression.debug_purchase_all()
	game.upgrade_tree.open_tree()
	await process_frame
	await process_frame

	# Hover a node so the cursor tooltip is part of the capture. The script has no
	# real pointer, so the tooltip is placed at the hovered star by hand. Keep
	# Canis Major above the horizon so its four-root figure and Sirius terminus
	# can be reviewed in one capture.
	var tree = game.upgrade_tree
	tree._reset_view(false)
	tree.rotation_offset = -1.27
	tree._layout_chart()
	tree._on_node_hovered("sirius_fireball")
	for _index in range(4):
		await process_frame
	# Park the tooltip in the sparse upper-left so it names Sirius without
	# covering the small Canis figure it is meant to review.
	tree._position_node_tooltip(Vector2(24.0, 100.0))
	# Fix animated pulse state and wait for the renderer so baseline comparisons
	# are deterministic instead of occasionally capturing a partially drawn frame.
	for star_visual_variant in tree.node_hold_bars.values():
		var star_visual: Control = star_visual_variant
		star_visual.set("pulse_phase", 0.0)
		star_visual.set_process(false)
		star_visual.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw

	var image := root.get_texture().get_image()
	var output := "res://build/research_chart_preview.png"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	var error := image.save_png(output)
	if error == OK:
		print("PREVIEW_SAVED: %s" % ProjectSettings.globalize_path(output))
	else:
		print("PREVIEW_FAILED: %d" % error)
	quit()
