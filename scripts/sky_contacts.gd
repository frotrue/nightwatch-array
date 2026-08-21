extends Node2D

# The player-aimed half of the observation array. Secondary Camera used to hand
# a target to the game; it now hands the player a dish and a few seconds of
# warning, and the aiming is theirs. Inert until that research is installed.

const SLEW_SPEED := 420.0
# Below the 390 of a fast meteor on purpose: a dish cannot hold the quick ones,
# so manual observation stays the only way to take them.
const TRACK_SPEED := 330.0
const COVERAGE_RADIUS := 105.0
const SCAN_RATE := 0.45
const CONTACT_HIT_RADIUS := 30.0

var progression: Node
var meteor_layer: Node2D
var contacts: Array[Dictionary] = []
var dishes: Array[Dictionary] = []
var cursor_position := Vector2.ZERO
var hovered_contact_id: int = -1


func setup(target_layer: Node2D, progression_controller: Node) -> void:
	meteor_layer = target_layer
	progression = progression_controller
	refresh_dishes()


func is_active() -> bool:
	return not dishes.is_empty()


# Dishes arrive with the research that grants them and park mid-sky, where they
# are equidistant from most entry points.
func refresh_dishes() -> void:
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


func reset() -> void:
	contacts.clear()
	hovered_contact_id = -1
	for index in range(dishes.size()):
		var dish: Dictionary = dishes[index]
		dish.assigned_id = -1
		dish.locked_id = 0
		dish.target = dish.position
		dish.arrived = true
		dishes[index] = dish
	queue_redraw()


func on_contact_announced(contact: Dictionary) -> void:
	if not is_active():
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
			dish.locked_id = meteor.get_instance_id()
			dish.assigned_id = -1
			dishes[index] = dish


func is_pointer_over_contact(pointer_position: Vector2) -> bool:
	return _contact_at(pointer_position) >= 0


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
	if not is_active():
		return
	cursor_position = get_viewport().get_mouse_position()
	hovered_contact_id = _contact_at(cursor_position)
	_update_dishes(delta)
	queue_redraw()


func _update_dishes(delta: float) -> void:
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
				locked.set_secondary_assist(SCAN_RATE)
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

		# A slewing dish records nothing. Arriving before the object does is
		# what the commitment buys.
		if bool(dish.arrived):
			var acquired = _acquire_target(dish, index)
			if acquired != null:
				dish.locked_id = acquired.get_instance_id()
				acquired.set_secondary_assist(SCAN_RATE)
		dishes[index] = dish


func _locked_target(dish: Dictionary):
	var locked_id := int(dish.get("locked_id", 0))
	if locked_id == 0:
		return null
	var locked = instance_from_id(locked_id)
	if locked == null or not is_instance_valid(locked):
		return null
	if not locked.has_method("can_be_tracked") or not locked.can_be_tracked():
		return null
	return locked


func _acquire_target(dish: Dictionary, own_index: int):
	var closest = null
	var closest_distance := INF
	for child_index in range(meteor_layer.get_child_count()):
		var meteor = meteor_layer.get_child(child_index)
		if not meteor.has_method("can_be_tracked") or not meteor.can_be_tracked():
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


# Prefer a free dish that can still make it; otherwise the nearest one, which
# means the click itself is the act of abandoning what it was covering.
func candidate_dish_for(contact: Dictionary) -> int:
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


func _unhandled_input(event: InputEvent) -> void:
	if not is_active():
		return
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	var contact_id := _contact_at(get_viewport().get_mouse_position())
	if contact_id < 0:
		return
	assign_to_contact(contact_id)
	get_viewport().set_input_as_handled()


func assign_to_contact(contact_id: int) -> bool:
	var contact := _find_contact(contact_id)
	if contact.is_empty():
		return false
	var index := candidate_dish_for(contact)
	if index < 0:
		return false
	var dish: Dictionary = dishes[index]
	if int(dish.assigned_id) == contact_id:
		return false
	var dropped_id := int(dish.assigned_id)
	if dropped_id != -1:
		var dropped := _find_contact(dropped_id)
		if not dropped.is_empty():
			dropped.abandoned_flash = 0.9
	dish.assigned_id = contact_id
	dish.locked_id = 0
	dish.target = _estimate_of(contact)
	dish.arrived = false
	dishes[index] = dish
	queue_redraw()
	return true


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
	if not is_active():
		return
	for dish in dishes:
		_draw_dish(dish)
	for contact in contacts:
		_draw_contact(contact)


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
	draw_circle(position, 7.0, Color(0.02, 0.05, 0.09, 0.95))
	draw_circle(position, 4.4, color)


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

	var error_radius: float = lerpf(70.0, 6.0, certainty)
	if error_radius > 7.0:
		draw_arc(estimate, error_radius * pulse, 0.0, TAU, 40, Color(base_color, 0.20), 1.0, true)
	draw_arc(estimate, 20.0 * pulse, 0.0, TAU, 32,
		Color(base_color, 0.85 if hovered else 0.6), 2.0 if hovered else 1.5, true)
	draw_line(estimate, estimate + Vector2(contact.direction) * 34.0, Color(base_color, 0.45), 1.2, true)

	var label := tr("CONTACT_UNCLASSIFIED")
	if bool(contact.classified):
		label = tr("METEOR_%s" % String(contact.type_id).to_upper())
	draw_string(font, estimate + Vector2(-60.0, -28.0), label,
		HORIZONTAL_ALIGNMENT_CENTER, 120.0, 14, Color(base_color, 0.95))
	draw_string(font, estimate + Vector2(-60.0, 40.0), "%.1fs" % maxf(0.0, float(contact.countdown)),
		HORIZONTAL_ALIGNMENT_CENTER, 120.0, 13, Color(base_color, 0.7))

	# Hovering shows which dish answers this call, and therefore what it drops.
	if not hovered:
		return
	var index := candidate_dish_for(contact)
	if index < 0:
		return
	var dish: Dictionary = dishes[index]
	draw_line(Vector2(dish.position), estimate, Color("ffe9a8"), 1.4, true)
	draw_arc(estimate, COVERAGE_RADIUS, 0.0, TAU, 56, Color("ffe9a8"), 1.0, true)
	var dropped_id := int(dish.assigned_id)
	if dropped_id == -1 or dropped_id == int(contact.id):
		return
	var dropped := _find_contact(dropped_id)
	if dropped.is_empty():
		return
	var dropped_point := _estimate_of(dropped)
	draw_arc(dropped_point, 27.0, 0.0, TAU, 32, Color("ff6a5e"), 2.2, true)
	draw_line(dropped_point + Vector2(-13, -13), dropped_point + Vector2(13, 13), Color("ff6a5e"), 2.0, true)
	draw_line(dropped_point + Vector2(13, -13), dropped_point + Vector2(-13, 13), Color("ff6a5e"), 2.0, true)
