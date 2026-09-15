extends Node2D

@onready var emission: Sprite2D = $Emission

func present(visual_scale: float, alpha: float, phase: float, motion: float, flashes: bool) -> void:
	scale = Vector2.ONE * visual_scale
	modulate.a = alpha
	visible = alpha > 0.001
	emission.material.set_shader_parameter("phase", phase)
	emission.material.set_shader_parameter("motion", motion)
	emission.material.set_shader_parameter("pulses", 1.0 if flashes else 0.0)
