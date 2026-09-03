extends CanvasLayer

signal tree_opened
signal tree_closed
signal galactic_pullback_finished

const Balance = preload("res://scripts/game_balance.gd")
const ChartData = preload("res://scripts/research_chart_data.gd")
const UITheme = preload("res://scripts/ui_theme.gd")

const TREE_SIZE := Vector2(1460, 780)
const MIN_ZOOM := 0.55
const MAX_ZOOM := 1.28
const GALACTIC_ZOOM := 0.18
# Installing every node earns a wider frame. The galaxy map still opens at
# GALACTIC_ZOOM; this only lowers the floor the player can pull back to, so the
# extra room is chosen rather than imposed.
const GALACTIC_ZOOM_COMPLETE := 0.12
const GALACTIC_DETAIL_ZOOM_START := 0.26
const GALACTIC_DETAIL_ZOOM_END := 0.55
const GALACTIC_CHART_SCALE := 0.0
const GALACTIC_NODE_SCREEN_SCALE := 0.72
const GALACTIC_DISK_TILT := 0.52
const GALACTIC_MAP_CENTER_SPEC := Vector2(910.0, 590.0)
const GALACTIC_ROUTE_INNER_RADIUS_SPEC := 124.0
const GALACTIC_ROUTE_OUTER_RADIUS_SPEC := 548.0
const GALACTIC_CORE_RADIUS_SPEC := 104.0
const GALACTIC_CORE_HIT_RADIUS_SPEC := 112.0
const GALACTIC_ROUTE_SAMPLES_PER_SEGMENT := 14
const GALACTIC_MODE_NORMAL := 0
const GALACTIC_MODE_PULLBACK := 1
const GALACTIC_MODE_FINAL := 2
const PULLBACK_DURATION := 3.60
const PULLBACK_LINES_END := 0.90
const PULLBACK_ZOOM_START := 0.15
const PULLBACK_ZOOM_END := 2.25
const PULLBACK_LEGACY_FADE_START := 0.40
const PULLBACK_LEGACY_FADE_END := 1.55
const PULLBACK_ROUTE_START := 0.95
const PULLBACK_ROUTE_END := 3.15
const PULLBACK_GALACTIC_BACKGROUND_START := 1.45
const PULLBACK_GALACTIC_BACKGROUND_END := 2.85
const GALACTIC_NODE_SETTLE_SCALE := 0.965
const GALACTIC_NODE_REVEAL_WINDOW := 0.04
const HOLD_PURCHASE_SECONDS := 0.75
const CHART_ORIGIN := Vector2(TREE_SIZE.x * 0.5, TREE_SIZE.y * 0.91)
const CONSTELLATION_ZOOM := UITheme.SCALE * 1.06
const ROTATION_STEP := deg_to_rad(6.0)
const DEFAULT_ROTATION := 0.0
const STAR_HIT_SIZE := Vector2(44.0, 44.0)
const TOOLTIP_SIZE := Vector2(318.0, 0.0)
# custom_minimum_size only sets a floor. A long branch or star line still
# widens the panel past it, and the clamp below then measures an already
# oversized box and cannot pull it back on screen.
const TOOLTIP_MAX_WIDTH := 318.0
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
const GALACTIC_BACKGROUND_STAR_COUNT := 74
const GALACTIC_BACKGROUND_STAR_SEED := 20260828
const GALACTIC_BACKGROUND_BOUNDS_SPEC := Rect2(40.0, 60.0, 1840.0, 980.0)
const GALACTIC_BACKGROUND_EXCLUSION_SPEC := Vector2(590.0, 318.0)
const GALACTIC_LEDGER_ORDER := [
	"cassiopeia", "big_dipper", "orion", "andromeda", "perseus", "lyra",
	"gemini", "taurus", "leo", "ursa_minor", "canis_major", "draco",
]
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
	var galaxy_rotation := 0.0


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


	func _draw_galaxy_marker(center: Vector2, _radius: float) -> void:
		# Local Group research uses the mock-up's edge-on galactic discs. Keep the
		# transform contained here so labels and later nodes never inherit rotation.
		var spec_radius := clampf(12.6 - magnitude * 0.52, 4.6, 13.0)
		var major := UITheme.px(spec_radius) / GALACTIC_NODE_SCREEN_SCALE
		var minor := major * 0.33
		draw_set_transform(center, galaxy_rotation)
		match visual_state:
			"purchased":
				draw_ellipse(Vector2.ZERO, major * 2.5, major * 1.5, Color(UITheme.STAR_INSTALLED_GLOW, 0.20 if hovered else 0.075))
				draw_ellipse(Vector2.ZERO, major, minor, UITheme.STAR_INSTALLED if hovered else Color(UITheme.STAR_INSTALLED_GLOW, 0.86))
			"available":
				var pulse := 0.16 + (0.06 * sin(pulse_phase) if affordable else 0.0)
				draw_ellipse(Vector2.ZERO, major * 2.5, major * 1.5, Color(UITheme.STAR_READY_RING, pulse))
				draw_ellipse(Vector2.ZERO, major, minor, UITheme.STAR_READY_FILL if affordable else Color(UITheme.STAR_SHORT_BORDER, 0.74))
			"locked", "teaser":
				draw_ellipse(Vector2.ZERO, major, minor, Color(UITheme.STAR_LOCKED, 0.30))
			_:
				draw_ellipse(Vector2.ZERO, major, minor, Color(UITheme.STAR_BACKGROUND, 0.26))
		if hold_ratio > 0.0:
			draw_ellipse_arc(Vector2.ZERO, major * 1.34, minor * 2.4, -PI * 0.5, -PI * 0.5 + TAU * hold_ratio, 42, UITheme.STAR_READY_RING, UITheme.px(2.0), true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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
				draw_circle(center, radius * purchased_glow_scale(), Color(UITheme.STAR_INSTALLED_GLOW, 0.22 if hovered else 0.13))
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
var data_context_label: Label
var systems_readout: Label
var galactic_progress_installed: Label
var galactic_progress_separator: Label
var galactic_progress_total: Label
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
var constellation_installation_rule: ColorRect
var galactic_installation_rule: ColorRect
var installation_rule: ColorRect
var installation_tween: Tween
var installation_node_id: String = ""
var galactic_inspector_node_id: String = ""
var north_label: Label
var subtitle_label: Label
var close_button: Button
var controls_label: Label
var constellation_horizon_hint: Label
var constellation_bottom_action: Label

var node_buttons: Dictionary = {}
var node_hold_bars: Dictionary = {}
var star_positions: Dictionary = {}
var node_positions: Dictionary = {}
var node_star_records: Dictionary = {}
var base_star_positions: Dictionary = {}
var star_node_ids: Dictionary = {}
var local_group_node_positions: Dictionary = {}
var local_group_node_order: Dictionary = {}
var local_group_node_route_ratios: Dictionary = {}
var local_group_route_length: float = 0.0
var local_group_route_polyline: PackedVector2Array = PackedVector2Array()
var galactic_core_max_length: float = 1.0

var hovered_node_id: String = ""
var selected_node_id: String = ""
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
var galactic_background_stars: PackedVector2Array = PackedVector2Array()
var galactic_background_star_radii: PackedFloat32Array = PackedFloat32Array()
var galactic_background_star_alphas: PackedFloat32Array = PackedFloat32Array()
var galactic_background_rng_state: int = GALACTIC_BACKGROUND_STAR_SEED
var galactic_outer_halo: GradientTexture2D
var galactic_inner_halo: GradientTexture2D
var constellation_halo: GradientTexture2D
var galactic_unlocked: bool = false
var galactic_pullback_seen: bool = false
var catalogue_final_watch_pending: bool = false
var catalogue_ending_ready: bool = false
var galactic_mode: int = GALACTIC_MODE_NORMAL
var galactic_chart_detail: float = 1.0
var pullback_elapsed: float = 0.0
var pullback_start_zoom: float = 0.78
var pullback_start_pan := Vector2.ZERO
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

var completion_detail_label: Label
var constellation_ledger: Control
var constellation_ledger_names: Array[Label] = []
var constellation_ledger_leaders: Array[ColorRect] = []
var constellation_ledger_notes: Array[Label] = []
var constellation_ledger_counts: Array[Label] = []
var tooltip_state: Label
var tooltip_cost: Label
var tooltip_action: Label
var galactic_ledger: Control
var galactic_span_value: Label
var galactic_ledger_names: Array[Label] = []
var galactic_ledger_leaders: Array[ColorRect] = []
var galactic_ledger_counts: Array[Label] = []
var galactic_panel: Control
var galactic_panel_group: Label
var galactic_panel_name: Label
var galactic_panel_code: Label
var galactic_panel_order: Label
var galactic_panel_state: Label
var galactic_panel_cost: Label
var galactic_panel_effect: Label
var galactic_core_hit: Button
var galactic_inner_hint: Label
var galactic_return_hint: Label
var galactic_watermark: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	node_star_records = ChartData.node_star_map()
	_build_background_stars()
	_build_galactic_background_stars()
	_build_galactic_halo_textures()
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


func configure_galactic_state(unlocked: bool, pullback_seen: bool) -> void:
	_cancel_installation_rule()
	galactic_unlocked = unlocked
	galactic_pullback_seen = unlocked and pullback_seen
	pullback_elapsed = 0.0
	if galactic_pullback_seen:
		galactic_mode = GALACTIC_MODE_FINAL
		galactic_chart_detail = 0.0
	else:
		galactic_mode = GALACTIC_MODE_NORMAL
		galactic_chart_detail = 1.0
	if tree_canvas != null:
		_layout_chart()
		_update_galactic_presentation()


func configure_catalogue_ending_state(final_watch_pending: bool, ending_ready: bool) -> void:
	catalogue_final_watch_pending = final_watch_pending
	catalogue_ending_ready = ending_ready
	# Ending state changes the chart's exit semantics as well as its explanatory
	# copy. Refresh the whole phase context so the header and lower action cannot
	# keep advertising another ordinary observation.
	_refresh_phase_context()


func begin_galactic_pullback() -> void:
	galactic_unlocked = true
	if galactic_pullback_seen or not is_open():
		return
	_start_galactic_pullback()


func open_tree() -> void:
	if overlay.visible or progression == null:
		return
	_cancel_installation_rule()
	_cancel_node_hold()
	pending_rotation_delta = 0.0
	overlay.visible = true
	_hide_node_tooltip()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	paused_by_tree = not get_tree().paused
	get_tree().paused = true
	_refresh()
	if galactic_unlocked:
		if galactic_pullback_seen:
			galactic_mode = GALACTIC_MODE_FINAL
			call_deferred("_frame_galaxy")
		else:
			call_deferred("_start_galactic_pullback")
	else:
		call_deferred("_frame_frontier")
	tree_opened.emit()


func close_tree() -> void:
	if not overlay.visible:
		return
	_cancel_installation_rule()
	_flush_pending_rotation()
	if galactic_mode == GALACTIC_MODE_PULLBACK and not galactic_pullback_seen:
		galactic_mode = GALACTIC_MODE_NORMAL
		galactic_chart_detail = 1.0
		pullback_elapsed = 0.0
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


func pulse_installation_rule() -> void:
	# The chart's opaque canvas covers the HUD banner. Animate its existing
	# inspector divider instead, on the same canvas as the purchased research.
	_cancel_installation_rule()
	if not is_open():
		return
	if _galactic_panel_active() and galactic_panel.is_visible_in_tree():
		installation_rule = galactic_installation_rule
		installation_node_id = galactic_inspector_node_id
	elif _constellation_panel_active() and tooltip_panel.is_visible_in_tree():
		installation_rule = constellation_installation_rule
		installation_node_id = selected_node_id
	else:
		# The Galactic Reference Frame has its own pull-back with no inspector.
		return
	installation_rule.pivot_offset = Vector2(installation_rule.size.x * 0.5, 0.0)
	installation_rule.scale = Vector2(0.2, 1.0)
	installation_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	installation_tween.tween_property(installation_rule, "scale:x", 1.0, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _cancel_installation_rule() -> void:
	if installation_tween != null and installation_tween.is_valid():
		installation_tween.kill()
	if is_instance_valid(installation_rule):
		installation_rule.scale = Vector2.ONE
	installation_rule = null
	installation_node_id = ""


func set_intermission_context(next_round: int, next_duration: int) -> void:
	intermission_active = true
	intermission_next_round = maxi(1, next_round)
	intermission_next_duration = maxi(1, next_duration)
	_refresh_phase_context()


func clear_intermission_context() -> void:
	intermission_active = false
	_refresh_phase_context()


func _refresh_phase_context() -> void:
	_cancel_installation_rule()
	if subtitle_label == null or close_button == null:
		return
	if catalogue_ending_ready:
		subtitle_label.text = tr("TREE_SUBTITLE")
		close_button.text = tr("TREE_CATALOGUE_SEAL_RECORD")
	elif intermission_active:
		subtitle_label.text = tr("TREE_NEXT_OBSERVATION") % [intermission_next_round, intermission_next_duration]
		close_button.text = tr("TREE_START_OBSERVATION")
	else:
		subtitle_label.text = tr("TREE_SUBTITLE")
		close_button.text = tr("TREE_CLOSE")
	if data_context_label != null:
		data_context_label.text = tr("TREE_DATA_CONTEXT") % [intermission_next_round, intermission_next_duration]
		# A ready ending owns this close, while an already-running final watch has
		# no pending next-observation context to advertise.
		data_context_label.visible = not catalogue_ending_ready and not (catalogue_final_watch_pending and not intermission_active)
	if constellation_bottom_action != null:
		constellation_bottom_action.text = _phase_bottom_action_text()
	if galactic_return_hint != null:
		galactic_return_hint.text = _phase_galactic_return_text()
	_refresh_galactic_completion_detail()
	_layout_chart_header()


func _phase_bottom_action_text() -> String:
	if catalogue_ending_ready:
		return tr("TREE_BOTTOM_CATALOGUE_SEAL_RECORD")
	return tr("TREE_BOTTOM_START_OBSERVATION") if intermission_active else tr("TREE_BOTTOM_CLOSE")


func _phase_galactic_return_text() -> String:
	if catalogue_ending_ready:
		return tr("TREE_BOTTOM_CATALOGUE_SEAL_RECORD")
	return tr("TREE_GALACTIC_RETURN")


func _input(event: InputEvent) -> void:
	if not is_open():
		return
	if galactic_mode == GALACTIC_MODE_PULLBACK and _is_deliberate_pullback_skip(event):
		_finish_galactic_pullback()
		if event is InputEventKey and event.keycode in [KEY_ESCAPE, KEY_U]:
			close_tree()
		# Let an ordinary mouse press continue through the GUI so a press on the
		# close action both skips and closes. Wheel presses are consumed here so the
		# same event cannot immediately zoom away from the final galaxy frame.
		if not (event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]):
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_U:
			close_tree()
			get_viewport().set_input_as_handled()
			return


func _process(delta: float) -> void:
	_flush_pending_rotation()
	if galactic_mode == GALACTIC_MODE_PULLBACK:
		_advance_galactic_pullback(delta)
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
			elif _galactic_chart_is_readable():
				_queue_chart_rotation(-ROTATION_STEP)
			get_viewport().set_input_as_handled()
			return
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if event.ctrl_pressed:
				_zoom_at(event.position, 1.0 / 1.10)
			elif _galactic_chart_is_readable():
				_queue_chart_rotation(ROTATION_STEP)
			get_viewport().set_input_as_handled()
			return


func _zoom_at(screen_position: Vector2, factor: float) -> void:
	if galactic_mode == GALACTIC_MODE_PULLBACK:
		return
	if galactic_unlocked and galactic_pullback_seen:
		_zoom_galactic_chart(factor)
		return
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
	if galactic_unlocked and galactic_pullback_seen:
		_frame_galaxy()
	else:
		_frame_frontier()


func _is_deliberate_pullback_skip(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo
	if event is InputEventMouseButton:
		return event.pressed
	if event is InputEventJoypadButton:
		return event.pressed
	return false


func _start_galactic_pullback() -> void:
	if not galactic_unlocked or galactic_pullback_seen or not is_open():
		return
	_cancel_node_hold()
	_hide_node_tooltip()
	pending_rotation_delta = 0.0
	galactic_mode = GALACTIC_MODE_PULLBACK
	pullback_elapsed = 0.0
	pullback_start_zoom = zoom
	pullback_start_pan = pan_position
	galactic_chart_detail = 1.0
	_update_galactic_presentation()


func _advance_galactic_pullback(delta: float) -> void:
	pullback_elapsed = minf(PULLBACK_DURATION, pullback_elapsed + maxf(0.0, delta))
	var pullback_ratio := _timed_ratio(pullback_elapsed, PULLBACK_ZOOM_START, PULLBACK_ZOOM_END)
	var eased_pullback := _ease_in_out(pullback_ratio)
	# Scale is perceived as a ratio, so a linear ramp through zoom reads as an
	# accelerating rush that stops dead at the end. Stepping through zoom
	# geometrically keeps the apparent rate of withdrawal constant.
	zoom = pullback_start_zoom * pow(GALACTIC_ZOOM / pullback_start_zoom, eased_pullback)
	galactic_chart_detail = 1.0 - eased_pullback
	# The anchor has to be recomputed from the live zoom every frame. Lerping a
	# stored start pan toward a galaxy pan puts the focal point on a different
	# curve from the scale, and the sky slides sideways while it shrinks.
	var anchored_pan := _galactic_pan_for_zoom(zoom, galactic_chart_detail)
	var canonical_start_pan := _galactic_pan_for_zoom(pullback_start_zoom, 1.0)
	pan_position = anchored_pan + (pullback_start_pan - canonical_start_pan) * (1.0 - eased_pullback)
	_layout_chart()
	_apply_transform()
	_update_galactic_presentation()
	if pullback_elapsed >= PULLBACK_DURATION:
		_finish_galactic_pullback()


func _finish_galactic_pullback() -> void:
	if galactic_pullback_seen:
		return
	galactic_unlocked = true
	galactic_pullback_seen = true
	galactic_mode = GALACTIC_MODE_FINAL
	pullback_elapsed = PULLBACK_DURATION
	galactic_chart_detail = 0.0
	_frame_galaxy()
	_update_galactic_presentation()
	galactic_pullback_finished.emit()


func _timed_ratio(value: float, start: float, finish: float) -> float:
	return clampf((value - start) / maxf(0.001, finish - start), 0.0, 1.0)


func _ease_in_out(value: float) -> float:
	return value * value * (3.0 - 2.0 * value)


func _ease_out_back(value: float) -> float:
	var offset := value - 1.0
	return 1.0 + 2.70158 * offset * offset * offset + 1.70158 * offset * offset


func _galactic_pan_for_zoom(target_zoom: float, chart_detail: float = 0.0) -> Vector2:
	if content_clip == null:
		return pan_position
	# The design frame fixes the Local Group disc at (910, 590) on a 1920x1080
	# canvas, leaving exact columns for the completion ledger and inspector.
	var galaxy_origin_screen := GALACTIC_MAP_CENTER_SPEC * UITheme.SCALE
	var chart_origin_screen := Vector2(content_clip.size.x * 0.5, content_clip.size.y - 18.0)
	var origin_screen := galaxy_origin_screen.lerp(chart_origin_screen, clampf(chart_detail, 0.0, 1.0))
	return origin_screen - CHART_ORIGIN * target_zoom


func _frame_galaxy() -> void:
	if content_clip == null or content_clip.size.x <= 1.0 or content_clip.size.y <= 1.0:
		return
	zoom = GALACTIC_ZOOM
	galactic_chart_detail = 0.0
	pan_position = _galactic_pan_for_zoom(zoom, galactic_chart_detail)
	galactic_mode = GALACTIC_MODE_FINAL
	_layout_chart()
	_apply_transform()
	_update_galactic_presentation()


func _galactic_zoom_floor() -> float:
	if progression != null and progression.upgrade_level >= Balance.research_node_count():
		return GALACTIC_ZOOM_COMPLETE
	return GALACTIC_ZOOM


func _zoom_galactic_chart(factor: float) -> void:
	var old_zoom := zoom
	zoom = clampf(zoom * factor, _galactic_zoom_floor(), MAX_ZOOM)
	if is_equal_approx(old_zoom, zoom):
		return
	galactic_chart_detail = _ease_in_out(_timed_ratio(
		zoom,
		GALACTIC_DETAIL_ZOOM_START,
		GALACTIC_DETAIL_ZOOM_END
	))
	pan_position = _galactic_pan_for_zoom(zoom, galactic_chart_detail)
	_layout_chart()
	_apply_transform()
	_update_galactic_presentation()


func _galactic_chart_is_readable() -> bool:
	return not galactic_unlocked or not galactic_pullback_seen or galactic_chart_detail >= 0.94


func _is_local_group_node(node_id: String) -> bool:
	return local_group_node_positions.has(node_id)


func _galactic_route_progress() -> float:
	if galactic_mode == GALACTIC_MODE_PULLBACK:
		# A linear clock moves the route head at a stable speed. Node-local easing
		# supplies the softness without repeatedly slowing the whole trace.
		return _timed_ratio(pullback_elapsed, PULLBACK_ROUTE_START, PULLBACK_ROUTE_END)
	if galactic_unlocked and galactic_pullback_seen:
		return 1.0
	return 0.0


func _local_group_alpha() -> float:
	if not galactic_unlocked:
		return 0.0
	if galactic_mode == GALACTIC_MODE_PULLBACK:
		return _galactic_route_progress()
	if not galactic_pullback_seen:
		return 0.0
	return 1.0 - smoothstep(0.05, 0.34, galactic_chart_detail)


func _galactic_background_alpha() -> float:
	if not galactic_unlocked:
		return 0.0
	if galactic_mode == GALACTIC_MODE_PULLBACK:
		return _ease_in_out(_timed_ratio(
			pullback_elapsed,
			PULLBACK_GALACTIC_BACKGROUND_START,
			PULLBACK_GALACTIC_BACKGROUND_END
		))
	if not galactic_pullback_seen:
		return 0.0
	return 1.0 - smoothstep(0.05, 0.34, galactic_chart_detail)


func _local_group_node_reveal(node_id: String) -> float:
	var group_alpha := _local_group_alpha()
	if galactic_mode != GALACTIC_MODE_PULLBACK or group_alpha <= 0.0:
		return group_alpha
	var arrival_ratio := float(local_group_node_route_ratios.get(node_id, 1.0))
	# The node reaches full brightness exactly as the traced route reaches it.
	# Its short lead-in reads as illumination, not a second expanding structure.
	return _ease_in_out(clampf(
		(group_alpha - arrival_ratio + GALACTIC_NODE_REVEAL_WINDOW) / GALACTIC_NODE_REVEAL_WINDOW,
		0.0,
		1.0
	))


func _legacy_chart_alpha() -> float:
	if not galactic_unlocked:
		return 1.0
	if galactic_mode == GALACTIC_MODE_PULLBACK:
		return 1.0 - _ease_in_out(_timed_ratio(
			pullback_elapsed,
			PULLBACK_LEGACY_FADE_START,
			PULLBACK_LEGACY_FADE_END
		))
	return smoothstep(0.05, 0.34, galactic_chart_detail)


func _node_presentation_alpha(node_id: String) -> float:
	if _is_local_group_node(node_id):
		return _local_group_node_reveal(node_id)
	if node_id == "galactic_reference_frame" and galactic_unlocked:
		return 1.0
	return _legacy_chart_alpha()


func _node_interaction_ready(node_id: String) -> bool:
	if _is_local_group_node(node_id):
		return galactic_unlocked and galactic_pullback_seen and galactic_chart_detail <= 0.06
	if node_id == "galactic_reference_frame" and galactic_unlocked:
		# The 112-spec-pixel core target owns galactic-scale input. The original
		# star button returns only when the completed chart becomes readable again.
		return galactic_pullback_seen and _galactic_chart_is_readable()
	return galactic_mode != GALACTIC_MODE_PULLBACK and _galactic_chart_is_readable()


func _galactic_structure_alpha() -> float:
	if galactic_mode == GALACTIC_MODE_PULLBACK:
		return 1.0 - _ease_in_out(_timed_ratio(pullback_elapsed, 0.0, PULLBACK_LINES_END))
	if galactic_mode == GALACTIC_MODE_FINAL:
		return galactic_chart_detail
	return 1.0


func _galactic_core_alpha() -> float:
	if not galactic_unlocked:
		return 0.0
	if galactic_mode == GALACTIC_MODE_PULLBACK:
		return _ease_in_out(_timed_ratio(
			pullback_elapsed,
			PULLBACK_GALACTIC_BACKGROUND_START,
			PULLBACK_GALACTIC_BACKGROUND_END
		))
	if not galactic_pullback_seen:
		return 0.0
	return 1.0 - smoothstep(0.05, 0.34, galactic_chart_detail)


func _update_galactic_presentation() -> void:
	if north_label != null:
		north_label.modulate.a = _galactic_structure_alpha()
	if controls_label != null:
		controls_label.text = tr("TREE_CONTROLS_GALACTIC") if galactic_unlocked and galactic_pullback_seen and not _galactic_chart_is_readable() else tr("TREE_CONTROLS_FULL")
	if tree_canvas != null:
		tree_canvas.queue_redraw()
	_refresh_galactic_overlays()


func _frame_frontier() -> void:
	if galactic_unlocked and galactic_pullback_seen:
		_frame_galaxy()
		return
	if content_clip == null or content_clip.size.x <= 1.0 or content_clip.size.y <= 1.0:
		return
	# The approved 1920×1080 chart fixes the celestial pivot at (880, 1008) and
	# presents the figure geometry at 1.06×. UITheme.SCALE maps that hand-off to
	# the 1152×648 project viewport without changing any simulation coordinates.
	zoom = CONSTELLATION_ZOOM
	pan_position = Vector2(UITheme.px(880.0), UITheme.px(1008.0)) - CHART_ORIGIN * zoom
	_apply_transform()


func _on_content_resized() -> void:
	_cancel_installation_rule()
	_layout_chart_header()
	_layout_galactic_overlays()
	if is_open() and content_clip.size.x > 1.0 and content_clip.size.y > 1.0:
		call_deferred("_frame_frontier")


func _apply_transform() -> void:
	tree_canvas.position = pan_position
	tree_canvas.scale = Vector2.ONE * zoom
	if north_label != null:
		north_label.position.y = minf(_north_label_y(), controls_label.position.y - north_label.get_combined_minimum_size().y - UITheme.px(6.0))
	_layout_galactic_overlays()


func _rotate_chart(amount: float) -> void:
	rotation_offset = wrapf(rotation_offset + amount, -PI, PI)
	if settings_controller != null:
		settings_controller.set_research_chart_rotation(rotation_offset, false)
	_layout_chart()


func _queue_chart_rotation(amount: float) -> void:
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
	title_label.position = Vector2(UITheme.px(56.0), UITheme.px(44.0))
	var caption_size := title_label.get_combined_minimum_size()
	var value_size := data_readout.get_combined_minimum_size()
	data_readout.size = value_size
	data_readout.position = Vector2(UITheme.px(56.0), title_label.position.y + caption_size.y + UITheme.px(6.0))
	if data_context_label != null:
		data_context_label.position = Vector2(UITheme.px(56.0), data_readout.position.y + value_size.y + UITheme.px(7.0))
		data_context_label.size.x = UITheme.px(360.0)

	var line_width := UITheme.px(440.0)
	var header_width := UITheme.px(640.0)
	var centre := frame.x * 0.5
	for label in [installed_caption, systems_readout, tree_status, completion_detail_label]:
		label.size.x = header_width
		label.position.x = centre - header_width * 0.5
	installed_caption.position.y = UITheme.px(40.0)
	var installed_height := installed_caption.get_combined_minimum_size().y
	systems_readout.position.y = installed_caption.position.y + installed_height + UITheme.px(10.0)
	var count_height := systems_readout.get_combined_minimum_size().y
	var count_y := systems_readout.position.y
	var installed_size := galactic_progress_installed.get_combined_minimum_size()
	var separator_size := galactic_progress_separator.get_combined_minimum_size()
	var total_size := galactic_progress_total.get_combined_minimum_size()
	var counter_gap := UITheme.px(18.0)
	var counter_width := installed_size.x + separator_size.x + total_size.x + counter_gap * 2.0
	var counter_x := centre - counter_width * 0.5
	galactic_progress_installed.position = Vector2(counter_x, count_y)
	galactic_progress_installed.size = installed_size
	galactic_progress_separator.position = Vector2(
		counter_x + installed_size.x + counter_gap,
		count_y + UITheme.mono_tabular().get_ascent(UITheme.size_px(64.0)) - UITheme.mono().get_ascent(UITheme.size_px(26.0))
	)
	galactic_progress_separator.size = separator_size
	galactic_progress_total.position = Vector2(
		galactic_progress_separator.position.x + separator_size.x + counter_gap,
		count_y
	)
	galactic_progress_total.size = total_size
	var line_y := systems_readout.position.y + count_height + UITheme.px(10.0)
	progress_track.position = Vector2(centre - line_width * 0.5, line_y)
	progress_track.size = Vector2(line_width, UITheme.px(2.0))
	progress_fill.position = progress_track.position
	var ratio := 0.0
	if progression != null:
		ratio = float(progression.upgrade_level) / maxf(1.0, float(Balance.research_node_count()))
	progress_fill.size = Vector2(line_width * clampf(ratio, 0.0, 1.0), UITheme.px(2.0))
	tree_status.position.y = progress_track.position.y + progress_track.size.y + UITheme.px(10.0)
	completion_detail_label.position.y = tree_status.position.y + tree_status.get_combined_minimum_size().y + UITheme.px(10.0)
	var watermark_width := UITheme.px(320.0)
	var watermark_height := galactic_watermark.get_combined_minimum_size().y
	galactic_watermark.position = Vector2(
		UITheme.px(1500.0) - watermark_width,
		UITheme.px(900.0) - watermark_height
	)
	galactic_watermark.size = Vector2(watermark_width, watermark_height)

	var action_width := UITheme.px(360.0)
	close_button.size = Vector2(action_width, UITheme.px(30.0))
	close_button.position = Vector2(frame.x - UITheme.px(40.0) - action_width, UITheme.px(44.0))
	var underline_width := close_button.get_theme_font("font").get_string_size(
		close_button.text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		UITheme.size_px(19.0)
	).x + UITheme.px(12.0)
	close_underline.size = Vector2(underline_width, 1.0)
	close_underline.position = Vector2(
		frame.x - UITheme.px(40.0) - underline_width,
		close_button.position.y + close_button.size.y + UITheme.px(4.0)
	)
	subtitle_label.size.x = action_width
	subtitle_label.position = Vector2(
		frame.x - UITheme.px(40.0) - action_width,
		close_underline.position.y + UITheme.px(11.0)
	)

	var wide := frame.x
	for label in [controls_label, north_label]:
		label.size.x = wide
		label.position.x = 0.0
	var bottom_y := frame.y - UITheme.px(38.0)
	controls_label.position.y = bottom_y - controls_label.get_combined_minimum_size().y
	north_label.position.y = minf(_north_label_y(), controls_label.position.y - north_label.get_combined_minimum_size().y - UITheme.px(6.0))
	if constellation_horizon_hint != null:
		constellation_horizon_hint.size.x = UITheme.px(430.0)
		constellation_horizon_hint.position = Vector2(UITheme.px(56.0), bottom_y - constellation_horizon_hint.get_combined_minimum_size().y)
	if constellation_bottom_action != null:
		constellation_bottom_action.size.x = UITheme.px(430.0)
		constellation_bottom_action.position = Vector2(frame.x - UITheme.px(40.0) - constellation_bottom_action.size.x, bottom_y - constellation_bottom_action.get_combined_minimum_size().y)
	galactic_inner_hint.size.x = UITheme.px(430.0)
	galactic_inner_hint.position = Vector2(UITheme.px(56.0), bottom_y - galactic_inner_hint.get_combined_minimum_size().y)
	galactic_return_hint.size.x = UITheme.px(430.0)
	galactic_return_hint.position = Vector2(frame.x - UITheme.px(40.0) - galactic_return_hint.size.x, bottom_y - galactic_return_hint.get_combined_minimum_size().y)
	_layout_constellation_overlays()


func _north_label_y() -> float:
	# The label rides with the horizon so the pivot stays legible at any zoom.
	var origin_y := tree_canvas.global_position.y + CHART_ORIGIN.y * zoom - overlay.global_position.y
	return origin_y + UITheme.px(16.0)


func _constellation_panel_active() -> bool:
	return galactic_mode != GALACTIC_MODE_PULLBACK and _galactic_chart_is_readable() and not _galactic_panel_active()


func _layout_constellation_overlays() -> void:
	if overlay == null or constellation_ledger == null or tooltip_panel == null:
		return
	var frame := overlay.size
	constellation_ledger.position = Vector2(UITheme.px(56.0), UITheme.px(206.0))
	constellation_ledger.size = Vector2(UITheme.px(288.0), maxf(0.0, frame.y - constellation_ledger.position.y - UITheme.px(70.0)))
	var ledger_title: Label = constellation_ledger.get_node("LedgerTitle")
	ledger_title.position = Vector2.ZERO
	ledger_title.size.x = constellation_ledger.size.x
	var row_y := ledger_title.get_combined_minimum_size().y + UITheme.px(10.0)
	for index in range(constellation_ledger_names.size()):
		var name_label := constellation_ledger_names[index]
		var leader := constellation_ledger_leaders[index]
		var note_label := constellation_ledger_notes[index]
		var count_label := constellation_ledger_counts[index]
		var count_width := maxf(UITheme.px(42.0), count_label.get_combined_minimum_size().x)
		var note_width := minf(UITheme.px(78.0), note_label.get_combined_minimum_size().x)
		var name_width := minf(name_label.get_combined_minimum_size().x, constellation_ledger.size.x - count_width - note_width - UITheme.px(34.0))
		name_label.position = Vector2(0.0, row_y)
		name_label.size.x = name_width
		count_label.position = Vector2(constellation_ledger.size.x - count_width, row_y)
		count_label.size.x = count_width
		note_label.position = Vector2(count_label.position.x - note_width - UITheme.px(10.0), row_y)
		note_label.size.x = note_width
		var baseline_y := row_y + maxf(name_label.get_combined_minimum_size().y, count_label.get_combined_minimum_size().y) * 0.66
		leader.position = Vector2(name_width + UITheme.px(10.0), baseline_y)
		leader.size = Vector2(maxf(1.0, note_label.position.x - leader.position.x - UITheme.px(10.0)), 1.0)
		row_y += maxf(name_label.get_combined_minimum_size().y, count_label.get_combined_minimum_size().y) + UITheme.px(10.0)
	tooltip_panel.position = Vector2(frame.x - UITheme.px(40.0) - UITheme.px(292.0), UITheme.px(196.0))
	tooltip_panel.size = Vector2(UITheme.px(292.0), maxf(1.0, frame.y - UITheme.px(196.0) - UITheme.px(70.0)))


func _galactic_panel_active() -> bool:
	return galactic_unlocked and _galactic_core_alpha() > 0.01 and galactic_chart_detail < 0.34


func _layout_galactic_overlays() -> void:
	if overlay == null or galactic_panel == null or galactic_ledger == null:
		return
	var frame := overlay.size
	galactic_ledger.position = Vector2(UITheme.px(56.0), UITheme.px(186.0))
	galactic_ledger.size = Vector2(UITheme.px(266.0), maxf(0.0, frame.y - galactic_ledger.position.y - UITheme.px(70.0)))
	_layout_galactic_ledger_content()
	galactic_panel.size = Vector2(UITheme.px(308.0), maxf(0.0, frame.y - UITheme.px(186.0) - UITheme.px(70.0)))
	galactic_panel.position = Vector2(frame.x - UITheme.px(56.0) - galactic_panel.size.x, UITheme.px(186.0))
	_layout_galactic_panel_content()
	var core_screen := tree_canvas.global_position + CHART_ORIGIN * zoom - overlay.global_position
	var hit_diameter := UITheme.px(GALACTIC_CORE_HIT_RADIUS_SPEC * 2.0)
	galactic_core_hit.size = Vector2.ONE * hit_diameter
	galactic_core_hit.position = core_screen - galactic_core_hit.size * 0.5


func _layout_galactic_ledger_content() -> void:
	if galactic_ledger == null:
		return
	var width := galactic_ledger.size.x
	var ledger_title: Label = galactic_ledger.get_node("LedgerTitle")
	var span_label: Label = galactic_ledger.get_node("SpanLabel")
	var divider: ColorRect = galactic_ledger.get_node("Divider")
	var branch_title: Label = galactic_ledger.get_node("BranchTitle")
	ledger_title.position = Vector2.ZERO
	ledger_title.size.x = width
	var row_height := maxf(span_label.get_combined_minimum_size().y, galactic_span_value.get_combined_minimum_size().y)
	var top_rows_y := ledger_title.get_combined_minimum_size().y + UITheme.px(9.0)
	var span_y := top_rows_y + (row_height + UITheme.px(5.0)) * 2.0
	span_label.position = Vector2(0.0, span_y)
	span_label.size.x = width * 0.68
	galactic_span_value.position = Vector2(width * 0.55, span_y)
	galactic_span_value.size.x = width * 0.45
	var divider_y := span_y + row_height + UITheme.px(16.0)
	divider.position = Vector2(0.0, divider_y)
	divider.size = Vector2(width, 1.0)
	branch_title.position = Vector2(0.0, divider_y + UITheme.px(16.0))
	branch_title.size.x = width
	var row_y := branch_title.position.y + branch_title.get_combined_minimum_size().y + UITheme.px(7.0)
	for index in range(galactic_ledger_names.size()):
		var name_label := galactic_ledger_names[index]
		var leader := galactic_ledger_leaders[index]
		var count_label := galactic_ledger_counts[index]
		var count_width := maxf(UITheme.px(28.0), count_label.get_combined_minimum_size().x)
		var name_width := minf(name_label.get_combined_minimum_size().x, width - count_width - UITheme.px(34.0))
		name_label.position = Vector2(0.0, row_y)
		name_label.size.x = name_width
		count_label.position = Vector2(width - count_width, row_y)
		count_label.size.x = count_width
		var baseline_y := row_y + maxf(name_label.get_combined_minimum_size().y, count_label.get_combined_minimum_size().y) * 0.66
		leader.position = Vector2(name_width + UITheme.px(10.0), baseline_y)
		leader.size = Vector2(maxf(1.0, width - count_width - name_width - UITheme.px(20.0)), 1.0)
		row_y += maxf(name_label.get_combined_minimum_size().y, count_label.get_combined_minimum_size().y) + UITheme.px(7.0)


func _layout_galactic_panel_content() -> void:
	if galactic_panel == null:
		return
	var width := galactic_panel.size.x
	galactic_panel_group.position = Vector2.ZERO
	galactic_panel_group.size.x = width
	var cursor_y := galactic_panel_group.get_combined_minimum_size().y + UITheme.px(11.0)
	galactic_panel_name.position = Vector2(0.0, cursor_y)
	galactic_panel_name.size.x = width
	cursor_y += maxf(galactic_panel_name.get_combined_minimum_size().y, UITheme.px(32.0)) + UITheme.px(11.0)
	galactic_panel_code.position = Vector2(0.0, cursor_y)
	galactic_panel_code.size.x = galactic_panel_code.get_combined_minimum_size().x
	galactic_panel_order.position = Vector2(galactic_panel_code.size.x + UITheme.px(12.0), cursor_y)
	galactic_panel_order.size.x = maxf(0.0, width - galactic_panel_order.position.x)
	cursor_y += maxf(galactic_panel_code.get_combined_minimum_size().y, galactic_panel_order.get_combined_minimum_size().y) + UITheme.px(11.0)
	var divider: ColorRect = galactic_panel.get_node("Divider")
	divider.position = Vector2(0.0, cursor_y)
	divider.size = Vector2(width, 1.0)
	cursor_y += UITheme.px(11.0)
	var field_value_x := UITheme.px(72.0)
	var value_width := maxf(1.0, width - field_value_x)
	var field_pairs := [
		[galactic_panel.get_node("FieldStatusLabel"), galactic_panel_state],
		[galactic_panel.get_node("FieldCostLabel"), galactic_panel_cost],
		[galactic_panel.get_node("FieldEffectLabel"), galactic_panel_effect],
	]
	for pair in field_pairs:
		var label: Label = pair[0]
		var value: Label = pair[1]
		label.position = Vector2(0.0, cursor_y + UITheme.px(2.0))
		label.size.x = field_value_x - UITheme.px(14.0)
		value.position = Vector2(field_value_x, cursor_y)
		value.size.x = value_width
		var row_height := maxf(label.get_combined_minimum_size().y + UITheme.px(2.0), value.get_combined_minimum_size().y)
		cursor_y += row_height + UITheme.px(7.0)


func _refresh_galactic_overlays() -> void:
	if galactic_panel == null:
		return
	var active := _galactic_panel_active()
	var constellation_active := _constellation_panel_active()
	var alpha := _galactic_core_alpha()
	galactic_panel.visible = active
	galactic_ledger.visible = active
	galactic_panel.modulate.a = alpha
	galactic_ledger.modulate.a = alpha
	galactic_watermark.visible = active
	galactic_watermark.modulate.a = alpha
	constellation_ledger.visible = constellation_active
	tooltip_panel.visible = constellation_active and not selected_node_id.is_empty()
	if installation_rule != null and not installation_rule.is_visible_in_tree():
		_cancel_installation_rule()
	systems_readout.visible = false
	galactic_progress_installed.visible = true
	galactic_progress_separator.visible = true
	galactic_progress_total.visible = true
	constellation_horizon_hint.visible = constellation_active
	constellation_bottom_action.visible = constellation_active
	galactic_inner_hint.visible = active
	galactic_return_hint.visible = active
	completion_detail_label.visible = constellation_active or (active and progression != null and progression.upgrade_level >= Balance.research_node_count())
	galactic_core_hit.visible = active and galactic_pullback_seen and galactic_chart_detail <= 0.06
	galactic_core_hit.mouse_filter = Control.MOUSE_FILTER_STOP if galactic_core_hit.visible else Control.MOUSE_FILTER_IGNORE
	if node_hold_bars.has("galactic_reference_frame"):
		var reference_visual: StarNodeVisual = node_hold_bars["galactic_reference_frame"]
		reference_visual.visible = not active
	if constellation_active:
		_refresh_constellation_overlays()
	if progression != null:
		galactic_span_value.text = "×%.4f" % float(progression.get_observation_span())
		for index in range(GALACTIC_LEDGER_ORDER.size()):
			var constellation: Dictionary = ChartData.CONSTELLATIONS[GALACTIC_LEDGER_ORDER[index]]
			var installed := 0
			for star_variant in constellation.stars:
				var star: Dictionary = star_variant
				var node_id := String(star.get("node_id", ""))
				if not node_id.is_empty() and progression.get_node_state(node_id) == "purchased":
					installed += 1
			galactic_ledger_counts[index].text = str(installed)
		var local_group_installed := 0
		for galaxy_variant in ChartData.LOCAL_GROUP_GALAXIES:
			if progression.get_node_state(String(galaxy_variant.node_id)) == "purchased":
				local_group_installed += 1
		galactic_ledger_counts[-1].text = str(local_group_installed)
	var selected_id := hovered_node_id if hovered_node_id == "galactic_reference_frame" or _is_local_group_node(hovered_node_id) else "galactic_reference_frame"
	_refresh_galactic_panel(selected_id)
	_layout_galactic_overlays()


func _refresh_constellation_overlays() -> void:
	if progression == null or constellation_ledger == null:
		return
	if selected_node_id.is_empty() or not node_buttons.has(selected_node_id) or _is_local_group_node(selected_node_id):
		selected_node_id = _default_constellation_selection()
	var below_horizon_count := 0
	for index in range(GALACTIC_LEDGER_ORDER.size()):
		var constellation_id: String = GALACTIC_LEDGER_ORDER[index]
		var constellation: Dictionary = ChartData.CONSTELLATIONS[constellation_id]
		var installed := 0
		var total := 0
		var opened := false
		for star_variant in constellation.stars:
			var star: Dictionary = star_variant
			var node_id := String(star.get("node_id", ""))
			if node_id.is_empty():
				continue
			total += 1
			var state: String = progression.get_node_state(node_id)
			if state == "purchased":
				installed += 1
			if state in ["purchased", "available", "locked"]:
				opened = true
		var below_horizon := _constellation_below_horizon(constellation_id)
		if below_horizon:
			below_horizon_count += 1
		var kind := "done" if installed == total else ("active" if opened else "locked")
		var tone := UITheme.TOOLTIP_BODY if kind == "done" else (UITheme.INK_MAX if kind == "active" else UITheme.INK_LOW)
		constellation_ledger_names[index].add_theme_color_override("font_color", tone)
		constellation_ledger_counts[index].add_theme_color_override("font_color", tone)
		constellation_ledger_counts[index].text = "%d / %d" % [installed, total]
		var note := ""
		if below_horizon:
			note = tr("TREE_CONSTELLATION_BELOW_HORIZON")
		elif kind == "active":
			note = tr("TREE_CONSTELLATION_IN_PROGRESS")
		elif kind == "locked":
			note = tr("TREE_CONSTELLATION_LOCKED")
		constellation_ledger_notes[index].text = note
	var local_group_index := GALACTIC_LEDGER_ORDER.size()
	var local_group_installed := 0
	for galaxy_variant in ChartData.LOCAL_GROUP_GALAXIES:
		if progression.get_node_state(String(galaxy_variant.node_id)) == "purchased":
			local_group_installed += 1
	var local_group_total := Balance.local_group_functional_node_count()
	var local_group_kind := "done" if local_group_installed == local_group_total else ("active" if galactic_unlocked else "locked")
	var local_group_tone := UITheme.TOOLTIP_BODY if local_group_kind == "done" else (UITheme.INK_MAX if local_group_kind == "active" else UITheme.INK_LOW)
	constellation_ledger_names[local_group_index].add_theme_color_override("font_color", local_group_tone)
	constellation_ledger_counts[local_group_index].add_theme_color_override("font_color", local_group_tone)
	constellation_ledger_counts[local_group_index].text = "%d / %d" % [local_group_installed, local_group_total]
	constellation_ledger_notes[local_group_index].text = tr("TREE_CONSTELLATION_IN_PROGRESS") if local_group_kind == "active" else ("" if local_group_kind == "done" else tr("TREE_CONSTELLATION_LOCKED"))
	constellation_horizon_hint.text = tr("TREE_CONSTELLATION_HORIZON_HINT") % below_horizon_count
	constellation_bottom_action.text = _phase_bottom_action_text()
	_refresh_constellation_detail_line()
	if not selected_node_id.is_empty():
		_refresh_constellation_inspector(selected_node_id)
	_layout_constellation_overlays()


func _constellation_below_horizon(constellation_id: String) -> bool:
	var placement: Dictionary = ChartData.PLACEMENTS[constellation_id]
	return sin(float(placement.anchor_angle) + rotation_offset) > 0.0


func _default_constellation_selection() -> String:
	if progression == null:
		return ""
	for require_affordable in [true, false]:
		for definition in Balance.UPGRADE_NODES:
			var node_id := String(definition.id)
			if _is_local_group_node(node_id) or progression.get_node_state(node_id) != "available":
				continue
			if require_affordable and not progression.can_purchase(node_id):
				continue
			if _is_node_above_horizon(node_id):
				return node_id
	for definition_index in range(Balance.UPGRADE_NODES.size() - 1, -1, -1):
		var node_id := String(Balance.UPGRADE_NODES[definition_index].id)
		if not _is_local_group_node(node_id) and progression.get_node_state(node_id) == "purchased" and _is_node_above_horizon(node_id):
			return node_id
	return ""


func _refresh_constellation_detail_line() -> void:
	if completion_detail_label == null or progression == null:
		return
	var group_label := tr("TREE_CONSTELLATION_CURRENT_SKY")
	if not selected_node_id.is_empty() and node_star_records.has(selected_node_id):
		var star_record: Dictionary = node_star_records[selected_node_id]
		var constellation_id := String(star_record.constellation_id)
		if constellation_id != "local_group":
			group_label = tr(String(ChartData.CONSTELLATIONS[constellation_id].label_key)).split("  /  ")[0]
	var non_draco_installed := 0
	for definition in Balance.UPGRADE_NODES:
		var node_id := String(definition.id)
		if _is_local_group_node(node_id) or String(definition.branch) == "draco":
			continue
		if progression.get_node_state(node_id) == "purchased":
			non_draco_installed += 1
	var remaining := maxi(0, 86 - non_draco_installed)
	if remaining > 0:
		completion_detail_label.text = tr("TREE_CONSTELLATION_DRACO_REMAINING") % [group_label, remaining]
	else:
		completion_detail_label.text = tr("TREE_CONSTELLATION_DRACO_OPEN") % group_label


func _refresh_galactic_panel(node_id: String) -> void:
	if galactic_panel == null or progression == null or not node_buttons.has(node_id):
		return
	if installation_rule == galactic_installation_rule and installation_node_id != node_id:
		_cancel_installation_rule()
	galactic_inspector_node_id = node_id
	var definition := Balance.upgrade_definition(node_id)
	var star_record: Dictionary = node_star_records[node_id]
	var star: Dictionary = star_record.star
	if node_id == "galactic_reference_frame":
		galactic_panel_group.text = tr("TREE_GALACTIC_REFERENCE_GROUP")
		galactic_panel_name.text = tr("TREE_GALACTIC_REFERENCE_NAME")
		galactic_panel_code.text = tr("TREE_GALACTIC_REFERENCE_CODE")
		galactic_panel_order.text = tr("TREE_GALACTIC_REFERENCE_ORDER")
	else:
		galactic_panel_group.text = tr(ChartData.LOCAL_GROUP_LABEL_KEY)
		galactic_panel_name.text = tr(String(star.name_key))
		galactic_panel_code.text = String(star.bayer)
		galactic_panel_order.text = tr("TREE_GALACTIC_ORDER") % [_local_group_functional_order(node_id), Balance.local_group_functional_node_count()]
	var state: String = progression.get_node_state(node_id)
	galactic_panel_state.text = tr("STATE_%s" % state.to_upper())
	galactic_panel_cost.text = tr("TREE_GALACTIC_COST") % _grouped(int(definition.cost))
	galactic_panel_effect.text = _upgrade_description(definition)
	_layout_galactic_panel_content()


func _refresh_constellation_static_text() -> void:
	if constellation_ledger == null or tooltip_panel == null:
		return
	var ledger_title: Label = constellation_ledger.get_node("LedgerTitle")
	ledger_title.text = tr("TREE_CONSTELLATION_LEDGER")
	for index in range(GALACTIC_LEDGER_ORDER.size()):
		var constellation: Dictionary = ChartData.CONSTELLATIONS[GALACTIC_LEDGER_ORDER[index]]
		constellation_ledger_names[index].text = tr(String(constellation.label_key)).split("  /  ")[0]
	constellation_ledger_names[-1].text = tr(ChartData.LOCAL_GROUP_LABEL_KEY).split(" / ")[0]
	for field_name in ["STATUS", "COST", "EFFECT"]:
		var field_label: Label = tooltip_panel.find_child("Field%sLabel" % field_name.capitalize(), true, false)
		field_label.text = tr("TREE_CONSTELLATION_FIELD_%s" % field_name)
	var legend_title: Label = tooltip_panel.find_child("LegendTitle", true, false)
	legend_title.text = tr("TREE_CONSTELLATION_STAR_STATES")
	var legend_keys := [
		"TREE_CONSTELLATION_LEGEND_INSTALLED",
		"TREE_CONSTELLATION_LEGEND_READY",
		"TREE_CONSTELLATION_LEGEND_SHORT",
		"TREE_CONSTELLATION_LEGEND_LOCKED",
	]
	for index in range(legend_keys.size()):
		var legend_text: Label = tooltip_panel.find_child("LegendText%d" % index, true, false)
		legend_text.text = tr(legend_keys[index])


func _refresh_galactic_static_text() -> void:
	if galactic_panel == null or galactic_ledger == null:
		return
	var ledger_title: Label = galactic_ledger.get_node("LedgerTitle")
	ledger_title.text = tr("TREE_GALACTIC_LEDGER")
	var span_label: Label = galactic_ledger.get_node("SpanLabel")
	span_label.text = tr("TREE_GALACTIC_SPAN")
	var branch_title: Label = galactic_ledger.get_node("BranchTitle")
	branch_title.text = tr("TREE_GALACTIC_BRANCH_INSTALLS")
	for index in range(GALACTIC_LEDGER_ORDER.size()):
		var constellation: Dictionary = ChartData.CONSTELLATIONS[GALACTIC_LEDGER_ORDER[index]]
		galactic_ledger_names[index].text = tr(String(constellation.label_key)).split("  /  ")[0]
	galactic_ledger_names[-1].text = tr(ChartData.LOCAL_GROUP_LABEL_KEY).split(" / ")[0]
	for field_name in ["STATUS", "COST", "EFFECT"]:
		var field_label: Label = galactic_panel.get_node("Field%sLabel" % field_name.capitalize())
		field_label.text = tr("TREE_GALACTIC_FIELD_%s" % field_name)
	_refresh_galactic_completion_detail()
	galactic_inner_hint.text = tr("TREE_GALACTIC_INNER_HINT")
	galactic_return_hint.text = _phase_galactic_return_text()
	galactic_watermark.text = tr("TREE_GALACTIC_WATERMARK")
	_refresh_galactic_overlays()


func _refresh_galactic_completion_detail() -> void:
	if completion_detail_label == null:
		return
	if catalogue_ending_ready:
		completion_detail_label.text = tr("TREE_CATALOGUE_ENDING_READY_DETAIL")
	elif catalogue_final_watch_pending and intermission_active:
		completion_detail_label.text = tr("TREE_CATALOGUE_FINAL_WATCH_DETAIL")
	else:
		completion_detail_label.text = tr("TREE_GALACTIC_COMPLETE_DETAIL")


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


func _build_galactic_background_stars() -> void:
	galactic_background_stars.clear()
	galactic_background_star_radii.clear()
	galactic_background_star_alphas.clear()
	galactic_background_rng_state = GALACTIC_BACKGROUND_STAR_SEED
	var attempts := 0
	while galactic_background_stars.size() < GALACTIC_BACKGROUND_STAR_COUNT and attempts < 6000:
		attempts += 1
		var spec_position := Vector2(
			GALACTIC_BACKGROUND_BOUNDS_SPEC.position.x + _next_galactic_background_random() * GALACTIC_BACKGROUND_BOUNDS_SPEC.size.x,
			GALACTIC_BACKGROUND_BOUNDS_SPEC.position.y + _next_galactic_background_random() * GALACTIC_BACKGROUND_BOUNDS_SPEC.size.y
		)
		var exclusion_distance := Vector2(
			(spec_position.x - GALACTIC_MAP_CENTER_SPEC.x) / GALACTIC_BACKGROUND_EXCLUSION_SPEC.x,
			(spec_position.y - GALACTIC_MAP_CENTER_SPEC.y) / GALACTIC_BACKGROUND_EXCLUSION_SPEC.y
		).length()
		if exclusion_distance < 1.0:
			continue
		galactic_background_stars.append(spec_position * UITheme.SCALE)
		galactic_background_star_radii.append(UITheme.px(0.7 + _next_galactic_background_random() * 1.1))
		galactic_background_star_alphas.append(0.16 + _next_galactic_background_random() * 0.30)


func _next_galactic_background_random() -> float:
	# Exact Mulberry32 stream used by the design source. Keeping it here makes the
	# 74-point field a deterministic part of the hand-off instead of a lookalike.
	galactic_background_rng_state = (galactic_background_rng_state + 0x6D2B79F5) & 0xFFFFFFFF
	var value := ((galactic_background_rng_state ^ (galactic_background_rng_state >> 15)) * (1 | galactic_background_rng_state)) & 0xFFFFFFFF
	value = (value + (((value ^ (value >> 7)) * (61 | value)) & 0xFFFFFFFF)) ^ value
	value &= 0xFFFFFFFF
	return float((value ^ (value >> 14)) & 0xFFFFFFFF) / 4294967296.0


func _build_galactic_halo_textures() -> void:
	constellation_halo = _radial_halo_texture(PackedFloat32Array([0.0, 0.40, 0.70, 1.0]), PackedColorArray([
		Color(1.0, 0.64, 0.48, 0.05),
		Color(1.0, 0.64, 0.48, 0.014),
		Color(1.0, 0.64, 0.48, 0.0),
		Color(1.0, 0.64, 0.48, 0.0),
	]))
	galactic_outer_halo = _radial_halo_texture(PackedFloat32Array([0.0, 0.38, 0.68, 1.0]), PackedColorArray([
		Color(1.0, 0.643, 0.478, 0.035),
		Color(1.0, 0.643, 0.478, 0.012),
		Color(0.035, 0.024, 0.016, 0.0),
		Color(0.035, 0.024, 0.016, 0.0),
	]))
	galactic_inner_halo = _radial_halo_texture(PackedFloat32Array([0.0, 0.44, 0.74, 1.0]), PackedColorArray([
		Color(1.0, 0.835, 0.682, 0.10),
		Color(1.0, 0.835, 0.682, 0.035),
		Color(0.035, 0.024, 0.016, 0.0),
		Color(0.035, 0.024, 0.016, 0.0),
	]))


func _radial_halo_texture(offsets: PackedFloat32Array, colors: PackedColorArray) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = offsets
	gradient.colors = colors
	var texture := GradientTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.gradient = gradient
	return texture


func _cache_chart_geometry() -> void:
	base_star_positions.clear()
	star_node_ids.clear()
	local_group_node_positions.clear()
	local_group_node_order.clear()
	local_group_node_route_ratios.clear()
	local_group_route_length = 0.0
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
	galactic_core_max_length = 1.0
	for base_position_variant in base_star_positions.values():
		galactic_core_max_length = maxf(
			galactic_core_max_length,
			(Vector2(base_position_variant) - CHART_ORIGIN).length()
		)
	var galactic_offsets := ChartData.galactic_map_offsets(
		GALACTIC_ROUTE_INNER_RADIUS_SPEC,
		GALACTIC_ROUTE_OUTER_RADIUS_SPEC,
		GALACTIC_DISK_TILT
	)
	for index in range(ChartData.LOCAL_GROUP_GALAXIES.size()):
		var galaxy_variant = ChartData.LOCAL_GROUP_GALAXIES[index]
		var galaxy: Dictionary = galaxy_variant
		var node_id := String(galaxy.node_id)
		var mapped_screen_offset := Vector2(galactic_offsets[node_id]) * UITheme.SCALE
		local_group_node_positions[node_id] = CHART_ORIGIN + mapped_screen_offset / GALACTIC_ZOOM
		local_group_node_order[node_id] = index
	_cache_local_group_route()


func _cache_local_group_route() -> void:
	var control_points := PackedVector2Array([CHART_ORIGIN])
	for galaxy_variant in ChartData.LOCAL_GROUP_GALAXIES:
		var galaxy: Dictionary = galaxy_variant
		if ChartData.is_local_group_decoration(String(galaxy.node_id)):
			continue
		control_points.append(Vector2(local_group_node_positions[String(galaxy.node_id)]))
	local_group_route_polyline = _sample_local_group_route(control_points)
	local_group_route_length = _polyline_length(local_group_route_polyline)
	if local_group_route_length <= 0.0:
		return
	var accumulated_length := 0.0
	var functional_galaxies: Array[Dictionary] = []
	for galaxy_variant in ChartData.LOCAL_GROUP_GALAXIES:
		var galaxy: Dictionary = galaxy_variant
		if not ChartData.is_local_group_decoration(String(galaxy.node_id)):
			functional_galaxies.append(galaxy)
	var next_node_index := 0
	for point_index in range(1, local_group_route_polyline.size()):
		accumulated_length += local_group_route_polyline[point_index - 1].distance_to(local_group_route_polyline[point_index])
		if point_index % GALACTIC_ROUTE_SAMPLES_PER_SEGMENT != 0:
			continue
		if next_node_index >= functional_galaxies.size():
			break
		var galaxy: Dictionary = functional_galaxies[next_node_index]
		local_group_node_route_ratios[String(galaxy.node_id)] = accumulated_length / local_group_route_length
		next_node_index += 1


func _sample_local_group_route(control_points: PackedVector2Array) -> PackedVector2Array:
	var sampled := PackedVector2Array()
	if control_points.is_empty():
		return sampled
	sampled.append(control_points[0])
	for segment_index in range(control_points.size() - 1):
		var p0 := control_points[maxi(0, segment_index - 1)]
		var p1 := control_points[segment_index]
		var p2 := control_points[segment_index + 1]
		var p3 := control_points[mini(control_points.size() - 1, segment_index + 2)]
		var c1 := p1 + (p2 - p0) / 6.0
		var c2 := p2 - (p3 - p1) / 6.0
		for sample_index in range(1, GALACTIC_ROUTE_SAMPLES_PER_SEGMENT + 1):
			var ratio := float(sample_index) / float(GALACTIC_ROUTE_SAMPLES_PER_SEGMENT)
			var inverse := 1.0 - ratio
			sampled.append(
				p1 * inverse * inverse * inverse
				+ c1 * 3.0 * inverse * inverse * ratio
				+ c2 * 3.0 * inverse * ratio * ratio
				+ p2 * ratio * ratio * ratio
			)
	return sampled


func _polyline_length(points: PackedVector2Array) -> float:
	var length := 0.0
	for index in range(1, points.size()):
		length += points[index - 1].distance_to(points[index])
	return length


func _layout_chart() -> void:
	if tree_canvas == null:
		return
	chart_layout_passes += 1
	star_positions.clear()
	node_positions.clear()
	for star_key_variant in base_star_positions:
		var star_key := String(star_key_variant)
		var base_position := Vector2(base_star_positions[star_key])
		var rotated_position := CHART_ORIGIN + (base_position - CHART_ORIGIN).rotated(rotation_offset)
		var chart_position := _present_chart_position(rotated_position)
		star_positions[star_key] = chart_position
		if star_node_ids.has(star_key):
			node_positions[String(star_node_ids[star_key])] = chart_position
	for node_id_variant in local_group_node_positions:
		var node_id := String(node_id_variant)
		node_positions[node_id] = _present_local_group_position(node_id)
	for node_id in node_positions:
		if not node_buttons.has(node_id):
			continue
		var button: Button = node_buttons[node_id]
		var center := Vector2(node_positions[node_id])
		button.position = center - button.size * 0.5
		var presentation_alpha := _node_presentation_alpha(String(node_id))
		button.scale = Vector2.ONE * _node_render_scale(String(node_id), presentation_alpha)
		button.modulate.a = presentation_alpha
		button.mouse_filter = Control.MOUSE_FILTER_STOP if presentation_alpha >= 0.92 and _node_interaction_ready(String(node_id)) else Control.MOUSE_FILTER_IGNORE
		button.visible = (
			bool(button.get_meta("revealed", true))
			and presentation_alpha > 0.01
			and (not _galactic_horizon_active() or center.y <= CHART_ORIGIN.y)
		)
	_layout_galactic_overlays()
	if progression != null and _constellation_panel_active():
		_refresh_constellation_overlays()
	tree_canvas.queue_redraw()


func _present_chart_position(chart_position: Vector2) -> Vector2:
	if not galactic_unlocked:
		return chart_position
	var chart_scale := lerpf(GALACTIC_CHART_SCALE, 1.0, galactic_chart_detail)
	return CHART_ORIGIN + (chart_position - CHART_ORIGIN) * chart_scale


func _present_local_group_position(node_id: String) -> Vector2:
	var final_position := Vector2(local_group_node_positions[node_id])
	if galactic_mode != GALACTIC_MODE_PULLBACK:
		return final_position
	var reveal_ratio := _local_group_node_reveal(node_id)
	var settle_ratio := lerpf(GALACTIC_NODE_SETTLE_SCALE, 1.0, _ease_out_back(reveal_ratio))
	# Hold traced nodes at their final screen-space radius while the old chart's
	# camera is still pulling back. Otherwise the new map appears oversized and
	# then visibly contracts as zoom reaches GALACTIC_ZOOM.
	var screen_lock_scale := GALACTIC_ZOOM / maxf(zoom, 0.001)
	return CHART_ORIGIN + (final_position - CHART_ORIGIN) * screen_lock_scale * settle_ratio


func _node_render_scale(node_id: String, presentation_alpha: float) -> float:
	var galaxy_presence := 0.0
	if _is_local_group_node(node_id):
		galaxy_presence = presentation_alpha
	elif node_id == "galactic_reference_frame" and galactic_unlocked:
		galaxy_presence = 1.0 - smoothstep(0.05, 0.34, galactic_chart_detail)
	if galaxy_presence <= 0.0:
		return 1.0
	var screen_fixed_scale := GALACTIC_NODE_SCREEN_SCALE / maxf(zoom, 0.001)
	return lerpf(1.0, screen_fixed_scale, galaxy_presence)


func _galactic_horizon_active() -> bool:
	return not galactic_unlocked or galactic_chart_detail >= 0.82


func _is_node_above_horizon(node_id: String) -> bool:
	if _is_local_group_node(node_id):
		return true
	# Before the first layout there are no positions yet; the layout pass that
	# follows settles it.
	if not node_positions.has(node_id):
		return true
	return not _galactic_horizon_active() or Vector2(node_positions[node_id]).y <= CHART_ORIGIN.y


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
	if not _is_local_group_node(node_id) and node_id != "galactic_reference_frame":
		selected_node_id = node_id
	if tree_canvas != null:
		tree_canvas.queue_redraw()
	_show_node_tooltip(node_id)


func _on_node_unhovered(node_id: String) -> void:
	if node_hold_bars.has(node_id):
		var star_visual: StarNodeVisual = node_hold_bars[node_id]
		star_visual.set_hovered(false)
	if held_node_id == node_id:
		_cancel_node_hold()
	if hovered_node_id == node_id:
		hovered_node_id = ""
		if _galactic_panel_active():
			_refresh_galactic_panel("galactic_reference_frame")
		elif not selected_node_id.is_empty():
			_refresh_constellation_inspector(selected_node_id)
		if tree_canvas != null:
			tree_canvas.queue_redraw()


func _hide_node_tooltip(clear_hover: bool = true) -> void:
	var hover_changed := clear_hover and not hovered_node_id.is_empty()
	if clear_hover:
		hovered_node_id = ""
	if tooltip_panel != null:
		tooltip_panel.visible = _constellation_panel_active() and not selected_node_id.is_empty()
	if galactic_panel != null and _galactic_panel_active():
		_refresh_galactic_panel("galactic_reference_frame")
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
	systems_readout.text = tr("TREE_PROGRESS_COUNT") % [progression.upgrade_level, Balance.research_node_count()]
	galactic_progress_installed.text = "%03d" % progression.upgrade_level
	galactic_progress_total.text = "%03d" % Balance.research_node_count()
	_layout_chart_header()
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
		var presentation_alpha := _node_presentation_alpha(node_id)
		button.modulate.a = presentation_alpha
		button.mouse_filter = Control.MOUSE_FILTER_STOP if presentation_alpha >= 0.92 and _node_interaction_ready(node_id) else Control.MOUSE_FILTER_IGNORE
		button.visible = visible and presentation_alpha > 0.01 and _is_node_above_horizon(node_id)
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
	_refresh_galactic_overlays()
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
	if _galactic_panel_active() and (node_id == "galactic_reference_frame" or _is_local_group_node(node_id)):
		if tooltip_panel != null:
			tooltip_panel.visible = false
		_refresh_galactic_panel(node_id)
		return
	if progression == null or not node_buttons.has(node_id) or _is_local_group_node(node_id):
		return
	selected_node_id = node_id
	_refresh_constellation_detail_line()
	_refresh_constellation_inspector(node_id)


func _refresh_constellation_inspector(node_id: String) -> void:
	if progression == null or not node_buttons.has(node_id) or _is_local_group_node(node_id):
		return
	if installation_rule == constellation_installation_rule and installation_node_id != node_id:
		_cancel_installation_rule()
	var visual_state := String(node_buttons[node_id].get_meta("visual_state"))
	var content_key := "%s:%s:%d:%d:%s" % [
		node_id,
		visual_state,
		int(floor(progression.observation_data)),
		int(progression.upgrade_level),
		TranslationServer.get_locale(),
	]
	if tooltip_content_key == content_key:
		tooltip_panel.visible = _constellation_panel_active()
		return
	tooltip_content_key = content_key
	tooltip_content_refreshes += 1
	var definition := Balance.upgrade_definition(node_id)
	var star_record: Dictionary = node_star_records[node_id]
	var star: Dictionary = star_record.star
	var group_id := String(star_record.constellation_id)
	var group_label_key := ChartData.LOCAL_GROUP_LABEL_KEY
	if group_id != "local_group":
		var constellation: Dictionary = ChartData.CONSTELLATIONS[group_id]
		group_label_key = String(constellation.label_key)
	var constellation_label := tr(group_label_key).replace("  /  ", " / ")
	tooltip_star.text = "%s    %s    %s" % [tr(String(star.name_key)), String(star.bayer), tr("TREE_CONSTELLATION_MAGNITUDE") % float(star.magnitude)]
	if visual_state == "teaser":
		tooltip_branch.text = "%s  /  %s" % [constellation_label, tr("TREE_UNRESOLVED_SIGNAL")]
		tooltip_name.text = "???"
		tooltip_description.text = tr("TREE_TEASER_DESCRIPTION")
		tooltip_state.text = tr("STATE_HIDDEN")
		tooltip_cost.text = "—"
		tooltip_action.text = tr("TREE_SIGNAL_OBSCURED")
	else:
		tooltip_branch.text = constellation_label
		tooltip_name.text = _upgrade_name(definition)
		tooltip_description.text = _upgrade_description(definition)
		tooltip_state.text = tr("STATE_%s" % visual_state.to_upper())
		tooltip_cost.text = tr("TREE_CONSTELLATION_COST") % _grouped(int(definition.cost))
		match visual_state:
			"purchased":
				tooltip_action.text = tr("TREE_SYSTEM_ONLINE")
			"available":
				if progression.can_purchase(node_id):
					tooltip_action.text = tr("TREE_CONSTELLATION_INSTALL_ACTION")
				else:
					tooltip_action.text = tr("TREE_NEED_MORE") % [int(floor(progression.observation_data)), int(definition.cost)]
			_:
				var prerequisite_names: Array[String] = []
				for prerequisite_variant in definition.prerequisites:
					var prerequisite_id := String(prerequisite_variant)
					if progression.get_node_state(prerequisite_id) == "purchased":
						continue
					var prerequisite := Balance.upgrade_definition(prerequisite_id)
					prerequisite_names.append(_upgrade_name(prerequisite))
				tooltip_action.text = tr("TREE_REQUIRES") % ", ".join(prerequisite_names)
	tooltip_branch.add_theme_color_override("font_color", UITheme.TOOLTIP_LABEL)
	var state_tone := UITheme.INK_MAX if visual_state == "purchased" else (UITheme.ACCENT_PIP if visual_state == "available" and progression.can_purchase(node_id) else (UITheme.STAR_SHORT_BORDER if visual_state == "available" else UITheme.TOOLTIP_LABEL))
	tooltip_state.add_theme_color_override("font_color", state_tone)
	tooltip_action.add_theme_color_override("font_color", UITheme.TOOLTIP_ACTION if visual_state == "available" and progression.can_purchase(node_id) else UITheme.TOOLTIP_LABEL)
	tooltip_panel.visible = _constellation_panel_active()
	_layout_constellation_overlays()
	tree_canvas.queue_redraw()


func _on_language_changed(_locale: String) -> void:
	_apply_locale()


func _apply_locale() -> void:
	if overlay == null:
		return
	title_label.text = tr("HUD_DATA_CAPTION")
	installed_caption.text = tr("TREE_INSTALLED_CAPTION")
	north_label.text = tr("TREE_NORTH")
	_refresh_constellation_static_text()
	_refresh_galactic_static_text()
	_refresh_phase_context()
	_update_galactic_presentation()
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
	background.color = UITheme.GROUND
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

	data_readout = _spec_label("0", UITheme.mono_tabular(), 52.0, UITheme.INK_HIGH, -0.03)
	data_readout.position = Vector2(UITheme.px(56.0), UITheme.px(44.0))
	header.add_child(data_readout)
	title_label = _spec_label(tr("HUD_DATA_CAPTION"), UITheme.mono(), 12.0, UITheme.INK_MID, 0.28)
	header.add_child(title_label)
	data_context_label = _spec_label("", UITheme.mono(), 12.0, UITheme.TOOLTIP_LABEL, 2.0 / 12.0)
	header.add_child(data_context_label)

	installed_caption = _spec_label(tr("TREE_INSTALLED_CAPTION"), UITheme.mono(), 12.0, UITheme.INK_MID, 0.30)
	installed_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(installed_caption)
	systems_readout = _spec_label(
		tr("TREE_PROGRESS_COUNT") % [0, Balance.research_node_count()],
		UITheme.mono_tabular(),
		64.0,
		UITheme.INK_MAX
	)
	systems_readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	systems_readout.visible = false
	header.add_child(systems_readout)
	galactic_progress_installed = _spec_label("000", UITheme.mono_tabular(), 64.0, UITheme.INK_MAX)
	galactic_progress_installed.name = "GalacticProgressInstalled"
	header.add_child(galactic_progress_installed)
	galactic_progress_separator = _spec_label("/", UITheme.mono(), 26.0, UITheme.INK_LOW)
	galactic_progress_separator.name = "GalacticProgressSeparator"
	header.add_child(galactic_progress_separator)
	galactic_progress_total = _spec_label("%03d" % Balance.research_node_count(), UITheme.mono_tabular(), 64.0, UITheme.INK_MID)
	galactic_progress_total.name = "GalacticProgressTotal"
	header.add_child(galactic_progress_total)
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
	close_button.add_theme_font_size_override("font_size", UITheme.size_px(19.0))
	close_button.add_theme_constant_override("spacing_glyph", UITheme.tracking(UITheme.size_px(19.0), 0.06))
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

	tree_status = _spec_label("", UITheme.sans("light"), 14.0, UITheme.ACCENT_TEXT, 0.11)
	tree_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(tree_status)
	completion_detail_label = _spec_label(tr("TREE_GALACTIC_COMPLETE_DETAIL"), UITheme.sans("light"), 13.0, UITheme.INK_MID)
	completion_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(completion_detail_label)
	controls_label = _spec_label(tr("TREE_CONTROLS_FULL"), UITheme.mono(), 12.0, UITheme.INK_LOW, 0.18)
	controls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(controls_label)
	constellation_horizon_hint = _spec_label("", UITheme.mono(), 12.0, UITheme.TOOLTIP_LABEL, 0.10)
	header.add_child(constellation_horizon_hint)
	constellation_bottom_action = _spec_label("", UITheme.mono(), 12.0, UITheme.INK_HIGH, 0.10)
	constellation_bottom_action.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(constellation_bottom_action)
	galactic_inner_hint = _spec_label(tr("TREE_GALACTIC_INNER_HINT"), UITheme.mono(), 12.0, UITheme.TOOLTIP_LABEL, 0.10)
	header.add_child(galactic_inner_hint)
	galactic_return_hint = _spec_label(tr("TREE_GALACTIC_RETURN"), UITheme.mono(), 12.0, UITheme.INK_HIGH, 0.10)
	galactic_return_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(galactic_return_hint)
	galactic_watermark = _spec_label(tr("TREE_GALACTIC_WATERMARK"), UITheme.mono(), 12.0, UITheme.INK_LOW, 2.6 / 12.0)
	galactic_watermark.name = "GalacticWatermark"
	galactic_watermark.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	galactic_watermark.visible = false
	header.add_child(galactic_watermark)
	north_label = _spec_label(tr("TREE_NORTH"), UITheme.mono(), 11.0, UITheme.HORIZON_LABEL, 0.24)
	north_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(north_label)

	header.resized.connect(_layout_chart_header)
	_layout_chart_header()

	for definition in Balance.UPGRADE_NODES:
		_build_node_button(definition)
	_build_constellation_ledger()
	_build_node_tooltip()
	_build_galactic_overlays()
	_layout_chart()


func _build_node_button(definition: Dictionary) -> void:
	var node_id := String(definition.id)
	var button := Button.new()
	button.name = "Node_" + node_id
	button.position = Vector2.ZERO
	button.size = STAR_HIT_SIZE
	button.custom_minimum_size = STAR_HIT_SIZE
	button.pivot_offset = STAR_HIT_SIZE * 0.5
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
	if local_group_node_order.has(node_id):
		var galaxy: Dictionary = ChartData.LOCAL_GROUP_GALAXIES[int(local_group_node_order[node_id])]
		star_visual.galaxy_rotation = Vector2(galaxy.local_position).angle() + deg_to_rad(58.0)
	button.add_child(star_visual)

	node_buttons[node_id] = button
	node_hold_bars[node_id] = star_visual


func _build_constellation_ledger() -> void:
	constellation_ledger = Control.new()
	constellation_ledger.name = "ConstellationInstallLedger"
	constellation_ledger.mouse_filter = Control.MOUSE_FILTER_IGNORE
	constellation_ledger.z_index = 30
	overlay.add_child(constellation_ledger)
	var ledger_title := _spec_label(tr("TREE_CONSTELLATION_LEDGER"), UITheme.mono(), 11.0, UITheme.INK_MID, 0.31)
	ledger_title.name = "LedgerTitle"
	constellation_ledger.add_child(ledger_title)
	var ledger_ids: Array[String] = []
	for constellation_id in GALACTIC_LEDGER_ORDER:
		ledger_ids.append(String(constellation_id))
	ledger_ids.append("local_group")
	for constellation_id in ledger_ids:
		var label_text := ""
		if constellation_id == "local_group":
			label_text = tr(ChartData.LOCAL_GROUP_LABEL_KEY).split(" / ")[0]
		else:
			label_text = tr(String(ChartData.CONSTELLATIONS[constellation_id].label_key)).split("  /  ")[0]
		var name_label := _spec_label(label_text, UITheme.sans("light"), 13.0, UITheme.TOOLTIP_BODY)
		constellation_ledger.add_child(name_label)
		constellation_ledger_names.append(name_label)
		var leader := ColorRect.new()
		leader.color = Color(UITheme.ACCENT_DEEP, 0.55)
		leader.mouse_filter = Control.MOUSE_FILTER_IGNORE
		constellation_ledger.add_child(leader)
		constellation_ledger_leaders.append(leader)
		var note_label := _spec_label("", UITheme.mono(), 11.0, UITheme.INK_LOW, 1.0 / 11.0)
		note_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		constellation_ledger.add_child(note_label)
		constellation_ledger_notes.append(note_label)
		var count_label := _spec_label("0 / 0", UITheme.mono_tabular(), 12.0, UITheme.INK_MID)
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		constellation_ledger.add_child(count_label)
		constellation_ledger_counts.append(count_label)


func _build_node_tooltip() -> void:
	tooltip_panel = PanelContainer.new()
	tooltip_panel.name = "ConstellationInspector"
	tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_panel.custom_minimum_size = Vector2(UITheme.px(292.0), 0.0)
	tooltip_panel.z_index = 100
	tooltip_panel.visible = false
	tooltip_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	overlay.add_child(tooltip_panel)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", UITheme.size_px(11.0))
	tooltip_panel.add_child(column)
	tooltip_branch = _spec_label("", UITheme.mono(), 11.0, UITheme.INK_MID, 0.31)
	tooltip_branch.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(tooltip_branch)
	tooltip_name = _spec_label("", UITheme.sans(), 26.0, UITheme.TOOLTIP_NAME)
	tooltip_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(tooltip_name)
	tooltip_star = _spec_label("", UITheme.mono(), 13.0, UITheme.TOOLTIP_VALUE)
	tooltip_star.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(tooltip_star)
	# The VBox owns the slot's geometry, not the animated rule's transform.
	# Otherwise its deferred sort resets the in-flight scale after a purchase.
	var divider_slot := Control.new()
	divider_slot.name = "DividerSlot"
	divider_slot.custom_minimum_size.y = 1.0
	divider_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(divider_slot)
	constellation_installation_rule = ColorRect.new()
	constellation_installation_rule.name = "Divider"
	constellation_installation_rule.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	constellation_installation_rule.color = UITheme.ACCENT_DEEP
	constellation_installation_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	divider_slot.add_child(constellation_installation_rule)
	var fields := GridContainer.new()
	fields.columns = 2
	fields.add_theme_constant_override("h_separation", UITheme.size_px(14.0))
	fields.add_theme_constant_override("v_separation", UITheme.size_px(7.0))
	fields.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(fields)
	for field_key in ["STATUS", "COST", "EFFECT"]:
		var field_label := _spec_label(tr("TREE_CONSTELLATION_FIELD_%s" % field_key), UITheme.mono(), 11.0, UITheme.TOOLTIP_LABEL, 0.18)
		field_label.name = "Field%sLabel" % field_key.capitalize()
		field_label.custom_minimum_size.x = UITheme.px(44.0)
		fields.add_child(field_label)
		match field_key:
			"STATUS":
				tooltip_state = _spec_label("", UITheme.sans("light"), 13.0, UITheme.INK_MAX)
				fields.add_child(tooltip_state)
			"COST":
				tooltip_cost = _spec_label("", UITheme.mono_tabular(), 13.0, UITheme.TOOLTIP_BODY)
				fields.add_child(tooltip_cost)
			"EFFECT":
				tooltip_description = _spec_label("", UITheme.sans("light"), 13.0, UITheme.TOOLTIP_BODY)
				tooltip_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				tooltip_description.custom_minimum_size.x = UITheme.px(220.0)
				fields.add_child(tooltip_description)
	tooltip_action = _spec_label("", UITheme.mono(), 13.0, UITheme.TOOLTIP_ACTION, 0.6 / 13.0)
	tooltip_action.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(tooltip_action)
	var legend_spacer := Control.new()
	legend_spacer.custom_minimum_size.y = UITheme.px(7.0)
	legend_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(legend_spacer)
	var legend_title := _spec_label(tr("TREE_CONSTELLATION_STAR_STATES"), UITheme.mono(), 11.0, UITheme.INK_MID, 0.31)
	legend_title.name = "LegendTitle"
	column.add_child(legend_title)
	var legend_rows := [
		["●", UITheme.STAR_INSTALLED, "TREE_CONSTELLATION_LEGEND_INSTALLED"],
		["●", UITheme.STAR_READY_FILL, "TREE_CONSTELLATION_LEGEND_READY"],
		["●", UITheme.STAR_SHORT_BORDER, "TREE_CONSTELLATION_LEGEND_SHORT"],
		["○", UITheme.STAR_LOCKED, "TREE_CONSTELLATION_LEGEND_LOCKED"],
	]
	for legend_index in range(legend_rows.size()):
		var row_variant = legend_rows[legend_index]
		var row: Array = row_variant
		var legend_row := HBoxContainer.new()
		legend_row.add_theme_constant_override("separation", UITheme.size_px(11.0))
		legend_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(legend_row)
		var marker := _spec_label(String(row[0]), UITheme.mono(), 15.0, Color(row[1]))
		marker.custom_minimum_size.x = UITheme.px(12.0)
		legend_row.add_child(marker)
		var legend_text := _spec_label(tr(String(row[2])), UITheme.sans("light"), 12.0, UITheme.TOOLTIP_LABEL)
		legend_text.name = "LegendText%d" % legend_index
		legend_row.add_child(legend_text)
	tooltip_meta = tooltip_action


func _build_galactic_overlays() -> void:
	galactic_core_hit = Button.new()
	galactic_core_hit.name = "GalacticCoreHit"
	galactic_core_hit.flat = true
	galactic_core_hit.focus_mode = Control.FOCUS_NONE
	galactic_core_hit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	galactic_core_hit.visible = false
	galactic_core_hit.z_index = 20
	for style_name in ["normal", "hover", "pressed", "focus", "disabled"]:
		galactic_core_hit.add_theme_stylebox_override(style_name, StyleBoxEmpty.new())
	galactic_core_hit.mouse_entered.connect(_on_node_hovered.bind("galactic_reference_frame"))
	galactic_core_hit.mouse_exited.connect(_on_node_unhovered.bind("galactic_reference_frame"))
	overlay.add_child(galactic_core_hit)

	galactic_ledger = Control.new()
	galactic_ledger.name = "GalacticCompletionLedger"
	galactic_ledger.mouse_filter = Control.MOUSE_FILTER_IGNORE
	galactic_ledger.z_index = 30
	overlay.add_child(galactic_ledger)
	var ledger_title := _spec_label(tr("TREE_GALACTIC_LEDGER"), UITheme.mono(), 11.0, UITheme.INK_MID, 0.31)
	ledger_title.name = "LedgerTitle"
	galactic_ledger.add_child(ledger_title)
	var span_label := _spec_label(tr("TREE_GALACTIC_SPAN"), UITheme.mono(), 13.0, UITheme.TOOLTIP_LABEL)
	span_label.name = "SpanLabel"
	galactic_ledger.add_child(span_label)
	galactic_span_value = _spec_label("×1.0000", UITheme.mono_tabular(), 13.0, UITheme.INK_HIGH)
	galactic_span_value.name = "SpanValue"
	galactic_span_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	galactic_ledger.add_child(galactic_span_value)
	var ledger_divider := ColorRect.new()
	ledger_divider.name = "Divider"
	ledger_divider.color = Color(UITheme.ACCENT_DEEP, 0.70)
	ledger_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	galactic_ledger.add_child(ledger_divider)
	var branch_title := _spec_label(tr("TREE_GALACTIC_BRANCH_INSTALLS"), UITheme.mono(), 11.0, UITheme.INK_MID, 0.31)
	branch_title.name = "BranchTitle"
	galactic_ledger.add_child(branch_title)
	for constellation_id in GALACTIC_LEDGER_ORDER:
		var constellation: Dictionary = ChartData.CONSTELLATIONS[constellation_id]
		var name_label := _spec_label(tr(String(constellation.label_key)).split("  /  ")[0], UITheme.sans("light"), 13.0, UITheme.TOOLTIP_BODY)
		galactic_ledger.add_child(name_label)
		galactic_ledger_names.append(name_label)
		var leader := ColorRect.new()
		leader.color = Color(UITheme.ACCENT_DEEP, 0.55)
		leader.mouse_filter = Control.MOUSE_FILTER_IGNORE
		galactic_ledger.add_child(leader)
		galactic_ledger_leaders.append(leader)
		var count_label := _spec_label("0", UITheme.mono_tabular(), 12.0, UITheme.INK_MID)
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		galactic_ledger.add_child(count_label)
		galactic_ledger_counts.append(count_label)
	var local_group_name := _spec_label(tr(ChartData.LOCAL_GROUP_LABEL_KEY).split(" / ")[0], UITheme.sans("light"), 13.0, UITheme.INK_MAX)
	galactic_ledger.add_child(local_group_name)
	galactic_ledger_names.append(local_group_name)
	var local_group_leader := ColorRect.new()
	local_group_leader.color = Color(UITheme.ACCENT_DEEP, 0.55)
	local_group_leader.mouse_filter = Control.MOUSE_FILTER_IGNORE
	galactic_ledger.add_child(local_group_leader)
	galactic_ledger_leaders.append(local_group_leader)
	var local_group_count := _spec_label("0", UITheme.mono_tabular(), 12.0, UITheme.INK_MID)
	local_group_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	galactic_ledger.add_child(local_group_count)
	galactic_ledger_counts.append(local_group_count)

	galactic_panel = Control.new()
	galactic_panel.name = "GalacticInspector"
	galactic_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	galactic_panel.z_index = 30
	overlay.add_child(galactic_panel)
	galactic_panel_group = _spec_label("", UITheme.mono(), 11.0, UITheme.INK_MID, 0.31)
	galactic_panel_group.name = "Group"
	galactic_panel.add_child(galactic_panel_group)
	galactic_panel_name = _spec_label("", UITheme.sans(), 26.0, UITheme.TOOLTIP_NAME)
	galactic_panel_name.name = "Name"
	galactic_panel_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	galactic_panel.add_child(galactic_panel_name)
	galactic_panel_code = _spec_label("", UITheme.mono(), 13.0, UITheme.TOOLTIP_VALUE)
	galactic_panel_code.name = "Code"
	galactic_panel.add_child(galactic_panel_code)
	galactic_panel_order = _spec_label("", UITheme.mono(), 13.0, UITheme.TOOLTIP_LABEL)
	galactic_panel_order.name = "Order"
	galactic_panel.add_child(galactic_panel_order)
	galactic_installation_rule = ColorRect.new()
	galactic_installation_rule.name = "Divider"
	galactic_installation_rule.color = UITheme.ACCENT_DEEP
	galactic_installation_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	galactic_panel.add_child(galactic_installation_rule)
	for field_name in ["Status", "Cost", "Effect"]:
		var field_label := _spec_label(tr("TREE_GALACTIC_FIELD_%s" % field_name.to_upper()), UITheme.mono(), 11.0, UITheme.TOOLTIP_LABEL, 0.18)
		field_label.name = "Field%sLabel" % field_name
		galactic_panel.add_child(field_label)
	galactic_panel_state = _spec_label("", UITheme.sans("light"), 13.0, UITheme.INK_MAX)
	galactic_panel_state.name = "FieldStatusValue"
	galactic_panel.add_child(galactic_panel_state)
	galactic_panel_cost = _spec_label("", UITheme.mono_tabular(), 13.0, UITheme.TOOLTIP_BODY)
	galactic_panel_cost.name = "FieldCostValue"
	galactic_panel.add_child(galactic_panel_cost)
	galactic_panel_effect = _spec_label("", UITheme.sans("light"), 13.0, UITheme.TOOLTIP_BODY)
	galactic_panel_effect.name = "FieldEffectValue"
	galactic_panel_effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	galactic_panel.add_child(galactic_panel_effect)
	_layout_galactic_overlays()
	_refresh_galactic_overlays()


func _request_tooltip_refit() -> void:
	if tooltip_refit_pending:
		return
	tooltip_refit_pending = true
	_refit_node_tooltip.call_deferred()


func _refit_node_tooltip() -> void:
	tooltip_refit_pending = false
	if tooltip_panel == null or not tooltip_panel.visible or overlay == null:
		return
	_resize_tooltip()
	_position_node_tooltip(overlay.get_local_mouse_position())


func _resize_tooltip() -> void:
	_layout_constellation_overlays()


func _position_node_tooltip(_cursor_position: Vector2) -> void:
	# The redesign keeps node detail in the fixed 292-spec-pixel right column.
	_layout_constellation_overlays()


func _connection_points(source_id: String, target_id: String) -> PackedVector2Array:
	var start := CHART_ORIGIN if source_id == "galactic_reference_frame" and _is_local_group_node(target_id) else Vector2(node_positions[source_id])
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
		var render_scale := float(node_buttons[node_id].scale.x) if node_buttons.has(node_id) else 1.0
		return star_visual.visual_radius() * render_scale
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
	_draw_chart_background()
	_draw_galactic_halos()
	_draw_galactic_background()
	_draw_galactic_orbits()
	var structure_alpha := _galactic_structure_alpha()
	for constellation_id in ChartData.CONSTELLATIONS:
		var constellation: Dictionary = ChartData.CONSTELLATIONS[constellation_id]
		for segment_variant in constellation.segments:
			var segment: Array = segment_variant
			var start := Vector2(star_positions["%s/%s" % [constellation_id, String(segment[0])]])
			var finish := Vector2(star_positions["%s/%s" % [constellation_id, String(segment[1])]])
			var states := _segment_states(constellation_id, segment)
			var segment_color := _segment_color(states)
			segment_color.a *= structure_alpha
			tree_canvas.draw_line(start, finish, segment_color, _segment_width(states), true)
		for star_variant in constellation.stars:
			var star: Dictionary = star_variant
			var point := Vector2(star_positions["%s/%s" % [constellation_id, String(star.id)]])
			var star_radius := _magnitude_radius(float(star.magnitude))
			var node_id := String(star.get("node_id", ""))
			var alpha := (0.23 if node_id.is_empty() else 0.12) * structure_alpha
			if node_id.is_empty():
				match String(star.kind):
					"cluster":
						_draw_background_cluster(point, star_radius, alpha)
					"galaxy":
						_draw_background_galaxy(point, star_radius, alpha)
			tree_canvas.draw_circle(point, maxf(1.2, star_radius * 0.55), Color(UITheme.STAR_BACKGROUND, alpha))
	if progression != null and (structure_alpha > 0.01 or _local_group_alpha() > 0.01):
		_draw_local_group_decorations()
		_draw_local_group_route()
		_draw_frontier_overlay()
	_draw_galactic_core()
	_draw_local_group_labels()
	# The ground goes on last. Half the sky now sits below the horizon at any
	# one rotation, and it has to be buried by the ground rather than drawn
	# over it.
	if structure_alpha > 0.01:
		_draw_chart_horizon(structure_alpha)


func _draw_chart_background() -> void:
	var structure_alpha := _galactic_structure_alpha() if galactic_unlocked else 1.0
	if structure_alpha <= 0.01:
		return
	if constellation_halo != null:
		var halo_size := Vector2(UITheme.px(2400.0), UITheme.px(1500.0)) / maxf(zoom, 0.001)
		tree_canvas.draw_texture_rect(
			constellation_halo,
			Rect2(CHART_ORIGIN - halo_size * 0.5, halo_size),
			false,
			Color(1.0, 1.0, 1.0, structure_alpha)
		)
	for index in range(background_stars.size()):
		var background_position := CHART_ORIGIN + (background_stars[index] - CHART_ORIGIN).rotated(rotation_offset)
		if galactic_unlocked:
			background_position = _present_chart_position(background_position)
		var radius := 1.7 if index % 5 == 0 else 1.0
		var alpha := (0.28 if index % 5 == 0 else 0.16) * structure_alpha
		tree_canvas.draw_circle(background_position, radius, Color(UITheme.STAR_BACKGROUND, alpha))


func _draw_galactic_halos() -> void:
	var alpha := _galactic_core_alpha()
	if alpha <= 0.01 or galactic_outer_halo == null or galactic_inner_halo == null:
		return
	var outer_size := Vector2(UITheme.px(1700.0), UITheme.px(900.0)) / maxf(zoom, 0.001)
	var inner_size := Vector2(UITheme.px(560.0), UITheme.px(290.0)) / maxf(zoom, 0.001)
	tree_canvas.draw_texture_rect(galactic_outer_halo, Rect2(CHART_ORIGIN - outer_size * 0.5, outer_size), false, Color(1.0, 1.0, 1.0, alpha))
	tree_canvas.draw_texture_rect(galactic_inner_halo, Rect2(CHART_ORIGIN - inner_size * 0.5, inner_size), false, Color(1.0, 1.0, 1.0, alpha))


func _draw_galactic_orbits() -> void:
	var alpha := _galactic_core_alpha()
	if alpha <= 0.01:
		return
	_draw_dashed_ellipse(
		CHART_ORIGIN,
		UITheme.px(596.0) / maxf(zoom, 0.001),
		UITheme.px(310.0) / maxf(zoom, 0.001),
		Color(UITheme.ACCENT_DEEP, 0.50 * alpha)
	)
	_draw_dashed_ellipse(
		CHART_ORIGIN,
		UITheme.px(380.0) / maxf(zoom, 0.001),
		UITheme.px(198.0) / maxf(zoom, 0.001),
		Color(UITheme.ACCENT_DEEP, 0.32 * alpha)
	)


func _draw_dashed_ellipse(center: Vector2, radius_x: float, radius_y: float, color: Color) -> void:
	var circumference := PI * (3.0 * (radius_x + radius_y) - sqrt((3.0 * radius_x + radius_y) * (radius_x + 3.0 * radius_y)))
	var screen_step := UITheme.px(1.5) / maxf(zoom, 0.001)
	var steps := maxi(96, int(ceil(circumference / maxf(0.1, screen_step))))
	var dash := UITheme.px(2.0) / maxf(zoom, 0.001)
	var period := UITheme.px(11.0) / maxf(zoom, 0.001)
	var segments := PackedVector2Array()
	var travelled := 0.0
	var previous := center + Vector2(radius_x, 0.0)
	for index in range(1, steps + 1):
		var angle := TAU * float(index) / float(steps)
		var current := center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y)
		var segment_length := previous.distance_to(current)
		if fmod(travelled + segment_length * 0.5, period) < dash:
			segments.append(previous)
			segments.append(current)
		travelled += segment_length
		previous = current
	if not segments.is_empty():
		tree_canvas.draw_multiline(segments, color, 1.0 / maxf(zoom, 0.001), true)


func _draw_galactic_background() -> void:
	var field_alpha := _galactic_background_alpha()
	if field_alpha <= 0.01 or content_clip == null:
		return
	for index in range(galactic_background_stars.size()):
		var screen_position := Vector2(galactic_background_stars[index])
		var point := CHART_ORIGIN + (screen_position - GALACTIC_MAP_CENTER_SPEC * UITheme.SCALE) / maxf(zoom, 0.001)
		tree_canvas.draw_circle(
			point,
			float(galactic_background_star_radii[index]) / maxf(zoom, 0.001),
			Color(UITheme.GALACTIC_BACKGROUND_STAR, float(galactic_background_star_alphas[index]) * field_alpha)
		)


func _draw_galactic_core() -> void:
	var alpha := _galactic_core_alpha()
	if alpha <= 0.01:
		return
	var scale_amount := UITheme.px(GALACTIC_CORE_RADIUS_SPEC) / (maxf(zoom, 0.001) * galactic_core_max_length)
	for constellation_id in ChartData.CONSTELLATIONS:
		var constellation: Dictionary = ChartData.CONSTELLATIONS[constellation_id]
		for segment_variant in constellation.segments:
			var segment: Array = segment_variant
			var start := _galactic_core_point("%s/%s" % [constellation_id, String(segment[0])], scale_amount)
			var finish := _galactic_core_point("%s/%s" % [constellation_id, String(segment[1])], scale_amount)
			tree_canvas.draw_line(start, finish, Color(UITheme.LINE_INSTALLED, 0.40 * alpha), UITheme.px(0.7) / maxf(zoom, 0.001), true)
		for star_variant in constellation.stars:
			var star: Dictionary = star_variant
			var point := _galactic_core_point("%s/%s" % [constellation_id, String(star.id)], scale_amount)
			var radius_spec := maxf(0.85, 2.5 - float(star.magnitude) * 0.22)
			var star_alpha := clampf(0.95 - float(star.magnitude) * 0.07, 0.42, 0.95)
			tree_canvas.draw_circle(point, UITheme.px(radius_spec) / maxf(zoom, 0.001), Color(UITheme.STAR_INSTALLED, star_alpha * alpha))
	var centre_alpha := 1.0 if hovered_node_id.is_empty() or hovered_node_id == "galactic_reference_frame" else 0.45
	tree_canvas.draw_circle(CHART_ORIGIN, UITheme.px(4.2) / maxf(zoom, 0.001), Color(UITheme.INK_MAX, centre_alpha * alpha))


func _galactic_core_point(star_key: String, scale_amount: float) -> Vector2:
	var raw_offset := Vector2(base_star_positions[star_key]) - CHART_ORIGIN
	return CHART_ORIGIN + Vector2(raw_offset.x * scale_amount, raw_offset.y * scale_amount * GALACTIC_DISK_TILT)


func _galactic_label_alpha() -> float:
	# Code labels are screen-locked, so pulling below the normal galactic frame
	# shrinks the disc under labels that stay the same size and they collide.
	# Fade them across the extra range the completed chart unlocks: the wider
	# frame is for reading the shape, and the inspector still names what is
	# hovered.
	if zoom >= GALACTIC_ZOOM:
		return 1.0
	var span := maxf(0.0001, GALACTIC_ZOOM - GALACTIC_ZOOM_COMPLETE)
	return clampf((zoom - GALACTIC_ZOOM_COMPLETE) / span, 0.0, 1.0)


func _draw_local_group_decorations() -> void:
	var group_alpha := _local_group_alpha()
	if group_alpha <= 0.01:
		return
	for galaxy_variant in ChartData.LOCAL_GROUP_GALAXIES:
		var galaxy: Dictionary = galaxy_variant
		var node_id := String(galaxy.node_id)
		if not ChartData.is_local_group_decoration(node_id) or not node_positions.has(node_id):
			continue
		var center := Vector2(node_positions[node_id])
		var source_position := Vector2(galaxy.local_position)
		var axis := Vector2.RIGHT.rotated(source_position.angle() + deg_to_rad(58.0))
		var radius_spec := clampf(10.4 - float(galaxy.magnitude) * 0.38, 3.8, 9.5)
		var major := UITheme.px(radius_spec) / maxf(zoom, 0.001)
		var minor_axis := Vector2(-axis.y, axis.x)
		var color := Color(UITheme.STAR_BACKGROUND, 0.30 * group_alpha)
		tree_canvas.draw_line(center - axis * major, center + axis * major, color, UITheme.px(1.0) / maxf(zoom, 0.001), true)
		tree_canvas.draw_line(center - minor_axis * major * 0.20, center + minor_axis * major * 0.20, Color(UITheme.STAR_BACKGROUND, 0.18 * group_alpha), UITheme.px(0.7) / maxf(zoom, 0.001), true)
		tree_canvas.draw_circle(center, maxf(UITheme.px(0.8), major * 0.12), Color(UITheme.STAR_BACKGROUND, 0.38 * group_alpha))


func _draw_local_group_labels() -> void:
	var group_alpha := _local_group_alpha()
	if group_alpha <= 0.01:
		return
	var label_alpha := _galactic_label_alpha()
	var font := UITheme.mono()
	var font_size := maxi(1, int(round(float(UITheme.size_px(12.0)) / maxf(zoom, 0.001))))
	var tracking := UITheme.px(1.4) / maxf(zoom, 0.001)
	for galaxy_variant in ChartData.LOCAL_GROUP_GALAXIES:
		var galaxy: Dictionary = galaxy_variant
		var node_id := String(galaxy.node_id)
		var decorative := ChartData.is_local_group_decoration(node_id)
		if not node_positions.has(node_id):
			continue
		if not decorative and (not node_buttons.has(node_id) or not node_buttons[node_id].visible):
			continue
		var point := Vector2(node_positions[node_id])
		var source_position := Vector2(galaxy.local_position)
		var spec_radius := clampf(12.6 - float(galaxy.magnitude) * 0.52, 4.6, 13.0)
		var offset := UITheme.px(spec_radius + 13.0) / maxf(zoom, 0.001)
		var left := source_position.x < 0.0
		var label_position := point + Vector2(-offset if left else offset, -UITheme.px(8.0) / maxf(zoom, 0.001))
		var label := String(galaxy.bayer)
		if left:
			label_position.x -= _tracked_text_width(font, label, font_size, tracking)
		var active := not decorative and hovered_node_id == node_id
		# The hovered galaxy keeps its label at any zoom; it is the one the
		# player is asking about.
		var fade := 1.0 if active else label_alpha * (0.42 if decorative else 1.0)
		if fade <= 0.01:
			continue
		_draw_tracked_text(
			font,
			label_position,
			label,
			font_size,
			Color(UITheme.INK_MAX if active else UITheme.INK_MID, (1.0 if active else (0.52 if decorative else 0.70)) * group_alpha * fade),
			tracking
		)


func _tracked_text_width(font: Font, value: String, font_size: int, tracking: float) -> float:
	var width := 0.0
	for index in range(value.length()):
		width += font.get_char_size(value.unicode_at(index), font_size).x
		if index + 1 < value.length():
			width += tracking
	return width


func _draw_tracked_text(font: Font, position: Vector2, value: String, font_size: int, color: Color, tracking: float) -> void:
	var cursor := position + Vector2(0.0, font.get_ascent(font_size))
	for index in range(value.length()):
		var character := value.substr(index, 1)
		tree_canvas.draw_string(font, cursor, character, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
		cursor.x += font.get_char_size(value.unicode_at(index), font_size).x + tracking


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


func _draw_local_group_route() -> void:
	var current_route := _current_local_group_route()
	if current_route.size() < 2:
		return
	var installed_ratio := 0.0
	var frontier_start_ratio := 0.0
	var frontier_end_ratio := 0.0
	for galaxy_variant in ChartData.LOCAL_GROUP_GALAXIES:
		var galaxy: Dictionary = galaxy_variant
		var node_id := String(galaxy.node_id)
		var node_ratio := float(local_group_node_route_ratios.get(node_id, 1.0))
		var state := _cached_node_state(node_id)
		if state == "purchased":
			installed_ratio = node_ratio
			frontier_start_ratio = node_ratio
			continue
		if state == "available":
			frontier_end_ratio = node_ratio
		break
		break
	var visible_ratio := minf(installed_ratio, _galactic_route_progress())
	var presentation_alpha := _local_group_alpha()
	if visible_ratio > 0.0 and presentation_alpha > 0.01:
		var installed_route := _polyline_slice(current_route, 0.0, visible_ratio)
		if installed_route.size() >= 2:
			tree_canvas.draw_polyline(installed_route, Color(UITheme.ACCENT_PIP, 0.07 * presentation_alpha), UITheme.px(16.0) / maxf(zoom, 0.001), true)
			tree_canvas.draw_polyline(installed_route, Color(UITheme.LINE_INSTALLED, 0.62 * presentation_alpha), UITheme.px(1.4) / maxf(zoom, 0.001), true)
	if frontier_end_ratio > frontier_start_ratio and galactic_mode != GALACTIC_MODE_PULLBACK:
		var frontier_route := _polyline_slice(current_route, frontier_start_ratio, frontier_end_ratio)
		if frontier_route.size() >= 2:
			tree_canvas.draw_polyline(frontier_route, Color(UITheme.LINE_FRONTIER, 0.60 * _local_group_alpha()), UITheme.px(1.5) / maxf(zoom, 0.001), true)


func _current_local_group_route() -> PackedVector2Array:
	var control_points := PackedVector2Array([CHART_ORIGIN])
	for galaxy_variant in ChartData.LOCAL_GROUP_GALAXIES:
		var galaxy: Dictionary = galaxy_variant
		var node_id := String(galaxy.node_id)
		if ChartData.is_local_group_decoration(node_id):
			continue
		control_points.append(Vector2(node_positions.get(node_id, local_group_node_positions[node_id])))
	return _sample_local_group_route(control_points)


func _local_group_functional_order(node_id: String) -> int:
	var order := 0
	for galaxy_variant in ChartData.LOCAL_GROUP_GALAXIES:
		var candidate := String(Dictionary(galaxy_variant).node_id)
		if ChartData.is_local_group_decoration(candidate):
			continue
		order += 1
		if candidate == node_id:
			return order
	return 0


func _polyline_slice(points: PackedVector2Array, start_ratio: float, end_ratio: float) -> PackedVector2Array:
	var output := PackedVector2Array()
	if points.size() < 2 or end_ratio <= start_ratio:
		return output
	var total_length := _polyline_length(points)
	var start_length := total_length * clampf(start_ratio, 0.0, 1.0)
	var end_length := total_length * clampf(end_ratio, 0.0, 1.0)
	var travelled := 0.0
	for index in range(1, points.size()):
		var segment_start := points[index - 1]
		var segment_end := points[index]
		var segment_length := segment_start.distance_to(segment_end)
		var next_travelled := travelled + segment_length
		if next_travelled < start_length:
			travelled = next_travelled
			continue
		if travelled > end_length:
			break
		var local_start := clampf((start_length - travelled) / maxf(0.001, segment_length), 0.0, 1.0)
		var local_end := clampf((end_length - travelled) / maxf(0.001, segment_length), 0.0, 1.0)
		var clipped_start := segment_start.lerp(segment_end, local_start)
		var clipped_end := segment_start.lerp(segment_end, local_end)
		if output.is_empty() or not output[-1].is_equal_approx(clipped_start):
			output.append(clipped_start)
		output.append(clipped_end)
		if next_travelled >= end_length:
			break
		travelled = next_travelled
	return output


func _draw_frontier_overlay() -> void:
	# Only the current purchasable frontier stays lit. Purchased history is
	# already encoded by stable bright stars, so late-game DAG clutter never grows.
	for frontier_variant in _frontier_connections():
		var frontier: PackedStringArray = frontier_variant
		var source_id := String(frontier[0])
		var target_id := String(frontier[1])
		if _is_local_group_node(source_id) or _is_local_group_node(target_id):
			continue
		var presentation_alpha := maxf(_node_presentation_alpha(source_id), _node_presentation_alpha(target_id))
		var connection := _connection_points(source_id, target_id)
		var start := connection[0]
		var finish := connection[1]
		var line_width := 1.5
		if _is_local_group_node(target_id) or _is_local_group_node(source_id):
			line_width /= maxf(zoom, 0.001)
		tree_canvas.draw_line(start, finish, Color(UITheme.LINE_FRONTIER, 0.60 * presentation_alpha), line_width, true)
	if not hovered_node_id.is_empty() and node_positions.has(hovered_node_id):
		var hovered_state := _cached_node_state(hovered_node_id)
		if hovered_state == "locked" or hovered_state == "hidden":
			var hovered_definition := Balance.upgrade_definition(hovered_node_id)
			for prerequisite_variant in hovered_definition.prerequisites:
				var source_id := String(prerequisite_variant)
				if _cached_node_state(source_id) == "purchased":
					continue
				var presentation_alpha := _node_presentation_alpha(hovered_node_id)
				var connection := _connection_points(source_id, hovered_node_id)
				_draw_dashed_connection(connection[0], connection[1], Color(UITheme.LINE_IDLE, UITheme.LINE_IDLE.a * presentation_alpha))


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


func _draw_chart_horizon(alpha: float = 1.0) -> void:
	# The hand-off uses one almost-flat, continuously visible ridge. It still owns
	# occlusion because the ground fill is drawn after every constellation.
	var overhang := TREE_SIZE.x
	var ridge_line := PackedVector2Array()
	var sample_count := 96
	for index in range(sample_count + 1):
		var x := lerpf(-overhang, TREE_SIZE.x + overhang, float(index) / float(sample_count))
		var y := CHART_ORIGIN.y + sin(x * 0.0042) * 5.0 + sin(x * 0.0131 + 1.2) * 3.0
		ridge_line.append(Vector2(x, y))
	var ground_color := Color(UITheme.GROUND, UITheme.GROUND.a * alpha)
	var ground_bottom := TREE_SIZE.y + overhang
	for index in range(ridge_line.size() - 1):
		var start := ridge_line[index]
		var finish := ridge_line[index + 1]
		tree_canvas.draw_colored_polygon(PackedVector2Array([
			start,
			finish,
			Vector2(finish.x, ground_bottom),
			Vector2(start.x, ground_bottom),
		]), ground_color)
	tree_canvas.draw_polyline(ridge_line, Color(UITheme.HORIZON, 0.90 * alpha), 1.4, true)
	# Due north is a single instrument tick through the ridge, matching the fixed
	# label in the bottom information band.
	tree_canvas.draw_line(
		Vector2(CHART_ORIGIN.x, CHART_ORIGIN.y - 4.0),
		Vector2(CHART_ORIGIN.x, CHART_ORIGIN.y + 26.0),
		Color(UITheme.HORIZON_TICK, 0.85 * alpha),
		1.4,
		true
	)


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
