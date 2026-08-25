extends CanvasLayer

signal restart_requested
signal phase_summary_continue_requested
signal save_slot_requested(slot: int)
signal load_slot_requested(slot: int)
signal startup_slot_selected(slot: int)
signal new_game_slot_requested(slot: int)
signal reset_slot_requested(slot: int)
signal tutorial_replay_requested

const Balance = preload("res://scripts/game_balance.gd")
const UITheme = preload("res://scripts/ui_theme.gd")


class TrackingCluster:
	extends Control

	# Text only. The gauge ring moved onto the software cursor, which is drawn at
	# the observation radius and already sat at this same point — two rings a few
	# pixels apart, both centred on the cursor, showing the same number.
	# ring_radius is kept because the text block is placed clear of it.
	var cursor := Vector2.ZERO
	var ring_radius: float = 50.0



var progression: Node
var settings_controller: Node
var save_game_controller: Node
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
var end_overlay: ColorRect
var end_title: Label
var end_stats: Label
var restart_button: Button
var phase_summary_overlay: Control
var in_round_visibility: Dictionary = {}
var phase_summary_title: Label
var phase_summary_subtitle: Label
var phase_summary_observations: Label
var phase_summary_data: Label
var phase_summary_split: Label
var phase_summary_comparison: Label
var phase_summary_badges: Label
var phase_summary_button: Button
var settings_button: Button
var settings_overlay: Control
var settings_panel: Control
var settings_title: Label
var settings_subtitle: Label
var settings_language_label: Label
var settings_hint: Label
var language_selector: OptionButton
var tutorial_replay_button: Button
var settings_close_button: Button
var save_management_button: Button
var save_management_container: VBoxContainer
var startup_overlay: Control
var startup_title: Label
var startup_subtitle: Label
var startup_hint: Label
var startup_slot_titles: Array[Label] = []
var startup_slot_details: Array[Label] = []
var startup_slot_buttons: Array[Button] = []
var startup_reset_buttons: Array[Button] = []
var save_section_label: Label
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
var data_gain_tween: Tween
var data_pulse_tween: Tween
var ready_pulse_tween: Tween
var last_end_success: bool = false
var paused_by_settings: bool = false
var paused_by_startup: bool = false
var active_save_slot: int = 0
var autosave_status_timer: float = 0.0
var save_management_expanded: bool = false


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
	if not settings_controller.language_changed.is_connected(_on_language_changed):
		settings_controller.language_changed.connect(_on_language_changed)
	_sync_language_selector()
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


func set_upgrade_phase(completed_round: int) -> void:
	phase_display_configured = true
	observation_phase_active = false
	observation_phase_round = maxi(1, completed_round)
	observation_phase_second = 0
	_refresh_phase_time_label()
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


func show_banner(text: String, color: Color = Color.WHITE, duration: float = 2.5) -> void:
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


func _layout_banner() -> void:
	if banner_root == null:
		return
	var width := UITheme.px(300.0)
	banner_rule.position = Vector2(-width * 0.5, UITheme.px(240.0))
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
	ring_radius: float = -1.0
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
	var quality_key := _tracking_quality_key(progress)
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


func _tracking_quality_key(progress: float) -> String:
	# The cluster names the grade the player is currently earning; the ring colour
	# used to be the only channel for it.
	if progress >= 0.99:
		return "QUALITY_PERFECT"
	if progress >= 0.75:
		return "QUALITY_EXCELLENT"
	if progress >= 0.45:
		return "QUALITY_GOOD"
	return "QUALITY_PARTIAL"


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
	tutorial_label.text = tr("HUD_TUTORIAL_DONE")
	var timer := get_tree().create_timer(4.0)
	timer.timeout.connect(func():
		if is_instance_valid(tutorial_label):
			tutorial_label.visible = false
	)


func reset_tutorial() -> void:
	tutorial_complete = false
	tutorial_label.text = tr("HUD_TUTORIAL_START")
	tutorial_label.visible = true


func restore_tutorial(already_observed: bool) -> void:
	tutorial_complete = already_observed
	tutorial_label.text = tr("HUD_TUTORIAL_DONE") if already_observed else tr("HUD_TUTORIAL_START")
	tutorial_label.visible = not already_observed


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


func show_end(success: bool, stats_text: String) -> void:
	last_end_success = success
	end_title.text = tr("HUD_END_SUCCESS") if success else tr("HUD_END_FAILURE")
	# Outcome reads as brightness rather than hue. The whole layer is red light,
	# so a red "failure" colour would say nothing; a sky that went dim on you does.
	end_title.add_theme_color_override("font_color", UITheme.INK_MAX if success else UITheme.INK_MID)
	end_stats.text = stats_text
	end_overlay.visible = true
	end_overlay.move_to_front()
	_refresh_in_round_readouts()


func hide_end() -> void:
	end_overlay.visible = false
	_refresh_in_round_readouts()


# Live readouts that belong to the round that just ended. The summary is
# typeset straight onto the sky now, so there is no panel in front of them and
# they would sit inside the summary's own column.
const IN_ROUND_GROUPS := ["DataReadout", "PhaseClock", "ReadySystems", "TrackingCluster", "EventBanner"]


func _refresh_in_round_readouts() -> void:
	# Any of the three overlays owns the screen while it is up, and none of them
	# has a panel to hide the live readouts behind any more.
	var covered := is_phase_summary_open()
	covered = covered or (end_overlay != null and end_overlay.visible)
	covered = covered or (settings_overlay != null and settings_overlay.visible)
	covered = covered or (startup_overlay != null and startup_overlay.visible)
	if covered:
		_stash_in_round_readouts()
	else:
		_restore_in_round_readouts()


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


func show_phase_summary(
	result: Dictionary,
	previous_result: Dictionary,
	comparison_state: String,
	new_best: bool
) -> void:
	var round_number := maxi(1, int(result.get("round", 1)))
	var data_earned := maxi(0, int(result.get("data", 0)))
	var duration_seconds := maxi(1, int(round(float(result.get("duration", 20.0)))))
	var round_rate := maxf(0.0, float(result.get("rate", 0.0)))
	var observations := maxi(0, int(result.get("observations", 0)))
	var manual_observations := maxi(0, int(result.get("manual", 0)))
	var automatic_observations := maxi(0, int(result.get("automatic", 0)))
	phase_summary_title.text = tr("PHASE_SUMMARY_TITLE") % round_number
	phase_summary_subtitle.text = tr("PHASE_SUMMARY_SUBTITLE") % duration_seconds
	phase_summary_data.text = tr("PHASE_SUMMARY_OUTPUT") % data_earned
	phase_summary_observations.text = tr("PHASE_SUMMARY_OBSERVATIONS") % observations
	phase_summary_split.text = tr("PHASE_SUMMARY_MANUAL_AUTO") % [manual_observations, automatic_observations]
	phase_summary_comparison.text = _round_comparison_text(round_rate, previous_result, comparison_state)
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
	phase_summary_badges.text = "  •  ".join(badge_texts)
	phase_summary_badges.visible = not badge_texts.is_empty()
	phase_summary_button.text = tr("PHASE_SUMMARY_CONTINUE")
	phase_summary_overlay.visible = true
	phase_summary_overlay.move_to_front()
	_refresh_in_round_readouts()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _round_comparison_text(round_rate: float, previous_result: Dictionary, comparison_state: String) -> String:
	match comparison_state:
		"systems_changed":
			return tr("PHASE_SUMMARY_SYSTEMS_CHANGED") % round_rate
		"session_resumed":
			return tr("PHASE_SUMMARY_SESSION_RESUMED") % round_rate
		"first_baseline":
			return tr("PHASE_SUMMARY_FIRST_BASELINE") % round_rate
	if previous_result.is_empty():
		return tr("PHASE_SUMMARY_FIRST_BASELINE") % round_rate
	var previous_rate := maxf(0.0, float(previous_result.get("rate", 0.0)))
	var delta := round_rate - previous_rate
	var signed_delta := _signed_rate_value(delta)
	if previous_rate <= 0.0:
		return tr("PHASE_SUMMARY_COMPARE_DELTA") % [round_rate, signed_delta]
	var percent_delta := int(round(delta * 100.0 / previous_rate))
	return tr("PHASE_SUMMARY_COMPARE") % [round_rate, signed_delta, _signed_round_value(percent_delta)]


func _signed_round_value(value: int) -> String:
	return "+%d" % value if value > 0 else "%d" % value


func _signed_rate_value(value: float) -> String:
	return "+%.1f" % value if value > 0.0 else "%.1f" % value


func hide_phase_summary() -> void:
	if phase_summary_overlay != null:
		phase_summary_overlay.visible = false
	_refresh_in_round_readouts()


func is_phase_summary_open() -> bool:
	return phase_summary_overlay != null and phase_summary_overlay.visible


func open_settings() -> void:
	if settings_overlay.visible:
		return
	settings_overlay.visible = true
	settings_overlay.move_to_front()
	_refresh_in_round_readouts()
	paused_by_settings = not get_tree().paused
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_sync_language_selector()
	_refresh_save_slots()
	save_feedback.visible = false
	_set_save_management_expanded(false)


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
	if paused_by_settings:
		get_tree().paused = false
	paused_by_settings = false
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


func is_settings_open() -> bool:
	return settings_overlay != null and settings_overlay.visible


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


func set_active_save_slot(slot: int) -> void:
	active_save_slot = slot
	autosave_status_timer = 0.0
	_refresh_save_mode_label(false)
	_refresh_save_slot_views()


func show_autosaved(slot: int) -> void:
	active_save_slot = slot
	autosave_status_timer = 2.2
	_refresh_save_mode_label(true)


func _refresh_save_mode_label(just_saved: bool) -> void:
	if save_mode_label == null:
		return
	save_mode_label.visible = just_saved and active_save_slot > 0
	if not save_mode_label.visible:
		return
	save_mode_label.text = tr("HUD_AUTOSAVED")
	save_mode_label.add_theme_color_override("font_color", UITheme.GAIN)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if reset_dialog != null and reset_dialog.visible:
			reset_dialog.hide()
			pending_reset_slot = 0
			get_viewport().set_input_as_handled()
			return
	if is_settings_open() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if overwrite_dialog != null and overwrite_dialog.visible:
			overwrite_dialog.hide()
			get_viewport().set_input_as_handled()
			return
		close_settings()
		get_viewport().set_input_as_handled()


func _refresh_progression() -> void:
	if progression == null:
		return
	var current_data := float(progression.observation_data)
	if last_observation_data >= 0.0 and current_data > last_observation_data:
		_show_data_gain(current_data - last_observation_data)
	last_observation_data = current_data
	data_label.text = _grouped(int(floor(current_data)))
	_layout_data_readout()
	_refresh_ready_notice()


func _grouped(value: int) -> String:
	var digits := str(absi(value))
	var grouped := ""
	for index in range(digits.length()):
		if index > 0 and (digits.length() - index) % 3 == 0:
			grouped += ","
		grouped += digits[index]
	return ("-" if value < 0 else "") + grouped


func _refresh_ready_notice() -> void:
	if ready_notice == null or progression == null:
		return
	var ready := 0
	for definition in Balance.UPGRADE_NODES:
		if progression.can_purchase(String(definition.id)):
			ready += 1
	if ready == last_ready_count:
		return
	last_ready_count = ready
	ready_notice.visible = ready > 0
	if ready_notice.visible:
		ready_label.text = tr("HUD_READY_SYSTEMS") % ready
		_layout_ready_notice()
		_ensure_ready_pulse()
	elif ready_pulse_tween != null and ready_pulse_tween.is_valid():
		ready_pulse_tween.kill()


func _ensure_ready_pulse() -> void:
	if ready_pulse_tween != null and ready_pulse_tween.is_valid():
		return
	ready_pulse_tween = create_tween().set_loops()
	ready_pulse_tween.tween_property(ready_pip, "modulate:a", 0.35, 0.8).set_trans(Tween.TRANS_SINE)
	ready_pulse_tween.tween_property(ready_pip, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE)


func set_phase_window(ratio: float) -> void:
	if phase_window_fill == null:
		return
	var next_width := UITheme.px(360.0) * clampf(ratio, 0.0, 1.0)
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
	data_label.scale = Vector2(1.16, 1.16)
	data_pulse_tween = create_tween()
	data_pulse_tween.tween_property(data_label, "scale", Vector2.ONE, 0.24) 		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _show_data_gain(amount: float) -> void:
	if amount < 1.0 or data_gain_label == null:
		return
	if data_gain_tween != null and data_gain_tween.is_valid():
		data_gain_tween.kill()
	data_gain_label.text = tr("HUD_DATA_GAIN") % int(round(amount))
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


func _refresh_save_slot_views() -> void:
	_refresh_save_slots()
	if is_startup_slots_open():
		_refresh_startup_slots()


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
		int(summary.get("observation_data", 0.0)), int(summary.get("upgrade_level", 0)),
		Balance.UPGRADE_NODES.size()
	]


func _on_language_selected(index: int) -> void:
	if settings_controller == null or index < 0 or index >= language_selector.item_count:
		return
	settings_controller.set_language(String(language_selector.get_item_metadata(index)))


func _on_language_changed(_locale: String) -> void:
	_sync_language_selector()
	_apply_locale()


func _on_save_management_pressed() -> void:
	_set_save_management_expanded(not save_management_expanded)


func _set_save_management_expanded(expanded: bool) -> void:
	save_management_expanded = expanded
	if save_management_container == null or settings_panel == null:
		return
	save_management_container.visible = expanded
	save_management_button.text = tr("SETTINGS_SAVE_HIDE") if expanded else tr("SETTINGS_SAVE_MANAGEMENT")
	# The column centres itself, so the frame only has to be tall enough for the
	# expanded state. Growing it on toggle made the whole block jump.
	var half_height := UITheme.px(470.0) if expanded else UITheme.px(350.0)
	settings_panel.offset_top = -half_height
	settings_panel.offset_bottom = half_height


func _sync_language_selector() -> void:
	if settings_controller == null or language_selector == null:
		return
	var index: int = settings_controller.get_language_index()
	if index >= 0 and index < language_selector.item_count:
		language_selector.select(index)


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
	settings_subtitle.text = tr("SETTINGS_SUBTITLE")
	settings_language_label.text = tr("SETTINGS_LANGUAGE")
	settings_hint.text = tr("SETTINGS_LANGUAGE_HINT")
	tutorial_replay_button.text = tr("TUTORIAL_REPLAY")
	startup_title.text = tr("STARTUP_SAVE_TITLE")
	startup_subtitle.text = tr("STARTUP_SAVE_SUBTITLE")
	startup_hint.text = tr("STARTUP_SAVE_HINT")
	save_section_label.text = tr("SAVE_SECTION_TITLE")
	save_feedback.text = tr("SAVE_SECTION_HINT")
	settings_close_button.text = tr("SETTINGS_CLOSE")
	if save_management_button != null:
		save_management_button.text = tr("SETTINGS_SAVE_HIDE") if save_management_expanded else tr("SETTINGS_SAVE_MANAGEMENT")
	overwrite_dialog.title = tr("SAVE_OVERWRITE_TITLE")
	overwrite_dialog.ok_button_text = tr("SAVE_OVERWRITE_CONFIRM")
	overwrite_dialog.cancel_button_text = tr("SAVE_CANCEL")
	reset_dialog.title = tr("SAVE_RESET_TITLE")
	reset_dialog.ok_button_text = tr("SAVE_RESET_CONFIRM")
	reset_dialog.cancel_button_text = tr("SAVE_CANCEL")
	language_selector.set_item_text(0, tr("SETTINGS_ENGLISH"))
	language_selector.set_item_text(1, tr("SETTINGS_KOREAN"))
	tutorial_label.text = tr("HUD_TUTORIAL_DONE") if tutorial_complete else tr("HUD_TUTORIAL_START")
	restart_button.text = tr("HUD_RESTART")
	end_title.text = tr("HUD_END_SUCCESS") if last_end_success else tr("HUD_END_FAILURE")
	debug_label.text = "\n\n".join([
		tr("HUD_DEBUG_TITLE"),
		"\n".join([
			tr("HUD_DEBUG_DATA"), tr("HUD_DEBUG_NEXT"), tr("HUD_DEBUG_ALL"),
			tr("HUD_DEBUG_METEOR"), tr("HUD_DEBUG_RARE"), tr("HUD_DEBUG_SHOWER"),
			tr("HUD_DEBUG_FINAL"), tr("HUD_DEBUG_RESET")
		])
	])
	last_runtime_second = -1
	_refresh_phase_time_label()
	_invalidate_tracking_cache()
	_refresh_save_mode_label(autosave_status_timer > 0.0)
	if progression != null:
		_refresh_progression()
	_refresh_save_slot_views()


func _build_interface() -> void:
	root_control = Control.new()
	root_control.name = "Interface"
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root_control)
	root_control.add_theme_font_override("font", UITheme.sans())
	_build_sky_gradients()

	_build_data_readout()
	_build_phase_clock()
	_build_ready_notice()

	banner_root = Control.new()
	banner_root.name = "EventBanner"
	banner_root.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_root.visible = false
	root_control.add_child(banner_root)
	banner_rule = ColorRect.new()
	banner_rule.color = UITheme.BANNER_RULE
	banner_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_root.add_child(banner_rule)
	banner_label = _spec_label("", UITheme.sans("light"), 27.0, UITheme.BANNER_TITLE, 0.22)
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_root.add_child(banner_label)
	banner_subtitle = _spec_label("", UITheme.mono(), 13.0, UITheme.BANNER_SUB, 0.20)
	banner_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_root.add_child(banner_subtitle)
	_layout_banner()

	tutorial_label = _spec_label(tr("HUD_TUTORIAL_START"), UITheme.sans(), 15.0, UITheme.HINT)
	tutorial_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	tutorial_label.anchor_left = 0.0
	tutorial_label.anchor_right = 1.0
	tutorial_label.offset_left = 0.0
	tutorial_label.offset_right = 0.0
	tutorial_label.offset_top = -UITheme.px(54.0) - UITheme.px(28.0)
	tutorial_label.offset_bottom = -UITheme.px(54.0)
	tutorial_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tutorial_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root_control.add_child(tutorial_label)

	_build_tracking_cluster()

	_build_debug_panel()
	_build_end_overlay()
	_build_phase_summary_overlay()
	_build_settings_ui()
	settings_button = Button.new()
	settings_button.name = "SettingsButton"
	settings_button.text = tr("SETTINGS_BUTTON")
	settings_button.flat = true
	settings_button.focus_mode = Control.FOCUS_NONE
	settings_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	settings_button.offset_left = -UITheme.px(200.0)
	settings_button.offset_top = -UITheme.px(50.0) - UITheme.px(22.0)
	settings_button.offset_right = -UITheme.px(56.0)
	settings_button.offset_bottom = -UITheme.px(50.0)
	settings_button.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	settings_button.add_theme_font_override("font", UITheme.mono())
	settings_button.add_theme_font_size_override("font_size", UITheme.size_px(12.0))
	settings_button.add_theme_constant_override("spacing_glyph", UITheme.tracking(UITheme.size_px(12.0), 0.20))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		settings_button.add_theme_color_override(state, UITheme.INK_LOW)
	settings_button.add_theme_color_override("font_hover_color", UITheme.INK_MID)
	settings_button.pressed.connect(open_settings)
	root_control.add_child(settings_button)
	_build_startup_slots_ui()
	_build_reset_dialog()


func _gradient_veil(from_alpha: float, height_spec: float, at_top: bool) -> TextureRect:
	# Legibility comes from two soft veils, not from bordered panels.
	var gradient := Gradient.new()
	var ink := Color(0.0078, 0.0118, 0.0235, from_alpha)
	gradient.set_color(0, ink if at_top else Color(ink, 0.0))
	gradient.set_color(1, Color(ink, 0.0) if at_top else ink)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(0.0, 1.0)
	texture.width = 8
	texture.height = 64
	var rect := TextureRect.new()
	rect.texture = texture
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if at_top:
		rect.set_anchors_preset(Control.PRESET_TOP_WIDE)
		rect.offset_bottom = UITheme.px(height_spec)
	else:
		rect.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		rect.offset_top = -UITheme.px(height_spec)
	return rect


func _build_sky_gradients() -> void:
	root_control.add_child(_gradient_veil(0.72, 230.0, true))
	root_control.add_child(_gradient_veil(0.60, 140.0, false))


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


func _build_data_readout() -> void:
	var column := Control.new()
	column.name = "DataReadout"
	column.set_anchors_preset(Control.PRESET_TOP_LEFT)
	column.offset_left = UITheme.px(56.0)
	column.offset_top = UITheme.px(46.0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(column)

	data_label = _spec_label("0", UITheme.mono_tabular(), 76.0, UITheme.INK_MAX, -0.03)
	data_label.position = Vector2.ZERO
	column.add_child(data_label)

	data_gain_label = _spec_label(tr("HUD_DATA_GAIN") % 0, UITheme.mono_tabular(), 22.0, UITheme.GAIN)
	data_gain_label.visible = false
	column.add_child(data_gain_label)

	data_caption_label = _spec_label(tr("HUD_DATA_CAPTION"), UITheme.mono(), 12.0, UITheme.INK_MID, 0.28)
	column.add_child(data_caption_label)
	_layout_data_readout()
	data_label.resized.connect(_layout_data_readout)


func _layout_data_readout() -> void:
	if data_label == null:
		return
	var value_size := data_label.get_combined_minimum_size()
	data_label.size = value_size
	# The gain sits on the value's baseline, not its box, so it does not drift when
	# the counter gains a digit.
	var gain_size := data_gain_label.get_combined_minimum_size()
	data_gain_label.position = Vector2(
		value_size.x + UITheme.px(14.0),
		value_size.y * 0.86 - gain_size.y
	)
	data_caption_label.position = Vector2(0.0, value_size.y * 0.86 + UITheme.px(12.0))


func _build_phase_clock() -> void:
	var column := Control.new()
	column.name = "PhaseClock"
	column.set_anchors_preset(Control.PRESET_CENTER_TOP)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(column)

	phase_round_label = _spec_label("", UITheme.mono(), 12.0, UITheme.INK_MID, 0.30)
	phase_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(phase_round_label)

	time_label = _spec_label(tr("HUD_TIME") % [0, 0], UITheme.mono_tabular(), 40.0, UITheme.INK_HIGH, 0.02)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(time_label)

	phase_window_track = ColorRect.new()
	phase_window_track.color = UITheme.ACCENT_DEEP
	phase_window_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(phase_window_track)
	phase_window_fill = ColorRect.new()
	phase_window_fill.color = UITheme.ACCENT_LINE
	phase_window_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(phase_window_fill)

	save_mode_label = _spec_label("", UITheme.mono(), 12.0, UITheme.INK_LOW, 0.18)
	save_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	save_mode_label.visible = false
	column.add_child(save_mode_label)
	_layout_phase_clock()


func _layout_phase_clock() -> void:
	if time_label == null:
		return
	var width := UITheme.px(360.0)
	var round_height := phase_round_label.get_combined_minimum_size().y
	var clock_height := time_label.get_combined_minimum_size().y
	for label in [phase_round_label, time_label, save_mode_label]:
		label.size.x = width
		label.position.x = -width * 0.5
	phase_round_label.position.y = UITheme.px(48.0)
	time_label.position.y = phase_round_label.position.y + round_height + UITheme.px(9.0)
	var line_y := time_label.position.y + clock_height + UITheme.px(14.0)
	phase_window_track.position = Vector2(-width * 0.5, line_y)
	phase_window_track.size = Vector2(width, 1.0)
	phase_window_fill.position = phase_window_track.position
	phase_window_fill.size = Vector2(width, 1.0)
	save_mode_label.position.y = line_y + UITheme.px(12.0)


func _build_ready_notice() -> void:
	ready_notice = Control.new()
	ready_notice.name = "ReadySystems"
	ready_notice.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	ready_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ready_notice.visible = false
	root_control.add_child(ready_notice)

	ready_pip = ColorRect.new()
	ready_pip.color = UITheme.ACCENT_PIP
	ready_pip.size = Vector2(UITheme.px(7.0), UITheme.px(7.0))
	ready_pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ready_notice.add_child(ready_pip)

	ready_label = _spec_label("", UITheme.sans(), 14.0, UITheme.ACCENT_TEXT, 0.06)
	ready_notice.add_child(ready_label)


func _layout_ready_notice() -> void:
	if ready_notice == null or not ready_notice.visible:
		return
	var text_size := ready_label.get_combined_minimum_size()
	ready_label.size = text_size
	var pip_gap := UITheme.px(10.0)
	var total := text_size.x + pip_gap + ready_pip.size.x
	var left := -UITheme.px(56.0) - total
	var top := UITheme.px(46.0)
	ready_pip.position = Vector2(left, top + text_size.y * 0.5 - ready_pip.size.y * 0.5)
	ready_label.position = Vector2(left + ready_pip.size.x + pip_gap, top)


func _build_tracking_cluster() -> void:
	tracking_cluster = TrackingCluster.new()
	tracking_cluster.name = "TrackingCluster"
	tracking_cluster.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tracking_cluster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tracking_cluster.process_mode = Node.PROCESS_MODE_PAUSABLE
	tracking_cluster.ring_radius = UITheme.px(84.0)
	tracking_cluster.visible = false
	root_control.add_child(tracking_cluster)

	tracking_percent = _spec_label("0%", UITheme.mono_tabular(), 26.0, UITheme.INSTRUMENT_ARC)
	tracking_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tracking_cluster.add_child(tracking_percent)

	tracking_target = _spec_label("", UITheme.sans(), 14.0, Color(UITheme.INSTRUMENT_LABEL, 0.80), 0.14)
	tracking_target.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tracking_cluster.add_child(tracking_target)

	tracking_quality = _spec_label("", UITheme.mono(), 13.0, UITheme.INSTRUMENT_QUALITY, 0.12)
	tracking_cluster.add_child(tracking_quality)
	tracking_divider = ColorRect.new()
	tracking_divider.color = UITheme.TOOLTIP_LABEL
	tracking_divider.size = Vector2(1.0, UITheme.px(11.0))
	tracking_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tracking_cluster.add_child(tracking_divider)
	tracking_multiplier = _spec_label("", UITheme.mono_tabular(), 13.0, UITheme.INSTRUMENT_QUALITY)
	tracking_cluster.add_child(tracking_multiplier)


func _layout_tracking_cluster() -> void:
	tracking_layout_passes += 1
	var cursor := tracking_cluster.cursor
	var width := UITheme.px(420.0)
	# Clear of the cursor ring so glyphs never sit on the meteor being tracked.
	var percent_top := cursor.y + tracking_cluster.ring_radius + UITheme.px(18.0)
	if tracking_metrics_dirty:
		tracking_percent.size.x = width
		tracking_target.size.x = width
		tracking_percent_height = tracking_percent.get_combined_minimum_size().y
		tracking_target_height = tracking_target.get_combined_minimum_size().y
		tracking_quality_size = tracking_quality.get_combined_minimum_size()
		tracking_multiplier_size = tracking_multiplier.get_combined_minimum_size()
		tracking_quality.size = tracking_quality_size
		tracking_multiplier.size = tracking_multiplier_size
		tracking_metrics_dirty = false
	for label in [tracking_percent, tracking_target]:
		label.position.x = cursor.x - width * 0.5
	tracking_percent.position.y = percent_top
	tracking_target.position.y = percent_top + tracking_percent_height + UITheme.px(5.0)
	var row_top := tracking_target.position.y + tracking_target_height + UITheme.px(8.0)

	var gap := UITheme.px(8.0)
	var show_divider := not tracking_multiplier.text.is_empty()
	tracking_divider.visible = show_divider
	var row_width := tracking_quality_size.x
	if show_divider:
		row_width += gap + 1.0 + gap + tracking_multiplier_size.x
	var row_left := cursor.x - row_width * 0.5
	tracking_quality.position = Vector2(row_left, row_top)
	if show_divider:
		tracking_divider.position = Vector2(
			row_left + tracking_quality_size.x + gap,
			row_top + tracking_quality_size.y * 0.5 - tracking_divider.size.y * 0.5
		)
		tracking_multiplier.position = Vector2(row_left + tracking_quality_size.x + gap + 1.0 + gap, row_top)


func _build_startup_slots_ui() -> void:
	startup_overlay = Control.new()
	startup_overlay.name = "StartupSaveSlots"
	startup_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	startup_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	startup_overlay.visible = false
	root_control.add_child(startup_overlay)
	var dim := ColorRect.new()
	dim.color = Color(UITheme.SCRIM, 0.96)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	startup_overlay.add_child(dim)
	var frame := Control.new()
	frame.name = "StartupColumn"
	frame.set_anchors_preset(Control.PRESET_CENTER)
	frame.offset_left = -UITheme.px(560.0)
	frame.offset_right = UITheme.px(560.0)
	frame.offset_top = -UITheme.px(390.0)
	frame.offset_bottom = UITheme.px(390.0)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	startup_overlay.add_child(frame)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", int(UITheme.px(12.0)))
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(column)
	startup_title = _spec_label(tr("STARTUP_SAVE_TITLE"), UITheme.sans("medium"), 40.0, UITheme.INK_MAX, -0.01)
	startup_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(startup_title)
	startup_subtitle = _spec_label(tr("STARTUP_SAVE_SUBTITLE"), UITheme.mono(), 13.0, UITheme.INK_MID, 0.30)
	startup_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(startup_subtitle)
	column.add_child(_hairline(1120.0))
	for slot in range(1, 4):
		_build_startup_slot_row(column, slot)
	startup_hint = _spec_label(tr("STARTUP_SAVE_HINT"), UITheme.sans("light"), 14.0, UITheme.HINT)
	startup_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	startup_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(startup_hint)


func _build_startup_slot_row(parent: VBoxContainer, slot: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(UITheme.px(24.0)))
	parent.add_child(row)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_theme_constant_override("separation", int(UITheme.px(4.0)))
	row.add_child(info)
	var title := _spec_label(tr("SAVE_SLOT_TITLE") % slot, UITheme.sans(), 20.0, UITheme.INK_HIGH)
	var details := _spec_label(tr("SAVE_SLOT_EMPTY"), UITheme.mono(), 13.0, UITheme.INK_LOW, 0.06)
	details.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.add_child(title)
	info.add_child(details)
	var select_button := Button.new()
	select_button.text = tr("STARTUP_NEW_GAME")
	_style_text_action(select_button, 18.0, UITheme.BANNER_TITLE)
	select_button.pressed.connect(_on_startup_slot_pressed.bind(slot))
	row.add_child(select_button)
	var reset_button := Button.new()
	reset_button.text = tr("SAVE_RESET_ACTION")
	_style_text_action(reset_button, 16.0, UITheme.ALERT)
	reset_button.pressed.connect(_on_reset_slot_pressed.bind(slot))
	reset_button.visible = false
	row.add_child(reset_button)
	parent.add_child(_hairline(1120.0))
	startup_slot_titles.append(title)
	startup_slot_details.append(details)
	startup_slot_buttons.append(select_button)
	startup_reset_buttons.append(reset_button)


func _style_confirm_dialog(dialog: ConfirmationDialog) -> void:
	# These were the last two surfaces still wearing Godot's default theme, so a
	# save prompt looked like an OS window dropped onto the observatory.
	dialog.transient = false
	dialog.exclusive = false
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(UITheme.SCRIM, 0.98)
	panel.border_width_top = 1
	panel.border_width_bottom = 1
	panel.border_width_left = 1
	panel.border_width_right = 1
	panel.border_color = UITheme.ACCENT_DEEP
	for side in ["content_margin_left", "content_margin_right"]:
		panel.set(side, UITheme.px(34.0))
	panel.content_margin_top = UITheme.px(26.0)
	panel.content_margin_bottom = UITheme.px(22.0)
	dialog.add_theme_stylebox_override("panel", panel)
	dialog.add_theme_font_override("font", UITheme.sans())
	dialog.add_theme_font_size_override("font_size", UITheme.size_px(19.0))
	dialog.add_theme_color_override("font_color", UITheme.INK_HIGH)
	var label := dialog.get_label()
	if label != null:
		label.add_theme_font_override("font", UITheme.sans())
		label.add_theme_font_size_override("font_size", UITheme.size_px(19.0))
		label.add_theme_color_override("font_color", UITheme.INK_HIGH)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_text_action(dialog.get_ok_button(), 18.0, UITheme.ALERT)
	_style_text_action(dialog.get_cancel_button(), 18.0, UITheme.INK_MID)


func _build_reset_dialog() -> void:
	reset_dialog = ConfirmationDialog.new()
	reset_dialog.title = tr("SAVE_RESET_TITLE")
	reset_dialog.ok_button_text = tr("SAVE_RESET_CONFIRM")
	reset_dialog.cancel_button_text = tr("SAVE_CANCEL")
	reset_dialog.confirmed.connect(_on_reset_confirmed)
	reset_dialog.canceled.connect(_on_reset_canceled)
	root_control.add_child(reset_dialog)
	_style_confirm_dialog(reset_dialog)


func _build_debug_panel() -> void:
	debug_panel = PanelContainer.new()
	debug_panel.name = "DebugPanel"
	debug_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	debug_panel.offset_left = -350.0
	debug_panel.offset_top = 78.0
	debug_panel.offset_right = -18.0
	debug_panel.offset_bottom = 252.0
	debug_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	debug_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.03, 0.025, 0.07, 0.96), Color(0.62, 0.45, 0.94, 0.7), 8))
	debug_panel.visible = false
	root_control.add_child(debug_panel)
	debug_label = _make_label(
		"\n\n".join([tr("HUD_DEBUG_TITLE"), "\n".join([tr("HUD_DEBUG_DATA"), tr("HUD_DEBUG_NEXT"), tr("HUD_DEBUG_ALL"), tr("HUD_DEBUG_METEOR"), tr("HUD_DEBUG_RARE"), tr("HUD_DEBUG_SHOWER"), tr("HUD_DEBUG_FINAL"), tr("HUD_DEBUG_RESET")])]),
		13,
		UITheme.INK_MID
	)
	debug_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
	debug_panel.add_child(debug_label)


func _build_end_overlay() -> void:
	end_overlay = ColorRect.new()
	end_overlay.name = "EndOverlay"
	end_overlay.color = Color(0.016, 0.008, 0.006, 0.94)
	end_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	end_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	end_overlay.visible = false
	root_control.add_child(end_overlay)
	var frame := Control.new()
	frame.name = "EndColumn"
	frame.set_anchors_preset(Control.PRESET_CENTER)
	frame.offset_left = -UITheme.px(640.0)
	frame.offset_right = UITheme.px(640.0)
	frame.offset_top = -UITheme.px(320.0)
	frame.offset_bottom = UITheme.px(320.0)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_overlay.add_child(frame)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", int(UITheme.px(20.0)))
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(column)

	end_title = _spec_label(tr("HUD_END_SUCCESS"), UITheme.sans("medium"), 46.0, UITheme.INK_MAX, -0.01)
	end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(end_title)

	var rule := CenterContainer.new()
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rule)
	var rule_line := ColorRect.new()
	rule_line.color = UITheme.ACCENT_DEEP
	rule_line.custom_minimum_size = Vector2(UITheme.px(420.0), 1.0)
	rule_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.add_child(rule_line)

	# The run tally is a column of figures, so it takes the tabular mono the
	# rest of the instrument layer uses. Proportional digits would leave the
	# six values ragged against each other.
	end_stats = _spec_label("", UITheme.mono_tabular(), 20.0, UITheme.INK_HIGH, 0.04)
	end_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(end_stats)

	restart_button = Button.new()
	restart_button.text = tr("HUD_RESTART")
	restart_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_text_action(restart_button, 22.0, UITheme.BANNER_TITLE)
	restart_button.pressed.connect(func(): restart_requested.emit())
	column.add_child(restart_button)


func _build_phase_summary_overlay() -> void:
	phase_summary_overlay = Control.new()
	phase_summary_overlay.name = "PhaseSummary"
	phase_summary_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	phase_summary_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	phase_summary_overlay.visible = false
	root_control.add_child(phase_summary_overlay)
	# No bordered panel. The round summary is typeset straight onto the dimmed
	# sky, the same way the in-round readouts and the research chart are. A panel
	# here was the last surface still speaking the old cyan HUD language.
	var dim := ColorRect.new()
	dim.color = Color(0.016, 0.008, 0.006, 0.88)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	phase_summary_overlay.add_child(dim)
	var frame := Control.new()
	frame.name = "SummaryColumn"
	frame.set_anchors_preset(Control.PRESET_CENTER)
	frame.offset_left = -UITheme.px(640.0)
	frame.offset_right = UITheme.px(640.0)
	frame.offset_top = -UITheme.px(300.0)
	frame.offset_bottom = UITheme.px(300.0)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	phase_summary_overlay.add_child(frame)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", int(UITheme.px(14.0)))
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(column)

	phase_summary_title = _spec_label("", UITheme.sans("medium"), 44.0, UITheme.INK_MAX, -0.01)
	phase_summary_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(phase_summary_title)

	phase_summary_subtitle = _spec_label("", UITheme.mono(), 13.0, UITheme.INK_MID, 0.30)
	phase_summary_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(phase_summary_subtitle)

	var rule := CenterContainer.new()
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rule)
	var rule_line := ColorRect.new()
	rule_line.color = UITheme.ACCENT_DEEP
	rule_line.custom_minimum_size = Vector2(UITheme.px(420.0), 1.0)
	rule_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.add_child(rule_line)

	# The round's output is a gain, so it takes the gain ink the data counter
	# already uses when it ticks up.
	phase_summary_data = _spec_label("", UITheme.sans("medium"), 40.0, UITheme.GAIN, 0.0)
	phase_summary_data.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(phase_summary_data)

	phase_summary_comparison = _spec_label("", UITheme.sans(), 17.0, UITheme.INK_MID, 0.02)
	phase_summary_comparison.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_summary_comparison.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(phase_summary_comparison)

	phase_summary_observations = _spec_label("", UITheme.sans("medium"), 22.0, UITheme.INK_HIGH, 0.0)
	phase_summary_observations.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(phase_summary_observations)

	phase_summary_split = _spec_label("", UITheme.sans("light"), 16.0, UITheme.INK_LOW, 0.06)
	phase_summary_split.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(phase_summary_split)

	phase_summary_badges = _spec_label("", UITheme.sans(), 15.0, UITheme.ACCENT_TEXT, 0.12)
	phase_summary_badges.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_summary_badges.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(phase_summary_badges)

	# Text with a rule under it, matching the research chart header action rather
	# than a filled button.
	phase_summary_button = Button.new()
	phase_summary_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_text_action(phase_summary_button, 22.0, UITheme.BANNER_TITLE)
	phase_summary_button.pressed.connect(_on_phase_summary_continue_pressed)
	column.add_child(phase_summary_button)


func _hairline(spec_width: float = 420.0) -> CenterContainer:
	var holder := CenterContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line := ColorRect.new()
	line.color = UITheme.ACCENT_DEEP
	line.custom_minimum_size = Vector2(UITheme.px(spec_width), 1.0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(line)
	return holder


func _style_text_action(button: Button, spec_size: float, color: Color) -> void:
	# Controls in the red-light layer are text with a rule under them, the same
	# as the research chart header action. A filled, bordered, rounded button is
	# the shape the observatory redesign removed.
	var font_size := UITheme.size_px(spec_size)
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", UITheme.sans())
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_constant_override("spacing_glyph", UITheme.tracking(font_size, 0.06))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, color)
	button.add_theme_color_override("font_disabled_color", UITheme.INK_LOW)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, _action_underline_style(state == "hover"))


func _action_underline_style(bright: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_width_bottom = 1
	style.border_color = UITheme.ACCENT_TEXT if bright else UITheme.ACCENT_DEEP
	style.content_margin_left = UITheme.px(10.0)
	style.content_margin_right = UITheme.px(10.0)
	style.content_margin_top = UITheme.px(12.0)
	style.content_margin_bottom = UITheme.px(9.0)
	return style


func _build_settings_ui() -> void:
	settings_overlay = Control.new()
	settings_overlay.name = "SettingsOverlay"
	settings_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	settings_overlay.visible = false
	root_control.add_child(settings_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.016, 0.008, 0.006, 0.9)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	settings_overlay.add_child(dim)
	# A column on the dimmed sky, not a bordered card. settings_panel stays a
	# Control so the save-management expansion can keep resizing it.
	settings_panel = Control.new()
	settings_panel.name = "SettingsColumn"
	settings_panel.set_anchors_preset(Control.PRESET_CENTER)
	settings_panel.offset_left = -UITheme.px(420.0)
	settings_panel.offset_right = UITheme.px(420.0)
	settings_panel.offset_top = -UITheme.px(350.0)
	settings_panel.offset_bottom = UITheme.px(350.0)
	settings_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	settings_overlay.add_child(settings_panel)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", int(UITheme.px(12.0)))
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	settings_panel.add_child(column)

	settings_title = _spec_label(tr("SETTINGS_TITLE"), UITheme.sans("medium"), 34.0, UITheme.INK_MAX, -0.01)
	settings_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(settings_title)
	settings_subtitle = _spec_label(tr("SETTINGS_SUBTITLE"), UITheme.mono(), 13.0, UITheme.INK_MID, 0.30)
	settings_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(settings_subtitle)
	column.add_child(_hairline(840.0))

	settings_language_label = _spec_label(tr("SETTINGS_LANGUAGE"), UITheme.mono(), 12.0, UITheme.INK_MID, 0.24)
	settings_language_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(settings_language_label)
	language_selector = OptionButton.new()
	language_selector.alignment = HORIZONTAL_ALIGNMENT_CENTER
	language_selector.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	language_selector.add_item(tr("SETTINGS_ENGLISH"))
	language_selector.set_item_metadata(0, "en")
	language_selector.add_item(tr("SETTINGS_KOREAN"))
	language_selector.set_item_metadata(1, "ko")
	_style_text_action(language_selector, 20.0, UITheme.INK_HIGH)
	language_selector.item_selected.connect(_on_language_selected)
	column.add_child(language_selector)
	settings_hint = _spec_label(tr("SETTINGS_LANGUAGE_HINT"), UITheme.sans("light"), 14.0, UITheme.INK_LOW)
	settings_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(settings_hint)

	tutorial_replay_button = Button.new()
	tutorial_replay_button.text = tr("TUTORIAL_REPLAY")
	tutorial_replay_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_text_action(tutorial_replay_button, 18.0, UITheme.INK_HIGH)
	tutorial_replay_button.pressed.connect(func(): tutorial_replay_requested.emit())
	column.add_child(tutorial_replay_button)
	save_management_button = Button.new()
	save_management_button.text = tr("SETTINGS_SAVE_MANAGEMENT")
	save_management_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_text_action(save_management_button, 18.0, UITheme.INK_HIGH)
	save_management_button.pressed.connect(_on_save_management_pressed)
	column.add_child(save_management_button)

	save_management_container = VBoxContainer.new()
	save_management_container.add_theme_constant_override("separation", int(UITheme.px(10.0)))
	save_management_container.visible = false
	column.add_child(save_management_container)
	save_management_container.add_child(_hairline(840.0))
	save_section_label = _spec_label(tr("SAVE_SECTION_TITLE"), UITheme.mono(), 12.0, UITheme.INK_MID, 0.24)
	save_section_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	save_management_container.add_child(save_section_label)
	for slot in range(1, 4):
		_build_save_slot_row(save_management_container, slot)
	save_feedback = _spec_label(tr("SAVE_SECTION_HINT"), UITheme.sans("light"), 13.0, UITheme.INK_LOW)
	save_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	save_feedback.visible = false
	save_management_container.add_child(save_feedback)

	settings_close_button = Button.new()
	settings_close_button.text = tr("SETTINGS_CLOSE")
	settings_close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_text_action(settings_close_button, 20.0, UITheme.BANNER_TITLE)
	settings_close_button.pressed.connect(close_settings)
	column.add_child(settings_close_button)
	overwrite_dialog = ConfirmationDialog.new()
	overwrite_dialog.title = tr("SAVE_OVERWRITE_TITLE")
	overwrite_dialog.ok_button_text = tr("SAVE_OVERWRITE_CONFIRM")
	overwrite_dialog.cancel_button_text = tr("SAVE_CANCEL")
	overwrite_dialog.confirmed.connect(_on_overwrite_confirmed)
	settings_overlay.add_child(overwrite_dialog)
	_style_confirm_dialog(overwrite_dialog)


func _build_save_slot_row(parent: VBoxContainer, slot: int) -> void:
	# A row of type on the sky, separated by a hairline, rather than a card.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(UITheme.px(18.0)))
	parent.add_child(row)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_theme_constant_override("separation", int(UITheme.px(3.0)))
	row.add_child(info)
	var title := _spec_label(tr("SAVE_SLOT_TITLE") % slot, UITheme.sans(), 17.0, UITheme.INK_HIGH)
	var details := _spec_label(tr("SAVE_SLOT_EMPTY"), UITheme.mono(), 12.0, UITheme.INK_LOW, 0.06)
	details.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.add_child(title)
	info.add_child(details)
	var save_button := Button.new()
	save_button.text = tr("SAVE_ACTION")
	_style_text_action(save_button, 15.0, UITheme.INK_HIGH)
	save_button.pressed.connect(_on_save_slot_pressed.bind(slot))
	row.add_child(save_button)
	var load_button := Button.new()
	load_button.text = tr("LOAD_ACTION")
	_style_text_action(load_button, 15.0, UITheme.INK_HIGH)
	load_button.disabled = true
	load_button.pressed.connect(_on_load_slot_pressed.bind(slot))
	row.add_child(load_button)
	var reset_button := Button.new()
	reset_button.text = tr("SAVE_RESET_ACTION")
	# Destructive, so it takes the one saturated ink in the palette instead of a
	# red box the red-light layer cannot spare.
	_style_text_action(reset_button, 15.0, UITheme.GAIN)
	reset_button.pressed.connect(_on_reset_slot_pressed.bind(slot))
	reset_button.visible = false
	row.add_child(reset_button)
	parent.add_child(_hairline(840.0))
	save_slot_titles.append(title)
	save_slot_details.append(details)
	save_slot_buttons.append(save_button)
	load_slot_buttons.append(load_button)
	reset_slot_buttons.append(reset_button)


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _panel_style(background: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style
