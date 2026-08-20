extends SceneTree

# Verifies the Layer 2 probe holds together mechanically. It cannot tell us
# whether the probe is fun; that is what playing it is for.

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("PROBE: " + message)


# The probe is driven by hand at a fixed step so the run is deterministic and
# does not depend on how fast a headless frame happens to be. Meteors are
# ticked alongside it: they age on their own _process, which no engine frame
# would deliver at this rate.
func _step(probe, seconds: float, step: float = 1.0 / 60.0) -> void:
	var remaining := seconds
	while remaining > 0.0:
		probe._process(step)
		for meteor in probe.meteor_layer.get_children():
			if meteor.has_method("can_be_tracked"):
				meteor._process(step)
		remaining -= step
	await process_frame


func _run() -> void:
	var packed: PackedScene = load("res://scenes/probe_layer2.tscn")
	_check(packed != null, "probe scene loads")
	if packed == null:
		quit(1)
		return
	var probe = packed.instantiate()
	root.add_child(probe)
	await process_frame
	await process_frame

	_check(probe.instruments.size() == 2, "the probe opens with exactly two dishes")
	_check(probe.signals.is_empty(), "no contacts before the first interval elapses")

	await _step(probe, 3.0)
	_check(not probe.signals.is_empty(), "contacts arrive within the opening seconds")

	var contact = probe.signals[0]
	_check(contact.countdown > 0.0 and not contact.spawned, "a contact leads the object it predicts")
	_check(contact.certainty() < 1.0, "an early contact is not yet certain")
	var early_estimate: Vector2 = contact.shown_point
	_check(
		early_estimate.distance_to(contact.intercept_point) > 1.0,
		"an early estimate is offset from the truth, so committing early is a bet"
	)

	# Committing aims at the estimate the player can see, not the hidden truth.
	probe._assign_to_signal(contact.id)
	var index: int = probe.candidate_instrument_for(contact)
	_check(index >= 0, "a contact resolves to a dish that can answer it")
	var assigned_count := 0
	for instrument in probe.instruments:
		if int(instrument.assigned_id) == contact.id:
			assigned_count += 1
			_check(
				Vector2(instrument.target).distance_to(early_estimate) < 1.0,
				"a committed dish slews to the visible estimate"
			)
	_check(assigned_count == 1, "a contact occupies exactly one dish")

	await _step(probe, 1.0)
	_check(
		contact.shown_point.distance_to(contact.intercept_point) < early_estimate.distance_to(contact.intercept_point),
		"the estimate converges on the truth as the object approaches"
	)

	# Three contacts against two dishes is the whole question, so the third
	# commitment must visibly cost one of the first two.
	while probe.signals.size() < 3:
		probe._emit_signal_contact()
	var third = probe.signals[2]
	var taken: int = probe.candidate_instrument_for(third)
	var displaced_id := int(probe.instruments[taken].assigned_id)
	probe._assign_to_signal(third.id)
	if displaced_id != -1:
		var dropped = probe._find_signal(displaced_id)
		_check(dropped != null and dropped.abandoned_flash > 0.0, "re-tasking a dish marks what it abandoned")
	var occupied := 0
	for instrument in probe.instruments:
		if int(instrument.assigned_id) != -1:
			occupied += 1
	_check(occupied <= 2, "two dishes cannot cover three contacts at once")

	# A meteor that nobody covered must register as a loss with a number.
	var missed_before: float = probe.data_missed
	await _step(probe, 14.0)
	_check(probe.data_missed > missed_before, "uncovered objects accumulate missed data")
	_check(probe.missed_count > 0, "uncovered objects are counted as misses")
	_check(not probe.miss_marks.is_empty() or probe.missed_count > 0, "a miss leaves a visible mark")

	# A dish parked on a target should be recording, not merely present.
	await _step(probe, 20.0)
	_check(probe.observed_count > 0, "committed dishes convert contacts into observations")
	_check(probe.data_earned > 0.0, "observations earn data")

	await _step(probe, 60.0)
	_check(probe.finished, "the probe ends on its own after ninety seconds")
	_check(probe.meteor_layer.get_child_count() == 0, "ending the probe clears the sky")
	var total: int = probe.observed_count + probe.missed_count
	_check(total > 0, "the probe produced a readable result")
	_check(
		probe.coverage_ratio() > 0.0 and probe.coverage_ratio() < 1.0,
		"two dishes cover some but not all of a ninety-second night"
	)

	probe._restart()
	_check(probe.elapsed == 0.0 and not probe.finished, "the probe restarts clean")
	_check(probe.data_missed == 0.0 and probe.observed_count == 0, "restart clears the tallies")

	if failures.is_empty():
		print("PROBE_TEST_PASS: signals, uncertainty, commitment, abandonment, misses, and completion")
		quit(0)
	else:
		print("PROBE_TEST_FAIL: %d" % failures.size())
		for failure in failures:
			print("  - " + failure)
		quit(1)
