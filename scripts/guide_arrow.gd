class_name GuideArrow
extends Control
## Setinha que mostra o próximo problema: pula em cima dele ou aponta da borda.

var target := Vector2.ZERO
var radius := 30.0
var behind := false
var working := false
var progress := 0.0
var t := 0.0
const MARGIN := 70.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _process(delta: float) -> void:
	t += delta
	queue_redraw()

func _arrow(tip: Vector2, dir: Vector2, s: float, col: Color) -> void:
	var d := dir.normalized()
	var side := Vector2(-d.y, d.x)
	var head := PackedVector2Array([tip, tip - d * 34 * s + side * 26 * s, tip - d * 34 * s - side * 26 * s])
	var stem := PackedVector2Array([
		tip - d * 30 * s + side * 11 * s, tip - d * 72 * s + side * 11 * s,
		tip - d * 72 * s - side * 11 * s, tip - d * 30 * s - side * 11 * s])
	var o := Color(0.17, 0.12, 0.3)
	for poly in [stem, head]:
		var big := PackedVector2Array()
		var c := Vector2.ZERO
		for p in poly:
			c += p
		c /= poly.size()
		for p in poly:
			big.append(c + (p - c) * 1.0 + (p - c).normalized() * 5.0)
		draw_colored_polygon(big, o)
	draw_colored_polygon(stem, col)
	draw_colored_polygon(head, col)

func _draw() -> void:
	var size := get_viewport_rect().size
	var r := Rect2(Vector2(MARGIN, MARGIN + 150), size - Vector2(MARGIN * 2, MARGIN * 2 + 400)).abs()
	if r.size.x < 10.0 or r.size.y < 10.0:
		return
	var col := Color("ffe066")
	var bounce := absf(sin(t * 4.0)) * 18.0
	if working and not behind:
		# anel de progresso da etapa atual
		draw_arc(target, radius + 14, 0, TAU, 48, Color(0, 0, 0, 0.35), 9.0, true)
		draw_arc(target, radius + 14, -PI / 2, -PI / 2 + TAU * clampf(progress, 0.0, 1.0), 48, Color("4cd07d"), 7.0, true)
		return
	if not behind and r.has_point(target):
		var pulse := 0.5 + 0.5 * sin(t * 5.0)
		draw_arc(target, radius + 10 + pulse * 8, 0, TAU, 40, Color(1, 0.9, 0.3, 0.35 + pulse * 0.3), 5.0, true)
		_arrow(target - Vector2(0, radius + 16 + bounce), Vector2(0, 1), 1.0, col)
	else:
		var c := size * 0.5
		var dir := target - c
		if behind:
			dir = -dir
		if dir.length() < 1.0:
			dir = Vector2(0, -1)
		var k := INF
		if absf(dir.x) > 0.001:
			k = minf(k, (r.size.x * 0.5) / absf(dir.x))
		if absf(dir.y) > 0.001:
			k = minf(k, (r.size.y * 0.5) / absf(dir.y))
		var edge := c + dir * k
		_arrow(edge + dir.normalized() * bounce * 0.6, dir, 1.1, col)
