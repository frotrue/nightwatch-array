extends CanvasLayer

signal tree_opened
signal tree_closed

const Balance = preload("res://scripts/game_balance.gd")
const ChartData = preload("res://scripts/research_chart_data.gd")
const UITheme = preload("res://scripts/ui_theme.gd")

const TREE_SIZE := Vector2(1460, 780)
const MIN_ZOOM := 0.55
const MAX_ZOOM := 1.28
const HOLD_PURCHASE_SECONDS := 0.75
const CHART_ORIGIN := Vector2(TREE_SIZE.x * 0.5, TREE_SIZE.y * 0.91)
const ROTATION_STEP := deg_to_rad(6.0)
const DEFAULT_ROTATION := 0.0
const STAR_HIT_SIZE := Vector2(44.0, 44.0)
const TOOLTIP_SIZE := Vector2(318.0, 0.0)
const TOOLTIP_CURSOR_OFFSET := 18.0
const TOOLTIP_SCREEN_MARGIN := 10.0
# The field is a disc around the horizon pivot rather than a rectangle over the
# canvas. The chart's sky is wider than the canvas now, so a rectangular field
# left a black quarter on screen at some rotations. Seeded, so the sky is the
# same sky every session.
const BACKGROUND_STAR_COUNT := 150
const BACKGROUND_STAR_MIN_RADIUS := 90.0
const BACKGROUND_STAR_MAX_RADIUS := 1180.0
const BACKGROUND_STAR_SEED := 20260824
const CLUSTER_MARKER_OFFSETS := [
	Vector2(-1.45, -0.42),
	Vector2(-0.62, 0.88),
	Vector2(0.20, -1.08),
	Vector2(0.92, -0.22),
	Vector2(1.35, 0.72),
	Vector2(0.28, 1.36),
]


class StarNodeVisual:
	extends Control
	const PURCHASED_GLOW_SCALE := 2.35
	const PURCHASED_ENDPOINT_GLOW_SCALE := 2.75

	var hold_ratio: float = 0.0
	var branch_color := UITheme.STAR_LOCKED
	var visual_state := "hidden"
	var magnitude: float = 3.0
	var star_kind := "star"
	var affordable := false
	var hovered := false
	var pulse_phase := 0.0
	var branch_endpoint := false


	func set_fill_progress(ratio: float, elapsed: float) -> void:
		hold_ratio = clampf(ratio, 0.0, 1.0)
		pulse_phase = elapsed * 8.0
		queue_redraw()


	func clear_fill() -> void:
		hold_ratio = 0.0
		queue_redraw()


	func configure(state: String, color: Color, apparent_magnitude: float, kind: String, can_afford: bool, is_branch_endpoint: bool) -> void:
		visual_state = state
		branch_color = color
		magnitude = apparent_magnitude
		star_kind = kind
		affordable = can_afford
		branch_endpoint = is_branch_endpoint
		set_process(visual_state == "available" and affordable)
		queue_redraw()


	func set_hovered(value: bool) -> void:
		hovered = value
		queue_redraw()


	func visual_radius() -> float:
		return clampf(7.4 - magnitude * 0.82, 3.4, 7.4)


	func purchased_glow_scale() -> float:
		return PURCHASED_ENDPOINT_GLOW_SCALE if branch_endpoint else PURCHASED_GLOW_SCALE


	func _draw_cluster_marker(center: Vector2, radius: float) -> void:
		# A small asymmetric point group identifies a real cluster without
		# borrowing the circular state language used by research nodes.
		for index in range(CLUSTER_MARKER_OFFSETS.size()):
			var point_radius := maxf(0.72, radius * (0.28 if index % 2 == 0 else 0.20))
			draw_circle(
				center + CLUSTER_MARKER_OFFSETS[index] * radius * 0.72,
				point_radius,
				Color(UITheme.STAR_BACKGROUND, 0.30)
			)


	func _draw_galaxy_marker(center: Vector2, radius: float) -> void:
		# Research state follows M31's elongated deep-sky mark instead of borrowing
		# the circular halo used by stellar nodes.
		var axis := Vector2(1.0, 0.32).normalized()
		var extent := radius * 2.35
		match visual_state:
			"purchased":
				draw_line(center - axis * extent, center + axis * extent, Color(UITheme.STAR_INSTALLED_GLOW, 0.58), maxf(2.0, radius * 1.15), true)
				draw_line(center - axis * extent * 0.88, center + axis * extent * 0.88, UITheme.STAR_INSTALLED, maxf(1.0, radius * 0.28), true)
			"available":
				var ready_color := UITheme.STAR_READY_FILL if affordable else UITheme.STAR_SHORT_BORDER
				var ready_alpha := 0.72 + (0.18 * sin(pulse_phase) if affordable else 0.0)
				draw_line(center - axis * extent, center + axis * extent, Color(ready_color, ready_alpha), maxf(1.0, radius * 0.34), true)
			"locked", "teaser":
				draw_line(center - axis * extent * 0.76, center + axis * extent * 0.76, Color(UITheme.STAR_LOCKED, 0.28), maxf(0.8, radius * 0.22), true)
			_:
				draw_line(center - axis * extent * 0.70, center + axis * extent * 0.70, Color(UITheme.STAR_BACKGROUND, 0.30), maxf(0.8, radius * 0.20), true)
		if hovered and visual_state != "hidden":
			draw_line(center - axis * extent * 1.18, center + axis * extent * 1.18, Color(UITheme.STAR_READY_RING, 0.34), maxf(1.0, radius * 0.18), true)
		if hold_ratio > 0.0:
			var track_start := center - axis * extent * 1.22
			var track_finish := center + axis * extent * 1.22
			draw_line(track_start, track_finish, Color(UITheme.HORIZON_TICK, 0.40), 1.0, true)
			draw_line(track_start, track_start.lerp(track_finish, hold_ratio), UITheme.STAR_READY_RING, UITheme.px(2.6), true)


	func _process(delta: float) -> void:
		pulse_phase = fmod(pulse_phase + delta * 3.2, TAU)
		queue_redraw()


	func _draw() -> void:
		var center := size * 0.5
		var radius := visual_radius()
		var pulse := 1.0 + (sin(pulse_phase) * 0.12 if visual_state == "available" and affordable else 0.0)
		if star_kind == "galaxy":
			_draw_galaxy_marker(center, radius)
			return
		if star_kind == "cluster" and visual_state != "hidden":
			_draw_cluster_marker(center, radius)
		match visual_state:
			"purchased":
				draw_circle(center, radius * purchased_glow_scale(), Color(UITheme.STAR_INSTALLED_GLOW, 0.70))
				draw_circle(center, radius, UITheme.STAR_INSTALLED)
			"available":
				if affordable:
					draw_circle(center, radius * 5.2 * pulse, Color(UITheme.STAR_READY_RING, 0.50), false, 1.0, true)
					draw_circle(center, radius, UITheme.STAR_READY_FILL)
					draw_circle(center, radius, UITheme.STAR_READY_BORDER, false, 1.0, true)
				else:
					draw_circle(center, radius, UITheme.STAR_SHORT_BORDER, false, 1.0, true)
			"locked", "teaser":
				draw_circle(center, maxf(1.5, radius * 0.6), Color(UITheme.STAR_LOCKED, 0.24))
			_:
				draw_circle(center, maxf(1.25, radius * 0.5), Color(UITheme.STAR_BACKGROUND, 0.30))
		if hovered and visual_state != "hidden":
			draw_circle(center, radius * 2.6, Color(UITheme.STAR_READY_RING, 0.28), false, 1.0, true)
		if hold_ratio > 0.0:
			# The gauge wraps the star so hand and eye watch the same place.
			draw_arc(center, radius + UITheme.px(11.0), 0.0, TAU, 48, Color(UITheme.HORIZON_TICK, 0.40), 1.0, true)
			draw_arc(
				center,
				radius + UITheme.px(11.0),
				-PI * 0.5,
				-PI * 0.5 + TAU * hold_ratio,
				48,
				UITheme.STAR_READY_RING,
				UITheme.px(2.6),
				true
			)


var progression: Node
var settings_controller: Node
var overlay: Control
var content_clip: Control
var tree_canvas: Control
var data_readout: Label
var systems_readout: Label
var tree_status: Label
var tooltip_panel: PanelContainer
var tooltip_branch: Label
var tooltip_name: Label
var tooltip_star: Label
var tooltip_description: Label
var tooltip_meta: Label
var title_label: Label
var installed_caption: Label
var progress_track: ColorRect
var progress_fill: ColorRect
var close_underline: ColorRect
var north_label: Label
var subtitle_label: Label
var close_button: Button
var controls_label: Label

var node_buttons: Dictionary = {}
var node_hold_bars: Dictionary = {}
var star_positions: Dictionary = {}
var node_positions: Dictionary = {}
var node_star_records: Dictionary = {}
var base_star_positions: Dictionary = {}
var star_node_ids: Dictionary = {}

var hovered_node_id: String = ""
var tooltip_suppressed_until_motion: bool = false
var tooltip_content_key: String = ""
var tooltip_refit_pending: bool = false
var held_node_id: String = ""
var hold_elapsed: float = 0.0
var zoom: float = 0.78
var pan_position := Vector2.ZERO
var rotation_offset: float = DEFAULT_ROTATION
var pending_rotation_delta: float = 0.0
var background_stars: PackedVector2Array = PackedVector2Array()
var paused_by_tree: bool = false
var refresh_pending: bool = false
var node_visual_keys: Dictionary = {}
var node_states: Dictionary = {}
var frontier_connections_cache: Array[PackedStringArray] = []
var intermission_active: bool = false
var intermission_next_round: int = 1
var intermission_next_duration: int = 20
var chart_layout_passes: int = 0
var tooltip_content_refreshes: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	node_star_records = ChartData.node_star_map()
	_build_background_stars()
	_cache_chart_geometry()
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
	pending_rotation_delta = 0.0
	overlay.visible = true
	_hide_node_tooltip()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	paused_by_tree = not get_tree().paused
	get_tree().paused = true
	_refresh()
	call_deferred("_frame_frontier")
	tree_opened.emit()


func close_tree() -> void:
	if not overlay.visible:
		return
	_flush_pending_rotation()
	_cancel_node_hold()
	overlay.visible = false
	_hide_node_tooltip()
	_sync_star_animation_processing()
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
		subtitle_label.text = tr("TREE_NEXT_OBSERVATION") % [intermission_next_round, intermission_next_duration]
		close_button.text = tr("TREE_START_OBSERVATION")
	else:
		subtitle_label.text = tr("TREE_SUBTITLE")
		close_button.text = tr("TREE_CLOSE")


func _input(event: InputEvent) -> void:
	if not is_open():
		return
	if event is InputEventMouseMotion and not hovered_node_id.is_empty():
		if tooltip_suppressed_until_motion or not tooltip_panel.visible:
			tooltip_suppressed_until_motion = false
			_show_node_tooltip(hovered_node_id)
		else:
			_position_node_tooltip(overlay.get_local_mouse_position())
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_U:
			close_tree()
			get_viewport().set_input_as_handled()
			return


func _process(delta: float) -> void:
	_flush_pending_rotation()
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
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if event.ctrl_pressed:
				_zoom_at(event.position, 1.10)
			else:
				_queue_chart_rotation(-ROTATION_STEP)
			get_viewport().set_input_as_handled()
			return
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if event.ctrl_pressed:
				_zoom_at(event.position, 1.0 / 1.10)
			else:
				_queue_chart_rotation(ROTATION_STEP)
			get_viewport().set_input_as_handled()
			return


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


func _reset_view(persist: bool = true) -> void:
	pending_rotation_delta = 0.0
	tooltip_suppressed_until_motion = false
	rotation_offset = DEFAULT_ROTATION
	_layout_chart()
	if persist and settings_controller != null:
		settings_controller.set_research_chart_rotation(rotation_offset)
	_frame_frontier()


func _frame_frontier() -> void:
	if content_clip == null or content_clip.size.x <= 1.0 or content_clip.size.y <= 1.0:
		return
	# Frame the figures that carry research, not the whole sky. The background
	# constellations reach past the frame on purpose — the wheel is what brings
	# them over the horizon. Fitting all twelve at once is what made the chart
	# read as one dense clump no matter how far the sky was spread.
	var visible_bounds := Rect2(CHART_ORIGIN, Vector2.ZERO)
	for star_key_variant in star_positions:
		var star_key := String(star_key_variant)
		if not star_node_ids.has(star_key):
			continue
		visible_bounds = visible_bounds.expand(Vector2(star_positions[star_key]))
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
	if north_label != null:
		north_label.position.y = minf(_north_label_y(), controls_label.position.y - north_label.get_combined_minimum_size().y - UITheme.px(6.0))


func _rotate_chart(amount: float) -> void:
	_hide_node_tooltip(false)
	tooltip_suppressed_until_motion = true
	rotation_offset = wrapf(rotation_offset + amount, -PI, PI)
	if settings_controller != null:
		settings_controller.set_research_chart_rotation(rotation_offset, false)
	_layout_chart()


func _queue_chart_rotation(amount: float) -> void:
	if is_zero_approx(pending_rotation_delta):
		_hide_node_tooltip(false)
		tooltip_suppressed_until_motion = true
	pending_rotation_delta = wrapf(pending_rotation_delta + amount, -PI, PI)


func _flush_pending_rotation() -> void:
	if is_zero_approx(pending_rotation_delta):
		return
	var amount := pending_rotation_delta
	pending_rotation_delta = 0.0
	_rotate_chart(amount)


func _grouped(value: int) -> String:
	var digits := str(absi(value))
	var grouped := ""
	for index in range(digits.length()):
		if index > 0 and (digits.length() - index) % 3 == 0:
			grouped += ","
		grouped += digits[index]
	return ("-" if value < 0 else "") + grouped


func _layout_chart_header() -> void:
	if overlay == null or data_readout == null:
		return
	var frame := overlay.size
	var value_size := data_readout.get_combined_minimum_size()
	data_readout.size = value_size
	title_label.position = Vector2(UITheme.px(56.0), UITheme.px(46.0) + value_size.y * 0.86 + UITheme.px(12.0))

	var line_width := UITheme.px(360.0)
	var centre := frame.x * 0.5
	for label in [installed_caption, systems_readout]:
		label.size.x = line_width
		label.position.x = centre - line_width * 0.5
	installed_caption.position.y = UITheme.px(52.0)
	var caption_height := installed_caption.get_combined_minimum_size().y
	systems_readout.position.y = installed_caption.position.y + caption_height + UITheme.px(9.0)
	var count_height := systems_readout.get_combined_minimum_size().y
	var line_y := systems_readout.position.y + count_height + UITheme.px(14.0)
	progress_track.position = Vector2(centre - line_width * 0.5, line_y)
	progress_track.size = Vector2(line_width, 1.0)
	progress_fill.position = progress_track.position
	var ratio := 0.0
	if progression != null:
		ratio = float(progression.upgrade_level) / maxf(1.0, float(Balance.UPGRADE_NODES.size()))
	progress_fill.size = Vector2(line_width * clampf(ratio, 0.0, 1.0), 1.0)

	var action_width := UITheme.px(360.0)
	close_button.size = Vector2(action_width, UITheme.px(30.0))
	close_button.position = Vector2(frame.x - UITheme.px(56.0) - action_width, UITheme.px(50.0))
	var underline_width := close_button.get_theme_font("font").get_string_size(
		close_button.text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		UITheme.size_px(20.0)
	).x + UITheme.px(12.0)
	close_underline.size = Vector2(underline_width, 1.0)
	close_underline.position = Vector2(
		frame.x - UITheme.px(56.0) - underline_width,
		close_button.position.y + close_button.size.y + UITheme.px(7.0)
	)
	subtitle_label.size.x = action_width
	subtitle_label.position = Vector2(
		frame.x - UITheme.px(56.0) - action_width,
		close_underline.position.y + UITheme.px(16.0)
	)

	var wide := frame.x
	for label in [tree_status, controls_label, north_label]:
		label.size.x = wide
		label.position.x = 0.0
	tree_status.position.y = progress_track.position.y + UITheme.px(26.0)
	controls_label.position.y = frame.y - UITheme.px(12.0) - controls_label.get_combined_minimum_size().y
	north_label.position.y = minf(_north_label_y(), controls_label.position.y - north_label.get_combined_minimum_size().y - UITheme.px(6.0))


func _north_label_y() -> float:
	# The label rides with the horizon so the pivot stays legible at any zoom.
	var origin_y := tree_canvas.global_position.y + CHART_ORIGIN.y * zoom - overlay.global_position.y
	return origin_y + UITheme.px(16.0)


func _build_background_stars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = BACKGROUND_STAR_SEED
	background_stars.resize(BACKGROUND_STAR_COUNT)
	var inner := BACKGROUND_STAR_MIN_RADIUS * BACKGROUND_STAR_MIN_RADIUS
	var outer := BACKGROUND_STAR_MAX_RADIUS * BACKGROUND_STAR_MAX_RADIUS
	for index in range(BACKGROUND_STAR_COUNT):
		# Sampling the squared radius keeps the scatter even per unit area.
		# Sampling the radius directly would crowd the stars at the pivot.
		var distance := sqrt(rng.randf_range(inner, outer))
		background_stars[index] = CHART_ORIGIN + Vector2.RIGHT.rotated(rng.randf_range(-PI, PI)) * distance


func _cache_chart_geometry() -> void:
	base_star_positions.clear()
	star_node_ids.clear()
	for constellation_id in ChartData.CONSTELLATIONS:
		var constellation: Dictionary = ChartData.CONSTELLATIONS[constellation_id]
		var placement: Dictionary = ChartData.PLACEMENTS[constellation_id]
		var anchor := CHART_ORIGIN + Vector2.RIGHT.rotated(float(placement.anchor_angle)) * float(placement.anchor_radius)
		var tilt := float(placement.tilt)
		var scale_amount := float(placement.scale)
		for star_variant in constellation.stars:
			var star: Dictionary = star_variant
			var local_offset := Vector2(star.local_position).rotated(tilt) * scale_amount
			var star_key := "%s/%s" % [constellation_id, String(star.id)]
			base_star_positions[star_key] = anchor + local_offset
			var node_id := String(star.get("node_id", ""))
			if not node_id.is_empty():
				star_node_ids[star_key] = node_id


func _layout_chart() -> void:
	if tree_canvas == null:
		return
	chart_layout_passes += 1
	star_positions.clear()
	node_positions.clear()
	for star_key_variant in base_star_positions:
		var star_key := String(star_key_variant)
		var base_position := Vector2(base_star_positions[star_key])
		var chart_position := CHART_ORIGIN + (base_position - CHART_ORIGIN).rotated(rotation_offset)
		star_positions[star_key] = chart_position
		if star_node_ids.has(star_key):
			node_positions[String(star_node_ids[star_key])] = chart_position
	for node_id in node_positions:
		if not node_buttons.has(node_id):
			continue
		var button: Button = node_buttons[node_id]
		var center := Vector2(node_positions[node_id])
		button.position = center - button.size * 0.5
		button.visible = bool(button.get_meta("revealed", true)) and center.y <= CHART_ORIGIN.y
	tree_canvas.queue_redraw()


func _is_node_above_horizon(node_id: String) -> bool:
	# Before the first layout there are no positions yet; the layout pass that
	# follows settles it.
	if not node_positions.has(node_id):
		return true
	return Vector2(node_positions[node_id]).y <= CHART_ORIGIN.y


func _on_node_hold_started(node_id: String) -> void:
	_cancel_node_hold()
	if hovered_node_id == node_id and not tooltip_suppressed_until_motion:
		_show_node_tooltip(node_id)
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
	hovered_node_id = node_id
	if tree_canvas != null:
		tree_canvas.queue_redraw()
	if tooltip_suppressed_until_motion:
		return
	_show_node_tooltip(node_id)


func _on_node_unhovered(node_id: String) -> void:
	if node_hold_bars.has(node_id):
		var star_visual: StarNodeVisual = node_hold_bars[node_id]
		star_visual.set_hovered(false)
	if held_node_id == node_id:
		_cancel_node_hold()
	if hovered_node_id == node_id:
		_hide_node_tooltip()


func _hide_node_tooltip(clear_hover: bool = true) -> void:
	var hover_changed := clear_hover and not hovered_node_id.is_empty()
	if clear_hover:
		hovered_node_id = ""
	if tooltip_panel != null and tooltip_panel.visible:
		tooltip_panel.visible = false
	if hover_changed and tree_canvas != null:
		tree_canvas.queue_redraw()


func _on_purchase_rejected(node_id: String, reason_key: String, value) -> void:
	match reason_key:
		"UPGRADE_ERROR_STATE":
			tree_status.text = tr(reason_key) % tr("STATE_%s" % String(value).to_upper())
		"UPGRADE_ERROR_NEED_DATA":
			tree_status.text = tr(reason_key) % int(value)
		_:
			tree_status.text = tr(reason_key)
	if hovered_node_id == node_id and not tooltip_suppressed_until_motion:
		_show_node_tooltip(node_id)


func _on_progression_state_changed() -> void:
	if is_open():
		_refresh()
	else:
		refresh_pending = true


func _refresh() -> void:
	if progression == null or data_readout == null:
		return
	refresh_pending = false
	data_readout.text = _grouped(int(floor(progression.observation_data)))
	_layout_chart_header()
	systems_readout.text = tr("TREE_PROGRESS_COUNT") % [progression.upgrade_level, Balance.UPGRADE_NODES.size()]
	var available_count := 0
	var affordable_count := 0
	node_states.clear()
	for definition in Balance.UPGRADE_NODES:
		var node_id := String(definition.id)
		var state: String = progression.get_node_state(node_id)
		node_states[node_id] = state
		var visual_state := state
		if state == "hidden" and _is_teaser_visible(definition):
			visual_state = "teaser"
		var visible := visual_state != "hidden"
		var button: Button = node_buttons[node_id]
		# Revealed is the node's own state; whether it is on screen also depends
		# on where the wheel has put it. Both are stored so neither pass undoes
		# the other.
		button.set_meta("revealed", visible)
		button.visible = visible and _is_node_above_horizon(node_id)
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
	_rebuild_frontier_connections()
	if affordable_count > 0:
		tree_status.text = tr("TREE_STATUS_READY") % affordable_count
	elif available_count > 0:
		tree_status.text = tr("TREE_STATUS_PATHS") % available_count
	else:
		tree_status.text = tr("TREE_STATUS_STABLE")
	if not hovered_node_id.is_empty() and node_buttons.has(hovered_node_id) and node_buttons[hovered_node_id].visible:
		if not tooltip_suppressed_until_motion:
			_show_node_tooltip(hovered_node_id)
	else:
		_hide_node_tooltip()
	_sync_star_animation_processing()
	tree_canvas.queue_redraw()


func _is_teaser_visible(definition: Dictionary) -> bool:
	for gate_variant in definition.hidden_until:
		if gate_variant is Dictionary:
			continue
		var gate_state: String = progression.get_node_state(String(gate_variant))
		if gate_state != "hidden" and gate_state != "missing":
			return true
	return false


func _apply_node_visual(definition: Dictionary, visual_state: String) -> void:
	var node_id := String(definition.id)
	var star_visual: StarNodeVisual = node_hold_bars[node_id]
	var star_record: Dictionary = node_star_records[node_id]
	var star: Dictionary = star_record.star
	star_visual.configure(
		visual_state,
		Color.WHITE,
		float(star.magnitude),
		String(star.kind),
		progression.can_purchase(node_id),
		_is_branch_endpoint(definition)
	)


func _is_branch_endpoint(definition: Dictionary) -> bool:
	var node_id := String(definition.id)
	var branch_id := String(definition.branch)
	for candidate in Balance.UPGRADE_NODES:
		if String(candidate.branch) != branch_id:
			continue
		if node_id in candidate.prerequisites:
			return false
	return true


func _sync_star_animation_processing() -> void:
	var chart_active := is_open()
	for node_id in node_hold_bars:
		var star_visual: StarNodeVisual = node_hold_bars[node_id]
		star_visual.set_process(chart_active and star_visual.visual_state == "available" and star_visual.affordable)


func _show_node_tooltip(node_id: String) -> void:
	if progression == null or not node_buttons.has(node_id) or not node_buttons[node_id].visible:
		return
	var visual_state := String(node_buttons[node_id].get_meta("visual_state"))
	var content_key := "%s:%s:%d:%d:%s" % [
		node_id,
		visual_state,
		int(floor(progression.observation_data)),
		int(progression.upgrade_level),
		TranslationServer.get_locale(),
	]
	if tooltip_content_key == content_key:
		var was_visible := tooltip_panel.visible
		tooltip_panel.visible = true
		if not was_visible:
			tooltip_panel.reset_size()
			_request_tooltip_refit()
		_position_node_tooltip(overlay.get_local_mouse_position())
		return
	tooltip_content_key = content_key
	tooltip_content_refreshes += 1
	var definition := Balance.upgrade_definition(node_id)
	var star_record: Dictionary = node_star_records[node_id]
	var star: Dictionary = star_record.star
	var constellation: Dictionary = ChartData.CONSTELLATIONS[String(star_record.constellation_id)]
	var constellation_label := tr(String(constellation.label_key))
	tooltip_star.text = "%s  ·  %s" % [tr(String(star.name_key)), String(star.bayer)]
	if visual_state == "teaser":
		tooltip_branch.text = "%s  /  %s" % [constellation_label, tr("TREE_UNRESOLVED_SIGNAL")]
		tooltip_name.text = "???"
		tooltip_description.text = tr("TREE_TEASER_DESCRIPTION")
		tooltip_meta.text = tr("TREE_SIGNAL_OBSCURED")
	else:
		tooltip_branch.text = "%s  /  %s" % [constellation_label, tr("EFFECT_%s" % String(definition.effect_type).to_upper())]
		tooltip_name.text = _upgrade_name(definition)
		tooltip_description.text = _upgrade_description(definition)
		match visual_state:
			"purchased":
				tooltip_meta.text = tr("TREE_SYSTEM_ONLINE")
			"available":
				if progression.can_purchase(node_id):
					tooltip_meta.text = tr("TREE_INSTALL") % int(definition.cost)
				else:
					tooltip_meta.text = tr("TREE_NEED_MORE") % [int(floor(progression.observation_data)), int(definition.cost)]
			_:
				var prerequisite_names: Array[String] = []
				for prerequisite_variant in definition.prerequisites:
					var prerequisite_id := String(prerequisite_variant)
					if progression.get_node_state(prerequisite_id) == "purchased":
						continue
					var prerequisite := Balance.upgrade_definition(prerequisite_id)
					prerequisite_names.append(_upgrade_name(prerequisite))
				var prerequisite_text := tr("TREE_REQUIRES") % ", ".join(prerequisite_names)
				tooltip_meta.text = "%s  •  %s" % [tr("TREE_COST") % int(definition.cost), prerequisite_text]
	tooltip_branch.add_theme_color_override("font_color", UITheme.TOOLTIP_LABEL)
	tooltip_meta.add_theme_color_override("font_color", UITheme.TOOLTIP_ACTION if visual_state == "available" and progression.can_purchase(node_id) else UITheme.TOOLTIP_VALUE)
	tooltip_panel.visible = true
	tooltip_panel.reset_size()
	_position_node_tooltip(overlay.get_local_mouse_position())
	# Container minimum sizes settle after the text changes. Coalesce their
	# notifications so one content refresh schedules at most one deferred refit.
	_request_tooltip_refit()
	tree_canvas.queue_redraw()


func _on_language_changed(_locale: String) -> void:
	_apply_locale()


func _apply_locale() -> void:
	if overlay == null:
		return
	title_label.text = tr("HUD_DATA_CAPTION")
	installed_caption.text = tr("TREE_INSTALLED_CAPTION")
	north_label.text = tr("TREE_NORTH")
	_refresh_phase_context()
	controls_label.text = tr("TREE_CONTROLS_FULL")
	if progression != null:
		node_visual_keys.clear()
		_refresh()


func _upgrade_name(definition: Dictionary) -> String:
	return tr("UPGRADE_%s_NAME" % String(definition.id).to_upper())


func _upgrade_description(definition: Dictionary) -> String:
	return tr("UPGRADE_%s_DESC" % String(definition.id).to_upper())


func _build_interface() -> void:
	overlay = Control.new()
	overlay.name = "UpgradeTreeOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false
	add_child(overlay)
	overlay.add_theme_font_override("font", UITheme.sans())

	var background := ColorRect.new()
	background.color = Color("04060A")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(background)

	# The chart fills the frame. Information is set on the sky, not inside plates.
	content_clip = Control.new()
	content_clip.name = "TreeViewport"
	content_clip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content_clip.clip_contents = true
	content_clip.mouse_filter = Control.MOUSE_FILTER_PASS
	content_clip.resized.connect(_on_content_resized)
	content_clip.gui_input.connect(_on_tree_viewport_gui_input)
	overlay.add_child(content_clip)

	tree_canvas = Control.new()
	tree_canvas.name = "TreeCanvas"
	tree_canvas.custom_minimum_size = TREE_SIZE
	tree_canvas.size = TREE_SIZE
	tree_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	tree_canvas.draw.connect(_draw_tree)
	content_clip.add_child(tree_canvas)

	var header := Control.new()
	header.name = "ChartHeader"
	header.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(header)

	data_readout = _spec_label("0", UITheme.mono_tabular(), 76.0, UITheme.INK_MAX, -0.03)
	data_readout.position = Vector2(UITheme.px(56.0), UITheme.px(46.0))
	header.add_child(data_readout)
	title_label = _spec_label(tr("HUD_DATA_CAPTION"), UITheme.mono(), 12.0, UITheme.INK_MID, 0.28)
	header.add_child(title_label)

	installed_caption = _spec_label(tr("TREE_INSTALLED_CAPTION"), UITheme.mono(), 12.0, UITheme.INK_MID, 0.30)
	installed_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(installed_caption)
	systems_readout = _spec_label(
		tr("TREE_PROGRESS_COUNT") % [0, Balance.UPGRADE_NODES.size()],
		UITheme.mono_tabular(),
		34.0,
		UITheme.INK_HIGH
	)
	systems_readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(systems_readout)
	progress_track = ColorRect.new()
	progress_track.color = UITheme.ACCENT_DEEP
	progress_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(progress_track)
	progress_fill = ColorRect.new()
	progress_fill.color = UITheme.ACCENT_LINE
	progress_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(progress_fill)

	close_button = Button.new()
	close_button.text = tr("TREE_CLOSE")
	close_button.flat = true
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	close_button.add_theme_font_override("font", UITheme.sans())
	close_button.add_theme_font_size_override("font_size", UITheme.size_px(20.0))
	close_button.add_theme_constant_override("spacing_glyph", UITheme.tracking(UITheme.size_px(20.0), 0.06))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		close_button.add_theme_color_override(state, UITheme.BANNER_TITLE)
	close_button.pressed.connect(close_tree)
	header.add_child(close_button)
	close_underline = ColorRect.new()
	close_underline.color = UITheme.ACCENT_TEXT
	close_underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(close_underline)
	subtitle_label = _spec_label(
		tr("TREE_NEXT_OBSERVATION") % [1, 20],
		UITheme.mono(),
		12.0,
		UITheme.HORIZON_LABEL,
		0.18
	)
	header.add_child(subtitle_label)
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	tree_status = _spec_label("", UITheme.mono(), 12.0, UITheme.ACCENT_TEXT, 0.10)
	tree_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(tree_status)
	controls_label = _spec_label(tr("TREE_CONTROLS_FULL"), UITheme.mono(), 12.0, UITheme.INK_LOW, 0.18)
	controls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(controls_label)
	north_label = _spec_label(tr("TREE_NORTH"), UITheme.mono(), 11.0, UITheme.HORIZON_LABEL, 0.24)
	north_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(north_label)

	header.resized.connect(_layout_chart_header)
	_layout_chart_header()

	for definition in Balance.UPGRADE_NODES:
		_build_node_button(definition)
	_build_node_tooltip()
	_layout_chart()


func _build_node_button(definition: Dictionary) -> void:
	var node_id := String(definition.id)
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
	star_visual.configure(
		"hidden",
		branch_color,
		float(star.magnitude),
		String(star.kind),
		false,
		_is_branch_endpoint(definition)
	)
	button.add_child(star_visual)

	node_buttons[node_id] = button
	node_hold_bars[node_id] = star_visual


func _build_node_tooltip() -> void:
	tooltip_panel = PanelContainer.new()
	tooltip_panel.name = "NodeTooltip"
	tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_panel.custom_minimum_size = TOOLTIP_SIZE
	tooltip_panel.z_index = 100
	tooltip_panel.visible = false
	tooltip_panel.add_theme_stylebox_override("panel", _panel_style(UITheme.TOOLTIP_BACKGROUND, UITheme.TOOLTIP_BORDER, 0, 1))
	overlay.add_child(tooltip_panel)
	tooltip_panel.minimum_size_changed.connect(_request_tooltip_refit)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	tooltip_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 5)
	margin.add_child(column)
	tooltip_branch = _make_label("", 10, UITheme.TOOLTIP_LABEL)
	column.add_child(tooltip_branch)
	tooltip_name = _make_label("", 18, UITheme.TOOLTIP_NAME)
	tooltip_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tooltip_name.custom_minimum_size.x = 290.0
	column.add_child(tooltip_name)
	tooltip_star = _make_label("", 10, UITheme.TOOLTIP_VALUE)
	tooltip_star.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(tooltip_star)
	var divider := HSeparator.new()
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(divider)
	tooltip_description = _make_label("", 11, UITheme.TOOLTIP_BODY)
	tooltip_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tooltip_description.custom_minimum_size.x = 290.0
	column.add_child(tooltip_description)
	tooltip_meta = _make_label("", 11, UITheme.TOOLTIP_LABEL)
	tooltip_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tooltip_meta.custom_minimum_size.x = 290.0
	column.add_child(tooltip_meta)


func _request_tooltip_refit() -> void:
	if tooltip_refit_pending:
		return
	tooltip_refit_pending = true
	_refit_node_tooltip.call_deferred()


func _refit_node_tooltip() -> void:
	tooltip_refit_pending = false
	if tooltip_panel == null or not tooltip_panel.visible or overlay == null:
		return
	tooltip_panel.reset_size()
	_position_node_tooltip(overlay.get_local_mouse_position())


func _position_node_tooltip(cursor_position: Vector2) -> void:
	if tooltip_panel == null or not tooltip_panel.visible or overlay == null:
		return
	var tooltip_size := tooltip_panel.size
	# Control has no to_local/to_global, so the origin is mapped by hand: the chart
	# point scales with the canvas, then shifts from global into overlay space.
	var chart_origin_on_overlay: Vector2 = tree_canvas.global_position + CHART_ORIGIN * tree_canvas.scale - overlay.global_position
	var away_from_origin: Vector2 = cursor_position - chart_origin_on_overlay
	if away_from_origin.is_zero_approx():
		away_from_origin = Vector2(1.0, -1.0)
	var tooltip_position := Vector2(
		cursor_position.x + (TOOLTIP_CURSOR_OFFSET if away_from_origin.x >= 0.0 else -tooltip_size.x - TOOLTIP_CURSOR_OFFSET),
		cursor_position.y + (TOOLTIP_CURSOR_OFFSET if away_from_origin.y >= 0.0 else -tooltip_size.y - TOOLTIP_CURSOR_OFFSET)
	)
	if tooltip_position.x < TOOLTIP_SCREEN_MARGIN:
		tooltip_position.x = cursor_position.x + TOOLTIP_CURSOR_OFFSET
	elif tooltip_position.x + tooltip_size.x > overlay.size.x - TOOLTIP_SCREEN_MARGIN:
		tooltip_position.x = cursor_position.x - tooltip_size.x - TOOLTIP_CURSOR_OFFSET
	if tooltip_position.y < TOOLTIP_SCREEN_MARGIN:
		tooltip_position.y = cursor_position.y + TOOLTIP_CURSOR_OFFSET
	elif tooltip_position.y + tooltip_size.y > overlay.size.y - TOOLTIP_SCREEN_MARGIN:
		tooltip_position.y = cursor_position.y - tooltip_size.y - TOOLTIP_CURSOR_OFFSET
	tooltip_position.x = clampf(tooltip_position.x, TOOLTIP_SCREEN_MARGIN, maxf(TOOLTIP_SCREEN_MARGIN, overlay.size.x - tooltip_size.x - TOOLTIP_SCREEN_MARGIN))
	tooltip_position.y = clampf(tooltip_position.y, TOOLTIP_SCREEN_MARGIN, maxf(TOOLTIP_SCREEN_MARGIN, overlay.size.y - tooltip_size.y - TOOLTIP_SCREEN_MARGIN))
	tooltip_panel.position = tooltip_position


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


func _rebuild_frontier_connections() -> void:
	frontier_connections_cache.clear()
	for definition in Balance.UPGRADE_NODES:
		var target_id := String(definition.id)
		if _cached_node_state(target_id) != "available":
			continue
		for prerequisite_variant in definition.prerequisites:
			var source_id := String(prerequisite_variant)
			if _cached_node_state(source_id) == "purchased":
				frontier_connections_cache.append(PackedStringArray([source_id, target_id]))


func _frontier_connections() -> Array[PackedStringArray]:
	return frontier_connections_cache


func _cached_node_state(node_id: String) -> String:
	if node_states.has(node_id):
		return String(node_states[node_id])
	return String(progression.get_node_state(node_id)) if progression != null else ""


func _draw_tree() -> void:
	for index in range(background_stars.size()):
		var background_position := CHART_ORIGIN + (background_stars[index] - CHART_ORIGIN).rotated(rotation_offset)
		var radius := 1.7 if index % 5 == 0 else 1.0
		var alpha := 0.28 if index % 5 == 0 else 0.16
		tree_canvas.draw_circle(background_position, radius, Color(UITheme.STAR_BACKGROUND, alpha))
	for constellation_id in ChartData.CONSTELLATIONS:
		var constellation: Dictionary = ChartData.CONSTELLATIONS[constellation_id]
		for segment_variant in constellation.segments:
			var segment: Array = segment_variant
			var start := Vector2(star_positions["%s/%s" % [constellation_id, String(segment[0])]])
			var finish := Vector2(star_positions["%s/%s" % [constellation_id, String(segment[1])]])
			var states := _segment_states(constellation_id, segment)
			tree_canvas.draw_line(start, finish, _segment_color(states), _segment_width(states), true)
		for star_variant in constellation.stars:
			var star: Dictionary = star_variant
			var point := Vector2(star_positions["%s/%s" % [constellation_id, String(star.id)]])
			var star_radius := _magnitude_radius(float(star.magnitude))
			var node_id := String(star.get("node_id", ""))
			var alpha := 0.23 if node_id.is_empty() else 0.12
			if node_id.is_empty():
				match String(star.kind):
					"cluster":
						_draw_background_cluster(point, star_radius, alpha)
					"galaxy":
						_draw_background_galaxy(point, star_radius, alpha)
			tree_canvas.draw_circle(point, maxf(1.2, star_radius * 0.55), Color(UITheme.STAR_BACKGROUND, alpha))
	if progression != null:
		_draw_frontier_overlay()
	# The ground goes on last. Half the sky now sits below the horizon at any
	# one rotation, and it has to be buried by the ground rather than drawn
	# over it.
	_draw_chart_horizon()


func _draw_background_cluster(center: Vector2, radius: float, alpha: float) -> void:
	for index in range(CLUSTER_MARKER_OFFSETS.size()):
		var point_radius := maxf(0.65, radius * (0.24 if index % 2 == 0 else 0.17))
		tree_canvas.draw_circle(
			center + CLUSTER_MARKER_OFFSETS[index] * radius * 0.68,
			point_radius,
			Color(UITheme.STAR_BACKGROUND, alpha * 0.82)
		)


func _draw_background_galaxy(center: Vector2, radius: float, alpha: float) -> void:
	# M31 is an elongated deep-sky mark, never a circular interaction halo.
	var axis := Vector2(1.0, 0.32).normalized()
	tree_canvas.draw_line(
		center - axis * radius * 1.75,
		center + axis * radius * 1.75,
		Color(UITheme.STAR_BACKGROUND, alpha * 0.46),
		maxf(0.7, radius * 0.18),
		true
	)
	tree_canvas.draw_circle(center - axis * radius * 0.55, maxf(0.65, radius * 0.16), Color(UITheme.STAR_BACKGROUND, alpha * 0.62))
	tree_canvas.draw_circle(center + axis * radius * 0.46, maxf(0.75, radius * 0.20), Color(UITheme.STAR_BACKGROUND, alpha * 0.72))


func _draw_frontier_overlay() -> void:
	# Only the current purchasable frontier stays lit. Purchased history is
	# already encoded by stable bright stars, so late-game DAG clutter never grows.
	for frontier_variant in _frontier_connections():
		var frontier: PackedStringArray = frontier_variant
		var source_id := String(frontier[0])
		var target_id := String(frontier[1])
		var connection := _connection_points(source_id, target_id)
		var start := connection[0]
		var finish := connection[1]
		tree_canvas.draw_line(start, finish, Color(UITheme.LINE_FRONTIER, 0.60), 1.5, true)
	if not hovered_node_id.is_empty() and node_positions.has(hovered_node_id):
		var hovered_state := _cached_node_state(hovered_node_id)
		if hovered_state == "locked" or hovered_state == "hidden":
			var hovered_definition := Balance.upgrade_definition(hovered_node_id)
			for prerequisite_variant in hovered_definition.prerequisites:
				var source_id := String(prerequisite_variant)
				if _cached_node_state(source_id) == "purchased":
					continue
				var connection := _connection_points(source_id, hovered_node_id)
				_draw_dashed_connection(connection[0], connection[1], UITheme.LINE_IDLE)


func _segment_color(states: PackedStringArray) -> Color:
	if states[0] == "purchased" and states[1] == "purchased":
		return Color(UITheme.LINE_INSTALLED, 0.42)
	if (states[0] == "purchased" and states[1] == "available") or (states[1] == "purchased" and states[0] == "available"):
		return Color(UITheme.LINE_FRONTIER, 0.60)
	return Color(UITheme.LINE_IDLE, 0.13)


func _segment_width(states: PackedStringArray) -> float:
	var frontier := (states[0] == "purchased" and states[1] == "available") or (states[1] == "purchased" and states[0] == "available")
	return 1.5 if frontier else 1.0


func _segment_states(constellation_id: String, segment: Array) -> PackedStringArray:
	var states := PackedStringArray(["", ""])
	for index in range(2):
		var star_key := "%s/%s" % [constellation_id, String(segment[index])]
		if star_node_ids.has(star_key):
			states[index] = _cached_node_state(String(star_node_ids[star_key]))
	return states


func _draw_chart_horizon() -> void:
	# The wheel turns about this point; without a mark the rotation reads as
	# arbitrary rather than as a sky pivoting on due north.
	var tick_height := UITheme.px(13.0)
	tree_canvas.draw_line(
		Vector2(CHART_ORIGIN.x, CHART_ORIGIN.y - tick_height),
		Vector2(CHART_ORIGIN.x, CHART_ORIGIN.y),
		UITheme.HORIZON_TICK,
		1.0,
		true
	)
	var span := TREE_SIZE.x * 0.375
	var steps := 24
	for index in range(steps):
		var a := float(index) / float(steps)
		var b := float(index + 1) / float(steps)
		for side in [-1.0, 1.0]:
			tree_canvas.draw_line(
				Vector2(CHART_ORIGIN.x + side * span * a, CHART_ORIGIN.y),
				Vector2(CHART_ORIGIN.x + side * span * b, CHART_ORIGIN.y),
				Color(UITheme.HORIZON, 1.0 - (a + b) * 0.5),
				1.0,
				true
			)
	var horizon_y := CHART_ORIGIN.y
	# The ground runs well past the canvas. Now that the sky reaches beyond
	# TREE_SIZE, a figure rotated below the horizon has to stay buried at any
	# zoom, and a ridge that stopped at the canvas edge would let it show.
	var overhang := TREE_SIZE.x
	var ridge := PackedVector2Array([
		Vector2(-overhang, horizon_y + 9.0), Vector2(TREE_SIZE.x * 0.18, horizon_y - 4.0),
		Vector2(TREE_SIZE.x * 0.36, horizon_y + 2.0), Vector2(TREE_SIZE.x * 0.54, horizon_y - 8.0),
		Vector2(TREE_SIZE.x * 0.76, horizon_y + 1.0), Vector2(TREE_SIZE.x, horizon_y - 5.0),
		Vector2(TREE_SIZE.x + overhang, horizon_y + 4.0),
		Vector2(TREE_SIZE.x + overhang, TREE_SIZE.y + overhang), Vector2(-overhang, TREE_SIZE.y + overhang)
	])
	tree_canvas.draw_colored_polygon(ridge, UITheme.GROUND)
	var dome_center := CHART_ORIGIN + Vector2(0, -2.0)
	tree_canvas.draw_circle(dome_center, 24.0, UITheme.GROUND)
	tree_canvas.draw_rect(Rect2(dome_center.x - 26.0, dome_center.y, 52.0, 28.0), UITheme.GROUND)
	tree_canvas.draw_line(dome_center + Vector2(0, -22), dome_center + Vector2(15, -38), UITheme.HORIZON, 3.0, true)
	tree_canvas.draw_circle(dome_center + Vector2(16, -39), 2.2, UITheme.HORIZON_TICK)


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
	# Text with a rule under it, matching the chart's own close action and the
	# HUD overlays. The bordered box was the last cyan-era shape on this screen.
	var font_size := UITheme.size_px(15.0)
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", UITheme.mono())
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_constant_override("spacing_glyph", UITheme.tracking(font_size, 0.16))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, UITheme.INK_MID)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_width_bottom = 1
	style.border_color = UITheme.ACCENT_DEEP
	style.content_margin_left = UITheme.px(9.0)
	style.content_margin_right = UITheme.px(9.0)
	style.content_margin_top = UITheme.px(7.0)
	style.content_margin_bottom = UITheme.px(6.0)
	var hover := style.duplicate()
	hover.border_color = UITheme.ACCENT_TEXT
	for state in ["normal", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, style)
	button.add_theme_stylebox_override("hover", hover)

func _spec_label(text: String, font: Font, spec_size: float, color: Color, em: float = 0.0) -> Label:
	var label := Label.new()
	label.text = text
	var font_size := UITheme.size_px(spec_size)
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if not is_zero_approx(em):
		label.add_theme_constant_override("spacing_glyph", UITheme.tracking(font_size, em))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


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
