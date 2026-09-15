extends Node2D

@onready var background_copy: BackBufferCopy = $BackgroundCopy
@onready var lens: Sprite2D = $Lens
# Slots follow the authored copy/lens draw order. Single-lens diagnostics keep
# using the first pair; freed slots can be reused without changing that order.
@onready var lenses: Array[Sprite2D] = [$Lens, $Lens2, $Lens3]
@onready var background_copies: Array[BackBufferCopy] = [$BackgroundCopy, $BackgroundCopy2, $BackgroundCopy3]
var targets: Array[Node2D] = [null, null, null]
var target: Node2D:
	get:
		for body in targets:
			if is_instance_valid(body): return body
		return null
var motion_scale := 1.0
const EXTENT_RADII := 5.0
const EINSTEIN_RADIUS := 0.34
const TAPER_START := 0.6

# Invert the shader's radial sampling for the primary visible image. Tick
# endpoints use tick poses; cursor/beam presentation uses interpolated poses.
func project_position(point: Vector2, fraction: float) -> Vector2:
	# Each shader samples the previous pass. Apply primary-image projections in
	# the same forward order so overlapping lenses keep manual contacts aligned.
	if motion_scale <= 0.0: return point
	for body in targets:
		if is_instance_valid(body): point = _project_one(point, fraction, body)
	return point

func _project_one(point: Vector2, fraction: float, body: Node2D) -> Vector2:
	if not is_instance_valid(body) or motion_scale <= 0.0 or not body.is_visible_in_tree(): return point
	var centre: Vector2 = body.previous_simulation_position.lerp(body.global_position, fraction)
	var extent: float = body.body_radius * body._head_scale() * body._current_visual_scale() * EXTENT_RADII
	var offset := point - centre
	var distance := offset.length()
	if distance >= extent or distance < 0.001: return point
	var visibility: float = body.get_burn_visibility() if body.alive else clampf(body.linger_time / maxf(body.linger_duration, 0.001), 0.0, 1.0)
	var strength := clampf(motion_scale, 0.0, 1.0) * visibility
	if strength <= 0.0: return point
	var source_radius := distance / extent
	var low := source_radius
	var high := 1.0
	for iteration in 14:
		var radius := (low + high) * 0.5
		var bend := EINSTEIN_RADIUS * EINSTEIN_RADIUS / maxf(radius, 0.12) * (1.0 - smoothstep(TAPER_START, 1.0, radius))
		if radius - bend * strength < source_radius: low = radius
		else: high = radius
	return centre + offset / distance * ((low + high) * 0.5 * extent)

func _ready() -> void:
	for view in lenses:
		view.material.set_shader_parameter("einstein_radius", EINSTEIN_RADIUS)
		view.material.set_shader_parameter("taper_start", TAPER_START)
	set_process(false)

func track(body: Node2D) -> void:
	if body in targets: return
	for slot in targets.size():
		if is_instance_valid(targets[slot]): continue
		targets[slot] = body
		body.tree_exiting.connect(_release.bind(body), CONNECT_ONE_SHOT)
		set_process(true)
		_process(0.0)
		return
	push_error("Black hole lens capacity exceeded")

func _release(body: Node2D) -> void:
	var slot := targets.find(body)
	if slot < 0: return
	targets[slot] = null
	lenses[slot].hide()
	background_copies[slot].copy_mode = BackBufferCopy.COPY_MODE_DISABLED
	set_process(target != null)

func _process(_delta: float) -> void:
	for slot in targets.size():
		if is_instance_valid(targets[slot]):
			_present(targets[slot], lenses[slot], background_copies[slot])

func _present(body: Node2D, view: Sprite2D, copy: BackBufferCopy) -> void:
	view.global_position = body.get_display_position() if body.is_physics_interpolated_and_enabled() else body.global_position
	var radius: float = body.body_radius * body._head_scale() * body._current_visual_scale()
	view.scale = Vector2.ONE * radius * EXTENT_RADII
	var canvas_scale := get_viewport().get_canvas_transform().get_scale()
	var viewport_size := get_viewport_rect().size
	var extent := Vector2.ONE * radius * EXTENT_RADII * canvas_scale
	var screen_position := get_viewport().get_canvas_transform() * view.global_position
	var on_screen := Rect2(-extent, viewport_size + extent * 2.0).has_point(screen_position)
	view.visible = body.is_visible_in_tree() and on_screen and motion_scale > 0.0
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT if view.visible else BackBufferCopy.COPY_MODE_DISABLED
	if not view.visible: return
	var visibility: float = body.get_burn_visibility() if body.alive else clampf(body.linger_time / maxf(body.linger_duration, 0.001), 0.0, 1.0)
	view.material.set_shader_parameter("screen_extent", extent / viewport_size)
	view.material.set_shader_parameter("visibility", visibility)
	view.material.set_shader_parameter("strength", clampf(motion_scale, 0.0, 1.0))
