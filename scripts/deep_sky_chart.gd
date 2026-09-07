extends Control

signal observatory_requested
signal constellations_requested

const UITheme = preload("res://scripts/ui_theme.gd")
const Modules = preload("res://scripts/observation_modules.gd")
const Data = preload("res://scripts/expansion_data.gd")

enum View {
	RESEARCH,
	PLANS,
	ANALYSIS,
}

const CATEGORY_COLORS := {
	"trace": Color("8BB8D5"),
	"sweep": Color("C7A6C5"),
	"link": Color("D9C78E"),
	"root": Color("D4DAE5"),
}

var chart: Node
var research: Node
var selected_id := "m31"
var active_view: View = View.RESEARCH
var title: Label
var balance: Label
var back_button: Button
var chart_button: Button
var tab_buttons: Dictionary = {}
var plans_panel: Control
var analysis_panel: Control
var plan_scroll: ScrollContainer
var plan_list: VBoxContainer
var plan_buttons: Dictionary = {}
var plan_title: Label
var plan_body: Label
var plan_status: Label
var analysis_title: Label
var analysis_body: Label
var analysis_status: Label
var analysis_button: Button
var candidate_buttons: Array[Button] = []
var direct_selector: OptionButton
var direct_button: Button
var catalogue_button: Button
var _last_acquired := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	title = label_at(Vector2(38, 22), 640, 24)
	balance = label_at(Vector2(690, 30), 420, 15)
	balance.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for descriptor in [[View.RESEARCH, "CHX_TAB_RESEARCH"], [View.PLANS, "CHX_TAB_PLANS"], [View.ANALYSIS, "CHX_TAB_ANALYSIS"]]:
		var view: View = descriptor[0]
		var tab := button_at(Vector2(328 + int(view) * 115, 65), Vector2(106, 27), _set_view.bind(view))
		tab_buttons[view] = tab

	plans_panel = Control.new()
	plans_panel.name = "PlansPanel"
	plans_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(plans_panel)
	plan_scroll = ScrollContainer.new()
	plan_scroll.position = Vector2(38, 128)
	plan_scroll.size = Vector2(340, 434)
	plan_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	plan_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	plan_scroll.focus_mode = Control.FOCUS_NONE
	plans_panel.add_child(plan_scroll)
	plan_list = VBoxContainer.new()
	plan_list.custom_minimum_size = Vector2(314, 0)
	plan_list.add_theme_constant_override("separation", 8)
	plan_scroll.add_child(plan_list)
	for id in Data.PLAN_ORDER:
		var button := Button.new()
		button.custom_minimum_size = Vector2(310, 52)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_configure_button(button)
		button.pressed.connect(_select_plan.bind(id))
		plan_list.add_child(button)
		plan_buttons[id] = button
	plan_title = panel_label(plans_panel, Vector2(414, 138), 380, 20)
	plan_body = panel_label(plans_panel, Vector2(414, 184), 380, 13)
	plan_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	plan_body.size.y = 174
	plan_status = panel_label(plans_panel, Vector2(414, 374), 380, 13)
	plan_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	plan_status.size.y = 120

	analysis_panel = Control.new()
	analysis_panel.name = "AnalysisPanel"
	analysis_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(analysis_panel)
	analysis_title = panel_label(analysis_panel, Vector2(54, 136), 640, 21)
	analysis_body = panel_label(analysis_panel, Vector2(54, 180), 640, 14)
	analysis_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	analysis_body.size.y = 76
	analysis_status = panel_label(analysis_panel, Vector2(54, 270), 640, 13)
	analysis_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	analysis_status.size.y = 52
	analysis_button = panel_button(analysis_panel, Vector2(54, 336), Vector2(258, 36), begin_analysis)
	for index in range(3):
		var candidate := panel_button(analysis_panel, Vector2(54 + index * 205, 392), Vector2(192, 54), _choose_pending.bind(index))
		candidate.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		candidate_buttons.append(candidate)
	direct_selector = OptionButton.new()
	direct_selector.position = Vector2(54, 492)
	direct_selector.size = Vector2(400, 34)
	direct_selector.add_theme_font_override("font", UITheme.sans())
	direct_selector.add_theme_font_size_override("font_size", 13)
	analysis_panel.add_child(direct_selector)
	direct_button = panel_button(analysis_panel, Vector2(468, 492), Vector2(246, 34), direct_analysis)
	catalogue_button = panel_button(analysis_panel, Vector2(54, 548), Vector2(258, 32), _open_catalogue)

	chart_button = button_at(Vector2(328, 590), Vector2(260, 34), func(): constellations_requested.emit())
	back_button = button_at(Vector2(902, 590), Vector2(203, 34), func(): observatory_requested.emit())
	visibility_changed.connect(refresh_text)
	refresh_text()


func bind(controller: Node, tree: Node) -> void:
	research = controller
	chart = tree
	chart.bind_extension(research)
	if not research.changed.is_connected(refresh_text):
		research.changed.connect(refresh_text)
	refresh_text()


func select(id: String) -> void:
	selected_id = id
	if id in Data.PLAN_ORDER:
		_set_view(View.PLANS)
	elif id == "analysis":
		_set_view(View.ANALYSIS)
	else:
		_set_view(View.RESEARCH)
		if chart != null: chart.select_extension(id)


func refresh_text(_binding: String = "U") -> void:
	if title == null:
		return
	title.text = tr("CHX_TITLE")
	back_button.text = tr("MODULE_RETURN_TO_SKY")
	chart_button.text = tr("ATLAS_RETURN")
	for view in tab_buttons:
		var tab: Button = tab_buttons[view]
		tab.text = tr(["ATLAS_RETURN", "CHX_TAB_PLANS", "CHX_TAB_ANALYSIS"][int(view)])
		tab.add_theme_font_size_override("font_size", 11)
		tab.add_theme_color_override("font_color", UITheme.ACCENT_TEXT if view == active_view else UITheme.INK_MID)
	if research == null:
		queue_redraw()
		return
	var data_value := int(research.game.progression.observation_data)
	balance.text = UITheme.grouped_integer(data_value) + " " + tr("MODULE_DATA")
	var base_owned := _visible_base_owned_count()
	var paid: int = research.paid_research_count()
	balance.tooltip_text = tr("CHX_PROGRESS") % [base_owned, 95, paid, 16, research.modules.purchased.size(), Modules.DEFINITIONS.size()]
	plans_panel.visible = active_view == View.PLANS
	analysis_panel.visible = active_view == View.ANALYSIS
	chart_button.visible = active_view != View.RESEARCH
	if active_view == View.PLANS:
		_refresh_plans_view()
	elif active_view == View.ANALYSIS:
		_refresh_analysis_view()
	queue_redraw()


func _set_view(view: View) -> void:
	active_view = view
	if chart != null:
		chart._cancel_node_hold()
		chart._refresh_galactic_overlays()
	refresh_text()


func _refresh_plans_view() -> void:
	var selected_plan: String = selected_id if selected_id in Data.PLAN_ORDER else research.active_plan()
	if selected_plan.is_empty() and not Data.PLAN_ORDER.is_empty():
		selected_plan = Data.PLAN_ORDER[0]
	for id in Data.PLAN_ORDER:
		var button: Button = plan_buttons[id]
		var progress: Vector2i = research.plan_progress(id)
		var available: bool = research.plan_available(id)
		button.text = research.plan_name(id) + "\n" + (tr("CHX_PLAN_PROGRESS") % [progress.x, progress.y])
		button.disabled = not available
		button.add_theme_color_override("font_color", _category_color(String(Data.PLANS[id].category)) if available else UITheme.INK_LOW)
	if not Data.PLANS.has(selected_plan):
		plan_title.text = tr("CHX_PLAN_SELECT")
		plan_body.text = tr("CHX_PLAN_UNAVAILABLE")
		plan_status.text = research.current_objective()
		return
	var progress: Vector2i = research.plan_progress(selected_plan)
	plan_title.text = research.plan_name(selected_plan)
	plan_body.text = research.plan_detail(selected_plan)
	var active_label := tr("CHX_ACTIVE_PLAN") % research.plan_name(research.active_plan()) if not research.active_plan().is_empty() else tr("CHX_PLAN_NONE")
	plan_status.text = active_label + "\n" + tr("CHX_CURRENT_OBJECTIVE") + "\n" + research.current_objective() + "\n" + (tr("CHX_PLAN_PROGRESS") % [progress.x, progress.y])


func _refresh_analysis_view() -> void:
	var pool: Array[String] = research.sample_pool()
	var sample_summary := tr("CHX_SAMPLES") % [research.samples]
	var pool_summary := tr("CHX_COLLECTION_DONE") if research.collection_complete() else tr("CHX_POOL_REMAINING") % [pool.size()]
	analysis_title.text = tr("CHX_ANALYSIS_TITLE")
	analysis_body.text = sample_summary + "\n" + pool_summary
	if not research.pending_offer.is_empty():
		analysis_status.text = tr("CHX_PENDING")
	elif not _last_acquired.is_empty():
		analysis_status.text = tr("CHX_ACQUIRED") % _module_name(_last_acquired)
	elif research.collection_complete():
		analysis_status.text = tr("CHX_COLLECTION_DONE")
	else:
		analysis_status.text = tr("CHX_ANALYSIS_IDLE")
	analysis_button.text = tr("CHX_DRAW_ANALYSIS")
	analysis_button.visible = research.pending_offer.is_empty()
	analysis_button.disabled = research.pending_offer.size() > 0 or research.samples < 8 or pool.is_empty()
	for index in range(candidate_buttons.size()):
		var candidate: Button = candidate_buttons[index]
		candidate.visible = index < research.pending_offer.size()
		candidate.disabled = not candidate.visible
		if candidate.visible:
			candidate.text = tr("CHX_CHOOSE") % _module_name(research.pending_offer[index])
	direct_selector.clear()
	for id in pool:
		direct_selector.add_item(_module_name(id))
		direct_selector.set_item_metadata(direct_selector.item_count - 1, id)
	var direct_available: bool = research.pending_offer.is_empty() and research.samples >= 12 and not pool.is_empty()
	direct_selector.disabled = not direct_available
	direct_button.text = tr("CHX_DIRECT_ANALYSIS")
	direct_button.disabled = not direct_available
	catalogue_button.text = tr("CHX_OPEN_CATALOGUE")
	catalogue_button.disabled = research.modules.purchased.is_empty()


func _select_plan(id: String) -> void:
	if research != null and research.select_plan(id):
		selected_id = id
	refresh_text()


func begin_analysis() -> void:
	if research != null and research.begin_analysis():
		_last_acquired = ""
	refresh_text()


func _choose_pending(index: int) -> void:
	if research == null or index < 0 or index >= research.pending_offer.size():
		return
	var id: String = research.pending_offer[index]
	if research.choose_analysis(id):
		_last_acquired = id
	refresh_text()


func direct_analysis() -> void:
	if research == null or direct_selector.item_count <= 0:
		return
	var id: String = str(direct_selector.get_item_metadata(direct_selector.selected))
	if research.direct_analysis(id):
		_last_acquired = id
	refresh_text()


func _open_catalogue() -> void:
	if research != null and research.game != null and research.game.module_popup != null:
		research.game.module_popup.open()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UITheme.TOOLTIP_BACKGROUND)
	for index in range(96):
		draw_circle(Vector2(fmod(index * 123.7 + 49, 1152), fmod(index * 89.3 + 103, 648)), 0.55, Color(UITheme.STAR_BACKGROUND, 0.20))
	draw_line(Vector2(38, 102), Vector2(1110, 102), Color(UITheme.INK_MID, 0.35), 1)
	match active_view:
		View.PLANS: _draw_plan_surface()
		View.ANALYSIS: _draw_analysis_surface()


func _draw_plan_surface() -> void:
	draw_rect(Rect2(38, 128, 340, 434), Color(UITheme.GROUND, 0.25), false, 1)
	draw_line(Vector2(392, 128), Vector2(392, 562), Color(UITheme.INK_MID, 0.35), 1)
	draw_line(Vector2(814, 128), Vector2(814, 562), Color(UITheme.INK_MID, 0.35), 1)
	_draw_m31_layers(Vector2(962, 270), 70)
	_draw_m31_legend(962, 390, true)


func _draw_analysis_surface() -> void:
	draw_rect(Rect2(38, 124, 708, 462), Color(UITheme.GROUND, 0.24), false, 1)
	draw_line(Vector2(38, 320), Vector2(746, 320), Color(UITheme.INK_MID, 0.32), 1)
	draw_line(Vector2(38, 468), Vector2(746, 468), Color(UITheme.INK_MID, 0.32), 1)
	_draw_m31_layers(Vector2(926, 285), 78)
	_draw_m31_legend(926, 390, false)


func _draw_m31_layers(center: Vector2, radius: float) -> void:
	draw_circle(center, radius, Color("D4DAE5", 0.035))
	draw_arc(center, radius, 0, TAU, 56, Color("D4DAE5", 0.46), 1, true)
	if research == null:
		return
	var categories := ["trace", "sweep", "link"]
	for index in range(categories.size()):
		var category: String = categories[index]
		var completed := 0
		var total := 0
		for id in Data.PLAN_ORDER:
			if String(Data.PLANS[id].category) != category:
				continue
			var progress: Vector2i = research.plan_progress(id)
			completed += progress.x
			total += progress.y
		var fraction := float(completed) / maxf(1.0, float(total))
		var start := -PI * 0.5 + float(index) * TAU / 3.0 + 0.08
		var sweep := (TAU / 3.0 - 0.16) * fraction
		var ring := radius - 14.0 - index * 14.0
		draw_arc(center, ring, start, start + TAU / 3.0 - 0.16, 24, Color(_category_color(category), 0.18), 3.0, true)
		if sweep > 0.0:
			draw_arc(center, ring, start, start + sweep, 24, _category_color(category), 3.0, true)


func _draw_m31_legend(center_x: float, title_y: float, include_progress: bool) -> void:
	_draw_caption(Vector2(center_x, title_y), tr("CHX_RECORD_LAYERS"), UITheme.INK_HIGH, 13)
	if research == null:
		return
	var categories := ["trace", "sweep", "link"]
	for index in range(categories.size()):
		var category: String = categories[index]
		var completed := 0
		var total := 0
		for id in Data.PLAN_ORDER:
			if String(Data.PLANS[id].category) != category:
				continue
			var progress: Vector2i = research.plan_progress(id)
			completed += progress.x
			total += progress.y
		_draw_caption(Vector2(center_x, 420 + index * 20), "%s  %d/%d" % [tr("CHX_CATEGORY_%s" % category.to_upper()), completed, total], _category_color(category), 11)
	if include_progress:
		_draw_caption(Vector2(center_x, 500), tr("CHX_BASE_PROGRESS") % [_visible_base_owned_count(), 95], UITheme.INK_MID, 10)
		_draw_caption(Vector2(center_x, 520), tr("CHX_CONTINUATION_PROGRESS") % [research.paid_research_count(), 16], UITheme.INK_MID, 10)
		_draw_caption(Vector2(center_x, 540), tr("CHX_MODULE_PROGRESS") % [research.modules.purchased.size(), Modules.DEFINITIONS.size()], UITheme.INK_MID, 10)


func _module_name(id: String) -> String:
	return tr("MODULE_%s_NAME" % id.to_upper())


func _category_color(category: String) -> Color:
	return CATEGORY_COLORS.get(category, UITheme.INK_MID)


func _visible_base_owned_count() -> int:
	if chart == null or chart.progression == null:
		return 0
	var count := 0
	for definition in chart.Balance.UPGRADE_NODES:
		if not chart._is_local_group_node(String(definition.id)) and chart.progression.has_upgrade(String(definition.id)):
			count += 1
	return count


func _draw_caption(p: Vector2, caption: String, ink: Color, font_size: int) -> void:
	var font: Font = UITheme.sans()
	var width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, p - Vector2(width * 0.5, 0), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)


func label_at(p: Vector2, width: float, font_size: int) -> Label:
	var label := Label.new()
	label.position = p
	label.size.x = width
	label.add_theme_font_override("font", UITheme.sans())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", UITheme.INK_HIGH)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


func panel_label(parent: Control, p: Vector2, width: float, font_size: int) -> Label:
	var label := Label.new()
	label.position = p
	label.size.x = width
	label.add_theme_font_override("font", UITheme.sans())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", UITheme.INK_HIGH)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func button_at(p: Vector2, dimensions: Vector2, callback: Callable, underline: bool = true) -> Button:
	var button := Button.new()
	button.position = p
	button.size = dimensions
	_configure_button(button)
	if underline:
		button.draw.connect(func(): button.draw_line(Vector2(0, button.size.y - 1), button.size - Vector2(0, 1), UITheme.INK_MID, UITheme.px(1), true))
	button.pressed.connect(callback)
	add_child(button)
	return button


func panel_button(parent: Control, p: Vector2, dimensions: Vector2, callback: Callable) -> Button:
	var button := Button.new()
	button.position = p
	button.size = dimensions
	_configure_button(button)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _configure_button(button: Button) -> void:
	button.flat = true
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_override("font", UITheme.sans())
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", UITheme.ACCENT_TEXT)
	button.add_theme_color_override("font_hover_color", UITheme.ACCENT_TEXT)
	button.add_theme_color_override("font_focus_color", UITheme.ACCENT_TEXT)
	button.add_theme_color_override("font_disabled_color", UITheme.INK_LOW)
	for state in ["normal", "hover", "focus", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
