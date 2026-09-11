extends SceneTree

# Original native circles and sunrise triangles are the pixel oracle. Exercise
# ordering, dawn opacity, zoom, resize, empty buffers and reused instance capacity.
class NativeSky:
	extends "res://scripts/starfield.gd"
	func _draw_star(point: Vector2, star: Dictionary) -> void:
		var level := int(star.level)
		var star_color: Color = STAR_TEMPERATURES[int(star.temperature)]
		star_color.a = clampf(float(star.alpha) + sin(float(star.phase)) * 0.035 + activity * 0.08, 0.18, 0.92)
		star_color.a *= background_star_alpha()
		# No cross rays. They were the reason a background star could occupy more
		# pixels than a meteor's head, and the sky has to stay quieter than the
		# thing the player is trying to see in it.
		draw_circle(point, _world_px(float(star.size)), star_color)
		if level == 2:
			var soft_edge := star_color
			soft_edge.a *= 0.07
			draw_circle(point, _world_px(float(star.size) * 2.15), soft_edge)


	func _draw_sunrise(frame: Rect2) -> void:
		# Draw behind the ridges so the sun rises out of the existing landscape.
		var radius := frame.size.y * 0.029
		var centre := frame.position + frame.size * Vector2(0.32, lerpf(0.96, 0.897, sunrise))
		var glow := dawn_amount() * 0.25 + sunrise * 0.75
		# A vertex-colored radial mesh avoids hard concentric halo edges.
		var points := PackedVector2Array()
		var colors := PackedColorArray()
		var glow_radius := radius * 6.0
		for index in range(64):
			var angle := TAU * float(index) / 64.0
			var next_angle := TAU * float(index + 1) / 64.0
			points = PackedVector2Array([centre, centre + Vector2.from_angle(angle) * glow_radius, centre + Vector2.from_angle(next_angle) * glow_radius])
			colors = PackedColorArray([Color(1.0, 0.64, 0.33, glow * 0.15), Color(1.0, 0.64, 0.33, 0.0), Color(1.0, 0.64, 0.33, 0.0)])
			draw_polygon(points, colors)
		if sunrise > 0.0:
			draw_circle(centre, radius, Color("FFE1AE"), true, -1.0, true)

class NativeTwinkle:
	extends "res://scripts/star_twinkle.gd"
	func _draw_star(point: Vector2, star: Dictionary) -> void:
		var pulse := 0.48 + sin(time * float(star.speed) + float(star.phase)) * 0.38
		var alpha := clampf(pulse, 0.08, 0.86)
		# Rays removed with the starfield's, for the same reason: a background
		# star must never take up more of the frame than a meteor does.
		draw_circle(point, _world_px(float(star.size)), Color(0.76, 0.89, 1.0, alpha))

var views: Array[SubViewport] = []
var skies: Array = []
var twinkles: Array = []
var cameras: Array[Camera2D] = []
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Background pixel comparison requires a real renderer")
		quit(1)
		return
	create_timer(60.0).timeout.connect(func(): push_error("Background comparison timed out"); quit(1))
	root.gui_disable_input = true
	for variant in 2:
		var view := SubViewport.new()
		view.size = Vector2i(1152, 648)
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(view)
		views.append(view)
		var camera = load("res://scripts/observation_view.gd").new()
		camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
		view.add_child(camera)
		cameras.append(camera)
		var sky = NativeSky.new() if variant == 0 else load("res://scripts/starfield.gd").new()
		view.add_child(sky)
		sky.setup(camera)
		skies.append(sky)
		var twinkle = NativeTwinkle.new() if variant == 0 else load("res://scripts/star_twinkle.gd").new()
		view.add_child(twinkle)
		twinkle.setup(camera)
		twinkle.set_process(false)
		twinkles.append(twinkle)
	# Force overlapping opaque centers/soft rims so batching must retain order.
	for sky in skies:
		sky.stars[1].p = sky.stars[0].p
	await _compare("night")
	for value in [0.5, 0.85, 1.0]:
		for sky in skies:
			sky.set_watch_progress(value)
			sky.set_activity(0.6)
		for twinkle in twinkles:
			twinkle.time = value * 17.0
			twinkle.queue_redraw()
		await _compare("dawn_%s" % value)
	for sky in skies: sky._set_sunrise(0.65)
	await _compare("sunrise")
	for camera in cameras: camera.set_observation_span(1.5)
	await _compare("wide")
	for view in views: view.size = Vector2i(1440, 810)
	await _compare("resize")
	for sky in skies:
		sky.stars.clear()
		sky.outer_stars.clear()
		sky.queue_redraw()
	for twinkle in twinkles:
		twinkle.stars.clear()
		twinkle.outer_stars.clear()
		twinkle.queue_redraw()
	await _compare("empty")
	for sky in skies: sky._rebuild_stars()
	for twinkle in twinkles: twinkle._rebuild_stars()
	await _compare("refill")
	for view in views: view.free()
	for failure in failures: push_error(failure)
	print("BACKGROUND_BATCH_RENDER_PASS" if failures.is_empty() else "BACKGROUND_BATCH_RENDER_FAIL")
	quit(0 if failures.is_empty() else 1)

func _compare(label: String) -> void:
	for frame in 3:
		await process_frame
		await RenderingServer.frame_post_draw
	var reference := views[0].get_texture().get_image()
	var actual := views[1].get_texture().get_image()
	var a := reference.get_data()
	var b := actual.get_data()
	var differing := 0
	var maximum := 0
	for i in a.size():
		var difference := absi(int(a[i]) - int(b[i]))
		if difference > 0: differing += 1
		maximum = maxi(maximum, difference)
	print("BACKGROUND_PIXELS ", label, " channels=", differing, " max=", maximum)
	if maximum > 2 or differing > 1500: failures.append("Background mismatch: " + label)
	var backend := RenderingServer.get_current_rendering_method()
	reference.save_png("res://build/background-reference-%s-%s.png" % [backend, label])
	actual.save_png("res://build/background-actual-%s-%s.png" % [backend, label])
