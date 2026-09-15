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

func advance(delta: float) -> void:
	age += delta
	visual_time += delta * motion_scale
	if age >= LIFETIME:
		hide()
		queue_free()
		return
	present()

func present() -> void:
	modulate.a = smoothstep(0.0, 0.6, age) * (1.0 - smoothstep(LIFETIME - 1.2, LIFETIME, age))
	emission.material.set_shader_parameter("visual_time", visual_time)
	emission.material.set_shader_parameter("motion", motion_scale)
	emission.material.set_shader_parameter("pulses", 1.0 if flashes_enabled else 0.0)
	emission.material.set_shader_parameter("effect_mode", effect_mode)
