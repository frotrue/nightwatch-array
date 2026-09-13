extends Node2D

@onready var background_copy: BackBufferCopy = $BackgroundCopy
@onready var lens: Sprite2D = $Lens
var target: Node2D
var motion_scale := 1.0

func _ready() -> void:
	set_process(false)

func track(body: Node2D) -> void:
	target = body
	body.tree_exiting.connect(_release.bind(body), CONNECT_ONE_SHOT)
	set_process(true)
	_process(0.0)

func _release(body: Node2D) -> void:
	if target != body: return
	target = null
	lens.hide()
	background_copy.copy_mode = BackBufferCopy.COPY_MODE_DISABLED
	set_process(false)

func _process(_delta: float) -> void:
	if not is_instance_valid(target): return
	lens.global_position = target.get_display_position() if target.is_physics_interpolated_and_enabled() else target.global_position
	var radius: float = target.body_radius * target._head_scale() * target._current_visual_scale()
	lens.scale = Vector2.ONE * radius * 3.0
	var canvas_scale := get_viewport().get_canvas_transform().get_scale()
	var viewport_size := get_viewport_rect().size
	var extent := Vector2.ONE * radius * 3.0 * canvas_scale
	var screen_position := get_viewport().get_canvas_transform() * lens.global_position
	var on_screen := Rect2(-extent, viewport_size + extent * 2.0).has_point(screen_position)
	lens.visible = target.is_visible_in_tree() and on_screen and motion_scale > 0.0
	background_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT if lens.visible else BackBufferCopy.COPY_MODE_DISABLED
	if not lens.visible: return
	var visibility: float = target.get_burn_visibility() if target.alive else clampf(target.linger_time / maxf(target.linger_duration, 0.001), 0.0, 1.0)
	lens.material.set_shader_parameter("screen_extent", extent / viewport_size)
	lens.material.set_shader_parameter("visibility", visibility)
	lens.material.set_shader_parameter("strength", clampf(motion_scale, 0.0, 1.0))
