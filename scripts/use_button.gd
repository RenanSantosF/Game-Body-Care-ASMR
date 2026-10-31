class_name UseButton
extends Control
## Botão de SEGURAR para usar a ferramenta (a mão de apoio segura; o outro dedo mira).
## Os toques são tratados pelo jogo (multitoque); aqui é só o desenho.

var center := Vector2(110, 900)
var radius := 78.0
var held := false
var tool_id := ""
var ready_glow := false          # a ferramenta está mirando um problema certo
var t := 0.0
var _press_k := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func hit(p: Vector2) -> bool:
	return p.distance_to(center) < radius * 1.25

func _process(delta: float) -> void:
	t += delta
	_press_k = move_toward(_press_k, 1.0 if held else 0.0, delta * 10.0)
	queue_redraw()

func _draw() -> void:
	var r := radius * (1.0 - _press_k * 0.07)
	var base := Color("4cd07d") if tool_id != "" else Color("9a96b0")
	if ready_glow and not held:
		var pul := 0.5 + 0.5 * sin(t * 6.0)
		draw_circle(center, r + 10 + pul * 8, Color(base, 0.25 + pul * 0.2))
	draw_circle(center + Vector2(0, 6), r, Color(0.08, 0.05, 0.16, 0.45))
	draw_circle(center, r, base.darkened(0.25 if held else 0.0))
	draw_circle(center + Vector2(0, -r * 0.12), r * 0.82, base.lightened(0.18 if not held else 0.0))
	draw_arc(center, r, 0, TAU, 48, Color.WHITE, 5.0, true)
	if tool_id != "":
		var tex: Texture2D = Icons.get_tex(tool_id)
		if tex:
			var s := r * 1.05
			draw_texture_rect(tex, Rect2(center - Vector2(s, s) * 0.5 + Vector2(0, -10), Vector2(s, s)), false)
	var f := get_theme_default_font()
	var label := tr("USANDO") if held else tr("SEGURE")
	var w := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	draw_string_outline(f, center + Vector2(-w * 0.5, r * 0.62), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 6, Color(0.1, 0.25, 0.12))
	draw_string(f, center + Vector2(-w * 0.5, r * 0.62), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
