extends CanvasLayer

signal tree_opened
signal tree_closed

const Balance = preload("res://scripts/game_balance.gd")
const ChartData = preload("res://scripts/research_chart_data.gd")

const TREE_SIZE := Vector2(1460, 780)
const MIN_ZOOM := 0.55
const MAX_ZOOM := 1.28
const HOLD_PURCHASE_SECONDS := 0.75
const CHART_ORIGIN := Vector2(TREE_SIZE.x * 0.5, TREE_SIZE.y * 0.91)
const ROTATION_STEP := deg_to_rad(6.0)
const DEFAULT_ROTATION := 0.0
const STAR_HIT_SIZE := Vector2(44.0, 44.0)
const BACKGROUND_STARS := [
	Vector2(74, 48), Vector2(184, 238), Vector2(267, 91), Vector2(386, 390),
	Vector2(488, 215), Vector2(594, 590), Vector2(704, 82), Vector2(812, 414),
	Vector2(916, 177), Vector2(1018, 568), Vector2(1119, 88), Vector2(1230, 408),
	Vector2(1342, 155), Vector2(1410, 544), Vector2(154, 612), Vector2(670, 332),
	Vector2(1072, 357), Vector2(1288, 604), Vector2(437, 511), Vector2(947, 46),
	Vector2(214, 704), Vector2(742, 746), Vector2(1088, 682), Vector2(1380, 735)
]


class StarNodeVisual:
	extends Control

	var hold_ratio: float = 0.0
	var branch_color := Color("7f9caf")
	var visual_state := "hidden"
	var magnitude: float = 3.0
	var star_kind := "star"
	var affordable := false
	var hovered := false
	var pulse_phase := 0.0


	func set_fill_progress(ratio: float, elapsed: float) -> void:
		hold_ratio = clampf(ratio, 0.0, 1.0)
		pulse_phase = elapsed * 8.0
		queue_redraw()


	func clear_fill() -> void:
		hold_ratio = 0.0
		queue_redraw()


	func configure(state: String, color: Color, apparent_magnitude: float, kind: String, can_afford: bool) -> void:
		visual_state = state
		branch_color = color
		magnitude = apparent_magnitude
		star_kind = kind
		affordable = can_afford
		set_process(visual_state == "available" and affordable)
		queue_redraw()


	func set_hovered(value: bool) -> void:
		hovered = value
		queue_redraw()


	func visual_radius() -> float:
		return clampf(7.4 - magnitude * 0.82, 3.4, 7.4)


	func _process(delta: float) -> void:
		pulse_phase = fmod(pulse_phase + delta * 3.2, TAU)
		queue_redraw()


	func _draw() -> void:
		var center := size * 0.5
		var radius := visual_radius()
		var state_alpha := 0.42
		var core_color := Color("758296")
		match visual_state:
			"purchased":
				state_alpha = 1.0
				core_color = branch_color.lightened(0.46)
			"available":
				state_alpha = 0.92 if affordable else 0.68
				core_color = Color("fff4ba") if affordable else branch_color.lightened(0.18)
			"locked":
				state_alpha = 0.46
				core_color = Color("667083")
			"teaser":
				state_alpha = 0.34
				core_color = Color("777b8a")
		var pulse := 1.0 + (sin(pulse_phase) * 0.12 if visual_state == "available" and affordable else 0.0)
		if star_kind == "nebula":
			draw_circle(center + Vector2(-3.0, 1.0), radius * 2.5 * pulse, Color(branch_color, 0.08 * state_alpha))
			draw_circle(center + Vector2(3.0, -2.0), radius * 1.8 * pulse, Color(core_color, 0.12 * state_alpha))
		else:
			draw_circle(center, radius * 2.7 * pulse, Color(branch_color, 0.08 * state_alpha))
		if visual_state == "available" or visual_state == "purchased" or hovered:
			draw_circle(center, radius * 1.65 * pulse, Color(branch_color, (0.20 if hovered else 0.13) * state_alpha), false, 1.4, true)
		draw_circle(center, radius * pulse, Color(core_color, state_alpha))
		draw_circle(center, maxf(1.2, radius * 0.33), Color(1.0, 1.0, 1.0, state_alpha))
		if visual_state == "purchased" or (visual_state == "available" and affordable):
			var glint := radius * (2.3 if visual_state == "purchased" else 1.9)
			draw_line(center - Vector2(glint, 0), center + Vector2(glint, 0), Color(core_color, 0.42 * state_alpha), 1.0, true)
			draw_line(center - Vector2(0, glint), center + Vector2(0, glint), Color(core_color, 0.32 * state_alpha), 1.0, true)
		if visual_state == "teaser":
			draw_string(ThemeDB.fallback_font, center + Vector2(-3.5, 4.0), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("a8adbd"))
		if hold_ratio > 0.0:
			draw_arc(center, radius + 7.0, -PI * 0.5, -PI * 0.5 + TAU * hold_ratio, 32, Color("fff3a3"), 2.4, true)

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
var detail_star: Label
var detail_description: Label
var detail_meta: Label
var detail_action_button: Button
var title_label: Label
var subtitle_label: Label
var reset_view_button: Button
var zoom_out_button: Button
var zoom_in_button: Button
var zoom_label: Label
var close_button: Button
var legend_label: Label
var controls_label: Label

var node_buttons: Dictionary = {}
var node_names: Dictionary = {}
var node_hold_bars: Dictionary = {}
var branch_labels: Dictionary = {}
var star_positions: Dictionary = {}
var node_positions: Dictionary = {}
var node_star_records: Dictionary = {}

var selected_node_id: String = ""
var held_node_id: String = ""
var hold_elapsed: float = 0.0
var zoom: float = 0.78
var pan_position := Vector2.ZERO
var rotation_offset: float = DEFAULT_ROTATION
var panning: bool = false
var pan_mouse_button: int = 0
var paused_by_tree: bool = false
var refresh_pending: bool = false
var node_visual_keys: Dictionary = {}
var intermission_active: bool = false
var intermission_next_round: int = 1
var intermission_next_duration: int = 20


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	node_star_records = ChartData.node_star_map()
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
	rotation_offset = settings_controller.get_research_chart_rotation()
	_layout_chart()
	_apply_locale()


func open_tree() -> void:
	if overlay.visible or progression == null:
		return
	_cancel_node_hold()
	overlay.visible = true
	_hide_node_detail()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	paused_by_tree = not get_tree().paused
	get_tree().paused = true
	_refresh()
	call_deferred("_frame_frontier")
	tree_opened.emit()


func close_tree() -> void:
	if not overlay.visible:
		return
	_cancel_node_hold()
	overlay.visible = false
	panning = false
	pan_mouse_button = 0
	_hide_node_detail()
	if paused_by_tree:
		get_tree().paused = false
	paused_by_tree = false
	if settings_controller != null:
		settings_controller.set_research_chart_rotation(rotation_offset)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	tree_closed.emit()


func is_open() -> bool:
	return overlay != null and overlay.visible


func set_intermission_context(next_round: int, next_duration: int) -> void:
	intermission_active = true
	intermission_next_round = maxi(1, next_round)
	intermission_next_duration = maxi(1, next_duration)
	_refresh_phase_context()


func clear_intermission_context() -> void:
	intermission_active = false
	_refresh_phase_context()


func _refresh_phase_context() -> void:
	if subtitle_label == null or close_button == null:
		return
	if intermission_active:
		subtitle_label.text = tr("TREE_INTERMISSION_SUBTITLE") % [intermission_next_round, intermission_next_duration]
		close_button.text = tr("TREE_START_OBSERVATION")
	else:
		subtitle_label.text = tr("TREE_SUBTITLE")
		close_button.text = tr("TREE_CLOSE")


func _input(event: InputEvent) -> void:
	if not is_open():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_U:
			close_tree()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton and not event.pressed and event.button_index == pan_mouse_button:
		panning = false
		pan_mouse_button = 0


func _process(delta: float) -> void:
	if held_node_id.is_empty():
		return
	if not is_open() or progression == null:
		_cancel_node_hold()
		return
	if progression.get_node_state(held_node_id) != "available" or not progression.can_purchase(held_node_id):
		_cancel_node_hold()
		return
	hold_elapsed = minf(HOLD_PURCHASE_SECONDS, hold_elapsed + delta)
	var hold_bar: StarNodeVisual = node_hold_bars[held_node_id]
	hold_bar.set_fill_progress(hold_elapsed / HOLD_PURCHASE_SECONDS, hold_elapsed)
	if hold_elapsed >= HOLD_PURCHASE_SECONDS:
		_complete_node_hold()


func _on_tree_viewport_gui_input(event: InputEvent) -> void:
	if not is_open():
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				panning = true
				pan_mouse_button = event.button_index
			elif pan_mouse_button == event.button_index:
				panning = false
				pan_mouse_button = 0
			get_viewport().set_input_as_handled()
			return
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if event.ctrl_pressed:
				_zoom_at(event.position, 1.10)
			else:
				_rotate_chart(-ROTATION_STEP)
			get_viewport().set_input_as_handled()
			return
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if event.ctrl_pressed:
				_zoom_at(event.position, 1.0 / 1.10)
			else:
				_rotate_chart(ROTATION_STEP)
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


func _zoom_from_center(factor: float) -> void:
	if content_clip == null:
		return
	_zoom_at(content_clip.global_position + content_clip.size * 0.5, factor)


func _reset_view() -> void:
	rotation_offset = DEFAULT_ROTATION
	_layout_chart()
	if settings_controller != null:
		settings_controller.set_research_chart_rotation(rotation_offset)
	_frame_frontier()


func _frame_frontier() -> void:
	if content_clip == null or content_clip.size.x <= 1.0 or content_clip.size.y <= 1.0:
		return
	var visible_bounds := Rect2(CHART_ORIGIN, Vector2.ZERO)
	for point_variant in star_positions.values():
		var point := Vector2(point_variant)
		visible_bounds = visible_bounds.expand(point)
	visible_bounds = visible_bounds.grow(72.0)
	var horizontal_extent := maxf(absf(visible_bounds.position.x - CHART_ORIGIN.x), absf(visible_bounds.end.x - CHART_ORIGIN.x))
	var upward_extent := maxf(1.0, CHART_ORIGIN.y - visible_bounds.position.y)
	zoom = clampf(
		minf((content_clip.size.x - 36.0) / maxf(horizontal_extent * 2.0, 1.0), (content_clip.size.y - 28.0) / upward_extent) * 0.94,
		MIN_ZOOM,
		1.0
	)
	pan_position = Vector2(content_clip.size.x * 0.5, content_clip.size.y - 18.0) - CHART_ORIGIN * zoom
	_apply_transform()


func _on_content_resized() -> void:
	if is_open() and content_clip.size.x > 1.0 and content_clip.size.y > 1.0:
		call_deferred("_frame_frontier")


func _apply_transform() -> void:
	tree_canvas.position = pan_position
	tree_canvas.scale = Vector2.ONE * zoom
	if zoom_label != null:
		zoom_label.text = "%d%%" % int(round(zoom * 100.0))


func _rotate_chart(amount: float) -> void:
	rotation_offset = wrapf(rotation_offset + amount, -PI, PI)
	if settings_controller != null:
		settings_controller.set_research_chart_rotation(rotation_offset, false)
	_layout_chart()


func _layout_chart() -> void:
	if tree_canvas == null:
		return
	star_positions.clear()
	node_positions.clear()
	for constellation_id in ChartData.CONSTELLATIONS:
		var constellation: Dictionary = ChartData.CONSTELLATIONS[constellation_id]
		var placement: Dictionary = ChartData.PLACEMENTS[constellation_id]
		var anchor := CHART_ORIGIN + Vector2.RIGHT.rotated(float(placement.anchor_angle)) * float(placement.anchor_radius)
		var tilt := float(placement.tilt)
		var scale_amount := float(placement.scale)
		for star_variant in constellation.stars:
			var star: Dictionary = star_variant
			var local_offset := Vector2(star.local_position).rotated(tilt) * scale_amount
			var base_position := anchor + local_offset
			var chart_position := CHART_ORIGIN + (base_position - CHART_ORIGIN).rotated(rotation_offset)
			var star_key := "%s/%s" % [constellation_id, String(star.id)]
			star_positions[star_key] = chart_position
			var node_id := String(star.get("node_id", ""))
			if not node_id.is_empty():
				node_positions[node_id] = chart_position
	for node_id in node_positions:
		if not node_buttons.has(node_id):
			continue
		var button: Button = node_buttons[node_id]
		var label: Label = node_names[node_id]
		var center := Vector2(node_positions[node_id])
		button.position = center - button.size * 0.5
		var label_direction := 1.0 if center.x < CHART_ORIGIN.x else -1.0
		label.position = center + Vector2(12.0 * label_direction, -18.0)
		if label_direction < 0.0:
			label.position.x -= label.size.x
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if label_direction > 0.0 else HORIZONTAL_ALIGNMENT_RIGHT
	_layout_branch_labels()
	tree_canvas.queue_redraw()


func _layout_branch_labels() -> void:
	for constellation_id in ChartData.CONSTELLATIONS:
		var constellation: Dictionary = ChartData.CONSTELLATIONS[constellation_id]
		var branch_id := String(constellation.branch)
		if not branch_labels.has(branch_id):
			continue
		var placement: Dictionary = ChartData.PLACEMENTS[constellation_id]
		var anchor := CHART_ORIGIN + Vector2.RIGHT.rotated(float(placement.anchor_angle)) * float(placement.anchor_radius)
		var rotated_anchor := CHART_ORIGIN + (anchor - CHART_ORIGIN).rotated(rotation_offset)
		var label: Label = branch_labels[branch_id]
		label.position = rotated_anchor + Vector2(-110.0, -118.0)


func _on_node_hold_started(node_id: String) -> void:
	_cancel_node_hold()
	_show_node_detail(node_id)
	if progression == null or progression.get_node_state(node_id) != "available" or not progression.can_purchase(node_id):
		return
	held_node_id = node_id
	hold_elapsed = 0.0
	var hold_bar: StarNodeVisual = node_hold_bars[node_id]
	hold_bar.clear_fill()


func _on_node_hold_released(node_id: String) -> void:
	if held_node_id == node_id:
		_cancel_node_hold()


func _complete_node_hold() -> void:
	if held_node_id.is_empty():
		return
	var completed_node_id := held_node_id
	var hold_bar: StarNodeVisual = node_hold_bars[completed_node_id]
	held_node_id = ""
	hold_elapsed = 0.0
	if progression.request_purchase(completed_node_id):
		var definition := Balance.upgrade_definition(completed_node_id)
		tree_status.text = tr("TREE_STATUS_ONLINE") % _upgrade_name(definition)
	hold_bar.clear_fill()


func _cancel_node_hold() -> void:
	if not held_node_id.is_empty() and node_hold_bars.has(held_node_id):
		var hold_bar: StarNodeVisual = node_hold_bars[held_node_id]
		hold_bar.clear_fill()
	held_node_id = ""
	hold_elapsed = 0.0


func _on_node_hovered(node_id: String) -> void:
	if node_hold_bars.has(node_id):
		var star_visual: StarNodeVisual = node_hold_bars[node_id]
		star_visual.set_hovered(true)
	_show_node_detail(node_id)


func _on_node_unhovered(node_id: String) -> void:
	if node_hold_bars.has(node_id):
		var star_visual: StarNodeVisual = node_hold_bars[node_id]
		star_visual.set_hovered(false)
	if held_node_id == node_id:
		_cancel_node_hold()


func _hide_node_detail() -> void:
	var previous_node_id := selected_node_id
	selected_node_id = ""
	if progression != null and not previous_node_id.is_empty() and node_names.has(previous_node_id):
		node_names[previous_node_id].visible = progression.get_node_state(previous_node_id) != "purchased"
	if detail_panel != null:
		detail_branch.text = tr("TREE_INSPECTOR_LABEL")
		detail_name.text = tr("TREE_INSPECTOR_TITLE")
		detail_star.text = ""
		detail_description.text = tr("TREE_INSPECTOR_HINT")
		detail_meta.text = tr("TREE_INSPECTOR_META")
		detail_action_button.text = tr("TREE_SELECT_NODE")
		detail_action_button.disabled = true
		detail_panel.add_theme_stylebox_override("panel", _panel_style(Color("0b1020"), Color("2d4055"), 12, 1))
		detail_panel.visible = true
	if tree_canvas != null:
		tree_canvas.queue_redraw()


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
		var button: Button = node_buttons[node_id]
		var name_label: Label = node_names[node_id]
		button.visible = visible
		name_label.visible = visible and (visual_state != "purchased" or node_id == selected_node_id)
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
	if not selected_node_id.is_empty() and node_buttons.has(selected_node_id) and node_buttons[selected_node_id].visible:
		_show_node_detail(selected_node_id)
	else:
		var recommended_node_id := _recommended_node_id()
		if recommended_node_id.is_empty():
			_hide_node_detail()
		else:
			_show_node_detail(recommended_node_id)
	tree_canvas.queue_redraw()


func _recommended_node_id() -> String:
	var first_available := ""
	var first_visible := ""
	for definition in Balance.UPGRADE_NODES:
		var node_id := String(definition.id)
		var button: Button = node_buttons[node_id]
		if not button.visible:
			continue
		if first_visible.is_empty():
			first_visible = node_id
		if progression.get_node_state(node_id) == "available":
			if progression.can_purchase(node_id):
				return node_id
			if first_available.is_empty():
				first_available = node_id
	return first_available if not first_available.is_empty() else first_visible


func _is_teaser_visible(definition: Dictionary) -> bool:
	for gate_variant in definition.hidden_until:
		var gate_state: String = progression.get_node_state(String(gate_variant))
		if gate_state != "hidden" and gate_state != "missing":
			return true
	return false


func _apply_node_visual(definition: Dictionary, visual_state: String) -> void:
	var node_id := String(definition.id)
	var branch: Dictionary = Balance.BRANCHES[String(definition.branch)]
	var branch_color: Color = branch.color
	var name_label: Label = node_names[node_id]
	var star_visual: StarNodeVisual = node_hold_bars[node_id]
	var star_record: Dictionary = node_star_records[node_id]
	var star: Dictionary = star_record.star
	var name_color := Color("c8d5e1")
	name_label.text = _upgrade_name(definition)
	match visual_state:
		"purchased":
			name_color = branch_color.lightened(0.28)
		"available":
			if progression.can_purchase(node_id):
				name_color = Color("fff0a8")
			else:
				name_color = branch_color.lightened(0.06)
		"locked":
			name_color = Color("747d8d")
		"teaser":
			name_color = Color("5f6373")
			name_label.text = tr("TREE_UNKNOWN_SIGNAL")
	name_label.add_theme_color_override("font_color", name_color)
	star_visual.configure(visual_state, branch_color, float(star.magnitude), String(star.kind), progression.can_purchase(node_id))


func _show_node_detail(node_id: String) -> void:
	if progression == null or not node_buttons.has(node_id) or not node_buttons[node_id].visible:
		return
	var previous_node_id := selected_node_id
	selected_node_id = node_id
	if not previous_node_id.is_empty() and previous_node_id != node_id and node_names.has(previous_node_id):
		node_names[previous_node_id].visible = progression.get_node_state(previous_node_id) != "purchased"
	node_names[node_id].visible = true
	var definition := Balance.upgrade_definition(node_id)
	var branch: Dictionary = Balance.BRANCHES[String(definition.branch)]
	var branch_color: Color = branch.color
	var visual_state := String(node_buttons[node_id].get_meta("visual_state"))
	var star_record: Dictionary = node_star_records[node_id]
	var star: Dictionary = star_record.star
	detail_star.text = "%s  ·  %s" % [tr(String(star.name_key)), String(star.bayer)]
	if visual_state == "teaser":
		detail_branch.text = "%s  /  %s" % [_branch_name(String(definition.branch)), tr("TREE_UNRESOLVED_SIGNAL")]
		detail_name.text = "???"
		detail_description.text = tr("TREE_TEASER_DESCRIPTION")
		detail_meta.text = tr("TREE_SIGNAL_OBSCURED")
		detail_action_button.text = tr("TREE_SIGNAL_BUTTON")
		detail_action_button.disabled = true
	else:
		detail_branch.text = "%s  /  %s" % [_branch_name(String(definition.branch)), tr("EFFECT_%s" % String(definition.effect_type).to_upper())]
		detail_name.text = _upgrade_name(definition)
		detail_description.text = _upgrade_description(definition)
		match visual_state:
			"purchased":
				detail_meta.text = tr("TREE_SYSTEM_ONLINE")
				detail_action_button.text = tr("TREE_SYSTEM_ONLINE")
				detail_action_button.disabled = true
			"available":
				if progression.can_purchase(node_id):
					detail_meta.text = tr("TREE_INSTALL") % int(definition.cost)
					detail_action_button.text = tr("TREE_INSTALL_BUTTON") % int(definition.cost)
					detail_action_button.disabled = true
				else:
					var missing := int(ceil(float(definition.cost) - progression.observation_data))
					detail_meta.text = tr("TREE_NEED_MORE") % [int(floor(progression.observation_data)), int(definition.cost)]
					detail_action_button.text = tr("TREE_NEED_DATA_BUTTON") % missing
					detail_action_button.disabled = true
			_:
				var prerequisite_names: Array[String] = []
				for prerequisite_variant in definition.prerequisites:
					var prerequisite := Balance.upgrade_definition(String(prerequisite_variant))
					prerequisite_names.append(_upgrade_name(prerequisite))
					detail_meta.text = tr("TREE_REQUIRES") % ", ".join(prerequisite_names)
				detail_action_button.text = tr("TREE_LOCKED_BUTTON")
				detail_action_button.disabled = true
	detail_branch.add_theme_color_override("font_color", branch_color)
	detail_meta.add_theme_color_override("font_color", Color("ffe078") if visual_state == "available" and progression.can_purchase(node_id) else branch_color.lightened(0.2))
	detail_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.035, 0.045, 0.09, 0.97), branch_color, 12, 2))
	detail_panel.visible = true
	tree_canvas.queue_redraw()


func _on_language_changed(_locale: String) -> void:
	_apply_locale()


func _apply_locale() -> void:
	if overlay == null:
		return
	title_label.text = tr("TREE_TITLE")
	reset_view_button.text = tr("TREE_CENTER")
	_refresh_phase_context()
	legend_label.text = tr("TREE_LEGEND")
	controls_label.text = "    " + tr("TREE_CONTROLS")
	for constellation_id in ChartData.CONSTELLATIONS:
		var constellation: Dictionary = ChartData.CONSTELLATIONS[constellation_id]
		branch_labels[String(constellation.branch)].text = tr(String(constellation.label_key))
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
	var zoom_controls := HBoxContainer.new()
	zoom_controls.add_theme_constant_override("separation", 3)
	top_row.add_child(zoom_controls)
	zoom_out_button = Button.new()
	zoom_out_button.text = "−"
	zoom_out_button.custom_minimum_size = Vector2(34, 34)
	_style_header_button(zoom_out_button)
	zoom_out_button.pressed.connect(_zoom_from_center.bind(1.0 / 1.10))
	zoom_controls.add_child(zoom_out_button)
	zoom_label = _make_label("78%", 10, Color("8297aa"))
	zoom_label.custom_minimum_size = Vector2(46, 34)
	zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zoom_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	zoom_controls.add_child(zoom_label)
	zoom_in_button = Button.new()
	zoom_in_button.text = "+"
	zoom_in_button.custom_minimum_size = Vector2(34, 34)
	_style_header_button(zoom_in_button)
	zoom_in_button.pressed.connect(_zoom_from_center.bind(1.10))
	zoom_controls.add_child(zoom_in_button)
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

	var content_row := HBoxContainer.new()
	content_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_row.add_theme_constant_override("separation", 10)
	column.add_child(content_row)
	var content_frame := PanelContainer.new()
	content_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_frame.add_theme_stylebox_override("panel", _panel_style(Color("060817"), Color("202d43"), 10, 1))
	content_row.add_child(content_frame)
	content_clip = Control.new()
	content_clip.name = "TreeViewport"
	content_clip.clip_contents = true
	content_clip.mouse_filter = Control.MOUSE_FILTER_PASS
	content_clip.resized.connect(_on_content_resized)
	content_clip.gui_input.connect(_on_tree_viewport_gui_input)
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
	_build_detail_panel(content_row)
	_layout_chart()


func _build_branch_labels() -> void:
	for constellation_id in ChartData.CONSTELLATIONS:
		var constellation: Dictionary = ChartData.CONSTELLATIONS[constellation_id]
		var branch_id := String(constellation.branch)
		var branch: Dictionary = Balance.BRANCHES[branch_id]
		var label := _make_label(tr(String(constellation.label_key)), 15, branch.color)
		label.position = Vector2.ZERO
		label.size = Vector2(300, 28)
		tree_canvas.add_child(label)
		branch_labels[branch_id] = label


func _build_node_button(definition: Dictionary) -> void:
	var node_id := String(definition.id)
	var major: bool = bool(definition.major)
	var button := Button.new()
	button.name = "Node_" + node_id
	button.position = Vector2.ZERO
	button.size = STAR_HIT_SIZE
	button.custom_minimum_size = STAR_HIT_SIZE
	button.clip_contents = false
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.focus_mode = Control.FOCUS_NONE
	button.set_meta("node_id", node_id)
	button.set_meta("visual_state", "hidden")
	for style_name in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(style_name, StyleBoxEmpty.new())
	button.button_down.connect(_on_node_hold_started.bind(node_id))
	button.button_up.connect(_on_node_hold_released.bind(node_id))
	button.mouse_entered.connect(_on_node_hovered.bind(node_id))
	button.mouse_exited.connect(_on_node_unhovered.bind(node_id))
	tree_canvas.add_child(button)

	var star_visual := StarNodeVisual.new()
	star_visual.name = "StarVisual"
	star_visual.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	star_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var branch_color: Color = Balance.BRANCHES[String(definition.branch)].color
	var star_record: Dictionary = node_star_records[node_id]
	var star: Dictionary = star_record.star
	star_visual.configure("hidden", branch_color, float(star.magnitude), String(star.kind), false)
	button.add_child(star_visual)

	var name_label := _make_label(_upgrade_name(definition), 12 if major else 11, Color("c8d5e1"))
	name_label.position = Vector2.ZERO
	name_label.size = Vector2(154, 38)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tree_canvas.add_child(name_label)

	node_buttons[node_id] = button
	node_names[node_id] = name_label
	node_hold_bars[node_id] = star_visual


func _build_detail_panel(parent: Control) -> void:
	detail_panel = PanelContainer.new()
	detail_panel.name = "SystemInspector"
	detail_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	detail_panel.custom_minimum_size = Vector2(306.0, 0.0)
	detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_panel.add_theme_stylebox_override("panel", _panel_style(Color("0b1020"), Color("2d4055"), 12, 1))
	parent.add_child(detail_panel)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 18)
	detail_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_theme_constant_override("separation", 7)
	margin.add_child(column)
	detail_branch = _make_label(tr("TREE_INSPECTOR_LABEL"), 10, Color("6f879b"))
	column.add_child(detail_branch)
	detail_name = _make_label(tr("TREE_INSPECTOR_TITLE"), 20, Color("f3f8ff"))
	detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(detail_name)
	detail_star = _make_label("", 11, Color("7692aa"))
	detail_star.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(detail_star)
	var divider := HSeparator.new()
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(divider)
	detail_description = _make_label(tr("TREE_INSPECTOR_HINT"), 12, Color("b4c2d2"))
	detail_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(detail_description)
	detail_meta = _make_label(tr("TREE_INSPECTOR_META"), 12, Color("7f9caf"))
	detail_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(detail_meta)
	detail_action_button = Button.new()
	detail_action_button.text = tr("TREE_SELECT_NODE")
	detail_action_button.custom_minimum_size = Vector2(0, 44)
	detail_action_button.disabled = true
	detail_action_button.add_theme_font_size_override("font_size", 13)
	detail_action_button.add_theme_color_override("font_color", Color("e8fbff"))
	detail_action_button.add_theme_color_override("font_disabled_color", Color("bdefff"))
	detail_action_button.add_theme_stylebox_override("normal", _panel_style(Color("12354b"), Color("4a7c96"), 7, 1))
	detail_action_button.add_theme_stylebox_override("hover", _panel_style(Color("18536d"), Color("72bdd5"), 7, 1))
	detail_action_button.add_theme_stylebox_override("pressed", _panel_style(Color("0d2a3b"), Color("8bdff0"), 7, 1))
	detail_action_button.add_theme_stylebox_override("disabled", _panel_style(Color("101726"), Color("29384a"), 7, 1))
	column.add_child(detail_action_button)


func _connection_points(source_id: String, target_id: String) -> PackedVector2Array:
	var start := Vector2(node_positions[source_id])
	var finish := Vector2(node_positions[target_id])
	var direction := start.direction_to(finish)
	if direction.is_zero_approx():
		return PackedVector2Array([start, finish])
	start += direction * (_node_visual_radius(source_id) + 2.0)
	finish -= direction * (_node_visual_radius(target_id) + 2.0)
	return PackedVector2Array([start, finish])


func _node_visual_radius(node_id: String) -> float:
	if node_hold_bars.has(node_id):
		var star_visual: StarNodeVisual = node_hold_bars[node_id]
		return star_visual.visual_radius()
	var star_record: Dictionary = node_star_records[node_id]
	return _magnitude_radius(float(star_record.star.magnitude))


func _magnitude_radius(magnitude: float) -> float:
	return clampf(7.4 - magnitude * 0.82, 3.4, 7.4)


func _frontier_connections() -> Array[PackedStringArray]:
	var result: Array[PackedStringArray] = []
	if progression == null:
		return result
	for definition in Balance.UPGRADE_NODES:
		var target_id := String(definition.id)
		if progression.get_node_state(target_id) != "available":
			continue
		for prerequisite_variant in definition.prerequisites:
			var source_id := String(prerequisite_variant)
			if progression.get_node_state(source_id) == "purchased":
				result.append(PackedStringArray([source_id, target_id]))
	return result


func _draw_tree() -> void:
	for index in range(BACKGROUND_STARS.size()):
		var background_position := CHART_ORIGIN + (Vector2(BACKGROUND_STARS[index]) - CHART_ORIGIN).rotated(rotation_offset)
		var radius := 1.7 if index % 5 == 0 else 1.0
		var alpha := 0.28 if index % 5 == 0 else 0.16
		tree_canvas.draw_circle(background_position, radius, Color(0.65, 0.82, 1.0, alpha))
	_draw_chart_horizon()
	for constellation_id in ChartData.CONSTELLATIONS:
		var constellation: Dictionary = ChartData.CONSTELLATIONS[constellation_id]
		var branch_color: Color = Balance.BRANCHES[String(constellation.branch)].color
		for segment_variant in constellation.segments:
			var segment: Array = segment_variant
			var start := Vector2(star_positions["%s/%s" % [constellation_id, String(segment[0])]])
			var finish := Vector2(star_positions["%s/%s" % [constellation_id, String(segment[1])]])
			tree_canvas.draw_line(start, finish, Color("02050c"), 4.2, true)
			tree_canvas.draw_line(start, finish, Color(branch_color, 0.25), 1.45, true)
		for star_variant in constellation.stars:
			var star: Dictionary = star_variant
			var point := Vector2(star_positions["%s/%s" % [constellation_id, String(star.id)]])
			var star_radius := _magnitude_radius(float(star.magnitude))
			var node_id := String(star.get("node_id", ""))
			var alpha := 0.23 if node_id.is_empty() else 0.12
			if String(star.kind) == "nebula":
				tree_canvas.draw_circle(point, star_radius * 2.2, Color(branch_color, alpha * 0.42))
			tree_canvas.draw_circle(point, maxf(1.2, star_radius * 0.55), Color(branch_color.lightened(0.26), alpha))
	if progression == null:
		return
	# Only the current purchasable frontier stays lit. Purchased history is
	# already encoded by stable bright stars, so late-game DAG clutter never grows.
	for frontier_variant in _frontier_connections():
		var frontier: PackedStringArray = frontier_variant
		var source_id := String(frontier[0])
		var target_id := String(frontier[1])
		var connection := _connection_points(source_id, target_id)
		var start := connection[0]
		var finish := connection[1]
		var definition := Balance.upgrade_definition(target_id)
		var branch_color: Color = Balance.BRANCHES[String(definition.branch)].color
		tree_canvas.draw_line(start, finish, Color(0.01, 0.015, 0.035, 0.90), 7.0, true)
		tree_canvas.draw_line(start, finish, Color(branch_color.lightened(0.18), 0.88), 2.8, true)
		tree_canvas.draw_circle(start.lerp(finish, 0.5), 2.4, branch_color.lightened(0.28))
	if not selected_node_id.is_empty() and node_positions.has(selected_node_id):
		var selected_state: String = progression.get_node_state(selected_node_id)
		if selected_state == "locked" or selected_state == "hidden":
			var selected_definition := Balance.upgrade_definition(selected_node_id)
			for prerequisite_variant in selected_definition.prerequisites:
				var source_id := String(prerequisite_variant)
				if progression.get_node_state(source_id) == "purchased":
					continue
				var connection := _connection_points(source_id, selected_node_id)
				_draw_dashed_connection(connection[0], connection[1], Color("79859b"))


func _draw_chart_horizon() -> void:
	var horizon_y := CHART_ORIGIN.y
	var ridge := PackedVector2Array([
		Vector2(0, horizon_y + 9.0), Vector2(TREE_SIZE.x * 0.18, horizon_y - 4.0),
		Vector2(TREE_SIZE.x * 0.36, horizon_y + 2.0), Vector2(TREE_SIZE.x * 0.54, horizon_y - 8.0),
		Vector2(TREE_SIZE.x * 0.76, horizon_y + 1.0), Vector2(TREE_SIZE.x, horizon_y - 5.0),
		Vector2(TREE_SIZE.x, TREE_SIZE.y), Vector2(0, TREE_SIZE.y)
	])
	tree_canvas.draw_colored_polygon(ridge, Color("030611"))
	var dome_center := CHART_ORIGIN + Vector2(0, -2.0)
	tree_canvas.draw_circle(dome_center, 24.0, Color("050a16"))
	tree_canvas.draw_rect(Rect2(dome_center.x - 26.0, dome_center.y, 52.0, 28.0), Color("050a16"))
	tree_canvas.draw_line(dome_center + Vector2(0, -22), dome_center + Vector2(15, -38), Color("14243a"), 3.0, true)
	tree_canvas.draw_circle(dome_center + Vector2(16, -39), 2.2, Color("74a1c7"))


func _draw_dashed_connection(start: Vector2, finish: Vector2, color: Color) -> void:
	var distance := start.distance_to(finish)
	if distance <= 0.01:
		return
	var direction := start.direction_to(finish)
	var cursor := 0.0
	while cursor < distance:
		var dash_end := minf(cursor + 8.0, distance)
		tree_canvas.draw_line(start + direction * cursor, start + direction * dash_end, Color(color, 0.58), 1.4, true)
		cursor += 14.0


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
