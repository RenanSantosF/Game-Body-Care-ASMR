class_name TwoFingerCoach
extends Control
## Ensina e mostra os dois dedos: "1" mira (azul), "2" usa (verde).

const VERB := {"pinca": "fechar a pinça", "espremedor": "apertar", "agulha": "furar",
	"spray": "borrifar", "curativo": "colar o curativo", "algodao": "limpar",
	"pano": "limpar", "bisturi": "cortar", "alicate": "cortar", "lamina": "raspar",
	"raspador": "raspar", "lixa": "lixar", "pomada": "passar a pomada"}

var aim := Vector2(-1, -1)
var action := Vector2(-1, -1)
var showing := false
var tool_id := ""
var t := 0.0
var intro_t := 0.0
var alpha := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func show_hint(tool: String) -> void:
	showing = true
	tool_id = tool
	t = 0.0

func hide_hint() -> void:
	showing = false

func intro() -> void:
	intro_t = 4.5

func _process(delta: float) -> void:
	t += delta
	intro_t = maxf(0.0, intro_t - delta)
	alpha = move_toward(alpha, 1.0 if (showing or intro_t > 0.0) else 0.0, delta * 4.0)
	queue_redraw()

func _finger(p: Vector2, label: String, col: Color, r := 34.0) -> void:
	draw_circle(p, r + 5, Color(0.1, 0.07, 0.2, 0.55))
	draw_circle(p, r, Color(col, 0.75))
	draw_arc(p, r, 0, TAU, 32, Color.WHITE, 3.0, true)
	var f := get_theme_default_font()
	draw_string(f, p + Vector2(-9, 11), label, HORIZONTAL_ALIGNMENT_CENTER, -1, 32, Color.WHITE)

func _text(p: Vector2, s: String, size: int, col := Color.WHITE) -> void:
	var f := get_theme_default_font()
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var vw := get_viewport_rect().size.x
	var pos := Vector2(clampf(p.x - w * 0.5, 16, vw - w - 16), p.y)
	draw_string_outline(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 8, Color(0.15, 0.1, 0.25))
	draw_string(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func _draw() -> void:
	var size := get_viewport_rect().size
	# marcadores dos dedos reais
	if aim.x >= 0:
		draw_arc(aim, 26, 0, TAU, 28, Color(0.35, 0.7, 1.0, 0.8), 4.0, true)
	if action.x >= 0:
		draw_arc(action, 40 + sin(t * 10.0) * 4.0, 0, TAU, 32, Color(0.3, 0.9, 0.5, 0.9), 6.0, true)
	if alpha <= 0.01:
		return
	var a := alpha
	var tap := Vector2(size.x * 0.75, size.y * 0.62)
	modulate.a = 1.0
	if intro_t > 0.0 and not showing:
		# mini-tutorial: dedo 1 mira, dedo 2 toca
		var c := Vector2(size.x * 0.33, size.y * 0.5)
		draw_rect(Rect2(Vector2(20, size.y * 0.36), Vector2(size.x - 40, size.y * 0.32)), Color(0.1, 0.06, 0.2, 0.6 * a), true)
		_finger(c + Vector2(sin(t * 2.0) * 20.0, 0), "1", Color("4fb3ff"))
		var pulse := 0.5 + 0.5 * sin(t * 6.0)
		_finger(tap, "2", Color("4cd07d"), 30.0 + pulse * 8.0)
		_text(Vector2(size.x * 0.5, size.y * 0.41), "1º dedo: MIRA a ferramenta", 30, Color("bfe3ff"))
		_text(Vector2(size.x * 0.5, size.y * 0.66), "2º dedo: toque para USAR", 30, Color("c6ffd6"))
		return
	if showing:
		var pulse2 := 0.5 + 0.5 * sin(t * 7.0)
		draw_arc(tap, 60 + pulse2 * 18.0, 0, TAU, 40, Color(0.3, 0.95, 0.5, 0.5 * a), 8.0, true)
		_finger(tap, "2", Color("4cd07d"), 36.0 + pulse2 * 6.0)
		if aim.x >= 0:
			# setinha do dedo 1 até onde tocar com o 2
			var d := (tap - aim).normalized()
			draw_line(aim + d * 40.0, tap - d * 50.0, Color(1, 1, 1, 0.6 * a), 4.0, true)
		_text(Vector2(tap.x, tap.y - 90), "TOQUE AQUI COM OUTRO DEDO", 28, Color("fff3b0"))
		_text(Vector2(tap.x, tap.y + 90), "para %s (sem soltar o 1º)" % VERB.get(tool_id, "usar"), 24)
