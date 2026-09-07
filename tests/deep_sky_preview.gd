extends SceneTree
const Fixtures = preload("res://tests/support/game_fixture.gd")
const Balance = preload("res://scripts/game_balance.gd")
const Capture = preload("res://tests/capture_reference.gd")
var failures: Array[String] = []
var records: Array = []
var output := ""

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(45.0, true, false, true).timeout.connect(func(): push_error("Deep sky preview timeout"); quit(1))
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	root.gui_disable_input = true
	var source := Capture.source_snapshot(failures)
	output = "res://build/deep_sky_review/%d" % int(Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var game: Node = load("res://scenes/main.tscn").instantiate()
	Fixtures.configure_before_ready(game)
	root.add_child(game)
	await process_frame
	var made_progress := true
	while made_progress:
		made_progress = false
		for definition in Balance.UPGRADE_NODES:
			if definition.branch != "local_group" and not game.progression.has_upgrade(definition.id):
				if game.progression.debug_purchase_node(definition.id):
					made_progress = true
	game.progression.observation_data = 240000000.0
	game.galactic_pullback_seen = true
	game.upgrade_tree.configure_galactic_state(true, true)
	game.deep_sky.target._process(0)
	game.effects.reset()
	game.hud.banner_root.hide()
	for spec in [["common", Vector2(240, 250)], ["binary_star", Vector2(420, 365)], ["fireball", Vector2(140, 440)]]:
		var meteor = game.spawner.spawn_meteor(spec[0], spec[1], Vector2(160, -20), 30.0)
		for index in range(20):
			meteor._process(0.025)
	game.progression.observation_data = 240000000.0
	game.hud._refresh_progression()
	game.hud.banner_root.hide()
	_freeze(game)
	game.observer.native_cursor_visible = false
	game.observer.cursor_position = game.observation_view.screen_to_world(Vector2(555, 305))
	game.observer.queue_redraw()
	_set_locale(game, "ko")
	await _capture(game, "ko_same_sky")
	game.upgrade_tree.open_tree()
	await process_frame
	await process_frame
	game.upgrade_tree.deep_sky_chart.select("m31")
	await _capture(game, "ko_chart_locked")
	game.upgrade_tree.deep_sky_chart.back_button.pressed.emit()
	game.deep_sky.target.apply_manual_observation(10.0, 0.0, 52.0)
	game.effects.reset()
	game.hud.banner_root.hide()
	game.progression.observation_data = 240000000.0
	game.upgrade_tree.open_tree()
	await process_frame
	await process_frame
	game.upgrade_tree.deep_sky_chart.select("focus")
	for locale in ["en", "ko"]:
		_set_locale(game, locale)
		await _capture(game, locale + "_chart_purchase")
	game.deep_sky.purchase("focus")
	game.deep_sky.purchase("wide")
	game.module_popup.open()
	game.deep_sky.equip("wide", 0)
	game.module_popup.select_slot(1)
	game.module_popup.select_module("focus")
	await _capture(game, "ko_popup_over_chart")
	game.module_popup.close()
	game.upgrade_tree.deep_sky_chart.back_button.pressed.emit()
	game.hud.banner_root.hide()
	game.effects.reset()
	game.upgrade_tree.open_tree()
	await process_frame
	await process_frame
	game.module_popup.open()
	game.module_popup.select_slot(1)
	game.module_popup.select_module("focus")
	for locale in ["en", "ko"]:
		_set_locale(game, locale)
		await _capture(game, locale + "_module_popup")
	if source != Capture.source_snapshot(failures):
		failures.append("source changed during capture")
	var manifest := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "source": source, "frames": records, "failures": failures, "synthetic": true}, "\t"))
	manifest.close()
	game.free()
	paused = false
	await process_frame
	if failures.is_empty() and records.size() == 7:
		print("DEEP_SKY_PREVIEW_PASS: 7 frames at " + ProjectSettings.globalize_path(output))
		quit(0)
	else:
		push_error(str(failures))
		quit(1)

func _set_locale(game: Node, locale: String) -> void:
	game.settings.set_language(locale, false)
	game.upgrade_tree.deep_sky_chart.refresh_text()
	game.module_popup.refresh()
	game.deep_sky.target.queue_redraw()

func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		_freeze(child)

func _capture(game: Node, name: String) -> void:
	if "popup" in name and (not game.module_popup.is_open() or game.module_popup.layer <= game.upgrade_tree.layer):
		failures.append("popup missing or obscured by research: " + name)
	game.hud.data_gain_label.hide()
	game.hud.banner_root.hide()
	for tween in get_processed_tweens():
		tween.kill()
	await process_frame
	await process_frame
	RenderingServer.force_draw()
	RenderingServer.force_sync()
	var first := root.get_texture().get_image()
	await process_frame
	RenderingServer.force_draw()
	RenderingServer.force_sync()
	var second := root.get_texture().get_image()
	if first.get_data() != second.get_data() or second.get_size() != Vector2i(1152, 648):
		failures.append("unstable or wrong-size frame: " + name)
	var path := output.path_join(name + ".png")
	if second.save_png(path) != OK:
		failures.append("write failed: " + name)
	records.append({"file": path, "sha256": FileAccess.get_sha256(path), "deep_sky": game.deep_sky.get_save_data(), "chart": game.upgrade_tree.is_open(), "popup": game.module_popup.is_open()})
