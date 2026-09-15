extends SceneTree

const Fixtures = preload("res://tests/support/game_fixture.gd")
const Bindings = preload("res://scripts/game_input_bindings.gd")
var failures: Array[String] = []

func _initialize() -> void: _run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error("WHITE_HOLE: " + message)

func _key(game: Node, code: int, modifiers: bool = true, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.ctrl_pressed = modifiers
	event.shift_pressed = modifiers
	event.echo = echo
	game.input_router._unhandled_key_input(event)

func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	Fixtures.configure_before_ready(game)
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.spawner.running = false
	game.events.running = false
	var layer = game.debug_celestials
	check(layer.get_child_count() == 0, "normal startup has no white holes")
	var save_before := JSON.stringify(game._build_save_data())
	var meteor_count: int = game.meteor_layer.get_child_count()
	_key(game, KEY_W, false)
	_key(game, KEY_W, true, true)
	check(layer.get_child_count() == 0, "plain W and key repeat cannot summon previews")
	_key(game, KEY_W)
	check(layer.get_child_count() == 1, "reserved debug chord reaches the preview layer")
	var first = layer.get_child(0)
	check(first.position.is_equal_approx(game.get_global_mouse_position()), "debug spawn uses the world-space cursor")
	var second = layer.spawn_white_hole(Vector2(500, 300), 2.0)
	var third = layer.spawn_white_hole(Vector2(700, 300), 1.0)
	check(second.scale.is_equal_approx(Vector2(2, 2)), "preview size accepts pulled-back camera units")
	check(first.emission.material != second.emission.material, "separate preview instances own their shader state")
	check(layer.spawn_white_hole(Vector2.ZERO, 1.0) == null, "debug previews are bounded at three")
	check(game.meteor_layer.get_child_count() == meteor_count, "previews never enter meteor admission or observation")
	_key(game, KEY_E)
	check(first.effect_mode == 1 and second.effect_mode == 1 and third.effect_mode == 1, "effect comparison updates all live previews")
	check(JSON.stringify(game._build_save_data()) == save_before, "spawning and switching effects leave the saved run and RNG unchanged")
	check(Bindings._reserved_key_reason(KEY_W, {"ctrl": true, "shift": true}) == "reserved_debug_input", "W chord cannot be rebound as gameplay")
	check(Bindings._reserved_key_reason(KEY_E, {"ctrl": true, "shift": true}) == "reserved_debug_input", "E chord cannot be rebound as gameplay")
	var before_age: float = first.age
	paused = true
	game.simulate_tick()
	check(first.age == before_age, "paused simulation does not age debug effects")
	_key(game, KEY_E)
	check(first.effect_mode == 0, "comparison chord works while chart simulation is paused")
	paused = false
	game.settings.set_motion_intensity(0.0, false)
	game.settings.set_screen_flashes_enabled(false, false)
	var before_visual: float = first.visual_time
	game.simulate_tick()
	check(first.age > before_age and first.visual_time == before_visual, "reduced motion freezes animation without freezing lifetime")
	check(first.emission.material.get_shader_parameter("motion") == 0.0 and first.emission.material.get_shader_parameter("pulses") == 0.0, "accessibility changes propagate to active shader instances")
	check(first.background_copy.copy_mode == BackBufferCopy.COPY_MODE_DISABLED, "reduced motion disables the sky copy")
	game.settings.set_motion_intensity(1.0, false)
	first.position = Vector2(576, 324)
	first.present()
	check(first.background_copy.copy_mode == BackBufferCopy.COPY_MODE_VIEWPORT, "visible active preview lenses the sky")
	check(first.lensed_sky.z_index < game.meteor_layer.z_index and not first.lensed_sky.z_as_relative, "optical layer precedes real observation targets")
	check(first.lensed_sky.material != second.lensed_sky.material, "sky lenses have independent material state")
	first.hide()
	check(first.background_copy.copy_mode == BackBufferCopy.COPY_MODE_DISABLED, "hidden previews do not copy the screen")
	first.show()
	first.position = Vector2(-10000, -10000)
	first.present()
	check(first.background_copy.copy_mode == BackBufferCopy.COPY_MODE_DISABLED, "offscreen previews do not copy the screen")
	first.advance(first.LIFETIME)
	check(first.is_queued_for_deletion() and not first.visible, "expiry hides and releases a preview")
	check(layer.spawn_white_hole(Vector2.ZERO, 1.0) != null, "expired preview frees a slot before deferred deletion")
	game._apply_save_data(game._build_save_data())
	check(layer.get_child_count() == 0, "loading clears visual previews")
	layer.spawn_white_hole(Vector2.ZERO, 1.0)
	game.reset_run()
	check(layer.get_child_count() == 0, "run reset clears previews")
	layer.spawn_white_hole(Vector2.ZERO, 1.0)
	game._end_observation_phase()
	check(layer.get_child_count() == 0, "round end clears previews")
	game.free()
	paused = false
	await process_frame
	if failures.is_empty(): print("WHITE_HOLE_PASS: debug routing, bounded previews, save isolation, pause, accessibility and cleanup")
	quit(0 if failures.is_empty() else 1)
