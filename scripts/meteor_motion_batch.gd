extends RefCounted

# No node access in this numerical stage. The caller snapshots and commits in
# simulation-ID order, using the same values as Meteor._update_burn_motion.
static func calculate(first: int, last: int, snapshots: Array) -> Array:
	var output: Array = []
	for index in range(first, last):
		var state: Dictionary = snapshots[index]
		var age: float = state.age + state.delta
		var progress := clampf(age / maxf(state.lifetime, 0.001), 0.0, 1.0)
		var ratio := clampf(state.terminal, 0.0, 1.0)
		var curve := (progress - (1.0 - ratio) * progress * progress * 0.5) / ((1.0 + ratio) * 0.5)
		var position: Vector2 = Vector2(state.entry).lerp(state.burnout, curve)
		var direction: Vector2 = (state.burnout - state.entry).normalized()
		if state.wobble > 0.0 and not direction.is_zero_approx():
			var instability := smoothstep(0.12, state.split, progress)
			var endpoint_taper := sin(PI * progress)
			var oscillation := 0.62 * sin(age * state.frequency + state.phase) + 0.38 * sin(age * state.frequency * 1.71 + state.phase * 1.7)
			position += Vector2(-direction.y, direction.x) * (oscillation * state.wobble * instability * endpoint_taper)
		if state.delta <= 0.0: position = state.position
		var velocity: Vector2 = (position - state.position) / state.delta if state.delta > 0.000001 else state.velocity
		var travel: Vector2 = velocity.normalized() if state.delta > 0.000001 and not velocity.is_zero_approx() else state.travel
		output.append({"age": age, "position": position, "velocity": velocity, "travel": travel})
	return output
