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
	# This fixture checks research and input, not audio playback. Reuse the
	# existing silent service so rapid purchases do not leave WAV voices at exit.
	game.sound.free()
	game.sound = Fixtures.SilentSound.new()
	game.add_child(game.sound)
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
			if not game.progression.has_upgrade(definition.id):
				advanced = game.progression.debug_purchase_node(definition.id) or advanced
	game.spawner.reset()
	game.galactic_pullback_seen = true
	tree.configure_galactic_state(true, true)
	tree.focus_outer_constellations()
	game.progression.observation_data = 2000000000.0
	tree._refresh()
	_check(tree.chart_constellations.size() == 25 and tree.extension_definitions.size() == 66, "thirteen figures and sixty-six research stars extend the original chart")
	_check(original_geometry == tree.base_star_positions, "unlock preserves the original positions")
	_check(tree.base_star_positions["pegasus/alpheratz"] == tree.base_star_positions["andromeda/alpheratz"], "Pegasus shares the original Alpheratz corner")
	_check(tree.constellation_ledger_hits.size() == tree._constellation_order().size(), "ledger has exactly one hit target per active constellation")
	for constellation in tree.ChartData.CONSTELLATIONS:
		tree.focus_constellation(constellation)
		for star in tree.chart_constellations[constellation].stars:
			var screen: Vector2 = tree.tree_canvas.get_global_transform() * tree.star_positions[constellation + "/" + star.id]
			_check(Rect2(180, 130, 720, 410).has_point(screen), "focused completed figure remains inside the chart: " + constellation)
		var id: String = tree.selected_node_id
		_check(tree.node_buttons[id].mouse_filter == Control.MOUSE_FILTER_STOP, "completed stars retain input after visual dimming")
		# Restore the overview zoom while keeping this figure above the horizon.
		tree.zoom = 0.43
		tree.pan_position = tree._galactic_pan_for_zoom(tree.zoom)
		tree._layout_chart()
		tree._apply_transform()
		_check(tree.node_hold_bars[id].modulate.a < 1.0 or tree.shared_star_node_ids.has(id), "completed overview stars are subdued except shared outer corners")
		tree.node_buttons[id].button_down.emit()
		tree.node_buttons[id].button_up.emit()
		_check(tree.zoom > 0.8 and tree.selected_node_id == id and tree.held_node_id.is_empty(), "clicking a completed star zooms in without buying or changing selection")
		var reading_center: Vector2 = (Vector2(560, 330) - tree.pan_position) / tree.zoom
		tree._zoom_at(Vector2(576, 324), 0.9)
		_check((tree.pan_position + reading_center * tree.zoom).distance_to(Vector2(560, 330)) < 0.001, "zooming a selected legacy figure retains its reading center")
	tree.focus_outer_constellations()
	for constellation in Extension.ORDER:
		var row: int = tree._constellation_order().find(constellation)
		tree.constellation_ledger_hits[row].pressed.emit()
		_check(tree.node_star_records[tree.selected_node_id].constellation_id == constellation, "ledger click focuses its displayed constellation: " + constellation)
		_check(tree.constellation_ledger_hits[row].get_global_rect().end.y < tree.atlas_navigation.get_global_rect().position.y, "ledger row is not covered by navigation: " + constellation)
		if constellation in ["scutum", "cancer", "sagittarius", "phoenix"]:
			for star in Extension.CONSTELLATIONS[constellation].stars:
				if String(star.node_id).is_empty(): continue
				var screen: Vector2 = tree.tree_canvas.get_global_transform() * tree.node_positions[star.node_id]
				_check(tree.node_buttons[star.node_id].is_visible_in_tree() and tree._star_hit_owner(screen) == star.node_id, "new research star is selectable: " + star.node_id)
	var seen: Dictionary = {}
	for constellation in Extension.ORDER:
		for star in Extension.CONSTELLATIONS[constellation].stars:
			var id: String = star.node_id
			if id.is_empty(): continue
			_check(not seen.has(id), "one research maps to one new star")
			seen[id] = true
			_check(Data.RESEARCH[id].branch == constellation, "research effect belongs to its displayed constellation: " + id)
			_check(tree.node_buttons[id].get_parent() == tree.tree_canvas, "original and new stars share the same canvas")
	for id in Modules.RESEARCH_IDS + Data.RESEARCH_ORDER:
		_check(seen.has(id), "acquisition remains reachable: " + id)
	_check(Data.MODULE_BRANCHES.size() == 2 and Extension.ORDER.size() - Data.MODULE_BRANCHES.size() == 11, "only two of thirteen branches support modules")
	_check(tree.content_clip.visible and tree.constellation_ledger.visible, "research opens on the constellation chart")
	_check(tree.node_positions.better_lens.distance_to(tree.CHART_ORIGIN) > 100.0, "original geometry does not collapse into a miniature")
	var visible_original := 0
	for definition in Balance.UPGRADE_NODES:
		if tree.node_buttons[definition.id].is_visible_in_tree(): visible_original += 1
	_check(visible_original > 0, "original stars remain visible beside new figures")
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
	_check(research.research_owned("ext_trace_study") and research.modules.purchased.is_empty() and is_equal_approx(research.state.effect("manual_speed"), 1.15), "holding Deneb installs permanent tracking without granting a module")
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
	_check(research.research_owned("focus") and research.modules.purchased.is_empty(), "retained research IDs install growth without module ownership")
	var save: Dictionary = JSON.parse_string(JSON.stringify(game._build_save_data()))
	game._apply_save_data(save)
	tree.open_tree()
	await process_frame
	_check(research.research_owned("focus") and research.research_owned("ext_trace_study") and research.modules.purchased.is_empty(), "new saves preserve permanent research independently from equipment")
	for locale in ["en", "ko"]:
		game.settings.set_language(locale, false)
		tree.focus_constellation("cygnus")
		_check(tree.tooltip_branch.text.begins_with(tr("ATLAS_CYGNUS")) and tree.tooltip_branch.text.contains(tr("ATLAS_ROLE_CYGNUS")), "localized constellation role and navigation: " + locale)
		var previous: Vector2 = tree.node_positions.ext_trace_study
		tree._rotate_chart(0.2)
		_check(not previous.is_equal_approx(tree.node_positions.ext_trace_study), "the chart wheel rotates new stars")
		var old_zoom: float = tree.zoom
		tree._zoom_at(Vector2(576, 324), 1.1)
		_check(tree.zoom > old_zoom, "Ctrl+wheel enlarges the same chart")
		var button: Button = tree.node_buttons.ext_trace_study
		var screen_center: Vector2 = tree.tree_canvas.get_global_transform() * tree.node_positions.ext_trace_study
		_check(button.get_global_rect().has_point(screen_center) and button.get_global_rect().size.x >= 27.0, "star hit area follows rotation and zoom")
	# Alpha Vul and 8 Vul are separated by only about seven arcminutes. Their
	# readable markers are separated while retaining native hold purchases.
	tree.focus_constellation("vulpecula")
	game.progression.observation_data = 1.0e15
	tree._refresh()
	var pair_point: Vector2 = tree.node_buttons.ext_vul_memory.get_global_rect().get_center()
	_check(tree._star_hit_owner(pair_point) == "ext_vul_memory", "close pair selects available first research, not last scene child")
	var first_button: Button = tree.node_buttons.ext_vul_memory
	var second_button: Button = tree.node_buttons.ext_vul_rhythm
	_check(first_button._has_point(first_button.size * 0.5) and not second_button._has_point(second_button.get_global_transform().affine_inverse() * pair_point), "overlapping native buttons have exactly one hit owner")
	await process_frame
	var pointer := InputEventMouseMotion.new()
	pointer.position = pair_point
	pointer.global_position = pair_point
	root.push_input(pointer, true)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.position = pair_point
	press.global_position = pair_point
	root.push_input(press, true)
	_check(tree.held_node_id == "ext_vul_memory", "native GUI press reaches the first close-pair star")
	tree._process(tree.HOLD_PURCHASE_SECONDS)
	var release: InputEventMouseButton = press.duplicate()
	release.pressed = false
	release.button_mask = 0
	root.push_input(release, true)
	var next_point: Vector2 = second_button.get_global_rect().get_center()
	_check(research.research_owned("ext_vul_memory") and pair_point.distance_to(next_point) >= tree.MIN_STAR_SCREEN_SEPARATION - 0.1, "close-pair research has distinct visible centers")
	_check(tree._star_hit_owner(pair_point) == "ext_vul_memory" and tree._star_hit_owner(next_point) == "ext_vul_rhythm", "each separated center keeps its own input owner after purchase")
	pointer.position = next_point
	pointer.global_position = next_point
	press.position = next_point
	press.global_position = next_point
	release.position = next_point
	release.global_position = next_point
	root.push_input(pointer, true)
	root.push_input(press, true)
	_check(tree.held_node_id == "ext_vul_rhythm", "native GUI press reaches the next close-pair star")
	tree._process(tree.HOLD_PURCHASE_SECONDS)
	root.push_input(release, true)
	_check(research.research_owned("ext_vul_rhythm"), "both close-pair nodes retain normal hold purchase semantics")
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
