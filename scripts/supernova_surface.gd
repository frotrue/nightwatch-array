extends Node2D

@onready var ejecta: Sprite2D = $Ejecta

func present(radius: float, reach: float, progress: float, motion: float, flashes: bool, phase: float) -> void:
	var extent := maxf(radius, reach) * 1.1
	ejecta.scale = Vector2.ONE * extent
	visible = progress < 1.0
	ejecta.material.set_shader_parameter("progress", progress)
	ejecta.material.set_shader_parameter("initial_radius", radius / extent)
	ejecta.material.set_shader_parameter("motion", motion)
	ejecta.material.set_shader_parameter("flashes", 1.0 if flashes else 0.0)
	ejecta.material.set_shader_parameter("seed_phase", phase)
