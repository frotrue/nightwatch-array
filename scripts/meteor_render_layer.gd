extends Node2D

# Local light triangles remain resident under each meteor's native canvas.
# Godot inherits its pose/interpolation, visibility and sibling paint order;
# render frames without geometry/layout changes need no per-target script work.
var geometry: Dictionary = {}
var retained_items: Dictionary = {}
var item_state: Dictionary = {}
var dirty_targets: Dictionary = {}
var layout_dirty := true
var additive_material := CanvasItemMaterial.new()
var rendered_target_count := 0
var render_batch_count := 0 # Visible retained items, not measured GPU draw calls.
var rendered_vertex_count := 0
var geometry_upload_count := 0
var reconciliation_count := 0

func _ready() -> void:
	additive_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	RenderingServer.frame_pre_draw.connect(_render_batches)
	child_entered_tree.connect(_watch_target)
	child_exiting_tree.connect(_forget_target)
	child_order_changed.connect(_mark_layout_dirty)
	for target in get_children(): _watch_target(target)

func _mark_layout_dirty() -> void:
	layout_dirty = true

func _watch_target(target: Node) -> void:
	if target is CanvasItem and not target.visibility_changed.is_connected(_mark_layout_dirty):
		target.visibility_changed.connect(_mark_layout_dirty)
	layout_dirty = true

func _forget_target(target: Node) -> void:
	if target is CanvasItem and target.visibility_changed.is_connected(_mark_layout_dirty):
		target.visibility_changed.disconnect(_mark_layout_dirty)
	var id := target.get_instance_id()
	if retained_items.has(id):
		RenderingServer.free_rid(retained_items[id])
		retained_items.erase(id)
	item_state.erase(id)
	dirty_targets.erase(id)
	geometry.erase(id)
	layout_dirty = true

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
	RenderingServer.frame_pre_draw.disconnect(_render_batches)
	for item in retained_items.values(): RenderingServer.free_rid(item)
	retained_items.clear()
	item_state.clear()
	dirty_targets.clear()
	geometry.clear()

func _render_batches() -> void:
	if not is_inside_tree() or (not layout_dirty and dirty_targets.is_empty()): return
	layout_dirty = false
	reconciliation_count += 1
	render_batch_count = 0
	rendered_target_count = 0
	rendered_vertex_count = 0
	for target in get_children():
		var id := target.get_instance_id()
		var data: Dictionary = geometry.get(id, {})
		if data.is_empty():
			if retained_items.has(id) and item_state[id].shown:
				RenderingServer.canvas_item_set_visible(retained_items[id], false)
				item_state[id].shown = false
			dirty_targets.erase(id)
			continue
		if not retained_items.has(id):
			var created := RenderingServer.canvas_item_create()
			RenderingServer.canvas_item_set_parent(created, target.get_canvas_item())
			# Same additive light before the meteor's filament, head and scan marks.
			RenderingServer.canvas_item_set_draw_behind_parent(created, true)
			RenderingServer.canvas_item_set_material(created, additive_material.get_rid())
			RenderingServer.canvas_item_set_interpolated(created, true)
			retained_items[id] = created
			item_state[id] = {"shown": true}
			dirty_targets[id] = true
		var item: RID = retained_items[id]
		if not item_state[id].shown:
			RenderingServer.canvas_item_set_visible(item, true)
			item_state[id].shown = true
		if dirty_targets.has(id):
			RenderingServer.canvas_item_clear(item)
			RenderingServer.canvas_item_add_triangle_array(item, data.indices, data.vertices, data.colors)
			dirty_targets.erase(id)
			geometry_upload_count += 1
		if target.visible:
			render_batch_count += 1
			rendered_target_count += 1
			rendered_vertex_count += data.vertices.size()
