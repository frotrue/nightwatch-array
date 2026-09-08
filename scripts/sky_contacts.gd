extends Node2D

const UITheme = preload("res://scripts/ui_theme.gd")

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
const GALACTIC_MUTED_FORECAST_TYPES := ["common", "fast"]

var progression: Node
var meteor_layer: Node2D
var additional_target_layers: Array[Node2D] = []
var modules: RefCounted
var observation_view: Camera2D
var contacts: Array[Dictionary] = []
var dishes: Array[Dictionary] = []
var cursor_position := Vector2.ZERO
var hovered_contact_id: int = -1
var abandoned_target_id: int = 0
var abandoned_target_position := Vector2.ZERO
var abandoned_target_flash: float = 0.0


func setup(target_layer: Node2D, progression_controller: Node, view: Camera2D = null) -> void:
	meteor_layer = target_layer
	progression = progression_controller
	observation_view = view
	refresh_dishes()


func forecast_visible() -> bool:
	return progression != null and progression.forecast_visible()


func forecast_contact_visible(contact: Dictionary) -> bool:
	return not (
		progression != null
		and progression.galaxy_unlocked()
		and String(contact.get("type_id", "")) in GALACTIC_MUTED_FORECAST_TYPES
	)


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
	var size := _atmospheric_rect().size
	while dishes.size() < wanted:
		var dish_index := dishes.size()
		var home_x := 0.42 + 0.2 * float(dish_index)
		if wanted > 2:
			home_x = 0.5 + (float(dish_index) - float(wanted - 1) * 0.5) * 0.16
		var home := Vector2(size.x * home_x, size.y * 0.55)
		dishes.append({
			"position": home,
			"target": home,
			"assigned_id": -1,
			"locked_id": 0,
			"arrived": true,
		})
	if wanted > 2:
		for dish_index in range(wanted):
			var dish: Dictionary = dishes[dish_index]
			var home_x := 0.5 + (float(dish_index) - float(wanted - 1) * 0.5) * 0.16
			var home := Vector2(size.x * home_x, size.y * 0.55)
			dish.position = home
			dish.target = home
			dish.assigned_id = -1
			dish.locked_id = 0
			dish.arrived = true
			dishes[dish_index] = dish
	queue_redraw()


func reset() -> void:
	_clear_dish_assists()
	contacts.clear()
	hovered_contact_id = -1
	abandoned_target_id = 0
	abandoned_target_flash = 0.0
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
	_assign_contact_automatically(contact)
	queue_redraw()


func on_contact_resolved(contact: Dictionary, meteor) -> void:
	contacts.erase(contact)
	if meteor == null:
		_release_dish_for_contact(int(contact.id))
		return
	# Predictive control reached this forecast; hand the dish to the live object.
	for index in range(dishes.size()):
		var dish: Dictionary = dishes[index]
		if int(dish.assigned_id) == int(contact.id):
			dish.locked_id = meteor.get_instance_id() if _dish_can_track(meteor) else 0
			dish.assigned_id = -1
			dishes[index] = dish


func _contact_at(point: Vector2) -> int:
	for contact in contacts:
		if not forecast_contact_visible(contact):
			continue
		if point.distance_to(_estimate_of(contact)) <= _world_px(CONTACT_HIT_RADIUS):
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
		cursor_position = _screen_to_world(get_viewport().get_mouse_position())
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
			var track_step: float = TRACK_SPEED * progression.extension_effect("dish_move") * delta
			dish.position = Vector2(dish.position) + (
				offset if offset.length() <= track_step else offset.normalized() * track_step
			)
			dish.arrived = true
			if Vector2(dish.position).distance_to(locked.global_position) > _world_px(COVERAGE_RADIUS * progression.extension_effect("dish_radius")):
				dish.locked_id = 0
			else:
				locked.set_dish_assist_rate(_dish_assist_rate(locked))
			dishes[index] = dish
			continue

		dish.locked_id = 0
		var position: Vector2 = dish.position
		var target: Vector2 = dish.target
		if not position.is_equal_approx(target):
			var step: float = SLEW_SPEED * progression.extension_effect("dish_move") * delta
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
		# can acquire; predictive control can arrive before a forecast resolves.
		if bool(dish.arrived):
			var acquired = _acquire_target(dish, index)
			if acquired != null:
				dish.locked_id = acquired.get_instance_id()
				acquired.set_dish_assist_rate(_dish_assist_rate(acquired))
		dishes[index] = dish


func _clear_dish_assists() -> void:
	for child in _target_children():
		if child.has_method("set_dish_assist_rate"):
			child.set_dish_assist_rate(0.0)


func _dish_assist_rate(target) -> float:
	if target == null or not target.has_method("get_assist_rate"):
		return 0.0
	var multiplier := 1.0
	if modules != null and modules.has_method("dish_multiplier"):
		multiplier = float(modules.dish_multiplier(target))
	return target.get_assist_rate(DISH_TIME_MULTIPLIER) * multiplier * progression.extension_effect("dish_speed")


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
	if not is_instance_valid(target):
		return false
	if _dish_can_track_type(String(target.type_id)):
		return true
	# Meteor's generic lane-assist API also exists on manual-only major targets.
	# Only these explicitly introduced anomaly types expand the dish allowlist.
	return String(target.type_id) in ["anomaly_rare", "anomaly_afterglow"] and target.has_method("allows_automatic_assist") and target.allows_automatic_assist()


func _dish_can_track_type(type_id: String) -> bool:
	return type_id in DISH_TRACKABLE_TYPES


func _acquire_target(dish: Dictionary, own_index: int):
	var closest = null
	var closest_distance := INF
	for meteor in _target_children():
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
		if distance <= _world_px(COVERAGE_RADIUS * progression.extension_effect("dish_radius")) and distance < closest_distance:
			closest = meteor
			closest_distance = distance
	return closest


func _target_children() -> Array:
	var targets: Array = []
	if meteor_layer != null:
		targets.append_array(meteor_layer.get_children())
	for layer in additional_target_layers:
		if layer != null:
			targets.append_array(layer.get_children())
	return targets


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


# Predictive control only uses a genuinely idle dish that can reach the current
# estimate before entry. It never steals an active lock or a manual slew.
func _automatic_dish_for(contact: Dictionary) -> int:
	if not _dish_can_track_type(String(contact.type_id)):
		return -1
	var estimate := _estimate_of(contact)
	var best_free := -1
	var best_free_time := INF
	for index in range(dishes.size()):
		var dish: Dictionary = dishes[index]
		var travel: float = Vector2(dish.position).distance_to(estimate) / (SLEW_SPEED * progression.extension_effect("dish_move"))
		var free: bool = (
			int(dish.assigned_id) == -1
			and _locked_target(dish) == null
			and bool(dish.arrived)
		)
		if free and travel <= float(contact.countdown) and travel < best_free_time:
			best_free_time = travel
			best_free = index
	return best_free


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
	if not InputMap.has_action(&"nw_dish") or not event.is_action_pressed(&"nw_dish"):
		return
	var screen_position := get_viewport().get_mouse_position()
	if event is InputEventMouseButton:
		screen_position = event.position
	var point := _screen_to_world(screen_position)
	cursor_position = point
	move_dish_to(point)
	get_viewport().set_input_as_handled()


func _assign_contact_automatically(contact: Dictionary) -> bool:
	if not dish_active() or not _auto_assignment_enabled():
		return false
	var index := _automatic_dish_for(contact)
	if index < 0:
		return false
	var dish: Dictionary = dishes[index]
	dish.assigned_id = int(contact.id)
	dish.locked_id = 0
	dish.target = _estimate_of(contact)
	dish.arrived = false
	dishes[index] = dish
	queue_redraw()
	return true


func _auto_assignment_enabled() -> bool:
	return progression != null and progression.dish_auto_assignment_enabled()


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
	for contact in contacts:
		if forecast_contact_visible(contact):
			_draw_contact(contact)
	_draw_abandoned_target_flash()


func _draw_dish(dish: Dictionary) -> void:
	var position: Vector2 = dish.position
	var arrived: bool = bool(dish.arrived)
	var visual_scale := _world_px(1.0)
	var coverage_radius := _world_px(COVERAGE_RADIUS * progression.extension_effect("dish_radius"))
	var assigned_contact := _find_contact(int(dish.assigned_id))
	var assignment_visual_visible := (
		assigned_contact.is_empty() or forecast_contact_visible(assigned_contact)
	)
	# Parked and covering reads as the actionable accent; still slewing stays
	# neutral, because it is not yet doing anything.
	var color := UITheme.ACCENT_LINE if arrived else UITheme.INK_MID
	draw_circle(position, coverage_radius, Color(color, 0.05 if arrived else 0.02))
	draw_arc(position, coverage_radius, 0.0, TAU, 56, Color(color, 0.42 if arrived else 0.20),
		(1.8 if arrived else 1.1) * visual_scale, true)
	if not arrived and assignment_visual_visible:
		draw_line(position, Vector2(dish.target), Color(color, 0.34), 1.2 * visual_scale, true)
		draw_arc(Vector2(dish.target), coverage_radius, 0.0, TAU, 56, Color(color, 0.14), 1.0 * visual_scale, true)
	if not assigned_contact.is_empty() and assignment_visual_visible:
		var estimate := _estimate_of(assigned_contact)
		draw_line(position, estimate, Color(UITheme.ACCENT_TEXT, 0.72), 1.6 * visual_scale, true)
		draw_arc(estimate, 25.0 * visual_scale, 0.0, TAU, 32, Color(UITheme.ACCENT_TEXT, 0.72), 1.5 * visual_scale, true)
	draw_circle(position, 7.0 * visual_scale, UITheme.SHADOW)
	draw_circle(position, 4.4 * visual_scale, color)


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
	var visual_scale := _world_px(1.0)
	var color := Color(UITheme.ALERT, clampf(alpha, 0.0, 1.0))
	if not tether_start.is_equal_approx(point):
		draw_line(tether_start, point, color, 1.6 * visual_scale, true)
	draw_arc(point, 27.0 * visual_scale, 0.0, TAU, 32, color, 2.2 * visual_scale, true)
	draw_line(point + Vector2(-13, -13) * visual_scale, point + Vector2(13, 13) * visual_scale, color, 2.0 * visual_scale, true)
	draw_line(point + Vector2(13, -13) * visual_scale, point + Vector2(-13, 13) * visual_scale, color, 2.0 * visual_scale, true)


func _draw_contact(contact: Dictionary) -> void:
	var visual_scale := _world_px(1.0)
	var font := UITheme.sans()
	var lead: float = maxf(float(contact.lead_time), 0.001)
	var certainty: float = clampf(1.0 - float(contact.countdown) / lead, 0.0, 1.0)
	var estimate := _estimate_of(contact)
	# Certainty is brightness plus warmth: a loose early estimate sits at the
	# neutral mid ink and firms up into the actionable accent as it resolves.
	var base_color := UITheme.INK_MID.lerp(UITheme.ACCENT_TEXT, certainty)
	if float(contact.get("abandoned_flash", 0.0)) > 0.0:
		base_color = UITheme.ALERT
	var hovered: bool = int(contact.id) == hovered_contact_id
	var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.006) * 0.08

	var error_radius: float = lerpf(float(contact.max_error), _world_px(6.0), certainty)
	if error_radius > _world_px(7.0):
		draw_arc(estimate, error_radius * pulse, 0.0, TAU, 40, Color(base_color, 0.20), 1.0 * visual_scale, true)
	draw_arc(estimate, 20.0 * visual_scale * pulse, 0.0, TAU, 32,
		Color(base_color, 0.85 if hovered else 0.6), (2.0 if hovered else 1.5) * visual_scale, true)
	if bool(contact.get("trajectory_known", false)):
		draw_line(estimate, estimate + Vector2(contact.direction) * 34.0 * visual_scale, Color(base_color, 0.45), 1.2 * visual_scale, true)

	var label := tr("CONTACT_UNCLASSIFIED")
	if bool(contact.classified):
		label = tr("METEOR_%s" % String(contact.type_id).to_upper())
	draw_string(font, estimate + Vector2(-60.0, -28.0) * visual_scale, label,
		HORIZONTAL_ALIGNMENT_CENTER, 120.0 * visual_scale, int(round(14.0 * visual_scale)), Color(base_color, 0.95))
	# Tabular figures: a countdown that reflows its own width every tenth of a
	# second is the exact jitter the red-light spec rules out.
	draw_string(UITheme.mono_tabular(), estimate + Vector2(-60.0, 40.0) * visual_scale, "%.1fs" % maxf(0.0, float(contact.countdown)),
		HORIZONTAL_ALIGNMENT_CENTER, 120.0 * visual_scale, int(round(13.0 * visual_scale)), Color(base_color, 0.7))


func _atmospheric_rect() -> Rect2:
	if observation_view != null:
		return observation_view.atmospheric_rect()
	return Rect2(Vector2.ZERO, get_viewport_rect().size)


func _world_px(pixels: float) -> float:
	if observation_view != null:
		return observation_view.screen_length_to_world(pixels)
	return pixels


func _screen_to_world(point: Vector2) -> Vector2:
	if observation_view != null:
		return observation_view.screen_to_world(point)
	return point
