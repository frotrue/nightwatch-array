extends Control

signal observatory_requested
signal constellations_requested
const UITheme = preload("res://scripts/ui_theme.gd")
const ChartData = preload("res://scripts/research_chart_data.gd")
const Visual = preload("res://scripts/module_visual.gd")
const Modules = preload("res://scripts/observation_modules.gd")
const POSITIONS := {
	"m31": Vector2(390, 315), "modules": Vector2(480, 315),
	"focus": Vector2(560, 160), "wide": Vector2(560, 430),
	"precision": Vector2(695, 160), "record": Vector2(695, 430),
	"slot_3": Vector2(700, 295), "revisit": Vector2(600, 535),
	"slot_4": Vector2(770, 490), "slot_5": Vector2(770, 570),
}
const CONNECTIONS := [["m31", "modules"], ["modules", "focus"], ["modules", "wide"], ["focus", "precision"], ["wide", "record"], ["precision", "slot_3"], ["record", "slot_3"], ["slot_3", "revisit"], ["revisit", "slot_4"], ["slot_4", "slot_5"]]
var chart: Node
var research: Node
var selected_id := "m31"
var nodes: Dictionary = {}
var title: Label
var balance: Label
var detail_title: Label
var detail_body: Label
var status: Label
var price: Label
var buy_button: Button
var back_button: Button
var chart_button: Button
var _miniature_edges: Array[PackedVector2Array] = []
var _miniature_stars: Array[Dictionary] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	title = label_at(Vector2(38, 26), 660, 24)
	balance = label_at(Vector2(801, 34), 309, 15)
	balance.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for id in POSITIONS:
		var button := button_at(POSITIONS[id] - Vector2(25, 25), Vector2(50, 50), select.bind(id), false)
		button.flat = true
		for state in ["normal", "hover", "pressed", "focus"]:
			button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		nodes[id] = button
	detail_title = label_at(Vector2(840, 168), 264, 19)
	detail_body = label_at(Vector2(840, 213), 263, 13)
	detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status = label_at(Vector2(840, 328), 264, 12)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	price = label_at(Vector2(840, 401), 264, 14)
	buy_button = button_at(Vector2(840, 441), Vector2(263, 35), purchase)
	chart_button = button_at(Vector2(83, 212), Vector2(235, 239), func(): constellations_requested.emit(), false)
	chart_button.flat = true
	for state in ["normal", "hover", "pressed", "focus"]:
		chart_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	back_button = button_at(Vector2(902, 588), Vector2(203, 35), func(): observatory_requested.emit())
	visibility_changed.connect(refresh_text)
	refresh_text()

func bind(controller: Node, tree: Node) -> void:
	research = controller
	chart = tree
	_cache_miniature()
	research.changed.connect(refresh_text)
	refresh_text()

func select(id: String) -> void:
	selected_id = id
	refresh_text()

func purchase() -> void:
	if research != null and selected_id in Modules.RESEARCH_IDS:
		research.purchase(selected_id)

func refresh_text(_binding: String = "U") -> void:
	if title == null or not is_visible_in_tree():
		return
	title.text = tr("DEEP_CHART_TITLE")
	back_button.text = tr("MODULE_RETURN_TO_SKY")
	chart_button.tooltip_text = tr("DEEP_EXPAND_OLD")
	if research == null:
		return
	balance.text = UITheme.grouped_integer(int(research.game.progression.observation_data)) + " " + tr("MODULE_DATA")
	buy_button.visible = selected_id in Modules.RESEARCH_IDS
	price.text = ""
	if selected_id == "m31":
		detail_title.text = tr("DEEP_M31_NAME")
		detail_body.text = tr("DEEP_M31_DESC")
		status.text = tr("DEEP_RECORDED") % research.observations if research.observations > 0 else tr("DEEP_FIRST_HINT")
	elif selected_id == "modules":
		detail_title.text = tr("DEEP_MODULE_RESEARCH")
		detail_body.text = tr("DEEP_RESEARCH_DESC")
		status.text = tr("DEEP_UNLOCKED") if research.modules_unlocked() else tr("DEEP_FIRST_HINT")
	else:
		var owned: bool = research.modules.research_owned(selected_id)
		if Modules.SLOT_RESEARCH.has(selected_id):
			var capacity: int = Modules.SLOT_RESEARCH[selected_id].capacity
			detail_title.text = tr("RING_RESEARCH_%d" % capacity)
			detail_body.text = tr("RING_RESEARCH_DESC") % [capacity - 1, capacity]
		else:
			detail_title.text = tr("MODULE_%s_NAME" % selected_id.to_upper())
			detail_body.text = tr("MODULE_%s_DESC" % selected_id.to_upper())
		status.text = tr("DEEP_TO_INVENTORY") if selected_id in Modules.DEFINITIONS else tr("RING_RESEARCH_LOCATION")
		if not research.modules_unlocked():
			status.text = tr("DEEP_FIRST_HINT")
		elif not owned and not research.modules.research_ready(selected_id):
			status.text = _prerequisite_text(selected_id)
		price.text = UITheme.grouped_integer(int(research.modules.research_cost(selected_id))) + " " + tr("MODULE_DATA")
		buy_button.text = tr("MODULE_OWNED") if owned else tr("DEEP_BUY_MODULE" if Modules.DEFINITIONS.has(selected_id) else "RING_RESEARCH_BUY")
		buy_button.disabled = not research.can_purchase(selected_id)
	if research.game.hud.autosave_failed:
		status.text = tr("AUTOSAVE_FAILURE") % research.game.active_save_slot
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UITheme.TOOLTIP_BACKGROUND)
	for index in range(96):
		draw_circle(Vector2(fmod(index * 123.7 + 49, 1152), fmod(index * 89.3 + 103, 648)), 0.55, Color(UITheme.STAR_BACKGROUND, 0.20))
	draw_line(Vector2(38, 92), Vector2(1110, 92), Color(UITheme.INK_MID, 0.35), 1)
	draw_line(Vector2(813, 148), Vector2(813, 535), Color(UITheme.INK_MID, 0.35), 1)
	_draw_old_constellations()
	draw_line(Vector2(319, 327), POSITIONS.m31, Color(UITheme.LINE_INSTALLED, 0.32), 1, true)
	for edge in CONNECTIONS:
		draw_line(POSITIONS[edge[0]], POSITIONS[edge[1]], Color(UITheme.LINE_INSTALLED, 0.32), 1, true)
	for id in POSITIONS:
		var p: Vector2 = POSITIONS[id]
		var unlocked: bool = research != null and (id == "m31" or (id == "modules" and research.modules_unlocked()) or (research.modules_unlocked() and (research.modules.research_owned(id) or research.modules.research_ready(id))))
		var tone := UITheme.ACCENT_TEXT if unlocked else UITheme.INK_LOW
		if Modules.DEFINITIONS.has(id):
			draw_polyline(PackedVector2Array([p + Vector2(0, -22), p + Vector2(22, 0), p + Vector2(0, 22), p + Vector2(-22, 0), p + Vector2(0, -22)]), tone, 1, true)
			Visual.draw_module(self, Rect2(p - Vector2(17, 17), Vector2(34, 34)), id, unlocked)
		else:
			draw_circle(p, 4, tone)
			draw_arc(p, 11, 0, TAU, 32, Color(tone, 0.45), 1, true)
		if selected_id == id:
			draw_arc(p, 28, 0, TAU, 48, Color(UITheme.ACCENT_LINE, 0.5), 1, true)
		var caption := tr("DEEP_M31_SHORT" if id == "m31" else ("DEEP_MODULE_RESEARCH" if id == "modules" else ("RING_RESEARCH_%d" % Modules.SLOT_RESEARCH[id].capacity if Modules.SLOT_RESEARCH.has(id) else "MODULE_%s_SHORT" % id.to_upper())))
		_draw_caption(p + Vector2(0, -35 if id == "modules" else 47), caption, tone, 12)
	_draw_caption(Vector2(199, 479), tr("DEEP_OLD_CHART"), UITheme.INK_HIGH, 13)
	_draw_caption(Vector2(199, 502), tr("DEEP_EXPAND_OLD"), UITheme.INK_MID, 11)

func _cache_miniature() -> void:
	# Base chart geometry is constructed once by UpgradeTree. Zoom and rotation
	# affect its presentation positions, not these immutable source coordinates.
	_miniature_edges.clear()
	_miniature_stars.clear()
	if chart == null or chart.base_star_positions.is_empty():
		return
	var bounds := Rect2(Vector2(chart.base_star_positions.values()[0]), Vector2.ZERO)
	for point in chart.base_star_positions.values():
		bounds = bounds.expand(point)
	var ratio := minf(226.0 / maxf(1, bounds.size.x), 216.0 / maxf(1, bounds.size.y))
	var center := Vector2(200, 327)
	for constellation_id in ChartData.CONSTELLATIONS:
		var constellation: Dictionary = ChartData.CONSTELLATIONS[constellation_id]
		for edge in constellation.segments:
			var a: Vector2 = chart.base_star_positions[constellation_id + "/" + edge[0]]
			var b: Vector2 = chart.base_star_positions[constellation_id + "/" + edge[1]]
			_miniature_edges.append(PackedVector2Array([center + (a - bounds.get_center()) * ratio, center + (b - bounds.get_center()) * ratio]))
		for star in constellation.stars:
			var p: Vector2 = chart.base_star_positions[constellation_id + "/" + star.id]
			_miniature_stars.append({"position": center + (p - bounds.get_center()) * ratio, "radius": 1.4 if not String(star.get("node_id", "")).is_empty() else 0.7})

func _draw_old_constellations() -> void:
	for edge in _miniature_edges:
		draw_line(edge[0], edge[1], Color(UITheme.LINE_INSTALLED, 0.52), 0.7, true)
	for star in _miniature_stars:
		draw_circle(star.position, star.radius, Color(UITheme.STAR_INSTALLED, 0.8))

func _draw_caption(p: Vector2, caption: String, ink: Color, font_size: int) -> void:
	var font: Font = UITheme.sans()
	var width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, p - Vector2(width * 0.5, 0), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)

func label_at(p: Vector2, width: float, font_size: int) -> Label:
	var label := Label.new()
	label.position = p
	label.size.x = width
	label.add_theme_font_override("font", UITheme.sans())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", UITheme.INK_HIGH)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label

func button_at(p: Vector2, dimensions: Vector2, callback: Callable, underline: bool = true) -> Button:
	var button := Button.new()
	button.position = p
	button.size = dimensions
	button.add_theme_font_override("font", UITheme.sans())
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", UITheme.ACCENT_TEXT)
	button.flat = true
	for state in ["normal", "hover", "focus", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	if underline:
		button.draw.connect(func(): button.draw_line(Vector2(0, button.size.y - 1), button.size - Vector2(0, 1), UITheme.INK_MID, UITheme.px(1), true))
	button.pressed.connect(callback)
	add_child(button)
	return button

func _prerequisite_text(id: String) -> String:
	var definition: Dictionary = Modules.SLOT_RESEARCH.get(id, Modules.DEFINITIONS.get(id, {}))
	var names: Array[String] = []
	for prerequisite in definition.get("requires", []):
		names.append(tr("MODULE_%s_NAME" % String(prerequisite).to_upper()))
	var previous_capacity := int(definition.get("capacity", 0)) - 1
	var required_capacity := int(definition.get("slots_required", 0))
	if maxi(previous_capacity, required_capacity) > Modules.INITIAL_SLOTS:
		names.append(tr("RING_RESEARCH_%d" % maxi(previous_capacity, required_capacity)))
	return tr("RING_REQUIRES") % " + ".join(names)
