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
	_test_authored_views()
	_test_initial_slot_locale()
	_test_renderer_alias()
	hud.free()
	chart.free()
	if failures.is_empty():
		print("UI_PRESENTATION_PASS: authored scenes and grouped integers preserve HUD/chart contracts; research marker aliases remain compatible")
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


func _test_authored_views() -> void:
	# Check the shipped scenes, rather than the removed code-building wrappers.
	_check(preload("res://resources/ui/native_dialog.tres").has_stylebox("panel", "AcceptDialog"), "native dialog keeps its authored panel instead of engine defaults")
	var hud_view = preload("res://scenes/ui/hud.tscn").instantiate()
	var chart_view = preload("res://scenes/ui/upgrade_tree.tscn").instantiate()
	var data: Label = hud_view.get_node("DataReadout/DataLabel")
	var chart_data: Label = chart_view.get_node("ChartHeader/DataReadout")
	for label in [data, chart_data]:
		_check(label.mouse_filter == Control.MOUSE_FILTER_IGNORE, "authored readout starts passive until data tooltip binding")
		_check(label.get_theme_color("font_color").is_equal_approx(UITheme.INK_HIGH), "authored readout retains shared ink")
		var font = label.get_theme_font("font")
		_check(font is FontVariation and font.base_font == UITheme.mono(), "authored readout retains the embedded mono font")
		_check(font.opentype_features.get(1953396077) == 1, "authored readout retains tabular digits")
	_check(data.get_theme_font_size("font_size") == 20, "HUD data type remains 20px")
	_check(chart_data.get_theme_font_size("font_size") == 31, "chart data type remains 31px")
	var summary = hud_view.get_node("PhaseSummary")
	_check(not summary.visible and not summary.get_node("SummaryColumn/Content/Details").visible, "summary is initially hidden with collapsed details")
	_check(summary.get_node("SummaryColumn/Content/DetailsButton").toggle_mode, "authored detail control retains toggle behavior")
	var other = preload("res://scenes/ui/hud.tscn").instantiate()
	data.text = "changed"
	_check(other.get_node("DataReadout/DataLabel").text != data.text, "scene instances keep independent live text")
	other.free()
	hud_view.free()
	chart_view.free()
	for item in [[13.0, 8], [52.0, 31], [12.0, 7], [0.0, 1], [20.0, 12]]:
		_check(UITheme.size_px(item[0]) == item[1], "procedural type retains design-to-viewport conversion")
	_check(UITheme.tracking(31, -0.03) == -1 and UITheme.tracking(7, 0.30) == 2, "procedural tracking conversion is unchanged")


func _test_initial_slot_locale() -> void:
	var original_locale := TranslationServer.get_locale()
	for locale in ["ko", "en"]:
		TranslationServer.set_locale(locale)
		var hud := HUD.new()
		root.add_child(hud)
		for index in 3:
			_check(hud.startup_slot_titles[index].text == tr("SAVE_SLOT_TITLE") % (index + 1), "initial authored slot title uses active locale")
			_check(hud.startup_slot_buttons[index].text == tr("STARTUP_NEW_GAME"), "initial authored slot action uses active locale")
		hud.free()
	TranslationServer.set_locale(original_locale)


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
