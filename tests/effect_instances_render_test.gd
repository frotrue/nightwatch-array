extends SceneTree

# Real-GPU comparison against the original native canvas circles, including
# overlapping alpha, moving/fading particles, camera scale and stale instances.
const Effects = preload("res://scripts/effects_layer.gd")
var views: Array[SubViewport] = []
var effects: Array = []
var failures: Array[String] = []

class ImmediateEffects:
	extends "res://scripts/effects_layer.gd"
	func _draw_particles(visual_scale: float) -> void:
		for particle in particles:
			var alpha := clampf(float(particle.life) / maxf(float(particle.max_life), 0.001), 0.0, 1.0)
			draw_circle(particle.p, float(particle.size) * alpha * visual_scale, Color(particle.color, alpha * 0.9))

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("A real renderer is required.")
		quit(1)
		return
	create_timer(60.0).timeout.connect(func():
		push_error("Effect instance comparison timed out")
		quit(1))
	root.gui_disable_input = true
	for variant in 2:
		var view := SubViewport.new()
		view.size = Vector2i(576, 400)
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(view)
		views.append(view)
		var effect = ImmediateEffects.new() if variant == 0 else Effects.new()
		view.add_child(effect)
		effects.append(effect)
		_seed_bursts(effect)
	await _compare("full_bursts")
	_check(effects[1].particles.size() == Effects.MAX_PARTICLES, "Fixture must reach the production particle cap")
	for step in [0.17, 0.19, 0.23]:
		for effect in effects:
			effect._process(step)
			effect.set_process(false)
		await _compare("fade_%s" % step)
	_check(effects[1].particles.size() < Effects.MAX_PARTICLES, "Fixture must remove expired instances")
	for effect in effects:
		effect.scale = Vector2(1.25, 1.25)
		effect.position = Vector2(-30, -20)
		effect.queue_redraw()
	await _compare("scaled_canvas")
	for effect in effects:
		effect._process(2.0)
		effect.set_process(false)
	await _compare("expired")
	_check(effects[1].particles.is_empty(), "Expired particles remain")
	for effect in effects: _seed_bursts(effect)
	await _compare("refilled")
	for i in 2:
		var camera = load("res://scripts/observation_view.gd").new()
		camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
		views[i].add_child(camera)
		camera.set_observation_span(1.5)
		effects[i].setup(camera)
		effects[i].queue_redraw()
	await _compare("late_camera")
	for effect in effects: effect.reset()
	await _compare("reset")
	_check(not effects[1].is_processing(), "Reset effects must stop processing")
	_check(effects[1].get_child_count() == 0, "Particle rendering added scene children")
	for view in views: view.free()
	for failure in failures: push_error(failure)
	print("EFFECT_INSTANCES_RENDER_PASS" if failures.is_empty() else "EFFECT_INSTANCES_RENDER_FAIL")
	quit(0 if failures.is_empty() else 1)

func _seed_bursts(effect: Node2D) -> void:
	effect.rng.seed = 12345
	for j in 15:
		effect.spawn_success(Vector2(100 + (j % 5) * 80, 100 + (j / 5) * 80), 10,
			Color(0.3 + (j % 3) * 0.2, 0.6, 0.8), 1.0, 0.6,
			"", Vector2(500, 30), 1.0, j % 2 == 0, Vector2(1, -0.3))
	# Interleave translucent colors in one place to make wrong draw order visible.
	for j in 12:
		effect.particles[j].p = Vector2(280 + j % 2, 250)
		effect.particles[j].color = Color.RED if j % 2 == 0 else Color.BLUE
		effect.particles[j].life *= 0.5
	effect.set_process(false)
	effect.queue_redraw()

func _compare(label: String) -> void:
	for frame in 3:
		await process_frame
		await RenderingServer.frame_post_draw
	_check(effects[1].particle_instances.count == effects[1].particles.size(), "Wrong instance count at " + label)
	_check(effects[1].particle_instances.instances.visible_instance_count == effects[1].particles.size(), "Stale visible instances at " + label)
	var reference := views[0].get_texture().get_image()
	var actual := views[1].get_texture().get_image()
	var a := reference.get_data()
	var b := actual.get_data()
	var changed := 0
	var maximum := 0
	for i in a.size():
		var difference := absi(int(a[i]) - int(b[i]))
		if difference > 0: changed += 1
		maximum = maxi(maximum, difference)
	print("EFFECT_PIXELS ", label, " channels=", changed, " max=", maximum)
	# CPU tessellation versus GPU instance transforms can round color/subpixel
	# edges slightly differently. Alpha-order or omitted particle errors exceed this.
	_check(maximum <= 2 and changed <= 1500, "Particle image mismatch at " + label)
	if label == "fade_0.17" or maximum > 2:
		reference.save_png("res://build/effects-reference-" + label + ".png")
		actual.save_png("res://build/effects-instanced-" + label + ".png")
