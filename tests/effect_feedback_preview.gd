extends SceneTree

# Stage-2-only rendered diagnostics. Run WINDOWED, not --headless:
#   godot --path . --script res://tests/effect_feedback_preview.gd
# Eight frozen PNGs and per-image JSON notes go to build/effect_feedback_review.
# This is not the stage-3 capture pipeline or a verdict on live animation feel.
const MainScene = preload("res://scenes/main.tscn")
const Fixtures = preload("res://tests/support/game_fixture.gd")
const Balance = preload("res://scripts/game_balance.gd")
const OUTPUT_DIR := "res://build/effect_feedback_review"
const EFFECT_SEED := 7331
const EFFECT_AGE := 0.12
const SOURCE_FILES := [
	"scripts/game.gd", "scripts/effects_layer.gd", "scripts/hud.gd",
	"scripts/upgrade_tree.gd", "tests/effect_feedback_preview.gd",
	"tests/support/game_fixture.gd", "scripts/research_star_visual.gd",
	"scripts/ui_theme.gd",
]

var game: Node
var source: Dictionary = {}
var run_id := ""
var captured_count := 0
var failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_fail("Windowed rendered diagnostics require a display; --headless cannot produce these PNGs.")
		return
	# A renderer which never submits a frame must not leave this diagnostic hung.
	create_timer(45.0, true, false, true).timeout.connect(func(): _fail("Rendered diagnostic exceeded its 45-second watchdog."))
	if not _read_source_identity():
		return
	run_id = "stage2_%d" % int(Time.get_unix_time_from_system() * 1000.0)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	if mkdir_error != OK:
		_fail("Cannot create diagnostic output directory: %s" % error_string(mkdir_error))
		return
	root.gui_disable_input = true
	game = MainScene.instantiate()
	Fixtures.configure_before_ready(game)
	root.add_child(game)
	game.sound.free()
	game.sound = Fixtures.SilentSound.new()
	game.add_child(game.sound)
	game.spawner.running = false
	game.events.running = false
	game.observer.visible = false
	_freeze_scene()
	await _settle_layout()
	if not await _capture_observation("01_routine_common_good", 0.40, false):
		return
	if not await _capture_observation("02_accent_common_perfect", 1.0, true):
		return
	game.effects.reset()
	game.progression.reset()
	game.progression.observation_data = 1000000000000.0
	game.upgrade_tree.open_tree()
	await _settle_layout()
	game.upgrade_tree._on_node_hovered("better_lens")
	if not await _capture_installation("03_constellation", "better_lens", game.upgrade_tree.constellation_installation_rule):
		return
	game.upgrade_tree.close_tree()
	for definition in Balance.UPGRADE_NODES:
		if String(definition.branch) != "local_group":
			game.progression.purchased_nodes[String(definition.id)] = true
	game.galactic_pullback_seen = true
	game.upgrade_tree.configure_galactic_state(true, true)
	game.upgrade_tree.open_tree()
	await _settle_layout()
	game.upgrade_tree._on_node_hovered("lmc_transit_watch")
	if not await _capture_installation("04_galaxy", "lmc_transit_watch", game.upgrade_tree.galactic_installation_rule):
		return
	if source.files_sha256 != _source_hashes():
		_fail("Source files changed during capture; do not treat this image set as one revision.")
		return
	if captured_count != 8:
		_fail("Expected exactly eight stage-2 diagnostic PNGs, got %d." % captured_count)
		return
	print("EFFECT_PREVIEW_PASS: 8 windowed stage-2 diagnostic PNGs; frozen poses, not live animation approval; run %s" % run_id)
	game.free()
	quit(0)


func _freeze_node(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	for child in node.get_children():
		_freeze_node(child)


func _freeze_scene() -> void:
	_freeze_node(game)
	for tween in get_processed_tweens():
		tween.pause()
	for visual in game.upgrade_tree.node_hold_bars.values():
		visual.pulse_phase = 0.0
		visual.queue_redraw()
	game.get_node("TwinkleStars").time = 0.0
	game.get_node("TwinkleStars").queue_redraw()


func _settle_layout() -> void:
	# Stop clocks immediately, but let deferred Container layout complete before
	# locking the final star pulses and before asking the renderer for pixels.
	_freeze_scene()
	for _frame in range(4):
		await process_frame
	_freeze_scene()


func _capture_observation(case_id: String, quality: float, accented: bool) -> bool:
	game.progression.reset()
	game.effects.reset()
	game.effects.rng.seed = EFFECT_SEED
	for _link in range(12):
		game.progression.record_manual_combo_success()
	game.hud.set_observation_phase(1, 14.0, 20.0)
	game.hud.banner_root.visible = false
	game.hud.banner_timer = 0.0
	var position := Vector2(570.0, 350.0)
	var direction := Vector2(220.0, 90.0)
	var target = game.spawner.spawn_meteor("common", position, direction, 10.0)
	if target == null:
		_fail("Could not spawn the diagnostic common meteor.")
		return false
	# Synthetic accumulated tracking quality, then the real meteor completion
	# signal and game feedback route. No research multiplier or proc is enabled.
	target.manual_touched = true
	target.manual_tracking_time = 1.0
	target.quality_integral = quality
	target.observation_progress = 1.0
	target._finish_observation(0.0)
	var grade: String = target.get_quality_grade()
	target.free() # Isolate the effects layer rather than its separate linger art.
	game.effects._process(EFFECT_AGE)
	await _settle_layout()
	var valid: bool = (
		game.effects.particles.size() > 0
		and game.effects.popups.size() == 1
		and game.effects.rings.size() == (1 if accented else 0)
		and (game.effects.flash_strength > 0.0) == accented
	)
	if not valid:
		_fail("Unexpected routine/accent state before rendering: " + case_id)
		return false
	return await _save_frame(case_id, {
		"kind": "observation_effects", "type": "common", "manual": true,
		"grade": grade, "combo": game.progression.manual_combo_count,
		"effect_seed": EFFECT_SEED, "effect_age_seconds": EFFECT_AGE,
		"target_world_position": [position.x, position.y],
		"target_velocity": [direction.x, direction.y],
		"particles": game.effects.particles.size(), "rings": game.effects.rings.size(),
		"packets": game.effects.popups.size(), "flash_strength": game.effects.flash_strength,
		"note": "Real Meteor._finish_observation route with synthetic accumulated quality; completed meteor linger art removed to isolate feedback. Frozen 120 ms pose, not an animation timing verdict.",
	})


func _capture_installation(case_prefix: String, node_id: String, rule: ColorRect) -> bool:
	var chart = game.upgrade_tree
	if not game.progression.request_purchase(node_id):
		_fail("Real chart-open purchase failed: " + node_id)
		return false
	var tween: Tween = chart.installation_tween
	if tween == null or not tween.is_valid():
		_fail("Purchase did not create the chart installation tween: " + node_id)
		return false
	tween.pause()
	await _settle_layout()
	var samples := [["start", 0.0, 0.2], ["mid", 0.14, 0.9], ["end", 0.14, 1.0]]
	for sample in samples:
		if float(sample[1]) > 0.0:
			tween.custom_step(float(sample[1]))
		if (
			not chart.is_open() or not paused or chart.installation_rule != rule
			or not rule.is_visible_in_tree() or rule.get_canvas_layer_node() != chart
			or chart.installation_node_id != node_id
			or not is_equal_approx(rule.scale.x, float(sample[2]))
			or not is_equal_approx(rule.size.y, 1.0)
		):
			_fail("Visible inspector/pulse state does not match %s/%s." % [node_id, sample[0]])
			return false
		var rect := rule.get_global_rect()
		if not root.get_visible_rect().encloses(rect) or rect.size.x <= 1.0:
			_fail("Inspector rule is empty or outside the rendered viewport.")
			return false
		if not await _save_frame(case_prefix + "_" + String(sample[0]), {
			"kind": "chart_installation", "purchased_node": node_id,
			"installed_count": game.progression.upgrade_level,
			"chart_scale": "galaxy" if chart._galactic_panel_active() else "constellation",
			"rule_scale_x": rule.scale.x, "rule_unscaled_width": rule.size.x,
			"rule_global_rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
			"chart_canvas_layer": chart.layer, "hud_canvas_layer": game.hud.layer,
			"sample": sample[0], "elapsed_seconds": 0.0 if sample[0] == "start" else (0.14 if sample[0] == "mid" else 0.28),
			"note": "Actual open_tree -> request_purchase -> production tween. Deferred layout settled, then the pause-safe tween is manually stepped and frozen for pixel review.",
		}):
			return false
	return true


func _save_frame(case_id: String, state: Dictionary) -> bool:
	var image: Image
	for _attempt in range(8):
		await process_frame
		await RenderingServer.frame_post_draw
		image = root.get_texture().get_image()
		if image != null and not image.is_empty() and _has_visible_interface(image):
			break
	if image == null or image.is_empty() or not _has_visible_interface(image):
		_fail("Renderer supplied no usable nonblank image: " + case_id)
		return false
	var file_id := run_id + "_" + case_id
	var image_path := OUTPUT_DIR.path_join(file_id + ".png")
	var png_error := image.save_png(image_path)
	if png_error != OK:
		_fail("PNG save failed: %s (%s)" % [image_path, error_string(png_error)])
		return false
	var metadata := {
		"diagnostic": "stage2_effect_feedback_windowed", "case_id": case_id,
		"run_id": run_id, "image": ProjectSettings.globalize_path(image_path),
		"captured_utc": Time.get_datetime_string_from_system(true),
		"display_server": DisplayServer.get_name(),
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"viewport": [root.get_visible_rect().size.x, root.get_visible_rect().size.y],
		"png_size": [image.get_width(), image.get_height()],
		"source": source, "state": state,
		"limitation": "Narrow stage-2 frozen-pose review only; not the stage-3 universal capture gate, not proof of perceived live pacing.",
	}
	var note := FileAccess.open(OUTPUT_DIR.path_join(file_id + ".json"), FileAccess.WRITE)
	if note == null:
		_fail("Cannot write diagnostic sidecar: %s" % error_string(FileAccess.get_open_error()))
		return false
	note.store_string(JSON.stringify(metadata, "\t") + "\n")
	var note_error := note.get_error()
	note.close()
	if note_error != OK:
		_fail("Diagnostic sidecar write failed: %s" % error_string(note_error))
		return false
	captured_count += 1
	print("EFFECT_PREVIEW_SAVED: " + ProjectSettings.globalize_path(image_path))
	return true


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


func _read_source_identity() -> bool:
	var revision_output: Array = []
	var status_output: Array = []
	var project_dir := ProjectSettings.globalize_path("res://")
	var revision_error := OS.execute("git", PackedStringArray(["-C", project_dir, "rev-parse", "HEAD"]), revision_output, true)
	var status_error := OS.execute("git", PackedStringArray(["-C", project_dir, "status", "--porcelain=v1", "--untracked-files=normal"]), status_output, true)
	if revision_error != 0 or status_error != 0 or revision_output.is_empty():
		_fail("Cannot record HEAD and working-tree status; Git must be available for this diagnostic.")
		return false
	var status_text := "".join(status_output).strip_edges()
	source = {
		"head": "".join(revision_output).strip_edges(),
		"working_tree_dirty": not status_text.is_empty(),
		"git_status_porcelain": status_text,
		"files_sha256": _source_hashes(),
		"note": "HEAD identifies the base commit only; dirty status and file hashes describe the actually rendered working tree.",
	}
	return true


func _source_hashes() -> Dictionary:
	var hashes := {}
	for path in SOURCE_FILES:
		hashes[path] = FileAccess.get_sha256("res://" + path)
	return hashes


func _fail(message: String) -> void:
	if failed:
		return
	failed = true
	push_error("EFFECT_PREVIEW_FAIL: " + message)
	quit(1)
