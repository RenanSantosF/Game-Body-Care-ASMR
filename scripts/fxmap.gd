class_name FxMap
extends RefCounted
## Mapa de efeitos pintado ao vivo em um remendo/cúpula (UV -1..1):
##   A = profundidade do corte (onde a lâmina passou), G = sangue acumulado.
## O sangue "brota" ao longo do corte e escorre morro abaixo.

const SIZE := 192

var img: Image
var tex: ImageTexture
var wmask: Image                # onde o algodão já limpou o sangue (pintado nativo, rápido)
var wtex: ImageTexture
var wdirty := false
var dirty := false
var _t := 0.0
var cut_pts: Array = []      # pontos do corte em pixels (para sangrar)
var drips: Array = []        # [pos_px, dir_px, vida]
var bleed := 0.0             # intensidade do sangramento
var down := Vector2(0, 1)    # direção "morro abaixo" em pixels
var slope := 0.0             # 0 = pele plana (sangue empoça), 1 = bem inclinada (escorre)
var _last := Vector2(-999, -999)
var wiped := 0.0             # algodão pressionando estanca o sangue

func _init() -> void:
	img = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	tex = ImageTexture.create_from_image(img)
	wmask = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	wmask.fill(Color(0, 0, 0, 1))
	wtex = ImageTexture.create_from_image(wmask)

static func to_px(uv: Vector2) -> Vector2:
	return (uv * 0.5 + Vector2(0.5, 0.5)) * SIZE

func _stamp(c: Vector2, r: float, ch: int, amount: float, mode := 0) -> void:
	if not c.is_finite() or c.x < -20.0 or c.y < -20.0 or c.x > SIZE + 20 or c.y > SIZE + 20 or r > 64.0:
		return
	var ri := int(ceil(r))
	var cx := int(c.x)
	var cy := int(c.y)
	for y in range(maxi(0, cy - ri), mini(SIZE, cy + ri + 1)):
		for x in range(maxi(0, cx - ri), mini(SIZE, cx + ri + 1)):
			var d := Vector2(x - c.x, y - c.y).length() / maxf(r, 0.5)
			if d > 1.0:
				continue
			var k := 1.0 - d * d
			var col := img.get_pixel(x, y)
			var v: float = col[ch]
			match mode:
				0: v = maxf(v, k * amount)          # corte
				1: v = minf(1.0, v + k * amount)    # sangue
				2: v = maxf(0.0, v - k * amount)    # limpar
			col[ch] = v
			img.set_pixel(x, y, col)
			# sangue novo aparece mesmo onde já foi limpo
			if mode == 1 and k > 0.3:
				wmask.set_pixel(x, y, Color(0, 0, 0, 1))
				wdirty = true
	dirty = true

## Traço da lâmina do último ponto até uv. Retorna os pixels percorridos.
func cut_to(uv: Vector2, width_px := 2.6, depth := 1.0) -> void:
	var p := to_px(uv)
	if _last.x < -100.0 or _last.distance_to(p) > 40.0:
		_last = p
	var dist := _last.distance_to(p)
	var steps := maxi(1, int(dist))
	for i in steps + 1:
		var q := _last.lerp(p, float(i) / steps)
		_stamp(q, width_px, 3, depth, 0)
		if cut_pts.size() < 400 and (cut_pts.is_empty() or cut_pts[cut_pts.size() - 1].distance_to(q) > 2.0):
			cut_pts.append(q)
	_last = p
	bleed = minf(1.0, bleed + 0.02 * steps)

func end_stroke() -> void:
	_last = Vector2(-999, -999)

func cut_at(uv: Vector2) -> float:
	var p := to_px(uv)
	var x := clampi(int(p.x), 0, SIZE - 1)
	var y := clampi(int(p.y), 0, SIZE - 1)
	return img.get_pixel(x, y).a

## Maior profundidade de corte perto do ponto (tolerância de alguns pixels)
func cut_near(uv: Vector2, r := 4) -> float:
	var p := to_px(uv)
	var best := 0.0
	for y in range(int(p.y) - r, int(p.y) + r + 1):
		for x in range(int(p.x) - r, int(p.x) + r + 1):
			if x >= 0 and y >= 0 and x < SIZE and y < SIZE:
				best = maxf(best, img.get_pixel(x, y).a)
	return best

func blood_at(uv: Vector2) -> float:
	var p := to_px(uv)
	return img.get_pixel(clampi(int(p.x), 0, SIZE - 1), clampi(int(p.y), 0, SIZE - 1)).g

func add_blood(uv: Vector2, r_px: float, amount: float) -> void:
	_stamp(to_px(uv), r_px, 1, amount, 1)

func wipe(uv: Vector2, r_px: float, amount: float) -> void:
	var px := clampi(int(r_px) * 2 + 1, 5, SIZE)
	var b := CleanMask.brush(px, clampf(amount * 1.4, 0.05, 1.0))
	var p := to_px(uv) - Vector2(px, px) * 0.5
	wmask.blend_rect(b, Rect2i(0, 0, px, px), Vector2i(p))
	wdirty = true
	wiped = 1.0
	bleed *= 0.95

func blood_total() -> float:
	var s := 0.0
	for j in 32:
		for i in 32:
			var x := int((i + 0.5) / 32.0 * SIZE)
			var y := int((j + 0.5) / 32.0 * SIZE)
			s += img.get_pixel(x, y).g * (1.0 - wmask.get_pixel(x, y).r)
	return s / 1024.0

## Sangue brota em gotinhas ao longo do corte e às vezes escorre
func step(dt: float) -> void:
	_t += dt
	if bleed > 0.01 and not cut_pts.is_empty():
		for i in 3:
			# gotinhas brotando ao longo do corte (bolinhas que crescem e se juntam)
			var q: Vector2 = cut_pts[randi() % cut_pts.size()]
			_stamp(q + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)), randf_range(1.6, 3.4), 1, 0.16 * bleed, 1)
		# em pele plana o sangue empoça em volta do corte em vez de escorrer
		if slope < 0.25 and randf() < dt * 2.0 * bleed:
			var q3: Vector2 = cut_pts[randi() % cut_pts.size()]
			_stamp(q3, randf_range(4.0, 7.0), 1, 0.08 * bleed, 1)
		if slope >= 0.25 and randf() < dt * 1.6 * bleed * slope and drips.size() < 4:
			var q2: Vector2 = cut_pts[randi() % cut_pts.size()]
			drips.append([q2, (down + Vector2(randf_range(-0.4, 0.4), randf_range(-0.4, 0.4))).normalized(), randf_range(6.0, 16.0)])
		wiped = maxf(0.0, wiped - dt)
		bleed = maxf(0.0 if wiped > 0.0 else 0.15, bleed - dt * (0.4 if wiped > 0.0 else 0.03))
	for d in drips:
		# escorre devagar, serpenteando, e termina numa gota
		var nd: Vector2 = d[1] + Vector2(randf_range(-0.25, 0.25), randf_range(-0.25, 0.25))
		d[1] = nd.normalized() if nd.length() > 0.01 else Vector2(0, 1)
		var mv: Vector2 = d[1] * dt * 7.0
		d[0] = d[0] + mv
		d[2] -= mv.length()
		_stamp(d[0], 1.8 + randf() * 0.6, 1, 0.3, 1)
		if d[2] <= 0.0:
			_stamp(d[0], 3.2, 1, 0.6, 1)
	drips = drips.filter(func(d): return d[2] > 0.0 and d[0].x > 0 and d[0].y > 0 and d[0].x < SIZE and d[0].y < SIZE)
	if (dirty or wdirty) and _t > 0.04:
		_t = 0.0
		if dirty:
			dirty = false
			tex.update(img)
		if wdirty:
			wdirty = false
			wtex.update(wmask)

func flush() -> void:
	if dirty:
		dirty = false
		tex.update(img)
	if wdirty:
		wdirty = false
		wtex.update(wmask)
