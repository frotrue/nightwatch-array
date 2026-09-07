extends Node2D

const UITheme = preload("res://scripts/ui_theme.gd")
var research: Node
var type_id := "andromeda"
var progress := 0.0
var cooldown := 0.0
var value_integral := 0.0
var cooldown_integral := 0.0
var integrated_progress := 0.0
var quality := 1.0
var dust: Array[Vector2] = []

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 310031
	for index in range(220):
		var radius := pow(rng.randf(), 0.7)
		var angle := rng.randf() * TAU
		dust.append(Vector2(cos(angle) * radius * 45, sin(angle) * radius * 13).rotated(-0.35))

func can_be_tracked() -> bool:
	return research != null and research.available() and research.game.observation_phase_active and cooldown <= 0.0

func get_tracking_radius(base: float) -> float:
	return base

func get_progress() -> float:
	return progress

func get_quality() -> float:
	return quality

func get_predicted_multiplier() -> float:
	return 1.0

func apply_manual_observation(delta: float, distance: float, radius: float, speed: float = 1.0) -> void:
	if not can_be_tracked() or delta <= 0.0:
		return
	quality = clampf(1.0 - distance / maxf(radius, 1.0), 0.0, 1.0)
	# Older snapshots and diagnostic fixtures can begin part-way through an
	# exposure. Account for that segment once under its restored configuration.
	if integrated_progress < progress:
		value_integral += (progress - integrated_progress) * float(research.modules.effect("m31_value"))
		cooldown_integral += (progress - integrated_progress) * float(research.modules.effect("m31_cooldown"))
	var previous := progress
	progress = minf(1.0, progress + delta * lerpf(0.8, 1.2, quality) * speed * research.game.progression.get_analysis_speed_multiplier("galaxy") / 10.0)
	var credited := progress - previous
	value_integral += credited * float(research.modules.effect("m31_value"))
	cooldown_integral += credited * float(research.modules.effect("m31_cooldown"))
	integrated_progress = progress
	research.note_m31_manual_progress(credited)
	if progress >= 1.0:
		var final_value := value_integral
		var final_cooldown := cooldown_integral
		progress = 0.0
		integrated_progress = 0.0
		value_integral = 0.0
		cooldown_integral = 0.0
		cooldown = 7.0 * final_cooldown
		research.record_observation(final_value)
	queue_redraw()

func _process(delta: float) -> void:
	visible = research != null and research.available()
	if not visible:
		return
	var game: Node = research.game
	position = game.observation_view.screen_to_world(get_viewport_rect().size * Vector2(0.73, 0.30))
	scale = Vector2.ONE * game.observation_view.screen_length_to_world(1.0)
	var was_cooling := cooldown > 0.0
	if game.observation_phase_active:
		cooldown = maxf(0.0, cooldown - delta / maxf(Engine.time_scale, 0.001))
	if was_cooling != (cooldown > 0.0):
		queue_redraw()

func _draw() -> void:
	var alpha := 0.3 if cooldown > 0 else 1.0
	for point in dust:
		draw_circle(point, 0.65, Color("CBD5E6", alpha * (0.45 - point.length() / 160.0)))
	for index in range(6, 0, -1):
		draw_circle(Vector2.ZERO, index * 1.5, Color("F0D7B4", alpha * 0.055))
	draw_circle(Vector2.ZERO, 1.5, Color("F0D7B4", alpha))
	# Completed fields add distinct observation layers around the same galaxy.
	# These are instrument annotations, not replacement astronomical artwork.
	if research != null:
		var trace: int = research.plan_progress("plan_trace_1").x + research.plan_progress("plan_trace_2").x
		var sweep: int = research.plan_progress("plan_sweep_1").x + research.plan_progress("plan_sweep_2").x
		var link: int = research.plan_progress("plan_link_1").x + research.plan_progress("plan_link_2").x
		for index in range(trace):
			var y := -19.0 + index * 7.0
			draw_line(Vector2(-52, y), Vector2(50, y - 18), Color("A7BDDD", alpha * 0.28), 0.7, true)
		for index in range(sweep):
			draw_arc(Vector2.ZERO, 22 + index * 4, PI * 0.90, PI * 1.86, 48, Color("C5ACC8", alpha * 0.28), 0.65, true)
		for index in range(link):
			var point := Vector2.from_angle(-0.5 + index * 0.7) * 42.0
			draw_line(Vector2.ZERO, point, Color("D8CDA9", alpha * 0.25), 0.6, true)
			draw_circle(point, 1.3, Color("D8CDA9", alpha * 0.75))
	var label := tr("DEEP_M31_NAME")
	var font: Font = UITheme.sans()
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_string(font, Vector2(-width * 0.5, 34), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("B2BCCA", 0.75))
