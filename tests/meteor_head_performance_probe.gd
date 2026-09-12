extends SceneTree

# Isolate head geometry submission; this is not 1,000 fully simulated meteors.
const Layer = preload("res://scripts/meteor_render_layer.gd")
const Balance = preload("res://scripts/game_balance.gd")
class CountedMeteor:
	extends "res://scripts/meteor.gd"
	static var draw_usec := 0
	static var draw_calls := 0
	func _draw() -> void:
		var began := Time.get_ticks_usec()
		super._draw()
		draw_usec += Time.get_ticks_usec() - began
		draw_calls += 1
class Driver:
	extends Node
	var targets: Array[CountedMeteor] = []
	func _physics_process(delta: float) -> void:
		for meteor in targets:
			meteor.age += delta
			meteor.queue_redraw()
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("A real renderer is required")
		quit(1)
		return
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var enabled := OS.get_environment("NIGHTWATCH_HEAD_TEXTURES") != "0"
	var layer := Layer.new()
	root.add_child(layer)
	var driver := Driver.new()
	root.add_child(driver)
	for i in 1000:
		var meteor := CountedMeteor.new()
		var kind := "common" if i % 2 == 0 else "fast"
		meteor.configure(Balance.meteor_spec(kind), kind, Vector2(14 + i % 40 * 28, 12 + i / 40 * 25), Vector2(100, 15), 1000.0, {}, Vector2(3000, 0))
		meteor.textured_head_enabled = enabled
		meteor.age = 0.5
		meteor.wobble_phase = float(i % 100) * 0.06
		layer.add_child(meteor)
		driver.targets.append(meteor)
	await create_timer(2.0).timeout
	CountedMeteor.draw_usec = 0
	CountedMeteor.draw_calls = 0
	var started := Time.get_ticks_usec()
	var frames := 0
	while Time.get_ticks_usec() - started < 5000000:
		await process_frame
		frames += 1
	var seconds := float(Time.get_ticks_usec() - started) / 1000000.0
	print("HEAD_PERF_RESULT ", JSON.stringify({"textured":enabled,"heads":1000,"renderer":RenderingServer.get_current_rendering_method(),"fps":frames/seconds,"head_cpu_us":float(CountedMeteor.draw_usec)/maxi(1,CountedMeteor.draw_calls),"draws":CountedMeteor.draw_calls,"sample_seconds":seconds}))
	var valid := CountedMeteor.draw_calls > 10000 and Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME) > 0
	driver.free()
	layer.free()
	await process_frame
	print("HEAD_PERF_PASS" if valid else "HEAD_PERF_FAIL")
	quit(0 if valid else 1)
