extends RefCounted

# Keep local geometry until the layer submits the contiguous additive run.
# Standalone meteor fixtures retain immediate drawing and its command order.
var vertices := PackedVector2Array()
var colors := PackedColorArray()
var indices := PackedInt32Array()
var deferred := false
var sources: Array[PackedInt32Array] = []
var shifted: Array[PackedInt32Array] = []
var offsets: Array[int] = []
var part := 0

func begin() -> void:
	vertices.clear()
	colors.clear()
	indices.clear()
	part = 0

func append(source_indices: PackedInt32Array, source_vertices: PackedVector2Array, source_colors: PackedColorArray) -> void:
	var offset := vertices.size()
	vertices.append_array(source_vertices)
	colors.append_array(source_colors)
	if part == sources.size():
		sources.append(PackedInt32Array())
		shifted.append(PackedInt32Array())
		offsets.append(-1)
	if offsets[part] != offset or sources[part] != source_indices:
		var adjusted := source_indices.duplicate()
		for i in adjusted.size():
			adjusted[i] += offset
		# Packed arrays passed through GDScript containers share mutable storage.
		# Keep an immutable topology snapshot, not the meteor's reused strip array.
		sources[part] = source_indices.duplicate()
		shifted[part] = adjusted
		offsets[part] = offset
	indices.append_array(shifted[part])
	part += 1

func flush(canvas: RID) -> void:
	if deferred or indices.is_empty():
		return
	RenderingServer.canvas_item_add_triangle_array(canvas, indices, vertices, colors)
	begin()
