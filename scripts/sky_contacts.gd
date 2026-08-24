extends Node2D

const Balance = preload("res://scripts/game_balance.gd")

# Forecast information can arrive before the player owns hardware to act on it.
# Secondary Camera adds the player-aimed dish and extends the warning to fund
# its slew time; Wide Field Sensor alone still supports cursor pre-positioning.

const SLEW_SPEED := 420.0
# Forecast pre-positioning lets the dish take routine high-motion work. Entry
# planning can raise a fast meteor from 390 to 436.8, so the servo clears the
# real ceiling rather than only the nominal speed.
const TRACK_SPEED := 460.0
const COVERAGE_RADIUS := 105.0
# Track time is shared analysis complexity. Cursor ergonomics belong in the
# manual quality curve and tracking radius, not in hardware scan duration.
const DISH_TIME_MULTIPLIER := 2.3
const CONTACT_HIT_RADIUS := 30.0
const DISH_TRACKABLE_TYPES := ["common", "fast", "fragment", "fragment_piece"]

var progression: Node
var meteor_layer: Node2D
var contacts: Array[Dictionary] = []
var dishes: Array[Dictionary] = []
var cursor_position := Vector2.ZERO
var hovered_contact_id: int = -1
var dish_movement_learned: bool = false
var dish_commitment_learned: bool = false
var abandoned_target_id: int = 0
var abandoned_target_position := Vector2.ZERO
var abandoned_target_flash: float = 0.0


func setup(target_layer: Node2D, progression_controller: Node) -> void:
	meteor_layer = target_layer
	progression = progression_controller
	refresh_dishes()


func forecast_visible() -> bool:
	return progression != null and progression.forecast_visible()


func dish_active() -> bool:
	return not dishes.is_empty()


# Dishes arrive with the research that grants them and park mid-sky, where they
# are equidistant from most entry points.
func refresh_dishes() -> void:
	# Refreshing can also remove every dish (reset/debug/load paths), so release
	# this source before resizing instead of relying on another process tick.
	_clear_dish_assists()
	var wanted: int = progression.get_dish_count() if progression != null else 0
	while dishes.size() > wanted:
		dishes.pop_back()
	if dishes.size() == wanted:
		return
	var size := get_viewport_rect().size
	while dishes.size() < wanted:
		var home := Vector2(size.x * (0.42 + 0.2 * float(dishes.size())), size.y * 0.55)
		dishes.append({
			"position": home,
			"target": home,
			"assigned_id": -1,
			"locked_id": 0,
			"arrived": true,
		})
	queue_redraw()


func reset(clear_interaction_learning: bool = false) -> void:
	_clear_dish_assists()
	contacts.clear()
	hovered_contact_id = -1
	abandoned_target_id = 0
	abandoned_target_flash = 0.0
	if clear_interaction_learning:
		dish_movement_learned = false
		dish_commitment_learned = false
	for index in range(dishes.size()):
		var dish: Dictionary = dishes[index]
		dish.assigned_id = -1
		dish.locked_id = 0
		dish.target = dish.position
		dish.arrived = true
		dishes[index] = dish
	queue_redraw()


func on_contact_announced(contact: Dictionary) -> void:
	if not forecast_visible():
		return
	contacts.append(contact)
	queue_redraw()


func on_contact_resolved(contact: Dictionary, meteor) -> void:
	contacts.erase(contact)
	if meteor == null:
		_release_dish_for_contact(int(contact.id))
		return
	# The dish was committed to a prediction; now it has an object to hold.
	for index in range(dishes.size()):
		var dish: Dictionary = dishes[index]
		if int(dish.assigned_id) == int(contact.id):
			dish.locked_id = meteor.get_instance_id() if _dish_can_track(meteor) else 0
			dish.assigned_id = -1
			dishes[index] = dish


func _contact_at(point: Vector2) -> int:
	for contact in contacts:
		if point.distance_to(_estimate_of(contact)) <= CONTACT_HIT_RADIUS:
			return int(contact.id)
	return -1


# What the player sees, not the truth: the predicted intercept carries an error
# that only shrinks as the object closes.
func _estimate_of(contact: Dictionary) -> Vector2:
	var lead: float = maxf(float(contact.lead_time), 0.001)
	var certainty: float = clampf(1.0 - float(contact.countdown) / lead, 0.0, 1.0)
	return Vector2(contact.intercept) + Vector2(contact.error_offset) * (1.0 - certainty)


func _process(delta: float) -> void:
	abandoned_target_flash = maxf(0.0, abandoned_target_flash - delta)
	if not forecast_visible():
		return
	if dish_active():
		cursor_position = get_viewport().get_mouse_position()
		hovered_contact_id = _contact_at(cursor_position)
		_update_dishes(delta)
	else:
		hovered_contact_id = -1
	queue_redraw()


func _update_dishes(delta: float) -> void:
	# Dish ownership is renewed every frame. Clearing here prevents a retasked or
	# broken lock from leaving its abandoned meteor under stale assistance.
	_clear_dish_assists()
	for index in range(dishes.size()):
		var dish: Dictionary = dishes[index]
		var locked = _locked_target(dish)

		if locked != null:
			var offset: Vector2 = locked.global_position - Vector2(dish.position)
			var track_step := TRACK_SPEED * delta
			dish.position = Vector2(dish.position) + (
				offset if offset.length() <= track_step else offset.normalized() * track_step
			)
			dish.arrived = true
			if Vector2(dish.position).distance_to(locked.global_position) > COVERAGE_RADIUS:
				dish.locked_id = 0
			else:
				locked.set_dish_assist_rate(locked.get_assist_rate(DISH_TIME_MULTIPLIER))
			dishes[index] = dish
			continue

		dish.locked_id = 0
		var position: Vector2 = dish.position
		var target: Vector2 = dish.target
		if not position.is_equal_approx(target):
			var step := SLEW_SPEED * delta
			var slew := target - position
			if slew.length() <= step:
				dish.position = target
				dish.arrived = true
			else:
				dish.position = position + slew.normalized() * step
				dish.arrived = false
		else:
			dish.arrived = true

		# A slewing dish records nothing. Manual placement must arrive before it
		# can acquire; researched commitment instead buys a direct handoff.
		if bool(dish.arrived):
			var acquired = _acquire_target(dish, index)
			if acquired != null:
				dish.locked_id = acquired.get_instance_id()
				acquired.set_dish_assist_rate(acquired.get_assist_rate(DISH_TIME_MULTIPLIER))
		dishes[index] = dish


func _clear_dish_assists() -> void:
	if meteor_layer == null:
		return
	for child in meteor_layer.get_children():
		if child.has_method("set_dish_assist_rate"):
			child.set_dish_assist_rate(0.0)


func _locked_target(dish: Dictionary):
	var locked_id := int(dish.get("locked_id", 0))
	if locked_id == 0:
		return null
	var locked = instance_from_id(locked_id)
	if locked == null or not is_instance_valid(locked):
		return null
	if not locked.has_method("can_be_tracked") or not locked.can_be_tracked():
		return null
	if not _dish_can_track(locked):
		return null
	return locked


func _dish_can_track(target) -> bool:
	return is_instance_valid(target) and _dish_can_track_type(String(target.type_id))


func _dish_can_track_type(type_id: String) -> bool:
	return type_id in DISH_TRACKABLE_TYPES


func _acquire_target(dish: Dictionary, own_index: int):
	var closest = null
	var closest_distance := INF
	for child_index in range(meteor_layer.get_child_count()):
		var meteor = meteor_layer.get_child(child_index)
		if not meteor.has_method("can_be_tracked") or not meteor.can_be_tracked():
			continue
		if not _dish_can_track(meteor):
			continue
		var taken := false
		for other_index in range(dishes.size()):
			if other_index != own_index and int(dishes[other_index].get("locked_id", 0)) == meteor.get_instance_id():
				taken = true
				break
		if taken:
			continue
		var distance: float = Vector2(dish.position).distance_to(meteor.global_position)
		if distance <= COVERAGE_RADIUS and distance < closest_distance:
			closest = meteor
			closest_distance = distance
	return closest


# Deliberately literal: a nearer busy dish wins over a farther idle dish. This
# makes the result spatially predictable, but the inability to call the farther
# dish is the primary playtest watch item for this interaction.
func nearest_dish_to(point: Vector2) -> int:
	var best_index := -1
	var best_distance := INF
	for index in range(dishes.size()):
		var distance: float = Vector2(dishes[index].position).distance_squared_to(point)
		if distance < best_distance:
			best_distance = distance
			best_index = index
	return best_index


# Predictive commitment preserves the previous capacity-aware choice. This is
# intentionally separate from plain movement and exists only behind research.
func commitment_dish_for(contact: Dictionary) -> int:
	var estimate := _estimate_of(contact)
	var best_free := -1
	var best_free_time := INF
	var best_any := -1
	var best_any_time := INF
	for index in range(dishes.size()):
		var dish: Dictionary = dishes[index]
		var travel: float = Vector2(dish.position).distance_to(estimate) / SLEW_SPEED
		if travel < best_any_time:
			best_any_time = travel
			best_any = index
		var free: bool = int(dish.assigned_id) == -1 and _locked_target(dish) == null
		if free and travel <= float(contact.countdown) and travel < best_free_time:
			best_free_time = travel
			best_free = index
	return best_free if best_free >= 0 else best_any


func move_dish_to(point: Vector2) -> int:
	if not dish_active():
		return -1
	var index := nearest_dish_to(point)
	if index < 0:
		return -1
	var dish: Dictionary = dishes[index]
	_abandon_dish_work(dish)
	dish.assigned_id = -1
	dish.locked_id = 0
	dish.target = point
	dish.arrived = Vector2(dish.position).is_equal_approx(point)
	dishes[index] = dish
	dish_movement_learned = true
	queue_redraw()
	return index


func _abandon_dish_work(dish: Dictionary) -> void:
	var dropped_contact_id := int(dish.get("assigned_id", -1))
	if dropped_contact_id != -1:
		var dropped_contact := _find_contact(dropped_contact_id)
		if not dropped_contact.is_empty():
			dropped_contact.abandoned_flash = 0.9
	var locked = _locked_target(dish)
	if locked == null:
		return
	locked.set_dish_assist_rate(0.0)
	abandoned_target_id = locked.get_instance_id()
	abandoned_target_position = locked.global_position
	abandoned_target_flash = 0.9


func _unhandled_input(event: InputEvent) -> void:
	if not dish_active():
		return
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	if event.button_index != MOUSE_BUTTON_RIGHT:
		return
	var point := Vector2(event.position)
	cursor_position = point
	var contact_id := _contact_at(point)
	if event.shift_pressed and _commitment_enabled() and contact_id >= 0:
		assign_to_contact(contact_id)
	else:
		move_dish_to(point)
	get_viewport().set_input_as_handled()


func assign_to_contact(contact_id: int) -> bool:
	if not dish_active() or not _commitment_enabled():
		return false
	var contact := _find_contact(contact_id)
	if contact.is_empty():
		return false
	var index := commitment_dish_for(contact)
	if index < 0:
		return false
	var dish: Dictionary = dishes[index]
	if int(dish.assigned_id) == contact_id:
		return false
	_abandon_dish_work(dish)
	dish.assigned_id = contact_id
	dish.locked_id = 0
	dish.target = _estimate_of(contact)
	dish.arrived = false
	dishes[index] = dish
	dish_commitment_learned = true
	queue_redraw()
	return true


func _commitment_enabled() -> bool:
	return progression != null and progression.dish_commitment_enabled()


func _find_contact(contact_id: int) -> Dictionary:
	for contact in contacts:
		if int(contact.id) == contact_id:
			return contact
	return {}


func _release_dish_for_contact(contact_id: int) -> void:
	for index in range(dishes.size()):
		var dish: Dictionary = dishes[index]
		if int(dish.assigned_id) == contact_id:
			dish.assigned_id = -1
			dishes[index] = dish


func _draw() -> void:
	if not forecast_visible():
		return
	for dish in dishes:
		_draw_dish(dish)
	if dish_active():
		_draw_movement_preview()
	for contact in contacts:
		_draw_contact(contact)
	_draw_abandoned_target_flash()


func _draw_dish(dish: Dictionary) -> void:
	var position: Vector2 = dish.position
	var arrived: bool = bool(dish.arrived)
	var color := Color("64e6c2") if arrived else Color("d8b45c")
	draw_circle(position, COVERAGE_RADIUS, Color(color, 0.05 if arrived else 0.02))
	draw_arc(position, COVERAGE_RADIUS, 0.0, TAU, 56, Color(color, 0.42 if arrived else 0.20),
		1.8 if arrived else 1.1, true)
	if not arrived:
		draw_line(position, Vector2(dish.target), Color(color, 0.34), 1.2, true)
		draw_arc(Vector2(dish.target), COVERAGE_RADIUS, 0.0, TAU, 56, Color(color, 0.14), 1.0, true)
	var assigned_contact := _find_contact(int(dish.assigned_id))
	if not assigned_contact.is_empty():
		var estimate := _estimate_of(assigned_contact)
		draw_line(position, estimate, Color("b99cff", 0.72), 1.6, true)
		draw_arc(estimate, 25.0, 0.0, TAU, 32, Color("b99cff", 0.72), 1.5, true)
	draw_circle(position, 7.0, Color(0.02, 0.05, 0.09, 0.95))
	draw_circle(position, 4.4, color)


func _draw_movement_preview() -> void:
	var index := nearest_dish_to(cursor_position)
	if index < 0:
		return
	var dish: Dictionary = dishes[index]
	var preview_color := Color("ffe9a8")
	draw_line(Vector2(dish.position), cursor_position, Color(preview_color, 0.48), 1.2, true)
	var locked = _locked_target(dish)
	if locked == null:
		return
	_draw_abandonment_mark(locked.global_position, Vector2(dish.position), 0.86)


func _draw_abandoned_target_flash() -> void:
	if abandoned_target_flash <= 0.0:
		return
	var point := abandoned_target_position
	if abandoned_target_id != 0:
		var target = instance_from_id(abandoned_target_id)
		if target != null and is_instance_valid(target):
			point = target.global_position
			abandoned_target_position = point
	_draw_abandonment_mark(point, point, abandoned_target_flash / 0.9)


func _draw_abandonment_mark(point: Vector2, tether_start: Vector2, alpha: float) -> void:
	var color := Color("ff6a5e", clampf(alpha, 0.0, 1.0))
	if not tether_start.is_equal_approx(point):
		draw_line(tether_start, point, color, 1.6, true)
	draw_arc(point, 27.0, 0.0, TAU, 32, color, 2.2, true)
	draw_line(point + Vector2(-13, -13), point + Vector2(13, 13), color, 2.0, true)
	draw_line(point + Vector2(13, -13), point + Vector2(-13, 13), color, 2.0, true)


func _draw_contact(contact: Dictionary) -> void:
	var font := ThemeDB.fallback_font
	var lead: float = maxf(float(contact.lead_time), 0.001)
	var certainty: float = clampf(1.0 - float(contact.countdown) / lead, 0.0, 1.0)
	var estimate := _estimate_of(contact)
	var base_color := Color("8fb6ff").lerp(Color("ffd27a"), certainty)
	if float(contact.get("abandoned_flash", 0.0)) > 0.0:
		base_color = Color("ff6a5e")
	var hovered: bool = int(contact.id) == hovered_contact_id
	var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.006) * 0.08

	var error_radius: float = lerpf(float(contact.max_error), 6.0, certainty)
	if error_radius > 7.0:
		draw_arc(estimate, error_radius * pulse, 0.0, TAU, 40, Color(base_color, 0.20), 1.0, true)
	draw_arc(estimate, 20.0 * pulse, 0.0, TAU, 32,
		Color(base_color, 0.85 if hovered else 0.6), 2.0 if hovered else 1.5, true)
	if progression.has_upgrade("filter_wheel"):
		var spectral_color := _spectral_band_color(String(contact.get("spectral_band", "blue")))
		draw_arc(estimate, 24.0 * pulse, -PI * 0.78, -PI * 0.22, 14,
			Color(spectral_color, 0.92), 3.0, true)
	if bool(contact.get("trajectory_known", false)):
		draw_line(estimate, estimate + Vector2(contact.direction) * 34.0, Color(base_color, 0.45), 1.2, true)

	var label := tr("CONTACT_UNCLASSIFIED")
	if bool(contact.classified):
		label = tr("METEOR_%s" % String(contact.type_id).to_upper())
	draw_string(font, estimate + Vector2(-60.0, -28.0), label,
		HORIZONTAL_ALIGNMENT_CENTER, 120.0, 14, Color(base_color, 0.95))
	if bool(contact.classified) and progression.has_upgrade("contact_ledger"):
		var spec := Balance.meteor_spec(String(contact.type_id))
		var metrics := tr("CONTACT_LEDGER_METRICS") % [int(spec.value), float(spec.track_time)]
		draw_string(font, estimate + Vector2(-70.0, -46.0), metrics,
			HORIZONTAL_ALIGNMENT_CENTER, 140.0, 12, Color(base_color, 0.72))
	draw_string(font, estimate + Vector2(-60.0, 40.0), "%.1fs" % maxf(0.0, float(contact.countdown)),
		HORIZONTAL_ALIGNMENT_CENTER, 120.0, 13, Color(base_color, 0.7))

	var hint_keys: Array[String] = []
	# Plain right-click moves whichever dish is nearest the click, so it is not a
	# per-contact action. Advertising it under every marker implied a targeting
	# gesture the control does not have; the Secondary Camera node teaches it.
	if _commitment_enabled() and (not dish_commitment_learned or hovered):
		hint_keys.append("CONTACT_COMMIT_HINT")
	# Manual-only information is secondary and appears only after classification,
	# so an unclassified contact never becomes a type oracle.
	if bool(contact.classified) and not _dish_can_track_type(String(contact.type_id)) and (not dish_movement_learned or hovered):
		hint_keys.append("CONTACT_MANUAL_ONLY_HINT")
	for hint_index in range(hint_keys.size()):
		_draw_assignment_hint(estimate, base_color, font, hint_keys[hint_index], hint_index, hint_keys.size())
	if hovered and _commitment_enabled() and Input.is_key_pressed(KEY_SHIFT):
		_draw_commitment_preview(contact, estimate)


func _spectral_band_color(band: String) -> Color:
	match band:
		"amber": return Color("ffbf66")
		"violet": return Color("b78cff")
		_: return Color("66bfff")


func _draw_commitment_preview(contact: Dictionary, estimate: Vector2) -> void:
	var index := commitment_dish_for(contact)
	if index < 0:
		return
	var dish: Dictionary = dishes[index]
	draw_line(Vector2(dish.position), estimate, Color("b99cff"), 1.6, true)
	draw_arc(estimate, COVERAGE_RADIUS, 0.0, TAU, 56, Color("b99cff", 0.48), 1.2, true)
	var locked = _locked_target(dish)
	if locked != null:
		_draw_abandonment_mark(locked.global_position, Vector2(dish.position), 0.86)
	var dropped_id := int(dish.assigned_id)
	if dropped_id == -1 or dropped_id == int(contact.id):
		return
	var dropped := _find_contact(dropped_id)
	if not dropped.is_empty():
		_draw_abandonment_mark(_estimate_of(dropped), Vector2(dish.position), 0.86)


func _draw_assignment_hint(estimate: Vector2, base_color: Color, font: Font, hint_key: String, row: int, row_count: int) -> void:
	var hint_top := 49.0 + float(row) * 28.0
	if estimate.y + 49.0 + float(row_count) * 28.0 > get_viewport_rect().size.y - 8.0:
		hint_top = -49.0 - float(row_count - row) * 28.0
	var hint_rect := Rect2(estimate + Vector2(-94.0, hint_top), Vector2(188.0, 24.0))
	draw_rect(hint_rect, Color(0.015, 0.035, 0.07, 0.92), true)
	draw_rect(hint_rect, Color(base_color, 0.68), false, 1.0)
	draw_string(font, estimate + Vector2(-94.0, hint_top + 17.0), tr(hint_key),
		HORIZONTAL_ALIGNMENT_CENTER, 188.0, 12, Color("f2fbff"))
