extends Control

# A presentation surface inside ModulePopup's existing pause/focus boundary.
# The transaction is saved BEFORE animation starts; closing/skipping never rolls.
const UITheme = preload("res://scripts/ui_theme.gd")
const Visual = preload("res://scripts/module_visual.gd")
const REVEAL_SECONDS := 1.8
const CENTER := Vector2(338, 326)
var host: CanvasLayer
var drawing := false
var elapsed := 0.0
var result_id := ""
var new_copy := false
var title: Label
var subtitle: Label
var balance: Label
var status: Label
var result_name: Label
var result_kind: Label
var result_effect: Label
var result_quantity: Label
var action: Button
var skip_button: Button
var loadout_button: Button
var close_button: Button
var result_panel: Control

func setup(owner_popup: CanvasLayer) -> void:
	host = owner_popup
	action = get_node("Action")
	balance = get_node("Balance")
	close_button = get_node("CloseButton")
	loadout_button = get_node("LoadoutButton")
	result_effect = get_node("ResultPanel/ResultEffect")
	result_kind = get_node("ResultPanel/ResultKind")
	result_name = get_node("ResultPanel/ResultName")
	result_panel = get_node("ResultPanel")
	result_quantity = get_node("ResultPanel/ResultQuantity")
	skip_button = get_node("SkipButton")
	status = get_node("Status")
	subtitle = get_node("Subtitle")
	title = get_node("Title")
	close_button.pressed.connect(host.close)
	action.pressed.connect(begin_draw)
	skip_button.pressed.connect(finish_reveal)
	loadout_button.pressed.connect(host.show_loadout)
	hide()
	set_process(false)


func enter() -> void:
	drawing = false
	elapsed = REVEAL_SECONDS
	result_id = host.game.deep_sky.state.last_draw
	new_copy = false
	show()
	set_process(true)
	refresh()
	action.grab_focus()

func leave() -> void:
	# Ownership and the last result already live in the saved model.
	drawing = false
	elapsed = REVEAL_SECONDS
	hide()
	set_process(false)

func begin_draw() -> void:
	if drawing or not visible:
		return
	drawing = true
	result_id = ""
	elapsed = 0.0
	refresh()
	var id: String = host.game.deep_sky.draw_module()
	if id.is_empty():
		drawing = false
		result_id = host.game.deep_sky.state.last_draw
		refresh()
		return
	result_id = id
	new_copy = host.model().owned_count(id) == 1
	if host.game.settings.motion_intensity <= 0.0:
		finish_reveal()
	else:
		refresh()
		skip_button.grab_focus()

func finish_reveal() -> void:
	if not drawing:
		return
	drawing = false
	elapsed = REVEAL_SECONDS
	refresh()
	action.grab_focus()

func refresh() -> void:
	if host == null or not visible:
		return
	var research: Node = host.game.deep_sky
	title.text = tr("DRAW_TITLE")
	subtitle.text = tr("DRAW_POOL") % [research.Data.SAMPLE_MODULES.size(), research.Data.SAMPLE_MODULES.size()]
	close_button.text = tr("DRAW_CLOSE")
	balance.text = tr("EXT_SAMPLES_COUNT") % research.samples
	action.text = tr("MODX_DRAW") % research.state.draw_cost()
	action.disabled = drawing or research.samples < research.state.draw_cost()
	loadout_button.text = tr("DRAW_LOADOUT")
	skip_button.text = tr("DRAW_SKIP")
	skip_button.visible = drawing
	result_panel.visible = not drawing
	if drawing:
		status.text = tr("DRAW_ALIGN" if elapsed >= REVEAL_SECONDS * 0.5 else "DRAW_SCAN")
	elif result_id.is_empty():
		status.text = tr("DRAW_READY")
		result_kind.text = tr("DRAW_SPECIMEN")
		result_name.text = tr("DRAW_WAITING")
		result_effect.text = tr("DRAW_EXPLAIN")
		result_quantity.text = tr("DRAW_NO_AUTO_EQUIP")
	else:
		status.text = "" # The result heading already identifies the acquisition.
		result_kind.text = tr("DRAW_NEW" if new_copy else "DRAW_SAVED")
		result_name.text = tr("MODULE_%s_NAME" % result_id.to_upper())
		result_effect.text = tr("MODULE_%s_DESC" % result_id.to_upper())
		result_quantity.text = tr("MODX_QUANTITY") % [host.model().owned_count(result_id), host.model().installed_count(result_id)]
		if not new_copy and host.model().owned_count(result_id) > 1:
			result_quantity.text += "  ·  " + tr("DRAW_DUPLICATE")
	if host.game.hud.autosave_failed:
		status.text = tr("AUTOSAVE_FAILURE") % host.game.active_save_slot
	status.visible = not status.text.is_empty()
	queue_redraw()

func _process(delta: float) -> void:
	if drawing:
		elapsed += delta / maxf(Engine.time_scale, 0.001)
		if elapsed >= REVEAL_SECONDS:
			finish_reveal()
		else:
			status.text = tr("DRAW_ALIGN" if elapsed >= REVEAL_SECONDS * 0.5 else "DRAW_SCAN")
		queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("100C09"))
	draw_line(Vector2(70, 134), Vector2(1080, 134), Color(UITheme.ACCENT_LINE, 0.25), 1.0)
	draw_line(Vector2(600, 178), Vector2(600, 594), Color(UITheme.ACCENT_LINE, 0.18), 1.0)
	var t := clampf(elapsed / REVEAL_SECONDS, 0.0, 1.0)
	var motion: float = host.game.settings.motion_intensity if host != null else 1.0
	var rotation := t * TAU * 1.5 * motion if drawing else 0.0
	for ring in range(3):
		var radius := 92.0 + ring * 38.0
		draw_arc(CENTER, radius, 0, TAU, 128, Color(UITheme.ACCENT_LINE, 0.12 + ring * 0.025), 1.0, true)
	for index in range(48):
		var angle := TAU * index / 48.0 - PI * 0.5
		var axis := Vector2.from_angle(angle)
		draw_line(CENTER + axis * 171, CENTER + axis * (181 if index % 4 == 0 else 176), Color(UITheme.INK_MID, 0.7), 1.0, true)
	for index in range(6):
		var angle := rotation + TAU * index / 6.0
		var radius := lerpf(142.0, 44.0, smoothstep(0.25, 1.0, t)) if drawing else 142.0
		var point := CENTER + Vector2.from_angle(angle) * radius
		draw_circle(point, 2.5, Color(UITheme.ACCENT_LINE, 0.9))
		if drawing:
			draw_arc(CENTER, radius, angle - 0.35, angle, 20, Color(UITheme.ACCENT_LINE, 0.45), 1.2, true)
	if drawing:
		draw_arc(CENTER, 190.0, -PI * 0.5, -PI * 0.5 + TAU * t, 128, UITheme.ACCENT_LINE, 2.0, true)
		var half := lerpf(18.0, 36.0, t)
		var diamond := PackedVector2Array([CENTER + Vector2(0, -half), CENTER + Vector2(half, 0), CENTER + Vector2(0, half), CENTER + Vector2(-half, 0), CENTER + Vector2(0, -half)])
		draw_polyline(diamond, UITheme.ACCENT_TEXT, 1.5, true)
	elif not result_id.is_empty():
		Visual.draw_module(self, Rect2(CENTER - Vector2(73, 73), Vector2(146, 146)), result_id, true, 1.0)
	else:
		for axis in [Vector2.RIGHT, Vector2.DOWN]:
			draw_line(CENTER - axis * 18, CENTER + axis * 18, UITheme.INK_MID, 1.5, true)
		draw_circle(CENTER, 40, Color(UITheme.ACCENT_LINE, 0.25), false, 1.0, true)
