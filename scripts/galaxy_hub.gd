extends Control

signal destination_requested(id: String)
signal observatory_requested
signal constellations_requested

const UITheme = preload("res://scripts/ui_theme.gd")
# Only real, playable destinations belong here. More stages can append records
# without recreating the old constellation research graph.
const DESTINATIONS := [
	{"id": "andromeda", "name_key": "ANDROMEDA_TITLE", "code": "M31", "description_key": "GALAXY_HUB_ANDROMEDA_DESC", "available": true},
]
var selected_id := "andromeda"
var destination_buttons: Dictionary = {}
var title: Label
var subtitle: Label
var selected_name: Label
var selected_code: Label
var selected_description: Label
var selected_status: Label
var enter_button: Button
var back_button: Button
var chart_button: Button
var backdrop: Control
var galaxy_points: Array[Dictionary] = []
var field_points: Array[Vector2] = []
var return_binding := "U"

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var rng := RandomNumberGenerator.new()
	rng.seed = 310005
	for index in range(92):
		field_points.append(Vector2(rng.randf(), rng.randf()))
	for index in range(1750):
		var r := pow(rng.randf(), 0.82)
		var theta := rng.randf() * TAU
		if index % 3 != 0:
			theta = r * 8.0 + PI * float(index % 2) + rng.randf_range(-0.45, 0.45)
		var p := Vector2(cos(theta) * r, sin(theta) * r * 0.36).rotated(-0.36)
		galaxy_points.append({"p": p, "a": rng.randf_range(0.18, 0.85) * (1.0 - r * 0.75), "r": rng.randf_range(0.45, 1.25), "warm": r < 0.24})
	backdrop = Control.new()
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	backdrop.draw.connect(_draw_map)
	title = _label(30, UITheme.INK_HIGH)
	subtitle = _label(13, UITheme.INK_MID)
	selected_name = _label(27, UITheme.INK_HIGH)
	selected_code = _label(12, UITheme.INK_MID)
	selected_description = _label(15, UITheme.TOOLTIP_BODY)
	selected_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	selected_status = _label(13, UITheme.ACCENT_TEXT)
	enter_button = _button(18, _enter_selected)
	back_button = _button(13, func(): observatory_requested.emit())
	chart_button = _button(13, func(): constellations_requested.emit())
	for destination in DESTINATIONS:
		var id := String(destination.id)
		var button := _button(15, func(): select_destination(id))
		button.name = "Destination_" + id
		button.disabled = not bool(destination.available)
		destination_buttons[id] = button
	resized.connect(_layout)
	refresh_text()
	_layout()

func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", UITheme.sans())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label

func _button(font_size: int, callback: Callable) -> Button:
	var button := Button.new()
	button.flat = true
	button.add_theme_font_override("font", UITheme.sans())
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", UITheme.ACCENT_TEXT)
	button.add_theme_color_override("font_hover_color", UITheme.INK_MAX)
	button.pressed.connect(callback)
	add_child(button)
	return button

func _selected() -> Dictionary:
	for destination in DESTINATIONS:
		if destination.id == selected_id:
			return destination
	return {}

func select_destination(id: String) -> void:
	for destination in DESTINATIONS:
		if destination.id == id and destination.available:
			selected_id = id
			refresh_text()
			return

func _enter_selected() -> void:
	var destination := _selected()
	if not destination.is_empty() and bool(destination.available):
		destination_requested.emit(selected_id)

func refresh_text(binding: String = "") -> void:
	if not binding.is_empty():
		return_binding = binding
	if title == null:
		return
	title.text = tr("GALAXY_HUB_TITLE")
	subtitle.text = tr("GALAXY_HUB_SUBTITLE")
	var destination := _selected()
	selected_name.text = tr(String(destination.name_key))
	selected_code.text = tr("GALAXY_HUB_DESTINATION")
	selected_description.text = tr(String(destination.description_key))
	selected_status.text = tr("GALAXY_HUB_AVAILABLE")
	enter_button.text = tr("GALAXY_HUB_ENTER")
	back_button.text = tr("GALAXY_HUB_RETURN") % return_binding
	chart_button.text = tr("GALAXY_HUB_CONSTELLATIONS")
	for entry in DESTINATIONS:
		destination_buttons[entry.id].text = String(entry.code) + ("  ·  " + tr("GALAXY_HUB_SELECTED") if entry.id == selected_id else "")
	_layout()

func _layout() -> void:
	if title == null or size.x <= 0.0:
		return
	var margin := 48.0
	title.position = Vector2(margin, 36)
	subtitle.position = Vector2(margin + 1, 83)
	var panel_x := size.x * 0.64
	var panel_width := size.x - panel_x - margin
	selected_code.position = Vector2(panel_x, size.y * 0.32)
	selected_name.position = Vector2(panel_x, size.y * 0.32 + 27)
	selected_name.size.x = panel_width
	selected_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	selected_description.position = Vector2(panel_x, selected_name.position.y + selected_name.get_minimum_size().y + 22)
	selected_description.size = Vector2(panel_width, 78)
	selected_status.position = Vector2(panel_x, selected_description.position.y + 89)
	enter_button.position = Vector2(panel_x - 10, selected_status.position.y + 39)
	enter_button.size = Vector2(panel_width, 48)
	enter_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	back_button.position = Vector2(margin - 10, size.y - 63)
	back_button.size = Vector2(300, 40)
	back_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	chart_button.position = Vector2(size.x - margin - 240, size.y - 63)
	chart_button.size = Vector2(240, 40)
	chart_button.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var count := destination_buttons.size()
	var index := 0
	for id in destination_buttons:
		var button: Button = destination_buttons[id]
		var p := _destination_center(index, count)
		button.position = p + Vector2(-140, 116 if count == 1 else 42)
		button.size = Vector2(280, 40)
		index += 1
	backdrop.queue_redraw()

func _destination_center(index: int, count: int) -> Vector2:
	if count == 1:
		return size * Vector2(0.33, 0.53)
	var columns := 2
	var rows := ceili(float(count) / columns)
	return Vector2(size.x * (0.18 + 0.25 * float(index % columns)), 160 + float(index / columns) * maxf(75, (size.y - 280) / rows))

func _draw_map() -> void:
	backdrop.draw_rect(Rect2(Vector2.ZERO, size), Color("060A12"))
	for index in range(field_points.size()):
		backdrop.draw_circle(field_points[index] * size, 0.65, Color("C6D6E3", 0.12 + float(index % 5) * 0.055))
	var count := destination_buttons.size()
	for index in range(count):
		var center := _destination_center(index, count)
		var span := minf(size.x * 0.235, 280.0) if count == 1 else 65.0
		for star in galaxy_points:
			var color := Color("E7C89E") if star.warm else Color("A8C3E0")
			backdrop.draw_circle(center + star.p * span, star.r if count == 1 else 0.5, Color(color, star.a))
		for radius in range(20, 0, -1):
			backdrop.draw_circle(center, float(radius) * span / 95.0, Color("E7C89E", 0.009))
	var line_x := size.x * 0.60
	backdrop.draw_line(Vector2(line_x, size.y * 0.30), Vector2(line_x, size.y * 0.72), Color("4F443E", 0.55), 1.0)
