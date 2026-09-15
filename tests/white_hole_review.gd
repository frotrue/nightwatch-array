extends "res://tests/deep_sky_preview.gd"

const UITheme = preload("res://scripts/ui_theme.gd")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("White hole review requires a real renderer")
		quit(1)
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
	await _capture(game, "01_waves")
	var waves := root.get_texture().get_image()
	var outside := 0
	var changed := 0
	for y in 648:
		for x in 1152:
			if background.get_pixel(x, y) != waves.get_pixel(x, y):
				changed += 1
				if Vector2(x, y).distance_to(Vector2(576, 324)) > 152.0: outside += 1
	if changed < 500 or outside > 0: failures.append("emission footprint changed=%d outside=%d" % [changed, outside])
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
	for item in [["파동형", 260], ["양극 제트형", 592]]:
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
		for index in 72:
			for preview in [body, jets]:
				preview.age = 3.0
				preview.visual_time = 3.0 + float(index) / 18.0
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
