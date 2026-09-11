extends Button

# Keep the marker on its catalogue coordinate. Resolve overlapping hit boxes
# by distance instead of scene order, and prefer unfinished research when a
# real close pair cannot be separated at the current screen scale.
var chart: Node
var node_id := ""

func _has_point(point: Vector2) -> bool:
	if not Rect2(Vector2.ZERO, size).has_point(point):
		return false
	return chart == null or chart._star_hit_owner(get_global_transform() * point) == node_id
