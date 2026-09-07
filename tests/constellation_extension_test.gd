extends SceneTree

const Fixtures = preload("res://tests/support/game_fixture.gd")
const Balance = preload("res://scripts/game_balance.gd")
const Extension = preload("res://scripts/constellation_extension_data.gd")
const Modules = preload("res://scripts/observation_modules.gd")
const Data = preload("res://scripts/expansion_data.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(45.0, true, false, true).timeout.connect(func(): push_error("Constellation test watchdog"); quit(1))
	var game: Node = load("res://scenes/main.tscn").instantiate()
	Fixtures.configure_before_ready(game)
	root.add_child(game)
	await process_frame
	var tree: Node = game.upgrade_tree
	var research: Node = game.deep_sky
	tree.open_tree()
	await process_frame
	_check(not tree.node_buttons.ext_trace_study.is_visible_in_tree(), "outer research stays hidden before galaxy unlock")
	var original_geometry: Dictionary = tree.base_star_positions.duplicate()
	var advanced := true
	while advanced:
		advanced = false
		for definition in Balance.UPGRADE_NODES:
			if definition.branch != "local_group" and not game.progression.has_upgrade(definition.id):
				advanced = game.progression.debug_purchase_node(definition.id) or advanced
	game.spawner.reset()
	game.galactic_pullback_seen = true
	tree.configure_galactic_state(true, true)
	tree.focus_outer_constellations()
	game.progression.observation_data = 2000000000.0
	tree._refresh()
	_check(tree.chart_constellations.size() == 16 and tree.extension_definitions.size() == 18, "four figures and eighteen stars extend the original chart")
	_check(original_geometry == tree.base_star_positions, "unlock preserves the original positions")
	_check(tree.base_star_positions["pegasus/alpheratz"] == tree.base_star_positions["andromeda/alpheratz"], "Pegasus shares the original Alpheratz corner")
	var seen: Dictionary = {}
	for constellation in Extension.ORDER:
		for star in Extension.CONSTELLATIONS[constellation].stars:
			var id: String = star.node_id
			if id.is_empty(): continue
			_check(not seen.has(id), "one research maps to one new star")
			seen[id] = true
			_check(tree.node_buttons[id].get_parent() == tree.tree_canvas, "original and new stars share the same canvas")
			_check(tree._research_state(id) == "locked", "first M31 observation gates the stars: " + id)
	for id in Modules.RESEARCH_IDS + Data.RESEARCH_ORDER:
		_check(seen.has(id), "acquisition remains reachable: " + id)
	_check(tree.content_clip.visible and tree.constellation_ledger.visible, "research opens on the constellation chart")
	_check(tree.node_positions.better_lens.distance_to(tree.CHART_ORIGIN) > 100.0, "original geometry does not collapse into a miniature")
	var visible_original := 0
	for definition in Balance.UPGRADE_NODES:
		if definition.branch != "local_group" and tree.node_buttons[definition.id].is_visible_in_tree(): visible_original += 1
	_check(visible_original > 0, "original stars remain visible beside new figures")
	research.target._process(0.0)
	research.target.apply_manual_observation(10.0, 0.0, 100.0)
	_check(research.observations == 1 and tree._research_state("ext_protocol") == "purchased", "first M31 lights the protocol star")
	tree.select_extension("ext_trace_study")
	_check(tree.tooltip_name.text == research.research_name("ext_trace_study") and tree.tooltip_star.text.contains("α Cyg"), "inspector shows the star identity and research effect")
	var balance_before: float = game.progression.observation_data
	tree.node_buttons.ext_trace_study.button_down.emit()
	tree._process(tree.HOLD_PURCHASE_SECONDS * 0.4)
	_check(not research.research_owned("ext_trace_study"), "partial hold does not purchase")
	tree.node_buttons.ext_trace_study.button_up.emit()
	_check(game.progression.observation_data == balance_before, "early release spends nothing")
	tree.node_buttons.ext_trace_study.button_down.emit()
	tree._process(tree.HOLD_PURCHASE_SECONDS)
	tree.node_buttons.ext_trace_study.button_up.emit()
	_check(research.research_owned("ext_trace_study") and research.modules.research_owned("trail_integrator"), "holding Deneb grants its research and module")
	_check(game.progression.observation_data == balance_before - Data.RESEARCH.ext_trace_study.cost and research.modules.installed_ids().is_empty(), "purchase debits once without auto-equipping")
	_check(tree.node_hold_bars.ext_trace_study.visual_state == "purchased", "completed research lights the existing star marker")
	_check(research.research_owned("ext_trace_study") and research.director.available_kinds() == ["rare"], "one rare meteor kind uses the real scheduler")
	tree.select_extension("focus")
	tree.node_buttons.focus.button_down.emit()
	tree._process(tree.HOLD_PURCHASE_SECONDS * 0.3)
	tree.atlas_actions[0].pressed.emit()
	_check(tree.held_node_id.is_empty() and not research.research_owned("focus"), "navigation cancels partial hold")
	_check(tree.atlas_actions.size() == 1 and tree.content_clip.visible, "chart only offers outer constellation navigation")
	tree.select_extension("focus")
	tree.node_buttons.focus.button_down.emit()
	tree._process(tree.HOLD_PURCHASE_SECONDS)
	tree.node_buttons.focus.button_up.emit()
	_check(research.modules.research_owned("focus"), "old module IDs use star purchases")
	var save: Dictionary = JSON.parse_string(JSON.stringify(game._build_save_data()))
	game._apply_save_data(save)
	tree.open_tree()
	await process_frame
	_check(research.modules.research_owned("focus") and research.research_owned("ext_trace_study"), "version-two saves preserve ownership")
	for locale in ["en", "ko"]:
		game.settings.set_language(locale, false)
		tree.focus_constellation("cygnus")
		_check(tree.tooltip_branch.text == tr("ATLAS_CYGNUS") and tree.tooltip_branch.text != "ATLAS_CYGNUS", "localized constellation navigation: " + locale)
		var previous: Vector2 = tree.node_positions.ext_trace_study
		tree._rotate_chart(0.2)
		_check(not previous.is_equal_approx(tree.node_positions.ext_trace_study), "the chart wheel rotates new stars")
		var old_zoom: float = tree.zoom
		tree._zoom_at(Vector2(576, 324), 1.1)
		_check(tree.zoom > old_zoom, "Ctrl+wheel enlarges the same chart")
		var button: Button = tree.node_buttons.ext_trace_study
		var screen_center: Vector2 = tree.tree_canvas.get_global_transform() * tree.node_positions.ext_trace_study
		_check(button.get_global_rect().has_point(screen_center) and button.get_global_rect().size.x >= 27.0, "star hit area follows rotation and zoom")
	game.free()
	paused = false
	await process_frame
	if failures.is_empty():
		print("CONSTELLATION_EXTENSION_PASS: shared geometry, hold purchases, unlocks, helpers, saves and bilingual navigation")
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
