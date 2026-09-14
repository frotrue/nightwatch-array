extends RefCounted

# Procedural celestial art: opaque photosphere, warm corona and slow prominences.
# The transient shockwave uses the source's existing completion lifetime.
static func draw(body: Node2D, radius: float, visibility: float) -> void:
	var age: float = body.age
	var phase: float = body.wobble_phase
	if body.observed_successfully and not body.alive:
		var progress := 1.0 - visibility
		var reach: float = body.supernova_radius
		var motion: float = body.completion_motion_scale
		if motion > 0.0 and reach > 0.0:
			var wave := lerpf(radius, reach, ease(clampf(progress / 0.8, 0.0, 1.0), 0.65))
			body.draw_arc(Vector2.ZERO, wave, 0.0, TAU, 96, Color("ffb76a", visibility * 0.65 * motion), 2.5, true)
			body.draw_arc(Vector2.ZERO, wave * 0.94, 0.0, TAU, 96, Color("ed7541", visibility * 0.22 * motion), 6.0, true)
			for i in 18:
				var direction := Vector2.RIGHT.rotated(TAU * i / 18.0 + phase)
				var tip := direction * wave * (0.7 + 0.16 * sin(i * 2.4))
				body.draw_line(tip * 0.83, tip, Color("ffd396", visibility * 0.65 * motion), 1.5, true)
		var core := radius * maxf(0.0, 1.0 - progress * 2.8)
		if core > 0.0:
			var tint := Color("fff1c7") if body.completion_glint_enabled else Color("e7934e")
			body.draw_circle(Vector2.ZERO, core, Color(tint, visibility), true, -1.0, true)
		return
	for layer in range(5, 0, -1):
		body.draw_circle(Vector2.ZERO, radius * (1.0 + layer * 0.10), Color("ef8139", visibility * 0.025), true, -1.0, true)
	for i in 9:
		var angle := TAU * i / 9.0 + phase + age * 0.025
		var direction := Vector2.RIGHT.rotated(angle)
		var height := radius * (0.15 + 0.045 * sin(age * 1.3 + i))
		var loop := PackedVector2Array()
		for j in 13:
			var t := float(j) / 12.0
			loop.append(direction.rotated((t - 0.5) * 0.20) * (radius * 0.98 + sin(t * PI) * height))
		body.draw_polyline(loop, Color("f18d40", visibility * 0.58), 1.4, true)
	body.draw_circle(Vector2.ZERO, radius, Color("db7131", visibility), true, -1.0, true)
	# Concentric shading keeps the edge dimmer than the warm centre.
	for layer in range(12, 0, -1):
		var fraction := float(layer) / 12.0
		var tint := Color("fff1bd").lerp(Color("e99946"), fraction * fraction)
		body.draw_circle(Vector2(-0.04, -0.04) * radius, radius * fraction * 0.95, Color(tint, visibility), true, -1.0, true)
	for i in 46:
		var angle := i * 2.399963 + phase + age * 0.035
		var distance := sqrt(float(i + 1) / 47.0) * radius * 0.86
		var centre := Vector2.RIGHT.rotated(angle) * distance
		var shimmer := 0.5 + 0.5 * sin(age * 0.8 + i * 1.7)
		body.draw_circle(centre, radius * (0.025 + shimmer * 0.012), Color("c97131", visibility * 0.17), true, -1.0, true)
