extends Node2D

@onready var background_copy: BackBufferCopy = $BackgroundCopy
@onready var haze: Sprite2D = $HeatHaze
@onready var photosphere: Sprite2D = $Photosphere
var heat_enabled := true

func conceal() -> void:
	hide()
	background_copy.copy_mode = BackBufferCopy.COPY_MODE_DISABLED

func present(radius: float, alpha: float, age: float, phase: float, progress: float, motion: float, flashes: bool, tint: Color) -> void:
	photosphere.scale = Vector2.ONE * radius * 1.8
	haze.scale = photosphere.scale
	visible = alpha > 0.0
	photosphere.self_modulate = Color(tint, tint.a * alpha)
	var visual_age := age * clampf(motion, 0.0, 1.0)
	photosphere.material.set_shader_parameter("age", visual_age)
	photosphere.material.set_shader_parameter("phase", phase)
	photosphere.material.set_shader_parameter("charge", progress)
	photosphere.material.set_shader_parameter("motion", clampf(motion, 0.0, 1.0))
	photosphere.material.set_shader_parameter("pulses", 1.0 if flashes else 0.0)
	var screen_transform := get_global_transform_with_canvas()
	var extent := Vector2.ONE * radius * 2.0 * screen_transform.get_scale().abs()
	var on_screen := Rect2(-extent, get_viewport_rect().size + extent * 2.0).has_point(screen_transform.origin)
	haze.visible = is_visible_in_tree() and on_screen and motion > 0.0 and heat_enabled
	# The effect samples only its local halo, but refresh the entire shared
	# backbuffer so this remains stable beside the black hole's screen shader.
	# Completion, reduced motion and off-screen stars need no screen copy.
	background_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT if haze.visible else BackBufferCopy.COPY_MODE_DISABLED
	if not haze.visible: return
	haze.material.set_shader_parameter("age", visual_age)
	haze.material.set_shader_parameter("phase", phase)
	haze.material.set_shader_parameter("strength", motion * alpha * tint.a)
	haze.material.set_shader_parameter("charge", progress)
	haze.material.set_shader_parameter("pixel_scale", clampf(radius * screen_transform.get_scale().length() / 46.0, 0.6, 2.0))
