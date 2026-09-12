extends RefCounted

# One immutable quad/atlas and shared palette materials. Only
# instance pose, palette, visibility and atlas phase change at each visual tick.
const Atlas = preload("res://resources/textures/meteor_heads.png")
const ShaderSource = preload("res://resources/shaders/meteor_head.gdshader")
const PHASE_SPAN := TAU * 4.0
static var mesh: ArrayMesh
static var palette_materials: Dictionary = {}
var palette_material: ShaderMaterial
var palette := Color.TRANSPARENT
var canvas: RID
var instance := MultiMesh.new()
var buffer := PackedFloat32Array()

func _init(parent_canvas: RID) -> void:
	if mesh == null:
		mesh = ArrayMesh.new()
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(-4, -4), Vector2(4, -4), Vector2(4, 4), Vector2(-4, 4)])
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	instance.transform_format = MultiMesh.TRANSFORM_2D
	instance.use_colors = true
	instance.use_custom_data = true
	instance.mesh = mesh
	instance.instance_count = 1
	buffer.resize(16)
	canvas = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(canvas, parent_canvas)
	RenderingServer.canvas_item_add_multimesh(canvas, instance.get_rid())

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and canvas.is_valid():
		RenderingServer.free_rid(canvas)

func hide() -> void:
	RenderingServer.canvas_item_set_visible(canvas, false)

func draw(kind: String, radius: float, direction: Vector2, primary: Color, glow: Color, visibility: float, phase: float, self_tint := Color.WHITE) -> void:
	if palette_material == null or palette != primary:
		palette = primary
		if not palette_materials.has(primary):
			var created := ShaderMaterial.new()
			created.shader = ShaderSource
			created.set_shader_parameter("head_atlas", Atlas)
			created.set_shader_parameter("primary_ink", Vector3(primary.r, primary.g, primary.b))
			# Runtime palettes normally occupy two entries. Bound diagnostic/custom
			# colors; live heads retain their material after a cache eviction.
			if palette_materials.size() >= 16: palette_materials.erase(palette_materials.keys()[0])
			palette_materials[primary] = created
		palette_material = palette_materials[primary]
		RenderingServer.canvas_item_set_material(canvas, palette_material.get_rid())
	var axis := direction * radius
	buffer[0] = axis.x
	buffer[1] = -axis.y
	buffer[4] = axis.y
	buffer[5] = axis.x
	buffer[8] = self_tint.r
	buffer[9] = self_tint.g
	buffer[10] = self_tint.b
	buffer[11] = visibility * self_tint.a
	buffer[12] = glow.r
	buffer[13] = glow.g
	buffer[14] = glow.b
	var frame := fposmod(phase, PHASE_SPAN) * 64.0 / PHASE_SPAN
	buffer[15] = -1.0 - frame if kind == "fast" else frame
	instance.buffer = buffer
	var extent := absf(radius) * 5.66
	instance.custom_aabb = AABB(Vector3(-extent, -extent, -1), Vector3(extent * 2, extent * 2, 2))
	RenderingServer.canvas_item_set_custom_rect(canvas, true, Rect2(Vector2.ONE * -extent, Vector2.ONE * extent * 2))
	RenderingServer.canvas_item_set_visible(canvas, true)
