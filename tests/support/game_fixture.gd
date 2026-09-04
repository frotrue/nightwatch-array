extends RefCounted

# Shared services for diagnostic games. Install before adding the main scene
# to the tree: suppressing the slot prompt alone does not isolate settings I/O.
# These fixtures deliberately cannot persist, load, or reset a player slot.

class NoSaveSlots:

	extends "res://scripts/save_game_controller.gd"

	func _ready() -> void:
		_reload_slot_summaries()

	func save_slot(_slot: int, _run_data: Dictionary) -> Error:
		return ERR_UNAVAILABLE

	func load_slot(_slot: int) -> Dictionary:
		return {}

	func reset_slot(_slot: int) -> Error:
		return ERR_UNAVAILABLE

	func set_save_directory(_path: String) -> void:
		pass

	func _ensure_save_directory() -> void:
		pass

	func _read_slot_summary(_slot: int) -> Dictionary:
		return {"exists": false, "valid": true}

class NoSettings:

	extends "res://scripts/game_settings.gd"

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		locale = "en"
		tutorial_completed = true
		research_chart_rotation = 0.0
		master_linear = DEFAULT_MASTER_LINEAR
		muted = DEFAULT_MUTED
		fullscreen = DEFAULT_FULLSCREEN
		_editable_bindings.clear()
		InputBindings.apply_editable_overrides(_editable_bindings)
		TranslationServer.set_locale(locale)

	func save_settings() -> Error:
		return ERR_UNAVAILABLE

	func set_research_chart_rotation(value: float, _persist: bool = true) -> void:
		research_chart_rotation = wrapf(value, -PI, PI)

	func set_tutorial_completed(completed: bool, _persist: bool = true) -> void:
		tutorial_completed = completed

	func _save_locale() -> void:
		pass

class SilentSound:

	extends "res://scripts/sound_synth.gd"

	func _play_stream(_stream: AudioStreamWAV, _pitch: float = 1.0, _delay: float = 0.0, _volume: float = 0.0) -> void:
		pass


static func configure_before_ready(game: Node) -> void:
	assert(not game.is_inside_tree(), "Diagnostic services must be replaced before _ready")
	game.startup_slot_prompt_enabled = false
	game.get_node("Tutorial").auto_start_enabled = false
	replace_child(game, "SaveGameController", NoSaveSlots.new())
	replace_child(game, "GameSettings", NoSettings.new())


static func replace_child(parent: Node, child_name: String, replacement: Node) -> void:
	var original := parent.get_node(child_name)
	parent.remove_child(original)
	original.free()
	replacement.name = child_name
	parent.add_child(replacement)
