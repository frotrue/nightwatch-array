extends Node2D

@onready var clouds: Sprite2D = $Clouds

func present(body: Node2D, radius: float, alpha: float) -> void:
	visible = alpha > 0.0
	clouds.scale = Vector2.ONE * radius * 1.04
	clouds.self_modulate = Color(body.self_modulate, body.self_modulate.a * alpha)
	var motion: float = clampf(body.completion_motion_scale, 0.0, 1.0)
	var surface: ShaderMaterial = clouds.material
	surface.set_shader_parameter("age", body.age * motion)
	surface.set_shader_parameter("phase", body.wobble_phase)
	surface.set_shader_parameter("charge", body.observation_progress)
	surface.set_shader_parameter("completion", 1.0 - alpha if body.observed_successfully and not body.alive else 0.0)
	surface.set_shader_parameter("motion", motion)
	surface.set_shader_parameter("flashes", 1.0 if body.completion_glint_enabled else 0.0)
	surface.set_shader_parameter("primary", body.primary_color)
	surface.set_shader_parameter("glow", body.glow_color)
