class_name UIKit
extends RefCounted
## Construção rápida de UI colorida e "gordinha" (estilo casual mobile).

const PINK := Color("ff6fae")
const GREEN := Color("4cd07d")
const BLUE := Color("4fb3ff")
const YELLOW := Color("ffc43d")
const PURPLE := Color("9b7bff")
const RED := Color("ff5a5a")
const DARK := Color("2d2442")
const CREAM := Color("fff8ee")

static func style(color: Color, radius := 22, border := 0, border_color := Color.TRANSPARENT, bottom := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(border)
	sb.border_color = border_color
	if bottom > 0:
		sb.border_width_bottom = bottom
		if border == 0:
			sb.border_color = color.darkened(0.35)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	sb.anti_aliasing = true
	return sb

static var _title_font: Font

static func title_font() -> Font:
	if _title_font == null:
		_title_font = load("res://assets/fonts/LilitaOne-Regular.ttf")
	return _title_font

static func btn(text: String, color := PINK, font := 30, min_size := Vector2(220, 78)) -> Button:
	var b := Button.new()
	b.add_theme_font_override("font", title_font())
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font)
	b.add_theme_stylebox_override("normal", style(color, 24, 0, Color.TRANSPARENT, 7))
	b.add_theme_stylebox_override("hover", style(color.lightened(0.08), 24, 0, Color.TRANSPARENT, 7))
	var pr := style(color.darkened(0.08), 24, 0, Color.TRANSPARENT, 2)
	pr.content_margin_top = 13
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_stylebox_override("disabled", style(color.lerp(Color("8a8a99"), 0.7), 24, 0, Color.TRANSPARENT, 7))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.7))
	b.add_theme_color_override("font_outline_color", color.darkened(0.55))
	b.add_theme_constant_override("outline_size", 8)
	b.pressed.connect(func(): Sfx.play("click"))
	return b

static func label(text: String, size := 30, color := Color.WHITE, outline := 8, outline_color := DARK) -> Label:
	var l := Label.new()
	l.text = text
	if size >= 36:
		l.add_theme_font_override("font", title_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", outline_color)
	l.add_theme_constant_override("outline_size", outline)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func panel(color := CREAM, radius := 30, border := 6, border_color := DARK) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := style(color, radius, border, border_color)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	sb.shadow_color = Color(0, 0, 0, 0.25)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 6)
	p.add_theme_stylebox_override("panel", sb)
	return p

## Fundo escurecido que bloqueia toques + painel central
static func modal(parent: Node, color := CREAM) -> Array:
	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.05, 0.15, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var p := panel(color)
	center.add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(vb)
	p.pivot_offset = Vector2(300, 200)
	p.scale = Vector2(0.7, 0.7)
	p.modulate.a = 0.0
	var tw := p.create_tween().set_parallel()
	tw.tween_property(p, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(p, "modulate:a", 1.0, 0.15)
	p.resized.connect(func(): p.pivot_offset = p.size * 0.5)
	return [dim, vb]

static func hbox(sep := 14) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	return h

static func coin_box() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", style(Color(0.15, 0.1, 0.25, 0.75), 30))
	var h := hbox(8)
	p.add_child(h)
	var ic := CoinIcon.new()
	ic.custom_minimum_size = Vector2(40, 40)
	h.add_child(ic)
	var l := CoinLabel.new()
	l.text = str(GameData.coins)
	l.add_theme_font_size_override("font_size", 30)
	l.add_theme_color_override("font_color", Color("ffe066"))
	l.add_theme_color_override("font_outline_color", DARK)
	l.add_theme_constant_override("outline_size", 6)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.custom_minimum_size.x = 80
	h.add_child(l)
	return p

static func pop_in(c: Control, delay := 0.0) -> void:
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2(0.2, 0.2)
	var tw := c.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(c, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


class CoinIcon extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.45
		draw_circle(c, r + 2, Color("8a5a00"))
		draw_circle(c, r, Color("ffc43d"))
		draw_circle(c, r * 0.7, Color("ffdb6e"))
		draw_rect(Rect2(c - Vector2(r * 0.12, r * 0.4), Vector2(r * 0.24, r * 0.8)), Color("e09a10"))


class StarRow extends Control:
	var filled := 0:
		set(v):
			filled = v
			queue_redraw()
	var total := 3
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var w := size.x / total
		var r := minf(w, size.y) * 0.45
		for i in total:
			var c := Vector2(w * (i + 0.5), size.y * 0.5)
			if total == 3 and i == 1:
				c.y -= size.y * 0.08
			var pts := PackedVector2Array()
			for k in 10:
				var a := -PI / 2 + k * PI / 5
				var rr := r if k % 2 == 0 else r * 0.45
				pts.append(c + Vector2(cos(a), sin(a)) * rr)
			var big := PackedVector2Array()
			for k in 10:
				var a := -PI / 2 + k * PI / 5
				var rr := (r + 4) if k % 2 == 0 else (r + 4) * 0.45
				big.append(c + Vector2(cos(a), sin(a)) * rr)
			draw_colored_polygon(big, Color("5a3a00"))
			draw_colored_polygon(pts, Color("ffc43d") if i < filled else Color("6d6680"))


## Label que acompanha as moedas (desconecta sozinho ao ser liberado)
class CoinLabel extends Label:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		GameData.coins_changed.connect(_on_coins)
	func _on_coins(c: int) -> void:
		text = str(c)
		pivot_offset = size * 0.5
		var tw := create_tween()
		tw.tween_property(self, "scale", Vector2(1.3, 1.3), 0.08)
		tw.tween_property(self, "scale", Vector2.ONE, 0.12)
