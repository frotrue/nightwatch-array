extends SceneTree

# Mechanical presentation gate, not a rendered colour/legibility verdict.
# The windowed capture corpus owns pixel review; this gate checks live binding,
# exact state ink, and the draw callbacks' use of the shared colour function.
const MainScene = preload("res://scenes/main.tscn")
const Chart = preload("res://scripts/upgrade_tree.gd")
const Balance = preload("res://scripts/game_balance.gd")
const UITheme = preload("res://scripts/ui_theme.gd")
const Fixtures = preload("res://tests/support/game_fixture.gd")
const STATES := ["purchased", "available", "locked", "teaser", "hidden"]

class InkRecorder:
	extends Chart.StarNodeVisual

	var draw_count := 0
	var ink_inputs: Array[Color] = []

	func state_ink(base: Color) -> Color:
		ink_inputs.append(base)
		return base

	func _draw() -> void:
		draw_count += 1
		super._draw()

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game = MainScene.instantiate()
	Fixtures.configure_before_ready(game)
	root.add_child(game)
	_freeze(game)
	var sample: Control = game.upgrade_tree.node_hold_bars["better_lens"]
	_check(sample.has_method("state_ink"), "StarNodeVisual exposes the production state_ink contract")
	if sample.has_method("state_ink"):
		_test_live_binding(game)
		_test_state_ink()
		await _test_draw_routing()
	_test_tutorial_copy()
	game.free()
	if failures.is_empty():
		print("RESEARCH_VISUAL_PASS: 95 base and 55 extension bindings, state-ink hierarchy, star/cluster/galaxy draw routing and bilingual tutorial truth")
		quit(0)
	else:
		print("RESEARCH_VISUAL_FAIL: %d failure(s)" % failures.size())
		quit(1)


func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		_freeze(child)


func _test_live_binding(game) -> void:
	var chart = game.upgrade_tree
	var branches := {}
	var kinds := {}
	_check(Balance.UPGRADE_NODES.size() == 95 and chart.node_hold_bars.size() == 150, "binding gate covers 95 base and 55 extension research markers")
	_check(Balance.BRANCHES.size() == 12, "current research has twelve branch families")
	for definition in Balance.UPGRADE_NODES:
		game.progression.purchased_nodes[String(definition.id)] = true
	for definition in Balance.UPGRADE_NODES:
		var node_id := String(definition.id)
		var branch_id := String(definition.branch)
		var visual = chart.node_hold_bars[node_id]
		var star: Dictionary = chart.node_star_records[node_id].star
		var expected_color: Color = Balance.BRANCHES[branch_id].color
		branches[branch_id] = true
		kinds[String(star.kind)] = true
		game.progression.purchased_nodes.erase(node_id)
		for affordable in [true, false]:
			game.progression.observation_data = 1000000000000.0 if affordable else 0.0
			_check(game.progression.can_purchase(node_id) == affordable, "isolated prerequisites make affordability explicit: " + node_id)
			for state in STATES:
				chart._apply_node_visual(definition, state)
				_check(visual.branch_color.is_equal_approx(expected_color), "live refresh preserves declared branch colour: %s/%s" % [node_id, state])
				_check(visual.visual_state == state and visual.affordable == affordable, "live refresh keeps state and affordability independent: %s/%s" % [node_id, state])
				_check(visual.star_kind == String(star.kind) and is_equal_approx(visual.magnitude, float(star.magnitude)), "branch binding preserves astronomical marker kind and magnitude: " + node_id)
		game.progression.purchased_nodes[node_id] = true
	_check(branches.size() == 12, "live bindings visit all twelve branch families")
	for kind in ["star", "cluster", "galaxy"]:
		_check(kinds.has(kind), "live bindings cover marker kind: " + kind)
	for definition in chart.extension_definitions:
		var visual = chart.node_hold_bars[definition.id]
		for state in STATES:
			chart._apply_node_visual(definition, state)
			_check(visual.branch_color.is_equal_approx(Chart.ExtensionChart.COLORS[definition.branch]) and visual.visual_state == state and visual.star_kind == "star", "outer constellation uses the shared star visual: " + definition.id)


func _test_state_ink() -> void:
	var visual = Chart.StarNodeVisual.new()
	var available_inks := {}
	var installed_min := INF
	var available_min := INF
	var available_max := 0.0
	var short_min := INF
	var short_max := 0.0
	var locked_max := 0.0
	var bases := [
		Color(UITheme.STAR_INSTALLED, 0.31), Color(UITheme.STAR_READY_FILL, 0.63),
		Color(UITheme.STAR_SHORT_BORDER, 0.75), Color(UITheme.STAR_LOCKED, 0.24),
		Color(0.13, 0.42, 0.77, 0.19),
	]
	for branch_id in Balance.BRANCHES:
		var branch: Color = Balance.BRANCHES[branch_id].color
		for kind in ["star", "cluster", "galaxy"]:
			for state in STATES:
				for affordable in [false, true]:
					visual.configure(state, branch, 3.0, kind, affordable, false)
					var weight := 0.06 if state == "purchased" else ((0.28 if affordable else 0.12) if state == "available" else 0.0)
					for base in bases:
						var expected := Color(
							base.r + (branch.r - base.r) * weight,
							base.g + (branch.g - base.g) * weight,
							base.b + (branch.b - base.b) * weight,
							base.a
						)
						var actual: Color = visual.state_ink(base)
						_check(actual.is_equal_approx(expected), "bounded independent RGB mix: %s/%s/%s/%s" % [branch_id, kind, state, affordable])
						_check(is_equal_approx(actual.a, base.a), "branch ink never changes alpha")
						if state in ["hidden", "locked", "teaser"]:
							_check(actual == base, "unavailable research has exactly no branch hue")
					_check(is_equal_approx(visual.visual_radius(), 4.94), "state ink preserves magnitude-based marker geometry")
					_check(is_equal_approx(visual.purchased_glow_scale(), 2.35), "ordinary installed halo geometry is unchanged")
		visual.configure("purchased", branch, 3.0, "star", false, true)
		_check(is_equal_approx(visual.purchased_glow_scale(), 2.75), "endpoint installed halo geometry is unchanged")
		installed_min = minf(installed_min, _display_luminance(visual.state_ink(UITheme.STAR_INSTALLED)))
		visual.configure("available", branch, 3.0, "star", true, false)
		var ready: Color = visual.state_ink(UITheme.STAR_READY_FILL)
		available_inks[branch_id] = ready
		available_min = minf(available_min, _display_luminance(ready))
		available_max = maxf(available_max, _display_luminance(ready))
		_check(ready.s < 0.60 and not ready.is_equal_approx(branch), "affordable nodes keep low-mix ink, not full branch saturation")
		visual.configure("available", branch, 3.0, "star", false, false)
		var short_ink: Color = visual.state_ink(UITheme.STAR_SHORT_BORDER)
		short_min = minf(short_min, _display_luminance(short_ink))
		short_max = maxf(short_max, _display_luminance(short_ink))
		visual.configure("locked", branch, 3.0, "star", false, false)
		locked_max = maxf(locked_max, _display_luminance(visual.state_ink(Color(UITheme.STAR_LOCKED, 0.24))))
	_check(installed_min > available_max and available_min > short_max and short_min > locked_max, "state luminance order survives every branch: installed > affordable > short > locked")
	_check(_rgb_distance(available_inks.optics, available_inks.detection) > 0.10, "affordable optics and detection have measurable branch separation")
	_check(_rgb_distance(available_inks.optics, available_inks.network) > 0.06, "affordable optics and network have measurable branch separation")
	var unique_inks := {}
	for ink in available_inks.values():
		unique_inks[Color(ink).to_html(false)] = true
	_check(unique_inks.size() == 12, "all twelve affordable branch bindings remain distinct at eight-bit RGB precision")
	visual.free()


func _test_draw_routing() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 200
	root.add_child(layer)
	var visual := InkRecorder.new()
	visual.position = Vector2(120.0, 120.0)
	visual.size = Vector2(64.0, 64.0)
	layer.add_child(visual)
	for kind in ["star", "cluster", "galaxy"]:
		for state in STATES:
			for affordable in [false, true]:
				for interaction in [false, true]:
					visual.configure(state, Color("53d6ff"), 3.0, kind, affordable, false)
					visual.set_process(false)
					visual.pulse_phase = 0.0
					visual.hold_ratio = 0.45 if interaction else 0.0
					visual.hovered = interaction
					visual.ink_inputs.clear()
					var previous_draws := visual.draw_count
					visual.queue_redraw()
					await process_frame
					await process_frame
					var context := "%s/%s/affordable=%s/interaction=%s" % [kind, state, affordable, interaction]
					_check(visual.draw_count > previous_draws, "real CanvasItem draw callback runs for " + context)
					var expected := _expected_draw_inks(kind, state, affordable, interaction)
					# Shared inks may be cached once or requested by each primitive.
					# Require every original colour/alpha, not one implementation's
					# call order or the six cluster points' duplicate lookup count.
					for ink in expected:
						_check(_has_ink(visual.ink_inputs, ink), "each original draw ink passes through state_ink: " + context)
					for ink in visual.ink_inputs:
						_check(_has_ink(expected, ink), "draw input keeps its original state ink and alpha: " + context)
	layer.free()


func _expected_draw_inks(kind: String, state: String, affordable: bool, interaction: bool) -> Array[Color]:
	var result: Array[Color] = []
	if kind == "cluster" and state != "hidden":
		result.append(Color(UITheme.STAR_BACKGROUND, 0.30))
	match state:
		"purchased":
			result.append_array([Color(UITheme.STAR_INSTALLED_GLOW, 0.22 if interaction else 0.13), UITheme.STAR_INSTALLED])
		"available":
			if affordable:
				result.append_array([Color(UITheme.STAR_READY_RING, 0.50), UITheme.STAR_READY_FILL, UITheme.STAR_READY_BORDER])
			else:
				result.append(UITheme.STAR_SHORT_BORDER)
		"locked", "teaser":
			result.append(Color(UITheme.STAR_LOCKED, 0.24))
		_:
			result.append(Color(UITheme.STAR_BACKGROUND, 0.30))
	if interaction:
		if state != "hidden":
			result.append(Color(UITheme.STAR_READY_RING, 0.28))
		# The neutral gauge track stays unmodified; only its foreground is
		# branch ink, so the track is intentionally not a state_ink call.
		result.append(UITheme.STAR_READY_RING)
	return result


func _has_ink(inks: Array[Color], expected: Color) -> bool:
	for ink in inks:
		if ink.is_equal_approx(expected):
			return true
	return false


func _test_tutorial_copy() -> void:
	var csv := FileAccess.open("res://localization/ui.csv", FileAccess.READ)
	_check(csv != null, "tutorial source CSV is readable")
	if csv == null:
		return
	var completion: PackedStringArray = []
	while not csv.eof_reached():
		var row := csv.get_csv_line()
		if row.size() >= 3 and row[0] == "TUTORIAL_COMPLETE_BODY":
			completion = row
	csv.close()
	_check(completion.size() >= 3, "tutorial completion has English and Korean copy")
	if completion.size() < 3:
		return
	_check(not completion[1].to_lower().contains("all three branches") and not completion[1].to_lower().contains("three branches"), "English tutorial does not claim there are only three research branches")
	_check(not completion[2].contains("세 계열") and not completion[2].contains("세 갈래") and not completion[2].contains("3개 계열"), "Korean tutorial does not claim there are only three research branches")
	_check(completion[1].contains("three manual save slots") and completion[2].contains("저장 슬롯 3개"), "valid three-slot information remains separate from branch count")


func _display_luminance(ink: Color) -> float:
	var composited := Color(UITheme.GROUND).lerp(Color(ink, 1.0), ink.a).srgb_to_linear()
	return composited.r * 0.2126 + composited.g * 0.7152 + composited.b * 0.0722


func _rgb_distance(a: Color, b: Color) -> float:
	return Vector3(a.r, a.g, a.b).distance_to(Vector3(b.r, b.g, b.b))


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures.append(message)
	push_error("RESEARCH_VISUAL: " + message)
