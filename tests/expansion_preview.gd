extends "res://tests/deep_sky_preview.gd"

func _run() -> void:
	create_timer(60.0, true, false, true).timeout.connect(func(): push_error("Expansion preview timeout"); quit(1))
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	root.gui_disable_input = true
	var source := Capture.source_snapshot(failures)
	output = "res://build/module_draw_review/%d" % int(Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var game: Node = load("res://scenes/main.tscn").instantiate()
	Fixtures.configure_before_ready(game)
	root.add_child(game)
	await process_frame
	var progressed := true
	while progressed:
		progressed = false
		for definition in Balance.UPGRADE_NODES:
			if definition.branch != "local_group" and not game.progression.has_upgrade(definition.id):
				progressed = game.progression.debug_purchase_node(definition.id) or progressed
	game.spawner.reset()
	game.galactic_pullback_seen = true
	game.upgrade_tree.configure_galactic_state(true, true)
	game.deep_sky.target._process(0.0)
	game.deep_sky.target.apply_manual_observation(10.0, 0.0, 100.0)
	game.upgrade_tree.open_tree()
	game.progression.observation_data = 5000000000.0
	game.effects.reset()
	_freeze(game)
	for locale in ["en", "ko"]:
		_set_locale(game, locale)
		game.upgrade_tree.focus_outer_constellations()
		game.upgrade_tree.select_extension("ext_trace_advanced")
		await _capture(game, locale + "_research")
		game.module_popup.open()
		await _capture(game, locale + "_popup_empty")
		game.module_popup.close()
	game.deep_sky.state.award_samples(80)
	game.deep_sky.state.acquisition_seed = 314159
	game.module_popup.open()
	game.module_popup.draw_button.pressed.emit()
	var id: String = game.deep_sky.state.last_draw
	game.deep_sky.modules.grant_copy(id)
	game.module_popup.refresh()
	game.module_popup.owned_buttons[id].pressed.emit()
	game.module_popup.owned_buttons[id].pressed.emit()
	for locale in ["en", "ko"]:
		_set_locale(game, locale)
		await _capture(game, locale + "_popup_duplicate")
		game.module_popup.show_module_tooltip(id)
		await _capture(game, locale + "_popup_duplicate_tooltip")
		game.module_popup.hide_tooltip()
	game.module_popup.close()
	for research_id in game.deep_sky.Data.RESEARCH_ORDER:
		if not game.deep_sky.research_owned(research_id): game.deep_sky.purchase(research_id)
	for research_id in game.deep_sky.Modules.RESEARCH_IDS:
		if not game.deep_sky.research_owned(research_id): game.deep_sky.purchase(research_id)
	for module_id in game.deep_sky.Modules.DEFINITIONS: game.deep_sky.modules.grant(module_id)
	game.module_popup.open()
	for module_id in ["focus", "relay_bus", "reference_bus"]: game.deep_sky.equip(module_id)
	game.module_popup.inventory_scroll.scroll_vertical = 10000
	for locale in ["en", "ko"]:
		_set_locale(game, locale)
		await _capture(game, locale + "_popup_five_slots")
	game.module_popup.close()
	game.upgrade_tree.close_tree()
	game.observation_phase_remaining = 46.0
	game.hud.set_observation_phase(game.observation_round, 46.0, 60.0)
	var director: Node = game.deep_sky.director
	director.end_round()
	director._ensure_ticket("n/preview", "rare", "natural")
	director._spawn_component({"ticket": "n/preview", "kind": "rare", "origin_kind": "natural", "component": 0, "start": Vector2(0.3, 0.45), "end": Vector2(0.67, 0.56)})
	var target: Node = director.targets()[0]
	target.set_process(false)
	target._process(3.5)
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
	if failures.is_empty() and records.size() == 12:
		print("EXPANSION_PREVIEW_PASS: 12 frames at " + ProjectSettings.globalize_path(output))
		quit(0)
	else:
		push_error(str(failures))
		quit(1)
