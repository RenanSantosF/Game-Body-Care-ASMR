class_name PusString
extends MeshInstance3D
## Fio contínuo de pus saindo do poro enquanto espreme (tipo pasta de dente):
## sobe um pouco, faz a curva e deita enrolando sobre a pele. Ao soltar, desaba e vira mancha.

const MAX_LEN := 0.2
const STEP := 0.006

var body: Body
var origin: Vector3
var up: Vector3
var side: Vector3
var radius := 0.006
var length := 0.0
var color := Color(0.95, 0.8, 0.32)
var detached := false
var _curl := 0.0
var _seed := 0.0

func setup(b: Body, pos: Vector3, normal: Vector3, col: Color, r: float) -> void:
	body = b
	origin = pos
	up = normal.normalized()
	var t := up.cross(Vector3(0, 0, 1))
	if t.length() < 0.1:
		t = up.cross(Vector3(1, 0, 0))
	side = t.normalized().rotated(up, randf() * TAU)
	color = col
	radius = r
	_curl = (1.0 if randf() < 0.5 else -1.0) * randf_range(22.0, 34.0)
	_seed = randf() * 10.0
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.3
	m.metallic_specular = 0.9
	m.rim_enabled = true
	m.rim = 0.3
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func full() -> bool:
	return length >= MAX_LEN

## Ponto do caminho no comprimento s: sobe, curva e deita na pele girando (enrola)
func _point(s: float) -> Vector3:
	var rise := 0.018 * (1.0 - exp(-s / 0.012))
	var flat := maxf(0.0, s - 0.01)
	# caminho no plano com curvatura crescente: espiral que vai se enrolando
	var p := origin + up * rise
	var n := int(flat / 0.004)
	var acc := Vector3.ZERO
	var ang := 0.0
	for i in n:
		ang += 0.004 * _curl * (1.0 + i * 0.04)
		acc += side.rotated(up, ang) * 0.004
	p += acc + side.rotated(up, ang) * (flat - n * 0.004)
	# cai sobre a pele conforme vai deitando
	var settle := smoothstep(0.02, 0.06, s)
	p -= up * (rise - radius * 0.8) * settle
	# cada volta da espiral empilha por cima da anterior (montinho)
	p += up * radius * 1.8 * absf(ang) / TAU
	if body:
		var sp := body.surface(p.x, p.z)
		if not sp.is_empty() and settle > 0.5:
			p.y = maxf(p.y, sp[0].y + radius * 0.7)
	return p

func grow(amt: float) -> void:
	if detached:
		return
	length = minf(MAX_LEN, length + amt)
	_rebuild()

func _rebuild() -> void:
	var n := maxi(2, int(length / STEP) + 2)
	var pts := PackedVector3Array()
	var rr := PackedFloat32Array()
	for i in n:
		var s := length * float(i) / (n - 1)
		pts.append(to_local(_point(s)))
		var tip := 1.0 - smoothstep(0.75, 1.0, float(i) / (n - 1)) * 0.55
		var wob := 1.0 + 0.18 * sin(s * 260.0 + _seed)
		rr.append(radius * tip * wob * (1.15 if i < 2 else 1.0))
	mesh = MeshGen.tube(pts, rr, 8, true)

## Solta: o fio desaba, vira mancha (que dá para limpar) e some
func detach() -> void:
	if detached:
		return
	detached = true
	if length < 0.008:
		queue_free()
		return
	if body:
		var mid := _point(length * 0.6)
		body.add_stain(mid, 2, clampf(length * 0.35, 0.015, 0.05))
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(1.08, 0.35, 1.08), 0.5).set_trans(Tween.TRANS_QUAD)
	tw.tween_interval(1.2)
	tw.tween_property(material_override, "albedo_color:a", 0.0, 0.8)
	tw.tween_callback(queue_free)
	(material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
