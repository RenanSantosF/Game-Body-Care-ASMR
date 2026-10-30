class_name CleanMask
extends RefCounted
## Máscara de limpeza (branco = limpo). Pintada com pincel macio ao esfregar.

const SIZE := 96

var img: Image
var tex: ImageTexture
var dirty := false
static var _brushes := {}

func _init() -> void:
	img = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 1))
	tex = ImageTexture.create_from_image(img)

static func brush(px: int, strength: float) -> Image:
	var key := "%d_%.2f" % [px, strength]
	if _brushes.has(key):
		return _brushes[key]
	var b := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var c := (px - 1) * 0.5
	for y in px:
		for x in px:
			var d := Vector2(x - c, y - c).length() / maxf(c, 1.0)
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a) * strength
			b.set_pixel(x, y, Color(1, 1, 1, a))
	_brushes[key] = b
	return b

## uv em -1..1, raio em unidades de uv
func paint(uv: Vector2, radius_uv: float, strength := 0.35) -> void:
	var px := clampi(int(radius_uv * SIZE), 4, SIZE)
	px = (px / 2) * 2 + 1
	var b := brush(px, strength)
	var p := (uv * 0.5 + Vector2(0.5, 0.5)) * SIZE - Vector2(px, px) * 0.5
	img.blend_rect(b, Rect2i(0, 0, px, px), Vector2i(p))
	dirty = true

func flush() -> void:
	if dirty:
		dirty = false
		tex.update(img)

## Fração limpa dentro do círculo de raio r (uv)
func coverage(r := 0.8) -> float:
	var tot := 0.0
	var n := 0
	for j in 12:
		for i in 12:
			var u := -1.0 + (i + 0.5) / 6.0
			var v := -1.0 + (j + 0.5) / 6.0
			if u * u + v * v > r * r:
				continue
			var x := clampi(int((u * 0.5 + 0.5) * SIZE), 0, SIZE - 1)
			var y := clampi(int((v * 0.5 + 0.5) * SIZE), 0, SIZE - 1)
			tot += img.get_pixel(x, y).r
			n += 1
	return tot / maxf(1.0, n)

func clear_all() -> void:
	img.fill(Color(1, 1, 1, 1))
	dirty = true
