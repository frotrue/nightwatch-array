extends RefCounted

# The authored shader sprite owns the opaque, turbulent photosphere and corona.
# The transient shockwave uses the source's existing completion lifetime.
static func draw(body: Node2D, radius: float, visibility: float) -> void:
	var phase: float = body.wobble_phase
	var surface: Node2D = body.stellar_surface
	if body.observed_successfully and not body.alive:
		surface.conceal()
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
	surface.present(radius, visibility, body.age, phase, body.observation_progress,
		body.completion_motion_scale, body.completion_glint_enabled, body.self_modulate)
