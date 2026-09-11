extends Node2D

# Procedural geometry is transient game art, so the scene owns this layer while
# RenderingServer RIDs own its changing additive runs. No extra target children
# are introduced: gameplay continues to see exactly the authored meteor nodes.
var geometry: Dictionary = {}
var previous_transforms: Dictionary = {}
var index_cache: Dictionary = {}
var canvases: Array[RID] = []
var additive_material := CanvasItemMaterial.new()
var rendered_target_count := 0
var render_batch_count := 0
var rendered_vertex_count := 0
var vertices := PackedVector2Array()
var colors := PackedColorArray()
var indices := PackedInt32Array()


func _ready() -> void:
	# Capture the same previous pose as Godot's CanvasItem interpolation, before
	# Game advances the tick. Frames without motion (including pauses) converge
	# to the current pose instead of replaying the last gameplay displacement.
	# The engine advances interpolation even when scene processing is paused or
	# a preview disables _physics_process. Follow its pre-tick signal directly.
	get_tree().physics_frame.connect(_capture_previous_poses)
	additive_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	RenderingServer.frame_pre_draw.connect(_render_batches)
	child_exiting_tree.connect(_forget_target)


func _capture_previous_poses() -> void:
	for target in get_children():
		previous_transforms[target.get_instance_id()] = target.transform


func _forget_target(target: Node) -> void:
	geometry.erase(target.get_instance_id())
	previous_transforms.erase(target.get_instance_id())
	index_cache.erase(target.get_instance_id())


func reset_target_transform(target: Node2D) -> void:
	previous_transforms[target.get_instance_id()] = target.transform


func begin_target(target: Node2D) -> void:
	geometry.erase(target.get_instance_id())


func submit_target(target: Node2D, batch: RefCounted) -> void:
	if batch.indices.is_empty():
		return
	geometry[target.get_instance_id()] = {
		"vertices": batch.vertices, "colors": batch.colors, "indices": batch.indices,
	}


func _render_batches() -> void:
	if not is_inside_tree():
		return
	render_batch_count = 0
	rendered_target_count = 0
	rendered_vertex_count = 0
	vertices.clear()
	colors.clear()
	indices.clear()
	var run_start := 0
	var fraction := Engine.get_physics_interpolation_fraction()
	for target in get_children():
		var data: Dictionary = geometry.get(target.get_instance_id(), {})
		# An opaque asteroid/planet is a strict order boundary. Never collect light
		# from opposite sides of it into one batch, even if the material matches.
		if data.is_empty() or not target.visible:
			_flush_run(run_start)
			continue
		if indices.is_empty():
			run_start = target.get_index()
		var pose: Transform2D = target.transform
		if target.is_physics_interpolated_and_enabled():
			var previous: Transform2D = previous_transforms.get(target.get_instance_id(), pose)
			pose = previous.interpolate_with(pose, fraction)
		var offset := vertices.size()
		vertices.append_array(pose * (data.vertices as PackedVector2Array))
		colors.append_array(data.colors)
		var cached: Dictionary = index_cache.get(target.get_instance_id(), {})
		if cached.is_empty() or cached.offset != offset or cached.source != data.indices:
			var adjusted: PackedInt32Array = data.indices.duplicate()
			for i in adjusted.size():
				adjusted[i] += offset
			cached = {"offset": offset, "source": data.indices.duplicate(), "indices": adjusted}
			index_cache[target.get_instance_id()] = cached
		indices.append_array(cached.indices)
		rendered_target_count += 1
	_flush_run(run_start)
	while canvases.size() > render_batch_count:
		RenderingServer.free_rid(canvases.pop_back())


func _flush_run(draw_index: int) -> void:
	if indices.is_empty():
		return
	if render_batch_count == canvases.size():
		var canvas := RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(canvas, get_canvas_item())
		RenderingServer.canvas_item_set_material(canvas, additive_material.get_rid())
		canvases.append(canvas)
	var canvas := canvases[render_batch_count]
	RenderingServer.canvas_item_clear(canvas)
	RenderingServer.canvas_item_set_draw_index(canvas, draw_index)
	RenderingServer.canvas_item_add_triangle_array(canvas, indices, vertices, colors)
	rendered_vertex_count += vertices.size()
	render_batch_count += 1
	vertices.clear()
	colors.clear()
	indices.clear()


func _exit_tree() -> void:
	get_tree().physics_frame.disconnect(_capture_previous_poses)
	RenderingServer.frame_pre_draw.disconnect(_render_batches)
	for canvas in canvases:
		RenderingServer.free_rid(canvas)
	canvases.clear()
