extends Control

signal observatory_requested
signal constellations_requested
const UITheme = preload("res://scripts/ui_theme.gd")
const ChartData = preload("res://scripts/research_chart_data.gd")
const Visual = preload("res://scripts/module_visual.gd")
const POSITIONS := {"m31": Vector2(455, 315), "modules": Vector2(588, 315), "focus": Vector2(709, 218), "wide": Vector2(716, 420)}
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

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	title = label_at(Vector2(38, 26), 660, 24)
	balance = label_at(Vector2(801, 34), 309, 15)
	balance.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for id in POSITIONS:
		var button := button_at(POSITIONS[id] - Vector2(25, 25), Vector2(50, 50), select.bind(id))
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
	chart_button = button_at(Vector2(83, 212), Vector2(235, 239), func(): constellations_requested.emit())
	chart_button.flat = true
	for state in ["normal", "hover", "pressed", "focus"]:
		chart_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	back_button = button_at(Vector2(902, 588), Vector2(203, 35), func(): observatory_requested.emit())
	refresh_text()

func bind(controller: Node, tree: Node) -> void:
	research = controller
	chart = tree
	research.changed.connect(refresh_text)
	refresh_text()

func select(id: String) -> void:
	selected_id = id
	refresh_text()

func purchase() -> void:
	if research != null and selected_id in ["focus", "wide"]:
		research.purchase(selected_id)

func refresh_text(_binding: String = "U") -> void:
	if title == null:
		return
	title.text = tr("DEEP_CHART_TITLE")
	back_button.text = tr("MODULE_RETURN_TO_SKY")
	chart_button.tooltip_text = tr("DEEP_EXPAND_OLD")
	if research == null:
		return
	balance.text = UITheme.grouped_integer(int(research.game.progression.observation_data)) + " " + tr("MODULE_DATA")
	buy_button.visible = selected_id in ["focus", "wide"]
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
		detail_title.text = tr("MODULE_%s_NAME" % selected_id.to_upper())
		detail_body.text = tr("MODULE_%s_DESC" % selected_id.to_upper())
		var owned: bool = selected_id in research.modules.purchased
		status.text = tr("DEEP_TO_INVENTORY") if research.modules_unlocked() else tr("DEEP_FIRST_HINT")
		price.text = UITheme.grouped_integer(int(research.modules.DEFINITIONS[selected_id].cost)) + " " + tr("MODULE_DATA")
		buy_button.text = tr("MODULE_OWNED") if owned else tr("DEEP_BUY_MODULE")
		buy_button.disabled = owned or not research.modules_unlocked() or research.game.progression.observation_data < research.modules.DEFINITIONS[selected_id].cost
	if research.game.hud.autosave_failed:
		status.text = tr("AUTOSAVE_FAILURE") % research.game.active_save_slot
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("05080E"))
	for index in range(96):
		draw_circle(Vector2(fmod(index * 123.7 + 49, 1152), fmod(index * 89.3 + 103, 648)), 0.55, Color("B7C7DD", 0.20))
	draw_line(Vector2(38, 92), Vector2(1110, 92), Color(UITheme.INK_MID, 0.35), 1)
	draw_line(Vector2(813, 148), Vector2(813, 535), Color(UITheme.INK_MID, 0.35), 1)
	_draw_old_constellations()
	for segment in [[Vector2(319, 327), POSITIONS.m31], [POSITIONS.m31, POSITIONS.modules], [POSITIONS.modules, POSITIONS.focus], [POSITIONS.modules, POSITIONS.wide]]:
		draw_line(segment[0], segment[1], Color(UITheme.LINE_INSTALLED, 0.32), 1, true)
	for id in POSITIONS:
		var p: Vector2 = POSITIONS[id]
		var unlocked: bool = research != null and (id == "m31" or research.modules_unlocked())
		var tone := UITheme.ACCENT_TEXT if unlocked else UITheme.INK_LOW
		if id in ["focus", "wide"]:
			draw_polyline(PackedVector2Array([p + Vector2(0, -22), p + Vector2(22, 0), p + Vector2(0, 22), p + Vector2(-22, 0), p + Vector2(0, -22)]), tone, 1, true)
			Visual.draw_module(self, Rect2(p - Vector2(17, 17), Vector2(34, 34)), id, unlocked)
		else:
			draw_circle(p, 4, tone)
			draw_arc(p, 11, 0, TAU, 32, Color(tone, 0.45), 1, true)
		if selected_id == id:
			draw_arc(p, 28, 0, TAU, 48, Color(UITheme.ACCENT_LINE, 0.5), 1, true)
		var caption := tr("DEEP_M31_SHORT" if id == "m31" else ("DEEP_MODULE_RESEARCH" if id == "modules" else "MODULE_%s_SHORT" % id.to_upper()))
		_draw_caption(p + Vector2(0, 47), caption, tone, 12)
	_draw_caption(Vector2(199, 479), tr("DEEP_OLD_CHART"), UITheme.INK_HIGH, 13)
	_draw_caption(Vector2(199, 502), tr("DEEP_EXPAND_OLD"), UITheme.INK_MID, 11)

func _draw_old_constellations() -> void:
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
			draw_line(center + (a - bounds.get_center()) * ratio, center + (b - bounds.get_center()) * ratio, Color(UITheme.LINE_INSTALLED, 0.52), 0.7, true)
		for star in constellation.stars:
			var p: Vector2 = chart.base_star_positions[constellation_id + "/" + star.id]
			draw_circle(center + (p - bounds.get_center()) * ratio, 1.4 if not String(star.get("node_id", "")).is_empty() else 0.7, Color("E7DCCC", 0.8))

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

func button_at(p: Vector2, dimensions: Vector2, callback: Callable) -> Button:
	var button := Button.new()
	button.position = p
	button.size = dimensions
	button.add_theme_font_override("font", UITheme.sans())
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", UITheme.ACCENT_TEXT)
	for state in ["normal", "hover", "focus", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("090D14") if state != "focus" else Color.TRANSPARENT
		style.border_color = UITheme.ACCENT_LINE if state in ["hover", "focus"] else Color("55483F")
		style.set_border_width_all(1)
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(callback)
	add_child(button)
	return button
