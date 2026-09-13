extends "res://tests/module_overhaul_review.gd"

# Actual game chart, save-free. One focused frame per figure, plus the two
# ordinary navigation views. Focus rotation is retained; no marker is moved.
func _run() -> void:
	create_timer(80.0, true, false, true).timeout.connect(func(): push_error("Geometry preview timeout"); quit(1))
	if DisplayServer.get_name() == "headless": quit(1); return
	root.gui_disable_input = true
	var game := await _game()
	var tree = game.upgrade_tree
	for id in game.deep_sky.Data.RESEARCH_ORDER:
		if id not in game.deep_sky.state.research_ids: game.deep_sky.state.research_ids.append(id)
	tree.configure_galactic_state(true, true)
	tree.open_tree()
	await process_frame
	_freeze(game)
	output = "res://build/constellation_geometry_review/%d" % int(Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var positions := {}
	for cid in tree.chart_constellations:
		tree.focus_constellation(cid)
		var bounds := Rect2()
		var first := true
		for star in tree.chart_constellations[cid].stars:
			var point: Vector2 = tree.star_positions[cid + "/" + star.id]
			if first: bounds = Rect2(point, Vector2.ZERO); first = false
			else: bounds = bounds.expand(point)
		tree.zoom = minf(1.65, minf(530.0 / bounds.size.x, 300.0 / bounds.size.y))
		tree.pan_position = Vector2(560, 330) - bounds.get_center() * tree.zoom
		tree._layout_chart()
		tree._apply_transform()
		await _capture(game, cid)
		var frame := root.get_texture().get_image()
		for segment in tree.chart_constellations[cid].segments:
			var start: Vector2 = tree.tree_canvas.get_global_transform() * tree.star_positions[cid + "/" + segment[0]]
			var finish: Vector2 = tree.tree_canvas.get_global_transform() * tree.star_positions[cid + "/" + segment[1]]
			if start.distance_to(finish) < 24.0: continue
			var mid := Vector2i((start + finish) * 0.5)
			var ink := 0.0
			for x in range(-2, 3):
				for y in range(-2, 3): ink = maxf(ink, frame.get_pixelv(mid + Vector2i(x, y)).r)
			if ink < 0.08: failures.append("missing rendered segment: " + cid + "/" + str(segment))
		positions[cid] = {}
		for star in tree.chart_constellations[cid].stars:
			var point: Vector2 = tree.tree_canvas.get_global_transform() * tree.star_positions[cid + "/" + star.id]
			positions[cid][star.id] = [point.x, point.y]
			if not Rect2(180, 130, 720, 410).has_point(point): failures.append("clipped figure: " + cid + "/" + star.id)
	tree._reset_view(false)
	await _capture(game, "normal_overview")
	tree.focus_outer_constellations()
	await _capture(game, "outer_overview")
	if "--legacy-scale" in OS.get_cmdline_user_args():
		for cid in tree.ChartData.CONSTELLATIONS:
			tree.focus_constellation(cid)
			await _capture(game, "natural_focus_" + cid)
	if "--outer-celestial" in OS.get_cmdline_user_args():
		for locale in ["ko", "en"]:
			_set_locale(game, locale)
			for cid in ["sagitta", "cancer", "sagittarius"]:
				tree.focus_constellation(cid)
				await _capture(game, locale + "_focus_" + cid)
	if "--node-spacing" in OS.get_cmdline_user_args():
		_set_locale(game, "ko")
		tree.configure_galactic_state(false, false)
		for cid in ["andromeda", "big_dipper", "orion", "taurus"]:
			tree.focus_constellation(cid)
			await _capture(game, "unexpanded_" + cid)
		game.progression.purchased_nodes.erase("galaxy_imaging")
		tree.focus_constellation("andromeda")
		tree._on_node_hovered("galaxy_imaging")
		tree.node_hold_bars.galaxy_imaging.set_fill_progress(0.5, 0.0)
		await _capture(game, "andromeda_research_hold")
	var manifest := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"positions": positions, "frames": records, "failures": failures, "synthetic": true}, "\t"))
	manifest.close()
	game.free()
	paused = false
	_finish("CONSTELLATION_GEOMETRY_REVIEW", "%d frames at " % records.size() + ProjectSettings.globalize_path(output))
