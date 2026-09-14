extends CanvasLayer

signal tree_opened
signal tree_closed
signal galactic_pullback_finished
signal observatory_requested

const Balance = preload("res://scripts/game_balance.gd")
const ChartData = preload("res://scripts/research_chart_data.gd")
const ExtensionChart = preload("res://scripts/constellation_extension_data.gd")
const UITheme = preload("res://scripts/ui_theme.gd")
const StarNodeVisual = preload("res://scripts/research_star_visual.gd")
const ACTION_CHART := &"nw_chart"
const ACTION_MENU_BACK := &"nw_menu_back"
const ATLAS_ACTION_ORIGIN := Vector2(34, 438)
const ATLAS_ACTION_SIZE := Vector2(172, 34)
const ATLAS_ACTION_STEP := Vector2(0, 46)
const RAW_DEBUG_KEYS := [
	KEY_D,
	KEY_N,
	KEY_A,
	KEY_M,
	KEY_R,
	KEY_S,
	KEY_F,
	KEY_E,
	KEY_BACKSPACE,
]

const TREE_SIZE := Vector2(1460, 780)
const MIN_ZOOM := 0.55
const MAX_ZOOM := 1.28
const COMPLETED_FIGURE_SCALE := 0.75
const GALACTIC_ZOOM := 0.18
# Installing every node earns a wider frame. The galaxy map still opens at
# GALACTIC_ZOOM; this only lowers the floor the player can pull back to, so the
# extra room is chosen rather than imposed.
const GALACTIC_NODE_SCREEN_SCALE := StarNodeVisual.GALACTIC_NODE_SCREEN_SCALE
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
const HOLD_PURCHASE_SECONDS := 0.75
const CHART_ORIGIN := Vector2(TREE_SIZE.x * 0.5, TREE_SIZE.y * 0.91)
const CONSTELLATION_ZOOM := UITheme.SCALE * 1.06
const ROTATION_STEP := deg_to_rad(6.0)
const DEFAULT_ROTATION := 0.0
const STAR_HIT_SIZE := Vector2(44.0, 44.0)
const MIN_STAR_SCREEN_SEPARATION := 18.0
const STAR_SCREEN_EDGE_GAP := 6.0
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
const GALACTIC_LEDGER_ORDER := [
	"cassiopeia", "big_dipper", "orion", "andromeda", "perseus", "lyra",
	"gemini", "taurus", "leo", "ursa_minor", "canis_major", "draco",
]
const CLUSTER_MARKER_OFFSETS := StarNodeVisual.CLUSTER_MARKER_OFFSETS



var chart_constellations: Dictionary = ChartData.CONSTELLATIONS.merged(ExtensionChart.CONSTELLATIONS)
var chart_placements: Dictionary = ChartData.PLACEMENTS.merged(ExtensionChart.PLACEMENTS)
var extension_definitions: Array[Dictionary] = ExtensionChart.definitions()
var extension_research: Node
var expanded_view_initialized := false
var pullback_start_rotation := 0.0
var atlas_actions: Array[Button] = []
var atlas_navigation: ColorRect
var constellation_ledger_hits: Array[Button] = []
var progression: Node
var settings_controller: Node
var tutorial_controller: Node
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
var inspector_details: VBoxContainer
var inspector_details_button: Button
var inspector_scroll: ScrollContainer
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
var installation_rule: ColorRect
var installation_tween: Tween
var installation_node_id: String = ""
var north_label: Label
var subtitle_label: Label
var close_button: Button
var module_popup: CanvasLayer
var hub_return_button: Button
var controls_label: Label
var constellation_horizon_hint: Label
var constellation_bottom_action: Label

var node_buttons: Dictionary = {}
var node_hold_bars: Dictionary = {}
var star_positions: Dictionary = {}
var node_positions: Dictionary = {}
var node_star_records: Dictionary = {}
var base_star_positions: Dictionary = {}
var expanded_star_positions: Dictionary = {}
var shared_star_node_ids: Dictionary = {}
var readable_star_positions: Dictionary = {}
var star_neighbor_clearances: Dictionary = {}
var spacing_cache_key := Vector2(-1, -1)
var star_node_ids: Dictionary = {}

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
var constellation_halo: GradientTexture2D
var galactic_unlocked: bool = false
var galactic_pullback_seen: bool = false
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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	node_star_records = ChartData.node_star_map().merged(ExtensionChart.node_star_map())
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
	if not settings_controller.number_notation_changed.is_connected(_on_number_notation_changed):
		settings_controller.number_notation_changed.connect(_on_number_notation_changed)
	if settings_controller.has_signal("binding_changed"):
		var binding_callback := Callable(self, "_on_binding_changed")
		if not settings_controller.is_connected("binding_changed", binding_callback):
			settings_controller.connect("binding_changed", binding_callback)
	rotation_offset = settings_controller.get_research_chart_rotation()
	_layout_chart()
	_apply_locale()


func bind_tutorial(controller: Node) -> void:
	tutorial_controller = controller


func configure_galactic_state(unlocked: bool, pullback_seen: bool) -> void:
	_cancel_installation_rule()
	galactic_unlocked = unlocked
	galactic_pullback_seen = unlocked and pullback_seen
	pullback_elapsed = 0.0
	if galactic_pullback_seen:
		galactic_mode = GALACTIC_MODE_FINAL
		galactic_chart_detail = 1.0
	else:
		galactic_mode = GALACTIC_MODE_NORMAL
		galactic_chart_detail = 1.0
	if tree_canvas != null:
		_layout_chart()
		_update_galactic_presentation()


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
	if module_popup != null and module_popup.is_open():
		module_popup.close()
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
	if _constellation_panel_active() and tooltip_panel.is_visible_in_tree():
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
	if intermission_active:
		subtitle_label.text = tr("TREE_NEXT_OBSERVATION") % [intermission_next_round, intermission_next_duration]
		close_button.text = _chart_action_text("TREE_START_OBSERVATION")
	else:
		subtitle_label.text = tr("TREE_SUBTITLE")
		close_button.text = _chart_action_text("TREE_CLOSE")
	if data_context_label != null:
		data_context_label.text = tr("TREE_DATA_CONTEXT") % [intermission_next_round, intermission_next_duration]
		data_context_label.visible = true
	if constellation_bottom_action != null:
		constellation_bottom_action.text = _phase_bottom_action_text()
	_refresh_galactic_completion_detail()
	_layout_chart_header()


func _phase_bottom_action_text() -> String:
	return _chart_action_text("TREE_BOTTOM_START_OBSERVATION") if intermission_active else _chart_action_text("TREE_BOTTOM_CLOSE")


func _phase_galactic_return_text() -> String:
	return _chart_action_text("TREE_GALACTIC_RETURN")


func _chart_action_text(key: String) -> String:
	var localized := tr(key)
	if "%s" not in localized:
		return localized
	var binding := "U"
	if settings_controller != null and settings_controller.has_method("binding_label"):
		binding = String(settings_controller.call("binding_label", ACTION_CHART))
	return localized % binding


func _input(event: InputEvent) -> void:
	if module_popup != null and module_popup.game.module_tutorial.active:
		return
	if module_popup != null and module_popup.is_open():
		return
	if not is_open():
		return
	var raw_debug_input := _is_raw_debug_input(event)
	var close_requested := (
		not raw_debug_input
		and (_action_pressed(event, ACTION_CHART) or _action_pressed(event, ACTION_MENU_BACK))
	)
	# The tutorial completion card can appear above an already-open chart. Keep
	# its modal pause intact instead of allowing the chart's first-refusal close
	# path to unpause the simulation behind that card.
	if close_requested and _tutorial_is_modal():
		get_viewport().set_input_as_handled()
		return
	if galactic_mode == GALACTIC_MODE_PULLBACK and _is_deliberate_pullback_skip(event):
		_finish_galactic_pullback()
		if close_requested:
			observatory_requested.emit()
		# Let an ordinary mouse press continue through the GUI so a press on the
		# close action both skips and closes. Wheel presses are consumed here so the
		# same event cannot immediately zoom away from the final galaxy frame.
		if close_requested or not (event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]):
			get_viewport().set_input_as_handled()
		return
	if close_requested:
		close_tree()
		get_viewport().set_input_as_handled()
		return


func _action_pressed(event: InputEvent, action: StringName) -> bool:
	return InputMap.has_action(action) and event.is_action_pressed(action, false, true)


func _is_raw_debug_input(event: InputEvent) -> bool:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return false
	if event.keycode == KEY_F9:
		return true
	return event.ctrl_pressed and event.shift_pressed and event.keycode in RAW_DEBUG_KEYS


func _tutorial_is_modal() -> bool:
	return (
		tutorial_controller != null
		and tutorial_controller.has_method("is_modal_step")
		and bool(tutorial_controller.call("is_modal_step"))
	)


func _process(delta: float) -> void:
	_flush_pending_rotation()
	if galactic_mode == GALACTIC_MODE_PULLBACK:
		_advance_galactic_pullback(delta)
	if held_node_id.is_empty():
		return
	if not is_open() or progression == null:
		_cancel_node_hold()
		return
	if _research_state(held_node_id) != "available" or not _can_research(held_node_id):
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
	_layout_chart()
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
		expanded_view_initialized = false
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
	pullback_start_rotation = rotation_offset
	pullback_start_zoom = zoom
	pullback_start_pan = pan_position
	galactic_chart_detail = 1.0
	_update_galactic_presentation()


func _advance_galactic_pullback(delta: float) -> void:
	pullback_elapsed = minf(PULLBACK_DURATION, pullback_elapsed + maxf(0.0, delta))
	var ratio := _ease_in_out(clampf(pullback_elapsed / PULLBACK_DURATION, 0.0, 1.0))
	zoom = lerpf(pullback_start_zoom, 0.43, ratio)
	rotation_offset = lerpf(pullback_start_rotation, 2.1, ratio)
	galactic_chart_detail = 1.0
	pan_position = pullback_start_pan.lerp(_galactic_pan_for_zoom(zoom), ratio)
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
	galactic_chart_detail = 1.0
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


func _galactic_pan_for_zoom(target_zoom: float, _chart_detail: float = 1.0) -> Vector2:
	return Vector2(UITheme.px(960), UITheme.px(1008)) - CHART_ORIGIN * target_zoom


func _frame_galaxy() -> void:
	if content_clip == null or content_clip.size.x <= 1.0:
		return
	galactic_chart_detail = 1.0
	galactic_mode = GALACTIC_MODE_FINAL
	if not expanded_view_initialized:
		focus_outer_constellations()
	else:
		_layout_chart()
		_apply_transform()
		_update_galactic_presentation()


func _galactic_zoom_floor() -> float:
	return 0.34 if galactic_unlocked else MIN_ZOOM


func _zoom_galactic_chart(factor: float) -> void:
	var old_zoom := zoom
	var focused_view := not pan_position.is_equal_approx(_galactic_pan_for_zoom(old_zoom))
	zoom = clampf(zoom * factor, _galactic_zoom_floor(), MAX_ZOOM)
	galactic_chart_detail = 1.0
	if focused_view:
		# Keep a selected legacy figure in the reading area during Ctrl+wheel.
		var focus_point := Vector2(560, 330)
		pan_position = focus_point - (focus_point - pan_position) * zoom / old_zoom
	else:
		pan_position = _galactic_pan_for_zoom(zoom)
	_layout_chart()
	_apply_transform()
	_update_galactic_presentation()


func _galactic_chart_is_readable() -> bool:
	return true


func _visible_base_research_count() -> int:
	return Balance.research_node_count()


func _visible_base_owned_count() -> int:
	if progression == null:
		return 0
	var count := 0
	for definition in Balance.UPGRADE_NODES:
		var node_id := String(definition.id)
		if progression.has_upgrade(node_id):
			count += 1
	return count


func _legacy_chart_alpha() -> float:
	return 1.0


func _node_presentation_alpha(node_id: String) -> float:
	if _is_extension_node(node_id) and not galactic_unlocked:
		return 0.0
	if node_id == "galactic_reference_frame" and galactic_unlocked:
		return 1.0
	return _legacy_chart_alpha()


func _node_interaction_ready(node_id: String) -> bool:
	if _is_extension_node(node_id) and not galactic_unlocked:
		return false
	if node_id == "galactic_reference_frame" and galactic_unlocked:
		# The 112-spec-pixel core target owns galactic-scale input. The original
		# star button returns only when the completed chart becomes readable again.
		return galactic_pullback_seen and _galactic_chart_is_readable()
	return galactic_mode != GALACTIC_MODE_PULLBACK and _galactic_chart_is_readable()


func _galactic_structure_alpha() -> float:
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
	_layout_chart()
	_apply_transform()


func _on_content_resized() -> void:
	_cancel_installation_rule()
	_layout_chart_header()
	if is_open() and content_clip.size.x > 1.0 and content_clip.size.y > 1.0:
		call_deferred("_frame_frontier")


func _apply_transform() -> void:
	tree_canvas.position = pan_position
	tree_canvas.scale = Vector2.ONE * zoom
	if north_label != null:
		north_label.position.y = minf(_north_label_y(), overlay.size.y - UITheme.px(60.0) - north_label.get_combined_minimum_size().y)


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
	return UITheme.grouped_integer(value)


func _data_number(value: float) -> String:
	return settings_controller.format_data(value) if settings_controller != null else UITheme.data_number(value)


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
		count_y + UITheme.mono_tabular().get_ascent(UITheme.size_px(38.0)) - UITheme.mono().get_ascent(UITheme.size_px(26.0))
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
		var owned := _visible_base_owned_count() + (_extension_owned_count() if galactic_unlocked else 0)
		var total := _visible_base_research_count() + (extension_definitions.size() if galactic_unlocked else 0)
		ratio = float(owned) / maxf(1.0, float(total))
	progress_fill.size = Vector2(line_width * clampf(ratio, 0.0, 1.0), UITheme.px(2.0))
	tree_status.position.y = progress_track.position.y + progress_track.size.y + UITheme.px(10.0)
	completion_detail_label.position.y = tree_status.position.y + tree_status.get_combined_minimum_size().y + UITheme.px(10.0)
	var watermark_width := UITheme.px(320.0)

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
	north_label.size.x = wide
	north_label.position.x = 0.0
	var bottom_y := frame.y - UITheme.px(38.0)
	north_label.position.y = minf(_north_label_y(), overlay.size.y - UITheme.px(60.0) - north_label.get_combined_minimum_size().y)
	if constellation_bottom_action != null:
		constellation_bottom_action.size.x = UITheme.px(430.0)
		constellation_bottom_action.position = Vector2(frame.x - UITheme.px(40.0) - constellation_bottom_action.size.x, bottom_y - constellation_bottom_action.get_combined_minimum_size().y)
	_layout_constellation_overlays()


func _north_label_y() -> float:
	# The label rides with the horizon so the pivot stays legible at any zoom.
	var origin_y := tree_canvas.global_position.y + CHART_ORIGIN.y * zoom - overlay.global_position.y
	return origin_y + UITheme.px(16.0)


func _constellation_panel_active() -> bool:
	return galactic_mode != GALACTIC_MODE_PULLBACK and _galactic_chart_is_readable()


func _layout_constellation_overlays() -> void:
	if overlay == null or constellation_ledger == null or tooltip_panel == null:
		return
	var frame := overlay.size
	constellation_ledger.position = Vector2(UITheme.px(56.0), UITheme.px(206.0))
	constellation_ledger.size = Vector2(UITheme.px(288.0), maxf(0.0, frame.y - constellation_ledger.position.y - UITheme.px(70.0)))
	_set_inspector_details(inspector_details_button.button_pressed)
	var ledger_title: Label = constellation_ledger.get_node("LedgerTitle")
	ledger_title.position = Vector2.ZERO
	ledger_title.size.x = constellation_ledger.size.x
	var row_y := ledger_title.get_combined_minimum_size().y + UITheme.px(10.0)
	for index in range(constellation_ledger_names.size()):
		var name_label := constellation_ledger_names[index]
		if not name_label.visible: continue
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
		constellation_ledger_hits[index].position = Vector2(0, row_y)
		constellation_ledger_hits[index].size = Vector2(constellation_ledger.size.x, 20)
		row_y += maxf(name_label.get_combined_minimum_size().y, count_label.get_combined_minimum_size().y) + UITheme.px(10.0)
	tooltip_panel.position = Vector2(frame.x - UITheme.px(40.0) - UITheme.px(292.0), UITheme.px(196.0))
	tooltip_panel.size = Vector2(UITheme.px(292.0), maxf(1.0, frame.y - UITheme.px(196.0) - UITheme.px(70.0)))


func _show_completed_constellations() -> void:
	_cancel_node_hold()
	_layout_chart()
	_refresh()
	_update_galactic_presentation()


func _refresh_atlas_navigation() -> void:
	if atlas_navigation != null:
		atlas_navigation.visible = galactic_unlocked
	for action in atlas_actions:
		action.visible = galactic_unlocked
		action.text = tr("ATLAS_EXPAND")
	if module_popup != null:
		module_popup.place_launcher()


func _refresh_galactic_overlays() -> void:
	var active := _constellation_panel_active()
	_refresh_atlas_navigation()
	constellation_ledger.visible = active
	tooltip_panel.visible = active and not selected_node_id.is_empty()
	if installation_rule != null and not installation_rule.is_visible_in_tree():
		_cancel_installation_rule()
	systems_readout.visible = false
	galactic_progress_installed.visible = true
	galactic_progress_separator.visible = true
	galactic_progress_total.visible = true
	constellation_horizon_hint.visible = active
	constellation_bottom_action.visible = active
	completion_detail_label.visible = active
	if active:
		_refresh_constellation_overlays()


func _refresh_constellation_overlays() -> void:
	if progression == null or constellation_ledger == null:
		return
	if selected_node_id.is_empty() or not node_buttons.has(selected_node_id):
		selected_node_id = _default_constellation_selection()
	var below_horizon_count := 0
	for index in range(_constellation_order().size()):
		var constellation_id: String = _constellation_order()[index]
		var is_extension := constellation_id in ExtensionChart.ORDER
		var show_row := galactic_unlocked if is_extension else not (galactic_unlocked and _constellation_complete(constellation_id))
		for widget in [constellation_ledger_names[index], constellation_ledger_counts[index], constellation_ledger_notes[index], constellation_ledger_leaders[index], constellation_ledger_hits[index]]:
			widget.visible = show_row
		if not show_row: continue
		var constellation: Dictionary = chart_constellations[constellation_id]
		var installed := 0
		var total := 0
		var opened := false
		for star_variant in constellation.stars:
			var star: Dictionary = star_variant
			var node_id := String(star.get("node_id", ""))
			if node_id.is_empty():
				continue
			total += 1
			var state: String = _research_state(node_id)
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
		constellation_ledger_counts[index].text = "%d / %d" % [installed, total] if total > 0 else "—"
		var note := ""
		if below_horizon:
			note = tr("TREE_CONSTELLATION_BELOW_HORIZON")
		elif kind == "active":
			note = tr("TREE_CONSTELLATION_IN_PROGRESS")
		elif kind == "locked":
			note = tr("TREE_CONSTELLATION_LOCKED")
		constellation_ledger_notes[index].text = note
	constellation_horizon_hint.text = tr("TREE_CONSTELLATION_HORIZON_HINT") % below_horizon_count
	constellation_bottom_action.text = _phase_bottom_action_text()
	_refresh_constellation_detail_line()
	if not selected_node_id.is_empty():
		_refresh_constellation_inspector(selected_node_id)
	_layout_constellation_overlays()


func _constellation_below_horizon(constellation_id: String) -> bool:
	var placement: Dictionary = chart_placements[constellation_id]
	return sin(float(placement.anchor_angle) + rotation_offset) > 0.0


func _default_constellation_selection() -> String:
	if progression == null:
		return ""
	if galactic_unlocked:
		for definition in extension_definitions:
			if _research_state(definition.id) == "available" and _is_node_above_horizon(definition.id):
				return definition.id
	for require_affordable in [true, false]:
		for definition in Balance.UPGRADE_NODES:
			var node_id := String(definition.id)
			if progression.get_node_state(node_id) != "available":
				continue
			if require_affordable and not progression.can_purchase(node_id):
				continue
			if _is_node_above_horizon(node_id):
				return node_id
	for definition_index in range(Balance.UPGRADE_NODES.size() - 1, -1, -1):
		var node_id := String(Balance.UPGRADE_NODES[definition_index].id)
		if progression.get_node_state(node_id) == "purchased" and _is_node_above_horizon(node_id):
			return node_id
	return ""


func _refresh_constellation_detail_line() -> void:
	if completion_detail_label == null or progression == null:
		return
	var group_label := tr("TREE_CONSTELLATION_CURRENT_SKY")
	if not selected_node_id.is_empty() and node_star_records.has(selected_node_id):
		var star_record: Dictionary = node_star_records[selected_node_id]
		var constellation_id := String(star_record.constellation_id)
		group_label = tr(String(chart_constellations[constellation_id].label_key)).split("  /  ")[0]
	if galactic_unlocked:
		completion_detail_label.text = tr("ATLAS_FIELD_RECORDS") % [group_label, _extension_owned_count(), extension_definitions.size()]
		return
	var non_draco_installed := 0
	for definition in Balance.UPGRADE_NODES:
		var node_id := String(definition.id)
		if String(definition.branch) == "draco":
			continue
		if progression.get_node_state(node_id) == "purchased":
			non_draco_installed += 1
	var remaining := maxi(0, 86 - non_draco_installed)
	if remaining > 0:
		completion_detail_label.text = tr("TREE_CONSTELLATION_DRACO_REMAINING") % [group_label, remaining]
	else:
		completion_detail_label.text = tr("TREE_CONSTELLATION_DRACO_OPEN") % group_label


func _set_inspector_details(expanded: bool) -> void:
	inspector_details.visible = expanded
	inspector_details_button.text = tr("UI_DETAILS_HIDE" if expanded else "TREE_DETAILS_SHOW")
	# Only expanded help owns the scroll surface. The ordinary inspector stays
	# transparent to star hits, apart from its explicit disclosure button.
	inspector_scroll.mouse_filter = Control.MOUSE_FILTER_STOP if expanded else Control.MOUSE_FILTER_IGNORE


func _set_inspector_purchase_state(state: String) -> void:
	# Installed state is stated once; there is no longer a purchase to price.
	tooltip_action.visible = state != "purchased"
	tooltip_cost.visible = state != "purchased"
	tooltip_panel.find_child("FieldCostLabel", true, false).visible = state != "purchased"


func _refresh_constellation_static_text() -> void:
	if constellation_ledger == null or tooltip_panel == null:
		return
	var ledger_title: Label = constellation_ledger.get_node("LedgerTitle")
	ledger_title.text = tr("TREE_CONSTELLATION_LEDGER")
	for index in range(_constellation_order().size()):
		var constellation: Dictionary = chart_constellations[_constellation_order()[index]]
		constellation_ledger_names[index].text = tr(String(constellation.label_key)).split("  /  ")[0]
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


func _refresh_galactic_completion_detail() -> void:
	if completion_detail_label != null:
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
	spacing_cache_key = Vector2(-1, -1)
	base_star_positions.clear()
	star_node_ids.clear()
	shared_star_node_ids.clear()
	for constellation_id in chart_constellations:
		var constellation: Dictionary = chart_constellations[constellation_id]
		var placement: Dictionary = chart_placements[constellation_id]
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
	for constellation_id in ExtensionChart.ORDER:
		for star in ExtensionChart.CONSTELLATIONS[constellation_id].stars:
			if star.has("shared_star_key"):
				var key := "%s/%s" % [constellation_id, star.id]
				# Move the whole figure to its shared corner. Replacing only that
				# corner would distort the catalogue-derived Pegasus square.
				var shift: Vector2 = base_star_positions[star.shared_star_key] - base_star_positions[key]
				for member in chart_constellations[constellation_id].stars:
					base_star_positions[constellation_id + "/" + member.id] += shift
				star_node_ids[key] = star_node_ids[star.shared_star_key]
				shared_star_node_ids[star_node_ids[key]] = true
	expanded_star_positions = base_star_positions.duplicate()
	# Keep the catalogue geometry immutable. Only the post-expansion view uses
	# smaller legacy figures, uniformly scaled around their own star centroid.
	for constellation_id in ChartData.CONSTELLATIONS:
		var stars: Array = chart_constellations[constellation_id].stars
		var center := Vector2.ZERO
		for star in stars:
			center += Vector2(base_star_positions[constellation_id + "/" + star.id])
		center /= float(stars.size())
		for star in stars:
			var key: String = constellation_id + "/" + star.id
			expanded_star_positions[key] = center + (Vector2(base_star_positions[key]) - center) * COMPLETED_FIGURE_SCALE
	# The outer figure retains its full size and follows its shared corner.
	for constellation_id in ExtensionChart.ORDER:
		for star in chart_constellations[constellation_id].stars:
			if not star.has("shared_star_key"): continue
			var shift: Vector2 = expanded_star_positions[star.shared_star_key] - expanded_star_positions[constellation_id + "/" + star.id]
			for member in chart_constellations[constellation_id].stars:
				expanded_star_positions[constellation_id + "/" + member.id] += shift


func _chart_source_positions() -> Dictionary:
	return expanded_star_positions if galactic_unlocked else base_star_positions


func _readable_chart_positions() -> Dictionary:
	var cache_key := Vector2(zoom, 1.0 if galactic_unlocked else 0.0)
	if spacing_cache_key == cache_key: return readable_star_positions
	var source := _chart_source_positions()
	readable_star_positions = source.duplicate()
	# User-approved readability offsets are applied to the view, never the
	# catalogue. Solve in unrotated space so wheel rotation cannot shuffle stars.
	for cid in chart_constellations:
		var stars: Array = chart_constellations[cid].stars
		var keys: Array[String] = []
		var radii: Array[float] = []
		var figure_zoom := maxf(zoom, CONSTELLATION_ZOOM) if cid in ExtensionChart.ORDER else zoom
		for star in stars:
			keys.append(cid + "/" + star.id)
			radii.append(clampf(7.4 - float(star.magnitude) * 0.82, 3.4, 7.4) * figure_zoom)
		for iteration in range(32):
			var largest_overlap := 0.0
			for a in keys.size():
				for b in range(a + 1, keys.size()):
					var separation := maxf(MIN_STAR_SCREEN_SEPARATION, radii[a] + radii[b] + STAR_SCREEN_EDGE_GAP) / maxf(zoom, 0.001)
					var delta: Vector2 = readable_star_positions[keys[b]] - readable_star_positions[keys[a]]
					var overlap := separation - delta.length()
					if overlap <= 0.0: continue
					largest_overlap = maxf(largest_overlap, overlap)
					var direction := delta.normalized() if delta.length_squared() > 0.000001 else Vector2.RIGHT.rotated(float(a + b))
					var correction := direction * overlap * 0.5
					readable_star_positions[keys[a]] -= correction
					readable_star_positions[keys[b]] += correction
			if largest_overlap * zoom < 0.01: break
	# Alpheratz is one marker. Move the complete outer figure to its shared
	# corner after spacing, preserving its square and the shared input owner.
	for cid in ExtensionChart.ORDER:
		for star in chart_constellations[cid].stars:
			if not star.has("shared_star_key"): continue
			var shift: Vector2 = readable_star_positions[star.shared_star_key] - readable_star_positions[cid + "/" + star.id]
			for member in chart_constellations[cid].stars:
				readable_star_positions[cid + "/" + member.id] += shift
			readable_star_positions[cid + "/" + star.id] = readable_star_positions[star.shared_star_key]
	_separate_neighboring_figures()
	star_neighbor_clearances.clear()
	for cid in chart_constellations:
		for star in chart_constellations[cid].stars:
			var key: String = cid + "/" + star.id
			if not star_node_ids.has(key): continue
			var id: String = star_node_ids[key]
			var clearance: float = star_neighbor_clearances.get(id, INF)
			for other in chart_constellations[cid].stars:
				if other.id == star.id: continue
				clearance = minf(clearance, Vector2(readable_star_positions[key]).distance_to(readable_star_positions[cid + "/" + other.id]))
			star_neighbor_clearances[id] = clearance
	spacing_cache_key = cache_key
	return readable_star_positions


func _separate_neighboring_figures() -> void:
	var groups := {}
	for cid in chart_constellations:
		if cid in ExtensionChart.ORDER and not galactic_unlocked: continue
		var group_id: String = cid
		for star in chart_constellations[cid].stars:
			if star.has("shared_star_key"): group_id = String(star.shared_star_key).get_slice("/", 0)
		if not groups.has(group_id): groups[group_id] = []
		for star in chart_constellations[cid].stars:
			groups[group_id].append(cid + "/" + star.id)
	var ids: Array = groups.keys()
	var gap := maxf(MIN_STAR_SCREEN_SEPARATION, 14.8 * maxf(zoom, CONSTELLATION_ZOOM) + STAR_SCREEN_EDGE_GAP) / maxf(zoom, 0.001)
	for iteration in range(16):
		var moved := false
		for a in ids.size():
			for b in range(a + 1, ids.size()):
				var one: Array = groups[ids[a]]
				var two: Array = groups[ids[b]]
				var bounds_a := Rect2(readable_star_positions[one[0]], Vector2.ZERO)
				var bounds_b := Rect2(readable_star_positions[two[0]], Vector2.ZERO)
				for key in one: bounds_a = bounds_a.expand(readable_star_positions[key])
				for key in two: bounds_b = bounds_b.expand(readable_star_positions[key])
				if not bounds_a.grow(gap).intersects(bounds_b, true): continue
				var closest := Vector2.INF
				for key_a in one:
					for key_b in two:
						var delta: Vector2 = readable_star_positions[key_b] - readable_star_positions[key_a]
						if delta.length_squared() < closest.length_squared(): closest = delta
				var overlap := gap - closest.length()
				if overlap * zoom < 0.01: continue
				var direction := closest.normalized() if closest.length_squared() > 0.000001 else Vector2.RIGHT
				var correction := direction * overlap * 0.5
				for key in one: readable_star_positions[key] -= correction
				for key in two: readable_star_positions[key] += correction
				moved = true
		if not moved: break
	# Hidden shared corners still follow their owning base figure.
	if not galactic_unlocked:
		for cid in ExtensionChart.ORDER:
			for star in chart_constellations[cid].stars:
				if star.has("shared_star_key"):
					var shift: Vector2 = readable_star_positions[star.shared_star_key] - readable_star_positions[cid + "/" + star.id]
					for member in chart_constellations[cid].stars:
						readable_star_positions[cid + "/" + member.id] += shift
					readable_star_positions[cid + "/" + star.id] = readable_star_positions[star.shared_star_key]


func _completed_figure_tone(constellation_id: String) -> float:
	if not galactic_unlocked or constellation_id in ExtensionChart.ORDER or progression == null:
		return 1.0
	if not _constellation_complete(constellation_id): return 1.0
	return lerpf(0.58, 1.0, smoothstep(0.65, 1.0, zoom))


func _update_star_tone(node_id: String) -> void:
	# Dimming the visual must not disable the button's presentation/input gate.
	var tone := 1.0 if shared_star_node_ids.has(node_id) else _completed_figure_tone(node_star_records[node_id].constellation_id)
	node_hold_bars[node_id].modulate.a = tone


func _layout_chart() -> void:
	if tree_canvas == null:
		return
	chart_layout_passes += 1
	star_positions.clear()
	node_positions.clear()
	var positions := _readable_chart_positions()
	for star_key_variant in positions:
		var star_key := String(star_key_variant)
		var base_position := Vector2(positions[star_key])
		var rotated_position := CHART_ORIGIN + (base_position - CHART_ORIGIN).rotated(rotation_offset)
		var chart_position := _present_chart_position(rotated_position)
		star_positions[star_key] = chart_position
		if star_node_ids.has(star_key):
			node_positions[String(star_node_ids[star_key])] = chart_position
	for node_id in node_positions:
		if not node_buttons.has(node_id):
			continue
		var button: Button = node_buttons[node_id]
		var center := Vector2(node_positions[node_id])
		button.position = center - button.size * 0.5
		var presentation_alpha := _node_presentation_alpha(String(node_id))
		button.scale = Vector2.ONE * _node_render_scale(String(node_id), presentation_alpha)
		node_hold_bars[node_id].set_neighbor_clearance(float(star_neighbor_clearances.get(node_id, INF)) / button.scale.x)
		button.modulate.a = presentation_alpha
		_update_star_tone(String(node_id))
		button.mouse_filter = Control.MOUSE_FILTER_STOP if presentation_alpha >= 0.92 and _node_interaction_ready(String(node_id)) else Control.MOUSE_FILTER_IGNORE
		button.visible = (
			bool(button.get_meta("revealed", true))
			and presentation_alpha > 0.01
			and (not _galactic_horizon_active() or center.y <= CHART_ORIGIN.y)
		)
	if progression != null and _constellation_panel_active():
		_refresh_constellation_overlays()
	tree_canvas.queue_redraw()


func _present_chart_position(chart_position: Vector2) -> Vector2:
	return chart_position


func _node_render_scale(node_id: String, presentation_alpha: float) -> float:
	if _is_extension_node(node_id):
		return maxf(1.0, CONSTELLATION_ZOOM / maxf(zoom, 0.001))
	var galaxy_presence := 0.0
	if node_id == "galactic_reference_frame" and galactic_unlocked:
		galaxy_presence = 1.0 - smoothstep(0.05, 0.34, galactic_chart_detail)
	if galaxy_presence <= 0.0:
		return 1.0
	var screen_fixed_scale := GALACTIC_NODE_SCREEN_SCALE / maxf(zoom, 0.001)
	return lerpf(1.0, screen_fixed_scale, galaxy_presence)


func _galactic_horizon_active() -> bool:
	return true


func _is_node_above_horizon(node_id: String) -> bool:
	# Before the first layout there are no positions yet; the layout pass that
	# follows settles it.
	if not node_positions.has(node_id):
		return true
	return not _galactic_horizon_active() or Vector2(node_positions[node_id]).y <= CHART_ORIGIN.y


func _on_node_hold_started(node_id: String) -> void:
	_cancel_node_hold()
	if not node_star_records.has(node_id): return
	if galactic_unlocked and galactic_pullback_seen and not _is_extension_node(node_id) and zoom < 0.8:
		focus_constellation(node_star_records[node_id].constellation_id)
		selected_node_id = node_id
		_refresh_constellation_inspector(node_id)
	if hovered_node_id == node_id and not tooltip_suppressed_until_motion:
		_show_node_tooltip(node_id)
	if progression == null or _research_state(node_id) != "available" or not _can_research(node_id):
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
	var id := held_node_id
	var hold_bar: StarNodeVisual = node_hold_bars[id]
	held_node_id = ""
	hold_elapsed = 0.0
	var purchased: bool = extension_research.purchase(id) if _is_extension_node(id) else progression.request_purchase(id)
	if purchased:
		var research_name: String = extension_research.research_name(id) if _is_extension_node(id) else _upgrade_name(Balance.upgrade_definition(id))
		tree_status.text = tr("TREE_STATUS_ONLINE") % research_name
		tooltip_content_key = ""
		_refresh()
		if _is_extension_node(id): pulse_installation_rule()
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
	if node_id != "galactic_reference_frame":
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
		if not selected_node_id.is_empty():
			_refresh_constellation_inspector(selected_node_id)
		if tree_canvas != null:
			tree_canvas.queue_redraw()


func _hide_node_tooltip(clear_hover: bool = true) -> void:
	var hover_changed := clear_hover and not hovered_node_id.is_empty()
	if clear_hover:
		hovered_node_id = ""
	if tooltip_panel != null:
		tooltip_panel.visible = _constellation_panel_active() and not selected_node_id.is_empty()
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
	data_readout.text = _data_number(floor(progression.observation_data))
	UITheme.data_tooltip(data_readout, floor(progression.observation_data))
	var visible_owned := _visible_base_owned_count() + (_extension_owned_count() if galactic_unlocked else 0)
	var visible_total := _visible_base_research_count() + (extension_definitions.size() if galactic_unlocked else 0)
	systems_readout.text = tr("TREE_PROGRESS_COUNT") % [visible_owned, visible_total]
	galactic_progress_installed.text = "%03d" % visible_owned
	galactic_progress_total.text = "%03d" % visible_total
	_layout_chart_header()
	var available_count := 0
	var affordable_count := 0
	node_states.clear()
	for definition in Balance.UPGRADE_NODES + extension_definitions:
		var node_id := String(definition.id)
		var state: String = _research_state(node_id)
		node_states[node_id] = state
		var visual_state := state
		if state == "hidden" and not _is_extension_node(node_id) and _is_teaser_visible(definition):
			visual_state = "teaser"
		var visible := visual_state != "hidden"
		var button: Button = node_buttons[node_id]
		# Revealed is the node's own state; whether it is on screen also depends
		# on where the wheel has put it. Both are stored so neither pass undoes
		# the other.
		button.set_meta("revealed", visible)
		var presentation_alpha := _node_presentation_alpha(node_id)
		button.modulate.a = presentation_alpha
		_update_star_tone(node_id)
		button.mouse_filter = Control.MOUSE_FILTER_STOP if presentation_alpha >= 0.92 and _node_interaction_ready(node_id) else Control.MOUSE_FILTER_IGNORE
		button.visible = visible and presentation_alpha > 0.01 and _is_node_above_horizon(node_id)
		button.set_meta("visual_state", visual_state)
		if not visible:
			continue
		if state == "available":
			available_count += 1
			if _can_research(node_id):
				affordable_count += 1
		var affordable: bool = state == "available" and _can_research(node_id)
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
		_research_branch_color(String(definition.branch)),
		float(star.magnitude),
		String(star.kind),
		_can_research(node_id),
		_is_branch_endpoint(definition)
	)


func _is_branch_endpoint(definition: Dictionary) -> bool:
	var node_id := String(definition.id)
	if _is_extension_node(node_id):
		return node_id in ["ext_record_complete", "ext_trace_advanced", "ext_link_advanced", "ext_sweep_advanced"]
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
	if progression == null or not node_buttons.has(node_id):
		return
	selected_node_id = node_id
	_refresh_constellation_detail_line()
	_refresh_constellation_inspector(node_id)


func _refresh_constellation_inspector(node_id: String) -> void:
	if progression == null or not node_buttons.has(node_id):
		return
	if _is_extension_node(node_id):
		_refresh_extension_inspector(node_id)
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
	var group_label_key := String(chart_constellations[group_id].label_key)
	var constellation_label := tr(group_label_key).replace("  /  ", " / ")
	tooltip_star.text = "%s    %s    %s" % [tr(String(star.name_key)), String(star.bayer), tr("TREE_CONSTELLATION_MAGNITUDE") % float(star.magnitude)]
	if visual_state == "teaser":
		tooltip_branch.text = "%s  /  %s" % [constellation_label, tr("TREE_UNRESOLVED_SIGNAL")]
		tooltip_name.text = "???"
		tooltip_description.text = tr("TREE_TEASER_DESCRIPTION")
		tooltip_state.text = tr("STATE_HIDDEN")
		tooltip_cost.text = "—"
		tooltip_cost.tooltip_text = ""
		tooltip_action.text = tr("TREE_SIGNAL_OBSCURED")
	else:
		tooltip_branch.text = constellation_label
		tooltip_name.text = _upgrade_name(definition)
		tooltip_description.text = _upgrade_description(definition)
		tooltip_state.text = tr("STATE_%s" % visual_state.to_upper())
		tooltip_cost.text = tr("TREE_CONSTELLATION_COST") % _data_number(definition.cost)
		UITheme.data_tooltip(tooltip_cost, definition.cost)
		match visual_state:
			"purchased":
				tooltip_action.text = tr("TREE_SYSTEM_ONLINE")
			"available":
				if progression.can_purchase(node_id):
					tooltip_action.text = tr("TREE_CONSTELLATION_INSTALL_ACTION")
				else:
					tooltip_action.text = tr("TREE_NEED_MORE") % [_data_number(floor(progression.observation_data)), _data_number(definition.cost)]
			_:
				var prerequisite_names: Array[String] = []
				for prerequisite_variant in definition.prerequisites:
					var prerequisite_id := String(prerequisite_variant)
					if progression.get_node_state(prerequisite_id) == "purchased":
						continue
					var prerequisite := Balance.upgrade_definition(prerequisite_id)
					prerequisite_names.append(_upgrade_name(prerequisite))
				tooltip_action.text = tr("TREE_REQUIRES") % ", ".join(prerequisite_names)
	_set_inspector_purchase_state(visual_state)
	tooltip_branch.add_theme_color_override("font_color", UITheme.TOOLTIP_LABEL)
	var state_tone := UITheme.INK_MAX if visual_state == "purchased" else (UITheme.ACCENT_PIP if visual_state == "available" and progression.can_purchase(node_id) else (UITheme.STAR_SHORT_BORDER if visual_state == "available" else UITheme.TOOLTIP_LABEL))
	tooltip_state.add_theme_color_override("font_color", state_tone)
	tooltip_action.add_theme_color_override("font_color", UITheme.TOOLTIP_ACTION if visual_state == "available" and progression.can_purchase(node_id) else UITheme.TOOLTIP_LABEL)
	tooltip_panel.visible = _constellation_panel_active()
	_layout_constellation_overlays()
	tree_canvas.queue_redraw()


func _on_language_changed(_locale: String) -> void:
	_apply_locale()


func _on_number_notation_changed(_notation: String) -> void:
	tooltip_content_key = ""
	_refresh()


func _on_binding_changed(action: StringName) -> void:
	if action == ACTION_CHART:
		_refresh_phase_context()


func _apply_locale() -> void:
	if overlay == null:
		return
	title_label.text = tr("HUD_DATA_CAPTION")
	installed_caption.text = tr("TREE_INSTALLED_CAPTION")
	north_label.text = tr("TREE_NORTH")
	_refresh_constellation_static_text()
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
	var view = preload("res://scenes/ui/upgrade_tree.tscn").instantiate()
	atlas_actions = [view.get_node("%AtlasActions0")]
	atlas_navigation = view.get_node("%AtlasNavigation")
	close_button = view.get_node("%ChartHeader").get_node("%CloseButton")
	close_underline = view.get_node("%ChartHeader").get_node("%CloseUnderline")
	completion_detail_label = view.get_node("%ChartHeader").get_node("%CompletionDetailLabel")
	constellation_bottom_action = view.get_node("%ChartHeader").get_node("%ConstellationBottomAction")
	constellation_horizon_hint = view.get_node("%ConstellationInspector").get_node("%ConstellationHorizonHint")
	constellation_installation_rule = view.get_node("%ConstellationInspector").get_node("%Divider")
	constellation_ledger = view.get_node("%ConstellationInstallLedger")
	constellation_ledger_counts = [
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerCounts0"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerCounts1"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerCounts2"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerCounts3"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerCounts4"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerCounts5"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerCounts6"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerCounts7"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerCounts8"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerCounts9"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerCounts10"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerCounts11"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerCounts12"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerCounts13"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerCounts14"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerCounts15"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerCounts16"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerCounts17"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerCounts18"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerCounts19"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerCounts20"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerCounts21"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerCounts22"),
	]
	constellation_ledger_hits = [
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits0"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits1"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits2"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits3"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits4"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits5"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits6"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits7"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits8"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits9"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits10"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits11"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits12"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits13"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits14"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits15"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits16"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits17"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits18"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits19"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits20"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits21"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits22"),
	]
	constellation_ledger_leaders = [
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerLeaders0"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerLeaders1"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerLeaders2"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerLeaders3"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerLeaders4"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerLeaders5"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerLeaders6"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerLeaders7"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerLeaders8"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerLeaders9"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerLeaders10"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerLeaders11"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerLeaders12"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerLeaders13"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerLeaders14"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerLeaders15"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerLeaders16"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerLeaders17"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerLeaders18"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerLeaders19"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerLeaders20"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerLeaders21"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerLeaders22"),
	]
	constellation_ledger_names = [
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNames0"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNames1"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNames2"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNames3"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNames4"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNames5"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNames6"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNames7"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNames8"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNames9"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNames10"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNames11"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNames12"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNames13"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNames14"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNames15"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNames16"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNames17"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNames18"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNames19"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNames20"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNames21"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNames22"),
	]
	constellation_ledger_notes = [
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNotes0"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNotes1"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNotes2"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNotes3"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNotes4"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNotes5"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNotes6"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNotes7"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNotes8"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNotes9"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNotes10"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNotes11"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNotes12"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNotes13"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNotes14"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNotes15"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNotes16"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNotes17"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNotes18"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNotes19"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNotes20"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNotes21"),
		view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerNotes22"),
	]
	content_clip = view.get_node("%TreeViewport")
	controls_label = view.get_node("%ConstellationInspector").get_node("%ControlsLabel")
	data_context_label = view.get_node("%ChartHeader").get_node("%DataContextLabel")
	data_readout = view.get_node("%ChartHeader").get_node("%DataReadout")
	galactic_progress_installed = view.get_node("%ChartHeader").get_node("%GalacticProgressInstalled")
	galactic_progress_separator = view.get_node("%ChartHeader").get_node("%GalacticProgressSeparator")
	galactic_progress_total = view.get_node("%ChartHeader").get_node("%GalacticProgressTotal")
	hub_return_button = view.get_node("%HubReturnButton")
	inspector_details = view.get_node("%ConstellationInspector").get_node("%InspectorDetails")
	inspector_details_button = view.get_node("%ConstellationInspector").get_node("%InspectorDetailsButton")
	inspector_scroll = view.get_node("%ConstellationInspector").get_node("%InspectorScroll")
	installed_caption = view.get_node("%ChartHeader").get_node("%InstalledCaption")
	north_label = view.get_node("%ChartHeader").get_node("%NorthLabel")
	overlay = view
	progress_fill = view.get_node("%ChartHeader").get_node("%ProgressFill")
	progress_track = view.get_node("%ChartHeader").get_node("%ProgressTrack")
	subtitle_label = view.get_node("%ChartHeader").get_node("%SubtitleLabel")
	systems_readout = view.get_node("%ChartHeader").get_node("%SystemsReadout")
	title_label = view.get_node("%ChartHeader").get_node("%TitleLabel")
	tooltip_action = view.get_node("%ConstellationInspector").get_node("%TooltipMeta")
	tooltip_branch = view.get_node("%ConstellationInspector").get_node("%TooltipBranch")
	tooltip_cost = view.get_node("%ConstellationInspector").get_node("%TooltipCost")
	tooltip_description = view.get_node("%ConstellationInspector").get_node("%TooltipDescription")
	tooltip_meta = view.get_node("%ConstellationInspector").get_node("%TooltipMeta")
	tooltip_name = view.get_node("%ConstellationInspector").get_node("%TooltipName")
	tooltip_panel = view.get_node("%ConstellationInspector")
	tooltip_star = view.get_node("%ConstellationInspector").get_node("%TooltipStar")
	tooltip_state = view.get_node("%ConstellationInspector").get_node("%TooltipState")
	tree_canvas = view.get_node("%TreeCanvas")
	tree_status = view.get_node("%ChartHeader").get_node("%TreeStatus")
	add_child(view)
	view.get_node("%TreeViewport").resized.connect(_on_content_resized)
	view.get_node("%TreeViewport").gui_input.connect(_on_tree_viewport_gui_input)
	view.get_node("%TreeCanvas").draw.connect(_draw_tree)
	view.get_node("%ChartHeader").resized.connect(_layout_chart_header)
	view.get_node("%ChartHeader").get_node("%CloseButton").pressed.connect(close_tree)
	view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits0").pressed.connect(focus_constellation.bind("cassiopeia"))
	view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits1").pressed.connect(focus_constellation.bind("big_dipper"))
	view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits2").pressed.connect(focus_constellation.bind("orion"))
	view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits3").pressed.connect(focus_constellation.bind("andromeda"))
	view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits4").pressed.connect(focus_constellation.bind("perseus"))
	view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits5").pressed.connect(focus_constellation.bind("lyra"))
	view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits6").pressed.connect(focus_constellation.bind("gemini"))
	view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits7").pressed.connect(focus_constellation.bind("taurus"))
	view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits8").pressed.connect(focus_constellation.bind("leo"))
	view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits9").pressed.connect(focus_constellation.bind("ursa_minor"))
	view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits10").pressed.connect(focus_constellation.bind("canis_major"))
	view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits11").pressed.connect(focus_constellation.bind("draco"))
	view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits12").pressed.connect(focus_constellation.bind("pegasus"))
	view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits13").pressed.connect(focus_constellation.bind("lacerta"))
	view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits14").pressed.connect(focus_constellation.bind("cygnus"))
	view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits15").pressed.connect(focus_constellation.bind("aquila"))
	view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits16").pressed.connect(focus_constellation.bind("vulpecula"))
	view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits17").pressed.connect(focus_constellation.bind("delphinus"))
	view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits18").pressed.connect(focus_constellation.bind("sagitta"))
	view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits19").pressed.connect(focus_constellation.bind("equuleus"))
	view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits20").pressed.connect(focus_constellation.bind("triangulum"))
	view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits21").pressed.connect(focus_constellation.bind("cancer"))
	view.get_node("%ConstellationInstallLedger").get_node("%ConstellationLedgerHits22").pressed.connect(focus_constellation.bind("sagittarius"))
	view.get_node("%ConstellationInspector").get_node("%InspectorDetailsButton").toggled.connect(_set_inspector_details)
	view.get_node("%HubReturnButton").pressed.connect(_frame_galaxy)
	view.get_node("%AtlasActions0").pressed.connect(_atlas_action.bind(0))
	for definition in Balance.UPGRADE_NODES + extension_definitions:
		_build_node_button(definition)
	_layout_chart_header()
	_layout_chart()


func _build_node_button(definition: Dictionary) -> void:
	var node_id := String(definition.id)
	var button: Button = preload("res://scenes/ui/research_star.tscn").instantiate()
	button.chart = self
	button.node_id = node_id
	button.name = "Node_" + node_id
	button.set_meta("node_id", node_id)
	button.set_meta("visual_state", "hidden")
	button.button_down.connect(_on_node_hold_started.bind(node_id))
	button.button_up.connect(_on_node_hold_released.bind(node_id))
	button.mouse_entered.connect(_on_node_hovered.bind(node_id))
	button.mouse_exited.connect(_on_node_unhovered.bind(node_id))
	tree_canvas.add_child(button)

	var star_visual = button.get_node("StarVisual")
	var branch_color: Color = _research_branch_color(String(definition.branch))
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
	node_buttons[node_id] = button
	node_hold_bars[node_id] = star_visual


func _star_hit_owner(screen_position: Vector2) -> String:
	var nearest := ""
	var nearest_distance := INF
	var candidates: Array[String] = []
	for id: String in node_buttons:
		var button: Button = node_buttons[id]
		if not button.is_visible_in_tree() or button.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			continue
		if not button.get_global_rect().has_point(screen_position):
			continue
		candidates.append(id)
		var distance := button.get_global_rect().get_center().distance_squared_to(screen_position)
		if distance < nearest_distance:
			nearest = id
			nearest_distance = distance
	if nearest.is_empty(): return ""
	if held_node_id in candidates: return held_node_id
	var center: Vector2 = node_buttons[nearest].get_global_rect().get_center()
	var available := ""
	var available_distance := INF
	for id in candidates:
		var candidate_center: Vector2 = node_buttons[id].get_global_rect().get_center()
		if candidate_center.distance_to(center) > 6.0 or _research_state(id) != "available":
			continue
		var distance := candidate_center.distance_squared_to(screen_position)
		if distance < available_distance:
			available = id
			available_distance = distance
	return available if not available.is_empty() else nearest


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
			if _cached_node_state(source_id) == "purchased" and _is_figure_connection(source_id, target_id):
				frontier_connections_cache.append(PackedStringArray([source_id, target_id]))


func _is_figure_connection(source_id: String, target_id: String) -> bool:
	# Research prerequisites remain save-compatible. They must not introduce
	# fictitious diagonals into a corrected astronomical figure (Ursa Minor).
	if not node_star_records.has(source_id) or not node_star_records.has(target_id): return false
	var source: Dictionary = node_star_records[source_id]
	var target: Dictionary = node_star_records[target_id]
	if source.constellation_id != target.constellation_id: return false
	for segment in chart_constellations[source.constellation_id].segments:
		if (segment[0] == source.star.id and segment[1] == target.star.id) or (segment[1] == source.star.id and segment[0] == target.star.id): return true
	return false


func _frontier_connections() -> Array[PackedStringArray]:
	return frontier_connections_cache


func _cached_node_state(node_id: String) -> String:
	if node_states.has(node_id):
		return String(node_states[node_id])
	return String(progression.get_node_state(node_id)) if progression != null else ""


func _draw_tree() -> void:
	# Control refreshes its culling rectangle on layout. Our drawing extends
	# outside that rectangle, so restore the whole-sky bounds with each redraw.
	var sky_extent := BACKGROUND_STAR_MAX_RADIUS + 256.0
	RenderingServer.canvas_item_set_custom_rect(tree_canvas.get_canvas_item(), true, Rect2(CHART_ORIGIN - Vector2.ONE * sky_extent, Vector2.ONE * sky_extent * 2.0))
	_draw_chart_background()
	var structure_alpha := _galactic_structure_alpha()
	for constellation_id in chart_constellations:
		if constellation_id in ExtensionChart.ORDER and not galactic_unlocked:
			continue
		var constellation: Dictionary = chart_constellations[constellation_id]
		var figure_alpha := structure_alpha * _completed_figure_tone(constellation_id)
		for segment_variant in constellation.segments:
			var segment: Array = segment_variant
			var start := Vector2(star_positions["%s/%s" % [constellation_id, String(segment[0])]])
			var finish := Vector2(star_positions["%s/%s" % [constellation_id, String(segment[1])]])
			var states := _segment_states(constellation_id, segment)
			var segment_color := _segment_color(states)
			segment_color.a *= figure_alpha
			tree_canvas.draw_line(start, finish, segment_color, _segment_width(states), true)
		for star_variant in constellation.stars:
			var star: Dictionary = star_variant
			var point := Vector2(star_positions["%s/%s" % [constellation_id, String(star.id)]])
			var star_radius := _magnitude_radius(float(star.magnitude))
			var node_id := String(star.get("node_id", ""))
			var alpha := (0.23 if node_id.is_empty() else 0.12) * figure_alpha
			if node_id.is_empty():
				match String(star.kind):
					"cluster":
						_draw_background_cluster(point, star_radius, alpha)
					"galaxy":
						_draw_background_galaxy(point, star_radius, alpha)
			tree_canvas.draw_circle(point, maxf(1.2, star_radius * 0.55), Color(UITheme.STAR_BACKGROUND, alpha))
	if progression != null and (structure_alpha > 0.01):
		_draw_frontier_overlay()
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


func _draw_frontier_overlay() -> void:
	# Only the current purchasable frontier stays lit. Purchased history is
	# already encoded by stable bright stars, so late-game DAG clutter never grows.
	for frontier_variant in _frontier_connections():
		var frontier: PackedStringArray = frontier_variant
		var source_id := String(frontier[0])
		var target_id := String(frontier[1])
		var presentation_alpha := maxf(_node_presentation_alpha(source_id), _node_presentation_alpha(target_id))
		var connection := _connection_points(source_id, target_id)
		var start := connection[0]
		var finish := connection[1]
		var line_width := 1.5
		tree_canvas.draw_line(start, finish, Color(UITheme.LINE_FRONTIER, 0.60 * presentation_alpha), line_width, true)
	if not hovered_node_id.is_empty() and node_positions.has(hovered_node_id):
		var hovered_state := _cached_node_state(hovered_node_id)
		if hovered_state == "locked" or hovered_state == "hidden":
			var hovered_definition := Balance.upgrade_definition(hovered_node_id)
			for prerequisite_variant in hovered_definition.prerequisites:
				var source_id := String(prerequisite_variant)
				if not _is_figure_connection(source_id, hovered_node_id): continue
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
		elif constellation_id in ExtensionChart.ORDER:
			states[index] = "purchased" if _constellation_complete(constellation_id) else "locked"
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


func bind_extension(research: Node) -> void:
	extension_research = research
	if not research.changed.is_connected(_on_progression_state_changed):
		research.changed.connect(_on_progression_state_changed)
	_refresh()

func _constellation_order() -> Array:
	return GALACTIC_LEDGER_ORDER + ExtensionChart.ORDER

func _is_extension_node(id: String) -> bool:
	return node_star_records.has(id) and String(node_star_records[id].constellation_id) in ExtensionChart.ORDER

func _research_branch_color(id: String) -> Color:
	return ExtensionChart.COLORS[id] if ExtensionChart.COLORS.has(id) else Balance.BRANCHES[id].color

func _research_state(id: String) -> String:
	if not _is_extension_node(id): return progression.get_node_state(id)
	if not galactic_unlocked or extension_research == null: return "hidden"
	if extension_research.research_owned(id): return "purchased"
	return "available" if extension_research.research_ready(id) else "locked"

func _can_research(id: String) -> bool:
	if _is_extension_node(id):
		return extension_research != null and galactic_unlocked and extension_research.can_purchase(id) and not extension_research.research_owned(id)
	return progression.can_purchase(id)

func _extension_owned_count() -> int:
	var count := 0
	if extension_research != null:
		for definition in extension_definitions:
			if extension_research.research_owned(definition.id): count += 1
	return count

func _constellation_complete(id: String) -> bool:
	for star in chart_constellations[id].stars:
		if not String(star.node_id).is_empty() and _research_state(star.node_id) != "purchased": return false
	return true

func _atlas_action(_index: int) -> void:
	focus_outer_constellations()

func focus_outer_constellations() -> void:
	if not galactic_unlocked: return
	_cancel_node_hold()
	if not _is_extension_node(selected_node_id):
		selected_node_id = "ext_protocol"
		for id in ["ext_trace_study", "ext_sweep_study", "ext_link_study"]:
			if _research_state(id) == "available":
				selected_node_id = id
				break
	expanded_view_initialized = true
	rotation_offset = 2.1
	zoom = 0.43
	galactic_chart_detail = 1.0
	pan_position = _galactic_pan_for_zoom(zoom)
	_layout_chart()
	_apply_transform()
	_update_galactic_presentation()

func focus_constellation(id: String) -> void:
	if not chart_placements.has(id): return
	if id in ExtensionChart.ORDER and not galactic_unlocked: return
	_cancel_node_hold()
	# Shared-corner figures can be translated from their nominal UI anchor.
	# Focus the actual stars, including the complete attached Pegasus figure.
	var center := Vector2.ZERO
	var positions := _readable_chart_positions()
	for star in chart_constellations[id].stars:
		center += positions[id + "/" + star.id] - CHART_ORIGIN
	center /= float(chart_constellations[id].stars.size())
	rotation_offset = -PI * 0.5 - center.angle()
	zoom = clampf(330.0 / maxf(1.0, center.length()), _galactic_zoom_floor(), CONSTELLATION_ZOOM)
	pan_position = _galactic_pan_for_zoom(zoom)
	if galactic_unlocked and id in ChartData.CONSTELLATIONS:
		var rotated_center := CHART_ORIGIN + center.rotated(rotation_offset)
		var bounds := Rect2(rotated_center, Vector2.ZERO)
		for star in chart_constellations[id].stars:
			var point := CHART_ORIGIN + (Vector2(positions[id + "/" + star.id]) - CHART_ORIGIN).rotated(rotation_offset)
			bounds = bounds.expand(point)
		zoom = minf(MAX_ZOOM, minf(500.0 / maxf(1.0, bounds.size.x), 290.0 / maxf(1.0, bounds.size.y)))
		pan_position = Vector2(560, 330) - bounds.get_center() * zoom
	galactic_chart_detail = 1.0
	for star in chart_constellations[id].stars:
		if not String(star.node_id).is_empty():
			selected_node_id = star.node_id
			if _research_state(star.node_id) == "available": break
	tooltip_content_key = ""
	_layout_chart()
	_apply_transform()
	_refresh()

func select_extension(id: String) -> void:
	if id == "modules": id = "ext_protocol"
	_show_completed_constellations()
	if not node_star_records.has(id): return
	focus_constellation(node_star_records[id].constellation_id)
	selected_node_id = id
	tooltip_content_key = ""
	_refresh_constellation_inspector(id)

func _refresh_extension_inspector(id: String) -> void:
	if extension_research == null: return
	if installation_rule == constellation_installation_rule and installation_node_id != id:
		_cancel_installation_rule()
	var record: Dictionary = node_star_records[id]
	var star: Dictionary = record.star
	var state := _research_state(id)
	tooltip_branch.text = tr(chart_constellations[record.constellation_id].label_key) + " · " + tr("ATLAS_ROLE_" + String(record.constellation_id).to_upper())
	tooltip_star.text = "%s    %s" % [tr(star.name_key), star.bayer]
	tooltip_name.text = extension_research.research_name(id)
	tooltip_description.text = extension_research.research_description(id)
	tooltip_state.text = tr("STATE_" + state.to_upper())
	var cost: float = extension_research.research_cost(id)
	tooltip_cost.text = tr("CHX_FREE") if is_zero_approx(cost) else tr("TREE_CONSTELLATION_COST") % _data_number(cost)
	UITheme.data_tooltip(tooltip_cost, cost)
	if state == "purchased": tooltip_action.text = tr("TREE_SYSTEM_ONLINE")
	elif _can_research(id): tooltip_action.text = tr("TREE_CONSTELLATION_INSTALL_ACTION")
	elif not extension_research.modules_unlocked(): tooltip_action.text = tr("ATLAS_COORDINATE_REQUIRED")
	elif state == "available": tooltip_action.text = tr("TREE_NEED_MORE") % [_data_number(floor(progression.observation_data)), _data_number(cost)]
	else: tooltip_action.text = extension_research.prerequisite_text(id)
	_set_inspector_purchase_state(state)
	tooltip_state.add_theme_color_override("font_color", UITheme.ACCENT_PIP if _can_research(id) else UITheme.INK_MID)
	tooltip_action.add_theme_color_override("font_color", UITheme.TOOLTIP_ACTION)
	tooltip_panel.visible = _constellation_panel_active()
	_layout_constellation_overlays()
