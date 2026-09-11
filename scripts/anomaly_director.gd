extends Node

const Data = preload("res://scripts/expansion_data.gd")
const Target = preload("res://scripts/anomaly_target.gd")
var research: Node
var remaining := 8.0
var opportunity_pending := false
var occurrence_rng := RandomNumberGenerator.new()
var scheduler_seed := 1
var scheduler_serial := 0
var event_serial := 0
var cycle: Array[String] = []
var pending: Array[Dictionary] = []
var tickets: Dictionary = {}
var _restore_targets: Array[Dictionary] = []

func setup(controller: Node) -> void:
	research = controller
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	scheduler_seed = rng.randi_range(1, 2147483646)
	occurrence_rng.seed = scheduler_seed

func targets() -> Array:
	var result: Array = []
	if research == null:
		return result
	for child in research.get_children():
		if child is Target and not child.is_queued_for_deletion():
			result.append(child)
	return result

func object_count() -> int:
	return targets().size() + pending.size()

func available_kinds() -> Array[String]:
	var kinds: Array[String] = []
	if research.modules_unlocked():
		kinds.append("rare")
	return kinds

func simulate_tick(delta: float) -> void:
	if research == null or not research.game.observation_phase_active or not research.available():
		return
	var real_delta := maxf(0.0, delta)
	for index in range(pending.size() - 1, -1, -1):
		pending[index].delay -= real_delta
		if pending[index].delay <= 0.0:
			var descriptor: Dictionary = pending[index]
			pending.remove_at(index)
			_spawn_component(descriptor)
	if available_kinds().is_empty():
		return
	var rolled := occurrence_rng.randf() < get_spawn_probability()
	remaining = maxf(0.0, remaining - real_delta)
	if remaining > 0.000001: return
	if rolled: opportunity_pending = true
	if opportunity_pending and targets().is_empty() and pending.is_empty(): try_opportunity()

func get_spawn_probability() -> float:
	return 1.0 / (38.0 * (0.8 if research.research_owned("ext_sweep_advanced") else 1.0) * 60.0)


func try_opportunity() -> bool:
	if available_kinds().is_empty() or not _safe_window(22.0) or not _space_for(1):
		return false
	event_serial += 1
	var ticket_id := "n/%d" % event_serial
	_ensure_ticket(ticket_id, "rare", "natural")
	pending.append_array(_event_descriptors(ticket_id, "rare", "single", 0.0))
	opportunity_pending = false
	remaining = 0.0
	research.changed.emit()
	research.game._autosave_active_slot()
	return true

func _safe_window(duration: float) -> bool:
	if not research.game.observation_phase_active or research.game.observation_phase_remaining < duration:
		return false
	# Existing important forecasts keep ownership of their warning and sky time.
	var events: Node = research.game.events
	if events.canis_major_state == "warning" or (events.canis_major_state == "scheduled" and events.canis_major_timer <= duration):
		return false
	for contact in research.game.spawner.pending_contacts:
		if String(contact.get("type_id", "")) == "major":
			return false
	for meteor in research.game.meteor_layer.get_children():
		if String(meteor.type_id) == "major" and meteor.can_be_tracked():
			return false
	return true

func _space_for(count: int) -> bool:
	return object_count() + count <= 3


func _ensure_ticket(id: String, kind: String, origin: String) -> void:
	if not tickets.has(id):
		tickets[id] = {"kind": kind, "origin_kind": origin, "components": {}, "sample_units": 0, "completed": false}

func _event_descriptors(ticket_id: String, kind: String, _variant: String, delay: float) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = scheduler_seed + event_serial * 15485863
	var start := Vector2(rng.randf_range(0.15, 0.35), rng.randf_range(0.23, 0.66))
	var end := Vector2(rng.randf_range(0.65, 0.85), rng.randf_range(0.23, 0.66))
	var result: Array[Dictionary] = [{"ticket": ticket_id, "event_id": ticket_id, "kind": kind, "origin_kind": tickets[ticket_id].origin_kind, "component": 0, "start": start, "end": end, "delay": delay}]
	return result

func _spawn_component(descriptor: Dictionary) -> void:
	if descriptor.get("kind", "") != "rare" or descriptor.get("origin_kind", "natural") != "natural":
		return
	var target := Target.new()
	target.configure(research, descriptor)
	target.z_index = 10
	research.add_child(target)
	target.restore_progress(descriptor.get("progress", {}), descriptor.get("restart", false))
	target._update_position(0.0)
	target.simulation_id = research.game.allocate_simulation_id()
	target.previous_simulation_position = target.global_position
	target.reset_physics_interpolation()

func remember_component(target: Node) -> void:
	if not tickets.has(target.reward_ticket_id):
		return
	var ticket: Dictionary = tickets[target.reward_ticket_id]
	var key := str(target.component_index)
	var previous: Dictionary = ticket.components.get(key, {})
	var snapshot: Dictionary = target.get_save_data()
	snapshot.data_paid = previous.get("data_paid", false)
	snapshot.manual_best = maxf(float(previous.get("manual_best", 0.0)), target.get_manual_contribution())
	snapshot.auto_best = maxf(float(previous.get("auto_best", 0.0)), target.get_automatic_contribution())
	snapshot.handoff = previous.get("handoff", false) or (target.get_manual_contribution() >= 0.25 and target.get_automatic_contribution() >= 0.25)
	snapshot.found = previous.get("found", false) or target.discovered
	ticket.components[key] = snapshot

func complete_component(target: Node) -> void:
	if target.alive or target.get_progress() < 0.9999:
		return
	remember_component(target)
	var ticket: Dictionary = tickets.get(target.reward_ticket_id, {})
	if ticket.is_empty() or ticket.completed:
		return
	var component: Dictionary = ticket.components[str(target.component_index)]
	if not component.data_paid:
		component.data_paid = true
		research.award_anomaly_data(target)
	research.game.observer.release_target(target)
	ticket.completed = true
	if ticket.origin_kind == "natural":
		var awarded: int = research.state.award_samples(maxi(0, research.state.sample_reward() - int(ticket.sample_units)))
		ticket.sample_units += awarded
		if awarded > 0:
			research.sample_feedback(awarded)
	research.changed.emit()
	research.game._autosave_active_slot()

func expire_component(target: Node) -> void:
	remember_component(target)
	research.game.observer.release_target(target)
	research.changed.emit()


func end_round() -> void:
	for target in targets():
		if target.alive:
			remember_component(target)
		research.game.observer.release_target(target)
		target.free()
	pending.clear()

func reset() -> void:
	opportunity_pending = false
	occurrence_rng.seed = scheduler_seed
	end_round()
	tickets.clear()
	cycle.clear()
	_restore_targets.clear()
	remaining = 8.0
	scheduler_serial = 0
	event_serial = 0

func get_save_data() -> Dictionary:
	var active: Array = []
	for target in targets():
		if target.alive:
			active.append(target.get_save_data())
	return {"occurrence_state": str(occurrence_rng.state), "opportunity_pending": opportunity_pending, "remaining": remaining, "scheduler_seed": scheduler_seed, "scheduler_serial": scheduler_serial, "event_serial": event_serial, "cycle": cycle.duplicate(), "pending": _encode_pending(), "tickets": tickets.duplicate(true), "active": active}

func _encode_pending() -> Array:
	var result: Array = []
	for descriptor in pending:
		var copy: Dictionary = descriptor.duplicate(true)
		copy.start = [descriptor.start.x, descriptor.start.y]
		copy.end = [descriptor.end.x, descriptor.end.y]
		result.append(copy)
	return result

func load_save_data(data: Dictionary) -> void:
	reset()
	remaining = Data.number(data.get("remaining", 8.0), 44.0, 8.0)
	scheduler_seed = maxi(1, Data.integer(data.get("scheduler_seed", scheduler_seed), 2147483646, scheduler_seed))
	occurrence_rng.seed = scheduler_seed
	var saved_rng = data.get("occurrence_state", "")
	if saved_rng is String and saved_rng.is_valid_int(): occurrence_rng.state = saved_rng.to_int()
	# A legacy countdown grants one opportunity when due, then uses independent rolls.
	opportunity_pending = Data.flag(data.get("opportunity_pending", not data.has("occurrence_state")))
	scheduler_serial = Data.integer(data.get("scheduler_serial", 0), 100000000)
	event_serial = Data.integer(data.get("event_serial", 0), 100000000)
	var saved_cycle = data.get("cycle", [])
	if saved_cycle is Array:
		for kind in saved_cycle:
			if kind is String and kind in available_kinds() and kind not in cycle:
				cycle.append(kind)
	var raw_tickets = data.get("tickets", {})
	if raw_tickets is Dictionary:
		for id in raw_tickets:
			if not id is String or id.length() > 120 or tickets.size() >= 10000:
				continue
			var ticket = raw_tickets[id]
			if not ticket is Dictionary or ticket.get("kind", "") != "rare" or not ticket.get("components", {}) is Dictionary:
				continue
			var origin: String = ticket.get("origin_kind", "natural") if ticket.get("origin_kind", "") is String else "natural"
			if origin != "natural":
				continue
			_ensure_ticket(id, ticket.kind, origin)
			tickets[id].sample_units = Data.integer(ticket.get("sample_units", 0), 3)
			tickets[id].completed = Data.flag(ticket.get("completed", false))
			for key in ["0", "1"]:
				var component = ticket.components.get(key, {})
				if component is Dictionary:
					var clean: Dictionary = component.duplicate(true)
					for flag_key in ["complete", "data_paid", "handoff", "found", "discovered"]:
						clean[flag_key] = Data.flag(component.get(flag_key, false))
					for number_key in ["manual_best", "auto_best", "manual_work", "automatic_work", "stage_progress"]:
						clean[number_key] = Data.number(component.get(number_key, 0.0), 1.0)
					tickets[id].components[key] = clean
	var active = data.get("active", [])
	if active is Array:
		for entry in active:
			if entry is Dictionary and _restore_targets.size() < 3:
				var descriptor := _decode_descriptor(entry)
				if not descriptor.is_empty():
					descriptor.progress = entry.duplicate(true)
					_restore_targets.append(descriptor)
	var raw_pending = data.get("pending", [])
	if raw_pending is Array:
		for entry in raw_pending:
			if entry is Dictionary and pending.size() + _restore_targets.size() < 3:
				var descriptor := _decode_descriptor(entry)
				if not descriptor.is_empty():
					pending.append(descriptor)

func _decode_descriptor(entry: Dictionary) -> Dictionary:
	if entry.get("kind", "") != "rare" or not tickets.has(entry.get("ticket", "")):
		return {}
	var descriptor: Dictionary = entry.duplicate(true)
	for key in ["start", "end"]:
		var point = entry.get(key, [0.5, 0.5])
		if not point is Array or point.size() != 2:
			return {}
		descriptor[key] = Vector2(Data.number(point[0], 1.0, 0.5), Data.number(point[1], 1.0, 0.5))
	descriptor.delay = Data.number(entry.get("delay", 0), 20.0)
	descriptor.component = Data.integer(entry.get("component", 0), 1)
	descriptor.origin_kind = tickets[entry.ticket].origin_kind
	descriptor.event_id = str(entry.get("event_id", entry.ticket))
	descriptor.variant = str(entry.get("variant", "single"))
	descriptor.progress = entry.get("progress", {}) if entry.get("progress", {}) is Dictionary else {}
	descriptor.restart = Data.flag(entry.get("restart", false))
	return descriptor

# Collapse each in-flight v2 event into one ordinary rare meteor. Already earned
# currency/Data stays in the game save; partial observation becomes normalized
# progress on the new target, and the old payment flags still prevent replays.
static func migrate_v2(data: Dictionary) -> Dictionary:
	var result: Dictionary = data.duplicate(true)
	result.active = []
	result.pending = []
	result.tickets = {}
	var old_tickets = data.get("tickets", {})
	if not old_tickets is Dictionary: old_tickets = {}
	var grouped: Dictionary = {}
	for list_key in ["active", "pending"]:
		var entries = data.get(list_key, [])
		if not entries is Array: continue
		for entry in entries:
			if not entry is Dictionary or not entry.get("ticket", "") is String: continue
			var id: String = entry.get("ticket", "")
			if id.is_empty() or entry.get("origin_kind", "") == "archive" or entry.get("kind", "") not in ["spectrum", "pair", "afterglow"]: continue
			if not grouped.has(id): grouped[id] = {"entry": entry.duplicate(true), "key": list_key, "components": {}}
			var progress = entry if list_key == "active" else entry.get("progress", {})
			if progress is Dictionary:
				grouped[id].components[str(Data.integer(entry.get("component", 0), 1))] = progress
	for id in grouped:
		var group: Dictionary = grouped[id]
		var entry: Dictionary = group.entry
		var old = old_tickets.get(id, {})
		if not old is Dictionary: old = {}
		var components = old.get("components", {})
		if not components is Dictionary: components = {}
		components = components.duplicate(true)
		components.merge(group.components, true)
		var count := 2 if entry.kind == "pair" else 1
		var progress := 0.0
		var data_paid := false
		for index in range(count):
			var component = components.get(str(index), {})
			if not component is Dictionary: continue
			var amount := Data.number(component.get("stage_progress", 0.0), 1.0)
			if entry.kind == "spectrum": amount = (Data.integer(component.get("stage", 0), 1) + amount) / 2.0
			if Data.flag(component.get("complete", false)): amount = 1.0
			progress += amount / count
		var saved_components = old.get("components", {})
		if saved_components is Dictionary:
			for component in saved_components.values():
				if component is Dictionary: data_paid = data_paid or Data.flag(component.get("data_paid", false))
		entry.kind = "rare"
		entry.origin_kind = "natural"
		entry.component = 0
		entry.stage_progress = minf(progress, 0.999999)
		entry.age = 0.0 # Give migrated partial work a full new observation window.
		entry.discovered = false
		entry.progress = {"stage_progress": entry.stage_progress, "discovered": false}
		result[group.key].append(entry)
		result.tickets[id] = {"kind": entry.kind, "origin_kind": entry.origin_kind, "components": {"0": {"data_paid": data_paid}}, "sample_units": Data.integer(old.get("sample_units", 0), 2), "completed": Data.flag(old.get("completed", false))}
	return result

func resume_targets() -> void:
	for descriptor in _restore_targets:
		_spawn_component(descriptor)
	_restore_targets.clear()
