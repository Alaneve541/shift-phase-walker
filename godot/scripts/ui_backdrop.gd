extends Control

const CANVAS := Vector2(960.0, 640.0)
const STATION: Texture2D = preload("res://assets/ui/meowa-station.png")
const INK := Color("0b151d")

var mode: String = "title":
	set(value):
		mode = value
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	resized.connect(queue_redraw)


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	draw_set_transform(Vector2.ZERO, 0.0, size / CANVAS)
	if mode in ["title", "chapters", "sample_chapters"]:
		draw_texture_rect_region(STATION, Rect2(Vector2.ZERO, CANVAS), Rect2(28, 104, 1992, 1328))
		if mode == "title":
			draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(600, 0), Vector2(600, 640), Vector2(0, 640)]),
				PackedColorArray([Color(INK, 0.65), Color(INK, 0.0), Color(INK, 0.0), Color(INK, 0.65)]))
			draw_polygon(PackedVector2Array([Vector2(0, 510), Vector2(960, 510), Vector2(960, 605), Vector2(0, 605)]),
				PackedColorArray([Color(INK, 0.0), Color(INK, 0.0), INK, INK]))
			draw_rect(Rect2(0, 605, 960, 35), INK)
			draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(960, 0), Vector2(960, 95), Vector2(0, 95)]),
				PackedColorArray([Color(INK, 0.7), Color(INK, 0.7), Color(INK, 0.0), Color(INK, 0.0)]))
		else:
			draw_rect(Rect2(Vector2.ZERO, CANVAS), Color(INK, 0.80))
	else:
		draw_rect(Rect2(Vector2.ZERO, CANVAS), Color(0.025, 0.055, 0.075, 0.77))
	draw_set_transform(Vector2.ZERO)
