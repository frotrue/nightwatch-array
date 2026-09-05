extends Control
const UITheme = preload("res://scripts/ui_theme.gd")

var stage: Node
var stars: Array[Dictionary] = []
var galaxy_stars: Array[Dictionary] = []
var target_stars: Array[Dictionary] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = 310206
	for index in range(100):
		stars.append({"p": Vector2(rng.randf(), rng.randf()), "a": rng.randf_range(0.15, 0.50), "r": rng.randf_range(0.4, 1.0)})
	for index in range(1000):
		var angle := rng.randf() * TAU
		var distance := pow(rng.randf(), 0.72)
		var p := Vector2(cos(angle) * distance * 0.53, sin(angle) * distance * 0.11).rotated(-0.32)
		galaxy_stars.append({"p": p, "a": (1.0 - distance) * rng.randf_range(0.05, 0.26), "r": rng.randf_range(0.35, 0.9)})
	for index in range(85):
		var angle := rng.randf() * TAU
		var r := pow(rng.randf(), 1.7)
		target_stars.append({"p": Vector2.from_angle(angle) * r, "a": rng.randf_range(0.35, 0.95)})

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("050A12"))
	for star in stars:
		draw_circle(star.p * size, star.r, Color(0.65, 0.77, 0.9, star.a))
	for star in galaxy_stars:
		draw_circle(size * (Vector2(0.52, 0.52) + star.p), star.r, Color(0.70, 0.72, 0.80, star.a))
	if stage == null:
		return
	for index in range(stage.targets.size()):
		var target: Dictionary = stage.targets[index]
		var p: Vector2 = target.position * size
		var alpha := 0.32 if target.cooldown > 0.0 else 1.0
		var tone := Color("B8DCFF") if target.kind == "stars" else Color("F0D8A9")
		if target.kind == "cluster":
			for star in target_stars:
				draw_circle(p + star.p * 32.0, 0.75, Color(tone, star.a * alpha))
			for layer in range(6, 0, -1):
				draw_circle(p, float(layer) * 2.0, Color(tone, alpha * 0.027))
		else:
			var core_radius := 2.2 if target.kind == "stars" else 1.8
			for layer in range(5, 0, -1):
				draw_circle(p, core_radius * float(layer), Color(tone, alpha * 0.033))
			draw_circle(p, core_radius, Color(tone, alpha))
			if target.kind == "cloud":
				for star in target_stars.slice(0, 28):
					draw_circle(p + star.p * Vector2(25, 16), 0.65, Color("8DB5DD", star.a * 0.55 * alpha))
		if target.progress > 0.0 and target.cooldown <= 0.0:
			var r := 40.0 if target.kind == "cluster" else 15.0
			draw_arc(p, r, -PI * 0.5, -PI * 0.5 + TAU * target.progress, 48, Color("F4D4B5", 0.75), 1.0, true)
		if index in stage.tracked_indices:
			draw_arc(p, 8.0 if target.kind != "cluster" else 36.0, 0, TAU, 32, Color("F8F5EE", 0.23), 0.8, true)
	var names := [[Vector2(0.26, 0.61), "ANDROMEDA_STARS"], [Vector2(0.73, 0.64), "ANDROMEDA_CLUSTER"], [Vector2(0.51, 0.84), "ANDROMEDA_CLOUD"]]
	for entry in names:
		var label := tr(entry[1])
		var font: Font = UITheme.sans()
		var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		draw_string(font, entry[0] * size - Vector2(text_size.x * 0.5, 0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("AAB9C9", 0.78))
	if not stage.modules_open and not stage.settings_open():
		var p: Vector2 = stage.cursor
		var r: float = stage.tracking_radius()
		var color := Color("FFB48E") if stage.tracked_indices.is_empty() else Color("F8F5EE")
		draw_arc(p, r, 0, TAU, 64, Color(color, 0.40), 1.0, true)
		for v in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			draw_line(p + v * (r + 2), p + v * (r + 6), Color(color, 0.6), 1.0, true)
		if stage.tracked_indices.is_empty():
			draw_circle(p, 1.3, Color(color, 0.9))
