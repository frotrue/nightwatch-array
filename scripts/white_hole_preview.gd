extends Node2D

# An authored, local effect for art iteration. This is deliberately not a Meteor:
# it has no observation, reward, gravity, RNG or save participation.
const LIFETIME := 16.0
const EXTENT := 150.0
var age := 0.0
var visual_time := 0.0
var motion_scale := 1.0
var flashes_enabled := true
var effect_mode := 0
@onready var emission: Sprite2D = $Emission
@onready var background_copy: BackBufferCopy = $BackgroundCopy
@onready var lensed_sky: Sprite2D = $LensedSky

func advance(delta: float) -> void:
	age += delta
	visual_time += delta * motion_scale
	if age >= LIFETIME:
		hide()
		background_copy.copy_mode = BackBufferCopy.COPY_MODE_DISABLED
		queue_free()
		return
	present()

func present() -> void:
	modulate.a = smoothstep(0.0, 0.6, age) * (1.0 - smoothstep(LIFETIME - 1.2, LIFETIME, age))
	emission.material.set_shader_parameter("visual_time", visual_time)
	emission.material.set_shader_parameter("motion", motion_scale)
	emission.material.set_shader_parameter("pulses", 1.0 if flashes_enabled else 0.0)
	emission.material.set_shader_parameter("effect_mode", effect_mode)
	_refresh_lens()

func _process(_delta: float) -> void:
	# Camera/viewport changes are presentation work; optical time stays on ticks.
	_refresh_lens()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_node_ready(): _refresh_lens()

func _refresh_lens() -> void:
	var screen_transform := get_global_transform_with_canvas()
	var extent := Vector2.ONE * EXTENT * screen_transform.get_scale().abs()
	var viewport_size := get_viewport_rect().size
	var on_screen := Rect2(-extent, viewport_size + extent * 2.0).has_point(screen_transform.origin)
	lensed_sky.visible = is_visible_in_tree() and on_screen and motion_scale > 0.0 and modulate.a > 0.001
	background_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT if lensed_sky.visible else BackBufferCopy.COPY_MODE_DISABLED
	if not lensed_sky.visible: return
	# Absolute z = -18 puts both optical nodes after the sky and before every
	# meteor/instrument. Real targets retain their rendered observation centres.
	lensed_sky.material.set_shader_parameter("screen_extent", extent / viewport_size)
	lensed_sky.material.set_shader_parameter("visibility", modulate.a)
	lensed_sky.material.set_shader_parameter("strength", motion_scale * 0.8)
