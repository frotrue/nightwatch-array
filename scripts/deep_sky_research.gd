extends Node2D

signal changed
const Modules = preload("res://scripts/observation_modules.gd")
const Target = preload("res://scripts/andromeda_target.gd")
const UITheme = preload("res://scripts/ui_theme.gd")
var game: Node
var modules = Modules.new()
var observations := 0
var target: Node2D
var _last_available := false

func setup(controller: Node) -> void:
	game = controller
	target = Target.new()
	target.research = self
	add_child(target)
	game.progression.state_changed.connect(_on_progression_changed)
	game.settings.language_changed.connect(func(_locale): target.queue_redraw())
	_last_available = available()
	target.visible = _last_available

func _on_progression_changed() -> void:
	var unlocked := available()
	target.visible = unlocked
	if unlocked != _last_available:
		_last_available = unlocked
		changed.emit()

func available() -> bool:
	return game != null and game.progression.galaxy_unlocked()

func modules_unlocked() -> bool:
	return available() and (observations > 0 or not modules.purchased.is_empty())

func can_purchase(id: String) -> bool:
	return modules_unlocked() and modules.research_ready(id) and game.progression.observation_data >= modules.research_cost(id)

func purchase(id: String) -> bool:
	if not modules_unlocked() or not game.upgrade_tree.is_open() or game.module_popup.is_open() or game.hud.is_settings_open():
		return false
	if not modules.purchase(id, game.progression):
		return false
	game.sound.play_upgrade()
	changed.emit()
	game._autosave_active_slot()
	return true

func equip(id: String, slot: int = -1) -> bool:
	if not modules_unlocked() or not game.module_popup.is_open() or not modules.equip(id, slot):
		return false
	game.observer.reset()
	game.sound.play_slot_confirm()
	changed.emit()
	game._autosave_active_slot()
	return true

func record_observation() -> void:
	observations += 1
	game.observer.release_target(target)
	var reward: float = 8000.0 * game.progression.get_observation_value_multiplier("common", 1) * float(modules.effect("m31_value"))
	reward = game.progression.add_galactic_observation(reward)
	game.effects.spawn_success(target.global_position, reward, Color("D4DAE5"), 1.0, 1.0, "GOOD", game.hud.get_data_anchor(), 0.4, true)
	game.sound.play_success(1.0, 1, 0.4)
	if observations == 1:
		game.hud.show_banner(tr("DEEP_FIRST_RECORD"), UITheme.ACCENT_TEXT, 4.0)
	changed.emit()
	game._autosave_active_slot()

func reset() -> void:
	observations = 0
	modules.load_save_data({})
	target.progress = 0.0
	target.cooldown = 0.0
	target.visible = available()
	target.queue_redraw()
	changed.emit()

func get_save_data() -> Dictionary:
	return {"version": 1, "observations": observations, "modules": modules.get_save_data(), "progress": target.progress, "cooldown": target.cooldown}

func load_save_data(data: Dictionary, legacy: Dictionary = {}) -> void:
	reset()
	if data.get("version", 1) != 1:
		return
	var owned = data.get("modules", legacy.get("modules", {}))
	modules.load_save_data(owned if owned is Dictionary else {})
	observations = int(_number(data.get("observations", 0), 1000000000.0))
	target.progress = _number(data.get("progress", 0), 0.999)
	target.cooldown = _number(data.get("cooldown", 0), 7.0)
	target.queue_redraw()
	changed.emit()

func _number(value, maximum: float) -> float:
	if not (value is float or value is int) or not is_finite(float(value)):
		return 0.0
	return clampf(float(value), 0.0, maximum)
