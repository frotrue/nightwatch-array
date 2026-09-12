extends SceneTree

const Meteor = preload("res://scripts/meteor.gd")
const Balance = preload("res://scripts/game_balance.gd")
var failures: Array[String] = []
var views: Array[SubViewport] = []
var targets: Array = []

class Head:
	extends Meteor
	var test_radius := 6.0
	var test_visibility := 1.0
	func _draw() -> void:
		if head_texture != null: head_texture.hide()
		triangle_batch.begin()
		_draw_type_silhouette(test_radius, test_visibility, 1.0)
		triangle_batch.flush(get_canvas_item())

func _initialize() -> void: _run.call_deferred()

func _check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Head texture validation requires a real renderer")
		quit(1)
		return
	for variant in 2:
		var view := SubViewport.new()
		view.size = Vector2i(720, 300)
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(view)
		views.append(view)
		var row: Array[Head] = []
		for i in 12:
			var meteor := Head.new()
			var type_id := "common" if i < 6 else "fast"
			meteor.configure(Balance.meteor_spec(type_id), type_id, Vector2(60 + (i % 6) * 120, 75 + (i / 6) * 150), Vector2.RIGHT * 100, 100, {}, Vector2(2000, 0))
			meteor.textured_head_enabled = variant == 1
			meteor.test_radius = [3.0, 6.0, 12.0][i % 3]
			meteor.test_visibility = 1.0 if i % 6 < 3 else 0.35
			meteor.wobble_phase = 0.0
			view.add_child(meteor)
			meteor.set_process(false)
			meteor.set_physics_process(false)
			row.append(meteor)
		targets.append(row)
	await _settle()
	for phase in [0.0, 0.39, 1.9, 8.2, 25.0, 25.12, TAU * 4.0 - 0.0000001, 25.2, 50.4]:
		for row in targets:
			for meteor in row:
				meteor.age = phase / (7.4 if meteor.type_id == "common" else 12.5)
				meteor.travel_direction = Vector2.RIGHT.rotated(phase * 0.07)
				meteor.queue_redraw()
		await _settle()
		var original := views[0].get_texture().get_image()
		var textured := views[1].get_texture().get_image()
		if phase == 1.9:
			original.save_png("res://build/head-original.png")
			textured.save_png("res://build/head-textured.png")
		# Rasterization/interpolated atlas shapes deliberately differ. Assess each
		# head, not a mostly black viewport: no lost head, clipping or large energy shift.
		for i in 12:
			var center: Vector2 = targets[0][i].position
			var region := Rect2i(Vector2i(center) - Vector2i(55, 55), Vector2i(110, 110))
			var a := _light(original, region)
			var b := _light(textured, region)
			_check(a > 0.1 and b > 0.1, "Missing head at %s/%s" % [phase, i])
			_check(b / a > 0.8 and b / a < 1.2, "Head brightness drift at %s/%s: %s" % [phase, i, b / a])
		print("HEAD_PHASE ", phase, " compared 12 heads")
	for row in targets:
		for meteor in row:
			meteor.modulate = Color(0.4, 0.7, 0.5, 0.65)
			meteor.self_modulate = Color(0.8, 0.9, 0.7, 0.85)
			meteor.queue_redraw()
	await _settle()
	for i in 12:
		var center: Vector2 = targets[0][i].position
		var region := Rect2i(Vector2i(center) - Vector2i(55, 55), Vector2i(110, 110))
		var a := _light(views[0].get_texture().get_image(), region)
		var b := _light(views[1].get_texture().get_image(), region)
		_check(b / a > 0.8 and b / a < 1.2, "Inherited canvas tint/alpha drift at %s: %s" % [i, b / a])
	# Palette, radius and type mutation must take effect immediately; leaving
	# the atlas-supported types must hide the retained native item.
	var head: Head = targets[1][0]
	head.primary_color = Color("d050b0")
	head.glow_color = Color("60b0d0")
	head.test_radius = 14.0
	head.queue_redraw()
	await _settle()
	_check(head.head_texture.palette_material.get_shader_parameter("primary_ink") == Vector3(head.primary_color.r, head.primary_color.g, head.primary_color.b) and head.head_texture.buffer[13] == head.glow_color.g, "Atlas retained a stale palette")
	head.type_id = "fragment"
	head.queue_redraw()
	await _settle()
	head.type_id = "fast"
	head.queue_redraw()
	await _settle()
	_check(head.head_texture.buffer[15] < 0.0, "Type change did not select the fast atlas cells")
	for view in views: view.free()
	for failure in failures: push_error(failure)
	print("METEOR_HEAD_TEXTURE_PASS" if failures.is_empty() else "METEOR_HEAD_TEXTURE_FAIL")
	quit(0 if failures.is_empty() else 1)

func _settle() -> void:
	for _frame in 3:
		await process_frame
		await RenderingServer.frame_post_draw

func _light(picture: Image, rect: Rect2i) -> float:
	var sum := 0.0
	var background := picture.get_pixel(0, 0)
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var color := picture.get_pixel(x, y) - background
			sum += color.r + color.g + color.b
	return sum
