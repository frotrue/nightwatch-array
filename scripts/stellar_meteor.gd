extends "res://scripts/meteor.gd"

signal remnant_requested(source)
var remnant_pending := false

func tick_motion(delta: float, tick_id: int) -> void:
	if remnant_pending and observed_successfully:
		simulation_tick = tick_id
		linger_time = maxf(0.0, linger_time - delta)
		return
	super.tick_motion(delta, tick_id)

func tick_resolve() -> void:
	super.tick_resolve()
	if remnant_pending and observed_successfully and linger_time <= 0.00001 and not is_queued_for_deletion():
		remnant_pending = false
		# Retire the parent reservation before admitting its child in resolve.
		hide()
		queue_free()
		remnant_requested.emit(self)
