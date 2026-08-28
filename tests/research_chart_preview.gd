extends SceneTree

const ChartData = preload("res://scripts/research_chart_data.gd")
const REFERENCE_COMPLETED_CONSTELLATIONS := [
	"cassiopeia", "big_dipper", "orion", "andromeda", "perseus", "lyra",
	"gemini", "taurus", "leo", "ursa_minor",
]

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

	var galactic_final_preview := OS.get_environment("NIGHTWATCH_GALACTIC_RESEARCH_PREVIEW") == "1"
	if galactic_final_preview:
		game.progression.debug_purchase_all()
	else:
		_build_reference_constellation_state(game.progression)
		game.progression.observation_data = 1284000.0
		game.upgrade_tree.set_intermission_context(5, 80)
	game.upgrade_tree.open_tree()
	await process_frame
	await process_frame
	var transition_time_text := OS.get_environment("NIGHTWATCH_GALACTIC_RESEARCH_PREVIEW_TIME")
	var transition_time := clampf(float(transition_time_text), 0.0, 3.6) if transition_time_text.is_valid_float() else -1.0

	var tree = game.upgrade_tree
	if galactic_final_preview:
		if transition_time >= 0.0 and transition_time < 3.6:
			tree._advance_galactic_pullback(transition_time)
		else:
			tree._finish_galactic_pullback()
	else:
		tree.rotation_offset = 0.0
		tree._layout_chart()
		tree._on_node_hovered("canis_capacity_ii")
	for _index in range(4):
		await process_frame
	# Fix animated pulse state and wait for the renderer so baseline comparisons
	# are deterministic instead of occasionally capturing a partially drawn frame.
	for star_visual_variant in tree.node_hold_bars.values():
		var star_visual: Control = star_visual_variant
		star_visual.set("pulse_phase", 0.0)
		star_visual.set_process(false)
		star_visual.queue_redraw()
	var image: Image = await _capture_settled_frame(root)
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


func _capture_settled_frame(viewport: Viewport) -> Image:
	var image: Image
	for _attempt in range(8):
		await process_frame
		await RenderingServer.frame_post_draw
		image = viewport.get_texture().get_image()
		if _has_visible_interface(image):
			return image
	push_warning("Research preview renderer did not produce a fully settled UI frame")
	return image


func _has_visible_interface(image: Image) -> bool:
	var bright_samples := 0
	for y in range(0, image.get_height(), 8):
		for x in range(0, image.get_width(), 8):
			var pixel := image.get_pixel(x, y)
			if maxf(pixel.r, maxf(pixel.g, pixel.b)) >= 0.35:
				bright_samples += 1
				if bright_samples >= 24:
					return true
	return false


func _build_reference_constellation_state(progression: Node) -> void:
	var pending: Array[String] = []
	for constellation_id in REFERENCE_COMPLETED_CONSTELLATIONS:
		for star_variant in ChartData.CONSTELLATIONS[constellation_id].stars:
			var node_id := String(star_variant.get("node_id", ""))
			if not node_id.is_empty():
				pending.append(node_id)
	pending.append_array(["canis_opening", "canis_cadence_i", "canis_capacity_i"])
	var made_progress := true
	while made_progress and not pending.is_empty():
		made_progress = false
		for index in range(pending.size() - 1, -1, -1):
			if progression.debug_purchase_node(pending[index]):
				pending.remove_at(index)
				made_progress = true
	assert(pending.is_empty(), "Reference constellation state could not install every requested node")
