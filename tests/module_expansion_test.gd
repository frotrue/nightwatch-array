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
	var applications := 0
	var last_speed := 0.0
	var last_delta := 0.0
	var observer_owner: Node
	var alive := true

	func can_be_tracked() -> bool:
		return alive

	func get_tracking_radius(base_radius: float) -> float:
		return base_radius

	func apply_manual_observation(_delta: float, _distance: float, _radius: float, speed: float = 1.0) -> void:
		applications += 1
		last_delta = _delta
		last_speed = speed
		if observer_owner != null:
			alive = false
			observer_owner.release_target(self)

	func get_manual_contribution() -> float:
		return manual_contribution

	func get_automatic_contribution() -> float:
		return 0.0


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


func _run() -> void:
	_check_catalogue()
	_check_linear_geometry()
	_check_capture()
	_check_overcharge()
	_check_sweep_charge_contract()
	_check_completion_roles()
	if failures.is_empty():
		print("MODULE_EXPANSION_PASS: eight modules, swept line geometry, live field slowdown, burst lifecycle and retired inventory")
		quit(0)
	else:
		push_error(str(failures))
		quit(1)

func _check_catalogue() -> void:
	_check(Modules.DEFINITIONS.size() == 8 and Expansion.SAMPLE_MODULES.size() == 8, "exactly eight active modules")
	for id in Modules.DEFINITIONS:
		_check(Expansion.SAMPLE_MODULES.count(id) == 1, "uniform draw pool contains each active module once: " + id)
	var removed := ["trail_integrator", "relay_bus", "long_baseline", "dual_processor", "afterglow_archive"]
	var model = Modules.new()
	model.load_save_data({"purchased": removed + ["focus"], "slots": removed, "unlocked_slots": 5})
	_check(model.purchased == ["focus"] and model.installed_ids().is_empty(), "old inventory drops deleted modules instead of hiding them")
	for id in removed:
		_check(not Modules.DEFINITIONS.has(id) and not model.grant(id), "deleted effect cannot be granted: " + id)
	var copies := _installed(["linear_observation", "linear_observation", "capture_hold", "capture_hold"])
	_check(is_equal_approx(copies.stacked_effect("linear_observation", "line_width"), 7.0) and is_equal_approx(copies.stacked_effect("capture_hold", "motion_speed"), 0.4), "same-ID copies add rather than multiply")
	var restored = Modules.new()
	restored.load_save_data(JSON.parse_string(JSON.stringify(copies.get_save_data())))
	_check(restored.slots == copies.slots and restored.quantities == copies.quantities, "new module identities preserve copies and slots on disk")

func _check_linear_geometry() -> void:
	var observer := Observer.new()
	observer.progression = MockProgression.new()
	observer.modules = _installed(["linear_observation"])
	var target := MockTarget.new()
	target.position = Vector2(35, 0)
	_check(observer._apply_manual_contact(target, 1.0) and target.applications == 1, "line reaches a target outside the old circle")
	target.position = Vector2(0, 6)
	_check(not observer._apply_manual_contact(target, 1.0), "line excludes a target beyond its vertical edge")
	target.position = Vector2.ZERO
	observer.previous_cursor_position = Vector2(0, -100)
	observer.cursor_position = Vector2(0, 100)
	_check(observer._apply_manual_contact(target, 1.0) and is_equal_approx(target.last_delta, 0.045), "fast sweep credits only the 9px portion of a 200px path inside the band")
	observer.previous_cursor_position = Vector2(50, 0)
	observer.cursor_position = Vector2(0, 10)
	_check(observer._apply_manual_contact(target, 1.0) and is_equal_approx(target.last_delta, 0.25), "diagonal clipping uses intersection of both axes")
	observer.modules.equip("", 0)
	observer.previous_cursor_position = Vector2.ZERO
	observer.cursor_position = Vector2.ZERO
	target.position = Vector2(35, 0)
	_check(not observer._apply_manual_contact(target, 1.0), "unequipping restores the circular footprint")
	target.free()
	observer.progression.free()
	observer.free()

func _check_capture() -> void:
	var added_action := not InputMap.has_action(&"nw_observe")
	if added_action: InputMap.add_action(&"nw_observe")
	Input.action_press(&"nw_observe")
	var meteor := Meteor.new()
	var control := Meteor.new()
	for target in [meteor, control]:
		target.configure(Balance.meteor_spec("common"), "common", Vector2(200, 200), Vector2(100, 0), 10.0, {})
		root.add_child(target)
		target.set_process(false)
		target.required_track_time = 100.0
	var observer := Observer.new()
	observer.progression = MockProgression.new()
	observer.modules = _installed(["capture_hold"])
	observer.cursor_position = meteor.position
	meteor.observation_controller = observer
	meteor.set_dish_assist_rate(0.1)
	meteor._process(1.0)
	control._process(0.7)
	_check(meteor.position.is_equal_approx(control.position) and is_equal_approx(meteor.age, 0.7), "inside field advances motion and burnout at 70%")
	_check(meteor.observation_progress >= 0.1, "slowdown leaves actual dish observation work unchanged")
	_check(observer.motion_multiplier_for(meteor) == 1.0, "meteor leaving the field immediately loses slowdown")
	observer.cursor_position = meteor.position
	_check(is_equal_approx(observer.motion_multiplier_for(meteor), 0.7), "reentering reapplies slowdown without a one-shot flag")
	Input.action_release(&"nw_observe")
	_check(observer.motion_multiplier_for(meteor) == 1.0, "button release removes slowdown without waiting for contact refresh")
	Input.action_press(&"nw_observe")
	observer.modules.equip("", 0)
	_check(observer.motion_multiplier_for(meteor) == 1.0, "unequip removes slowdown immediately")
	observer.modules = _installed(["capture_hold", "linear_observation"])
	observer.cursor_position = meteor.position + Vector2(35, 0)
	_check(is_equal_approx(observer.motion_multiplier_for(meteor), 0.7), "line slows targets beyond the circular field")
	observer.cursor_position = meteor.position + Vector2(0, 6)
	_check(observer.motion_multiplier_for(meteor) == 1.0, "line does not slow targets beyond its thin vertical bounds")
	observer.cursor_position = meteor.position
	observer.modules = _installed(["capture_hold", "capture_hold", "capture_hold", "capture_hold", "capture_hold"])
	_check(is_equal_approx(observer.motion_multiplier_for(meteor), 0.1), "stacked slowdown never stops time completely")
	Input.action_release(&"nw_observe")
	if added_action: InputMap.erase_action(&"nw_observe")
	meteor.free()
	control.free()
	observer.progression.free()
	observer.free()

func _check_overcharge() -> void:
	var modules := _installed(["overcharge"])
	for index in range(30):
		var source := Node.new()
		modules.record_completion(source)
		modules.record_completion(source)
		source.free()
		if index < 29: _check(modules.burst_remaining == 0.0, "one completion counts once")
	_check(modules.burst_remaining == 9.0 and modules.charge_count == 0, "thirty completed targets start one bounded burst")
	var source := Node.new()
	modules.record_completion(source)
	source.free()
	_check(modules.charge_count == 0, "burst cannot recharge itself")
	modules.advance_time(2.0)
	var restored := _installed(["overcharge"])
	restored.restore_round_state(JSON.parse_string(JSON.stringify(modules.get_round_state())))
	_check(restored.burst_remaining == 7.0 and restored.burst_multiplier("burst_speed") == 2.0, "active burst survives real JSON without restarting its duration")
	restored.advance_time(6.5)
	_check(restored.burst_multiplier("burst_speed") == 2.0, "burst remains active until all nine seconds are spent")
	restored.advance_time(0.5)
	_check(restored.burst_multiplier("burst_speed") == 1.0, "burst ends exactly at the boundary")
	modules.equip("", 0)
	modules.equip("overcharge", 0)
	_check(modules.burst_remaining == 0.0 and modules.charge_count == 0, "equipment swap cannot bank or restore a burst")
	modules.restore_round_state({"charge_count": INF, "burst_remaining": NAN})
	_check(modules.burst_remaining == 0.0 and modules.charge_count == 0, "malformed runtime numbers are rejected")
	modules.restore_round_state({"charge_count": 7})
	modules.reset_round()
	_check(modules.charge_count == 0, "new round clears partial charge")
	var observer := Observer.new()
	observer.progression = MockProgression.new()
	observer.modules = _installed(["overcharge", "overcharge", "wide"])
	observer.modules.restore_round_state({"burst_remaining": 3.0})
	_check(is_equal_approx(observer._module_manual_speed(), 2.25) and is_equal_approx(observer._module_tracking_radius(), 33.0), "burst copies compose with the retained wide module in production speed and radius")
	observer.progression.free()
	observer.free()

func _check_completion_roles() -> void:
	var observer := Observer.new()
	observer.modules = _installed(["linear_observation", "wide_correlation"])
	observer.progression = MockProgression.new()
	observer.hud = MockHud.new()
	observer.meteor_layer = Node2D.new()
	var targets: Array[Node] = []
	for x in [-30, 0, 30]:
		var target := MockTarget.new()
		target.position = Vector2(x, 0)
		target.observer_owner = observer
		observer.meteor_layer.add_child(target)
		targets.append(target)
	observer.selected_meteor = targets[0]
	observer._update_manual_tracking(1.0)
	_check(targets.all(func(target): return target.applications == 1), "line observes all contacted targets without requiring multi-target research")
	_check(is_equal_approx(targets[0].last_speed, 0.75) and is_equal_approx(targets[1].last_speed, 1.35) and is_equal_approx(targets[2].last_speed, 1.35), "synchronous completion cannot promote secondary targets into the primary role")
	observer.meteor_layer.free()
	observer.progression.free()
	observer.hud.free()
	observer.free()

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
	var charge: float = survey.charge_distance
	survey.modules = _installed(["linear_observation"])
	_check(survey.uses_linear_feedback() and survey.has_visible_feedback(), "linear mode gives survey feedback to the cursor instead of drawing a ring")
	_check(is_equal_approx(survey.get_visual_feedback().progress, 0.135), "linear feedback reads existing charge without changing it")
	survey.cooldown_duration = 4.0
	survey.cooldown_remaining = 3.0
	_check(is_equal_approx(survey.get_visual_feedback().progress, 0.25) and survey.charge_distance == charge, "cooldown replaces visible progress without spending preserved charge")
	survey.advance_time(1.0)
	_check(is_equal_approx(survey.get_visual_feedback().progress, 0.5), "stationary cooldown feedback follows the real timer")
	survey.modules.equip("", 0)
	_check(not survey.uses_linear_feedback() and survey.has_visible_feedback(), "unequip restores the ordinary survey feedback")
	survey.end_round()
	_check(survey.get_visual_feedback().is_empty(), "ended round leaves no survey indicator")
	var progression: Node = survey.progression
	var spawner: Node = survey.spawner
	var layer: Node2D = survey.meteor_layer
	survey.free()
	progression.free()
	spawner.free()
	layer.free()
