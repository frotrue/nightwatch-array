extends SceneTree

# Isolates per-frame batch submission from procedural redraw and simulation.
# 1,000 frozen-shape meteors move at 60 Hz; this bypasses gameplay capacity and
# is not a late-game FPS estimate. Run sequential A/Bs with a real renderer.
const Balance = preload("res://scripts/game_balance.gd")
const Meteor = preload("res://scripts/meteor.gd")
class MeasuredLayer:
	extends "res://scripts/meteor_render_layer.gd"
	var usec := 0
	var calls := 0
	func _render_batches() -> void:
		var began := Time.get_ticks_usec()
		super._render_batches()
		usec += Time.get_ticks_usec() - began
		calls += 1
class Driver:
	extends Node
	var targets: Array = []
	var time := 0.0
	var moving := false
	func _physics_process(delta: float) -> void:
		if not moving: return
		time += delta
		for target in targets:
			target.position = target.entry_position + Vector2(sin(time) * 10, cos(time) * 5)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Submission measurements require a real renderer")
		quit(1)
		return
	root.gui_disable_input = true
	var layer := MeasuredLayer.new()
	root.add_child(layer)
	var driver := Driver.new()
	root.add_child(driver)
	var textured := OS.get_environment("NIGHTWATCH_HEAD_TEXTURES") != "0"
	for i in 1000:
		var target := Meteor.new()
		var point := Vector2(20 + (i % 40) * 28, 30 + (i / 40) * 23)
		target.configure(Balance.meteor_spec("common"), "common", point, Vector2(30, 0), 1000.0, {}, point + Vector2(1000, 0))
		target.textured_head_enabled = textured
		layer.add_child(target)
		target.reset_physics_interpolation()
		target.set_process(false)
		target.age = 2.0
		for j in 24: target.trail_points.append(point - Vector2(j * 2, 0))
		target.queue_redraw()
		driver.targets.append(target)
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# Draw before moving: head + samples 1..24 = 25 stations, each with
	# three glow and three core vertices. Procedural heads add 55 vertices.
	await RenderingServer.frame_post_draw
	var expected_vertices := 150000 if textured else 205000
	driver.moving = true
	await create_timer(2.0).timeout
	layer.usec = 0
	layer.calls = 0
	var rebuilds := layer.geometry_upload_count
	var began := Time.get_ticks_usec()
	await create_timer(5.0).timeout
	var elapsed := (Time.get_ticks_usec() - began) / 1000000.0
	print("SUBMISSION_RESULT ", JSON.stringify({"textured":textured,"expected_vertices":expected_vertices,"fps":layer.calls / elapsed,"calls":layer.calls,"mean_submission_ms":layer.usec / 1000.0 / maxi(layer.calls, 1),"vertices":layer.rendered_vertex_count,"batches":layer.render_batch_count,"geometry_uploads":layer.geometry_upload_count - rebuilds}))
	var valid := layer.calls > 0 and layer.rendered_target_count == 1000 and layer.rendered_vertex_count == expected_vertices and layer.render_batch_count == 1000 and layer.geometry_upload_count == rebuilds
	driver.free()
	layer.free()
	print("METEOR_SUBMISSION_PASS" if valid else "METEOR_SUBMISSION_FAIL")
	quit(0 if valid else 1)
