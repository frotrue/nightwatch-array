extends CanvasLayer

signal tree_opened
signal tree_closed

const Balance = preload("res://scripts/game_balance.gd")

const TREE_SIZE := Vector2(1460, 620)
const NODE_SIZE := Vector2(124, 92)
const MAJOR_NODE_SIZE := Vector2(142, 104)
const MIN_ZOOM := 0.55
const MAX_ZOOM := 1.28
const BACKGROUND_STARS := [
	Vector2(74, 48), Vector2(184, 238), Vector2(267, 91), Vector2(386, 390),
	Vector2(488, 215), Vector2(594, 590), Vector2(704, 82), Vector2(812, 414),
	Vector2(916, 177), Vector2(1018, 568), Vector2(1119, 88), Vector2(1230, 408),
	Vector2(1342, 155), Vector2(1410, 544), Vector2(154, 612), Vector2(670, 332),
	Vector2(1072, 357), Vector2(1288, 604), Vector2(437, 511), Vector2(947, 46)
]

var progression: Node
var settings_controller: Node
var overlay: Control
var content_clip: Control
var tree_canvas: Control
var data_readout: Label
var systems_readout: Label
var tree_status: Label
var detail_panel: PanelContainer
var detail_branch: Label
var detail_name: Label
var detail_description: Label
var detail_meta: Label
var title_label: Label
var subtitle_label: Label
var reset_view_button: Button
var close_button: Button
var legend_label: Label
var controls_label: Label

var node_buttons: Dictionary = {}
var node_shadows: Dictionary = {}
var node_icons: Dictionary = {}
var node_costs: Dictionary = {}
var node_names: Dictionary = {}
var node_major_badges: Dictionary = {}
var branch_labels: Dictionary = {}

var selected_node_id: String = ""
var zoom: float = 0.78
var pan_position := Vector2.ZERO
var panning: bool = false
var paused_by_tree: bool = false
var opening_layout_active: bool = false
var refresh_pending: bool = false
var layout_upgrade_level: int = -1
var node_visual_keys: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_build_interface()
	set_process_input(true)


func bind_progression(controller: Node) -> void:
	progression = controller
	progression.state_changed.connect(_on_progression_state_changed)
	progression.purchase_rejected.connect(_on_purchase_rejected)
	_refresh()


func bind_settings(controller: Node) -> void:
	settings_controller = controller
	if not settings_controller.language_changed.is_connected(_on_language_changed):
		settings_controller.language_changed.connect(_on_language_changed)
	_apply_locale()


func open_tree() -> void:
	if overlay.visible or progression == null:
		return
	overlay.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	paused_by_tree = not get_tree().paused
	get_tree().paused = true
	_refresh()
	call_deferred("_reset_view")
	tree_opened.emit()


func close_tree() -> void:
	if not overlay.visible:
		return
	overlay.visible = false
	panning = false
	if paused_by_tree:
		get_tree().paused = false
	paused_by_tree = false
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	tree_closed.emit()


func is_open() -> bool:
	return overlay != null and overlay.visible


func _input(event: InputEvent) -> void:
	if not is_open():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_U:
			close_tree()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			panning = event.pressed
			get_viewport().set_input_as_handled()
			return
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(event.position, 1.10)
			get_viewport().set_input_as_handled()
			return
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(event.position, 1.0 / 1.10)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion and panning:
		pan_position += event.relative
		_apply_transform()
		get_viewport().set_input_as_handled()


func _zoom_at(screen_position: Vector2, factor: float) -> void:
	var old_zoom := zoom
	zoom = clampf(zoom * factor, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(old_zoom, zoom):
		return
	var local_focus := (screen_position - tree_canvas.global_position) / old_zoom
	pan_position += local_focus * (old_zoom - zoom)
	_apply_transform()


func _reset_view() -> void:
	if content_clip == null or content_clip.size.x <= 1.0 or content_clip.size.y <= 1.0:
		return
	var visible_bounds := Rect2()
	var has_visible_node := false
	for button_variant in node_buttons.values():
		var button: Button = button_variant
		if not button.visible:
			continue
		var label: Label = node_names[String(button.get_meta("node_id"))]
		var button_rect := Rect2(button.position, Vector2(maxf(button.size.x, label.size.x), button.size.y + 34.0))
		visible_bounds = button_rect if not has_visible_node else visible_bounds.merge(button_rect)
		has_visible_node = true
	if not has_visible_node:
		visible_bounds = Rect2(Vector2.ZERO, TREE_SIZE)
	visible_bounds = visible_bounds.grow(44.0)
	zoom = clampf(
		minf(content_clip.size.x / visible_bounds.size.x, content_clip.size.y / visible_bounds.size.y) * 0.94,
		MIN_ZOOM,
		1.0
	)
	pan_position = (content_clip.size - visible_bounds.size * zoom) * 0.5 - visible_bounds.position * zoom
	_apply_transform()


func _on_content_resized() -> void:
	if is_open() and content_clip.size.x > 1.0 and content_clip.size.y > 1.0:
		call_deferred("_reset_view")


func _apply_transform() -> void:
	tree_canvas.position = pan_position
	tree_canvas.scale = Vector2.ONE * zoom
	if not selected_node_id.is_empty():
		_position_detail_panel(selected_node_id)


func _on_node_pressed(node_id: String) -> void:
	_show_node_detail(node_id)
	if progression.get_node_state(node_id) != "available":
		return
	if progression.request_purchase(node_id):
		var definition := Balance.upgrade_definition(node_id)
		tree_status.text = tr("TREE_STATUS_ONLINE") % _upgrade_name(definition)


func _on_node_hovered(node_id: String) -> void:
	_show_node_detail(node_id)


func _on_purchase_rejected(node_id: String, reason_key: String, value) -> void:
	selected_node_id = node_id
	match reason_key:
		"UPGRADE_ERROR_STATE":
			tree_status.text = tr(reason_key) % tr("STATE_%s" % String(value).to_upper())
		"UPGRADE_ERROR_NEED_DATA":
			tree_status.text = tr(reason_key) % int(value)
		_:
			tree_status.text = tr(reason_key)
	_show_node_detail(node_id)


func _on_progression_state_changed() -> void:
	if is_open():
		_refresh()
	else:
		refresh_pending = true


func _refresh() -> void:
	if progression == null or data_readout == null:
		return
	refresh_pending = false
	var current_upgrade_level := int(progression.upgrade_level)
	if layout_upgrade_level != current_upgrade_level:
		_apply_layout_mode()
		layout_upgrade_level = current_upgrade_level
	data_readout.text = tr("TREE_DATA") % int(floor(progression.observation_data))
	systems_readout.text = tr("TREE_SYSTEMS") % [progression.upgrade_level, Balance.UPGRADE_NODES.size()]
	var available_count := 0
	var affordable_count := 0
	for definition in Balance.UPGRADE_NODES:
		var node_id := String(definition.id)
		var state: String = progression.get_node_state(node_id)
		var visual_state := state
		if state == "hidden" and _is_teaser_visible(definition):
			visual_state = "teaser"
		var visible := visual_state != "hidden"
		if opening_layout_active and not definition.prerequisites.is_empty():
			visible = false
		var button: Button = node_buttons[node_id]
		var shadow: PanelContainer = node_shadows[node_id]
		var name_label: Label = node_names[node_id]
		button.visible = visible
		shadow.visible = visible
		name_label.visible = visible
		button.set_meta("visual_state", visual_state)
		if not visible:
			continue
		if state == "available":
			available_count += 1
			if progression.can_purchase(node_id):
				affordable_count += 1
		var affordable: bool = state == "available" and progression.can_purchase(node_id)
		var visual_key: String = "%s:%s" % [visual_state, affordable]
		if String(node_visual_keys.get(node_id, "")) != visual_key:
			_apply_node_visual(definition, visual_state)
			node_visual_keys[node_id] = visual_key
	if affordable_count > 0:
		tree_status.text = tr("TREE_STATUS_READY") % affordable_count
	elif available_count > 0:
		tree_status.text = tr("TREE_STATUS_PATHS") % available_count
	else:
		tree_status.text = tr("TREE_STATUS_STABLE")
	if selected_node_id.is_empty() or not node_buttons.has(selected_node_id) or not node_buttons[selected_node_id].visible:
		selected_node_id = _first_visible_node_id()
	if not selected_node_id.is_empty():
		_show_node_detail(selected_node_id)
	tree_canvas.queue_redraw()


func _is_teaser_visible(definition: Dictionary) -> bool:
	for gate_variant in definition.hidden_until:
		var gate_state: String = progression.get_node_state(String(gate_variant))
		if gate_state != "hidden" and gate_state != "missing":
			return true
	return false


func _first_visible_node_id() -> String:
	for definition in Balance.UPGRADE_NODES:
		var node_id := String(definition.id)
		if node_buttons[node_id].visible and String(node_buttons[node_id].get_meta("visual_state")) != "teaser":
			return node_id
	return ""


func _apply_layout_mode() -> void:
	opening_layout_active = progression.upgrade_level == 0
	var opening_positions := {
		"better_lens": Vector2(290, 245),
		"edge_detection": Vector2(620, 245),
		"array_planning": Vector2(950, 245)
	}
	for definition in Balance.UPGRADE_NODES:
		var node_id := String(definition.id)
		var position := Vector2(definition.position)
		if opening_layout_active and opening_positions.has(node_id):
			position = opening_positions[node_id]
		_set_node_position(node_id, position)
	var normal_rows := {"optics": 34.0, "detection": 245.0, "network": 444.0}
	var opening_x := {"optics": 212.0, "detection": 542.0, "network": 872.0}
	for branch_id in branch_labels:
		var label: Label = branch_labels[branch_id]
		if opening_layout_active:
			label.position = Vector2(float(opening_x[branch_id]), 195.0)
			label.size = Vector2(280.0, 32.0)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		else:
			label.position = Vector2(24.0, float(normal_rows[branch_id]))
			label.size = Vector2(300.0, 28.0)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT


func _set_node_position(node_id: String, position: Vector2) -> void:
	if not node_buttons.has(node_id):
		return
	var button: Button = node_buttons[node_id]
	var shadow: PanelContainer = node_shadows[node_id]
	var name_label: Label = node_names[node_id]
	button.position = position
	shadow.position = position + Vector2(0, 8)
	name_label.position = Vector2(position.x + button.size.x * 0.5 - 95.0, position.y + button.size.y + 7.0)


func _apply_node_visual(definition: Dictionary, visual_state: String) -> void:
	var node_id := String(definition.id)
	var branch: Dictionary = Balance.BRANCHES[String(definition.branch)]
	var branch_color: Color = branch.color
	var button: Button = node_buttons[node_id]
	var shadow: PanelContainer = node_shadows[node_id]
	var icon_label: Label = node_icons[node_id]
	var cost_label: Label = node_costs[node_id]
	var name_label: Label = node_names[node_id]
	var major_badge: Label = node_major_badges[node_id]
	var major: bool = bool(definition.major)
	var background := Color("10182a")
	var border := Color(branch_color, 0.62)
	var icon_color := branch_color.lightened(0.18)
	var cost_color := Color("93a8ba")
	var name_color := Color("c8d5e1")
	var opacity := 1.0
	var border_width := 3 if major else 2
	icon_label.text = String(definition.icon)
	cost_label.text = tr("TREE_COST") % int(definition.cost)
	name_label.text = _upgrade_name(definition)
	major_badge.visible = major
	match visual_state:
		"purchased":
			background = branch_color.darkened(0.58)
			border = branch_color.lightened(0.22)
			icon_color = Color("f1fbff")
			cost_color = branch_color.lightened(0.28)
			name_color = branch_color.lightened(0.28)
			cost_label.text = tr("TREE_ONLINE")
		"available":
			if progression.can_purchase(node_id):
				background = branch_color.darkened(0.68)
				border = branch_color.lightened(0.34)
				icon_color = Color("ffffff")
				cost_color = Color("ffe078")
				border_width += 1
			else:
				background = branch_color.darkened(0.76)
				border = Color(branch_color, 0.72)
		"locked":
			background = Color("111421")
			border = Color("495064")
			icon_color = Color("747b8d")
			cost_color = Color("646b7d")
			name_color = Color("747d8d")
			cost_label.text = tr("TREE_LOCKED")
			opacity = 0.78
		"teaser":
			background = Color("0b0d17")
			border = Color("343746")
			icon_color = Color("686b7d")
			cost_color = Color("555868")
			name_color = Color("5f6373")
			icon_label.text = "?"
			cost_label.text = tr("TREE_SIGNAL")
			name_label.text = tr("TREE_UNKNOWN_SIGNAL")
			major_badge.visible = false
			opacity = 0.56
	icon_label.add_theme_color_override("font_color", icon_color)
	cost_label.add_theme_color_override("font_color", cost_color)
	name_label.add_theme_color_override("font_color", name_color)
	major_badge.add_theme_color_override("font_color", branch_color.lightened(0.24))
	button.modulate.a = opacity
	shadow.modulate.a = opacity
	button.add_theme_stylebox_override("normal", _panel_style(background, border, 12 if major else 10, border_width))
	button.add_theme_stylebox_override("hover", _panel_style(background.lightened(0.08), border.lightened(0.18), 12 if major else 10, border_width))
	button.add_theme_stylebox_override("pressed", _panel_style(background.darkened(0.08), border, 12 if major else 10, border_width))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	shadow.add_theme_stylebox_override("panel", _panel_style(background.darkened(0.45), Color.TRANSPARENT, 12 if major else 10, 0))


func _show_node_detail(node_id: String) -> void:
	if progression == null or not node_buttons.has(node_id) or not node_buttons[node_id].visible:
		return
	selected_node_id = node_id
	var definition := Balance.upgrade_definition(node_id)
	var branch: Dictionary = Balance.BRANCHES[String(definition.branch)]
	var branch_color: Color = branch.color
	var visual_state := String(node_buttons[node_id].get_meta("visual_state"))
	if visual_state == "teaser":
		detail_branch.text = "%s  /  %s" % [_branch_name(String(definition.branch)), tr("TREE_UNRESOLVED_SIGNAL")]
		detail_name.text = "???"
		detail_description.text = tr("TREE_TEASER_DESCRIPTION")
		detail_meta.text = tr("TREE_SIGNAL_OBSCURED")
	else:
		detail_branch.text = "%s  /  %s" % [_branch_name(String(definition.branch)), tr("EFFECT_%s" % String(definition.effect_type).to_upper())]
		detail_name.text = _upgrade_name(definition)
		detail_description.text = _upgrade_description(definition)
		match visual_state:
			"purchased":
				detail_meta.text = tr("TREE_SYSTEM_ONLINE")
			"available":
				if progression.can_purchase(node_id):
					detail_meta.text = tr("TREE_INSTALL") % int(definition.cost)
				else:
					var missing := int(ceil(float(definition.cost) - progression.observation_data))
					detail_meta.text = tr("TREE_NEED_MORE") % [int(definition.cost), missing]
			_:
				var prerequisite_names: Array[String] = []
				for prerequisite_variant in definition.prerequisites:
					var prerequisite := Balance.upgrade_definition(String(prerequisite_variant))
					prerequisite_names.append(_upgrade_name(prerequisite))
				detail_meta.text = tr("TREE_REQUIRES") % ", ".join(prerequisite_names)
	detail_branch.add_theme_color_override("font_color", branch_color)
	detail_meta.add_theme_color_override("font_color", Color("ffe078") if visual_state == "available" and progression.can_purchase(node_id) else branch_color.lightened(0.2))
	detail_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.035, 0.045, 0.09, 0.97), branch_color, 12, 2))
	detail_panel.visible = true
	_position_detail_panel(node_id)


func _position_detail_panel(node_id: String) -> void:
	if content_clip == null or detail_panel == null or not node_buttons.has(node_id):
		return
	var button: Button = node_buttons[node_id]
	var node_top_left := tree_canvas.position + button.position * zoom
	var node_size := button.size * zoom
	var panel_size := Vector2(390.0, 154.0)
	var desired := Vector2(node_top_left.x + node_size.x + 18.0, node_top_left.y + node_size.y * 0.5 - panel_size.y * 0.5)
	if opening_layout_active:
		desired = Vector2(node_top_left.x + node_size.x * 0.5 - panel_size.x * 0.5, node_top_left.y + node_size.y + 18.0)
	elif desired.x + panel_size.x > content_clip.size.x - 14.0:
		desired.x = node_top_left.x - panel_size.x - 18.0
	if desired.y + panel_size.y > content_clip.size.y - 14.0:
		desired.y = node_top_left.y - panel_size.y - 18.0
	desired.x = clampf(desired.x, 14.0, maxf(14.0, content_clip.size.x - panel_size.x - 14.0))
	desired.y = clampf(desired.y, 14.0, maxf(14.0, content_clip.size.y - panel_size.y - 14.0))
	detail_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	detail_panel.position = desired
	detail_panel.size = panel_size


func _on_language_changed(_locale: String) -> void:
	_apply_locale()


func _apply_locale() -> void:
	if overlay == null:
		return
	title_label.text = tr("TREE_TITLE")
	subtitle_label.text = tr("TREE_SUBTITLE")
	reset_view_button.text = tr("TREE_CENTER")
	close_button.text = tr("TREE_CLOSE")
	legend_label.text = tr("TREE_LEGEND")
	controls_label.text = "    " + tr("TREE_CONTROLS")
	for branch_id in branch_labels:
		branch_labels[branch_id].text = _branch_name(branch_id)
	if progression != null:
		node_visual_keys.clear()
		_refresh()


func _upgrade_name(definition: Dictionary) -> String:
	return tr("UPGRADE_%s_NAME" % String(definition.id).to_upper())


func _upgrade_description(definition: Dictionary) -> String:
	return tr("UPGRADE_%s_DESC" % String(definition.id).to_upper())


func _branch_name(branch_id: String) -> String:
	return tr("BRANCH_%s" % branch_id.to_upper())


func _build_interface() -> void:
	overlay = Control.new()
	overlay.name = "UpgradeTreeOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false
	add_child(overlay)
	var interface_font := SystemFont.new()
	interface_font.font_names = PackedStringArray(["Pretendard", "Noto Sans CJK KR", "Malgun Gothic", "Segoe UI"])
	overlay.add_theme_font_override("font", interface_font)

	var background := ColorRect.new()
	background.color = Color("050615")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(background)

	var frame := PanelContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 18.0
	frame.offset_top = 16.0
	frame.offset_right = -18.0
	frame.offset_bottom = -16.0
	frame.add_theme_stylebox_override("panel", _panel_style(Color("0a0e20"), Color("354d69"), 14, 1))
	overlay.add_child(frame)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	frame.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var top_row := HBoxContainer.new()
	top_row.custom_minimum_size.y = 46.0
	top_row.add_theme_constant_override("separation", 12)
	column.add_child(top_row)
	var title_stack := VBoxContainer.new()
	title_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_stack.add_theme_constant_override("separation", -2)
	top_row.add_child(title_stack)
	title_label = _make_label(tr("TREE_TITLE"), 22, Color("e8f6ff"))
	title_stack.add_child(title_label)
	subtitle_label = _make_label(tr("TREE_SUBTITLE"), 10, Color("647d96"))
	title_stack.add_child(subtitle_label)
	data_readout = _make_label(tr("TREE_DATA") % 0, 16, Color("9fe8ff"))
	data_readout.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_row.add_child(data_readout)
	systems_readout = _make_label(tr("TREE_SYSTEMS") % [0, Balance.UPGRADE_NODES.size()], 13, Color("67e2bd"))
	systems_readout.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_row.add_child(systems_readout)
	reset_view_button = Button.new()
	reset_view_button.text = tr("TREE_CENTER")
	reset_view_button.custom_minimum_size = Vector2(104, 34)
	_style_header_button(reset_view_button)
	reset_view_button.pressed.connect(_reset_view)
	top_row.add_child(reset_view_button)
	close_button = Button.new()
	close_button.text = tr("TREE_CLOSE")
	close_button.custom_minimum_size = Vector2(108, 34)
	_style_header_button(close_button)
	close_button.pressed.connect(close_tree)
	top_row.add_child(close_button)

	var sub_row := HBoxContainer.new()
	sub_row.custom_minimum_size.y = 22.0
	column.add_child(sub_row)
	tree_status = _make_label("", 12, Color("80e6d2"))
	tree_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub_row.add_child(tree_status)
	legend_label = _make_label(tr("TREE_LEGEND"), 10, Color("6e7890"))
	sub_row.add_child(legend_label)
	controls_label = _make_label("    " + tr("TREE_CONTROLS"), 10, Color("5e6b7f"))
	sub_row.add_child(controls_label)

	var content_frame := PanelContainer.new()
	content_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_frame.add_theme_stylebox_override("panel", _panel_style(Color("060817"), Color("202d43"), 10, 1))
	column.add_child(content_frame)
	content_clip = Control.new()
	content_clip.name = "TreeViewport"
	content_clip.clip_contents = true
	content_clip.mouse_filter = Control.MOUSE_FILTER_PASS
	content_clip.resized.connect(_on_content_resized)
	content_frame.add_child(content_clip)

	tree_canvas = Control.new()
	tree_canvas.name = "TreeCanvas"
	tree_canvas.custom_minimum_size = TREE_SIZE
	tree_canvas.size = TREE_SIZE
	tree_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	tree_canvas.draw.connect(_draw_tree)
	content_clip.add_child(tree_canvas)

	_build_branch_labels()
	for definition in Balance.UPGRADE_NODES:
		_build_node_button(definition)
	_build_detail_panel()


func _build_branch_labels() -> void:
	var rows := {"optics": 34.0, "detection": 245.0, "network": 444.0}
	for branch_id in ["optics", "detection", "network"]:
		var branch: Dictionary = Balance.BRANCHES[branch_id]
		var label := _make_label(_branch_name(branch_id), 15, branch.color)
		label.position = Vector2(24.0, float(rows[branch_id]))
		label.size = Vector2(300, 28)
		tree_canvas.add_child(label)
		branch_labels[branch_id] = label


func _build_node_button(definition: Dictionary) -> void:
	var node_id := String(definition.id)
	var major: bool = bool(definition.major)
	var node_size := MAJOR_NODE_SIZE if major else NODE_SIZE
	var position := Vector2(definition.position)
	var shadow := PanelContainer.new()
	shadow.name = "Shadow_" + node_id
	shadow.position = position + Vector2(0, 8)
	shadow.size = node_size
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tree_canvas.add_child(shadow)

	var button := Button.new()
	button.name = "Node_" + node_id
	button.position = position
	button.size = node_size
	button.custom_minimum_size = node_size
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.focus_mode = Control.FOCUS_NONE
	button.set_meta("node_id", node_id)
	button.set_meta("visual_state", "hidden")
	button.pressed.connect(_on_node_pressed.bind(node_id))
	button.mouse_entered.connect(_on_node_hovered.bind(node_id))
	tree_canvas.add_child(button)

	var icon_label := _make_label(String(definition.icon), 38 if major else 34, Color.WHITE)
	icon_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon_label.offset_bottom = -16.0
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	button.add_child(icon_label)
	var cost_label := _make_label(tr("TREE_COST") % int(definition.cost), 11, Color("93a8ba"))
	cost_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	cost_label.offset_top = -22.0
	cost_label.offset_bottom = -4.0
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	button.add_child(cost_label)
	var major_badge := _make_label("✦", 12, Color.WHITE)
	major_badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	major_badge.offset_left = -22.0
	major_badge.offset_top = 4.0
	major_badge.offset_right = -5.0
	major_badge.offset_bottom = 22.0
	major_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_child(major_badge)

	var name_label := _make_label(_upgrade_name(definition), 12 if major else 11, Color("c8d5e1"))
	name_label.position = Vector2(position.x + node_size.x * 0.5 - 95.0, position.y + node_size.y + 7.0)
	name_label.size = Vector2(190, 38)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tree_canvas.add_child(name_label)

	node_buttons[node_id] = button
	node_shadows[node_id] = shadow
	node_icons[node_id] = icon_label
	node_costs[node_id] = cost_label
	node_names[node_id] = name_label
	node_major_badges[node_id] = major_badge


func _build_detail_panel() -> void:
	detail_panel = PanelContainer.new()
	detail_panel.name = "NodeDetailCard"
	detail_panel.z_index = 50
	detail_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_panel.custom_minimum_size = Vector2(390.0, 154.0)
	detail_panel.visible = false
	content_clip.add_child(detail_panel)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	detail_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 3)
	margin.add_child(column)
	detail_branch = _make_label(tr("BRANCH_OPTICS"), 10, Color("53d6ff"))
	column.add_child(detail_branch)
	detail_name = _make_label(tr("UPGRADE_BETTER_LENS_NAME"), 19, Color("f3f8ff"))
	column.add_child(detail_name)
	detail_description = _make_label("", 12, Color("b4c2d2"))
	detail_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(detail_description)
	detail_meta = _make_label("", 12, Color("ffe078"))
	column.add_child(detail_meta)


func _draw_tree() -> void:
	for x in range(-240, int(TREE_SIZE.x) + 240, 180):
		tree_canvas.draw_line(Vector2(x, 0), Vector2(x + 320, TREE_SIZE.y), Color(0.20, 0.28, 0.42, 0.055), 1.0, true)
	for index in range(BACKGROUND_STARS.size()):
		var radius := 1.7 if index % 5 == 0 else 1.0
		var alpha := 0.28 if index % 5 == 0 else 0.16
		tree_canvas.draw_circle(BACKGROUND_STARS[index], radius, Color(0.65, 0.82, 1.0, alpha))
	if not opening_layout_active:
		var branch_lanes := {
			"optics": [Vector2(55, 145), Vector2(1395, 115)],
			"detection": [Vector2(55, 350), Vector2(1395, 305)],
			"network": [Vector2(55, 555), Vector2(1395, 535)]
		}
		for branch_id in branch_lanes:
			var branch_color: Color = Balance.BRANCHES[branch_id].color
			var lane: Array = branch_lanes[branch_id]
			tree_canvas.draw_line(lane[0], lane[1], Color(branch_color, 0.035), 36.0, true)
			tree_canvas.draw_line(lane[0], lane[1], Color(branch_color, 0.18), 1.4, true)
	if progression == null:
		return
	for definition in Balance.UPGRADE_NODES:
		var target_id := String(definition.id)
		var target_button: Button = node_buttons[target_id]
		if not target_button.visible:
			continue
		for prerequisite_variant in definition.prerequisites:
			var source_id := String(prerequisite_variant)
			var source_button: Button = node_buttons[source_id]
			if not source_button.visible:
				continue
			var start := source_button.position + source_button.size * 0.5
			var finish := target_button.position + target_button.size * 0.5
			var visual_state := String(target_button.get_meta("visual_state"))
			var branch_color: Color = Balance.BRANCHES[String(definition.branch)].color
			var underlay_width := 4.0
			var line_width := 1.5
			var line_color := Color("3d4354")
			match visual_state:
				"purchased":
					underlay_width = 8.0
					line_width = 4.0
					line_color = Color(branch_color, 0.92)
				"available":
					underlay_width = 6.0
					line_width = 2.6
					line_color = Color(branch_color, 0.72)
				"locked":
					line_color = Color(0.36, 0.39, 0.47, 0.36)
				"teaser":
					underlay_width = 3.0
					line_width = 1.2
					line_color = Color(0.34, 0.36, 0.43, 0.22)
			tree_canvas.draw_line(start, finish, Color(0.01, 0.015, 0.035, 0.82), underlay_width, true)
			tree_canvas.draw_line(start, finish, line_color, line_width, true)
			if visual_state == "purchased":
				tree_canvas.draw_circle(start.lerp(finish, 0.5), 3.0, branch_color.lightened(0.2))


func _style_header_button(button: Button) -> void:
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_color_override("font_color", Color("b8cada"))
	button.add_theme_stylebox_override("normal", _panel_style(Color("11192b"), Color("344a60"), 7, 1))
	button.add_theme_stylebox_override("hover", _panel_style(Color("17243a"), Color("5a88a6"), 7, 1))
	button.add_theme_stylebox_override("pressed", _panel_style(Color("0b1220"), Color("72bedb"), 7, 1))


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _panel_style(background: Color, border: Color, radius: int, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style
