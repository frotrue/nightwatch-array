extends SceneTree

const Layer = preload("res://scripts/meteor_render_layer.gd")
const Balance = preload("res://scripts/game_balance.gd")
var failures: Array[String] = []
var pair: Array[SubViewport] = []
var layers: Array[Node2D] = []
var all_targets: Array = []

class CountedMeteor:
	extends "res://scripts/meteor.gd"
	var draws := 0
	func _draw() -> void:
		draws += 1
		super._draw()

class NativeArcs:
	extends CountedMeteor
	# Compare native arcs and immediate trail submissions against retained ones.
	# Animated body materials have a separate seeded visual review.
	func _draw_dashed_arc(radius: float, start_angle: float, arc_length: float, dash_count: int, color: Color, width: float) -> void:
		var cell := arc_length / float(dash_count)
		for index in range(dash_count):
			var dash_start := start_angle + cell * float(index)
			draw_arc(Vector2.ZERO, radius, dash_start, dash_start + cell * 0.46, 5, color, width, true)

class MotionDriver:
	extends Node
	var targets: Array = []
	var moving := false
	var tick := 0
	func _physics_process(delta: float) -> void:
		if not moving: return
		tick += 1
		for target in targets:
			target.tick_motion(delta, tick)
			target.tick_resolve()

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("A real renderer is required.")
		quit(1)
		return
	root.gui_disable_input = true
	var driver := MotionDriver.new()
	root.add_child(driver)
	for variant in 2:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(576, 400)
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		pair.append(viewport)
		var layer: Node2D = Layer.new() if variant == 1 else Node2D.new()
		viewport.add_child(layer)
		layers.append(layer)
		var targets: Array = []
		# Alternating opaque and additive objects deliberately overlap. The last
		# light must be in front of each rock while earlier light is occluded.
		var types := ["common", "major", "galaxy", "fast", "variable_star", "comet", "satellite", "binary_star", "fragment", "fragment_piece", "fireball"]
		for i in types.size():
			var target := NativeArcs.new() if variant == 0 else CountedMeteor.new()
			var point := Vector2(190 + (i % 3) * 20, 110 + (i / 3) * 45)
			var spec: Dictionary = Balance.meteor_spec(types[i])
			target.configure(spec, types[i], point, Vector2(80, 12), 1000.0 / float(spec.lifetime), {"automation":0.1}, point + Vector2(1000, 150))
			layer.add_child(target)
			target.reset_physics_interpolation()
			target.age = 0.8
			for j in target.max_trail_points:
				target.trail_points.append(point - Vector2(j * 2.0, j * 0.3))
			target.required_track_time = 1000000.0
			targets.append(target)
			driver.targets.append(target)
		all_targets.append(targets)
	await _settle()
	await _compare("overlap")
	_check(layers[1].render_batch_count == 8, "Each non-solid target must retain its own ordered light item")
	_check(layers[1].rendered_target_count == 8, "All eight non-solid targets must be batched")
	_check(layers[1].get_child_count() == 11, "Renderer must not introduce target children")
	var counts: Array = []
	for target in all_targets[1]: counts.append(target.draws)
	var rebuilds: int = layers[1].geometry_upload_count
	var reconciliations: int = layers[1].reconciliation_count
	await _settle()
	_check(layers[1].geometry_upload_count == rebuilds, "Unchanged geometry was uploaded between ticks")
	_check(layers[1].reconciliation_count == reconciliations, "Stable scene rescanned targets between ticks")
	for i in counts.size():
		_check(all_targets[1][i].draws == counts[i], "Unchanged meteor geometry was rebuilt between ticks")
	# Pose-only updates must transform the unchanged resident geometry.
	for targets in all_targets:
		targets[0].position += Vector2(17, -9)
	await _settle()
	await _compare("cached_pose")
	_check(layers[1].geometry_upload_count == rebuilds, "Pose-only update uploaded geometry")
	_check(layers[1].reconciliation_count == reconciliations, "Pose-only update rescanned targets")
	# Native parent transforms must also work without a geometry publication.
	for targets in all_targets:
		targets[0].rotation = 0.37
		targets[0].scale = Vector2(1.2, 0.85)
	await _settle()
	await _compare("native_rotation_scale")
	for targets in all_targets:
		targets[0].physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		targets[0].position += Vector2(4, -3)
	await _settle()
	await _compare("native_interpolation_off")
	for targets in all_targets:
		targets[0].rotation = 0.0
		targets[0].scale = Vector2.ONE
		targets[0].physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
		targets[0].reset_physics_interpolation()
	await _settle()
	await _compare("native_interpolation_restored")
	# A leading target's changed topology must update its own retained buffer.
	for targets in all_targets:
		targets[0].trail_points.resize(4)
		targets[0].queue_redraw()
	await _settle()
	await _compare("shortened_leading_trail")
	for targets in all_targets:
		targets[1].hide()
	await _settle()
	await _compare("hidden_additive")
	for targets in all_targets:
		targets[1].show()
	await _settle()
	await _compare("shown_additive")
	# Move an opaque boundary into an existing run, then restore its position.
	for variant in 2: layers[variant].move_child(all_targets[variant][2], 1)
	await _settle()
	await _compare("reordered_opaque")
	for variant in 2: layers[variant].move_child(all_targets[variant][2], 2)
	await _settle()
	await _compare("restored_opaque")
	var inserted: Array[Node2D] = []
	for layer in layers:
		var boundary := Polygon2D.new()
		boundary.polygon = PackedVector2Array([Vector2(190, 100), Vector2(250, 100), Vector2(220, 165)])
		boundary.color = Color("253044")
		layer.add_child(boundary)
		layer.move_child(boundary, 1)
		inserted.append(boundary)
	await _settle()
	await _compare("inserted_opaque")
	for boundary in inserted: boundary.free()
	await _settle()
	await _compare("removed_opaque")
	driver.moving = true
	for frame in 12:
		await physics_frame
		await process_frame
		await RenderingServer.frame_post_draw
		await _compare("moving_%d" % frame)
	driver.moving = false
	await _settle()
	await _compare("stopped")
	var cloud_quad: Sprite2D = all_targets[1][2].planet_surface.clouds
	var original_surface: RID = cloud_quad.texture.get_rid()
	for targets in all_targets:
		targets[2].age += 0.1
	await _settle()
	await _compare("planet_cached_age")
	_check(cloud_quad.texture.get_rid() == original_surface, "Planet recreated its quad for age changes")
	for targets in all_targets:
		targets[2].body_radius *= 1.3
		targets[2].primary_color = Color("7799cc")
		targets[2].glow_color = Color("88ddee")
		targets[2].queue_redraw()
	await _settle()
	await _compare("planet_radius_palette")
	_check(is_equal_approx(cloud_quad.scale.x, all_targets[1][2].get_observation_body_radius() * 1.04), "Planet retained stale size")
	_check(cloud_quad.material.get_shader_parameter("primary") == all_targets[1][2].primary_color, "Planet retained stale palette")
	for targets in all_targets:
		targets[2].alive = false
		targets[2].linger_time = 0.073
		targets[2].queue_redraw()
	await _settle()
	await _compare("planet_translucent")
	_check(cloud_quad.texture.get_rid() == original_surface, "Planet recreated its quad while fading")
	# Exercise subpixel shader expansion at the late camera's largest scale.
	# Keep the actual canvas transform and shader bounds involved in culling.
	var cameras: Array = []
	for variant in 2:
		var camera = load("res://scripts/observation_view.gd").new()
		camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
		pair[variant].add_child(camera)
		cameras.append(camera)
		for target in all_targets[variant]: target.observation_view = camera
	for span in [1.0, 1.5]:
		for variant in 2:
			cameras[variant].set_observation_span(span)
			for target in all_targets[variant]:
				target.body_radius += 0.007
				target.queue_redraw()
		await _settle()
		await _compare("arc_subpixel_span_%s" % span)
	for targets in all_targets:
		for target in targets:
			target.base_automatic_rate = 0.0
			target.queue_redraw()
	await _settle()
	await _compare("scan_stopped")
	for targets in all_targets:
		for target in targets:
			target.base_automatic_rate = 0.1
			target.queue_redraw()
	await _settle()
	await _compare("scan_restarted")
	# A teleport resets the engine's previous pose; the shared layer must follow.
	for targets in all_targets:
		targets[3].position += Vector2(60, 15)
		targets[3].reset_physics_interpolation()
	await process_frame
	await RenderingServer.frame_post_draw
	await _compare("reset_interpolation")
	# Fades, feature changes and camera scale must invalidate cached geometry.
	for targets in all_targets:
		targets[0].alive = false
		targets[0].linger_time = 0.12
		targets[1].set_dish_assist_rate(0.5)
		targets[2].hide()
	await _settle()
	await _compare("fade_hidden_planet")
	for variant in 2:
		layers[variant].set_physics_process(false)
		for target in all_targets[variant]:
			target.set_process(false)
			target.position += Vector2(3, 2)
	paused = true
	await _settle()
	await _compare("frozen_scene")
	paused = false
	for targets in all_targets:
		for target in targets: target.queue_free()
	driver.targets.clear()
	await _settle()
	_check(layers[1].geometry.is_empty() and layers[1].retained_items.is_empty() and layers[1].item_state.is_empty() and layers[1].dirty_targets.is_empty(), "Deleted targets retained geometry or canvas RIDs")
	await _compare("empty")
	# Stress retained buffers beyond 65,536 total vertices. Each target now has
	# local indices; compare actual pixels to catch missing or stale light.
	for variant in 2:
		for i in 1000:
			var target := NativeArcs.new() if variant == 0 else CountedMeteor.new()
			var point := Vector2(15 + (i % 40) * 14, 12 + (i / 40) * 15)
			var spec: Dictionary = Balance.meteor_spec("common")
			target.configure(spec, "common", point, Vector2(30, 0), 100.0, {}, point + Vector2(1000, 0))
			layers[variant].add_child(target)
			target.reset_physics_interpolation()
			for j in 12: target.trail_points.append(point - Vector2(j * 2, 0))
	await _settle()
	_check(layers[1].render_batch_count == 1000 and layers[1].rendered_target_count == 1000, "Thousand targets did not retain all light items")
	_check(layers[1].rendered_vertex_count > 65536, "Fixture did not exercise the intended total geometry load")
	await _compare("thousand")
	for viewport in pair: viewport.free()
	driver.free()
	for failure in failures: push_error(failure)
	print("METEOR_BATCH_RENDER_PASS" if failures.is_empty() else "METEOR_BATCH_RENDER_FAIL")
	quit(0 if failures.is_empty() else 1)

func _settle() -> void:
	for frame in 3:
		await process_frame
		await RenderingServer.frame_post_draw

func _compare(label: String) -> void:
	var reference := pair[0].get_texture().get_image()
	var batched := pair[1].get_texture().get_image()
	var a := reference.get_data()
	var b := batched.get_data()
	if a == b:
		print("BATCH_PIXELS ", label, " identical")
		if label == "overlap":
			reference.save_png("res://build/batch-reference-overlap.png")
			batched.save_png("res://build/batch-actual-overlap.png")
		return
	var differing := 0
	var maximum := 0
	for i in a.size():
		var difference := absi(int(a[i]) - int(b[i]))
		if difference > 0: differing += 1
		maximum = maxi(maximum, difference)
	print("BATCH_PIXELS ", label, " channels=", differing, " max=", maximum)
	# CPU world transforms can round subpixel edge coverage differently from a
	# per-item GPU transform. Opaque ordering and motion errors exceed this bound.
	_check(maximum <= 2 and differing <= 1500, "Image mismatch at " + label)
	if label == "overlap" or maximum > 2:
		reference.save_png("res://build/batch-reference-" + label + ".png")
		batched.save_png("res://build/batch-actual-" + label + ".png")
