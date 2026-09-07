extends "res://tests/deep_sky_preview.gd"

const Expansion = preload("res://scripts/expansion_data.gd")

func _run() -> void:
	create_timer(60.0, true, false, true).timeout.connect(func(): push_error("Expansion preview timeout"); quit(1))
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	root.gui_disable_input = true
	var source := Capture.source_snapshot(failures)
	output = "res://build/expansion_review/%d" % int(Time.get_unix_time_from_system())
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
	game.progression.observation_data = 1680000000.0
	for id in ["ext_trace_study", "ext_sweep_study", "ext_link_study"]:
		game.deep_sky.purchase(id)
	game.deep_sky.state.award_samples(24, game.deep_sky.modules.purchased)
	game.deep_sky.begin_analysis()
	game.effects.reset()
	_freeze(game)
	var chart: Control = game.upgrade_tree.deep_sky_chart
	for locale in ["en", "ko"]:
		_set_locale(game, locale)
		chart.select("ext_trace_advanced")
		await _capture(game, locale + "_research")
		chart._set_view(chart.View.PLANS)
		await _capture(game, locale + "_plans")
		chart._set_view(chart.View.ANALYSIS)
		await _capture(game, locale + "_analysis_pending")
	game.deep_sky.state.pending_offer.clear()
	for id in game.deep_sky.Modules.DEFINITIONS:
		game.deep_sky.modules.grant(id)
	game.deep_sky.modules.unlocked_slots = 5
	game.module_popup.open()
	for id in ["focus", "trail_integrator", "relay_bus", "long_baseline", "reference_bus"]:
		game.deep_sky.equip(id)
	for locale in ["en", "ko"]:
		_set_locale(game, locale)
		game.module_popup.show_module_tooltip("trail_integrator")
		await _capture(game, locale + "_popup_full_catalogue")
	game.module_popup.inventory_scroll.scroll_vertical = 10000
	game.module_popup.hide_tooltip()
	await _capture(game, "ko_popup_catalogue_bottom")
	game.module_popup.close()
	game.upgrade_tree.close_tree()
	game.spawner.reset()
	game.observation_phase_remaining = 46.0
	game.hud.set_observation_phase(game.observation_round, 46.0, 60.0)
	game.deep_sky.state.select_plan("plan_sweep_1")
	game.deep_sky.state.prepare_from_bank()
	var director: Node = game.deep_sky.director
	for index in range(3):
		var kind: String = ["spectrum", "afterglow", "pair"][index]
		var id := "n/preview_%d" % index
		director._ensure_ticket(id, kind, "natural")
		director._spawn_component({"ticket": id, "event_id": id, "kind": kind, "origin_kind": "natural", "component": 0, "start": Vector2(0.22 + index * 0.25, 0.50), "end": Vector2(0.29 + index * 0.25, 0.56)})
	for target in director.targets():
		target.set_process(false)
		target._process(target.warning_time + 0.2)
		if target.kind == "spectrum":
			target.stage = 1
			target.stage_progress = 0.25
			target._update_position(0.0)
			target.queue_redraw()
	game.hud._refresh_extension()
	game.effects.reset()
	for locale in ["en", "ko"]:
		_set_locale(game, locale)
		for target in director.targets(): target.queue_redraw()
		game.hud.set_tracking(0.25, "anomaly_spectrum", 1.0, 1, Vector2(334, 333), 26.0, 0.8)
		await _capture(game, locale + "_anomaly_sky")
	game.hud.hide_tracking()
	director.end_round()
	for plan in Expansion.PLAN_ORDER:
		for field in game.deep_sky.state.records[plan]:
			field.prepared = true
			field.complete = true
	for id in Expansion.RESEARCH_ORDER:
		if id not in game.deep_sky.state.research_ids: game.deep_sky.state.research_ids.append(id)
	game.deep_sky.state.record_complete = true
	game.deep_sky.state.selected_plan = "plan_integrated_1"
	game.deep_sky.target.queue_redraw()
	game.upgrade_tree.open_tree()
	for locale in ["en", "ko"]:
		_set_locale(game, locale)
		chart.select("ext_record_complete")
		await _capture(game, locale + "_record_complete")
	game.upgrade_tree.close_tree()
	game.hud.set_upgrade_phase(game.observation_round)
	for locale in ["en", "ko"]:
		_set_locale(game, locale)
		game.hud.show_phase_summary({"round": 4, "duration": 60.0, "data": 168000000, "rate": 168000000.0, "observations": 24, "manual": 9, "automatic": 15, "modules_acquired": ["trail_integrator", "sweep_optics", "relay_bus"], "extension_research_acquired": ["ext_protocol", "ext_trace_study", "ext_sweep_study", "ext_link_study"]}, {}, "equipment_changed", true)
		await _capture(game, locale + "_growth_summary")
	if source != Capture.source_snapshot(failures): failures.append("source changed during capture")
	var manifest := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "source": source, "frames": records, "failures": failures, "synthetic": true}, "\t"))
	manifest.close()
	game.free()
	paused = false
	await process_frame
	if failures.is_empty() and records.size() == 15:
		print("EXPANSION_PREVIEW_PASS: 15 frames at " + ProjectSettings.globalize_path(output))
		quit(0)
	else:
		push_error(str(failures))
		quit(1)
