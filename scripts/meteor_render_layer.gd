extends Node2D

# Procedural light remains in native canvas buffers until its geometry changes.
# Each target owns one layer-managed RID: its interpolated transform is applied
# by the renderer, while native lines and opaque target children retain order.
var geometry: Dictionary = {}
var previous_transforms: Dictionary = {}
var retained_items: Dictionary = {}
var item_state: Dictionary = {}
var dirty_targets: Dictionary = {}
var additive_material := CanvasItemMaterial.new()
var rendered_target_count := 0
var render_batch_count := 0 # Retained light items, not measured GPU draw calls.
var rendered_vertex_count := 0
var geometry_upload_count := 0

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


func reset_target_transform(target: Node2D) -> void:
	previous_transforms[target.get_instance_id()] = target.transform


func _forget_target(target: Node) -> void:
	var id := target.get_instance_id()
	if retained_items.has(id):
		RenderingServer.free_rid(retained_items[id])
		retained_items.erase(id)
	item_state.erase(id)
	dirty_targets.erase(id)
	geometry.erase(id)
	previous_transforms.erase(id)

func begin_target(target: Node2D) -> void:
	geometry.erase(target.get_instance_id())
	dirty_targets[target.get_instance_id()] = true

func submit_target(target: Node2D, batch: RefCounted) -> void:
	if batch.indices.is_empty(): return
	geometry[target.get_instance_id()] = {
		"vertices": batch.vertices, "colors": batch.colors, "indices": batch.indices,
	}
	dirty_targets[target.get_instance_id()] = true

func _exit_tree() -> void:
	get_tree().physics_frame.disconnect(_capture_previous_poses)
	RenderingServer.frame_pre_draw.disconnect(_render_batches)
	for item in retained_items.values(): RenderingServer.free_rid(item)
	retained_items.clear()
	item_state.clear()
	dirty_targets.clear()


func _render_batches() -> void:
	if not is_inside_tree(): return
	render_batch_count = 0
	rendered_target_count = 0
	rendered_vertex_count = 0
	var fraction := Engine.get_physics_interpolation_fraction()
	for target in get_children():
		var id := target.get_instance_id()
		var data: Dictionary = geometry.get(id,{})
		if data.is_empty() or not target.visible:
			if retained_items.has(id) and item_state[id].shown:
				RenderingServer.canvas_item_set_visible(retained_items[id],false)
				item_state[id].shown = false
			continue
		if not retained_items.has(id):
			var created := RenderingServer.canvas_item_create()
			RenderingServer.canvas_item_set_parent(created,get_canvas_item())
			RenderingServer.canvas_item_set_material(created,additive_material.get_rid())
			RenderingServer.canvas_item_set_interpolated(created,false)
			retained_items[id] = created
			item_state[id] = {"index":-1,"shown":true}
			dirty_targets[id] = true
		var item: RID = retained_items[id]
		if not item_state[id].shown:
			RenderingServer.canvas_item_set_visible(item,true)
			item_state[id].shown = true
		if item_state[id].index != target.get_index():
			RenderingServer.canvas_item_set_draw_index(item,target.get_index())
			item_state[id].index = target.get_index()
		if dirty_targets.has(id):
			RenderingServer.canvas_item_clear(item)
			RenderingServer.canvas_item_add_triangle_array(item,data.indices,data.vertices,data.colors)
			dirty_targets.erase(id)
			geometry_upload_count += 1
		var pose: Transform2D = target.transform
		if target.is_physics_interpolated_and_enabled():
			var previous: Transform2D = previous_transforms.get(id,pose)
			pose = previous.interpolate_with(pose,fraction)
		RenderingServer.canvas_item_set_transform(item,pose)
		render_batch_count += 1
		rendered_target_count += 1
		rendered_vertex_count += data.vertices.size()
