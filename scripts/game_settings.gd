extends Node

signal language_changed(locale: String)

const SETTINGS_PATH := "user://settings.cfg"
const SUPPORTED_LOCALES := ["en", "ko"]

var locale: String = "en"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	locale = _load_locale()
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


func _load_locale() -> String:
	var fallback := OS.get_locale_language().to_lower().left(2)
	if fallback not in SUPPORTED_LOCALES:
		fallback = "en"
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return fallback
	var saved := String(config.get_value("accessibility", "language", fallback)).to_lower().left(2)
	return saved if saved in SUPPORTED_LOCALES else fallback


func _save_locale() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("accessibility", "language", locale)
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("Could not save language setting: %s" % error_string(error))
