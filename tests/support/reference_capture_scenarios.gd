extends RefCounted

# Scenario construction only. The driver owns files, rendering and provenance.
# Synthetic inputs use production nodes/routes, but do not measure game pacing.
const MainScene = preload("res://scenes/main.tscn")
const Fixtures = preload("res://tests/effect_feedback_test.gd")
const Balance = preload("res://scripts/game_balance.gd")
const ChartData = preload("res://scripts/research_chart_data.gd")
const VIEWPORT := Vector2(1152.0, 648.0)
const SEED := 7331
const METEOR_STEP := 1.0 / 60.0
const METEOR_STEPS := 30
const REFERENCE_COMPLETED_CONSTELLATIONS := [
	"cassiopeia", "big_dipper", "orion", "andromeda", "perseus", "lyra",
	"gemini", "taurus", "leo", "ursa_minor",
]
const DIRECTIONAL_SPECIMENS := [
	["common", Vector2(60, 155), Vector2(170, 10), Vector2(1090, 215.6)],
	["fast", Vector2(255, 225), Vector2(285, 14), Vector2(1090, 266)],
	["fragment", Vector2(70, 300), Vector2(205, -8), Vector2(1090, 260.2)],
	["fragment_piece", Vector2(500, 365), Vector2(235, 12), Vector2(1090, 395.1)],
	["fireball", Vector2(140, 445), Vector2(155, -10), Vector2(1090, 383.7)],
	["major", Vector2(610, 530), Vector2(105, -6), Vector2(1090, 502.6)],
]
const SPECIAL_SPECIMENS := [
	["comet", Vector2(70, 170), Vector2(120, 8), Vector2(1090, 225)],
	["satellite", Vector2(240, 260), Vector2(150, 6), Vector2(1090, 300)],
	["variable_star", Vector2(120, 350), Vector2(135, -6), Vector2(1090, 315)],
	["binary_star", Vector2(430, 440), Vector2(160, 10), Vector2(1090, 470)],
	["galaxy", Vector2(210, 530), Vector2(110, -8), Vector2(1090, 490)],
]
const SCENARIOS := [
	{"id": "observation_hud", "stage": "opening", "density": "one_target", "overlays": ["tracking"], "note": "Real fast target and cursor gauge at synthetic 67% progress; fixed 0.5-second meteor pose.", "expected": {"meteors": 1, "installed": 0, "tracking": true, "span": 1.0}},
	{"id": "observation_hud_dense", "stage": "constellation_specimens", "density": "eleven_targets", "overlays": ["tracking"], "note": "Synthetic eleven-identity density plate, without research automation; major target tracked at 42%.", "expected": {"meteors": 11, "installed": 0, "tracking": true, "span": 1.0}},
	{"id": "meteor_family_directional", "stage": "constellation_specimens", "density": "six_targets", "overlays": [], "note": "Six authored directional specimens, aged by 30 fixed 1/60-second steps; 30-second diagnostic lifetimes.", "expected": {"meteors": 6, "installed": 0, "tracking": false, "span": 1.0}},
	{"id": "meteor_family_special", "stage": "constellation_specimens", "density": "five_targets", "overlays": [], "note": "Five authored special specimens at the same fixed pose and diagnostic lifetime.", "expected": {"meteors": 5, "installed": 0, "tracking": false, "span": 1.0}},
	{"id": "sky_sweep", "stage": "opening", "density": "empty_sky", "overlays": ["sweep"], "note": "Purchased Sky Sweep, 210/460 pixels of blank-sky charge; no summon roll yet.", "expected": {"meteors": 0, "installed": 1, "tracking": false, "span": 1.0}},
	{"id": "round_summary", "stage": "intermission", "density": "empty_sky", "overlays": ["summary"], "note": "Synthetic fifth-round results through the production summary renderer.", "expected": {"meteors": 0, "installed": 0, "tracking": false, "span": 1.0}},
	{"id": "research_chart", "stage": "constellation", "density": "81_of_107_research", "overlays": ["chart", "constellation_inspector"], "note": "Existing reference build: ten completed constellations plus three Canis nodes; canis_capacity_ii selected.", "expected": {"meteors": 0, "installed": 81, "tracking": false, "span": 1.0}},
	{"id": "galactic_sky", "stage": "galactic", "density": "two_hosts_two_phenomena", "overlays": [], "note": "Full research, two idle hosts and two supernovae at six explicit seconds; no atmospheric specimens.", "expected": {"meteors": 0, "installed": 107, "tracking": false, "span": 1.477455443789063}},
	{"id": "exoplanet_transit", "stage": "galactic", "density": "two_hosts_two_phenomena", "overlays": [], "note": "Full research; first host's first transit window at exactly 48%, without a simulated completion.", "expected": {"meteors": 0, "installed": 107, "tracking": false, "span": 1.477455443789063}},
	{"id": "local_group_chart", "stage": "galactic_chart", "density": "107_of_107_research", "overlays": ["chart", "galactic_inspector"], "note": "Completed research, finished production pull-back, LMC inspector selected; decorations remain non-research.", "expected": {"meteors": 0, "installed": 107, "tracking": false, "span": 1.477455443789063}},
	{"id": "catalogue_ending", "stage": "ending_preview", "density": "completed_catalogue", "overlays": ["ending"], "note": "Synthetic completed-run statistics through the non-persistent production debug reveal, stepped 8.1 seconds.", "expected": {"meteors": 0, "installed": 107, "tracking": false, "span": 1.477455443789063}},
]

class NoPersistence:
	extends Fixtures.NoSaveSlots

	func load_slot(_slot: int) -> Dictionary:
		return {}

	func reset_slot(_slot: int) -> Error:
		return ERR_UNAVAILABLE

	func set_save_directory(_path: String) -> void:
		pass

var failures: Array[String] = []


func prepare(tree: SceneTree, id: String) -> Node:
	if _definition(id).is_empty():
		failures.append("Unknown reference scenario: " + id)
		return null
	tree.paused = false
	tree.root.gui_disable_input = true
	var game: Node = MainScene.instantiate()
	game.startup_slot_prompt_enabled = false
	game.get_node("Tutorial").auto_start_enabled = false
	_replace_child(game, "SaveGameController", NoPersistence.new())
	_replace_child(game, "GameSettings", Fixtures.NoSettings.new())
	tree.root.add_child(game)
	# No process/input frame may run between _ready and this first freeze.
	freeze(game)
	game.sound.free()
	game.sound = Fixtures.SilentSound.new()
	game.add_child(game.sound)
	game.spawner.running = false
	game.events.running = false
	game.spawner.rng.seed = SEED
	game.spawner.forecast_rng.seed = SEED + 1
	game.spawner.warm_contact_rng.seed = SEED + 2
	game.spawner.echo_rng.seed = SEED + 3
	game.events.rng.seed = SEED + 4
	game.effects.rng.seed = SEED + 5
	game.observer.visible = false
	game.observer.cursor_position = VIEWPORT * 0.5
	game.observer.previous_cursor_position = game.observer.cursor_position
	game.get_node("TwinkleStars").time = 0.0
	game.get_node("TwinkleStars").redraw_accumulator = 0.0
	game.progression.add_debug_data(1284000.0)
	game.hud.hide_tracking()
	game.hud.set_observation_phase(3, 24.0, 40.0)
	match id:
		"observation_hud":
			var target = _spawn(game, ["fast", Vector2(470, 300), Vector2(285, 14), Vector2(1090, 340)])
			_track(game, target, 0.67)
		"observation_hud_dense":
			for specimen in DIRECTIONAL_SPECIMENS + SPECIAL_SPECIMENS:
				_spawn(game, specimen)
			game.hud.set_observation_phase(9, 18.0, 60.0)
			_track(game, _meteor_of_type(game, "major"), 0.42)
		"meteor_family_directional":
			for specimen in DIRECTIONAL_SPECIMENS:
				_spawn(game, specimen)
		"meteor_family_special":
			for specimen in SPECIAL_SPECIMENS:
				_spawn(game, specimen)
		"sky_sweep":
			_buy_nodes(game, ["polar_survey"])
			game.survey.begin_round(3)
			var point := Vector2(560, 420)
			game.survey.set_scanning(true, point)
			game.survey.apply_scan_segment(point - Vector2(210, 0), point)
			game.observer.visible = true
			game.observer.cursor_position = point
			game.observer.previous_cursor_position = point
			game.observer.was_holding = true
			game.observer.interaction_mode = game.observer.InteractionMode.SCANNING
		"round_summary":
			game.hud.show_phase_summary(
				{"round": 5, "data": 1284000, "duration": 60.0, "rate": 1284000.0, "observations": 147, "manual": 91, "automatic": 56},
				{"round": 4, "data": 1068000, "duration": 60.0, "rate": 1068000.0, "observations": 131, "manual": 84, "automatic": 47},
				"comparison", true)
		"research_chart":
			_buy_nodes(game, _reference_research())
			game.upgrade_tree.set_intermission_context(5, 80)
			game.upgrade_tree.open_tree()
		"galactic_sky", "exoplanet_transit", "local_group_chart", "catalogue_ending":
			var all_nodes: Array[String] = []
			for definition in Balance.UPGRADE_NODES:
				all_nodes.append(String(definition.id))
			_buy_nodes(game, all_nodes)
			game._sync_galactic_systems()
			game.galactic_phenomena.advance_time(6.0)
			if id == "exoplanet_transit":
				game.host_stars.advance_time(game.host_stars.next_transit_remaining)
				game.host_stars.advance_time(game.host_stars.TRANSIT_WINDOW * 0.48)
			elif id == "local_group_chart":
				game.upgrade_tree.open_tree()
			elif id == "catalogue_ending":
				for target_id in game.galactic_phenomena.TARGET_SPECS:
					game.galactic_phenomena.completed_targets[target_id] = true
				game.galactic_phenomena.refresh_unlock_state()
				game.elapsed_time = 3040.0
				game.observation_round = 61
				game.progression.success_count = 2100
				game.progression.manual_successes = 1200
				game.progression.automatic_successes = 900
				game.progression.total_data_earned = 42000000000.0
				game._show_catalogue_ending_debug_preview()
	game.progression.observation_data = 1284000.0
	game.hud._refresh_progression()
	# Layout/deferred refresh is allowed; simulation, input and tweens are not.
	await _settle(tree, game)
	if id == "research_chart":
		game.upgrade_tree.rotation_offset = 0.0
		game.upgrade_tree._layout_chart()
		game.upgrade_tree._on_node_hovered("canis_capacity_ii")
	elif id == "local_group_chart":
		game.upgrade_tree._finish_galactic_pullback()
		game.upgrade_tree._on_node_hovered("lmc_transit_watch")
	elif id == "catalogue_ending":
		var reveal: Tween = game.hud.end_reveal_tween
		if reveal == null or not reveal.is_valid():
			failures.append(id + ": missing production reveal tween")
		else:
			reveal.custom_step(8.1)
	for tween in tree.get_processed_tweens():
		if tween.is_valid():
			tween.custom_step(10.0)
	# Bulk setup is not a new research/rare event in the chosen reference pose.
	game.hud.banner_root.visible = false
	game.hud.banner_timer = 0.0
	game.hud.banner_rule.scale = Vector2.ONE
	game.effects.reset()
	for star in game.host_stars.host_stars:
		star.visual_age = 0.0
		star._process(1.0)
	for target in game.galactic_phenomena.get_children():
		if target.has_method("get_stage") and "capture_time_override_msec" in target:
			target.set("capture_time_override_msec", 0.0)
	await _settle(tree, game)
	for visual in game.upgrade_tree.node_hold_bars.values():
		visual.pulse_phase = 0.0
	game.observation_view.force_update_scroll()
	freeze(game)
	_queue_draws(game)
	return game


func inspect(game: Node, id: String) -> Dictionary:
	var definition := _definition(id)
	if game == null or definition.is_empty():
		failures.append(id + ": missing game/scenario")
		return {}
	var expected: Dictionary = definition.expected
	var meteors: Array[Dictionary] = []
	var types: Array[String] = []
	for meteor in game.meteor_layer.get_children():
		types.append(String(meteor.type_id))
		meteors.append({"type": String(meteor.type_id), "position": _point(meteor.position), "age": meteor.age, "alive": meteor.alive, "trail_points": meteor.trail_points.size(), "progress": meteor.observation_progress})
	types.sort()
	var overlays: Array[String] = []
	if game.hud.tracking_cluster.is_visible_in_tree(): overlays.append("tracking")
	if game.survey.scanning and game.observer.visible: overlays.append("sweep")
	if game.hud.phase_summary_overlay.is_visible_in_tree(): overlays.append("summary")
	if game.upgrade_tree.is_open():
		overlays.append("chart")
		if game.upgrade_tree.tooltip_panel.is_visible_in_tree(): overlays.append("constellation_inspector")
		if game.upgrade_tree.galactic_panel.is_visible_in_tree(): overlays.append("galactic_inspector")
	if game.hud.end_overlay.is_visible_in_tree(): overlays.append("ending")
	if game.hud.settings_overlay.is_visible_in_tree(): overlays.append("settings")
	if game.hud.startup_overlay.is_visible_in_tree(): overlays.append("startup")
	if game.hud.banner_root.is_visible_in_tree(): overlays.append("banner")
	var hosts: Array[Dictionary] = []
	for star in game.host_stars.host_stars:
		hosts.append({"id": star.stable_star_id, "profile": star.profile_id, "state": star.state, "position": _point(star.position), "visual_age": star.visual_age, "transit_phase": star.transit_phase_ratio})
	var phenomena: Array[Dictionary] = []
	for target in game.galactic_phenomena.get_children():
		phenomena.append({"id": String(target.target_id), "stage": String(target.get_stage()) if target.has_method("get_stage") else "lens", "position": _point(target.position), "visual_time_msec": target.capture_time_override_msec})
	var active_processes: Array[String] = []
	_find_active_processes(game, active_processes)
	var running_tweens := 0
	for tween in game.get_tree().get_processed_tweens():
		if tween.is_running(): running_tweens += 1
	var state := {
		"id": id, "locale": TranslationServer.get_locale(), "viewport": _point(game.get_viewport_rect().size),
		"installed": game.progression.upgrade_level, "data": game.progression.observation_data,
		"span": game.observation_view.observation_span, "meteors": meteors, "meteor_types": types,
		"overlays": overlays, "tracking_type": game.hud.last_tracking_target_type,
		"tracking_progress_percent": game.hud.last_tracking_progress_percent,
		"tracking_target_valid": game.observer._selection_is_valid(),
		"cursor": _point(game.observer.cursor_position), "survey_charge": game.survey.get_charge_progress(),
		"chart_mode": game.upgrade_tree.galactic_mode, "chart_rotation": game.upgrade_tree.rotation_offset,
		"chart_selection": game.upgrade_tree.selected_node_id, "galaxy_selection": game.upgrade_tree.galactic_inspector_node_id,
		"hosts": hosts, "phenomena": phenomena, "phenomena_recorded": game.galactic_phenomena.get_completed_record_count(),
		"ending_complete": game.hud.end_reveal_complete, "ending_debug_preview": game.catalogue_ending_debug_preview,
		"ending_map_progress": [game.hud.end_coda.constellation_progress, game.hud.end_coda.pullback_progress, game.hud.end_coda.route_progress, game.hud.end_coda.illumination_progress, game.hud.end_coda.settle_progress],
		"active_processes": active_processes, "running_tweens": running_tweens,
		"paused": game.get_tree().paused, "isolated": game.save_games is NoPersistence and game.settings is Fixtures.NoSettings,
		"twinkle_time": game.get_node("TwinkleStars").time,
	}
	_check(game.get_viewport_rect().size.is_equal_approx(VIEWPORT), id, "viewport must be 1152x648")
	_check(state.locale == "en" and state.isolated and game.active_save_slot == 0, id, "isolated English slot-zero fixture")
	_check(state.installed == int(expected.installed), id, "research count differs from contract")
	_check(is_equal_approx(float(state.span), float(expected.span)), id, "observation span differs from contract")
	_check(meteors.size() == int(expected.meteors), id, "meteor count differs from contract")
	_check(overlays == definition.overlays, id, "overlay stack differs from contract: " + str(overlays))
	_check(state.tracking_target_valid == bool(expected.tracking), id, "tracking is not backed by the expected real target")
	_check(active_processes.is_empty() and running_tweens == 0 and state.paused, id, "scene clocks or input are not frozen")
	_check(game.get_tree().root.gui_disable_input, id, "GUI input must be disabled")
	var expected_types: Array[String] = []
	if id == "observation_hud": expected_types.append("fast")
	if id in ["observation_hud_dense", "meteor_family_directional"]:
		for specimen in DIRECTIONAL_SPECIMENS: expected_types.append(String(specimen[0]))
	if id in ["observation_hud_dense", "meteor_family_special"]:
		for specimen in SPECIAL_SPECIMENS: expected_types.append(String(specimen[0]))
	expected_types.sort()
	_check(types == expected_types, id, "meteor identities differ from contract")
	for meteor in meteors:
		_check(bool(meteor.alive) and is_equal_approx(float(meteor.age), METEOR_STEP * METEOR_STEPS) and int(meteor.trail_points) > 1, id, "specimen must be alive at the fixed age with a real trail")
	if id == "sky_sweep":
		_check(is_equal_approx(float(state.survey_charge), 210.0 / 460.0) and game.survey.roll_count == 0, id, "sweep charge or roll count differs")
	if id == "research_chart":
		_check(state.chart_selection == "canis_capacity_ii" and is_zero_approx(float(state.chart_rotation)), id, "reference inspector/rotation differs")
	if id in ["galactic_sky", "exoplanet_transit", "local_group_chart"]:
		_check(hosts.size() == 2 and phenomena.size() == 2, id, "full research must expose two hosts and two phenomena")
		for target in phenomena:
			_check(is_zero_approx(float(target.visual_time_msec)), id, "supernova visual clock must be deterministic")
	if id == "exoplanet_transit":
		_check(not hosts.is_empty() and hosts[0].state == "transiting" and is_equal_approx(float(hosts[0].transit_phase), 0.48), id, "primary transit must be at exactly 48%")
	if id == "local_group_chart":
		_check(state.chart_mode == game.upgrade_tree.GALACTIC_MODE_FINAL and state.galaxy_selection == "lmc_transit_watch", id, "final galaxy map/LMC inspector not active")
	if id == "catalogue_ending":
		_check(state.ending_complete and state.ending_debug_preview and state.phenomena_recorded == 5, id, "completed catalogue reveal is missing")
		for value in state.ending_map_progress:
			_check(is_equal_approx(float(value), 1.0), id, "ending map has not reached its final pose")
	return state


func freeze(game: Node) -> void:
	_freeze_node(game)
	for tween in game.get_tree().get_processed_tweens():
		if tween.is_valid(): tween.pause()
	game.get_tree().paused = true


func _freeze_node(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	node.set_process_unhandled_key_input(false)
	for child in node.get_children(): _freeze_node(child)


func _settle(tree: SceneTree, game: Node) -> void:
	for _frame in range(4):
		freeze(game)
		await tree.process_frame
	freeze(game)


func _spawn(game: Node, specimen: Array):
	var meteor = game.spawner.spawn_meteor(String(specimen[0]), specimen[1], specimen[2], 30.0, specimen[3])
	if meteor == null:
		failures.append("Could not create specimen: " + String(specimen[0]))
		return null
	_freeze_node(meteor)
	for _step in range(METEOR_STEPS): meteor._process(METEOR_STEP)
	return meteor


func _track(game: Node, target, progress: float) -> void:
	if target == null: return
	target.observation_progress = progress
	target.manual_touched = true
	target.manual_tracking_time = 1.0
	target.quality_integral = 0.8
	game.observer.visible = true
	game.observer.selected_meteor = target
	game.observer.tracked_meteors = [target]
	game.observer.cursor_position = target.global_position
	game.observer.previous_cursor_position = target.global_position
	game.observer.was_holding = true
	game.observer.interaction_mode = game.observer.InteractionMode.TRACKING
	game.hud.set_tracking(progress, String(target.type_id), target.get_predicted_multiplier(), 1, target.global_position, game.progression.get_tracking_radius())


func _buy_nodes(game: Node, requested: Array) -> void:
	var pending: Array = requested.duplicate()
	game.progression.add_debug_data(1000000000000.0)
	while not pending.is_empty():
		var bought := false
		for index in range(pending.size() - 1, -1, -1):
			if not game.progression.can_purchase(String(pending[index])): continue
			if not game.progression.request_purchase(String(pending[index])):
				failures.append("Purchase failed after can_purchase: " + String(pending[index]))
				return
			pending.remove_at(index)
			bought = true
		if not bought:
			failures.append("Reference prerequisites could not be satisfied: " + str(pending))
			return


func _reference_research() -> Array[String]:
	var result: Array[String] = []
	for constellation_id in REFERENCE_COMPLETED_CONSTELLATIONS:
		for star in ChartData.CONSTELLATIONS[constellation_id].stars:
			var node_id := String(star.get("node_id", ""))
			if not node_id.is_empty(): result.append(node_id)
	result.append_array(["canis_opening", "canis_cadence_i", "canis_capacity_i"])
	return result


func _meteor_of_type(game: Node, type_id: String):
	for meteor in game.meteor_layer.get_children():
		if String(meteor.type_id) == type_id: return meteor
	return null


func _replace_child(game: Node, child_name: String, replacement: Node) -> void:
	var original: Node = game.get_node(child_name)
	game.remove_child(original)
	original.free()
	replacement.name = child_name
	game.add_child(replacement)


func _definition(id: String) -> Dictionary:
	for definition in SCENARIOS:
		if definition.id == id: return definition
	return {}


func _point(point: Vector2) -> Array:
	return [point.x, point.y]


func _find_active_processes(node: Node, result: Array[String]) -> void:
	if node.is_processing() or node.is_physics_processing() or node.is_processing_input() or node.is_processing_unhandled_input() or node.is_processing_unhandled_key_input():
		result.append(String(node.get_path()))
	for child in node.get_children(): _find_active_processes(child, result)


func _queue_draws(node: Node) -> void:
	if node is CanvasItem: node.queue_redraw()
	for child in node.get_children(): _queue_draws(child)


func _check(condition: bool, id: String, message: String) -> void:
	if not condition: failures.append(id + ": " + message)
