extends RefCounted

# The authored shader sprite owns the opaque, turbulent photosphere and corona.
# The transient shockwave uses the source's existing completion lifetime.
const COLLAPSE_FRACTION := 0.24
const CORE_SCALE := 0.16

static func draw(body: Node2D, radius: float, visibility: float) -> void:
	var phase: float = body.wobble_phase
	var surface: Node2D = body.stellar_surface
	if body.observed_successfully and not body.alive:
		var elapsed := 1.0 - visibility
		var motion := clampf(body.completion_motion_scale, 0.0, 1.0)
		var core_scale := lerpf(1.0, CORE_SCALE, motion)
		# A fixed completion beat remains readable even with very fast tracking.
		# Only presentation is delayed; the existing observation event stays immediate.
		if motion > 0.0 and elapsed < COLLAPSE_FRACTION:
			var collapse := smoothstep(0.0, COLLAPSE_FRACTION, elapsed)
			body.supernova_surface.hide()
			surface.present(radius * lerpf(1.0, core_scale, collapse), 1.0,
				body.age, phase, 1.0, motion, body.completion_glint_enabled,
				body.self_modulate, collapse, false)
			return
		surface.conceal()
		var burst := inverse_lerp(COLLAPSE_FRACTION, 1.0, elapsed) if motion > 0.0 else elapsed
		body.supernova_surface.present(radius * core_scale, body.supernova_radius, burst,
			body.completion_motion_scale, body.completion_glint_enabled, phase)
		return
	body.supernova_surface.hide()
	surface.present(radius, visibility, body.age, phase, body.observation_progress,
		body.completion_motion_scale, body.completion_glint_enabled, body.self_modulate)
