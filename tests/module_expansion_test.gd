extends SceneTree

const Balance = preload("res://scripts/game_balance.gd")
const Meteor = preload("res://scripts/meteor.gd")
const Modules = preload("res://scripts/observation_modules.gd")
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
	_check_shutter_and_dish_contract()
	_check_meteor_contribution_contract()
	_check_trail_observation_contract()
	_check_sweep_charge_contract()
	_check_same_frame_completion()
	_check_duplicate_effects()
	if failures.is_empty():
		print("MODULE_EXPANSION_PASS: 14 module metadata, bounded effects, shutter state, trail/manual provenance and sweep charge")
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
	_check(Modules.DEFINITIONS.size() == 14, "the five purchased and nine expansion modules are defined")
	_check(Modules.RESEARCH_IDS.size() == 8 and "trail_integrator" not in Modules.RESEARCH_IDS, "only the original eight chart purchases remain research IDs")
	for id in ["trail_integrator", "sweep_optics", "relay_bus"]:
		var definition: Dictionary = Modules.DEFINITIONS[id]
		_check(definition.source == "research" and String(definition.category) in ["trace", "sweep", "link"] and String(definition.pool).is_empty(), id + " is research-granted metadata")
	for id in ["long_baseline", "dual_processor", "afterglow_archive", "wide_correlation", "reference_bus", "shutter_weave"]:
		var definition: Dictionary = Modules.DEFINITIONS[id]
		_check(definition.source == "sample" and String(definition.pool) == String(definition.category), id + " has its matching specimen pool")
	var legacy := Modules.configuration(["focus", "wide", "record"])
	_check(is_equal_approx(float(legacy.speed), 1.08) and is_equal_approx(float(legacy.radius), 1.65) and is_equal_approx(float(legacy.m31_value), 1.5), "legacy speed, radius and M31 value effects are unchanged")
	var expanded := Modules.configuration(["sweep_optics", "trail_integrator", "relay_bus", "shutter_weave"])
	_check(is_equal_approx(float(expanded.new_speed), 0.729) and is_equal_approx(float(expanded.sweep_charge), 1.35) and is_equal_approx(float(expanded.rare_radius), 1.5), "new generic penalties and sweep effects remain separate from legacy speed")
	_check(is_equal_approx(float(expanded.m31_value), 1.0) and is_equal_approx(float(expanded.m31_cooldown), 1.25), "shutter changes cooldown but never M31 data value")


func _check_slot_and_inventory_contract() -> void:
	var model = Modules.new()
	_check(model.research_ready("slot_3") and not model.research_ready("slot_4"), "slot capacity remains sequential without forced module purchases")
	model.unlocked_slots = 3
	_check(model.research_ready("revisit"), "revisit still requires the third slot")
	_check(model.grant("trail_integrator") and model.research_owned("trail_integrator") and not model.has("trail_integrator"), "reward grants ownership without auto-equipping")
	_check(model.equip("trail_integrator", 0) and model.has("trail_integrator"), "has reports an active installed module")


func _check_shutter_and_dish_contract() -> void:
	var shutter = _installed(["shutter_weave"])
	var completed := MockTarget.new()
	completed.manual_contribution = 0.25
	_check(shutter.notify_completed(completed) and shutter.shutter_active(), "a natural target with 25% manual work refreshes shutter")
	shutter.advance_time(2.0)
	var restored = Modules.new()
	restored.load_save_data(shutter.get_save_data())
	_check(restored.shutter_active() and is_equal_approx(restored.shutter_remaining, 3.0), "runtime shutter duration survives save/load")
	completed.type_id = "fragment"
	_check(not shutter.notify_completed(completed), "fragments cannot refresh shutter")
	completed.type_id = "common"
	completed.manual_contribution = 0.249
	_check(not shutter.notify_completed(completed), "sub-threshold manual work cannot refresh shutter")
	completed.free()

	var dishes = _installed(["relay_bus", "reference_bus"])
	var ordinary := MockTarget.new()
	ordinary.manual_contribution = 0.25
	_check(is_equal_approx(dishes.dish_multiplier(ordinary), 1.75), "relay affects actual dish work after manual contribution")
	dishes.set_m31_manual_active(true)
	_check(is_equal_approx(dishes.dish_multiplier(ordinary), 2.5), "manual M31 cross-feeds other dish work while combined new modifiers respect their x2.5 cap")
	ordinary.type_id = "andromeda"
	_check(is_equal_approx(dishes.dish_multiplier(ordinary), 1.75), "Reference Bus never makes M31 an automatic dish target")
	ordinary.type_id = "common"
	dishes.set_m31_manual_active(false)
	_check(is_equal_approx(dishes.dish_multiplier(ordinary), 1.75), "reference requires a live M31 manual contact")
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
	target.applications = 0
	target.position = Vector2(50.0, 0.0)
	_check(observer._apply_manual_contact(target, 1.0) and target.applications == 1 and is_equal_approx(target.last_speed, 0.9), "head contact does not double-apply the trail path")
	target.type_id = "andromeda"
	_check(observer._apply_manual_contact(target, 0.1) and modules.m31_manual_active(), "a live M31 contact is exposed to dish logic")
	observer._notification(Node.NOTIFICATION_PAUSED)
	_check(not modules.m31_manual_active(), "pausing clears the transient M31 manual-contact flag")
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
	target.type_id = "andromeda"
	observer.modules = _installed(["reference_bus", "reference_bus"])
	_check(is_equal_approx(observer._module_manual_speed_for_target(target), 0.5), "two reference M31 penalties add")
	target.type_id = "common"
	observer.modules.set_m31_manual_active(true)
	_check(is_equal_approx(observer.modules.dish_multiplier(target), 2.2), "two reference dish bonuses add")
	target.type_id = "andromeda"
	observer.modules = _installed(["shutter_weave", "shutter_weave"])
	observer.modules.shutter_remaining = 5.0
	_check(is_equal_approx(observer._module_manual_speed_for_target(target), 1.7), "two shutter conditional bonuses add")
	observer.progression.free()
	observer.free()
	target.free()
