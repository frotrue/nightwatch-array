extends SceneTree

# Presentation routing is checked independently of the renderer and economy.
# Listening/visual review still determines feel; this gate protects semantics.
const MainScene = preload("res://scenes/main.tscn")
const Balance = preload("res://scripts/game_balance.gd")
const Fixtures = preload("res://tests/support/game_fixture.gd")
# Preserve the fixture names used by older local review drivers.
const SilentSound = Fixtures.SilentSound
const NoSaveSlots = Fixtures.NoSaveSlots
const NoSettings = Fixtures.NoSettings
const ROUTINE_TYPES := [
	"common", "fast", "fragment", "fragment_piece", "satellite",
	"variable_star", "comet", "binary_star", "galaxy",
]
const IMPACT_TYPES := ["fireball", "major"]
const CENTRE := Vector2(420.0, 240.0)

class DistantFixture:

	extends Node2D

	func get_visual_color() -> Color:
		return Color.WHITE

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures.append(message)
	push_error("EFFECT_FEEDBACK: " + message)


func _run() -> void:
	var game = MainScene.instantiate()
	Fixtures.configure_before_ready(game)
	root.add_child(game)
	game.sound.free()
	var sound := SilentSound.new()
	game.add_child(sound)
	game.sound = sound
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.spawner.running = false
	game.events.running = false
	_test_particle_categories(game.effects)
	_test_meteor_routing(game)
	_test_distant_and_event_paths(game)
	_test_caps(game.effects)
	await _test_installation_rule(game)
	await _test_chart_installation_rule(game)
	paused = false
	game._release_hitstop()
	game.free()
	if failures.is_empty():
		print("EFFECT_FEEDBACK_PASS: routine/accent routing, directional cones, event/cap preservation and visible paused HUD/chart installation rules")
		quit(0)
	else:
		print("EFFECT_FEEDBACK_FAIL: %d failure(s)" % failures.size())
		quit(1)


func _test_particle_categories(effects) -> void:
	for direction in [Vector2.RIGHT, Vector2(-2.0, 3.0), Vector2.ZERO]:
		for strength in [0.0, 0.5, 1.0]:
			effects.reset()
			effects.rng.seed = 7331
			effects.spawn_success(CENTRE, 123.0, Color.WHITE, 1.0, strength, "GOOD", Vector2(10, 20), 1.0, false, direction)
			_check(effects.particles.size() == int(round(10.0 + 24.0 * strength)), "routine particle count retains its 10-to-34 power scale")
			_check(effects.popups.size() == 1 and float(effects.popups[0].amount) == 123.0 and effects.popups[0].anchor == Vector2(10, 20), "routine completion retains its reward packet and destination")
			_check_no_accent(effects, "routine particles at strength %.1f" % strength)
			_check_cone(effects, direction, "routine particle cone")

	for strength in [0.0, 0.21, 0.22, 1.0]:
		effects.reset()
		effects.spawn_success(CENTRE, 123.0, Color.WHITE, 1.0, strength, "PERFECT", Vector2.ZERO, 1.0, true)
		_check(effects.rings.size() == (1 if strength >= 0.22 else 0), "accent ring retains its independent 0.22 strength gate")
		_check(is_equal_approx(effects.flash_strength, 0.07 + 0.19 * strength), "accent flash retains its 0.07-to-0.26 strength scale")
	effects.reset()
	effects.spawn_success(CENTRE, 1.0, Color.WHITE, 1.0, 1.0, "PERFECT", Vector2.ZERO, 0.0, true)
	_check(effects.rings.size() == 1 and is_zero_approx(effects.flash_strength), "explicit zero flash scale retains an accented ring without viewport flash")


func _test_meteor_routing(game) -> void:
	# High economy and a live twelve-link chain must never become category gates.
	for node_id in ["perfect_observation", "draco_synthesis", "draco_apotheosis"]:
		game.progression.purchased_nodes[node_id] = true
	for type_id in ROUTINE_TYPES:
		for was_manual in [false, true]:
			for grade in ["GOOD", "EXCELLENT", "PERFECT"]:
				game.effects.reset()
				game.progression.reset_manual_combo()
				for _link in range(12):
					game.progression.record_manual_combo_success()
				var accented: bool = was_manual and grade in ["EXCELLENT", "PERFECT"]
				_check(game._is_accented_observation(type_id, was_manual, grade) == accented, "routine type category depends only on manual high grade: %s/%s/%s" % [type_id, was_manual, grade])
				_observe(game, type_id, was_manual, grade)
				if accented:
					_check(game.effects.rings.size() == 1 and game.effects.flash_strength > 0.0, "manual high grade receives an accent: " + type_id)
					_check(game.effects.kick_amplitude > 0.0 and game.effects.shake_trauma > 0.0, "accent plus a full chain permits manual motion: " + type_id)
				else:
					_check_no_accent(game.effects, "routine %s/%s/%s with high economy and long combo" % [type_id, was_manual, grade])
					_check_cone(game.effects, Vector2(140.0, 70.0), "game passes routine meteor travel into its particle cone")
				_check(not game.hitstop_active, "non-impact types never gain hitstop from grade or combo")

	for type_id in IMPACT_TYPES:
		for was_manual in [false, true]:
			game.effects.reset()
			game.hitstop_cooldown_until_msec = 0
			_check(game._is_accented_observation(type_id, was_manual, "GOOD"), "rare identity is accented independently of grade")
			_observe(game, type_id, was_manual, "GOOD")
			_check(game.effects.rings.size() == 1 and game.effects.flash_strength > 0.0, "rare identity retains its ring and flash")
			_check((game.effects.kick_amplitude > 0.0) == was_manual and (game.effects.shake_trauma > 0.0) == was_manual, "automatic rare completions cannot move the view")
			_check(game.hitstop_active == was_manual, "strong impact types keep manual-only hitstop")
			game._release_hitstop()

	game.effects.reset()
	game.progression.reset_manual_combo()
	_observe(game, "common", true, "EXCELLENT")
	_check(game.effects.kick_amplitude > 0.0 and is_zero_approx(game.effects.shake_trauma), "an accent below 0.50 strength gets a kick but not shake")
	game.effects.reset()
	game.progression.purchased_nodes["galactic_reference_frame"] = true
	_observe(game, "common", true, "PERFECT")
	_check(game.effects.rings.size() == 1 and is_zero_approx(game.effects.flash_strength), "galaxy-stage common high-grade accent still respects existing flash suppression")
	game.progression.purchased_nodes.erase("galactic_reference_frame")


func _test_distant_and_event_paths(game) -> void:
	var target := DistantFixture.new()
	game.add_child(target)
	target.position = CENTRE
	game.effects.reset()
	game._on_host_harvested(target, 120.0, 1.0, true, "GOOD", 1)
	_check(game.effects.rings.size() == 1 and game.effects.flash_strength > 0.0, "distant-host harvest is explicitly accented despite ordinary grade")
	game.effects.reset()
	game._on_galactic_phenomenon_observed(target, 120.0, 1.0, "GOOD")
	_check(game.effects.rings.size() == 1 and is_zero_approx(game.effects.flash_strength), "galactic phenomenon keeps its explicit accent and zero-flash contract")
	target.free()

	# Origin metadata prevents recursive rewards; it is not an accent category.
	for origin in ["gemini_echo", "leonid_storm", "perseid_outburst", "polar_summoned"]:
		game.effects.reset()
		_observe(game, "common", true, "GOOD", origin)
		_check_no_accent(game.effects, "event-origin routine completion stays quiet: " + origin)
		game.effects.reset()
		_observe(game, "fireball", true, "GOOD", origin)
		_check(game.effects.rings.size() == 1 and game.effects.flash_strength > 0.0, "event-origin rare completion retains identity accent: " + origin)
		game._release_hitstop()


func _test_caps(effects) -> void:
	effects.reset()
	for index in range(100):
		effects.spawn_success(CENTRE, 100.0, Color.WHITE, 1.0, 1.0, "PERFECT", Vector2.ZERO, 1.0, index % 2 == 0, Vector2.RIGHT)
	_check(effects.particles.size() == effects.MAX_PARTICLES, "mixed routine/accent bursts fill but never exceed the particle cap")
	_check(effects.rings.size() == effects.MAX_RINGS, "accented bursts fill but never exceed the ring cap")
	_check(effects.popups.size() == effects.MAX_POPUPS, "all categories preserve the packet cap")
	effects.reset()
	_check_no_accent(effects, "reset clears all feedback channels")
	_check(effects.particles.is_empty() and effects.popups.is_empty(), "reset clears particles and packets")


func _test_installation_rule(game) -> void:
	game.effects.reset()
	paused = true
	game._on_upgrade_purchased({"id": "better_lens"})
	_check_no_accent(game.effects, "research installation never flashes or moves the sky")
	_check(game.effects.particles.is_empty() and game.effects.popups.is_empty(), "research installation cannot generate meteor particles or packets")
	_check(game.hud.banner_root.visible and is_equal_approx(game.hud.banner_rule.scale.x, 0.2), "installation extends the existing visible rule from 20 percent width")
	_check(is_equal_approx(game.hud.banner_rule.size.y, 1.0) and is_equal_approx(game.hud.banner_rule.scale.y, 1.0), "installation keeps the existing one-pixel rule thickness")
	var first_tween: Tween = game.hud.installation_tween
	first_tween.pause()
	first_tween.custom_step(0.14)
	_check(is_equal_approx(game.hud.banner_rule.scale.x, 0.9), "installation reaches the cubic-out midpoint after 140 ms")
	game.hud.pulse_installation_rule()
	var replacement: Tween = game.hud.installation_tween
	_check(replacement != first_tween and not first_tween.is_valid(), "repeated installation kills and replaces the old tween")
	_check(is_equal_approx(game.hud.banner_rule.scale.x, 0.2), "replacement restarts from 20 percent instead of accumulating scale")
	await create_timer(0.05, true, false, true).timeout
	_check(game.hud.banner_rule.scale.x > 0.2, "installation tween advances while the world is paused")
	game.hud.pulse_installation_rule()
	var final_tween: Tween = game.hud.installation_tween
	final_tween.pause()
	final_tween.custom_step(0.28)
	_check(game.hud.banner_rule.scale.is_equal_approx(Vector2.ONE), "installation reaches the original width exactly at 280 ms")
	game.hud.pulse_installation_rule()
	var interrupted: Tween = game.hud.installation_tween
	game.hud.show_banner("OTHER EVENT")
	_check(not interrupted.is_valid() and game.hud.banner_rule.scale.is_equal_approx(Vector2.ONE), "a new banner cancels installation motion and restores full width")
	_check_no_accent(game.effects, "paused installation and replacement leave sky feedback unchanged")
	paused = false


func _test_chart_installation_rule(game) -> void:
	var chart = game.upgrade_tree
	game.progression.reset()
	game.progression.observation_data = 1000000000000.0
	game.effects.reset()
	var old_hud_tween: Tween = game.hud.installation_tween
	chart.open_tree()
	await process_frame
	await process_frame
	chart._on_node_hovered("better_lens")
	_check(game.progression.request_purchase("better_lens"), "open-chart integration buys a real available research node")
	var rule: ColorRect = chart.constellation_installation_rule
	_check_chart_rule(chart, rule, "constellation purchase")
	_check(chart.installation_node_id == "better_lens", "constellation pulse belongs to the selected research")
	_check(game.hud.installation_tween == old_hud_tween, "open-chart purchase does not start a hidden HUD pulse")
	var first_tween: Tween = chart.installation_tween
	first_tween.pause()
	first_tween.custom_step(0.14)
	_check(is_equal_approx(rule.scale.x, 0.9), "chart pulse uses the same 140 ms cubic-out midpoint")
	chart.pulse_installation_rule()
	var replacement: Tween = chart.installation_tween
	_check(replacement != first_tween and not first_tween.is_valid(), "chart repeat replaces its previous pulse")
	await create_timer(0.05, true, false, true).timeout
	_check(rule.scale.x > 0.2 and rule.scale.x < 1.0 and replacement.is_running(), "chart pulse survives deferred layout and progression refresh while paused (scale %.4f, valid %s, context %s)" % [rule.scale.x, replacement.is_valid(), chart.installation_node_id])
	chart._on_node_hovered("long_exposure")
	_check(not replacement.is_valid() and rule.scale.is_equal_approx(Vector2.ONE), "constellation selection cancels the prior research pulse")
	_check(game.progression.request_purchase("long_exposure"), "a second chart research purchase succeeds")
	_check_chart_rule(chart, rule, "second constellation purchase")
	var second_tween: Tween = chart.installation_tween
	await process_frame
	await process_frame
	_check(second_tween.is_running() and rule.scale.x > 0.2 and rule.scale.x < 1.0, "actual repeated purchase pulse survives the following state_changed and layout frames")
	chart._refresh_phase_context()
	_check(not second_tween.is_valid() and rule.scale.is_equal_approx(Vector2.ONE), "phase context refresh cancels stale installation feedback")
	chart.pulse_installation_rule()
	var close_tween: Tween = chart.installation_tween
	chart.close_tree()
	_check(not close_tween.is_valid() and rule.scale.is_equal_approx(Vector2.ONE), "closing the chart cancels and resets its inspector rule")

	# Configure a completed first sky without purchasing it through persistence.
	for definition in Balance.UPGRADE_NODES:
		if String(definition.branch) != "local_group":
			game.progression.purchased_nodes[String(definition.id)] = true
	game.galactic_pullback_seen = true
	chart.configure_galactic_state(true, true)
	chart.open_tree()
	await process_frame
	await process_frame
	chart._on_node_hovered("lmc_transit_watch")
	var old_balance: float = game.progression.observation_data
	chart._on_node_hold_started("lmc_transit_watch")
	chart._process(1.0)
	chart.pulse_installation_rule()
	_check(chart.galaxy_hub.is_visible_in_tree(), "galaxy scale is a destination hub")
	_check(chart.installation_rule == null and not chart.galactic_panel.is_visible_in_tree(), "destination navigation never animates the retired purchase inspector")
	_check(not game.progression.has_upgrade("lmc_transit_watch") and game.progression.observation_data == old_balance, "retired Local Group holds cannot buy research")
	chart.galaxy_hub.select_destination("andromeda")
	_check(game.hud.installation_tween == old_hud_tween, "selecting a destination does not dispatch purchase feedback")
	chart.close_tree()

	# Galactic Reference Frame owns the existing pull-back, where neither
	# inspector is visible; do not replace it with another hidden animation.
	game.progression.purchased_nodes.erase("galactic_reference_frame")
	game.galactic_pullback_seen = false
	chart.configure_galactic_state(false, false)
	chart.open_tree()
	await process_frame
	chart._on_node_hovered("galactic_reference_frame")
	_check(game.progression.request_purchase("galactic_reference_frame"), "reference-frame purchase starts its real presentation transition")
	_check(chart.galactic_mode == chart.GALACTIC_MODE_PULLBACK, "reference-frame installation retains its own visible pull-back")
	_check(chart.installation_rule == null and not chart.tooltip_panel.visible and not chart.galactic_panel.visible, "pull-back does not start a pulse under either hidden inspector")
	_check(game.hud.installation_tween == old_hud_tween, "pull-back never starts an obscured HUD pulse")
	chart.close_tree()
	_check_no_accent(game.effects, "chart installation never adds meteor feedback")
	paused = false


func _check_chart_rule(chart, rule: ColorRect, context: String) -> void:
	_check(chart.is_open() and paused, context + " uses the actually opened, paused chart")
	_check(chart.installation_rule == rule and rule.is_visible_in_tree(), context + " animates the active inspector rule")
	_check(rule.get_canvas_layer_node() == chart, context + " draws above the opaque chart background on its own canvas")
	_check(rule.size.x > 1.0 and root.get_visible_rect().encloses(rule.get_global_rect()), context + " has an on-screen, nonempty rule")
	_check(is_equal_approx(rule.scale.x, 0.2) and is_equal_approx(rule.scale.y, 1.0) and is_equal_approx(rule.size.y, 1.0), context + " keeps the one-pixel rule with the 20 percent starting width")


func _observe(game, type_id: String, was_manual: bool, grade: String, origin: String = "gemini_echo") -> void:
	var target = game.spawner.spawn_meteor(type_id, CENTRE, Vector2(140.0, 70.0), 10.0)
	_check(target != null, "observation fixture spawns: " + type_id)
	if target == null:
		return
	target.set_meta(origin, true)
	target.alive = false
	game._on_meteor_observed(target, 100.0, 1.0, was_manual, grade)
	_check(not game.effects.particles.is_empty() and game.effects.popups.size() == 1, "all completed observations retain particles and a reward packet")
	target.free()


func _check_no_accent(effects, context: String) -> void:
	_check(effects.rings.is_empty() and is_zero_approx(effects.flash_strength) and is_zero_approx(effects.kick_amplitude) and is_zero_approx(effects.shake_trauma), context)


func _check_cone(effects, direction: Vector2, context: String) -> void:
	var heading := Vector2.UP if direction.is_zero_approx() else direction.normalized()
	var all_inside: bool = not effects.particles.is_empty()
	for particle in effects.particles:
		if absf(heading.angle_to(Vector2(particle.v))) > 0.55 + 0.000001:
			all_inside = false
	_check(all_inside, context)
