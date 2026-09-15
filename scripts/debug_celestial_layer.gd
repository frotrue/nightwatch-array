extends Node2D

const WhiteHole = preload("res://scenes/white_hole_preview.tscn")
const MAX_PREVIEWS := 3
var effect_mode := 0
var motion_scale := 1.0
var flashes_enabled := true

func spawn_observable_white_hole(world_position: Vector2, world_unit: float) -> Node2D:
	var game = get_parent()
	# Pick one heading at birth without consuming any of the run's RNG streams.
	var angle := float(game.spawner.next_simulation_id) * 2.399963
	var direction := Vector2(cos(angle), sin(angle) * 0.35).normalized()
	var body = game.spawner.spawn_meteor("white_hole", world_position, direction * 22.0 * world_unit)
	if body != null: body.preview_mode = effect_mode
	return body

# Standalone optical fixture retained for comparing the two materials without
# spawning gameplay targets. The game shortcut uses the observable path above.
func spawn_white_hole(world_position: Vector2, world_unit: float) -> Node2D:
	var count := 0
	for body in get_children():
		if not body.is_queued_for_deletion(): count += 1
	if count >= MAX_PREVIEWS: return null
	var body := WhiteHole.instantiate()
	body.position = world_position
	body.scale = Vector2.ONE * world_unit
	body.effect_mode = effect_mode
	body.motion_scale = motion_scale
	body.flashes_enabled = flashes_enabled
	add_child(body)
	body.present()
	return body

func cycle_effect() -> void:
	effect_mode = (effect_mode + 1) % 2
	for body in get_parent().meteor_layer.get_children():
		if body.type_id == "white_hole":
			body.preview_mode = effect_mode
			body.queue_redraw()
	for body in get_children():
		body.effect_mode = effect_mode
		body.present()

func set_accessibility(motion: float, flashes: bool) -> void:
	motion_scale = clampf(motion, 0.0, 1.0)
	flashes_enabled = flashes
	for body in get_children():
		body.motion_scale = motion_scale
		body.flashes_enabled = flashes_enabled
		body.present()

func simulate_tick(delta: float) -> void:
	for body in get_children():
		if not body.is_queued_for_deletion(): body.advance(delta)

func reset() -> void:
	for body in get_parent().meteor_layer.get_children():
		if body.type_id == "white_hole":
			body.get_parent().remove_child(body)
			body.queue_free()
	# Remove immediately from this diagnostic layer; queued old views cannot
	# remain visible for one frame or consume the next round's preview slots.
	for body in get_children():
		remove_child(body)
		body.queue_free()
