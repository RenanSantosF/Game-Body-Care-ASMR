class_name PatientFace
extends Control
## Rostinho do paciente desenhado em vetor: reage à dor, chora e fica feliz.

var skin := Color("f2c2a0")
var hair := Color("3a2416")
var pain := 0.0          # 0..100
var relief := 0.0        # segundos de alívio
var hurt_flash := 0.0
var happy := false
var t := 0.0
var tears: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func hurt() -> void:
	hurt_flash = 0.6

func relieve() -> void:
	relief = 1.3

func _process(delta: float) -> void:
	t += delta
	relief = maxf(0.0, relief - delta)
	hurt_flash = maxf(0.0, hurt_flash - delta)
	if _crying():
		if randf() < delta * 5.0:
			tears.append([randf() < 0.5, 0.0])
	for tr in tears:
		tr[1] += delta * 1.4
	tears = tears.filter(func(x): return x[1] < 1.0)
	queue_redraw()

func _crying() -> bool:
	return not happy and relief <= 0.0 and (pain >= 65.0 or hurt_flash > 0.0)

func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size * 0.5 + Vector2(0, s * 0.04)
	var r := s * 0.42
	var shake := Vector2(sin(t * 60.0), 0) * (s * 0.015 if hurt_flash > 0.0 else 0.0)
	c += shake
	# cabelo de trás
	draw_circle(c + Vector2(0, -r * 0.12), r * 1.04, hair)
	# rosto
	var face := skin.lerp(Color("ff8a8a"), clampf(pain / 100.0, 0.0, 1.0) * 0.25)
	draw_circle(c, r, face.darkened(0.15))
	draw_circle(c, r * 0.96, face)
	# franja
	for i in 5:
		var a := -PI * 0.85 + i * PI * 0.17
		draw_circle(c + Vector2(cos(a), sin(a)) * r * 0.78, r * 0.32, hair)
	# bochechas
	var blush := Color(1.0, 0.45, 0.5, 0.35 + (0.25 if happy or relief > 0.0 else 0.0))
	draw_circle(c + Vector2(-r * 0.55, r * 0.25), r * 0.16, blush)
	draw_circle(c + Vector2(r * 0.55, r * 0.25), r * 0.16, blush)
	var mood := 0  # 0 normal, 1 preocupado, 2 dor, 3 chorando, 4 feliz
	if happy or relief > 0.0:
		mood = 4
	elif _crying():
		mood = 3
	elif pain >= 35.0:
		mood = 2
	elif pain >= 12.0:
		mood = 1
	var ink := Color("3a2420")
	for side in [-1.0, 1.0]:
		var e := c + Vector2(side * r * 0.36, -r * 0.02)
		match mood:
			4:
				draw_arc(e + Vector2(0, r * 0.05), r * 0.13, PI * 1.1, PI * 1.9, 10, ink, r * 0.07, true)
			3, 2:
				# olhos apertados ><
				var k := r * 0.12
				draw_line(e + Vector2(-k * side, -k), e + Vector2(k * side, 0), ink, r * 0.07, true)
				draw_line(e + Vector2(k * side, 0), e + Vector2(-k * side, k), ink, r * 0.07, true)
			_:
				draw_circle(e, r * 0.13, Color.WHITE)
				draw_circle(e + Vector2(0, r * 0.02), r * 0.08, ink)
				draw_circle(e + Vector2(r * 0.03, -r * 0.02), r * 0.03, Color.WHITE)
		# sobrancelhas
		var tilt := 0.0
		match mood:
			1: tilt = 0.35
			2, 3: tilt = 0.55
			4: tilt = -0.15
		var b := e + Vector2(0, -r * 0.24)
		var d := Vector2(cos(tilt * side), -sin(tilt * side) * side * side) * r * 0.14
		d = Vector2(r * 0.14, r * 0.14 * tilt * side)
		draw_line(b - d, b + d, hair.darkened(0.3), r * 0.07, true)
	# boca
	var m := c + Vector2(0, r * 0.45)
	match mood:
		4:
			draw_arc(m + Vector2(0, -r * 0.12), r * 0.24, PI * 0.15, PI * 0.85, 14, ink, r * 0.07, true)
		3:
			var open := r * (0.16 + 0.04 * sin(t * 12.0))
			draw_circle(m, open, Color("6a1f25"))
			draw_circle(m + Vector2(0, open * 0.45), open * 0.5, Color("e0606a"))
		2:
			draw_arc(m + Vector2(0, r * 0.12), r * 0.18, PI * 1.2, PI * 1.8, 12, ink, r * 0.07, true)
		1:
			var pts := PackedVector2Array()
			for i in 7:
				var x := -r * 0.18 + i * r * 0.06
				pts.append(m + Vector2(x, sin(i * 2.0) * r * 0.03))
			draw_polyline(pts, ink, r * 0.06, true)
		_:
			draw_line(m + Vector2(-r * 0.12, 0), m + Vector2(r * 0.12, 0), ink, r * 0.07, true)
	# lágrimas
	for tr in tears:
		var side := -1.0 if tr[0] else 1.0
		var start := c + Vector2(side * r * 0.4, r * 0.1)
		var p: Vector2 = start + Vector2(side * r * 0.08 * tr[1], r * 0.9 * tr[1])
		draw_circle(p, r * 0.07, Color(0.55, 0.85, 1.0, 1.0 - tr[1]))
	if mood == 3:
		for side in [-1.0, 1.0]:
			draw_line(c + Vector2(side * r * 0.36, r * 0.08), c + Vector2(side * r * 0.42, r * 0.5), Color(0.55, 0.85, 1.0, 0.8), r * 0.06, true)
	if hurt_flash > 0.0 and not happy:
		draw_circle(c + Vector2(r * 0.85, -r * 0.6), r * 0.12, Color(0.6, 0.85, 1.0, 0.8))
