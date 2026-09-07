extends Node

const Data = preload("res://scripts/expansion_data.gd")
const Target = preload("res://scripts/anomaly_target.gd")
var research: Node
var remaining := 8.0
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
	for kind in ["spectrum", "afterglow", "pair"]:
		if Data.study_for_kind(kind) in research.state.research_ids:
			kinds.append(kind)
	return kinds

func plan_selected() -> void:
	if research.state.selected_plan not in research.state.guided_plans:
		remaining = minf(remaining, 8.0)

func _process(delta: float) -> void:
	if research == null or not research.game.observation_phase_active or not research.available():
		return
	var real_delta := maxf(0.0, delta / maxf(Engine.time_scale, 0.001))
	for index in range(pending.size() - 1, -1, -1):
		pending[index].delay -= real_delta
		if pending[index].delay <= 0.0:
			var descriptor: Dictionary = pending[index]
			pending.remove_at(index)
			_spawn_component(descriptor)
	if available_kinds().is_empty():
		return
	remaining = maxf(0.0, remaining - real_delta)
	if remaining > 0.0 or not targets().is_empty() or not pending.is_empty():
		return
	try_opportunity()

func try_opportunity() -> bool:
	if available_kinds().is_empty() or not _safe_window(22.0) or not _space_for(3):
		return false
	var assignments: Array[Dictionary] = []
	var field: Dictionary = research.state.active_field()
	var definition: Dictionary = research.state.field_definition()
	if not field.is_empty() and field.prepared and not research.state.field_ready():
		var plan: String = research.state.selected_plan
		var field_index: int = research.state.field_index()
		for event in definition.events:
			if field.evidence.get(event.slot, false):
				continue
			var ticket_id := "p/%s/%d/%s" % [plan, field_index, event.slot]
			_ensure_ticket(ticket_id, event.kind, "plan", plan, field_index, event.slot, definition.get("mode", "manual"))
			assignments.append_array(_event_descriptors(ticket_id, event.kind, event.get("variant", "single"), float(event.get("delay", 0.0))))
		# A parallel exposure may be the only remaining evidence. Reoffer its pair
		# using the same ticket, keeping all prior Data and sample payment flags.
		if assignments.is_empty() and definition.get("parallel", false) and field.parallel_progress < 0.25:
			for event in definition.events:
				if event.kind == "pair":
					var ticket_id := "p/%s/%d/%s" % [plan, field_index, event.slot]
					assignments.append_array(_event_descriptors(ticket_id, "pair", event.get("variant", "upper"), 0.0, true))
	else:
		var kind := _next_kind()
		if kind.is_empty():
			return false
		event_serial += 1
		var ticket_id := "n/%d" % event_serial
		_ensure_ticket(ticket_id, kind, "natural")
		assignments.append_array(_event_descriptors(ticket_id, kind, "single" if kind == "spectrum" else "center", 0.0))
	if assignments.is_empty() or not _space_for(assignments.size()):
		return false
	for descriptor in assignments:
		pending.append(descriptor)
	var selected: String = research.state.selected_plan
	if not selected.is_empty() and selected not in research.state.guided_plans:
		research.state.guided_plans.append(selected)
	remaining = _next_interval()
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
	if object_count() + count > 3:
		return false
	var spawner: Node = research.game.spawner
	return research.game.meteor_layer.get_child_count() + spawner.pending_contacts.size() + spawner.pending_echoes.size() + object_count() + count <= 31

func _next_interval() -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = scheduler_seed + scheduler_serial * 104729
	scheduler_serial += 1
	return rng.randf_range(32.0, 44.0)

func _next_kind() -> String:
	var unlocked := available_kinds()
	if unlocked.is_empty():
		return ""
	for index in range(cycle.size() - 1, -1, -1):
		if cycle[index] not in unlocked:
			cycle.remove_at(index)
	if cycle.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = scheduler_seed + scheduler_serial * 104729
		scheduler_serial += 1
		while not unlocked.is_empty():
			var index := rng.randi_range(0, unlocked.size() - 1)
			cycle.append(unlocked[index])
			unlocked.remove_at(index)
	return cycle.pop_front()

func _ensure_ticket(id: String, kind: String, origin: String, plan: String = "", field_index: int = 0, slot: String = "", mode: String = "manual") -> void:
	if tickets.has(id):
		return
	tickets[id] = {"kind": kind, "origin_kind": origin, "plan": plan, "field": field_index, "slot": slot, "mode": mode, "components": {}, "sample_units": 0, "completed": false}

func _event_descriptors(ticket_id: String, kind: String, variant: String, delay: float, force_replay: bool = false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ticket: Dictionary = tickets[ticket_id]
	var replay: bool = force_replay or bool(ticket.completed)
	var count := 2 if kind == "pair" else 1
	for index in range(count):
		var saved: Dictionary = ticket.components.get(str(index), {})
		if saved.get("complete", false) and not replay:
			continue
		var route := _route(kind, variant, index)
		result.append({"ticket": ticket_id, "event_id": ticket_id, "kind": kind, "origin_kind": ticket.origin_kind, "variant": variant, "component": index, "start": route[0], "end": route[1], "delay": delay, "progress": {} if replay else saved.duplicate(true), "restart": true})
	return result

func _route(kind: String, variant: String, component: int) -> Array[Vector2]:
	if kind == "afterglow":
		var centers := {"center": Vector2(0.48, 0.51), "outer": Vector2(0.18, 0.58), "left": Vector2(0.22, 0.47), "right": Vector2(0.83, 0.60), "upper": Vector2(0.49, 0.20), "lower": Vector2(0.47, 0.72)}
		var end: Vector2 = centers.get(variant, Vector2(0.48, 0.51))
		return [end - Vector2(0.10, 0.04), end]
	if kind == "pair":
		var base_y := 0.31 if variant == "upper" else (0.65 if variant == "lower" else 0.48)
		var start := Vector2(0.34 + component * 0.04, base_y)
		var end := Vector2(0.66 + component * 0.04, base_y + 0.04)
		if variant in ["diverging", "upper", "lower"]:
			end.y += -0.12 if component == 0 else 0.12
		return [start, end]
	match variant:
		"diagonal": return [Vector2(0.24, 0.23), Vector2(0.68, 0.65)]
		"parallel_a": return [Vector2(0.22, 0.37), Vector2(0.67, 0.42)]
		"parallel_b": return [Vector2(0.26, 0.49), Vector2(0.71, 0.54)]
		"cross_a": return [Vector2(0.22, 0.29), Vector2(0.73, 0.61)]
		"cross_b": return [Vector2(0.24, 0.63), Vector2(0.69, 0.27)]
	return [Vector2(0.26, 0.40), Vector2(0.73, 0.47)]

func _spawn_component(descriptor: Dictionary) -> void:
	var target := Target.new()
	target.configure(research, descriptor)
	target.z_index = 10
	research.add_child(target)
	target.restore_progress(descriptor.get("progress", {}), descriptor.get("restart", false))
	target._update_position(0.0)

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
	remember_component(target)
	var ticket: Dictionary = tickets.get(target.reward_ticket_id, {})
	if ticket.is_empty():
		return
	var component: Dictionary = ticket.components[str(target.component_index)]
	if not component.data_paid:
		component.data_paid = true
		research.award_anomaly_data(target)
	research.modules.notify_completed(target)
	research.game.observer.release_target(target)
	var count := 2 if ticket.kind == "pair" else 1
	var complete := true
	for index in range(count):
		if not ticket.components.get(str(index), {}).get("complete", false):
			complete = false
	if complete:
		ticket.completed = true
		if ticket.origin_kind in ["plan", "natural"]:
			var desired := 2 if _manual_qualified(ticket) else 1
			var awarded: int = research.state.award_samples(maxi(0, desired - int(ticket.sample_units)), research.modules.purchased)
			ticket.sample_units += awarded
			if awarded > 0:
				research.sample_feedback(awarded)
		if not String(ticket.plan).is_empty() and _task_qualified(ticket):
			research.state.record_evidence(ticket.plan, ticket.field, ticket.slot)
	research.changed.emit()
	research.game._autosave_active_slot()

func _manual_qualified(ticket: Dictionary) -> bool:
	var total := 0.0
	for component in ticket.components.values():
		total += float(component.get("manual_best", 0.0))
		if ticket.kind == "afterglow" and component.get("found", false):
			return true
	return total / (2.0 if ticket.kind == "pair" else 1.0) >= 0.25

func _task_qualified(ticket: Dictionary) -> bool:
	if ticket.kind != "pair" or ticket.mode == "manual":
		return _manual_qualified(ticket)
	var a: Dictionary = ticket.components.get("0", {})
	var b: Dictionary = ticket.components.get("1", {})
	match ticket.mode:
		"split": return (a.get("manual_best", 0) >= 0.25 and b.get("auto_best", 0) >= 0.75) or (b.get("manual_best", 0) >= 0.25 and a.get("auto_best", 0) >= 0.75)
		"handoff": return a.get("handoff", false) or b.get("handoff", false)
		"parallel": return a.get("auto_best", 0) > 0.0 or b.get("auto_best", 0) > 0.0
	return false

func expire_component(target: Node) -> void:
	remember_component(target)
	research.game.observer.release_target(target)
	research.changed.emit()

func pair_automatic_active() -> bool:
	var plan: String = research.state.selected_plan
	var index: int = research.state.field_index()
	for target in targets():
		if target.kind != "pair" or not target.can_be_tracked() or target.last_auto_frame < Engine.get_process_frames() - 1:
			continue
		var ticket: Dictionary = tickets.get(target.reward_ticket_id, {})
		if ticket.get("plan", "") == plan and ticket.get("field", -1) == index:
			return true
	return false

func record_sweep_segment(from: Vector2, to: Vector2) -> void:
	var width: float = research.game.observation_view.screen_length_to_world(30.0 * float(research.modules.effect("discovery_width")))
	var revealed := false
	for target in targets():
		revealed = target.reveal(from, to, width) or revealed
	if revealed:
		research.changed.emit()

func archive_meteor(meteor: Node) -> void:
	if not research.modules.has("afterglow_archive") or not research.game.observation_phase_active or meteor.type_id not in ["common", "fast"] or not meteor.is_natural_observation():
		return
	for target in targets():
		if target.origin_kind == "archive":
			return
	if not _space_for(1):
		return
	var rect: Rect2 = research.game.observation_view.atmospheric_rect()
	var uv: Vector2 = (meteor.global_position - rect.position) / rect.size
	uv = uv.clamp(Vector2(0.12, 0.17), Vector2(0.88, 0.77))
	event_serial += 1
	var id := "a/%d" % event_serial
	_ensure_ticket(id, "afterglow", "archive")
	_spawn_component({"ticket": id, "event_id": id, "kind": "afterglow", "origin_kind": "archive", "component": 0, "start": uv, "end": uv, "archive_value": meteor.base_value * 0.5})

func end_round() -> void:
	for target in targets():
		if target.alive:
			remember_component(target)
		research.game.observer.release_target(target)
		target.free()
	pending.clear()

func reset() -> void:
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
	return {"remaining": remaining, "scheduler_seed": scheduler_seed, "scheduler_serial": scheduler_serial, "event_serial": event_serial, "cycle": cycle.duplicate(), "pending": _encode_pending(), "tickets": tickets.duplicate(true), "active": active}

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
			if not ticket is Dictionary or ticket.get("kind", "") not in ["spectrum", "pair", "afterglow"] or not ticket.get("components", {}) is Dictionary:
				continue
			var origin: String = ticket.get("origin_kind", "natural") if ticket.get("origin_kind", "") is String else "natural"
			if origin not in ["plan", "natural", "archive"]:
				continue
			var plan: String = ticket.get("plan", "") if ticket.get("plan", "") is String else ""
			if not plan.is_empty() and not Data.PLANS.has(plan):
				continue
			_ensure_ticket(id, ticket.kind, origin, plan, Data.integer(ticket.get("field", 0), 2), str(ticket.get("slot", "")), str(ticket.get("mode", "manual")))
			tickets[id].sample_units = Data.integer(ticket.get("sample_units", 0), 2)
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
	if entry.get("kind", "") not in ["spectrum", "pair", "afterglow"] or not tickets.has(entry.get("ticket", "")):
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
	descriptor.archive_value = Data.number(entry.get("archive_value", 0), 1000000)
	descriptor.progress = entry.get("progress", {}) if entry.get("progress", {}) is Dictionary else {}
	descriptor.restart = Data.flag(entry.get("restart", false))
	return descriptor

func resume_targets() -> void:
	for descriptor in _restore_targets:
		_spawn_component(descriptor)
	_restore_targets.clear()
