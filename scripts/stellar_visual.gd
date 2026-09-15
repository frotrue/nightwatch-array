extends RefCounted

# The authored shader sprite owns the opaque, turbulent photosphere and corona.
# The transient shockwave uses the source's existing completion lifetime.
static func draw(body: Node2D, radius: float, visibility: float) -> void:
	var phase: float = body.wobble_phase
	var surface: Node2D = body.stellar_surface
	if body.observed_successfully and not body.alive:
		surface.conceal()
		body.supernova_surface.present(radius, body.supernova_radius, 1.0 - visibility,
			body.completion_motion_scale, body.completion_glint_enabled, phase)
		return
	body.supernova_surface.hide()
	surface.present(radius, visibility, body.age, phase, body.observation_progress,
		body.completion_motion_scale, body.completion_glint_enabled, body.self_modulate)
