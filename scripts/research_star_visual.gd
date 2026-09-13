extends Control

# Presentation-only research marker; chart state and purchases stay with UpgradeTree.
const UITheme = preload("res://scripts/ui_theme.gd")
const GALACTIC_NODE_SCREEN_SCALE := 0.72
const CLUSTER_MARKER_OFFSETS := [
	Vector2(-1.45, -0.42),
	Vector2(-0.62, 0.88),
	Vector2(0.20, -1.08),
	Vector2(0.92, -0.22),
	Vector2(1.35, 0.72),
	Vector2(0.28, 1.36),
]
const PURCHASED_GLOW_SCALE := 2.35
const PURCHASED_ENDPOINT_GLOW_SCALE := 2.75
const BRANCH_MIX_INSTALLED := 0.06
const BRANCH_MIX_READY := 0.28
const BRANCH_MIX_SHORT := 0.12

var hold_ratio: float = 0.0
var branch_color := UITheme.STAR_LOCKED
var visual_state := "hidden"
var magnitude: float = 3.0
var star_kind := "star"
var affordable := false
var hovered := false
var pulse_phase := 0.0
var branch_endpoint := false


func set_fill_progress(ratio: float, elapsed: float) -> void:
	hold_ratio = clampf(ratio, 0.0, 1.0)
	pulse_phase = elapsed * 8.0
	queue_redraw()


func clear_fill() -> void:
	hold_ratio = 0.0
	queue_redraw()


func configure(state: String, color: Color, apparent_magnitude: float, kind: String, can_afford: bool, is_branch_endpoint: bool) -> void:
	visual_state = state
	branch_color = color
	magnitude = apparent_magnitude
	star_kind = kind
	affordable = can_afford
	branch_endpoint = is_branch_endpoint
	set_process(visual_state == "available" and affordable)
	queue_redraw()


func set_hovered(value: bool) -> void:
	hovered = value
	queue_redraw()


func visual_radius() -> float:
	return clampf(7.4 - magnitude * 0.82, 3.4, 7.4)


func purchased_glow_scale() -> float:
	return PURCHASED_ENDPOINT_GLOW_SCALE if branch_endpoint else PURCHASED_GLOW_SCALE


func state_ink(base: Color) -> Color:
	# Hue adds branch identity; the original warm ink, alpha and geometry
	# still carry state. Locked/hidden research must not leak branch hue.
	var weight := 0.0
	if visual_state == "purchased":
		weight = BRANCH_MIX_INSTALLED
	elif visual_state == "available":
		weight = BRANCH_MIX_READY if affordable else BRANCH_MIX_SHORT
	if weight == 0.0:
		return base
	return base.lerp(Color(branch_color, base.a), weight)


func _draw_cluster_marker(center: Vector2, radius: float) -> void:
	# A small asymmetric point group identifies a real cluster without
	# borrowing the circular state language used by research nodes.
	for index in range(CLUSTER_MARKER_OFFSETS.size()):
		var point_radius := maxf(0.72, radius * (0.28 if index % 2 == 0 else 0.20))
		draw_circle(
			center + CLUSTER_MARKER_OFFSETS[index] * radius * 0.72,
			point_radius,
			state_ink(Color(UITheme.STAR_BACKGROUND, 0.30))
		)


func _process(delta: float) -> void:
	pulse_phase = fmod(pulse_phase + delta * 3.2, TAU)
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var radius := visual_radius()
	var pulse := 1.0 + (sin(pulse_phase) * 0.12 if visual_state == "available" and affordable else 0.0)
	# M31 retains its catalogue identity but uses the same compact research
	# marker and interaction rings as neighboring nodes.
	if star_kind == "cluster" and visual_state != "hidden":
		_draw_cluster_marker(center, radius)
	match visual_state:
		"purchased":
			draw_circle(center, radius * purchased_glow_scale(), state_ink(Color(UITheme.STAR_INSTALLED_GLOW, 0.22 if hovered else 0.13)))
			draw_circle(center, radius, state_ink(UITheme.STAR_INSTALLED))
		"available":
			if affordable:
				draw_circle(center, radius * 5.2 * pulse, state_ink(Color(UITheme.STAR_READY_RING, 0.50)), false, 1.0, true)
				draw_circle(center, radius, state_ink(UITheme.STAR_READY_FILL))
				draw_circle(center, radius, state_ink(UITheme.STAR_READY_BORDER), false, 1.0, true)
			else:
				draw_circle(center, radius, state_ink(UITheme.STAR_SHORT_BORDER), false, 1.0, true)
		"locked", "teaser":
			draw_circle(center, maxf(1.5, radius * 0.6), state_ink(Color(UITheme.STAR_LOCKED, 0.24)))
		_:
			draw_circle(center, maxf(1.25, radius * 0.5), state_ink(Color(UITheme.STAR_BACKGROUND, 0.30)))
	if hovered and visual_state != "hidden":
		draw_circle(center, radius * 2.6, state_ink(Color(UITheme.STAR_READY_RING, 0.28)), false, 1.0, true)
	if hold_ratio > 0.0:
		# The gauge wraps the star so hand and eye watch the same place.
		draw_arc(center, radius + UITheme.px(11.0), 0.0, TAU, 48, Color(UITheme.HORIZON_TICK, 0.40), 1.0, true)
		draw_arc(
			center,
			radius + UITheme.px(11.0),
			-PI * 0.5,
			-PI * 0.5 + TAU * hold_ratio,
			48,
			state_ink(UITheme.STAR_READY_RING),
			UITheme.px(2.6),
			true
		)
