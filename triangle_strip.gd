extends Control
## Original vector artwork, drawn directly by Godot.
const COLORS: Array[Color] = [Color("e9b949"), Color("4d9de0"), Color("e85d75")]
var order: Array[int] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func set_order(value: Array) -> void:
	order.assign(value)
	queue_redraw()


func _draw() -> void:
	if order.is_empty():
		return
	var cell := size.x / order.size()
	var width := minf(cell * 0.76, size.y * 0.93)
	var height := width * 0.87
	for index in range(order.size()):
		var center := Vector2(cell * (index + 0.5), size.y * 0.5)
		var points := PackedVector2Array([
			center + Vector2(0, -height * 0.5),
			center + Vector2(width * 0.5, height * 0.5),
			center + Vector2(-width * 0.5, height * 0.5)
		])
		draw_colored_polygon(points, COLORS[order[index]])
		var outline := points.duplicate()
		outline.append(points[0])
		draw_polyline(outline, COLORS[order[index]].lightened(0.22), 1.5, true)
