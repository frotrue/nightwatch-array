extends Node2D

@onready var mineral: Sprite2D = $Mineral

func present(body: Node2D, screen_scale: float, direction: Vector2, alpha: float) -> void:
	visible = body.age >= body.warning_time and alpha > 0.0
	if not visible:
		return
	scale = Vector2.ONE * screen_scale
	rotation = direction.angle()
	mineral.self_modulate = Color(body.self_modulate, body.self_modulate.a * alpha)
	var effects: Node = body.research.game.effects
	var motion: float = clampf(effects.motion_intensity, 0.0, 1.0)
	var surface: ShaderMaterial = mineral.material
	# Derive a stable variation from the existing ticket, without consuming game RNG
	# or adding visual state to the save format. Animation follows simulation time.
	var phase := float(hash(body.reward_ticket_id) % 4096) / 4096.0 * TAU
	surface.set_shader_parameter("age", body.age * motion)
	surface.set_shader_parameter("phase", phase)
	surface.set_shader_parameter("charge", body.stage_progress)
	surface.set_shader_parameter("completion", 1.0 - alpha if not body.alive and body.stage_progress >= 1.0 else 0.0)
	surface.set_shader_parameter("motion", motion)
	surface.set_shader_parameter("flashes", 1.0 if effects.screen_flashes_enabled else 0.0)
