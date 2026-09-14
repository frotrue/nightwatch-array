extends "res://tests/deep_sky_preview.gd"

func _run() -> void:
	create_timer(60.0, true, false, true).timeout.connect(func(): push_error("Expansion preview timeout"); quit(1))
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	root.gui_disable_input = true
	var source := Capture.source_snapshot(failures)
	output = "res://build/outer_growth_review/%d" % int(Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var game: Node = load("res://scenes/main.tscn").instantiate()
	Fixtures.configure_before_ready(game)
	root.add_child(game)
	await process_frame
	var progressed := true
	while progressed:
		progressed = false
		for definition in Balance.UPGRADE_NODES:
			if not game.progression.has_upgrade(definition.id):
				progressed = game.progression.debug_purchase_node(definition.id) or progressed
	game.spawner.reset()
	game.galactic_pullback_seen = true
	game.upgrade_tree.configure_galactic_state(true, true)
	game.upgrade_tree.open_tree()
	game.progression.observation_data = 100000000000.0
	game.effects.reset()
	_freeze(game)
	var popup: Node = game.module_popup
	var window: Control = popup.draw_window
	for locale in ["en", "ko"]:
		_set_locale(game, locale)
		popup.open()
		await _capture(game, locale + "_popup_empty")
		popup.open_draw()
		window.set_process(false)
		await _capture(game, locale + "_draw_empty")
		popup.close()
	game.deep_sky.state.award_samples(80)
	game.deep_sky.state.acquisition_seed = 314159
	popup.open_draw()
	window.begin_draw()
	window.set_process(false)
	var id: String = game.deep_sky.state.last_draw
	for locale in ["en", "ko"]:
		_set_locale(game, locale)
		window.drawing = true
		window.elapsed = 0.45
		window.refresh()
		await _capture(game, locale + "_draw_scan")
		window.elapsed = 1.25
		window.refresh()
		await _capture(game, locale + "_draw_align")
		window.finish_reveal()
		await _capture(game, locale + "_draw_result")
	game.deep_sky.modules.grant_copy(id)
	popup.show_loadout()
	popup.owned_buttons[id].pressed.emit()
	popup.owned_buttons[id].pressed.emit()
	for locale in ["en", "ko"]:
		_set_locale(game, locale)
		await _capture(game, locale + "_popup_duplicate")
	popup.close()
	# Paint every figure in its actual chart focus pose, with completed research.
	progressed = true
	while progressed:
		progressed = false
		for research_id in game.deep_sky.Data.RESEARCH_ORDER:
			if game.deep_sky.can_purchase(research_id):
				progressed = game.deep_sky.purchase(research_id) or progressed
	if game.deep_sky.state.research_ids.size() != 60: failures.append("not all outer research purchased")
	for locale in ["en", "ko"]:
		_set_locale(game, locale)
		for figure in game.upgrade_tree.ExtensionChart.ORDER:
			game.upgrade_tree.focus_constellation(figure)
			await _capture(game, locale + "_chart_" + figure)
		game.upgrade_tree.focus_outer_constellations()
		await _capture(game, locale + "_chart_overview")
	for module_id in game.deep_sky.Modules.DEFINITIONS: game.deep_sky.modules.grant(module_id)
	popup.open()
	for module_id in ["focus", "capture_hold", "precision"]: game.deep_sky.equip(module_id)
	for locale in ["en", "ko"]:
		_set_locale(game, locale)
		await _capture(game, locale + "_popup_five_slots")
	popup.close()
	game.upgrade_tree.close_tree()
	game.observation_phase_remaining = 46.0
	game.hud.set_observation_phase(game.observation_round, 46.0, 60.0)
	var director: Node = game.deep_sky.director
	director.end_round()
	director._ensure_ticket("n/preview", "rare", "natural")
	director._spawn_component({"ticket": "n/preview", "kind": "rare", "origin_kind": "natural", "component": 0, "start": Vector2(0.3, 0.45), "end": Vector2(0.67, 0.56)})
	var target: Node = director.targets()[0]
	target.set_process(false)
	target.simulate_tick(3.5)
	target.stage_progress = 0.4
	game.effects.reset()
	for locale in ["en", "ko"]:
		_set_locale(game, locale)
		target.queue_redraw()
		game.hud._refresh_extension()
		game.hud.set_tracking(0.4, "anomaly_rare", 1.0, 1, game.observation_view.world_to_screen(target.global_position), 26.0, 0.8)
		await _capture(game, locale + "_rare_meteor")
	if source != Capture.source_snapshot(failures): failures.append("source changed during capture")
	var manifest := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "source": source, "frames": records, "failures": failures, "synthetic": true}, "\t"))
	manifest.close()
	game.free()
	paused = false
	await process_frame
	if failures.is_empty() and records.size() == 36:
		print("EXPANSION_PREVIEW_PASS: 36 frames at " + ProjectSettings.globalize_path(output))
		quit(0)
	else:
		push_error(str(failures))
		quit(1)
