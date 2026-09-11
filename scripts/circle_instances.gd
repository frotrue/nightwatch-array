extends RefCounted

# The same 64-segment filled circle as Godot 4.7's canvas ellipse, instanced in
# original particle order. Keep the geometry resident and upload only pose/color.
# This is procedural effect art, not additional scene children or a new shader.
const SEGMENTS := 64
const STRIDE := 12 # 2D transform (8 floats), RGBA (4 floats).
static var circle_mesh: ArrayMesh
var instances := MultiMesh.new()
var buffer := PackedFloat32Array()
var capacity := 0
var count := 0


func _init(maximum: int) -> void:
	if circle_mesh == null:
		circle_mesh = _make_circle()
	capacity = maximum
	instances.transform_format = MultiMesh.TRANSFORM_2D
	instances.use_colors = true
	instances.mesh = circle_mesh
	instances.instance_count = capacity
	instances.visible_instance_count = 0
	buffer.resize(capacity * STRIDE)


static func _make_circle() -> ArrayMesh:
	var vertices := PackedVector2Array()
	var indices := PackedInt32Array()
	# Native ellipse tessellation uses float32 angle arithmetic.
	var rounded := PackedFloat32Array([TAU / float(SEGMENTS)])
	var step: float = rounded[0]
	for i in SEGMENTS + 1:
		rounded[0] = float(i) * step
		vertices.append(Vector2(cos(rounded[0]), sin(rounded[0])))
	vertices.append(Vector2.ZERO)
	for i in SEGMENTS:
		indices.append_array(PackedInt32Array([SEGMENTS + 1, i, i + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_2D_VERTICES)
	return mesh


func begin() -> void:
	count = 0


func append(center: Vector2, radius: float, color: Color) -> void:
	assert(count < capacity)
	var offset := count * STRIDE
	buffer[offset] = radius
	buffer[offset + 3] = center.x
	buffer[offset + 5] = radius
	buffer[offset + 7] = center.y
	buffer[offset + 8] = color.r
	buffer[offset + 9] = color.g
	buffer[offset + 10] = color.b
	buffer[offset + 11] = color.a
	count += 1


func draw(canvas: Node2D) -> void:
	instances.visible_instance_count = count
	if count == 0: return
	instances.buffer = buffer
	canvas.draw_multimesh(instances, null)
