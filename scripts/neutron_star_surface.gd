extends Node2D

@onready var emission: Sprite2D = $Emission

func present(visual_scale: float, alpha: float, phase: float, motion: float, flashes: bool,
		age: float, axis: Vector3, beam_length: float, releasing: bool) -> void:
	scale = Vector2.ONE * visual_scale
	modulate.a = alpha
	visible = alpha > 0.001
	emission.material.set_shader_parameter("phase", phase)
	emission.material.set_shader_parameter("motion", motion)
	emission.material.set_shader_parameter("pulses", 1.0 if flashes else 0.0)
	emission.material.set_shader_parameter("emergence", 1.0 - smoothstep(0.08, 0.75, age))
	emission.material.set_shader_parameter("magnetic_axis", axis)
	emission.material.set_shader_parameter("beam_length", beam_length)
	emission.material.set_shader_parameter("release", 1.0 if releasing else 0.0)
