extends SceneTree

# Shared presentation primitives only. No main scene or services are started,
# so this gate cannot read or write player saves or settings.
const HUD = preload("res://scripts/hud.gd")
const Chart = preload("res://scripts/upgrade_tree.gd")
const StarVisual = preload("res://scripts/research_star_visual.gd")
const UITheme = preload("res://scripts/ui_theme.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var hud := HUD.new()
	var chart := Chart.new()
	_test_grouped_integers(hud, chart)
	_test_data_notation(hud, chart)
	_test_spec_labels(hud, chart)
	_test_renderer_alias()
	hud.free()
	chart.free()
	if failures.is_empty():
		print("UI_PRESENTATION_PASS: shared labels and grouped integers preserve HUD/chart contracts; research marker aliases remain compatible")
		quit(0)
	else:
		print("UI_PRESENTATION_FAIL: %d failure(s)" % failures.size())
		quit(1)


func _test_grouped_integers(hud, chart) -> void:
	var cases := [
		[0, "0"], [1, "1"], [-1, "-1"],
		[999, "999"], [-999, "-999"],
		[1000, "1,000"], [-1000, "-1,000"],
		[999999, "999,999"], [-999999, "-999,999"],
		[1000000, "1,000,000"], [-1000000, "-1,000,000"],
		[41332301070, "41,332,301,070"],
		[1000000000000, "1,000,000,000,000"],
		[9223372036854775807, "9,223,372,036,854,775,807"],
		[-9223372036854775807, "-9,223,372,036,854,775,807"],
	]
	var original_locale := TranslationServer.get_locale()
	for locale in ["en", "ko"]:
		TranslationServer.set_locale(locale)
		for item in cases:
			var value: int = item[0]
			var expected: String = item[1]
			_check(UITheme.grouped_integer(value) == expected, "shared grouping: %s/%d" % [locale, value])
			_check(hud._grouped(value) == expected, "HUD grouping wrapper: %s/%d" % [locale, value])
			_check(chart._grouped(value) == expected, "chart grouping wrapper: %s/%d" % [locale, value])
	TranslationServer.set_locale(original_locale)


func _test_spec_labels(hud, chart) -> void:
	# Expected pixels are literal contract values, not calculated with the helper.
	var cases := [
		{"spec": 13.0, "em": 0.0, "size": 8, "spacing": 0, "override": false},
		{"spec": 52.0, "em": -0.03, "size": 31, "spacing": -1, "override": true},
		{"spec": 12.0, "em": 0.30, "size": 7, "spacing": 2, "override": true},
		{"spec": 0.0, "em": 0.16, "size": 1, "spacing": 0, "override": true},
		{"spec": 20.0, "em": 0.0000001, "size": 12, "spacing": 0, "override": false},
	]
	var font: Font = UITheme.sans("light")
	var ink := Color(0.63, 0.42, 0.21, 0.37)
	var text := "OBSERVATION / 관측"
	for item in cases:
		var labels: Array[Label] = [
			UITheme.spec_label(text, font, item.spec, ink, item.em),
			hud._spec_label(text, font, item.spec, ink, item.em),
			chart._spec_label(text, font, item.spec, ink, item.em),
		]
		_check(labels[0] != labels[1] and labels[1] != labels[2], "label factories return independent controls")
		for label in labels:
			_check(label.text == text, "label text is unchanged")
			_check(label.has_theme_font_override("font") and label.get_theme_font("font") == font, "font identity is unchanged")
			_check(label.get_theme_font_size("font_size") == int(item.size), "spec size conversion is unchanged")
			_check(label.get_theme_color("font_color") == ink, "ink including alpha is unchanged")
			_check(label.has_theme_constant_override("spacing_glyph") == bool(item.override), "near-zero em preserves absence of an override")
			if bool(item.override):
				_check(label.get_theme_constant("spacing_glyph") == int(item.spacing), "glyph tracking is unchanged")
			_check(label.mouse_filter == Control.MOUSE_FILTER_IGNORE, "labels do not intercept input")
			_check(label.get_parent() == null, "factory leaves layout and ownership to the caller")
			label.free()
	var default_label := UITheme.spec_label("default", UITheme.mono_tabular(), 54.0, UITheme.INK_HIGH)
	_check(not default_label.has_theme_constant_override("spacing_glyph"), "omitted em retains the original default")
	_check(default_label.get_theme_font("font") == UITheme.mono_tabular(), "tabular font identity is preserved")
	default_label.free()


func _test_data_notation(hud, chart) -> void:
	var cases := [
		[0.0, "0", "0"], [999999.0, "999,999", "999,999"],
		[1000000.0, "1.00M", "1.00e6"], [60000000.0, "60.0M", "6.00e7"],
		[1200000000.0, "1.20B", "1.20e9"], [90940000000.0, "90.9B", "9.09e10"],
		[1000000000000.0, "1.00T", "1.00e12"], [1000000000000000.0, "1.00e15", "1.00e15"],
		[999499999.0, "999M", "9.99e8"], [999999999.0, "1.00B", "1.00e9"],
		[-1200000000.0, "-1.20B", "-1.20e9"],
	]
	for item in cases:
		_check(UITheme.data_number(item[0]) == item[1], "compact threshold/carry/sign: " + str(item[0]))
		_check(UITheme.data_number(item[0], "scientific") == item[2], "scientific exponent/carry/sign: " + str(item[0]))
		_check(hud._data_number(item[0]) == item[1] and chart._data_number(item[0]) == item[1], "HUD and chart default to the shared compact format")
	_check(UITheme.data_number(1234.5, "scientific", 1) == "1,234.5", "small rates keep one decimal in either mode")
	_check(UITheme.full_data(1234567890.0) == "1,234,567,890", "exact tooltip never abbreviates")
	_check(UITheme.full_data(-1234567.8, 1) == "-1,234,567.8", "rate tooltip retains sign and decimal")


func _test_renderer_alias() -> void:
	_check(Chart.StarNodeVisual == StarVisual, "existing marker script name aliases the extracted renderer")
	_check(is_equal_approx(Chart.GALACTIC_NODE_SCREEN_SCALE, 0.72), "chart scale alias retains the established value")
	_check(Chart.GALACTIC_NODE_SCREEN_SCALE == StarVisual.GALACTIC_NODE_SCREEN_SCALE, "chart and marker share one scale constant")
	_check(Chart.CLUSTER_MARKER_OFFSETS == StarVisual.CLUSTER_MARKER_OFFSETS, "chart and marker share one cluster silhouette")
	var visual := Chart.StarNodeVisual.new()
	_check(visual is StarVisual and visual is Chart.StarNodeVisual, "legacy and extracted marker type checks both work")
	visual.set_fill_progress(0.5, 0.25)
	_check(is_equal_approx(visual.hold_ratio, 0.5) and is_equal_approx(visual.pulse_phase, 2.0), "legacy marker methods remain callable")
	visual.clear_fill()
	_check(is_zero_approx(visual.hold_ratio), "legacy clear-fill contract remains callable")
	visual.free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("UI_PRESENTATION: " + message)
