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
	_set_label_text(clock_label, "%02d:%02d" % [int(remaining) / 60, int(remaining) % 60])
	_set_label_text(earned_label, "%d" % int(probe.data_earned))
	_set_label_text(missed_label, "−%d" % int(probe.data_missed))
	var missed_alpha := 1.0 if probe.data_missed > 0.0 else 0.35
	if not is_equal_approx(missed_label.modulate.a, missed_alpha):
		missed_label.modulate.a = missed_alpha

	var instrument_lines: Array[String] = []
	for index in range(probe.instruments.size()):
		var instrument: Dictionary = probe.instruments[index]
		var state := "IDLE"
		if int(instrument.assigned_id) != -1:
			state = "ON #%d" % int(instrument.assigned_id) if bool(instrument.arrived) else "SLEWING → #%d" % int(instrument.assigned_id)
		instrument_lines.append("DISH %d    %s" % [index + 1, state])
	_set_label_text(instrument_label, "\n".join(instrument_lines))

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
	_set_label_text(queue_label, "\n".join(queue_lines) if not queue_lines.is_empty() else "NO CONTACTS")


func _set_label_text(label: Label, next_text: String) -> void:
	# Label assignment invalidates text shaping and container layout. Most probe
	# values are unchanged between HUD ticks, so keep the cached layout intact.
	if label.text != next_text:
		label.text = next_text


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
	var view = preload("res://scenes/ui/probe_hud.tscn").instantiate()
	root_control = view
	earned_label = view.get_node("%EarnedLabel")
	missed_label = view.get_node("%MissedLabel")
	clock_label = view.get_node("%ClockLabel")
	instrument_label = view.get_node("%InstrumentLabel")
	queue_label = view.get_node("%QueueLabel")
	hint_label = view.get_node("%HintLabel")
	summary_overlay = view.get_node("%SummaryOverlay")
	summary_label = view.get_node("%SummaryLabel")
	add_child(view)
