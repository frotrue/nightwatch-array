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
			var target := CountedMeteor.new()
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
	_check(layers[1].render_batch_count == 4, "Opaque objects must split four additive runs")
	_check(layers[1].rendered_target_count == 8, "All eight non-solid targets must be batched")
	_check(layers[1].get_child_count() == 11, "Renderer must not introduce target children")
	var counts: Array = []
	for target in all_targets[1]: counts.append(target.draws)
	await _settle()
	for i in counts.size():
		_check(all_targets[1][i].draws == counts[i], "Unchanged meteor geometry was rebuilt between ticks")
	driver.moving = true
	for frame in 12:
		await physics_frame
		await process_frame
		await RenderingServer.frame_post_draw
		await _compare("moving_%d" % frame)
	driver.moving = false
	await _settle()
	await _compare("stopped")
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
	_check(layers[1].geometry.is_empty() and layers[1].index_cache.is_empty() and layers[1].canvases.is_empty(), "Deleted targets retained geometry or canvas RIDs")
	await _compare("empty")
	# Cross the 16-bit vertex-index boundary in one real GPU batch. A count-only
	# headless test cannot catch wrapped indices or missing light at this density.
	for variant in 2:
		for i in 1000:
			var target := CountedMeteor.new()
			var point := Vector2(15 + (i % 40) * 14, 12 + (i / 40) * 15)
			var spec: Dictionary = Balance.meteor_spec("common")
			target.configure(spec, "common", point, Vector2(30, 0), 100.0, {}, point + Vector2(1000, 0))
			layers[variant].add_child(target)
			target.reset_physics_interpolation()
			for j in 12: target.trail_points.append(point - Vector2(j * 2, 0))
	await _settle()
	_check(layers[1].render_batch_count == 1 and layers[1].rendered_target_count == 1000, "Thousand targets did not share one light batch")
	_check(layers[1].rendered_vertex_count > 65536, "Fixture did not exercise 32-bit indices")
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
