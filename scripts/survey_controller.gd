extends Node2D

signal sample_completed(slot: int, position: Vector2, reward: float, catalogued: bool)

const UITheme = preload("res://scripts/ui_theme.gd")

const GRID_SIZE := 7
const GRID_CENTRE := 3
const SOURCE_RADIUS := 72.0
const CELL_EXPIRY_SECONDS := 2.2
const MIN_SAMPLE_SCAN_SECONDS := 2.4
const COMPLETION_FLASH_SECONDS := 0.8
const SURVEY_SEED_BASE := 731_927
const INACTIVE_TIMESTAMP := -1000000.0

var progression: Node
var samples: Array[Dictionary] = []
var active_round: int = 0
var round_elapsed: float = 0.0
var completed_slot_mask: int = 0
var scanning: bool = false
var cursor_position := Vector2.ZERO


func _ready() -> void:
	get_viewport().size_changed.connect(_on_viewport_size_changed)


func setup(progression_controller: Node) -> void:
	progression = progression_controller
	reset()


func reset() -> void:
	samples.clear()
	active_round = 0
	round_elapsed = 0.0
	completed_slot_mask = 0
	scanning = false
	queue_redraw()


func begin_round(round_index: int) -> void:
	reset()
	active_round = maxi(1, round_index)
	if progression == null or not progression.survey_enabled():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = SURVEY_SEED_BASE + active_round * 7919
	var viewport_size := get_viewport_rect().size
	var sample_count: int = progression.get_survey_sample_count()
	for slot in range(sample_count):
		var normalized_position := _choose_normalized_position(rng, samples)
		var timestamps := PackedFloat32Array()
		timestamps.resize(GRID_SIZE * GRID_SIZE)
		timestamps.fill(INACTIVE_TIMESTAMP)
		samples.append({
			"slot": slot,
			"normalized_position": normalized_position,
			"center": normalized_position * viewport_size,
			"timestamps": timestamps,
			"scan_time": 0.0,
			"completed": false,
			"completion_time": INACTIVE_TIMESTAMP,
		})
	queue_redraw()


func end_round() -> void:
	reset()


func advance_time(real_delta: float) -> void:
	if active_round <= 0 or samples.is_empty():
		return
	round_elapsed += maxf(0.0, real_delta)
	var changed := false
	if progression != null and not progression.survey_coverage_persists():
		for sample in samples:
			if bool(sample.completed):
				continue
			var timestamps: PackedFloat32Array = sample.timestamps
			for index in range(timestamps.size()):
				if timestamps[index] > INACTIVE_TIMESTAMP and round_elapsed - timestamps[index] > CELL_EXPIRY_SECONDS:
					timestamps[index] = INACTIVE_TIMESTAMP
					changed = true
			sample.timestamps = timestamps
			if _active_cell_count(timestamps) == 0:
				sample.scan_time = 0.0
	if changed or _has_live_completion_flash():
		queue_redraw()


func set_scanning(value: bool, position: Vector2) -> void:
	var enabled: bool = active_round > 0 and progression != null and progression.survey_enabled()
	if not enabled and not scanning:
		return
	var next_scanning: bool = value and enabled
	var changed: bool = scanning != next_scanning or (next_scanning and cursor_position != position)
	scanning = next_scanning
	cursor_position = position
	if changed:
		queue_redraw()


func apply_scan_segment(from: Vector2, to: Vector2, active_delta: float = 0.0) -> int:
	if not scanning or progression == null or not progression.survey_enabled():
		return 0
	var path_length := from.distance_to(to)
	if path_length <= 0.01:
		return 0
	var brush_radius: float = progression.get_survey_brush_radius()
	var sample_steps := maxi(1, ceili(path_length / maxf(4.0, brush_radius * 0.45)))
	var completed_count := 0
	for sample in samples:
		if bool(sample.completed):
			continue
		var center: Vector2 = sample.center
		if _distance_to_segment(center, from, to) > SOURCE_RADIUS + brush_radius:
			continue
		var timestamps: PackedFloat32Array = sample.timestamps
		for step_index in range(sample_steps + 1):
			var point := from.lerp(to, float(step_index) / float(sample_steps))
			_mark_cells(timestamps, center, point, brush_radius)
		sample.timestamps = timestamps
		sample.scan_time = float(sample.scan_time) + maxf(0.0, active_delta)
		if _active_cell_count(timestamps) >= _eligible_cell_count() and float(sample.scan_time) >= MIN_SAMPLE_SCAN_SECONDS:
			_complete_sample(sample)
			completed_count += 1
	queue_redraw()
	return completed_count


func get_round_state() -> Dictionary:
	return {
		"round": active_round,
		"completed_slot_mask": completed_slot_mask,
	}


func load_round_state(value, round_index: int) -> void:
	if progression == null or not progression.survey_enabled():
		reset()
		return
	if active_round != round_index:
		begin_round(round_index)
	if not (value is Dictionary) or int(value.get("round", round_index)) != round_index:
		return
	completed_slot_mask = maxi(0, int(value.get("completed_slot_mask", 0)))
	for sample in samples:
		var slot := int(sample.slot)
		if (completed_slot_mask & (1 << slot)) == 0:
			continue
		sample.completed = true
		sample.completion_time = round_elapsed
	queue_redraw()


func get_completed_count() -> int:
	var count := 0
	for sample in samples:
		if bool(sample.completed):
			count += 1
	return count


func get_sample_coverage(slot: int) -> float:
	for sample in samples:
		if int(sample.slot) == slot:
			if bool(sample.completed):
				return 1.0
			return float(_active_cell_count(sample.timestamps)) / float(_eligible_cell_count())
	return 0.0


func _choose_normalized_position(rng: RandomNumberGenerator, existing_samples: Array[Dictionary]) -> Vector2:
	var fallback := Vector2(0.5, 0.42)
	for _attempt in range(24):
		var candidate := Vector2(rng.randf_range(0.12, 0.88), rng.randf_range(0.28, 0.72))
		fallback = candidate
		var separated := true
		for existing in existing_samples:
			if candidate.distance_to(Vector2(existing.normalized_position)) < 0.19:
				separated = false
				break
		if separated:
			return candidate
	return fallback


func _mark_cells(timestamps: PackedFloat32Array, center: Vector2, point: Vector2, brush_radius: float) -> void:
	var spacing := SOURCE_RADIUS * 2.0 / float(GRID_SIZE)
	var cell_reach := spacing * 0.46
	for cell_y in range(GRID_SIZE):
		for cell_x in range(GRID_SIZE):
			if not _cell_is_eligible(cell_x, cell_y):
				continue
			var cell_position := center + Vector2(
				(float(cell_x) + 0.5) * spacing - SOURCE_RADIUS,
				(float(cell_y) + 0.5) * spacing - SOURCE_RADIUS
			)
			if cell_position.distance_to(point) <= brush_radius + cell_reach:
				timestamps[cell_y * GRID_SIZE + cell_x] = round_elapsed


func _active_cell_count(timestamps: PackedFloat32Array) -> int:
	var count := 0
	for cell_y in range(GRID_SIZE):
		for cell_x in range(GRID_SIZE):
			if not _cell_is_eligible(cell_x, cell_y):
				continue
			var timestamp := timestamps[cell_y * GRID_SIZE + cell_x]
			if timestamp <= INACTIVE_TIMESTAMP:
				continue
			if progression.survey_coverage_persists() or round_elapsed - timestamp <= CELL_EXPIRY_SECONDS:
				count += 1
	return count


func _eligible_cell_count() -> int:
	var count := 0
	for cell_y in range(GRID_SIZE):
		for cell_x in range(GRID_SIZE):
			if _cell_is_eligible(cell_x, cell_y):
				count += 1
	return count


func _cell_is_eligible(cell_x: int, cell_y: int) -> bool:
	var offset_x := cell_x - GRID_CENTRE
	var offset_y := cell_y - GRID_CENTRE
	return offset_x * offset_x + offset_y * offset_y <= 10


func _complete_sample(sample: Dictionary) -> void:
	if bool(sample.completed):
		return
	sample.completed = true
	sample.completion_time = round_elapsed
	var slot := int(sample.slot)
	completed_slot_mask |= 1 << slot
	var reward: float = progression.add_survey_data(progression.get_survey_reward())
	var catalogued: bool = progression.survey_catalog_enabled()
	if catalogued:
		progression.record_survey_catalog_entry()
	sample_completed.emit(slot, Vector2(sample.center), reward, catalogued)


func _distance_to_segment(point: Vector2, from: Vector2, to: Vector2) -> float:
	var segment := to - from
	var length_squared := segment.length_squared()
	if length_squared <= 0.0001:
		return point.distance_to(to)
	var projection := clampf((point - from).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(from + segment * projection)


func _has_live_completion_flash() -> bool:
	for sample in samples:
		if bool(sample.completed) and round_elapsed - float(sample.completion_time) <= COMPLETION_FLASH_SECONDS:
			return true
	return false


func _on_viewport_size_changed() -> void:
	var viewport_size := get_viewport_rect().size
	for sample in samples:
		sample.center = Vector2(sample.normalized_position) * viewport_size
	queue_redraw()


func _draw() -> void:
	if samples.is_empty() or progression == null or not progression.survey_enabled():
		return
	var spacing := SOURCE_RADIUS * 2.0 / float(GRID_SIZE)
	for sample in samples:
		var center: Vector2 = sample.center
		if bool(sample.completed):
			_draw_completed_sample(center, float(sample.completion_time))
			continue
		var distance := cursor_position.distance_to(center)
		var proximity := clampf(1.0 - distance / (SOURCE_RADIUS + 180.0), 0.0, 1.0) if scanning else 0.0
		# The source itself is environmental, not a HUD label: a nearly invisible
		# fixed glint becomes legible only as a survey stroke approaches it.
		draw_circle(center, 1.2, Color(UITheme.INK_LOW, 0.10 + proximity * 0.18))
		draw_circle(center + Vector2(-11.0, 7.0), 0.8, Color(UITheme.ACCENT_DEEP, 0.06 + proximity * 0.12))
		draw_circle(center + Vector2(9.0, -8.0), 0.7, Color(UITheme.ACCENT_DEEP, 0.05 + proximity * 0.10))
		if scanning and proximity > 0.0:
			draw_arc(center, SOURCE_RADIUS, 0.0, TAU, 64, Color(UITheme.ACCENT_DEEP, 0.035 + proximity * 0.12), 1.2, true)
		var timestamps: PackedFloat32Array = sample.timestamps
		for cell_y in range(GRID_SIZE):
			for cell_x in range(GRID_SIZE):
				if not _cell_is_eligible(cell_x, cell_y):
					continue
				var timestamp := timestamps[cell_y * GRID_SIZE + cell_x]
				if timestamp <= INACTIVE_TIMESTAMP:
					continue
				var freshness := 1.0
				if not progression.survey_coverage_persists():
					freshness = clampf(1.0 - (round_elapsed - timestamp) / CELL_EXPIRY_SECONDS, 0.0, 1.0)
				if freshness <= 0.0:
					continue
				var cell_position := center + Vector2(
					(float(cell_x) + 0.5) * spacing - SOURCE_RADIUS,
					(float(cell_y) + 0.5) * spacing - SOURCE_RADIUS
				)
				draw_circle(cell_position, spacing * 0.34, Color(UITheme.ACCENT_LINE, (0.06 + proximity * 0.16) * freshness))


func _draw_completed_sample(center: Vector2, completion_time: float) -> void:
	var age := maxf(0.0, round_elapsed - completion_time)
	if progression.survey_catalog_enabled():
		var glow := 0.72 + sin(round_elapsed * 2.4) * 0.08
		draw_circle(center, 3.2, Color(UITheme.ACCENT_TEXT, glow))
		draw_circle(center, 10.0, Color(UITheme.ACCENT_DEEP, 0.10))
		for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			draw_line(center + direction * 5.0, center + direction * 13.0, Color(UITheme.ACCENT_LINE, 0.30), 1.0, true)
		return
	if age > COMPLETION_FLASH_SECONDS:
		return
	var fade := 1.0 - age / COMPLETION_FLASH_SECONDS
	draw_circle(center, lerpf(5.0, SOURCE_RADIUS * 0.82, 1.0 - fade), Color(UITheme.ACCENT_LINE, fade * 0.12))
	draw_arc(center, SOURCE_RADIUS * (1.0 - fade * 0.2), 0.0, TAU, 64, Color(UITheme.ACCENT_TEXT, fade * 0.62), 1.8, true)
