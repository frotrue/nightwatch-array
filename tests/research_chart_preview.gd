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
	var galactic_final_preview := OS.get_environment("NIGHTWATCH_GALACTIC_RESEARCH_PREVIEW") == "1"
	var transition_time_text := OS.get_environment("NIGHTWATCH_GALACTIC_RESEARCH_PREVIEW_TIME")
	var transition_time := clampf(float(transition_time_text), 0.0, 3.6) if transition_time_text.is_valid_float() else -1.0

	var tree = game.upgrade_tree
	if galactic_final_preview and transition_time >= 0.0 and transition_time < 3.6:
		tree._advance_galactic_pullback(transition_time)
	else:
		tree._finish_galactic_pullback()
	if not galactic_final_preview:
		# Hover a node so the cursor tooltip is part of the chart-scale capture. The
		# script has no real pointer, so the tooltip is placed by hand. Ctrl+wheel's
		# actual zoom path is reused to enter the completed chart from the galaxy.
		tree._zoom_at(tree.content_clip.global_position + tree.content_clip.size * 0.5, 4.0)
		tree.rotation_offset = 0.58
		tree._layout_chart()
		tree._on_node_hovered("galactic_reference_frame")
	for _index in range(4):
		await process_frame
	if not galactic_final_preview:
		# Park the tooltip in the sparse upper-left so it names the transition without
		# covering Draco itself.
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
	if galactic_final_preview:
		output = "res://build/galactic_research_preview.png"
		if transition_time >= 0.0 and transition_time < 3.6:
			output = "res://build/galactic_research_transition_%03d.png" % int(round(transition_time * 100.0))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	var error := image.save_png(output)
	if error == OK:
		print("PREVIEW_SAVED: %s" % ProjectSettings.globalize_path(output))
	else:
		print("PREVIEW_FAILED: %d" % error)
	quit()
