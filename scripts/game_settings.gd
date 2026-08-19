extends Node

signal language_changed(locale: String)

const SETTINGS_PATH := "user://settings.cfg"
const SUPPORTED_LOCALES := ["en", "ko"]

var locale: String = "en"
var tutorial_completed: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	locale = _load_locale()
	tutorial_completed = _load_tutorial_completed()
	TranslationServer.set_locale(locale)


func set_language(requested_locale: String, persist: bool = true) -> void:
	var normalized := requested_locale.to_lower().left(2)
	if normalized not in SUPPORTED_LOCALES:
		normalized = "en"
	if locale == normalized and TranslationServer.get_locale().left(2) == normalized:
		return
	locale = normalized
	TranslationServer.set_locale(locale)
	if persist:
		_save_locale()
	language_changed.emit(locale)


func get_language_index() -> int:
	return SUPPORTED_LOCALES.find(locale)


func is_tutorial_completed() -> bool:
	return tutorial_completed


func set_tutorial_completed(completed: bool) -> void:
	if tutorial_completed == completed:
		return
	tutorial_completed = completed
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("accessibility", "language", locale)
	config.set_value("onboarding", "tutorial_completed", tutorial_completed)
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("Could not save tutorial setting: %s" % error_string(error))


func _load_locale() -> String:
	var fallback := OS.get_locale_language().to_lower().left(2)
	if fallback not in SUPPORTED_LOCALES:
		fallback = "en"
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return fallback
	var saved := String(config.get_value("accessibility", "language", fallback)).to_lower().left(2)
	return saved if saved in SUPPORTED_LOCALES else fallback


func _load_tutorial_completed() -> bool:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return false
	return bool(config.get_value("onboarding", "tutorial_completed", false))


func _save_locale() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("accessibility", "language", locale)
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("Could not save language setting: %s" % error_string(error))
