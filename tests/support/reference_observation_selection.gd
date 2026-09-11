extends "res://scripts/observation_controller.gd"

# Pre-optimization selection oracle. Keep this pass independent so the
# threaded parity gate detects changes to latch/grace, ties and target order.
func _update_manual_tracking(delta: float, keep_primary: bool = false) -> bool:
	tracked_meteors.clear()
	# Retain each buffered segment origin for fast press-and-drag motion.
	if not _selection_is_valid():
		selected_meteor = _find_target_under_cursor()
		if _selection_is_valid():
			tracking_grace_remaining = _tracking_grace()
	if not _selection_is_valid():
		return false

	var primary = selected_meteor
	# Synchronous completion can release selected_meteor during this pass. Keep
	# the primary role stable so same-frame completions cannot shift the
	# remaining correlation modifiers between recipients.
	_manual_frame_active = true
	_manual_frame_primary = primary
	var tracking_radius: float = _tracking_radius_for(primary)
	var current_distance: float = _target_contact_distance(primary, cursor_position)
	if _apply_manual_contact(primary, delta):
		tracking_grace_remaining = _tracking_grace()
		_append_tracked_if_valid(primary)
	elif current_distance <= tracking_radius * TRACKING_BREAK_MULTIPLIER:
		# The soft outer ring pauses progress but keeps the target latched.
		tracking_grace_remaining = _tracking_grace()
	else:
		tracking_grace_remaining -= delta
		if tracking_grace_remaining <= 0.0:
			selected_meteor = null

	if _manual_target_limit() > 1:
		_observe_additional_targets(delta, primary)
		var closest_tracked = _closest_valid_tracked_target()
		if closest_tracked != null and (not keep_primary or not _selection_is_valid()):
			selected_meteor = closest_tracked
	_manual_frame_active = false
	_manual_frame_primary = null
	return true
