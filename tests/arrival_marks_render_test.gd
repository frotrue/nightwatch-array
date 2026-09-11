extends SceneTree
class Before:
	extends "res://scripts/effects_layer.gd"
	func _original_draw() -> void:
		var visual_scale := _world_px(1.0)
		_draw_particles(visual_scale)
		for ring in rings:
			var progress := 1.0 - clampf(float(ring.life) / maxf(float(ring.max_life), 0.001), 0.0, 1.0)
			var radius := lerpf(float(ring.radius_start), float(ring.radius_end), progress)
			draw_arc(ring.p, radius * visual_scale, 0.0, TAU, 44, Color(ring.color, (1.0 - progress) * 0.55), float(ring.width) * visual_scale, true)
		for popup in popups:
			var alpha := clampf(float(popup.alpha), 0.0, 1.0)
			var text := String(popup.text)
			if text.is_empty():
				var mote := float(popup.mote_size)
				draw_circle(popup.p, mote * 2.4 * visual_scale, Color(popup.color, alpha * 0.16))
				draw_circle(popup.p, mote * visual_scale, Color(popup.color, alpha * 0.92))
				continue
			var font := UITheme.sans()
			draw_string(font, popup.p, text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, int(round(float(popup.font_size) * visual_scale)), Color(popup.color, alpha))
		for marker in incoming_markers:
			var alpha := clampf(float(marker.life) / 0.4, 0.0, 1.0)
			var forecast := bool(marker.get("forecast", false))
			var duration := 3.0 if forecast else 1.45
			alpha *= smoothstep(0.0, 0.12, duration - float(marker.life))
			var p := ArrivalVisual.edge_point(Vector2(marker.p), _visible_world_rect(), visual_scale)
			var direction: Vector2 = marker.dir
			# One fading stroke is enough to indicate the entry direction.
			var ink := UITheme.ACCENT_LINE
			var reach := 38.0 if forecast else 26.0
			ArrivalVisual.draw_direction(self, p, direction, visual_scale, ink, alpha, reach)
		if flash_strength > 0.001:
			# Grown by the shake budget so a displaced canvas cannot expose an
			# unpainted strip along the edge the screen shook away from.
			var margin := Vector2.ONE * _world_px(MAX_SHAKE_OFFSET + MAX_KICK_OFFSET + 2.0)
			draw_rect(_visible_world_rect().grow(margin.x), Color(flash_color, flash_strength), true)

	var usec := 0
	var calls := 0
	func _draw() -> void:
		var start := Time.get_ticks_usec()
		_original_draw()
		usec += Time.get_ticks_usec() - start
		calls += 1
class After:
	extends "res://scripts/effects_layer.gd"
	var usec := 0
	var calls := 0
	func _draw() -> void:
		var start := Time.get_ticks_usec()
		super._draw()
		usec += Time.get_ticks_usec() - start
		calls += 1
var views: Array[SubViewport] = []
var effects: Array = []
var valid := true
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	for i in 2:
		var view := SubViewport.new()
		view.size = Vector2i(576,400)
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(view)
		views.append(view)
		var e = Before.new() if i == 0 else After.new()
		view.add_child(e)
		e.set_process(false)
		for j in 24:
			e.incoming_markers.append({"p":Vector2(200+(j%4)*35,100+(j/4)*20),"dir":Vector2.from_angle(j*0.33),"life":0.1+j*0.02,"forecast":j%2==0})
		e.flash_strength = 0.12
		e.flash_color = Color(0.2,0.4,0.8)
		effects.append(e)
	await compare("initial")
	var builds: int = effects[1].arrival_marks.builds
	for frame in (120 if OS.get_environment("NIGHTWATCH_MARKER_BENCH") == "1" else 6):
		for e in effects:
			for m in e.incoming_markers: m.life = 0.1+float(frame%20)*0.01
			e.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
	await compare("fade")
	valid = valid and effects[1].arrival_marks.builds == builds
	print("MARKER_CPU_US ",effects[0].usec/float(effects[0].calls)," -> ",effects[1].usec/float(effects[1].calls))
	for e in effects:
		e.incoming_markers[0].dir = Vector2(0.33,0.71)
		e.incoming_markers[1].forecast = false
		e.incoming_markers[2].p = Vector2(50,300)
		e.incoming_markers.pop_front()
		e.flash_strength = 0
	await compare("changed_removed")
	for e in effects:
		e.scale = Vector2(1.25, 1.25)
		e.position = Vector2(-25,-20)
		e.modulate = Color(0.8,0.9,1.0,0.75)
	await compare("canvas_transform_modulate")
	for i in 2:
		var camera = load("res://scripts/observation_view.gd").new()
		camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
		views[i].add_child(camera)
		camera.set_observation_span(1.5)
		effects[i].setup(camera)
	await compare("camera_span")
	for e in effects: e.reset()
	await compare("reset")
	valid = valid and effects[1].arrival_marks.items.is_empty()
	for view in views: view.free()
	print("ARRIVAL_MARKS_RENDER_PASS" if valid else "ARRIVAL_MARKS_RENDER_FAIL")
	quit(0 if valid else 1)
func compare(label: String) -> void:
	for e in effects: e.queue_redraw()
	for frame in 3:
		await process_frame
		await RenderingServer.frame_post_draw
	var a := views[0].get_texture().get_image().get_data()
	var b := views[1].get_texture().get_image().get_data()
	var maximum := 0
	var changed := 0
	for i in a.size():
		maximum = maxi(maximum,absi(int(a[i])-int(b[i])))
		changed += int(a[i]!=b[i])
	print("MARKER_PIXELS ",label," max=",maximum," channels=",changed)
	valid = valid and maximum <= 2 and changed <= 1500
