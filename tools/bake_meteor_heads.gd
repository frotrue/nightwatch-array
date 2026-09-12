extends SceneTree

# Bake the existing procedural head into independent additive contribution masks:
# R = optical skirt/glow, G = warm core, B = moving hotspot. No palette is baked.
const Meteor = preload("res://scripts/meteor.gd")
const CELL := 128
const COLUMNS := 8
const FRAMES := 64
const PHASE_SPAN := TAU * 4.0

class Baker:
	extends Meteor
	var fan := 0
	func _draw() -> void:
		triangle_batch.begin()
		triangle_batch.deferred = true
		fan = 0
		var profile := _head_profile()
		_draw_directional_head(16.0, 1.0, profile[0], profile[1], profile[2], profile[3], profile[4], profile[5])
		# The last sixteen vertices are the original moving hotspot polygon.
		for index in range(triangle_batch.colors.size() - 16, triangle_batch.colors.size()):
			triangle_batch.colors[index] = Color(0, 0, 1, triangle_batch.colors[index].a)
		triangle_batch.deferred = false
		triangle_batch.flush(get_canvas_item())
	func _draw_graded_polygon(points: PackedVector2Array, bright_point: Vector2, centre_color: Color, rim_color: Color) -> void:
		var channel := Color.RED if fan < 2 else Color.GREEN
		fan += 1
		super._draw_graded_polygon(points, bright_point, Color(channel, centre_color.a), Color(channel, rim_color.a))

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Baking requires the real renderer")
		quit(1)
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(CELL * COLUMNS, CELL * FRAMES * 2 / COLUMNS)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var backdrop := ColorRect.new()
	backdrop.color = Color.BLACK
	backdrop.size = Vector2(viewport.size)
	viewport.add_child(backdrop)
	for kind in 2:
		for frame in FRAMES:
			var baker := Baker.new()
			baker.type_id = "common" if kind == 0 else "fast"
			baker.age = PHASE_SPAN * float(frame) / FRAMES / (7.4 if kind == 0 else 12.5)
			baker.wobble_phase = 0.0
			baker.travel_direction = Vector2.RIGHT
			var cell := kind * FRAMES + frame
			baker.position = Vector2(cell % COLUMNS, cell / COLUMNS) * CELL + Vector2.ONE * CELL * 0.5
			viewport.add_child(baker)
			baker.set_process(false)
			baker.set_physics_process(false)
	for _frame in 3:
		await process_frame
		await RenderingServer.frame_post_draw
	var picture := viewport.get_texture().get_image()
	picture.convert(Image.FORMAT_RGB8)
	var error := picture.save_png("res://resources/textures/meteor_heads.png")
	viewport.free()
	if error != OK:
		push_error("Could not save meteor atlas: %s" % error)
		quit(1)
		return
	print("METEOR_HEAD_BAKE_PASS: 128 frames, 1024x2048 additive masks")
	quit()
