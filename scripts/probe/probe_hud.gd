extends CanvasLayer

# Probe HUD. "Missed" is deliberately the loudest number on screen: the
# question this probe answers is whether giving something up registers.

var probe: Node2D
var root_control: Control
var earned_label: Label
var missed_label: Label
var clock_label: Label
var instrument_label: Label
var queue_label: Label
var hint_label: Label
var summary_overlay: Control
var summary_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func bind_probe(controller: Node2D) -> void:
	probe = controller
	refresh()


func refresh() -> void:
	if probe == null:
		return
	var remaining: float = maxf(0.0, probe.PROBE_DURATION - probe.elapsed)
	clock_label.text = "%02d:%02d" % [int(remaining) / 60, int(remaining) % 60]
	earned_label.text = "%d" % int(probe.data_earned)
	missed_label.text = "−%d" % int(probe.data_missed)
	missed_label.modulate.a = 1.0 if probe.data_missed > 0.0 else 0.35

	var instrument_lines: Array[String] = []
	for index in range(probe.instruments.size()):
		var instrument: Dictionary = probe.instruments[index]
		var state := "IDLE"
		if int(instrument.assigned_id) != -1:
			state = "ON #%d" % int(instrument.assigned_id) if bool(instrument.arrived) else "SLEWING → #%d" % int(instrument.assigned_id)
		instrument_lines.append("DISH %d    %s" % [index + 1, state])
	instrument_label.text = "\n".join(instrument_lines)

	var queue_lines: Array[String] = []
	for contact in probe.signals:
		if contact.spawned:
			continue
		var contact_name: String = "UNCLASSIFIED" if not contact.classified else String(probe._short_type_name(contact.type_id))
		var covered := false
		for instrument in probe.instruments:
			if int(instrument.assigned_id) == contact.id:
				covered = true
				break
		queue_lines.append("%s  #%d  %-13s  %.1fs" % ["●" if covered else "○", contact.id, contact_name, maxf(0.0, contact.countdown)])
	queue_label.text = "\n".join(queue_lines) if not queue_lines.is_empty() else "NO CONTACTS"


func show_summary() -> void:
	if probe == null:
		return
	var total: int = probe.observed_count + probe.missed_count
	summary_label.text = "\n".join([
		"90 SECONDS",
		"",
		"OBSERVED        %d / %d   (%d%%)" % [probe.observed_count, total, int(round(probe.coverage_ratio() * 100.0))],
		"BY HAND         %d" % probe.manual_count,
		"BY DISH         %d" % probe.instrument_count_observed,
		"",
		"DATA EARNED     %d" % int(probe.data_earned),
		"DATA MISSED     %d" % int(probe.data_missed),
		"",
		"[R] RUN AGAIN",
	])
	summary_overlay.visible = true


func hide_summary() -> void:
	summary_overlay.visible = false


func _build() -> void:
	root_control = Control.new()
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root_control)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Pretendard", "Noto Sans CJK KR", "Malgun Gothic", "Segoe UI"])
	root_control.add_theme_font_override("font", font)

	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_LEFT)
	top.offset_left = 22.0
	top.offset_top = 16.0
	top.add_theme_constant_override("separation", 34)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(top)
	top.add_child(_stat_column("EARNED", "0", 30, Color("8fffe5"), true))
	top.add_child(_stat_column("MISSED", "−0", 30, Color("ff7a6d"), false))
	top.add_child(_stat_column("REMAINING", "01:30", 24, Color("bcd6e8"), false))

	instrument_label = _label("", 13, Color("9fe0cf"))
	instrument_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	instrument_label.offset_left = 22.0
	instrument_label.offset_top = -76.0
	instrument_label.offset_right = 320.0
	instrument_label.offset_bottom = -26.0
	root_control.add_child(instrument_label)

	queue_label = _label("", 13, Color("cfe0f0"))
	queue_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	queue_label.offset_left = -290.0
	queue_label.offset_top = 20.0
	queue_label.offset_right = -20.0
	queue_label.offset_bottom = 260.0
	root_control.add_child(queue_label)

	hint_label = _label("CLICK A SIGNAL TO COMMIT A DISH    ·    HOLD LMB TO OBSERVE BY HAND", 13, Color("7d94a8"))
	hint_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint_label.offset_top = -34.0
	hint_label.offset_bottom = -12.0
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_control.add_child(hint_label)

	summary_overlay = Control.new()
	summary_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	summary_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	summary_overlay.visible = false
	root_control.add_child(summary_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.002, 0.007, 0.02, 0.9)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	summary_overlay.add_child(dim)
	summary_label = _label("", 19, Color("dceefc"))
	summary_label.set_anchors_preset(Control.PRESET_CENTER)
	summary_label.offset_left = -230.0
	summary_label.offset_top = -170.0
	summary_label.offset_right = 230.0
	summary_label.offset_bottom = 170.0
	summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	summary_overlay.add_child(summary_label)


func _stat_column(caption: String, value: String, size: int, color: Color, is_earned: bool) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", -2)
	column.add_child(_label(caption, 10, Color("6f8ba0")))
	var value_label := _label(value, size, color)
	column.add_child(value_label)
	if is_earned:
		earned_label = value_label
	elif caption == "MISSED":
		missed_label = value_label
	else:
		clock_label = value_label
	return column


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
