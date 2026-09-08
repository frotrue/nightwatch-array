extends "res://tests/deep_sky_preview.gd"

func _capture(game: Node, name: String) -> void:
	_freeze(game)
	await super._capture(game, name)

func _run() -> void:
	create_timer(60.0, true, false, true).timeout.connect(func(): push_error("Constellation preview timeout"); quit(1))
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	root.gui_disable_input = true
	var source := Capture.source_snapshot(failures)
	output = "res://build/constellation_review/%d" % int(Time.get_unix_time_from_system())
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
	var tree: Node = game.upgrade_tree
	tree.configure_galactic_state(true, true)
	tree.open_tree()
	await process_frame
	game.progression.observation_data = 1680000000.0
	_freeze(game)
	for locale in ["en", "ko"]:
		_set_locale(game, locale)
		tree.focus_outer_constellations()
		tree.selected_node_id = "ext_trace_study"
		tree._refresh()
		await _capture(game, locale + "_atlas_revealed")
	game.deep_sky.target._process(0.0)
	game.deep_sky.target.apply_manual_observation(10.0, 0.0, 100.0)
	for id in ["ext_trace_study", "ext_sweep_study", "ext_link_study", "focus", "wide"]:
		game.deep_sky.purchase(id)
	for locale in ["en", "ko"]:
		_set_locale(game, locale)
		tree.focus_outer_constellations()
		tree.selected_node_id = "ext_trace_study"
		tree._refresh()
		await _capture(game, locale + "_atlas_started")
		tree.select_extension("precision")
		await _capture(game, locale + "_cygnus_partial")
		tree._on_node_hold_started("precision")
		tree._process(tree.HOLD_PURCHASE_SECONDS * 0.5)
		await _capture(game, locale + "_star_hold")
		tree._on_node_hold_released("precision")
		game.deep_sky.state.award_samples(24)
		game.module_popup.open_draw()
		await _capture(game, locale + "_popup_draw")
		game.module_popup.draw_window.begin_draw()
		game.module_popup.draw_window.finish_reveal()
		await _capture(game, locale + "_popup_result")
		game.module_popup.close()
	for id in game.deep_sky.Data.RESEARCH_ORDER:
		if id not in game.deep_sky.state.research_ids: game.deep_sky.state.research_ids.append(id)
	for id in game.deep_sky.Modules.DEFINITIONS: game.deep_sky.modules.grant(id)
	game.deep_sky.modules.unlocked_slots = 5
	for locale in ["en", "ko"]:
		_set_locale(game, locale)
		tree.focus_outer_constellations()
		tree.selected_node_id = "ext_record_complete"
		tree._refresh()
		await _capture(game, locale + "_atlas_complete")
	if source != Capture.source_snapshot(failures): failures.append("source changed during capture")
	var manifest := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "source": source, "frames": records, "failures": failures, "synthetic": true}, "\t"))
	manifest.close()
	game.free()
	paused = false
	await process_frame
	if failures.is_empty() and records.size() == 14:
		print("CONSTELLATION_EXTENSION_PREVIEW_PASS: 14 frames at " + ProjectSettings.globalize_path(output))
		quit(0)
	else:
		push_error(str(failures))
		quit(1)
