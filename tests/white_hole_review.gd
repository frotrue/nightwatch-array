extends "res://tests/deep_sky_preview.gd"

const UITheme = preload("res://scripts/ui_theme.gd")

# Synthetic optical controls: a star grid behind the lens and an opaque
# instrument/target stand-in in front, both used only by this diagnostic.
class SkyGrid:
	extends Node2D
	func _draw() -> void:
		for y in range(-120, 121, 20):
			for x in range(-120, 121, 20):
				draw_circle(Vector2(x, y), 0.85, Color(0.7, 0.8, 1.0))

class ForegroundMarker:
	extends Node2D
	func _draw() -> void:
		draw_rect(Rect2(-60, 28, 120, 4), Color("05ff41"))

func _review_sky_lens(game: Node, body: Node2D, centre: Vector2) -> void:
	var grid := SkyGrid.new()
	grid.position = centre
	grid.z_index = -19
	game.add_child(grid)
	var marker := ForegroundMarker.new()
	marker.position = centre
	marker.z_index = 10
	game.add_child(marker)
	body.set_process(false)
	body.emission.hide()
	body.lensed_sky.hide()
	body.background_copy.copy_mode = BackBufferCopy.COPY_MODE_DISABLED
	await _capture(game, "lens_reference_off")
	var original := root.get_texture().get_image()
	body.present()
	await _capture(game, "lens_reference_on")
	var warped := root.get_texture().get_image()
	var changed := 0
	for y in 648:
		for x in 1152:
			if original.get_pixel(x, y) != warped.get_pixel(x, y): changed += 1
	if changed < 100: failures.append("sky reference did not refract")
	var front_rect := Rect2i(516, 352, 120, 4)
	if original.get_region(front_rect).get_data() != warped.get_region(front_rect).get_data():
		failures.append("sky refraction displaced foreground content")
	grid.free()
	marker.free()
	body.emission.show()
	body.set_process(true)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("White hole review requires a real renderer")
		quit(1)
		return
	if "--observe" in OS.get_cmdline_user_args():
		await _run_observable()
		return
	create_timer(120.0, true, false, true).timeout.connect(func(): push_error("White hole review timeout"); quit(1))
	root.size = Vector2i(1152, 648)
	root.gui_disable_input = true
	var game = load("res://scenes/main.tscn").instantiate()
	Fixtures.configure_before_ready(game)
	root.add_child(game)
	await process_frame
	game.settings.set_language("ko", false)
	game.spawner.reset()
	game.effects.reset()
	game.observer.hide()
	_freeze(game)
	for tween in get_processed_tweens(): tween.kill()
	output = "res://build/white_hole/" + RenderingServer.get_current_rendering_method()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var layer = game.debug_celestials
	var unit: float = game.observation_view.screen_length_to_world(1.0)
	var centre: Vector2 = game.observation_view.screen_to_world(Vector2(576, 324))
	var body = layer.spawn_white_hole(centre, unit)
	body.age = 3.0
	body.visual_time = 3.0
	body.present()
	body.hide()
	await _capture(game, "00_background")
	var background := root.get_texture().get_image()
	body.show()
	await _capture(game, "01_turbulent_disc")
	var waves := root.get_texture().get_image()
	var outside := 0
	var changed := 0
	for y in 648:
		for x in 1152:
			if background.get_pixel(x, y) != waves.get_pixel(x, y):
				changed += 1
				if Vector2(x, y).distance_to(Vector2(576, 324)) > 152.0: outside += 1
	if changed < 500 or outside > 0: failures.append("emission footprint changed=%d outside=%d" % [changed, outside])
	# Advance optical time without the lifetime envelope: a changing image must
	# come from the material, and a held clock must stop both flow and pose.
	body.visual_time = 9.0
	body.present()
	await _capture(game, "01_disc_later")
	var later := root.get_texture().get_image()
	if waves.get_data() == later.get_data(): failures.append("normal-motion disc does not animate")
	for y in 648:
		for x in 1152:
			if background.get_pixel(x, y) != later.get_pixel(x, y) and Vector2(x, y).distance_to(Vector2(576, 324)) > 152.0:
				outside += 1
	if outside > 0: failures.append("rotated disc exceeds the emission footprint")
	await _capture(game, "01_disc_held")
	if later.get_data() != root.get_texture().get_image().get_data(): failures.append("held optical time still changes the disc")
	body.visual_time = 3.0
	body.present()
	await _review_sky_lens(game, body, centre)
	layer.cycle_effect()
	await _capture(game, "02_jets")
	if waves.get_data() == root.get_texture().get_image().get_data(): failures.append("effect modes render identically")
	layer.set_accessibility(0.0, false)
	await _capture(game, "03_reduced_motion")
	var reduced := root.get_texture().get_image()
	body.advance(1.0)
	await _capture(game, "04_reduced_motion_later")
	if reduced.get_data() != root.get_texture().get_image().get_data(): failures.append("reduced-motion effect still animates")
	layer.set_accessibility(1.0, true)
	body.position = game.observation_view.screen_to_world(Vector2(410, 324))
	body.effect_mode = 0
	body.present()
	var jets = layer.spawn_white_hole(game.observation_view.screen_to_world(Vector2(742, 324)), unit)
	jets.age = 3.0
	jets.visual_time = 3.0
	jets.effect_mode = 1
	jets.present()
	# Diagnostic comparison captions belong only to this save-free review.
	var captions := CanvasLayer.new()
	captions.layer = 70
	game.add_child(captions)
	for item in [["난류 원반형", 260], ["양극 제트형", 592]]:
		var label := Label.new()
		label.text = item[0]
		label.position = Vector2(item[1], 140)
		label.size = Vector2(300, 30)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 20)
		label.add_theme_font_override("font", UITheme.sans())
		label.add_theme_color_override("font_color", UITheme.ACCENT_TEXT)
		captions.add_child(label)
	await _capture(game, "05_comparison")
	if "--animate" in OS.get_cmdline_user_args():
		var frames := output.path_join("animation")
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(frames))
		for index in 192:
			for preview in [body, jets]:
				preview.age = 3.0
				preview.visual_time = 3.0 + float(index) / 24.0
				preview.present()
			await process_frame
			await RenderingServer.frame_post_draw
			if root.get_texture().get_image().save_png(frames.path_join("frame_%03d.png" % index)) != OK:
				failures.append("animation frame write failed")
	captions.queue_free()
	var third = layer.spawn_white_hole(centre, unit)
	third.age = 3.0
	third.present()
	await _capture(game, "06_three_overlapping")
	layer.reset()
	await _capture(game, "07_cleared")
	if background.get_data() != root.get_texture().get_image().get_data(): failures.append("cleared preview leaves residual pixels")
	var manifest := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "engine": Engine.get_version_info(), "renderer": RenderingServer.get_current_rendering_method(), "adapter": RenderingServer.get_video_adapter_name(), "frames": records, "failures": failures, "changed_pixels": changed, "outside_pixels": outside, "synthetic": true}, "\t"))
	manifest.close()
	game.free()
	paused = false
	await process_frame
	if failures.is_empty(): print("WHITE_HOLE_REVIEW_PASS: modes, footprint, reduced motion and cleanup at " + ProjectSettings.globalize_path(output))
	quit(0 if failures.is_empty() else 1)

func _run_observable() -> void:
	create_timer(120.0, true, false, true).timeout.connect(func(): push_error("White hole lifecycle review timeout"); quit(1))
	root.size = Vector2i(1152, 648)
	root.gui_disable_input = true
	var game = load("res://scenes/main.tscn").instantiate()
	Fixtures.configure_before_ready(game)
	root.add_child(game)
	await process_frame
	game.settings.set_language("ko", false)
	game.spawner.reset()
	game.events.running = false
	game.effects.reset()
	game.sound.free()
	game.sound = Fixtures.SilentSound.new()
	game.add_child(game.sound)
	_freeze(game)
	for tween in get_processed_tweens(): tween.kill()
	game.hud.hide()
	game.observer.hide()
	output = "res://build/white_hole/" + RenderingServer.get_current_rendering_method() + "/observable"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var unit: float = game.observation_view.screen_length_to_world(1.0)
	var origin: Vector2 = game.observation_view.screen_to_world(Vector2(455, 310))
	var source = game.spawner.spawn_meteor("white_hole", origin, Vector2(24, -5) * unit)
	var stats := {"released": 0, "completion_tick": -1, "peak": 0}
	source.ejecta_requested.connect(func(_body, _index): stats.released += 1)
	game.observer.tick_input.reset(origin)
	game.observer.input_time = 0.0
	game.observer.set_process_input(false)
	var caption_layer := CanvasLayer.new()
	caption_layer.layer = 70
	game.add_child(caption_layer)
	var caption := Label.new()
	caption.position = Vector2(120, 100)
	caption.size = Vector2(912, 40)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_override("font", UITheme.sans())
	caption.add_theme_font_size_override("font_size", 24)
	caption.add_theme_color_override("font_color", UITheme.ACCENT_TEXT)
	caption_layer.add_child(caption)
	for tick in 480:
		var held: bool = tick >= 90 and is_instance_valid(source) and source.alive
		var cursor: Vector2 = source.position + source.velocity / 60.0 if held else origin
		# Focus changes can reset the input epoch. Keep synthetic samples in the
		# observer's current epoch instead of queuing them many seconds ahead.
		game.observer.tick_input.push(game.observer.input_time + 1.0 / 60.0, cursor, held)
		game.simulate_tick()
		game.effects._process(1.0 / 60.0)
		if is_instance_valid(source) and source.observed_successfully and stats.completion_tick < 0:
			stats.completion_tick = tick
		stats.peak = maxi(stats.peak, game.meteor_layer.get_child_count())
		caption.text = "스폰 방향으로 이동" if tick < 90 else ("관측 중 · 에너지 응집" if stats.completion_tick < 0 else "양극 제트 방출 · 유성 %d개" % stats.released)
		if tick % 2 == 1:
			for body in game.meteor_layer.get_children():
				body.previous_simulation_position = body.position
				body.reset_physics_interpolation()
				body.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			if root.get_texture().get_image().save_png(output.path_join("frame_%03d.png" % (tick / 2))) != OK:
				failures.append("lifecycle animation frame write failed")
	if stats.completion_tick < 90:
		failures.append("buffered manual tracking did not complete the moving white hole")
		print("WHITE_HOLE_INPUT_DIAGNOSTIC ", {"progress": source.get_progress(), "cursor": game.observer.cursor_position, "position": source.position, "input_time": game.observer.input_time, "held": game.observer.simulation_holding, "manual": source.manual_contribution})
	if stats.released != 24: failures.append("lifecycle did not emit 24 meteors")
	if is_instance_valid(source): failures.append("source survived its completion animation")
	var manifest := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "renderer": RenderingServer.get_current_rendering_method(), "stats": stats, "frames": 240, "fps": 30, "failures": failures}, "\t"))
	manifest.close()
	game.free()
	paused = false
	await process_frame
	if failures.is_empty(): print("WHITE_HOLE_OBSERVABLE_PASS: moving target, buffered manual observation, jet release and disappearance")
	else: push_error(str(failures))
	quit(0 if failures.is_empty() else 1)
