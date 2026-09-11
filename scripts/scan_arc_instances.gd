extends RefCounted

# Feather-strip construction adapted from Godot 4.7 renderer_canvas_cull.cpp.
# Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md).
# Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# The two five-point dashed arcs used by automatic observation. Each dash keeps
# the native Godot 4.7 open-polyline center/left/right feather strips. Only its
# radius, width, rotation and color change; the GPU expands a shared template.
const ShaderSource = preload("res://resources/shaders/scan_arc.gdshader")
const STRIDE := 16 # transform, color, custom(radius, compensated width).
static var material: ShaderMaterial
static var meshes: Dictionary = {}
var canvas: RID
var batches: Dictionary = {}
var half := PackedByteArray()
var bound := 0.0

func _init(parent_canvas: RID) -> void:
	half.resize(2)
	if material == null:
		material = ShaderMaterial.new()
		material.shader = ShaderSource
	canvas = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(canvas, parent_canvas)
	RenderingServer.canvas_item_set_material(canvas, material.get_rid())

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and canvas.is_valid():
		RenderingServer.free_rid(canvas)

func clear() -> void:
	RenderingServer.canvas_item_clear(canvas)
	bound = 0.0

func draw(radius: float, angle: float, length: float, count: int, color: Color, width: float) -> void:
	var cell := length / count
	# Production widths are <= 1.2 * sqrt(1.5); native AA halves widths <= 2.5,
	# then uses a 1.25 * width feather below 1.0. Other widths retain native arcs.
	assert(width > 0.0 and width < 2.0)
	# The vertex shader expands a unit template; culling must use the real ring.
	bound = maxf(bound, absf(radius) + width * 2.0)
	RenderingServer.canvas_item_set_custom_rect(canvas, true, Rect2(Vector2.ONE * -bound, Vector2.ONE * bound * 2.0))
	if not batches.has(count):
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_2D
		instances.use_colors = true
		instances.use_custom_data = true
		if not meshes.has(cell): meshes[cell] = _make_mesh(cell * 0.46)
		instances.mesh = meshes[cell]
		instances.instance_count = count
		batches[count] = {"instances": instances, "buffer": PackedFloat32Array()}
		batches[count].buffer.resize(count * STRIDE)
	var batch: Dictionary = batches[count]
	var buffer: PackedFloat32Array = batch.buffer
	# Compatibility packs custom values to float16 internally. Preserve the
	# subpixel radius/width in a high+residual pair instead of visibly snapping.
	half.encode_half(0, radius)
	var radius_high := half.decode_half(0)
	half.encode_half(0, width * 0.5)
	var width_high := half.decode_half(0)
	for i in count:
		var at := angle + cell * i
		var c := cos(at)
		var s := sin(at)
		var base := i * STRIDE
		buffer[base] = c
		buffer[base + 1] = -s
		buffer[base + 4] = s
		buffer[base + 5] = c
		buffer[base + 8] = color.r
		buffer[base + 9] = color.g
		buffer[base + 10] = color.b
		buffer[base + 11] = color.a
		buffer[base + 12] = radius_high
		buffer[base + 13] = width_high
		buffer[base + 14] = radius - radius_high
		buffer[base + 15] = width * 0.5 - width_high
	batch.instances.buffer = buffer
	RenderingServer.canvas_item_add_multimesh(canvas, batch.instances.get_rid())

static func _make_mesh(length: float) -> ArrayMesh:
	var centers := PackedVector2Array()
	for i in 5: centers.append(Vector2.from_angle(length * i / 4.0))
	var strips: Array = [[], [], []]
	for i in 5:
		var direction := (centers[i + 1] - centers[i]).normalized() if i < 4 else (centers[4] - centers[3]).normalized()
		var previous := direction if i == 0 else (centers[i] - centers[i - 1]).normalized()
		var normal := direction.orthogonal()
		if i > 0 and i < 4:
			var bisector := (previous * direction.length() - direction * previous.length()).normalized()
			var sine := sin(atan2(bisector.cross(previous), bisector.dot(previous)))
			if not is_zero_approx(sine): normal = bisector * clampf(1.0 / sine, -3.0, 3.0)
		var edge := normal * 0.5
		var border := normal * 1.25
		if i == 0:
			var cap := -direction * 1.25
			strips[0].append_array([[centers[i], edge + cap, 0.0], [centers[i], -edge + cap, 0.0]])
			strips[1].append_array([[centers[i], edge + cap, 0.0], [centers[i], edge + cap + border, 0.0]])
			strips[2].append_array([[centers[i], -edge + cap, 0.0], [centers[i], -edge + cap - border, 0.0]])
		strips[0].append_array([[centers[i], edge, 1.0], [centers[i], -edge, 1.0]])
		strips[1].append_array([[centers[i], edge, 1.0], [centers[i], edge + border, 0.0]])
		strips[2].append_array([[centers[i], -edge, 1.0], [centers[i], -edge - border, 0.0]])
		if i == 4:
			var cap := previous * 1.25
			strips[0].append_array([[centers[i], edge + cap, 0.0], [centers[i], -edge + cap, 0.0]])
			strips[1].append_array([[centers[i], edge, 1.0], [centers[i], edge + cap + border, 0.0], [centers[i], edge + cap, 0.0]])
			strips[2].append_array([[centers[i], -edge, 1.0], [centers[i], -edge + cap - border, 0.0], [centers[i], -edge + cap, 0.0]])
	var vertices := PackedVector2Array()
	var offsets := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for strip in strips:
		var base := vertices.size()
		for vertex in strip:
			vertices.append(vertex[0])
			offsets.append(vertex[1])
			colors.append(Color(1, 1, 1, vertex[2]))
		for i in strip.size() - 2: indices.append_array(PackedInt32Array([base + i, base + i + 1, base + i + 2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = offsets
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_2D_VERTICES)
	return result
