extends RefCounted

# Main-thread transient motion. The capture keeps no reference to its source,
# so completing/freeing a black hole cannot cancel or dangle a moving target.
const PULL_SECONDS := 0.85
const SLOW_SECONDS := 1.0
const SLOW_SCALE := 0.25
var elapsed := 0.0
var start := Vector2.ZERO
var destination := Vector2.ZERO
var released := false
var slow_seconds := SLOW_SECONDS

func configure(target: Node2D, centre: Vector2, world_scale: float, extra_slow_seconds: float = 0.0) -> void:
	slow_seconds = SLOW_SECONDS + maxf(0.0, extra_slow_seconds)
	start = target.position
	var offset := start - centre
	var distance := offset.length()
	# Keep large surfaces outside the centre and preserve their angular spacing.
	var body_extent: float = target.get_observation_body_radius()
	var landing := minf(distance, (25.0 + float(target.simulation_id % 5) * 6.0) * world_scale + body_extent)
	destination = centre + offset.normalized() * landing

func advance(target: Node2D, delta: float) -> bool:
	var previous := target.position
	var before := elapsed
	elapsed += delta
	if elapsed < PULL_SECONDS:
		target.position = start.lerp(destination, smoothstep(0.0, PULL_SECONDS, elapsed))
	else:
		if not released:
			# Shift both path anchors at the same age instead of snapping back to
			# the pre-capture analytic path on the following tick.
			target._update_burn_motion(0.0)
			var shift: Vector2 = destination - target.position
			target.entry_position += shift
			target.burnout_position += shift
			target.position = destination
			released = true
		var slow_delta := maxf(0.0, minf(elapsed, PULL_SECONDS + slow_seconds) - maxf(before, PULL_SECONDS))
		var normal_delta := maxf(0.0, elapsed - maxf(before, PULL_SECONDS + slow_seconds))
		target.age += slow_delta * SLOW_SCALE + normal_delta
		target._update_burn_motion(delta)
	if delta > 0.000001:
		target.velocity = (target.position - previous) / delta
		if not target.velocity.is_zero_approx(): target.travel_direction = target.velocity.normalized()
	return elapsed >= PULL_SECONDS + slow_seconds
