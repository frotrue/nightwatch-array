extends SceneTree

const Balance = preload("res://scripts/game_balance.gd")
const Meteor = preload("res://scripts/meteor.gd")
const Modules = preload("res://scripts/observation_modules.gd")
const Expansion = preload("res://scripts/expansion_data.gd")
const Observer = preload("res://scripts/observation_controller.gd")
const Survey = preload("res://scripts/survey_controller.gd")

var failures: Array[String] = []


class MockProgression:
	extends Node
	func extension_effect(_key: String, fallback: float = 1.0) -> float:
		return fallback

	func galaxy_unlocked() -> bool:
		return true

	func get_manual_analysis_speed_multiplier() -> float:
		return 1.0

	func get_tracking_radius() -> float:
		return 10.0

	func survey_enabled() -> bool:
		return true

	func get_survey_required_distance() -> float:
		return 1000.0

	func get_survey_spawn_probability() -> float:
		return 0.0

	func get_survey_spawn_count() -> int:
		return 1

	func has_upgrade(_id: String) -> bool:
		return false

	func get_survey_cooldown_seconds() -> float:
		return 1.0


class MockTarget:
	extends Node2D
	var type_id := "common"
	var manual_contribution := 0.0
	var natural := true
	var trail := PackedVector2Array()
	var applications := 0
	var last_speed := 0.0
	var observer_owner: Node
	var alive := true

	func can_be_tracked() -> bool:
		return alive

	func get_tracking_radius(base_radius: float) -> float:
		return base_radius

	func apply_manual_observation(_delta: float, _distance: float, _radius: float, speed: float = 1.0) -> void:
		applications += 1
		last_speed = speed
		if observer_owner != null:
			alive = false
			observer_owner.release_target(self)

	func get_manual_contribution() -> float:
		return manual_contribution

	func get_automatic_contribution() -> float:
		return 0.0

	func get_recent_observation_trail() -> PackedVector2Array:
		return trail

	func is_natural_observation() -> bool:
		return natural


class DummySpawner:
	extends Node


class MockHud:
	extends CanvasLayer
	func hide_tracking() -> void:
		pass


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_definition_contract()
	_check_slot_and_inventory_contract()
	_check_dish_contract()
	_check_meteor_contribution_contract()
	_check_trail_observation_contract()
	_check_sweep_charge_contract()
	_check_same_frame_completion()
	_check_duplicate_effects()
	if failures.is_empty():
		print("MODULE_EXPANSION_PASS: 10 module metadata, bounded effects, dish contribution, trail/manual provenance and sweep charge")
		quit(0)
	else:
		push_error(str(failures))
		quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures.append(message)
	push_error("MODULE_EXPANSION: " + message)


func _installed(ids: Array[String]) -> RefCounted:
	var model = Modules.new()
	model.unlocked_slots = Modules.MAX_SLOTS
	for id in ids:
		model.grant_copy(id)
		model.equip(id)
	return model


func _check_definition_contract() -> void:
	_check(Modules.DEFINITIONS.size() == 10 and Expansion.SAMPLE_MODULES.size() == 10, "all ten modules are in the current draw pool")
	_check(Modules.RESEARCH_IDS.size() == 6 and "trail_integrator" not in Modules.RESEARCH_IDS, "the retained diagnostic purchase IDs remain compatible")
	for id in Modules.DEFINITIONS:
		var definition: Dictionary = Modules.DEFINITIONS[id]
		_check(Expansion.SAMPLE_MODULES.count(id) == 1 and definition.source == "sample" and String(definition.pool) == String(definition.category), id + " occurs once in the equal-odds draw with matching acquisition metadata")
	var expanded := Modules.configuration(["sweep_optics", "trail_integrator", "relay_bus"])
	_check(is_equal_approx(float(expanded.new_speed), 0.729) and is_equal_approx(float(expanded.sweep_charge), 1.35) and is_equal_approx(float(expanded.rare_radius), 1.5), "new generic penalties and sweep effects remain separate from legacy speed")


func _check_slot_and_inventory_contract() -> void:
	var model = Modules.new()
	_check(model.research_ready("slot_3") and not model.research_ready("slot_4"), "slot capacity remains sequential without forced module purchases")
	model.unlocked_slots = 3
	_check(model.grant("trail_integrator") and model.research_owned("trail_integrator") and not model.has("trail_integrator"), "reward grants ownership without auto-equipping")
	_check(model.equip("trail_integrator", 0) and model.has("trail_integrator"), "has reports an active installed module")


func _check_dish_contract() -> void:
	var dishes = _installed(["relay_bus"])
	var ordinary := MockTarget.new()
	ordinary.manual_contribution = 0.249
	_check(is_equal_approx(dishes.dish_multiplier(ordinary), 1.0), "relay requires 25 percent manual contribution")
	ordinary.manual_contribution = 0.25
	_check(is_equal_approx(dishes.dish_multiplier(ordinary), 1.75), "relay affects dish work at the contribution threshold")
	ordinary.free()


func _check_meteor_contribution_contract() -> void:
	var meteor = Meteor.new()
	meteor.configure(Balance.meteor_spec("common"), "common", Vector2.ZERO, Vector2.RIGHT * 100.0, 1.0, {})
	meteor.apply_manual_observation(0.2, 0.0, 10.0)
	_check(meteor.get_manual_contribution() > 0.0 and meteor.get_automatic_contribution() == 0.0, "ordinary meteor exposes normalized manual and automatic work separately")
	_check(meteor.get_recent_observation_trail().size() == 1, "ordinary meteor exposes a recent observation trail")
	root.add_child(meteor)
	meteor.set_process(false)
	meteor.max_trail_points = 3
	meteor.observation_progress = 0.0
	for _step in range(45): meteor._process(0.025)
	_check(meteor.get_recent_observation_trail().size() >= 39 and meteor.trail_points.size() == 3, "one-second interaction trail is independent of visual ribbon point limit")
	meteor.observation_progress = 0.99
	meteor.manual_contribution = 0.0
	meteor.automatic_contribution = 0.99
	meteor.apply_manual_observation(1.0, 0.0, 10.0)
	_check(meteor.get_manual_contribution() < 0.011, "last-percent manual finish cannot claim25percent contribution")
	_check(meteor.is_natural_observation(), "ordinary unprocured meteor is natural")
	meteor.set_meta("polar_summoned", true)
	_check(not meteor.is_natural_observation(), "summoned meteors cannot be treated as natural shutter sources")
	meteor.free()


func _check_trail_observation_contract() -> void:
	var modules = _installed(["trail_integrator"])
	var observer = Observer.new()
	observer.modules = modules
	var progression := MockProgression.new()
	observer.progression = progression
	observer.hud = MockHud.new()
	var target := MockTarget.new()
	target.position = Vector2.ZERO
	target.trail = PackedVector2Array([Vector2(50.0, 0.0)])
	observer.selected_meteor = target
	observer.previous_cursor_position = Vector2(50.0, 0.0)
	observer.cursor_position = Vector2(50.0, 0.0)
	_check(observer._apply_manual_contact(target, 1.0) and target.applications == 1 and is_equal_approx(target.last_speed, 0.54), "trail acquisition applies one 60% observation only when the head has no contact")
	modules.grant_copy("trail_integrator")
	modules.equip("trail_integrator")
	target.applications = 0
	_check(observer._apply_manual_contact(target, 1.0) and target.applications == 1 and is_equal_approx(target.last_speed, 0.96), "two trail copies add 60% work each before their two manual penalties")
	modules.equip("", 1)
	target.applications = 0
	target.position = Vector2(50.0, 0.0)
	_check(observer._apply_manual_contact(target, 1.0) and target.applications == 1 and is_equal_approx(target.last_speed, 0.9), "head contact does not double-apply the trail path")
	observer.release_target(target)
	observer.hud.free()
	observer.free()
	progression.free()
	target.free()


func _check_sweep_charge_contract() -> void:
	var survey = Survey.new()
	survey.progression = MockProgression.new()
	survey.spawner = DummySpawner.new()
	survey.meteor_layer = Node2D.new()
	survey.active_round = 1
	survey.scanning = true
	survey.modules = _installed(["sweep_optics"])
	survey.apply_scan_segment(Vector2.ZERO, Vector2(100.0, 0.0))
	_check(is_equal_approx(survey.charge_distance, 135.0), "Sweep Optics increases blank-sky charge without changing the guard radius")
	var progression: Node = survey.progression
	var spawner: Node = survey.spawner
	var layer: Node2D = survey.meteor_layer
	survey.free()
	progression.free()
	spawner.free()
	layer.free()

func _check_same_frame_completion() -> void:
	var observer = Observer.new()
	observer.modules = _installed(["wide", "dual_processor"])
	observer.progression = MockProgression.new()
	observer.hud = MockHud.new()
	observer.meteor_layer = Node2D.new()
	var targets: Array[Node] = []
	for index in range(3):
		var target := MockTarget.new()
		target.position = Vector2(index, 0)
		target.observer_owner = observer
		observer.meteor_layer.add_child(target)
		targets.append(target)
	observer.selected_meteor = targets[0]
	observer._update_manual_tracking(1.0)
	_check(is_equal_approx(targets[0].last_speed, 0.975) and is_equal_approx(targets[1].last_speed, 0.975) and is_equal_approx(targets[2].last_speed, 0.4125), "same-frame completion cannot promote every additional target into the dual boost")
	observer.meteor_layer.free()
	observer.progression.free()
	observer.hud.free()
	observer.free()

func _check_duplicate_effects() -> void:
	var wide := _installed(["wide", "wide"])
	_check(wide.effect("targets") == 5 and is_equal_approx(wide.effect("radius"), 2.3) and is_equal_approx(wide.effect("speed"), 0.5), "two wide copies add two extra targets and both radius bonuses and speed penalties")
	var focus := _installed(["focus", "focus"])
	_check(is_equal_approx(focus.effect("split_chance"), 0.6) and is_equal_approx(focus.effect("speed"), 1.0), "two split copies increase chance without restoring legacy speed")
	var capped := _installed(["focus", "focus", "focus", "focus", "focus"])
	_check(is_equal_approx(capped.effect("split_chance"), 1.0), "split chance caps at certainty")
	var restored := Modules.new()
	restored.load_save_data(JSON.parse_string(JSON.stringify(capped.get_save_data())))
	_check(restored.installed_count("focus") == 5 and is_equal_approx(restored.effect("split_chance"), 1.0), "old focus identity preserves copies and slots through JSON")
	var precision := _installed(["precision", "precision"])
	_check(is_equal_approx(precision.effect("speed"), 2.0) and is_equal_approx(precision.effect("radius"), 0.4), "two precision copies compose speed and radius penalties")
	var sweep := _installed(["sweep_optics", "sweep_optics"])
	_check(is_equal_approx(sweep.effect("sweep_charge"), 1.7) and is_equal_approx(sweep.effect("rare_radius"), 2.0), "sweep copies add both effects")
	var relay := _installed(["relay_bus", "relay_bus"])
	var assisted := MockTarget.new()
	assisted.manual_contribution = 0.25
	_check(is_equal_approx(relay.dish_multiplier(assisted), 2.5), "relay copies reach the actual dish cap")
	assisted.free()
	var observer = Observer.new()
	observer.progression = MockProgression.new()
	var target := MockTarget.new()
	observer.selected_meteor = target
	observer.modules = _installed(["long_baseline", "long_baseline"])
	observer.primary_tracking_seconds = 1.0
	_check(is_equal_approx(observer._module_manual_speed_for_target(target), 1.54), "two baseline bonuses and two penalties add before composing")
	observer.modules = _installed(["dual_processor", "dual_processor"])
	_check(is_equal_approx(observer._module_manual_speed_for_target(target), 1.6), "two dual primary bonuses add")
	observer.modules = _installed(["wide_correlation", "wide_correlation"])
	_check(is_equal_approx(observer._module_manual_speed_for_target(target), 0.5), "two correlation primary penalties add")
	observer.selected_meteor = null
	_check(is_equal_approx(observer._module_manual_speed_for_target(target), 1.7), "two correlation secondary bonuses add")
	target.free()
	observer.progression.free()
	observer.free()
