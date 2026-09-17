extends CanvasLayer

signal phase_summary_continue_requested
signal save_slot_requested(slot: int)
signal load_slot_requested(slot: int)
signal startup_slot_selected(slot: int)
signal new_game_slot_requested(slot: int)
signal reset_slot_requested(slot: int)
signal tutorial_replay_requested

const Balance = preload("res://scripts/game_balance.gd")
const UITheme = preload("res://scripts/ui_theme.gd")
const ExtensionData = preload("res://scripts/expansion_data.gd")
const OBSERVATION_CLOCK_WIDTH := 140.0
const SETTINGS_PAGE_ORDER := ["general", "audio", "display", "accessibility", "controls", "save"]
const SETTINGS_PAGE_TAB_KEYS := {
	"general": "SETTINGS_TAB_GENERAL",
	"audio": "SETTINGS_TAB_AUDIO",
	"display": "SETTINGS_TAB_DISPLAY",
	"accessibility": "SETTINGS_TAB_ACCESSIBILITY",
	"controls": "SETTINGS_TAB_CONTROLS",
	"save": "SETTINGS_TAB_SAVE",
}


const TrackingCluster = preload("res://scripts/ui/tracking_cluster.gd")

var progression: Node
var settings_controller: Node
var save_game_controller: Node
var deep_sky: Node
var root_control: Control
var data_caption_label: Label
var data_label: Label
var data_gain_label: Label
var time_label: Label
var save_mode_label: Label
var tutorial_label: Label
var banner_root: Control
var banner_rule: ColorRect
var banner_label: Label
var banner_subtitle: Label
var tracking_cluster: TrackingCluster
var tracking_percent: Label
var tracking_target: Label
var tracking_quality: Label
var tracking_multiplier: Label
var tracking_divider: ColorRect
var phase_round_label: Label
var phase_window_track: ColorRect
var phase_window_fill: ColorRect
var ready_notice: Control
var ready_pip: ColorRect
var ready_label: Label
var debug_panel: PanelContainer
var debug_label: Label
var guided_tutorial_active := false
var external_readouts_covered := false
var discovery_banners: Dictionary = {}
var summary_details: VBoxContainer
var summary_details_button: Button
var summary_lead: Label
var summary_highlight: Label
var phase_summary_overlay: Control
var phase_summary_reveal: Tween
var in_round_visibility: Dictionary = {}
var phase_summary_title: Label
var phase_summary_subtitle: Label
var phase_summary_observations: Label
var phase_summary_data: Label
var phase_summary_split: Label
var phase_summary_comparison: Label
var phase_summary_badges: Label
var phase_summary_button: Button
var extension_readout: Control
var extension_objective_label: Label
var extension_samples_label: Label
var extension_should_show: bool = false
var settings_button: Button
var settings_overlay: Control
var settings_panel: Control
var settings_title: Label
var settings_subtitle: Label
var settings_page_stack: Control
var settings_nav_buttons: Dictionary = {}
var settings_pages: Dictionary = {}
var settings_page_labels: Array[Dictionary] = []
var settings_page_focus_memory: Dictionary = {}
var settings_active_page: String = "general"
var settings_page_before_controls: String = "general"
var settings_language_label: Label
var settings_hint: Label
var language_selector: OptionButton
var number_notation_selector: OptionButton
var tutorial_replay_button: Button
var final_observation_active := false
var settings_close_button: Button
var audio_display_button: Button
var audio_display_container: VBoxContainer
var master_volume_label: Label
var master_volume_slider: HSlider
var master_volume_value: Label
var mute_button: Button
var mute_unfocused_button: Button
var fullscreen_button: Button
var vsync_button: Button
var fps_limit_selector: OptionButton
var performance_monitor: PanelContainer
var performance_monitor_button: Button
var motion_intensity_label: Label
var motion_intensity_slider: HSlider
var motion_intensity_value: Label
var screen_flashes_button: Button
var controls_button: Button
var save_management_button: Button
var save_management_container: VBoxContainer
var controls_overlay: Control
var controls_panel: Control
var controls_title: Label
var controls_subtitle: Label
var controls_hint: Label
var controls_status: Label
var controls_back_button: Button
var controls_reset_button: Button
var controls_action_widgets: Dictionary = {}
var controls_clear_widgets: Dictionary = {}
var controls_localized_text: Array[Dictionary] = []
var reset_bindings_dialog: ConfirmationDialog
var startup_overlay: Control
var startup_title: Label
var startup_subtitle: Label
var startup_hint: Label
var startup_slot_titles: Array[Label] = []
var startup_slot_details: Array[Label] = []
var startup_slot_buttons: Array[Button] = []
var startup_reset_buttons: Array[Button] = []
var save_section_label: Label
var save_status_label: Label
var save_feedback: Label
var save_slot_titles: Array[Label] = []
var save_slot_details: Array[Label] = []
var save_slot_buttons: Array[Button] = []
var load_slot_buttons: Array[Button] = []
var reset_slot_buttons: Array[Button] = []
var overwrite_dialog: ConfirmationDialog
var reset_dialog: ConfirmationDialog
var pending_overwrite_slot: int = 0
var pending_reset_slot: int = 0
var banner_timer: float = 0.0
var tutorial_complete: bool = false
var last_runtime_second: int = -1
var runtime_seconds: float = 0.0
var phase_display_configured: bool = false
var observation_phase_active: bool = false
var observation_phase_round: int = 1
var observation_phase_second: int = 30
var phase_window_seconds: int = 30
var last_tracking_text: String = ""
var last_tracking_progress_percent: int = -1
var last_tracking_target_type: String = ""
var last_tracking_quality_key: String = ""
var last_tracking_multiplier_hundredths: int = -1
var last_tracking_target_count: int = -1
var tracking_percent_height: float = 0.0
var tracking_target_height: float = 0.0
var tracking_quality_size := Vector2.ZERO
var tracking_multiplier_size := Vector2.ZERO
var tracking_metrics_dirty: bool = true
var tracking_layout_passes: int = 0
var last_phase_window_width: float = -1.0
var last_ready_count: int = -1
var last_observation_data: float = -1.0
var last_data_gain: float = 0.0
var phase_number_result: Dictionary = {}
var data_gain_tween: Tween
var data_pulse_tween: Tween
var ready_pulse_tween: Tween
var installation_tween: Tween
var paused_by_settings: bool = false
var paused_by_startup: bool = false
var active_save_slot: int = 0
var autosave_status_timer: float = 0.0
var last_autosave_unix: int = 0
var autosave_failed: bool = false
var save_management_expanded: bool = false
var audio_display_expanded: bool = false
var syncing_settings_controls: bool = false
var settings_previous_focus: Control
var controls_previous_focus: Control
var rebind_action: StringName = &""
var rebind_release_keycode: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_interface()
	set_process(true)


func bind_progression(controller: Node) -> void:
	progression = controller
	progression.state_changed.connect(_refresh_progression)
	last_observation_data = float(progression.observation_data)
	_refresh_progression()


func bind_settings(controller: Node) -> void:
	settings_controller = controller
	settings_controller.performance_monitor_changed.connect(func(_enabled: bool): _sync_settings_controls())
	if not settings_controller.language_changed.is_connected(_on_language_changed):
		settings_controller.language_changed.connect(_on_language_changed)
	if not settings_controller.number_notation_changed.is_connected(_on_number_notation_changed):
		settings_controller.number_notation_changed.connect(_on_number_notation_changed)
	if settings_controller.has_signal("audio_changed") and not settings_controller.audio_changed.is_connected(_on_audio_changed):
		settings_controller.audio_changed.connect(_on_audio_changed)
	if settings_controller.has_signal("audio_policy_changed") and not settings_controller.audio_policy_changed.is_connected(_on_settings_policy_changed):
		settings_controller.audio_policy_changed.connect(_on_settings_policy_changed)
	if settings_controller.has_signal("fullscreen_changed") and not settings_controller.fullscreen_changed.is_connected(_on_fullscreen_changed):
		settings_controller.fullscreen_changed.connect(_on_fullscreen_changed)
	if settings_controller.has_signal("performance_changed") and not settings_controller.performance_changed.is_connected(_on_performance_changed):
		settings_controller.performance_changed.connect(_on_performance_changed)
	if settings_controller.has_signal("accessibility_changed") and not settings_controller.accessibility_changed.is_connected(_on_accessibility_changed):
		settings_controller.accessibility_changed.connect(_on_accessibility_changed)
	if settings_controller.has_signal("input_bindings_changed") and not settings_controller.input_bindings_changed.is_connected(_on_input_bindings_changed):
		settings_controller.input_bindings_changed.connect(_on_input_bindings_changed)
	_sync_language_selector()
	_sync_settings_controls()
	_apply_locale()


func bind_save_games(controller: Node) -> void:
	save_game_controller = controller
	if not save_game_controller.slots_changed.is_connected(_refresh_save_slot_views):
		save_game_controller.slots_changed.connect(_refresh_save_slot_views)
	_refresh_save_slot_views()


func _process(delta: float) -> void:
	if banner_timer > 0.0:
		banner_timer -= delta
		var fade := clampf(banner_timer / 0.3, 0.0, 1.0)
		banner_root.modulate.a = fade
		if banner_timer <= 0.0:
			banner_root.visible = false
	if autosave_status_timer > 0.0:
		autosave_status_timer -= delta
		if autosave_status_timer <= 0.0:
			_refresh_save_mode_label(false)


func set_runtime(seconds: float) -> void:
	runtime_seconds = maxf(0.0, seconds)
	var whole_seconds := int(seconds)
	if whole_seconds == last_runtime_second:
		return
	last_runtime_second = whole_seconds
	if phase_display_configured:
		return
	var minutes := whole_seconds / 60
	var remaining := whole_seconds % 60
	time_label.text = tr("HUD_TIME") % [minutes, remaining]


func set_observation_phase(round_number: int, seconds_remaining: float, phase_duration: float = 0.0) -> void:
	var entering_observation := not phase_display_configured or not observation_phase_active
	if phase_duration > 0.0:
		phase_window_seconds = maxi(1, ceili(phase_duration))
	var whole_seconds := maxi(0, ceili(seconds_remaining))
	var phase_changed := (
		not phase_display_configured
		or not observation_phase_active
		or observation_phase_round != round_number
		or observation_phase_second != whole_seconds
	)
	phase_display_configured = true
	observation_phase_active = true
	observation_phase_round = maxi(1, round_number)
	observation_phase_second = whole_seconds
	set_phase_window(float(whole_seconds) / maxf(1.0, float(phase_window_seconds)))
	if phase_changed:
		_refresh_phase_time_label()
	# Research/load and locale changes already refresh this through their signals.
	# The remaining phase dependency changes only when observation starts/stops.
	if entering_observation:
		_refresh_extension()


func set_upgrade_phase(completed_round: int) -> void:
	phase_display_configured = true
	observation_phase_active = false
	observation_phase_round = maxi(1, completed_round)
	observation_phase_second = 0
	_refresh_phase_time_label()
	_refresh_extension()
	if progression != null:
		_refresh_progression()


func _refresh_phase_time_label() -> void:
	if time_label == null:
		return
	if not phase_display_configured:
		var whole_seconds := int(runtime_seconds)
		phase_round_label.text = ""
		time_label.text = tr("HUD_PHASE_CLOCK") % [whole_seconds / 60, whole_seconds % 60]
		_layout_phase_clock()
		return
	phase_round_label.text = tr("HUD_PHASE_ROUND") % observation_phase_round
	if observation_phase_active:
		time_label.text = tr("HUD_PHASE_CLOCK") % [
			observation_phase_second / 60,
			observation_phase_second % 60,
		]
	else:
		time_label.text = tr("HUD_UPGRADE_PHASE") % observation_phase_round
	_layout_phase_clock()


func show_discovery_banner(key: String, text: String, color: Color, duration: float) -> void:
	if discovery_banners.has(key):
		return
	discovery_banners[key] = true
	# Never replace an active discovery, warning or save failure with routine success.
	if banner_root.visible:
		return
	show_banner(text, color, duration)


func set_guided_tutorial_active(active: bool) -> void:
	guided_tutorial_active = active
	_set_tutorial_hint_visible(not tutorial_complete)


func _set_tutorial_hint_visible(show_hint: bool) -> void:
	var wanted := show_hint and not guided_tutorial_active
	if in_round_visibility.has("FirstObservationHint"):
		in_round_visibility["FirstObservationHint"] = wanted
	tutorial_label.visible = wanted and not _in_round_readouts_covered()


func set_external_readouts_covered(covered: bool) -> void:
	external_readouts_covered = covered
	_refresh_in_round_readouts()


func show_banner(text: String, color: Color = Color.WHITE, duration: float = 2.5) -> void:
	# A different announcement must not inherit a partially installed rule.
	if installation_tween != null and installation_tween.is_valid():
		installation_tween.kill()
	banner_rule.scale = Vector2.ONE
	# Callers still pass one string; a bullet separator splits title from subtitle.
	var title := text
	var subtitle := ""
	for separator in ["  •  ", " • ", "•"]:
		if separator in text:
			var parts := text.split(separator, false, 1)
			title = parts[0].strip_edges()
			subtitle = parts[1].strip_edges() if parts.size() > 1 else ""
			break
	banner_label.text = title
	banner_label.add_theme_color_override("font_color", color if color != Color.WHITE else UITheme.BANNER_TITLE)
	banner_subtitle.text = subtitle
	banner_subtitle.visible = not subtitle.is_empty()
	banner_root.modulate.a = 1.0
	banner_root.visible = true
	banner_timer = duration
	_layout_banner()


func pulse_installation_rule() -> void:
	# Local instrument activation: extend the existing one-pixel rule, without
	# moving the sky, flashing the viewport, or adding another meteor ring.
	if installation_tween != null and installation_tween.is_valid():
		installation_tween.kill()
	banner_rule.pivot_offset = Vector2(banner_rule.size.x * 0.5, 0.0)
	banner_rule.scale = Vector2(0.2, 1.0)
	installation_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	installation_tween.tween_property(banner_rule, "scale:x", 1.0, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _layout_banner() -> void:
	if banner_root == null:
		return
	var width := UITheme.px(240.0)
	banner_rule.position = Vector2(-width * 0.5, UITheme.px(76.0))
	banner_rule.size = Vector2(width, 1.0)
	var text_width := UITheme.px(900.0)
	for label in [banner_label, banner_subtitle]:
		label.size.x = text_width
		label.position.x = -text_width * 0.5
	banner_label.position.y = banner_rule.position.y + UITheme.px(20.0)
	var title_height := banner_label.get_combined_minimum_size().y
	banner_subtitle.position.y = banner_label.position.y + title_height + UITheme.px(14.0)


func set_tracking(
	progress: float,
	target_type: String,
	multiplier: float,
	target_count: int = 1,
	cursor_position: Vector2 = Vector2.ZERO,
	ring_radius: float = -1.0,
	aim_quality: float = 0.0
) -> void:
	if not tracking_cluster.visible:
		tracking_cluster.visible = true
	var cursor_changed := not tracking_cluster.cursor.is_equal_approx(cursor_position)
	tracking_cluster.cursor = cursor_position
	# The ring now belongs to the software cursor and grows with Better Lens, so
	# the text block clears whatever radius the cursor is currently drawing.
	if ring_radius >= 0.0 and not is_equal_approx(tracking_cluster.ring_radius, ring_radius):
		tracking_cluster.ring_radius = ring_radius
		cursor_changed = true
	var progress_percent := int(progress * 100.0)
	var multiplier_hundredths := int(round(multiplier * 100.0))
	if progress_percent != last_tracking_progress_percent:
		last_tracking_progress_percent = progress_percent
		tracking_percent.text = "%d%%" % progress_percent
	if target_type != last_tracking_target_type:
		last_tracking_target_type = target_type
		tracking_target.text = tr("METEOR_%s" % target_type.to_upper())
		last_tracking_text = tracking_target.text
		tracking_metrics_dirty = true
	var quality_key := _tracking_aim_key(aim_quality)
	if quality_key != last_tracking_quality_key:
		last_tracking_quality_key = quality_key
		tracking_quality.text = tr(quality_key)
		tracking_metrics_dirty = true
	if multiplier_hundredths != last_tracking_multiplier_hundredths:
		last_tracking_multiplier_hundredths = multiplier_hundredths
		var previous_multiplier_length := tracking_multiplier.text.length()
		# A multiplier of x1.01 or less is noise, not a reward.
		tracking_multiplier.text = (
			tr("HUD_TRACK_MULTIPLIER") % (float(multiplier_hundredths) / 100.0)
			if multiplier_hundredths > 101
			else ""
		)
		if previous_multiplier_length != tracking_multiplier.text.length():
			tracking_metrics_dirty = true
	last_tracking_target_count = target_count
	if cursor_changed or tracking_metrics_dirty:
		_layout_tracking_cluster()


func _tracking_aim_key(quality: float) -> String:
	# Live alignment is independent of completion and the accumulated final grade.
	if quality >= 0.8:
		return "HUD_AIM_CENTER"
	if quality >= 0.4:
		return "HUD_AIM_INNER"
	if quality > 0.0:
		return "HUD_AIM_EDGE"
	return "HUD_AIM_LOST"


func hide_tracking() -> void:
	if tracking_cluster != null and tracking_cluster.visible:
		tracking_cluster.visible = false
		_invalidate_tracking_cache()


func _invalidate_tracking_cache() -> void:
	last_tracking_text = ""
	last_tracking_progress_percent = -1
	last_tracking_target_type = ""
	last_tracking_quality_key = ""
	last_tracking_multiplier_hundredths = -1
	last_tracking_target_count = -1
	tracking_metrics_dirty = true


func mark_first_success() -> void:
	if tutorial_complete:
		return
	tutorial_complete = true
	_set_tutorial_hint_visible(true)
	tutorial_label.text = tr("HUD_TUTORIAL_DONE") % _chart_binding_label()
	var timer := get_tree().create_timer(4.0)
	timer.timeout.connect(func():
		if is_instance_valid(tutorial_label):
			_set_tutorial_hint_visible(false)
	)


func reset_tutorial() -> void:
	discovery_banners.clear()
	tutorial_complete = false
	tutorial_label.text = tr("HUD_TUTORIAL_START")
	_set_tutorial_hint_visible(true)


func restore_tutorial(already_observed: bool) -> void:
	tutorial_complete = already_observed
	tutorial_label.text = tr("HUD_TUTORIAL_DONE") % _chart_binding_label() if already_observed else tr("HUD_TUTORIAL_START")
	_set_tutorial_hint_visible(not already_observed)


func toggle_debug() -> void:
	debug_panel.visible = not debug_panel.visible


func is_debug_visible() -> bool:
	return debug_panel.visible


func is_pointer_over_hud(pointer_position: Vector2) -> bool:
	for surface in [
		debug_panel, settings_button, banner_root, tutorial_label,
	]:
		if surface is Control and surface.is_visible_in_tree() and surface.get_global_rect().has_point(pointer_position):
			return true
	return false


const IN_ROUND_GROUPS := ["DataReadout", "PhaseClock", "ExtensionReadout", "ReadySystems", "TrackingCluster", "EventBanner", "FirstObservationHint"]


func _refresh_in_round_readouts() -> void:
	# Any of the three overlays owns the screen while it is up, and none of them
	# has a panel to hide the live readouts behind any more.
	var covered := _in_round_readouts_covered()
	if covered:
		_stash_in_round_readouts()
	else:
		_restore_in_round_readouts()
		if extension_readout != null:
			extension_readout.visible = extension_should_show


func _in_round_readouts_covered() -> bool:
	return (
		external_readouts_covered
		or is_phase_summary_open()
		or (settings_overlay != null and settings_overlay.visible)
		or is_controls_open()
		or (startup_overlay != null and startup_overlay.visible)
	)


func _stash_in_round_readouts() -> void:
	# Idempotent: overlays can stack, and a second stash would record the state
	# the first one already hid.
	if not in_round_visibility.is_empty():
		return
	for group_name in IN_ROUND_GROUPS:
		var group: Control = root_control.get_node_or_null(NodePath(group_name))
		if group == null:
			continue
		# Their own state is recorded rather than assumed: the tracking cluster
		# and the banner are already hidden most of the time, and restoring them
		# to visible would put stale readouts back on screen.
		in_round_visibility[group_name] = group.visible
		group.visible = false


func _restore_in_round_readouts() -> void:
	for group_name_variant in in_round_visibility:
		var group: Control = root_control.get_node_or_null(NodePath(String(group_name_variant)))
		if group != null:
			group.visible = bool(in_round_visibility[group_name_variant])
	in_round_visibility.clear()
	if extension_readout != null:
		extension_readout.visible = extension_should_show


func show_phase_summary(
	result: Dictionary,
	previous_result: Dictionary,
	comparison_state: String,
	new_best: bool,
	reveal_delay: float = 0.0
) -> void:
	_reset_phase_summary_reveal()
	_set_summary_details(false)
	summary_details_button.set_pressed_no_signal(false)
	summary_highlight.text = tr("PHASE_SUMMARY_BADGE_BEST") if new_best else ""
	summary_highlight.visible = new_best
	var round_number := maxi(1, int(result.get("round", 1)))
	var data_earned := maxi(0, int(result.get("data", 0)))
	var duration_seconds := maxi(1, int(round(float(result.get("duration", 20.0)))))
	var round_rate := maxf(0.0, float(result.get("rate", 0.0)))
	var observations := maxi(0, int(result.get("observations", 0)))
	var manual_observations := maxi(0, int(result.get("manual", 0)))
	var automatic_observations := maxi(0, int(result.get("automatic", 0)))
	phase_summary_title.text = tr("PHASE_SUMMARY_TITLE") % round_number
	phase_summary_subtitle.text = tr("PHASE_SUMMARY_SUBTITLE") % duration_seconds
	phase_number_result = {"data": data_earned, "rate": round_rate, "previous": previous_result.duplicate(true), "comparison": comparison_state}
	_refresh_phase_number_text()
	summary_details_button.text = tr("UI_DETAILS_HIDE" if summary_details_button.button_pressed else "PHASE_DETAILS_SHOW")
	phase_summary_observations.text = tr("PHASE_SUMMARY_OBSERVATIONS") % observations
	phase_summary_split.text = tr("PHASE_SUMMARY_MANUAL_AUTO") % [manual_observations, automatic_observations]
	var badge_texts: Array[String] = []
	var systems_since_baseline = result.get("systems_since_baseline", [])
	if systems_since_baseline is Array and not systems_since_baseline.is_empty():
		var system_names: PackedStringArray = []
		for system_variant in systems_since_baseline:
			var node_id := String(system_variant)
			if not Balance.upgrade_definition(node_id).is_empty():
				system_names.append(tr("UPGRADE_%s_NAME" % node_id.to_upper()).to_upper())
		if not system_names.is_empty():
			badge_texts.append(tr("PHASE_SUMMARY_SINCE_BASELINE") % ", ".join(system_names))
	if bool(result.get("shower", false)):
		badge_texts.append(tr("PHASE_SUMMARY_BADGE_SHOWER"))
	if new_best:
		badge_texts.append(tr("PHASE_SUMMARY_BADGE_BEST"))
	var modules_acquired = result.get("modules_acquired", [])
	if modules_acquired is Array and not modules_acquired.is_empty():
		var module_names: Array[String] = []
		for module_variant in modules_acquired:
			var module_id := String(module_variant)
			if module_id.is_empty():
				continue
			var module_name := module_id
			if deep_sky != null and deep_sky.has_method("research_name"):
				module_name = String(deep_sky.research_name(module_id))
			module_names.append(module_name)
		if not module_names.is_empty():
			badge_texts.append(tr("PHASE_SUMMARY_MODULES_ACQUIRED") % _bounded_acquired_names(module_names))
	var extension_research_acquired = result.get("extension_research_acquired", [])
	if extension_research_acquired is Array and not extension_research_acquired.is_empty():
		var research_names: Array[String] = []
		for research_variant in extension_research_acquired:
			var research_id := String(research_variant)
			if research_id.is_empty():
				continue
			var research_name := research_id
			if deep_sky != null and deep_sky.has_method("research_name"):
				research_name = String(deep_sky.research_name(research_id))
			research_names.append(research_name)
		if not research_names.is_empty():
			badge_texts.append(tr("PHASE_SUMMARY_RESEARCH_ACQUIRED") % _bounded_acquired_names(research_names))
	phase_summary_badges.text = "  •  ".join(badge_texts)
	phase_summary_badges.visible = not badge_texts.is_empty()
	phase_summary_button.text = tr("PHASE_SUMMARY_CONTINUE")
	phase_summary_overlay.visible = true
	phase_summary_overlay.move_to_front()
	if reveal_delay > 0.0:
		phase_summary_overlay.modulate.a = 0.0
		phase_summary_button.disabled = true
		phase_summary_reveal = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		phase_summary_reveal.set_ignore_time_scale(true)
		phase_summary_reveal.tween_interval(reveal_delay)
		phase_summary_reveal.tween_property(phase_summary_overlay, "modulate:a", 1.0, 0.3)
		phase_summary_reveal.tween_callback(func(): phase_summary_button.disabled = false)
	_refresh_in_round_readouts()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _refresh_phase_number_text() -> void:
	if phase_number_result.is_empty():
		return
	phase_summary_data.text = tr("PHASE_SUMMARY_OUTPUT") % _data_number(phase_number_result.data)
	UITheme.data_tooltip(phase_summary_data, phase_number_result.data)
	phase_summary_comparison.text = _round_comparison_text(phase_number_result.rate, phase_number_result.previous, phase_number_result.comparison)
	summary_lead.text = _round_comparison_text(phase_number_result.rate, phase_number_result.previous, phase_number_result.comparison)
	var previous: Dictionary = phase_number_result.previous
	if phase_number_result.comparison == "comparison" and float(previous.get("rate", 0.0)) > 0.0:
		var change := int(round((phase_number_result.rate / float(previous.rate) - 1.0) * 100.0))
		summary_lead.text = tr("PHASE_SUMMARY_GROWTH") % [_data_number(phase_number_result.rate, 1), _signed_round_value(change)]
	UITheme.data_tooltip(phase_summary_comparison, phase_number_result.rate, 1)
	phase_summary_comparison.tooltip_text = _round_comparison_text(phase_number_result.rate, phase_number_result.previous, phase_number_result.comparison, true)


func _round_comparison_text(round_rate: float, previous_result: Dictionary, comparison_state: String, exact: bool = false) -> String:
	var rate_text := UITheme.full_data(round_rate, 1) if exact else _data_number(round_rate, 1)
	match comparison_state:
		"systems_changed":
			return tr("PHASE_SUMMARY_SYSTEMS_CHANGED") % rate_text
		"equipment_changed":
			return tr("PHASE_SUMMARY_EQUIPMENT_CHANGED") % rate_text
		"session_resumed":
			return tr("PHASE_SUMMARY_SESSION_RESUMED") % rate_text
		"first_baseline":
			return tr("PHASE_SUMMARY_FIRST_BASELINE") % rate_text
	if previous_result.is_empty():
		return tr("PHASE_SUMMARY_FIRST_BASELINE") % rate_text
	var previous_rate := maxf(0.0, float(previous_result.get("rate", 0.0)))
	var delta := round_rate - previous_rate
	var signed_delta := _signed_rate_value(delta, exact)
	if previous_rate <= 0.0:
		return tr("PHASE_SUMMARY_COMPARE_DELTA") % [rate_text, signed_delta]
	var percent_delta := int(round(delta * 100.0 / previous_rate))
	return tr("PHASE_SUMMARY_COMPARE") % [rate_text, signed_delta, _signed_round_value(percent_delta)]


func _bounded_acquired_names(names: Array[String]) -> String:
	if names.size() <= 2:
		return ", ".join(names)
	return "%s, %s %s" % [names[0], names[1], tr("PHASE_SUMMARY_MORE_ACQUIRED") % (names.size() - 2)]


func _signed_round_value(value: int) -> String:
	return "+%d" % value if value > 0 else "%d" % value


func _signed_rate_value(value: float, exact: bool = false) -> String:
	return ("+" if value > 0.0 else "") + (UITheme.full_data(value, 1) if exact else _data_number(value, 1))


func hide_phase_summary() -> void:
	_reset_phase_summary_reveal()
	if phase_summary_overlay != null:
		phase_summary_button.release_focus()
		phase_summary_overlay.visible = false
	_refresh_in_round_readouts()


func _reset_phase_summary_reveal() -> void:
	if phase_summary_reveal != null:
		phase_summary_reveal.kill()
		phase_summary_reveal = null
	if phase_summary_overlay != null:
		phase_summary_overlay.modulate.a = 1.0
		phase_summary_button.disabled = false


func is_phase_summary_open() -> bool:
	return phase_summary_overlay != null and phase_summary_overlay.visible


func open_settings(page: String = "") -> void:
	if settings_overlay.visible:
		if not page.is_empty():
			_set_settings_page(page)
		return
	settings_previous_focus = get_viewport().gui_get_focus_owner()
	settings_overlay.visible = true
	settings_overlay.move_to_front()
	_refresh_in_round_readouts()
	paused_by_settings = not get_tree().paused
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_sync_language_selector()
	_sync_settings_controls()
	_refresh_save_slots()
	save_feedback.visible = false
	tutorial_replay_button.disabled = is_phase_summary_open() or final_observation_active
	tutorial_replay_button.tooltip_text = tr("ENDING_TUTORIAL_UNAVAILABLE" if final_observation_active else "TUTORIAL_REPLAY_UNAVAILABLE_SUMMARY") if tutorial_replay_button.disabled else ""
	var requested_page := page if page in SETTINGS_PAGE_ORDER else settings_active_page
	_set_settings_page(requested_page, false)
	_focus_settings_page.call_deferred(requested_page)


func close_settings() -> void:
	if not settings_overlay.visible:
		return
	settings_overlay.visible = false
	_refresh_in_round_readouts()
	if overwrite_dialog != null and overwrite_dialog.visible:
		overwrite_dialog.hide()
	if reset_dialog != null and reset_dialog.visible:
		reset_dialog.hide()
		pending_reset_slot = 0
	if reset_bindings_dialog != null and reset_bindings_dialog.visible:
		reset_bindings_dialog.hide()
	_cancel_rebind(false)
	if paused_by_settings:
		get_tree().paused = false
	paused_by_settings = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if get_tree().paused else Input.MOUSE_MODE_HIDDEN
	_restore_focus(settings_previous_focus)
	settings_previous_focus = null


func is_settings_open() -> bool:
	return settings_overlay != null and settings_overlay.visible


func is_controls_open() -> bool:
	return is_settings_open() and settings_active_page == "controls"


func is_rebind_capture_active() -> bool:
	return not rebind_action.is_empty()


func open_startup_slots() -> void:
	if startup_overlay == null or startup_overlay.visible:
		return
	startup_overlay.visible = true
	startup_overlay.move_to_front()
	_refresh_in_round_readouts()
	paused_by_startup = not get_tree().paused
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	startup_hint.text = tr("STARTUP_SAVE_HINT")
	startup_hint.add_theme_color_override("font_color", UITheme.HINT)
	_refresh_startup_slots()
	_focus_first_startup_action.call_deferred()


func close_startup_slots() -> void:
	if startup_overlay == null or not startup_overlay.visible:
		return
	startup_overlay.visible = false
	_refresh_in_round_readouts()
	if reset_dialog != null and reset_dialog.visible:
		reset_dialog.hide()
		pending_reset_slot = 0
	if paused_by_startup:
		get_tree().paused = false
	paused_by_startup = false
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


func is_startup_slots_open() -> bool:
	return startup_overlay != null and startup_overlay.visible


func _focus_first_startup_action() -> void:
	if not is_startup_slots_open():
		return
	for button in startup_slot_buttons:
		if is_instance_valid(button) and button.visible and not button.disabled:
			button.grab_focus()
			return
	for button in startup_reset_buttons:
		if is_instance_valid(button) and button.visible and not button.disabled:
			button.grab_focus()
			return


func consume_menu_back() -> bool:
	if is_rebind_capture_active():
		_cancel_rebind(true)
		return true
	if reset_bindings_dialog != null and reset_bindings_dialog.visible:
		reset_bindings_dialog.hide()
		return true
	if reset_dialog != null and reset_dialog.visible:
		reset_dialog.hide()
		pending_reset_slot = 0
		return true
	if overwrite_dialog != null and overwrite_dialog.visible:
		overwrite_dialog.hide()
		pending_overwrite_slot = 0
		return true
	if is_settings_open():
		close_settings()
		return true
	return false


func set_active_save_slot(slot: int) -> void:
	if slot != active_save_slot:
		last_autosave_unix = 0
	active_save_slot = slot
	autosave_status_timer = 0.0
	autosave_failed = false
	_refresh_save_mode_label(false)
	_refresh_save_slot_views()
	_refresh_save_status()


func show_autosaved(slot: int) -> void:
	active_save_slot = slot
	autosave_status_timer = 2.2
	last_autosave_unix = int(Time.get_unix_time_from_system())
	autosave_failed = false
	_refresh_save_mode_label(true)
	_refresh_save_status()


func show_autosave_failed(slot: int) -> void:
	active_save_slot = slot
	autosave_failed = true
	_refresh_save_status()


func _refresh_save_mode_label(just_saved: bool) -> void:
	if save_mode_label == null:
		return
	save_mode_label.visible = just_saved and active_save_slot > 0
	if not save_mode_label.visible:
		return
	save_mode_label.text = tr("HUD_AUTOSAVED")
	save_mode_label.add_theme_color_override("font_color", UITheme.GAIN)


func _unhandled_key_input(event: InputEvent) -> void:
	# The always-processing GameInputRouter owns this path in the live game. This
	# remains as a safe fallback for isolated HUD fixtures.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if consume_menu_back():
			get_viewport().set_input_as_handled()


func _refresh_progression() -> void:
	if progression == null:
		return
	var current_data := float(progression.observation_data)
	if last_observation_data >= 0.0 and current_data > last_observation_data:
		_show_data_gain(current_data - last_observation_data)
	last_observation_data = current_data
	data_label.text = _data_number(floor(current_data))
	UITheme.data_tooltip(data_label, floor(current_data))
	_layout_data_readout()
	_refresh_ready_notice()


func _grouped(value: int) -> String:
	return UITheme.grouped_integer(value)


func _data_number(value: float, small_decimals: int = 0) -> String:
	return settings_controller.format_data(value, small_decimals) if settings_controller != null else UITheme.data_number(value, "compact", small_decimals)


func _refresh_ready_notice() -> void:
	if ready_notice == null or progression == null:
		return
	var ready := 0
	for definition in Balance.UPGRADE_NODES:
		if progression.can_purchase(String(definition.id)):
			ready += 1
	if deep_sky != null and deep_sky.modules_unlocked():
		for id in deep_sky.modules.RESEARCH_IDS:
			if deep_sky.can_purchase(id):
				ready += 1
		for id in ExtensionData.RESEARCH_ORDER:
			if deep_sky.can_purchase(id):
				ready += 1
	if ready == last_ready_count:
		return
	var newly_ready := last_ready_count <= 0 and ready > 0
	last_ready_count = ready
	ready_notice.visible = ready > 0 and not _in_round_readouts_covered()
	if in_round_visibility.has("ReadySystems"):
		in_round_visibility["ReadySystems"] = ready > 0
	if ready > 0:
		ready_label.text = tr("HUD_RESEARCH_READY") % _chart_binding_label()
		ready_label.tooltip_text = tr("HUD_READY_SYSTEMS") % [ready, _chart_binding_label()]
		_layout_ready_notice()
		if newly_ready and ready_notice.visible:
			_ensure_ready_pulse()
	elif ready_pulse_tween != null and ready_pulse_tween.is_valid():
		ready_pulse_tween.kill()


func _refresh_extension() -> void:
	if extension_readout == null:
		return
	var objective := ""
	if observation_phase_active and deep_sky != null and deep_sky.has_method("current_objective"):
		objective = String(deep_sky.current_objective()).strip_edges()
	extension_objective_label.text = objective
	extension_objective_label.visible = not objective.is_empty()
	extension_samples_label.visible = false # Samples are shown beside the draw action, not over the sky.
	extension_should_show = extension_objective_label.visible or extension_samples_label.visible
	if not _in_round_readouts_covered():
		extension_readout.visible = extension_should_show
	_layout_extension_readout()
	_refresh_in_round_readouts()


func _ensure_ready_pulse() -> void:
	if ready_pulse_tween != null and ready_pulse_tween.is_valid():
		return
	ready_pulse_tween = create_tween()
	ready_pulse_tween.tween_property(ready_pip, "modulate:a", 0.35, 0.8).set_trans(Tween.TRANS_SINE)
	ready_pulse_tween.tween_property(ready_pip, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE)


func set_phase_window(ratio: float) -> void:
	if phase_window_fill == null:
		return
	var next_width := UITheme.px(OBSERVATION_CLOCK_WIDTH) * clampf(ratio, 0.0, 1.0)
	if is_equal_approx(next_width, last_phase_window_width):
		return
	last_phase_window_width = next_width
	phase_window_fill.size.x = next_width


func get_data_anchor() -> Vector2:
	# Where a delivered observation packet is aimed. Returned in viewport
	# coordinates: this CanvasLayer carries no transform, so its controls and the
	# default canvas the effects layer draws into share one space.
	if data_label == null:
		return Vector2.ZERO
	var extent := data_label.size
	if extent == Vector2.ZERO:
		extent = data_label.get_minimum_size()
	return data_label.global_position + extent * 0.5


func pulse_data_counter(amount: float) -> void:
	if data_label == null or amount < 1.0:
		return
	if data_pulse_tween != null and data_pulse_tween.is_valid():
		data_pulse_tween.kill()
	data_label.pivot_offset = data_label.size * 0.5
	data_label.scale = Vector2(1.07, 1.07)
	data_pulse_tween = create_tween()
	data_pulse_tween.tween_property(data_label, "scale", Vector2.ONE, 0.24) 		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _show_data_gain(amount: float) -> void:
	if amount < 1.0 or data_gain_label == null:
		return
	if data_gain_tween != null and data_gain_tween.is_valid():
		data_gain_tween.kill()
	last_data_gain = round(amount)
	data_gain_label.text = tr("HUD_DATA_GAIN") % _data_number(last_data_gain)
	UITheme.data_tooltip(data_gain_label, last_data_gain)
	_layout_data_readout()
	data_gain_label.modulate = Color.WHITE
	data_gain_label.visible = true
	data_label.modulate = UITheme.GAIN
	data_gain_tween = create_tween()
	data_gain_tween.set_parallel(true)
	data_gain_tween.tween_property(data_label, "modulate", Color.WHITE, 0.48)
	data_gain_tween.tween_property(data_gain_label, "modulate:a", 0.0, 0.72).set_delay(0.42)
	data_gain_tween.chain().tween_callback(func():
		if is_instance_valid(data_gain_label):
			data_gain_label.visible = false
	)


func _on_phase_summary_continue_pressed() -> void:
	if is_phase_summary_open():
		phase_summary_continue_requested.emit()


func show_save_feedback(text: String, color: Color) -> void:
	save_feedback.text = text
	save_feedback.add_theme_color_override("font_color", color)
	save_feedback.visible = true


func show_slot_reset_feedback(text: String, color: Color) -> void:
	if is_startup_slots_open():
		startup_hint.text = text
		startup_hint.add_theme_color_override("font_color", color)
	else:
		show_save_feedback(text, color)


func _on_save_slot_pressed(slot: int) -> void:
	if save_game_controller == null:
		return
	if save_game_controller.has_slot(slot):
		pending_overwrite_slot = slot
		overwrite_dialog.dialog_text = tr("SAVE_OVERWRITE_PROMPT") % slot
		overwrite_dialog.popup_centered(Vector2i(430, 180))
		return
	var summary: Dictionary = save_game_controller.get_slot_summary(slot)
	if not bool(summary.get("exists", false)):
		new_game_slot_requested.emit(slot)
		return
	save_slot_requested.emit(slot)


func _on_load_slot_pressed(slot: int) -> void:
	if save_game_controller != null and save_game_controller.has_slot(slot):
		load_slot_requested.emit(slot)


func _on_reset_slot_pressed(slot: int) -> void:
	if save_game_controller == null:
		return
	var summary: Dictionary = save_game_controller.get_slot_summary(slot)
	if not bool(summary.get("exists", false)):
		return
	pending_reset_slot = slot
	reset_dialog.dialog_text = tr("SAVE_RESET_PROMPT") % slot
	reset_dialog.popup_centered(Vector2i(460, 190))


func _on_startup_slot_pressed(slot: int) -> void:
	if save_game_controller == null:
		return
	var summary: Dictionary = save_game_controller.get_slot_summary(slot)
	if bool(summary.get("exists", false)) and not bool(summary.get("valid", false)):
		return
	startup_slot_selected.emit(slot)


func _on_overwrite_confirmed() -> void:
	if pending_overwrite_slot < 1:
		return
	var slot := pending_overwrite_slot
	pending_overwrite_slot = 0
	save_slot_requested.emit(slot)


func _on_reset_confirmed() -> void:
	if pending_reset_slot < 1:
		return
	var slot := pending_reset_slot
	pending_reset_slot = 0
	reset_slot_requested.emit(slot)


func _on_reset_canceled() -> void:
	pending_reset_slot = 0


func _refresh_save_slots() -> void:
	if save_game_controller == null or save_slot_titles.size() != 3:
		return
	for slot in range(1, 4):
		var index := slot - 1
		var summary: Dictionary = save_game_controller.get_slot_summary(slot)
		save_slot_titles[index].text = tr("SAVE_SLOT_TITLE") % slot
		if slot == active_save_slot:
			save_slot_titles[index].text += tr("SAVE_ACTIVE_MARKER")
		var exists := bool(summary.get("exists", false))
		var valid := bool(summary.get("valid", false))
		load_slot_buttons[index].disabled = not exists or not valid
		reset_slot_buttons[index].visible = exists
		reset_slot_buttons[index].text = tr("SAVE_RESET_ACTION")
		if exists and valid:
			save_slot_buttons[index].text = tr("SAVE_OVERWRITE")
		elif exists:
			save_slot_buttons[index].text = tr("SAVE_ACTION")
		else:
			save_slot_buttons[index].text = tr("STARTUP_NEW_GAME")
		load_slot_buttons[index].text = tr("LOAD_ACTION")
		save_slot_details[index].text = _format_slot_details(summary)
		UITheme.data_tooltip(save_slot_details[index], floor(float(summary.get("observation_data", 0.0))))
		if not exists or not valid: save_slot_details[index].tooltip_text = ""
	_refresh_save_status()


func _refresh_save_slot_views() -> void:
	_refresh_save_slots()
	if is_startup_slots_open():
		_refresh_startup_slots()


func _refresh_save_status() -> void:
	if save_status_label == null:
		return
	if active_save_slot < 1 or active_save_slot > 3:
		save_status_label.text = tr("SAVE_STATUS_NO_SLOT")
		save_status_label.add_theme_color_override("font_color", UITheme.INK_MID)
		return
	if autosave_failed:
		save_status_label.text = tr("SAVE_STATUS_FAILURE") % active_save_slot
		save_status_label.add_theme_color_override("font_color", UITheme.ALERT)
		return
	var saved_at := last_autosave_unix
	if saved_at <= 0 and save_game_controller != null:
		var summary: Dictionary = save_game_controller.get_slot_summary(active_save_slot)
		saved_at = int(summary.get("saved_at", 0))
	var stamp := tr("SAVE_STATUS_NEVER")
	if saved_at > 0:
		var timezone: Dictionary = Time.get_time_zone_from_system()
		var local_saved_at := saved_at + int(timezone.get("bias", 0)) * 60
		var date := Time.get_datetime_dict_from_unix_time(local_saved_at)
		stamp = "%02d:%02d" % [date.hour, date.minute]
	save_status_label.text = tr("SAVE_STATUS_ACTIVE") % [active_save_slot, stamp]
	save_status_label.add_theme_color_override("font_color", UITheme.ACCENT_TEXT)


func _refresh_startup_slots() -> void:
	if save_game_controller == null or startup_slot_titles.size() != 3:
		return
	for slot in range(1, 4):
		var index := slot - 1
		var summary: Dictionary = save_game_controller.get_slot_summary(slot)
		var exists := bool(summary.get("exists", false))
		var valid := bool(summary.get("valid", false))
		startup_slot_titles[index].text = tr("SAVE_SLOT_TITLE") % slot
		startup_slot_details[index].text = _format_slot_details(summary)
		UITheme.data_tooltip(startup_slot_details[index], floor(float(summary.get("observation_data", 0.0))))
		if not exists or not valid: startup_slot_details[index].tooltip_text = ""
		startup_slot_buttons[index].disabled = exists and not valid
		startup_reset_buttons[index].visible = exists
		startup_reset_buttons[index].text = tr("SAVE_RESET_ACTION")
		if exists and valid:
			startup_slot_buttons[index].text = tr("STARTUP_CONTINUE")
		elif exists:
			startup_slot_buttons[index].text = tr("STARTUP_UNAVAILABLE")
		else:
			startup_slot_buttons[index].text = tr("STARTUP_NEW_GAME")


func _format_slot_details(summary: Dictionary) -> String:
	var exists := bool(summary.get("exists", false))
	var valid := bool(summary.get("valid", false))
	if not exists:
		return tr("SAVE_SLOT_EMPTY")
	if not valid:
		return tr("SAVE_SLOT_INVALID")
	var saved_at := int(summary.get("saved_at", 0))
	var timezone: Dictionary = Time.get_time_zone_from_system()
	var local_saved_at := saved_at + int(timezone.get("bias", 0)) * 60
	var date := Time.get_datetime_dict_from_unix_time(local_saved_at)
	var stamp := "%04d-%02d-%02d %02d:%02d" % [date.year, date.month, date.day, date.hour, date.minute]
	var seconds := int(summary.get("elapsed_time", 0.0))
	return tr("SAVE_SLOT_META") % [
		stamp, seconds / 60, seconds % 60,
		_data_number(floor(float(summary.get("observation_data", 0.0)))), int(summary.get("upgrade_level", 0)),
		Balance.research_node_count()
	]


func _on_language_selected(index: int) -> void:
	if settings_controller == null or index < 0 or index >= language_selector.item_count:
		return
	settings_controller.set_language(String(language_selector.get_item_metadata(index)))


func _on_language_changed(_locale: String) -> void:
	_sync_language_selector()
	_apply_locale()
	_refresh_phase_number_text()


func _on_number_notation_selected(index: int) -> void:
	if syncing_settings_controls or settings_controller == null:
		return
	settings_controller.set_number_notation(String(number_notation_selector.get_item_metadata(index)))


func _on_number_notation_changed(_notation: String) -> void:
	_sync_settings_controls()
	_refresh_progression()
	data_gain_label.text = tr("HUD_DATA_GAIN") % _data_number(last_data_gain)
	_layout_data_readout()
	_refresh_phase_number_text()
	_refresh_save_slot_views()


func _on_audio_changed(_master_linear: float, _muted: bool) -> void:
	_sync_settings_controls()


func _on_settings_policy_changed() -> void:
	_sync_settings_controls()


func _on_fullscreen_changed(_fullscreen: bool) -> void:
	_sync_settings_controls()


func _on_performance_changed(_vsync_enabled: bool, _fps_limit: int) -> void:
	_sync_settings_controls()


func _on_accessibility_changed(_motion_intensity: float, _screen_flashes_enabled: bool) -> void:
	_sync_settings_controls()


func _on_input_bindings_changed() -> void:
	_apply_dynamic_binding_labels()
	_refresh_controls_rows()


func _on_master_volume_changed(value: float) -> void:
	if syncing_settings_controls or settings_controller == null:
		return
	settings_controller.set_master_volume_linear(value / 100.0)


func _on_mute_pressed() -> void:
	if settings_controller != null:
		settings_controller.toggle_muted()


func _on_mute_unfocused_pressed() -> void:
	if settings_controller != null:
		settings_controller.toggle_mute_when_unfocused()


func _on_fullscreen_pressed() -> void:
	if settings_controller != null:
		settings_controller.toggle_fullscreen()


func _on_vsync_pressed() -> void:
	if settings_controller != null:
		settings_controller.toggle_vsync()


func _on_fps_limit_selected(index: int) -> void:
	if syncing_settings_controls or settings_controller == null or index < 0 or index >= fps_limit_selector.item_count:
		return
	settings_controller.set_fps_limit(int(fps_limit_selector.get_item_metadata(index)))


func _on_motion_intensity_changed(value: float) -> void:
	if syncing_settings_controls or settings_controller == null:
		return
	settings_controller.set_motion_intensity(value / 100.0)


func _on_screen_flashes_pressed() -> void:
	if settings_controller != null:
		settings_controller.toggle_screen_flashes()


func _sync_settings_controls() -> void:
	if settings_controller == null:
		return
	syncing_settings_controls = true
	if number_notation_selector != null:
		for index in range(number_notation_selector.item_count):
			if number_notation_selector.get_item_metadata(index) == settings_controller.number_notation:
				number_notation_selector.select(index)
	if master_volume_slider != null:
		master_volume_slider.value = float(settings_controller.get_master_volume_linear()) * 100.0
	if master_volume_value != null:
		master_volume_value.text = "%d" % int(round(float(settings_controller.get_master_volume_linear()) * 100.0))
	if mute_button != null:
		mute_button.text = tr("SETTINGS_ON") if settings_controller.is_muted() else tr("SETTINGS_OFF")
	if mute_unfocused_button != null:
		mute_unfocused_button.text = tr("SETTINGS_ON") if settings_controller.should_mute_when_unfocused() else tr("SETTINGS_OFF")
	if fullscreen_button != null:
		fullscreen_button.text = tr("SETTINGS_ON") if settings_controller.is_fullscreen() else tr("SETTINGS_OFF")
	if vsync_button != null:
		vsync_button.text = tr("SETTINGS_ON") if settings_controller.is_vsync_enabled() else tr("SETTINGS_OFF")
	if performance_monitor_button != null:
		performance_monitor_button.text = tr("SETTINGS_ON") if settings_controller.performance_monitor_enabled else tr("SETTINGS_OFF")
	if fps_limit_selector != null:
		for index in range(fps_limit_selector.item_count):
			if int(fps_limit_selector.get_item_metadata(index)) == int(settings_controller.get_fps_limit()):
				fps_limit_selector.select(index)
				break
	if motion_intensity_slider != null:
		motion_intensity_slider.value = float(settings_controller.get_motion_intensity()) * 100.0
	if motion_intensity_value != null:
		motion_intensity_value.text = "%d%%" % int(round(float(settings_controller.get_motion_intensity()) * 100.0))
	if screen_flashes_button != null:
		screen_flashes_button.text = tr("SETTINGS_ON") if settings_controller.are_screen_flashes_enabled() else tr("SETTINGS_OFF")
	syncing_settings_controls = false


func _on_audio_display_pressed() -> void:
	_set_settings_page("audio")


func _on_save_management_pressed() -> void:
	_set_settings_page("save")


func _set_save_management_expanded(expanded: bool) -> void:
	if expanded:
		_set_settings_page("save")
	elif settings_active_page == "save":
		_set_settings_page("general")


func _set_audio_display_expanded(expanded: bool) -> void:
	if expanded:
		_set_settings_page("audio")
	elif settings_active_page == "audio":
		_set_settings_page("general")


func _refresh_settings_panel_height() -> void:
	# The consolidated console has a fixed safe frame at 1152x648. Kept as a
	# compatibility hook for probes that called the former accordion layout.
	pass


func _set_settings_page(page: String, focus_page: bool = true) -> void:
	if page not in SETTINGS_PAGE_ORDER or settings_pages.is_empty():
		return
	var focus_owner := get_viewport().gui_get_focus_owner()
	var old_page: Control = settings_pages.get(settings_active_page)
	if focus_owner != null and old_page != null and (focus_owner == old_page or old_page.is_ancestor_of(focus_owner)):
		settings_page_focus_memory[settings_active_page] = focus_owner
	if settings_active_page != "controls" and page == "controls":
		settings_page_before_controls = settings_active_page
	if settings_active_page == "controls" and page != "controls":
		_cancel_rebind(false)
	settings_active_page = page
	for page_name in settings_pages:
		var page_control: Control = settings_pages[page_name]
		page_control.visible = page_name == page
	audio_display_expanded = page == "audio"
	save_management_expanded = page == "save"
	_refresh_settings_navigation()
	if page == "save":
		_refresh_save_slots()
		_refresh_save_status()
	elif page == "controls":
		_refresh_controls_rows()
	if focus_page:
		_focus_settings_page.call_deferred(page)


func _refresh_settings_navigation() -> void:
	for page_name in settings_nav_buttons:
		var button: Button = settings_nav_buttons[page_name]
		var active: bool = String(page_name) == settings_active_page
		button.text = (">  " if active else "   ") + tr(String(SETTINGS_PAGE_TAB_KEYS[page_name]))
		button.add_theme_color_override("font_color", UITheme.ACCENT_TEXT if active else UITheme.INK_MID)
		button.add_theme_color_override("font_hover_color", UITheme.ACCENT_TEXT)
		button.add_theme_color_override("font_focus_color", UITheme.ACCENT_TEXT)
		button.add_theme_stylebox_override("normal", _action_underline_style(active))


func _focus_settings_page(page: String) -> void:
	if not is_settings_open() or settings_active_page != page:
		return
	var remembered: Control = settings_page_focus_memory.get(page)
	if _restore_focus(remembered):
		return
	var target: Control
	match page:
		"general":
			target = language_selector
		"audio":
			target = master_volume_slider
		"display":
			target = fullscreen_button
		"accessibility":
			target = motion_intensity_slider
		"controls":
			target = controls_action_widgets.get("nw_chart")
		"save":
			for button in save_slot_buttons:
				if is_instance_valid(button) and button.visible and not button.disabled:
					target = button
					break
	if target != null:
		target.grab_focus()


func _contains_keyboard_focus(control: Control) -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus != null and (focus == control or control.is_ancestor_of(focus))


func _sync_language_selector() -> void:
	if settings_controller == null or language_selector == null:
		return
	var index: int = settings_controller.get_language_index()
	if index >= 0 and index < language_selector.item_count:
		language_selector.select(index)


func _chart_binding_label() -> String:
	if settings_controller != null and settings_controller.has_method("binding_label"):
		return String(settings_controller.binding_label(&"nw_chart"))
	return "U"


func _apply_dynamic_binding_labels() -> void:
	if root_control == null:
		return
	if tutorial_label != null:
		tutorial_label.text = tr("HUD_TUTORIAL_DONE") % _chart_binding_label() if tutorial_complete else tr("HUD_TUTORIAL_START")
	last_ready_count = -1
	_refresh_ready_notice()


func _apply_locale() -> void:
	if root_control == null:
		return
	data_caption_label.text = tr("HUD_DATA_CAPTION")
	last_ready_count = -1
	_refresh_ready_notice()
	_invalidate_tracking_cache()
	_refresh_phase_time_label()
	settings_button.text = tr("SETTINGS_BUTTON")
	settings_title.text = tr("SETTINGS_TITLE")
	settings_subtitle.text = tr("SETTINGS_PAUSED")
	for localized in settings_page_labels:
		var page_label: Label = localized["label"]
		page_label.text = tr(String(localized["key"]))
	tutorial_replay_button.text = tr("TUTORIAL_REPLAY")
	if tutorial_replay_button.disabled:
		tutorial_replay_button.tooltip_text = tr("ENDING_TUTORIAL_UNAVAILABLE" if final_observation_active else "TUTORIAL_REPLAY_UNAVAILABLE_SUMMARY")
	if controls_reset_button != null:
		controls_reset_button.text = tr("CONTROLS_RESET")
	startup_title.text = tr("STARTUP_SAVE_TITLE")
	startup_subtitle.text = tr("STARTUP_SAVE_SUBTITLE")
	startup_hint.text = tr("STARTUP_SAVE_HINT")
	settings_close_button.text = tr("SETTINGS_CLOSE")
	_refresh_settings_navigation()
	overwrite_dialog.title = tr("SAVE_OVERWRITE_TITLE")
	overwrite_dialog.ok_button_text = tr("SAVE_OVERWRITE_CONFIRM")
	overwrite_dialog.cancel_button_text = tr("SAVE_CANCEL")
	reset_dialog.title = tr("SAVE_RESET_TITLE")
	reset_dialog.ok_button_text = tr("SAVE_RESET_CONFIRM")
	reset_dialog.cancel_button_text = tr("SAVE_CANCEL")
	if reset_bindings_dialog != null:
		reset_bindings_dialog.title = tr("CONTROLS_RESET_TITLE")
		reset_bindings_dialog.dialog_text = tr("CONTROLS_RESET_PROMPT")
		reset_bindings_dialog.ok_button_text = tr("CONTROLS_RESET_CONFIRM")
		reset_bindings_dialog.cancel_button_text = tr("SAVE_CANCEL")
	language_selector.set_item_text(0, tr("SETTINGS_ENGLISH"))
	language_selector.set_item_text(1, tr("SETTINGS_KOREAN"))
	number_notation_selector.set_item_text(0, tr("SETTINGS_NUMBER_COMPACT"))
	number_notation_selector.set_item_text(1, tr("SETTINGS_NUMBER_SCIENTIFIC"))
	if fps_limit_selector != null:
		for index in range(fps_limit_selector.item_count):
			var limit := int(fps_limit_selector.get_item_metadata(index))
			fps_limit_selector.set_item_text(index, tr("SETTINGS_FPS_UNLIMITED") if limit == 0 else tr("SETTINGS_FPS_VALUE") % limit)
	tutorial_label.text = tr("HUD_TUTORIAL_DONE") % _chart_binding_label() if tutorial_complete else tr("HUD_TUTORIAL_START")
	_sync_settings_controls()
	_refresh_controls_rows()
	debug_label.text = "\n\n".join([
		tr("HUD_DEBUG_TITLE"),
		"\n".join([
			tr("HUD_DEBUG_DATA"), tr("HUD_DEBUG_NEXT"), tr("HUD_DEBUG_ALL"),
			tr("HUD_DEBUG_METEOR"), tr("HUD_DEBUG_RARE"), tr("HUD_DEBUG_SHOWER"),
			tr("HUD_DEBUG_FINAL"), tr("HUD_DEBUG_MODULE"), tr("HUD_DEBUG_RESET")
		])
	])
	last_runtime_second = -1
	_refresh_phase_time_label()
	_invalidate_tracking_cache()
	_refresh_save_mode_label(autosave_status_timer > 0.0)
	_refresh_save_status()
	if progression != null:
		_refresh_progression()
	_refresh_extension()
	_refresh_save_slot_views()


func _build_interface() -> void:
	var view = preload("res://scenes/ui/hud.tscn").instantiate()
	audio_display_button = view.get_node("%SettingsOverlay").get_node("%SettingsTab_Audio")
	audio_display_container = view.get_node("%SettingsOverlay").get_node("%SettingsPage_Audio")
	banner_label = view.get_node("%EventBanner").get_node("%BannerLabel")
	banner_root = view.get_node("%EventBanner")
	banner_rule = view.get_node("%EventBanner").get_node("%BannerRule")
	banner_subtitle = view.get_node("%EventBanner").get_node("%BannerSubtitle")
	controls_action_widgets = {
		"nw_observe": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Controls").get_node("%ControlsActionWidgetsNwObserve"),
		"nw_dish": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Controls").get_node("%ControlsActionWidgetsNwDish"),
		"nw_chart": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Controls").get_node("%Binding_nw_chart"),
		"nw_menu_back": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Controls").get_node("%Binding_nw_menu_back"),
		"nw_continue": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Controls").get_node("%Binding_nw_continue"),
		"nw_fullscreen": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Controls").get_node("%Binding_nw_fullscreen"),
	}
	controls_button = view.get_node("%SettingsOverlay").get_node("%SettingsTab_Controls")
	controls_clear_widgets = {"nw_menu_back": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Controls").get_node("%Clear_nw_menu_back")}
	controls_hint = view.get_node("%SettingsOverlay").get_node("%SettingsPage_Controls").get_node("%ControlsHint")
	controls_localized_text = [
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Controls").get_node("%ControlsLocalizedText0Label"),
		"key": "CONTROL_OBSERVE"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Controls").get_node("%ControlsLocalizedText1Label"),
		"key": "CONTROL_DISH"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Controls").get_node("%ControlsLocalizedText2Label"),
		"key": "CONTROLS_REQUIRES",
		"argument_key": "UPGRADE_SECONDARY_CAMERA_NAME"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Controls").get_node("%ControlsLocalizedText3Label"),
		"key": "CONTROL_CHART"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Controls").get_node("%ControlsLocalizedText4Label"),
		"key": "CONTROL_MENU_BACK"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Controls").get_node("%ControlsLocalizedText5Label"),
		"key": "CONTROL_CONTINUE"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Controls").get_node("%ControlsLocalizedText6Label"),
		"key": "CONTROL_FULLSCREEN"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Controls").get_node("%ControlsLocalizedText7Label"),
		"key": "CONTROL_ROTATE"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Controls").get_node("%ControlsLocalizedText8Label"),
		"key": "CONTROL_WHEEL"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Controls").get_node("%ControlsLocalizedText9Label"),
		"key": "CONTROL_ZOOM"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Controls").get_node("%ControlsLocalizedText10Label"),
		"key": "CONTROL_CTRL_WHEEL"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Controls").get_node("%ControlsLocalizedText11Label"),
		"key": "CONTROL_INSTALL"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Controls").get_node("%ControlsLocalizedText12Label"),
		"key": "CONTROL_POINTER_HOLD"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Controls").get_node("%ControlsLocalizedText13Label"),
		"key": "CONTROL_SKY_SWEEP"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Controls").get_node("%ControlsLocalizedText14Label"),
		"key": "CONTROLS_REQUIRES",
		"argument_key": "UPGRADE_POLAR_SURVEY_NAME"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Controls").get_node("%ControlsLocalizedText15Label"),
		"key": "CONTROL_POINTER_HOLD"},
	]
	controls_overlay = view.get_node("%SettingsOverlay").get_node("%SettingsPage_Controls")
	controls_panel = view.get_node("%SettingsOverlay").get_node("%SettingsPage_Controls")
	controls_reset_button = view.get_node("%SettingsOverlay").get_node("%SettingsPage_Controls").get_node("%ControlsResetButton")
	controls_status = view.get_node("%SettingsOverlay").get_node("%SettingsPage_Controls").get_node("%ControlsStatus")
	controls_subtitle = view.get_node("%SettingsOverlay").get_node("%SettingsPage_Controls").get_node("%PageDescription")
	controls_title = view.get_node("%SettingsOverlay").get_node("%SettingsPage_Controls").get_node("%PageTitle")
	data_caption_label = view.get_node("%DataReadout").get_node("%DataCaptionLabel")
	data_gain_label = view.get_node("%DataReadout").get_node("%DataGainLabel")
	data_label = view.get_node("%DataReadout").get_node("%DataLabel")
	debug_label = view.get_node("%DebugPanel").get_node("%DebugLabel")
	debug_panel = view.get_node("%DebugPanel")
	performance_monitor = view.get_node("%PerformanceMonitor")
	performance_monitor_button = view.get_node("%SettingsOverlay").get_node("%SettingsPage_Display").get_node("%PerformanceMonitorButton")
	performance_monitor_button.pressed.connect(func(): settings_controller.set_performance_monitor_enabled(not settings_controller.performance_monitor_enabled))
	extension_objective_label = view.get_node("%ExtensionReadout").get_node("%ExtensionObjectiveLabel")
	extension_readout = view.get_node("%ExtensionReadout")
	extension_samples_label = view.get_node("%ExtensionReadout").get_node("%ExtensionSamplesLabel")
	fps_limit_selector = view.get_node("%SettingsOverlay").get_node("%SettingsPage_Display").get_node("%FpsLimitSelector")
	fullscreen_button = view.get_node("%SettingsOverlay").get_node("%SettingsPage_Display").get_node("%FullscreenButton")
	language_selector = view.get_node("%SettingsOverlay").get_node("%SettingsPage_General").get_node("%LanguageSelector")
	load_slot_buttons = [
		view.get_node("%SettingsOverlay").get_node("%SettingsPage_Save").get_node("%HBoxContainer5").get_node("%Load"),
		view.get_node("%SettingsOverlay").get_node("%SettingsPage_Save").get_node("%HBoxContainer7").get_node("%Load"),
		view.get_node("%SettingsOverlay").get_node("%SettingsPage_Save").get_node("%HBoxContainer9").get_node("%Load"),
	]
	master_volume_label = view.get_node("%SettingsOverlay").get_node("%SettingsPage_Audio").get_node("%SettingsPageLabels11Label")
	master_volume_slider = view.get_node("%SettingsOverlay").get_node("%SettingsPage_Audio").get_node("%MasterVolume")
	master_volume_value = view.get_node("%SettingsOverlay").get_node("%SettingsPage_Audio").get_node("%MasterVolumeValue")
	motion_intensity_label = view.get_node("%SettingsOverlay").get_node("%SettingsPage_Accessibility").get_node("%SettingsPageLabels27Label")
	motion_intensity_slider = view.get_node("%SettingsOverlay").get_node("%SettingsPage_Accessibility").get_node("%MotionIntensitySlider")
	motion_intensity_value = view.get_node("%SettingsOverlay").get_node("%SettingsPage_Accessibility").get_node("%MotionIntensityValue")
	mute_button = view.get_node("%SettingsOverlay").get_node("%SettingsPage_Audio").get_node("%MuteButton")
	mute_unfocused_button = view.get_node("%SettingsOverlay").get_node("%SettingsPage_Audio").get_node("%MuteUnfocusedButton")
	number_notation_selector = view.get_node("%SettingsOverlay").get_node("%SettingsPage_General").get_node("%NumberNotationSelector")
	overwrite_dialog = view.get_node("%SettingsOverlay").get_node("%OverwriteDialog")
	phase_round_label = view.get_node("%PhaseClock").get_node("%PhaseRoundLabel")
	phase_summary_badges = view.get_node("%PhaseSummary").get_node("%Badges")
	phase_summary_button = view.get_node("%PhaseSummary").get_node("%ContinueButton")
	phase_summary_comparison = view.get_node("%PhaseSummary").get_node("%Comparison")
	phase_summary_data = view.get_node("%PhaseSummary").get_node("%Data")
	phase_summary_observations = view.get_node("%PhaseSummary").get_node("%Observations")
	phase_summary_overlay = view.get_node("%PhaseSummary")
	phase_summary_split = view.get_node("%PhaseSummary").get_node("%Split")
	phase_summary_subtitle = view.get_node("%PhaseSummary").get_node("%Duration")
	phase_summary_title = view.get_node("%PhaseSummary").get_node("%Title")
	phase_window_fill = view.get_node("%PhaseClock").get_node("%PhaseWindowFill")
	phase_window_track = view.get_node("%PhaseClock").get_node("%PhaseWindowTrack")
	ready_label = view.get_node("%ReadySystems").get_node("%ReadyLabel")
	ready_notice = view.get_node("%ReadySystems")
	ready_pip = view.get_node("%ReadySystems").get_node("%ReadyPip")
	reset_bindings_dialog = view.get_node("%SettingsOverlay").get_node("%ResetBindingsDialog")
	reset_dialog = view.get_node("%ResetDialog")
	reset_slot_buttons = [
		view.get_node("%SettingsOverlay").get_node("%SettingsPage_Save").get_node("%HBoxContainer5").get_node("%Reset"),
		view.get_node("%SettingsOverlay").get_node("%SettingsPage_Save").get_node("%HBoxContainer7").get_node("%Reset"),
		view.get_node("%SettingsOverlay").get_node("%SettingsPage_Save").get_node("%HBoxContainer9").get_node("%Reset"),
	]
	root_control = view
	save_feedback = view.get_node("%SettingsOverlay").get_node("%SettingsPage_Save").get_node("%SettingsPageLabels37Label")
	save_management_button = view.get_node("%SettingsOverlay").get_node("%SettingsTab_Save")
	save_management_container = view.get_node("%SettingsOverlay").get_node("%SettingsPage_Save")
	save_mode_label = view.get_node("%PhaseClock").get_node("%SaveModeLabel")
	save_section_label = view.get_node("%SettingsOverlay").get_node("%SettingsPage_Save").get_node("%SettingsPageLabels36Label")
	save_slot_buttons = [
		view.get_node("%SettingsOverlay").get_node("%SettingsPage_Save").get_node("%HBoxContainer5").get_node("%Save"),
		view.get_node("%SettingsOverlay").get_node("%SettingsPage_Save").get_node("%HBoxContainer7").get_node("%Save"),
		view.get_node("%SettingsOverlay").get_node("%SettingsPage_Save").get_node("%HBoxContainer9").get_node("%Save"),
	]
	save_slot_details = [
		view.get_node("%SettingsOverlay").get_node("%SettingsPage_Save").get_node("%HBoxContainer5").get_node("%Details"),
		view.get_node("%SettingsOverlay").get_node("%SettingsPage_Save").get_node("%HBoxContainer7").get_node("%Details"),
		view.get_node("%SettingsOverlay").get_node("%SettingsPage_Save").get_node("%HBoxContainer9").get_node("%Details"),
	]
	save_slot_titles = [
		view.get_node("%SettingsOverlay").get_node("%SettingsPage_Save").get_node("%HBoxContainer5").get_node("%Title"),
		view.get_node("%SettingsOverlay").get_node("%SettingsPage_Save").get_node("%HBoxContainer7").get_node("%Title"),
		view.get_node("%SettingsOverlay").get_node("%SettingsPage_Save").get_node("%HBoxContainer9").get_node("%Title"),
	]
	save_status_label = view.get_node("%SettingsOverlay").get_node("%SettingsPage_Save").get_node("%SaveStatusLabel")
	screen_flashes_button = view.get_node("%SettingsOverlay").get_node("%SettingsPage_Accessibility").get_node("%ScreenFlashesButton")
	settings_button = view.get_node("%SettingsButton")
	settings_close_button = view.get_node("%SettingsOverlay").get_node("%SettingsCloseButton")
	settings_hint = view.get_node("%SettingsOverlay").get_node("%SettingsPage_General").get_node("%SettingsPageLabels4Label")
	settings_language_label = view.get_node("%SettingsOverlay").get_node("%SettingsPage_General").get_node("%SettingsPageLabels3Label")
	settings_nav_buttons = {
		"general": view.get_node("%SettingsOverlay").get_node("%SettingsTab_General"),
		"audio": view.get_node("%SettingsOverlay").get_node("%SettingsTab_Audio"),
		"display": view.get_node("%SettingsOverlay").get_node("%SettingsTab_Display"),
		"accessibility": view.get_node("%SettingsOverlay").get_node("%SettingsTab_Accessibility"),
		"controls": view.get_node("%SettingsOverlay").get_node("%SettingsTab_Controls"),
		"save": view.get_node("%SettingsOverlay").get_node("%SettingsTab_Save"),
	}
	settings_overlay = view.get_node("%SettingsOverlay")
	settings_page_labels = [
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPageLabels0Label"),
		"key": "SETTINGS_NAVIGATION"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_General").get_node("%PageTitle"),
		"key": "SETTINGS_PAGE_GENERAL_TITLE"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_General").get_node("%PageDescription"),
		"key": "SETTINGS_PAGE_GENERAL_DESC"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_General").get_node("%SettingsPageLabels3Label"),
		"key": "SETTINGS_LANGUAGE"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_General").get_node("%SettingsPageLabels4Label"),
		"key": "SETTINGS_LANGUAGE_HINT"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_General").get_node("%SettingsPageLabels5Label"),
		"key": "SETTINGS_NUMBER_NOTATION"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_General").get_node("%SettingsPageLabels6Label"),
		"key": "SETTINGS_NUMBER_HINT"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_General").get_node("%SettingsPageLabels7Label"),
		"key": "SETTINGS_TUTORIAL_TITLE"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_General").get_node("%SettingsPageLabels8Label"),
		"key": "SETTINGS_TUTORIAL_DESC"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Audio").get_node("%PageTitle"),
		"key": "SETTINGS_PAGE_AUDIO_TITLE"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Audio").get_node("%PageDescription"),
		"key": "SETTINGS_PAGE_AUDIO_DESC"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Audio").get_node("%SettingsPageLabels11Label"),
		"key": "SETTINGS_MASTER_VOLUME"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Audio").get_node("%SettingsPageLabels12Label"),
		"key": "SETTINGS_MASTER_VOLUME_DESC"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Audio").get_node("%SettingsPageLabels13Label"),
		"key": "SETTINGS_MUTE_TITLE"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Audio").get_node("%SettingsPageLabels14Label"),
		"key": "SETTINGS_MUTE_DESC"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Audio").get_node("%SettingsPageLabels15Label"),
		"key": "SETTINGS_MUTE_UNFOCUSED_TITLE"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Audio").get_node("%SettingsPageLabels16Label"),
		"key": "SETTINGS_MUTE_UNFOCUSED_DESC"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Display").get_node("%PageTitle"),
		"key": "SETTINGS_PAGE_DISPLAY_TITLE"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Display").get_node("%PageDescription"),
		"key": "SETTINGS_PAGE_DISPLAY_DESC"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Display").get_node("%SettingsPageLabels19Label"),
		"key": "SETTINGS_FULLSCREEN_TITLE"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Display").get_node("%SettingsPageLabels20Label"),
		"key": "SETTINGS_FULLSCREEN_DESC"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Display").get_node("%SettingsPageLabels21Label"),
		"key": "SETTINGS_VSYNC_TITLE"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Display").get_node("%SettingsPageLabels22Label"),
		"key": "SETTINGS_VSYNC_DESC"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Display").get_node("%SettingsPageLabels23Label"),
		"key": "SETTINGS_FPS_TITLE"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Display").get_node("%SettingsPageLabels24Label"),
		"key": "SETTINGS_FPS_DESC"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Display").get_node("%MonitorTitle"),
		"key": "SETTINGS_MONITOR_TITLE"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Display").get_node("%MonitorDescription"),
		"key": "SETTINGS_MONITOR_DESC"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Accessibility").get_node("%PageTitle"),
		"key": "SETTINGS_PAGE_ACCESSIBILITY_TITLE"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Accessibility").get_node("%PageDescription"),
		"key": "SETTINGS_PAGE_ACCESSIBILITY_DESC"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Accessibility").get_node("%SettingsPageLabels27Label"),
		"key": "SETTINGS_MOTION_TITLE"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Accessibility").get_node("%SettingsPageLabels28Label"),
		"key": "SETTINGS_MOTION_DESC"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Accessibility").get_node("%SettingsPageLabels29Label"),
		"key": "SETTINGS_FLASHES_TITLE"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Accessibility").get_node("%SettingsPageLabels30Label"),
		"key": "SETTINGS_FLASHES_DESC"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Accessibility").get_node("%SettingsPageLabels31Label"),
		"key": "SETTINGS_ACCESSIBILITY_NOTE"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Controls").get_node("%PageTitle"),
		"key": "CONTROLS_TITLE"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Controls").get_node("%PageDescription"),
		"key": "CONTROLS_HINT"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Save").get_node("%PageTitle"),
		"key": "SETTINGS_PAGE_SAVE_TITLE"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Save").get_node("%PageDescription"),
		"key": "SETTINGS_PAGE_SAVE_DESC"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Save").get_node("%SettingsPageLabels36Label"),
		"key": "SAVE_SECTION_TITLE"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Save").get_node("%SettingsPageLabels37Label"),
		"key": "SAVE_SECTION_HINT"},
		{"label": view.get_node("%SettingsOverlay").get_node("%SettingsPageLabels38Label"),
		"key": "SETTINGS_AUTOSAVE_NOTE"},
	]
	settings_page_stack = view.get_node("%SettingsOverlay").get_node("%SettingsPages")
	settings_pages = {
		"general": view.get_node("%SettingsOverlay").get_node("%SettingsPage_General"),
		"audio": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Audio"),
		"display": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Display"),
		"accessibility": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Accessibility"),
		"controls": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Controls"),
		"save": view.get_node("%SettingsOverlay").get_node("%SettingsPage_Save"),
	}
	settings_panel = view.get_node("%SettingsOverlay").get_node("%SettingsConsole")
	settings_subtitle = view.get_node("%SettingsOverlay").get_node("%SettingsSubtitle")
	settings_title = view.get_node("%SettingsOverlay").get_node("%SettingsTitle")
	startup_hint = view.get_node("%StartupSaveSlots").get_node("%StartupHint")
	startup_overlay = view.get_node("%StartupSaveSlots")
	startup_reset_buttons = [
		view.get_node("%StartupSaveSlots").get_node("%HBoxContainer3").get_node("%Reset"),
		view.get_node("%StartupSaveSlots").get_node("%HBoxContainer5").get_node("%Reset"),
		view.get_node("%StartupSaveSlots").get_node("%HBoxContainer7").get_node("%Reset"),
	]
	startup_slot_buttons = [
		view.get_node("%StartupSaveSlots").get_node("%HBoxContainer3").get_node("%Select"),
		view.get_node("%StartupSaveSlots").get_node("%HBoxContainer5").get_node("%Select"),
		view.get_node("%StartupSaveSlots").get_node("%HBoxContainer7").get_node("%Select"),
	]
	startup_slot_details = [
		view.get_node("%StartupSaveSlots").get_node("%HBoxContainer3").get_node("%Details"),
		view.get_node("%StartupSaveSlots").get_node("%HBoxContainer5").get_node("%Details"),
		view.get_node("%StartupSaveSlots").get_node("%HBoxContainer7").get_node("%Details"),
	]
	startup_slot_titles = [
		view.get_node("%StartupSaveSlots").get_node("%HBoxContainer3").get_node("%Title"),
		view.get_node("%StartupSaveSlots").get_node("%HBoxContainer5").get_node("%Title"),
		view.get_node("%StartupSaveSlots").get_node("%HBoxContainer7").get_node("%Title"),
	]
	startup_subtitle = view.get_node("%StartupSaveSlots").get_node("%StartupSubtitle")
	startup_title = view.get_node("%StartupSaveSlots").get_node("%StartupTitle")
	summary_details = view.get_node("%PhaseSummary").get_node("%Details")
	summary_details_button = view.get_node("%PhaseSummary").get_node("%DetailsButton")
	summary_highlight = view.get_node("%PhaseSummary").get_node("%Highlight")
	summary_lead = view.get_node("%PhaseSummary").get_node("%Lead")
	time_label = view.get_node("%PhaseClock").get_node("%TimeLabel")
	tracking_cluster = view.get_node("%TrackingCluster")
	tracking_divider = view.get_node("%TrackingCluster").get_node("%TrackingDivider")
	tracking_multiplier = view.get_node("%TrackingCluster").get_node("%TrackingMultiplier")
	tracking_percent = view.get_node("%TrackingCluster").get_node("%TrackingPercent")
	tracking_quality = view.get_node("%TrackingCluster").get_node("%TrackingQuality")
	tracking_target = view.get_node("%TrackingCluster").get_node("%TrackingTarget")
	tutorial_label = view.get_node("%FirstObservationHint")
	tutorial_replay_button = view.get_node("%SettingsOverlay").get_node("%SettingsPage_General").get_node("%TutorialReplayButton")
	vsync_button = view.get_node("%SettingsOverlay").get_node("%SettingsPage_Display").get_node("%VsyncButton")
	add_child(view)
	view.get_node("%DataReadout").get_node("%DataLabel").resized.connect(_layout_data_readout)
	view.get_node("%PhaseSummary").get_node("%DetailsButton").toggled.connect(_set_summary_details)
	view.get_node("%PhaseSummary").get_node("%ContinueButton").pressed.connect(_on_phase_summary_continue_pressed)
	view.get_node("%SettingsOverlay").get_node("%SettingsTab_General").pressed.connect(_set_settings_page.bind("general", true))
	view.get_node("%SettingsOverlay").get_node("%SettingsTab_Audio").pressed.connect(_set_settings_page.bind("audio", true))
	view.get_node("%SettingsOverlay").get_node("%SettingsTab_Display").pressed.connect(_set_settings_page.bind("display", true))
	view.get_node("%SettingsOverlay").get_node("%SettingsTab_Accessibility").pressed.connect(_set_settings_page.bind("accessibility", true))
	view.get_node("%SettingsOverlay").get_node("%SettingsTab_Controls").pressed.connect(_set_settings_page.bind("controls", true))
	view.get_node("%SettingsOverlay").get_node("%SettingsTab_Save").pressed.connect(_set_settings_page.bind("save", true))
	view.get_node("%SettingsOverlay").get_node("%SettingsPage_General").get_node("%LanguageSelector").item_selected.connect(_on_language_selected)
	view.get_node("%SettingsOverlay").get_node("%SettingsPage_General").get_node("%NumberNotationSelector").item_selected.connect(_on_number_notation_selected)
	view.get_node("%SettingsOverlay").get_node("%SettingsPage_Audio").get_node("%MasterVolume").value_changed.connect(_on_master_volume_changed)
	view.get_node("%SettingsOverlay").get_node("%SettingsPage_Audio").get_node("%MuteButton").pressed.connect(_on_mute_pressed)
	view.get_node("%SettingsOverlay").get_node("%SettingsPage_Audio").get_node("%MuteUnfocusedButton").pressed.connect(_on_mute_unfocused_pressed)
	view.get_node("%SettingsOverlay").get_node("%SettingsPage_Display").get_node("%FullscreenButton").pressed.connect(_on_fullscreen_pressed)
	view.get_node("%SettingsOverlay").get_node("%SettingsPage_Display").get_node("%VsyncButton").pressed.connect(_on_vsync_pressed)
	view.get_node("%SettingsOverlay").get_node("%SettingsPage_Display").get_node("%FpsLimitSelector").item_selected.connect(_on_fps_limit_selected)
	view.get_node("%SettingsOverlay").get_node("%SettingsPage_Accessibility").get_node("%MotionIntensitySlider").value_changed.connect(_on_motion_intensity_changed)
	view.get_node("%SettingsOverlay").get_node("%SettingsPage_Accessibility").get_node("%ScreenFlashesButton").pressed.connect(_on_screen_flashes_pressed)
	view.get_node("%SettingsOverlay").get_node("%SettingsPage_Controls").get_node("%Binding_nw_chart").pressed.connect(_begin_rebind.bind(&"nw_chart"))
	view.get_node("%SettingsOverlay").get_node("%SettingsPage_Controls").get_node("%Binding_nw_menu_back").pressed.connect(_begin_rebind.bind(&"nw_menu_back"))
	view.get_node("%SettingsOverlay").get_node("%SettingsPage_Controls").get_node("%Clear_nw_menu_back").pressed.connect(_clear_optional_binding.bind(&"nw_menu_back"))
	view.get_node("%SettingsOverlay").get_node("%SettingsPage_Controls").get_node("%Binding_nw_continue").pressed.connect(_begin_rebind.bind(&"nw_continue"))
	view.get_node("%SettingsOverlay").get_node("%SettingsPage_Controls").get_node("%Binding_nw_fullscreen").pressed.connect(_begin_rebind.bind(&"nw_fullscreen"))
	view.get_node("%SettingsOverlay").get_node("%SettingsPage_Controls").get_node("%ControlsResetButton").pressed.connect(_on_controls_reset_pressed)
	view.get_node("%SettingsOverlay").get_node("%SettingsPage_Save").get_node("%HBoxContainer5").get_node("%Save").pressed.connect(_on_save_slot_pressed.bind(1))
	view.get_node("%SettingsOverlay").get_node("%SettingsPage_Save").get_node("%HBoxContainer5").get_node("%Load").pressed.connect(_on_load_slot_pressed.bind(1))
	view.get_node("%SettingsOverlay").get_node("%SettingsPage_Save").get_node("%HBoxContainer5").get_node("%Reset").pressed.connect(_on_reset_slot_pressed.bind(1))
	view.get_node("%SettingsOverlay").get_node("%SettingsPage_Save").get_node("%HBoxContainer7").get_node("%Save").pressed.connect(_on_save_slot_pressed.bind(2))
	view.get_node("%SettingsOverlay").get_node("%SettingsPage_Save").get_node("%HBoxContainer7").get_node("%Load").pressed.connect(_on_load_slot_pressed.bind(2))
	view.get_node("%SettingsOverlay").get_node("%SettingsPage_Save").get_node("%HBoxContainer7").get_node("%Reset").pressed.connect(_on_reset_slot_pressed.bind(2))
	view.get_node("%SettingsOverlay").get_node("%SettingsPage_Save").get_node("%HBoxContainer9").get_node("%Save").pressed.connect(_on_save_slot_pressed.bind(3))
	view.get_node("%SettingsOverlay").get_node("%SettingsPage_Save").get_node("%HBoxContainer9").get_node("%Load").pressed.connect(_on_load_slot_pressed.bind(3))
	view.get_node("%SettingsOverlay").get_node("%SettingsPage_Save").get_node("%HBoxContainer9").get_node("%Reset").pressed.connect(_on_reset_slot_pressed.bind(3))
	view.get_node("%SettingsOverlay").get_node("%SettingsCloseButton").pressed.connect(close_settings)
	view.get_node("%SettingsOverlay").get_node("%OverwriteDialog").confirmed.connect(_on_overwrite_confirmed)
	view.get_node("%SettingsOverlay").get_node("%ResetBindingsDialog").confirmed.connect(_on_controls_reset_confirmed)
	view.get_node("%SettingsButton").pressed.connect(open_settings)
	view.get_node("%StartupSaveSlots").get_node("%HBoxContainer3").get_node("%Select").pressed.connect(_on_startup_slot_pressed.bind(1))
	view.get_node("%StartupSaveSlots").get_node("%HBoxContainer3").get_node("%Reset").pressed.connect(_on_reset_slot_pressed.bind(1))
	view.get_node("%StartupSaveSlots").get_node("%HBoxContainer5").get_node("%Select").pressed.connect(_on_startup_slot_pressed.bind(2))
	view.get_node("%StartupSaveSlots").get_node("%HBoxContainer5").get_node("%Reset").pressed.connect(_on_reset_slot_pressed.bind(2))
	view.get_node("%StartupSaveSlots").get_node("%HBoxContainer7").get_node("%Select").pressed.connect(_on_startup_slot_pressed.bind(3))
	view.get_node("%StartupSaveSlots").get_node("%HBoxContainer7").get_node("%Reset").pressed.connect(_on_reset_slot_pressed.bind(3))
	view.get_node("%ResetDialog").confirmed.connect(_on_reset_confirmed)
	view.get_node("%ResetDialog").canceled.connect(_on_reset_canceled)
	tutorial_replay_button.pressed.connect(func(): tutorial_replay_requested.emit())
	# Option metadata is live binding data; Godot does not serialize it.
	for index in 2:
		language_selector.set_item_metadata(index, ["en", "ko"][index])
		number_notation_selector.set_item_metadata(index, ["compact", "scientific"][index])
	for index in 4:
		fps_limit_selector.set_item_metadata(index, [0, 30, 60, 120][index])
	tracking_cluster.ring_radius = UITheme.px(84.0)
	# Preserve localized initial rows before the slot controller is bound/opened.
	for index in 3:
		startup_slot_titles[index].text = tr("SAVE_SLOT_TITLE") % (index + 1)
		startup_slot_details[index].text = tr("SAVE_SLOT_EMPTY")
		startup_slot_buttons[index].text = tr("STARTUP_NEW_GAME")
		startup_reset_buttons[index].text = tr("SAVE_RESET_ACTION")
	for dialog in [reset_dialog, overwrite_dialog, reset_bindings_dialog]:
		_style_confirm_dialog(dialog)
	_layout_data_readout()
	_layout_phase_clock()
	_layout_banner()
	_set_summary_details(false)


func _layout_data_readout() -> void:
	if data_label == null:
		return
	var value_size := data_label.get_combined_minimum_size()
	var caption_size := data_caption_label.get_combined_minimum_size()
	var value_top := caption_size.y + UITheme.px(3.0)
	data_caption_label.position = Vector2.ZERO
	data_label.position = Vector2(0.0, value_top)
	data_label.size = value_size
	# The gain sits on the value's baseline, not its box, so it does not drift when
	# the counter gains a digit.
	var gain_size := data_gain_label.get_combined_minimum_size()
	data_gain_label.position = Vector2(
		value_size.x + UITheme.px(14.0),
		value_top + value_size.y * 0.86 - gain_size.y
	)


func _layout_phase_clock() -> void:
	if time_label == null:
		return
	var width := UITheme.px(OBSERVATION_CLOCK_WIDTH)
	var round_height := phase_round_label.get_combined_minimum_size().y
	var clock_height := time_label.get_combined_minimum_size().y
	for label in [phase_round_label, time_label, save_mode_label]:
		label.size.x = width
		label.position.x = 0.0
	phase_round_label.position.y = 0.0
	time_label.position.y = round_height + UITheme.px(3.0)
	var line_y := time_label.position.y + clock_height + UITheme.px(7.0)
	phase_window_track.position = Vector2(0.0, line_y)
	phase_window_track.size = Vector2(width, 1.0)
	phase_window_fill.position = phase_window_track.position
	phase_window_fill.size = Vector2(width if last_phase_window_width < 0.0 else last_phase_window_width, 1.0)
	save_mode_label.position.y = line_y + UITheme.px(12.0)


func _layout_extension_readout() -> void:
	if extension_readout == null:
		return
	var width := UITheme.px(900.0)
	extension_objective_label.size = Vector2(width, UITheme.px(30.0))
	extension_samples_label.size.x = width


func _layout_ready_notice() -> void:
	if ready_notice == null or not ready_notice.visible:
		return
	var text_size := ready_label.get_combined_minimum_size()
	ready_label.size = text_size
	var pip_gap := UITheme.px(10.0)
	var total := text_size.x + pip_gap + ready_pip.size.x
	var left := -UITheme.px(64.0) - total
	var top := UITheme.px(48.0)
	ready_pip.position = Vector2(left, top + text_size.y * 0.5 - ready_pip.size.y * 0.5)
	ready_label.position = Vector2(left + ready_pip.size.x + pip_gap, top)


func _layout_tracking_cluster() -> void:
	tracking_layout_passes += 1
	var cursor := tracking_cluster.cursor
	var width := UITheme.px(360.0)
	# Two quiet lines below the field. Leave room for the Perseid pips, and move
	# above the field near the horizon rather than covering the ground readouts.
	if tracking_metrics_dirty:
		tracking_percent.size.x = UITheme.px(66.0)
		tracking_target.size.x = width
		tracking_percent_height = tracking_percent.get_combined_minimum_size().y
		tracking_target_height = tracking_target.get_combined_minimum_size().y
		tracking_quality_size = tracking_quality.get_combined_minimum_size()
		tracking_multiplier_size = tracking_multiplier.get_combined_minimum_size()
		tracking_quality.size = tracking_quality_size
		tracking_multiplier.size = tracking_multiplier_size
		tracking_metrics_dirty = false
	var gap := UITheme.px(8.0)
	var show_divider := not tracking_multiplier.text.is_empty()
	tracking_divider.visible = show_divider
	var row_width := tracking_percent.size.x + gap + tracking_quality_size.x
	if show_divider:
		row_width += gap + 1.0 + gap + tracking_multiplier_size.x
	var screen_size := get_viewport().get_visible_rect().size
	var center_x := clampf(cursor.x, width * 0.5 + 8.0, screen_size.x - width * 0.5 - 8.0)
	var block_height := tracking_target_height + maxf(tracking_percent_height, tracking_quality_size.y) + UITheme.px(4.0)
	var block_top := cursor.y + tracking_cluster.ring_radius + UITheme.px(34.0)
	if block_top + block_height > screen_size.y - UITheme.px(125.0):
		block_top = cursor.y - tracking_cluster.ring_radius - block_height - UITheme.px(16.0)
	block_top = maxf(8.0, block_top)
	tracking_target.position = Vector2(center_x - width * 0.5, block_top)
	var row_top := block_top + tracking_target_height + UITheme.px(4.0)
	var row_left := center_x - row_width * 0.5
	tracking_percent.position = Vector2(row_left, row_top)
	var quality_left := row_left + tracking_percent.size.x + gap
	tracking_quality.position = Vector2(quality_left, row_top + (tracking_percent_height - tracking_quality_size.y) * 0.5)
	if show_divider:
		tracking_divider.position = Vector2(
			quality_left + tracking_quality_size.x + gap,
			row_top + tracking_percent_height * 0.5 - tracking_divider.size.y * 0.5
		)
		tracking_multiplier.position = Vector2(quality_left + tracking_quality_size.x + gap + 1.0 + gap, tracking_quality.position.y)


func _style_confirm_dialog(dialog: ConfirmationDialog) -> void:
	# Native dialog children are created by Godot, outside the authored scene.
	dialog.theme = preload("res://resources/ui/native_dialog.tres")
	dialog.get_label().theme = preload("res://resources/ui/native_dialog_label.tres")
	dialog.get_label().horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dialog.get_ok_button().theme = preload("res://resources/ui/native_dialog_confirm.tres")
	dialog.get_cancel_button().theme = preload("res://resources/ui/native_dialog_cancel.tres")
	dialog.get_ok_button().flat = true
	dialog.get_cancel_button().flat = true


func _set_summary_details(expanded: bool) -> void:
	summary_details.visible = expanded
	summary_lead.visible = not expanded
	summary_highlight.visible = not expanded and not summary_highlight.text.is_empty()
	summary_details_button.text = tr("UI_DETAILS_HIDE" if expanded else "PHASE_DETAILS_SHOW")


func open_controls() -> void:
	if not is_settings_open():
		open_settings("controls")
		return
	if is_controls_open():
		return
	controls_previous_focus = get_viewport().gui_get_focus_owner()
	controls_status.visible = false
	_cancel_rebind(false)
	_set_settings_page("controls")


func _close_controls(restore_focus: bool = true) -> void:
	if not is_controls_open():
		return
	if reset_bindings_dialog != null and reset_bindings_dialog.visible:
		reset_bindings_dialog.hide()
	_cancel_rebind(false)
	_set_settings_page(settings_page_before_controls if settings_page_before_controls in SETTINGS_PAGE_ORDER else "general", restore_focus)
	controls_previous_focus = null


func _restore_focus(target: Control) -> bool:
	if is_instance_valid(target) and target.is_inside_tree() and target.is_visible_in_tree() and target.focus_mode != Control.FOCUS_NONE:
		if not (target is BaseButton) or not target.disabled:
			target.grab_focus()
			return true
	get_viewport().gui_release_focus()
	return false


func _control_action_title(action: StringName) -> String:
	var keys := {
		&"nw_observe": "CONTROL_OBSERVE",
		&"nw_dish": "CONTROL_DISH",
		&"nw_chart": "CONTROL_CHART",
		&"nw_menu_back": "CONTROL_MENU_BACK",
		&"nw_continue": "CONTROL_CONTINUE",
		&"nw_fullscreen": "CONTROL_FULLSCREEN",
	}
	return tr(String(keys.get(action, String(action))))


func _fallback_binding_label(action: StringName) -> String:
	match action:
		&"nw_observe":
			return tr("CONTROL_LMB_HOLD")
		&"nw_dish":
			return tr("CONTROL_RMB")
		&"nw_chart":
			return "U"
		&"nw_menu_back":
			return "Esc"
		&"nw_continue":
			return "Enter / Space / U"
		&"nw_fullscreen":
			return "F11"
	return "—"


func _binding_label(action: StringName) -> String:
	if settings_controller != null and settings_controller.has_method("binding_label"):
		return String(settings_controller.binding_label(action))
	return _fallback_binding_label(action)


func _binding_slot_label(action: StringName, slot: int) -> String:
	if settings_controller != null and settings_controller.has_method("binding_label"):
		return String(settings_controller.binding_label(action, slot))
	var pieces := _fallback_binding_label(action).split(" / ")
	return pieces[slot] if slot >= 0 and slot < pieces.size() else ""


func _binding_button_text(action: StringName) -> String:
	match action:
		&"nw_menu_back":
			var alternate := _binding_slot_label(action, 1)
			if alternate.is_empty():
				alternate = tr("CONTROLS_ADD_KEY")
			return "%s  %s  •  [%s]" % [_binding_slot_label(action, 0), tr("CONTROLS_FIXED"), alternate]
		&"nw_continue":
			return "%s / %s  %s  •  [%s]" % [
				_binding_slot_label(action, 0),
				_binding_slot_label(action, 1),
				tr("CONTROLS_FIXED"),
				_binding_slot_label(action, 2),
			]
	return "[%s]" % _binding_label(action)


func _refresh_controls_rows() -> void:
	for localized in controls_localized_text:
		var label: Label = localized["label"]
		var key := String(localized["key"])
		if localized.has("argument_key"):
			label.text = tr(key) % tr(String(localized["argument_key"]))
		else:
			label.text = tr(key)
	for action_text in controls_action_widgets:
		var action := StringName(action_text)
		var widget: Control = controls_action_widgets[action_text]
		if widget is Button and action == rebind_action:
			widget.text = tr("CONTROLS_CAPTURE")
		elif widget is Button:
			widget.text = _binding_button_text(action)
		elif widget is Label:
			widget.text = "%s  •  %s" % [_binding_label(action), tr("CONTROLS_FIXED")]
	for action_text in controls_clear_widgets:
		var clear_button: Button = controls_clear_widgets[action_text]
		clear_button.text = tr("CONTROLS_REMOVE")
		clear_button.tooltip_text = tr("CONTROLS_REMOVE")
		clear_button.visible = not _binding_slot_label(StringName(action_text), 1).is_empty()


func _begin_rebind(action: StringName) -> void:
	if settings_controller == null or not is_controls_open():
		return
	rebind_action = action
	rebind_release_keycode = 0
	controls_status.text = tr("CONTROLS_CAPTURE")
	controls_status.add_theme_color_override("font_color", UITheme.BANNER_TITLE)
	controls_status.visible = true
	_refresh_controls_rows()
	var widget: Control = controls_action_widgets.get(String(action))
	if widget != null:
		widget.grab_focus()


func _cancel_rebind(show_feedback: bool = true) -> void:
	rebind_action = &""
	rebind_release_keycode = 0
	_refresh_controls_rows()
	if controls_status == null:
		return
	if show_feedback:
		controls_status.text = tr("CONTROLS_CAPTURE_CANCELLED")
		controls_status.add_theme_color_override("font_color", UITheme.INK_MID)
		controls_status.visible = true
	else:
		controls_status.visible = false


func handle_rebind_capture_input(event: InputEvent) -> bool:
	if event is InputEventKey and not event.pressed and rebind_release_keycode != 0:
		if _event_keycode(event) == rebind_release_keycode:
			rebind_release_keycode = 0
			return true
	if not is_rebind_capture_active():
		return false
	if not (event is InputEventKey):
		# Capture is deliberately keyboard-only this pass, but pointer/gamepad input
		# is swallowed so it cannot operate a covered gameplay surface.
		return true
	if event.echo:
		return true
	if not event.pressed:
		return true
	var code := _event_keycode(event)
	if code == KEY_ESCAPE:
		rebind_release_keycode = code
		rebind_action = &""
		_refresh_controls_rows()
		controls_status.text = tr("CONTROLS_CAPTURE_CANCELLED")
		controls_status.add_theme_color_override("font_color", UITheme.INK_MID)
		controls_status.visible = true
		return true
	if code in [KEY_CTRL, KEY_SHIFT, KEY_ALT, KEY_META] or code == 0:
		return true
	var captured_action := rebind_action
	var use_physical: bool = event.keycode == 0 and event.physical_keycode != 0
	var result: Dictionary = settings_controller.set_editable_binding(captured_action, event, 0, true, use_physical)
	if bool(result.get("ok", false)):
		rebind_release_keycode = code
		rebind_action = &""
		_refresh_controls_rows()
		controls_status.text = tr("CONTROLS_REBOUND") % [_control_action_title(captured_action), _binding_label(captured_action)]
		controls_status.add_theme_color_override("font_color", UITheme.GAIN)
		controls_status.visible = true
	else:
		var conflict_action := StringName(result.get("conflict_action", &""))
		if not conflict_action.is_empty():
			controls_status.text = tr("CONTROLS_CONFLICT") % [_event_key_label(event), _control_action_title(conflict_action)]
		else:
			controls_status.text = tr("CONTROLS_INVALID")
		controls_status.add_theme_color_override("font_color", UITheme.ALERT)
		controls_status.visible = true
	return true


func _event_keycode(event: InputEventKey) -> int:
	return int(event.keycode if event.keycode != 0 else event.physical_keycode)


func _event_key_label(event: InputEventKey) -> String:
	var label := event.as_text_key_label()
	return label if not label.is_empty() else event.as_text()


func _on_controls_reset_pressed() -> void:
	if reset_bindings_dialog != null:
		reset_bindings_dialog.popup_centered(Vector2i(500, 190))


func _clear_optional_binding(action: StringName) -> void:
	if settings_controller == null:
		return
	var binding_widget: Control = controls_action_widgets.get(String(action))
	if binding_widget != null:
		binding_widget.grab_focus()
	var result: Dictionary = settings_controller.clear_editable_binding(action)
	_refresh_controls_rows()
	if bool(result.get("ok", false)):
		controls_status.text = tr("CONTROLS_REMOVED") % _control_action_title(action)
		controls_status.add_theme_color_override("font_color", UITheme.GAIN)
	else:
		controls_status.text = tr("CONTROLS_INVALID")
		controls_status.add_theme_color_override("font_color", UITheme.ALERT)
	controls_status.visible = true


func _on_controls_reset_confirmed() -> void:
	if settings_controller == null:
		return
	settings_controller.reset_nightwatch_bindings()
	_cancel_rebind(false)
	_refresh_controls_rows()
	controls_status.text = tr("CONTROLS_RESTORED")
	controls_status.add_theme_color_override("font_color", UITheme.GAIN)
	controls_status.visible = true



func _action_underline_style(bright: bool) -> StyleBoxFlat:
	return preload("res://resources/ui/action_focus.tres") if bright else preload("res://resources/ui/action_normal.tres")
