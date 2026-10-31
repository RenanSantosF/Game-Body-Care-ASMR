class_name BeforeAfter
extends Control
## Comparação antes/depois com divisória arrastável (estilo slider).

var before: Texture2D
var after: Texture2D
var split := 0.5
var dragging := false
var show_labels := true
var _font: Font

func _init(b: Image = null, a: Image = null) -> void:
	if b:
		before = ImageTexture.create_from_image(b)
	if a:
		after = ImageTexture.create_from_image(a)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true

func _ready() -> void:
	_font = get_theme_default_font()

## Varre a divisória uma vez para mostrar a diferença
func intro() -> void:
	split = 0.95
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "split", 0.08, 1.1).set_delay(0.3)
	tw.tween_property(self, "split", 0.5, 0.7)

func _process(_d: float) -> void:
	queue_redraw()

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton or e is InputEventScreenTouch:
		dragging = e.pressed
	var press: bool = (e is InputEventMouseButton or e is InputEventScreenTouch) and e.pressed
	if press or ((e is InputEventMouseMotion or e is InputEventScreenDrag) and dragging):
		split = clampf(e.position.x / maxf(size.x, 1.0), 0.0, 1.0)
		accept_event()

## Recorte "cover": parte central da imagem que preenche o retângulo
func _src(tex: Texture2D) -> Rect2:
	var ts := tex.get_size()
	var k := maxf(size.x / ts.x, size.y / ts.y)
	var w := size.x / k
	var h := size.y / k
	return Rect2((ts.x - w) * 0.5, (ts.y - h) * 0.45, w, h)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.15, 0.1, 0.2))
	var x := size.x * split
	if after:
		var s := _src(after)
		var fx := x / size.x
		draw_texture_rect_region(after, Rect2(x, 0, size.x - x, size.y), Rect2(s.position.x + s.size.x * fx, s.position.y, s.size.x * (1.0 - fx), s.size.y))
	if before:
		var s2 := _src(before)
		var fx2 := x / size.x
		draw_texture_rect_region(before, Rect2(0, 0, x, size.y), Rect2(s2.position, Vector2(s2.size.x * fx2, s2.size.y)))
	# divisória com alça
	draw_rect(Rect2(x - 3, 0, 6, size.y), Color.WHITE)
	var c := Vector2(x, size.y * 0.5)
	draw_circle(c, 26, Color.WHITE)
	draw_circle(c, 22, Color("8e5ac8"))
	for sgn in [-1.0, 1.0]:
		var p := c + Vector2(sgn * 9, 0)
		draw_colored_polygon(PackedVector2Array([p + Vector2(sgn * 7, 0), p + Vector2(0, -7), p + Vector2(0, 7)]), Color.WHITE)
	if show_labels and _font:
		_tag("ANTES", Vector2(14, 16), Color("e8505b"), split > 0.2)
		_tag("DEPOIS", Vector2(size.x - 14, 16), Color("3fbf7f"), split < 0.8, true)

func _tag(t: String, at: Vector2, col: Color, vis: bool, right := false) -> void:
	if not vis:
		return
	var fs := 26
	var w := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 24
	var r := Rect2(at - Vector2(w if right else 0.0, 0), Vector2(w, 40))
	draw_style_box(UIKit.style(col, 14, 0), r)
	draw_string(_font, r.position + Vector2(12, 29), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
