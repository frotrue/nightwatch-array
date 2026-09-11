extends RefCounted

# Transient instrument art uses retained native canvas commands, without scene
# children. Flash stays after the marks, preserving the original paint order.
var items: Array[RID] = []
var keys: Array = []
var flash := RID()
var builds := 0
func draw_marker(owner: Node2D, slot: int, p: Vector2, direction: Vector2, scale: float, ink: Color, alpha: float, reach: float) -> void:
	if slot == items.size():
		var item := RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(item, owner.get_canvas_item())
		RenderingServer.canvas_item_set_draw_index(item, slot)
		items.append(item)
		keys.append([])
	var key := [p, direction, scale, ink, reach]
	if keys[slot] != key:
		keys[slot] = key
		RenderingServer.canvas_item_clear(items[slot])
		RenderingServer.canvas_item_add_polyline(items[slot], PackedVector2Array([p-direction*4.0*scale,p+direction*8.0*scale,p+direction*reach*scale]), PackedColorArray([Color(ink,0.28),Color(ink,0.8),Color(ink,0.0)]),1.1*scale,true)
		builds += 1
	RenderingServer.canvas_item_set_modulate(items[slot], Color(1,1,1,alpha))
func finish_markers(count: int) -> void:
	while items.size() > count:
		RenderingServer.free_rid(items.pop_back())
		keys.pop_back()
func clear_flash() -> void:
	if flash.is_valid(): RenderingServer.canvas_item_clear(flash)
func draw_flash(owner: Node2D, rect: Rect2, color: Color) -> void:
	if not flash.is_valid():
		flash = RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(flash, owner.get_canvas_item())
		RenderingServer.canvas_item_set_draw_index(flash, 24)
	RenderingServer.canvas_item_add_rect(flash, rect, color)
func release() -> void:
	finish_markers(0)
	if flash.is_valid(): RenderingServer.free_rid(flash)
	flash = RID()
