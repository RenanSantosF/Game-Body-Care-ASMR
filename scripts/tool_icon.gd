class_name ToolIcon
extends Control
## Ícone 2D desenhado por código para cada ferramenta.

var tool_id := "":
	set(v):
		tool_id = v
		queue_redraw()
var locked := false:
	set(v):
		locked = v
		queue_redraw()

const METAL := Color("b9c4d2")
const OUT := Color("37304a")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _l(a: Vector2, b: Vector2, c: Color, w: float) -> void:
	var s := size.x
	draw_line(a * s, b * s, OUT, w * s + 4.0, true)
	draw_line(a * s, b * s, c, w * s, true)

func _c(p: Vector2, r: float, c: Color) -> void:
	var s := size.x
	draw_circle(p * s, r * s + 2.5, OUT)
	draw_circle(p * s, r * s, c)

func _r(p: Vector2, sz: Vector2, c: Color, ang := 0.0) -> void:
	var s := size.x
	draw_set_transform(p * s, ang, Vector2.ONE)
	var rect := Rect2(-sz * s * 0.5, sz * s)
	draw_rect(rect.grow(2.5), OUT)
	draw_rect(rect, c)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw() -> void:
	var s := size.x
	match tool_id:
		"algodao":
			_l(Vector2(0.2, 0.85), Vector2(0.62, 0.38), Color("8fd3ff"), 0.06)
			_c(Vector2(0.68, 0.32), 0.17, Color("fbfbf7"))
			_c(Vector2(0.62, 0.27), 0.06, Color("ffffff"))
		"espremedor":
			_l(Vector2(0.2, 0.85), Vector2(0.6, 0.42), METAL, 0.05)
			_l(Vector2(0.2, 0.85), Vector2(0.36, 0.68), Color("ff7eb6"), 0.1)
			draw_arc(Vector2(0.68, 0.32) * s, 0.13 * s, 0, TAU, 20, OUT, 0.08 * s + 4.0, true)
			draw_arc(Vector2(0.68, 0.32) * s, 0.13 * s, 0, TAU, 20, METAL, 0.07 * s, true)
		"pinca":
			_l(Vector2(0.78, 0.16), Vector2(0.28, 0.78), METAL, 0.06)
			_l(Vector2(0.78, 0.16), Vector2(0.4, 0.86), METAL, 0.06)
			_l(Vector2(0.66, 0.32), Vector2(0.55, 0.47), Color("ffcf4f"), 0.08)
		"escova":
			_r(Vector2(0.62, 0.36), Vector2(0.5, 0.18), Color("4fb3ff"), -0.6)
			_r(Vector2(0.7, 0.47), Vector2(0.46, 0.08), Color("fff6d6"), -0.6)
			_l(Vector2(0.18, 0.86), Vector2(0.48, 0.5), Color("4fb3ff"), 0.08)
		"espatula":
			_l(Vector2(0.2, 0.85), Vector2(0.55, 0.45), Color("7ed957"), 0.09)
			_r(Vector2(0.68, 0.3), Vector2(0.22, 0.3), METAL, 0.7)
		"bisturi":
			_l(Vector2(0.18, 0.84), Vector2(0.58, 0.42), Color("8a96a6"), 0.08)
			var pts := PackedVector2Array([Vector2(0.56, 0.4) * s, Vector2(0.86, 0.14) * s, Vector2(0.7, 0.42) * s])
			draw_colored_polygon(pts, OUT)
			var pts2 := PackedVector2Array([Vector2(0.6, 0.39) * s, Vector2(0.82, 0.19) * s, Vector2(0.69, 0.38) * s])
			draw_colored_polygon(pts2, Color("eef6ff"))
		"lamina":
			_l(Vector2(0.5, 0.9), Vector2(0.5, 0.4), Color("9b7bff"), 0.08)
			_r(Vector2(0.5, 0.3), Vector2(0.62, 0.16), Color("9b7bff"))
			_r(Vector2(0.5, 0.2), Vector2(0.6, 0.05), METAL)
		"pente":
			_r(Vector2(0.5, 0.36), Vector2(0.75, 0.14), Color("ff8f4f"))
			for i in 8:
				var x := 0.18 + i * 0.09
				_l(Vector2(x, 0.43), Vector2(x, 0.7), Color("ff8f4f"), 0.035)
		"spray":
			_r(Vector2(0.42, 0.6), Vector2(0.34, 0.5), Color("8fd3ff"))
			_r(Vector2(0.42, 0.3), Vector2(0.2, 0.1), Color.WHITE)
			for i in 5:
				_c(Vector2(0.62 + i * 0.06, 0.24 - (i % 2) * 0.06), 0.03, Color(0.8, 0.93, 1.0))
		"curativo":
			_r(Vector2(0.5, 0.5), Vector2(0.8, 0.3), Problem.BAND, -0.7)
			_r(Vector2(0.5, 0.5), Vector2(0.26, 0.26), Color("fbf3e6"), -0.7)
	if locked:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.08, 0.15, 0.55))
		_r(Vector2(0.5, 0.6), Vector2(0.36, 0.28), Color("ffcf4f"))
		draw_arc(Vector2(0.5, 0.44) * s, 0.12 * s, PI, TAU, 12, OUT, 0.06 * s, true)
