extends Control

var history := PackedFloat32Array()

func clear_history() -> void:
	history.clear()
	queue_redraw()

func add_sample(milliseconds: float) -> void:
	history.append(milliseconds)
	if history.size() > 60: history.remove_at(0)
	queue_redraw()

func _draw() -> void:
	# Diagnostic history is procedural; its stable layout belongs to the scene.
	var ceiling := 33.334
	for value in history: ceiling = maxf(ceiling, value)
	var baseline := size.y * (1.0 - 16.667 / ceiling)
	draw_line(Vector2(0, baseline), Vector2(size.x, baseline), Color(0.6, 0.47, 0.4, 0.35))
	if history.size() < 2: return
	var points := PackedVector2Array()
	for index in history.size():
		points.append(Vector2(size.x * (60 - history.size() + index) / 59.0, size.y * (1.0 - history[index] / ceiling)))
	draw_polyline(points, Color(1.0, 0.63, 0.43, 0.9), 1.0, true)
