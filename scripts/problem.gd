class_name Problem
extends Node3D
## Um problema na pele/unha: monta o visual suave e anima cada etapa do tratamento.

signal stage_done(p: Problem, finished: bool)
signal popped(p: Problem, color: Color)

const LESION := "res://shaders/lesion.gdshader"
const DOME := "res://shaders/dome.gdshader"
const TUBE := "res://shaders/tube.gdshader"

# tipos do lesion.gdshader
const L_INFLAM := 0
const L_DIRT := 1
const L_PUS := 2
const L_BLOOD := 3
const L_FAVO := 4
const L_WOUND := 5
const L_CALLUS := 6
const L_CRUST := 7
const L_BRUISE := 8
const L_CUT := 9
const L_TRACK := 10
const L_FLUID := 11
const L_OILY := 12
# tipos do dome.gdshader
const D_PUSTULE := 0
const D_BLISTER := 1
const D_BOIL := 2
const D_WART := 3
const D_BUMP := 4
# tipos do tube.gdshader
const T_WORM := 0
const T_LARVA := 1
const T_PUS := 2
const T_DARK := 3
const T_WOOD := 4
const T_SKIN := 5
const T_HAIR := 6

const PUS_C := Color(0.98, 0.84, 0.35)
const BLOOD_C := Color(0.6, 0.04, 0.06)
const BAND := Color("e8c39a")

var id := ""
var def := {}
var stage := 0
var progress := 0.0
var size := 0.1
var done := false
var body: Body
var skin := Color.WHITE
var speed := 1.0
var rng := RandomNumberGenerator.new()
var t := 0.0
var flat: Node3D                  # filho sem rotação (para remendos em coordenadas do mundo)
var n := {}                       # nós nomeados
var items: Array = []
var items_left := 0
var nail := {}                    # dados da unha (problemas de unha)
var cut_path := PackedVector3Array()
var cut_t := 0.0
var guide: Node3D
var pull_dir := Vector3(1, 0, 0)
var _pus_len := 0.0
var _hairs: Array = []
var _hair_mi: MeshInstance3D
var _hair_dirty := false
var _worm_pts := PackedVector3Array()
var _anim := {}

static var _tube_mats := {}

func setup(p_id: String, p_body: Body, p_rng: RandomNumberGenerator, extra := {}) -> void:
	id = p_id
	def = Defs.PROBLEMS[id]
	size = def["size"]
	body = p_body
	skin = body.skin_mat.get_shader_parameter("skin")
	rng.seed = p_rng.randi()
	flat = Node3D.new()
	add_child(flat)
	flat.global_basis = Basis()
	if extra.has("nail"):
		nail = extra["nail"]
	call("_build_" + id)

func pname() -> String:
	return def["name"]

func tool() -> String:
	return "" if done else def["stages"][stage][0]

func mech() -> int:
	return -1 if done else def["stages"][stage][1]

func amount() -> float:
	return def["stages"][stage][2]

func focus_radius() -> float:
	return size * 1.6

## Centro (mundo) usado para acertar o toque e enquadrar a câmera
func center() -> Vector3:
	if n.has("center"):
		return n["center"].global_position
	return global_position

# =================================================================== entrada

func hold(dt: float) -> void:
	_add(dt)

func pull(px: float) -> void:
	_add(px)

func tap() -> void:
	if mech() == Defs.Mech.TAP:
		_add(amount())

## Esfregar: limpa a máscara sob o pincel (ou acumula distância)
func rub(wpos: Vector3, px: float, brush_r: float) -> void:
	if done:
		return
	var a := amount()
	var target := _rub_target()
	if a <= 1.0 and target != null:
		var cov := _paint(target, wpos, brush_r, 0.3 * speed)
		progress = clampf(cov / a, 0.0, 1.0)
		if progress >= 0.9:
			progress = 1.0
		_visual()
		if progress >= 1.0:
			_complete_stage()
	else:
		_add(px)

func set_cut(f: float) -> void:
	if mech() != Defs.Mech.CUT:
		return
	progress = clampf(f, 0.0, 1.0)
	_visual()
	if progress >= 1.0:
		_complete_stage()

func sweep(screen_pos: Vector2, radius_px: float, cam: Camera3D) -> int:
	var c := 0
	for it in items:
		if it["alive"]:
			var sp := cam.unproject_position(it["pos"])
			if sp.distance_to(screen_pos) < radius_px:
				_remove_item(it)
				c += 1
	if c > 0:
		_after_items()
	return c

func pick(screen_pos: Vector2, radius_px: float, cam: Camera3D) -> bool:
	var best = null
	var bd := radius_px
	for it in items:
		if it["alive"]:
			var d := cam.unproject_position(it["pos"]).distance_to(screen_pos)
			if d < bd:
				bd = d
				best = it
	if best != null:
		_remove_item(best)
		_after_items()
		return true
	return false

func _add(x: float) -> void:
	if done:
		return
	progress += x * speed / amount()
	_visual()
	if progress >= 1.0:
		_complete_stage()

func _after_items() -> void:
	progress = 1.0 - float(items_left) / maxf(1.0, items.size())
	_visual()
	if items_left <= 0:
		_complete_stage()

func _complete_stage() -> void:
	progress = 1.0
	_visual()
	_on_stage_end(stage)
	stage += 1
	progress = 0.0
	if stage >= def["stages"].size():
		done = true
		_on_done()
	else:
		_on_stage_start(stage)
		_visual()
	stage_done.emit(self, done)

## Partículas durante o HOLD
func hold_color() -> Color:
	var tl := tool()
	if tl == "spray":
		return Color(0.85, 0.95, 1.0, 0.8)
	if tl == "espremedor" and progress > 0.1:
		if id == "furunculo" and rng.randf() < 0.25:
			return BLOOD_C
		return PUS_C
	return Color(0, 0, 0, 0)

## Ponto onde a ferramenta "segura" (pinça)
func grip_point() -> Vector3:
	if n.has("grip") and is_instance_valid(n["grip"]):
		return n["grip"].global_position
	return center()

## Área ainda suja? (para o bônus de limpar antes)
func dirt_left() -> float:
	if done:
		return 0.0
	if id == "sujeira":
		return 1.0 - progress
	if (id == "larvas" or id == "favo") and stage == 0:
		return 1.0 - progress
	return 0.0

# =================================================================== helpers

func _lesion(kind: int, half: float, off := Vector2.ZERO, use_mask := false, lift := 0.004) -> MeshInstance3D:
	var c := global_position + Vector3(off.x, 0, off.y)
	var sp := body.surface(c.x, c.z)
	if not sp.is_empty():
		c = sp[0]
	var rot := rng.randf() * TAU
	var mi := MeshInstance3D.new()
	mi.mesh = MeshGen.patch(body, c, half, rot, lift)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := MeshGen.shader_mat(LESION)
	mat.set_shader_parameter("kind", kind)
	mat.set_shader_parameter("skin", skin)
	mat.set_shader_parameter("seed", rng.randf() * 50.0)
	if use_mask:
		var mk := CleanMask.new()
		mat.set_shader_parameter("mask", mk.tex)
		mat.set_shader_parameter("use_mask", 1.0)
		mi.set_meta("mask", mk)
	mi.material_override = mat
	flat.add_child(mi)
	mi.global_position = c
	mi.set_meta("c", c)
	mi.set_meta("rot", rot)
	mi.set_meta("half", half)
	return mi

func _paint(mi: MeshInstance3D, wpos: Vector3, brush_r: float, strength: float) -> float:
	if not mi.has_meta("mask"):
		return 0.0
	var mk: CleanMask = mi.get_meta("mask")
	var c: Vector3 = mi.get_meta("c")
	var rot: float = mi.get_meta("rot")
	var half: float = mi.get_meta("half")
	var d := Vector2(wpos.x - c.x, wpos.z - c.z)
	var u := (d.x * cos(rot) + d.y * sin(rot)) / half
	var v := (-d.x * sin(rot) + d.y * cos(rot)) / half
	mk.paint(Vector2(u, v), brush_r / half, strength)
	mk.flush()
	return mk.coverage(0.7)

func _lmat(mi: MeshInstance3D) -> ShaderMaterial:
	return mi.material_override as ShaderMaterial

func _lset(key: String, param: String, value) -> void:
	if n.has(key) and is_instance_valid(n[key]):
		(n[key].material_override as ShaderMaterial).set_shader_parameter(param, value)

func _dome(kind: int, r: float, h: float, pos := Vector3.ZERO) -> MeshInstance3D:
	var mat := MeshGen.shader_mat(DOME)
	mat.set_shader_parameter("kind", kind)
	mat.set_shader_parameter("skin", skin)
	mat.set_shader_parameter("seed", rng.randf() * 20.0)
	var mi := MeshGen.inst(self, MeshGen.sphere(1.0), mat, pos + Vector3(0, -h * 0.12, 0), Vector3(r, h, r))
	mi.set_meta("base_scale", mi.scale)
	return mi

static func tube_mat(kind: int, tint := Color.WHITE) -> ShaderMaterial:
	var key := "%d_%s" % [kind, tint.to_html()]
	if _tube_mats.has(key):
		return _tube_mats[key]
	var m := MeshGen.shader_mat(TUBE)
	m.set_shader_parameter("kind", kind)
	m.set_shader_parameter("tint", tint)
	_tube_mats[key] = m
	return m

func _tube(kind: int, pts: PackedVector3Array, radii: PackedFloat32Array, parent: Node3D = null, sides := 8) -> MeshInstance3D:
	var par := parent if parent else self
	return MeshGen.inst(par, MeshGen.tube(pts, radii, sides), tube_mat(kind, skin if kind == T_SKIN else Color.WHITE))

func _taper(count: int, r0: float, r1: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in count:
		out.append(lerpf(r0, r1, float(i) / maxf(1.0, count - 1)))
	return out

func _fade_lesion(key: String, dur := 0.8) -> void:
	if not n.has(key) or not is_instance_valid(n[key]):
		return
	var m: ShaderMaterial = n[key].material_override
	var tw := create_tween()
	tw.tween_method(func(v): m.set_shader_parameter("heal", v), 0.0, 1.0, dur)

func _heal_lesion(key: String, to: float, dur := 0.8) -> void:
	if not n.has(key) or not is_instance_valid(n[key]):
		return
	var m: ShaderMaterial = n[key].material_override
	var hv = m.get_shader_parameter("heal")
	var from: float = hv if hv != null else 0.0
	var tw := create_tween()
	tw.tween_method(func(v): m.set_shader_parameter("heal", v), from, to, dur)

func _shrink(key: String, dur := 0.4) -> void:
	if not n.has(key) or not is_instance_valid(n[key]):
		return
	var nd: Node3D = n[key]
	var tw := create_tween()
	tw.tween_property(nd, "scale", nd.scale * 0.01, dur).set_ease(Tween.EASE_IN)
	tw.tween_callback(nd.hide)

func _fly_off(nd: Node3D, extra := Vector3.ZERO) -> void:
	if nd == null or not is_instance_valid(nd):
		return
	var tw := create_tween().set_parallel()
	var target := nd.global_position + Vector3(rng.randf_range(-0.25, 0.25), 0.9, 0.35) + extra
	tw.tween_property(nd, "global_position", target, 0.55).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(nd, "rotation", nd.rotation + Vector3(rng.randf_range(-2, 2), rng.randf_range(-2, 2), 0), 0.55)
	tw.tween_property(nd, "scale", nd.scale * 0.01, 0.3).set_delay(0.3)
	tw.chain().tween_callback(nd.hide)

func _bandage(w: float, l: float) -> void:
	var b := Node3D.new()
	add_child(b)
	b.position = Vector3(0, 0.012, 0)
	MeshGen.inst(b, MeshGen.sphere(1.0), MeshGen.std(BAND, 0.8), Vector3.ZERO, Vector3(w * 0.5, 0.014, l * 0.5))
	MeshGen.inst(b, MeshGen.sphere(1.0), MeshGen.std(Color("fbf4ea"), 0.9), Vector3(0, 0.006, 0), Vector3(w * 0.2, 0.012, l * 0.2))
	for i in 8:
		var px := (float(i % 4) / 3.0 - 0.5) * w * 0.8
		var pz := (-0.35 if i < 4 else 0.35) * l
		MeshGen.inst(b, MeshGen.sphere(1.0), MeshGen.std(BAND.darkened(0.2), 0.8), Vector3(px, 0.011, pz), Vector3.ONE * 0.004)
	b.scale = Vector3.ONE * 0.01
	var tw := create_tween()
	tw.tween_property(b, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.play("tap")

func _nail_bandage() -> void:
	var nd: Node3D = nail["node"]
	var r: float = nail["r"]
	var band := Node3D.new()
	nd.add_child(band)
	band.position = Vector3(0, -r * 0.6, nail["len"] * 0.55)
	var ring := MeshGen.inst(band, MeshGen.cylinder(1.0, 1.0), MeshGen.std(BAND, 0.8), Vector3.ZERO, Vector3(r * 1.2, nail["len"] * 1.1, r * 1.05))
	ring.rotation.x = PI / 2
	MeshGen.inst(band, MeshGen.sphere(1.0), MeshGen.std(Color("fbf4ea"), 0.9), Vector3(0, r * 1.02, 0), Vector3(r * 0.6, 0.02, nail["len"] * 0.35))
	band.scale = Vector3.ONE * 0.01
	create_tween().tween_property(band, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.play("tap")

func _burst(pos: Vector3, c: Color, amount := 16, spd := 1.0, sz := 0.012, spread := 40.0) -> void:
	MeshGen.burst(body, pos, c, amount, spd, sz, global_basis.y, spread)

func _cut_guide(pts: PackedVector3Array) -> void:
	cut_path = pts
	if guide:
		guide.queue_free()
	guide = Node3D.new()
	body.add_child(guide)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 1, 1, 0.9)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	for i in pts.size():
		var r := 0.008 if (i == 0 or i == pts.size() - 1) else 0.004
		var d := MeshGen.inst(guide, MeshGen.sphere(1.0), m, pts[i] + Vector3(0, 0.01, 0), Vector3.ONE * r)
		d.set_meta("i", i)
	guide.visible = false

func show_guide(v: bool) -> void:
	if guide:
		guide.visible = v and mech() == Defs.Mech.CUT

func _end_guide() -> void:
	if guide:
		guide.queue_free()
		guide = null

## Fio de pus saindo e se enrolando
func _pus_string(base: Vector3, length: float, thick: float, key := "pus") -> void:
	var pts := PackedVector3Array()
	var cnt := 12
	for i in cnt:
		var k := float(i) / (cnt - 1)
		var s := k * length
		var curl := maxf(0.0, s - 0.03)
		pts.append(base + Vector3(sin(s * 40.0 + t * 2.0) * 0.004 + curl * curl * 6.0, s * 0.9 - curl * curl * 4.0, cos(s * 30.0) * 0.004))
	var radii := _taper(cnt, thick, thick * 0.55)
	if not n.has(key) or not is_instance_valid(n[key]):
		n[key] = MeshGen.inst(self, MeshGen.tube(pts, radii, 10), tube_mat(T_PUS))
	else:
		(n[key] as MeshInstance3D).mesh = MeshGen.tube(pts, radii, 10)
	n[key].visible = length > 0.004

func _drop_pus(key := "pus") -> void:
	if not n.has(key) or not is_instance_valid(n[key]):
		return
	var nd: Node3D = n[key]
	var tw := create_tween().set_parallel()
	tw.tween_property(nd, "position", nd.position + Vector3(0.04, -0.03, 0.02), 0.3)
	tw.tween_property(nd, "scale", Vector3(1.4, 0.05, 1.4), 0.3)
	tw.chain().tween_callback(nd.queue_free)
	n.erase(key)

# =================================================================== construção

func _build_espinha() -> void:
	n["red"] = _lesion(L_INFLAM, size * 1.6)
	n["dome"] = _dome(D_PUSTULE, size * 0.62, size * 0.5)
	n["grip"] = n["dome"]

func _build_bolha() -> void:
	n["red"] = _lesion(L_INFLAM, size * 1.4)
	_lmat(n["red"]).set_shader_parameter("strength", 0.5)
	n["dome"] = _dome(D_BLISTER, size * 0.8, size * 0.55)

func _build_farpa() -> void:
	n["red"] = _lesion(L_INFLAM, size * 0.9)
	var piv := Node3D.new()
	add_child(piv)
	piv.rotation = Vector3(0, rng.randf() * TAU, 0)
	n["piv"] = piv
	var sp := Node3D.new()
	piv.add_child(sp)
	n["splinter"] = sp
	var pts := PackedVector3Array()
	var dirv := Vector3(0.94, 0.33, 0).normalized()
	for i in 6:
		pts.append(dirv * (-0.06 + i * 0.03))
	_tube(T_WOOD, pts, _taper(6, 0.009, 0.004), sp, 6)
	var grip := Node3D.new()
	sp.add_child(grip)
	grip.position = dirv * 0.09
	n["grip"] = grip
	n["dir"] = dirv

func _build_sujeira() -> void:
	n["dirt"] = _lesion(L_DIRT, size * 1.1, Vector2.ZERO, true)
	n["crumbs"] = []
	for i in rng.randi_range(7, 11):
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * size * 0.75
		var c := global_position + Vector3(cos(a) * d, 0, sin(a) * d)
		var sp := body.surface(c.x, c.z)
		if sp.is_empty():
			continue
		var r := rng.randf_range(0.008, 0.018)
		var mi := MeshGen.inst(body, MeshGen.sphere(1.0), MeshGen.std(Color(0.25, 0.17, 0.1), 0.9), sp[0], Vector3(r, r * 0.6, r))
		mi.set_meta("th", rng.randf() * 0.7)
		n["crumbs"].append(mi)

func _build_cravos() -> void:
	n["oily"] = _lesion(L_OILY, size * 1.3, Vector2.ZERO, true)
	for i in rng.randi_range(10, 15):
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * size
		var c := global_position + Vector3(cos(a) * d, 0, sin(a) * d)
		var sp := body.surface(c.x, c.z)
		if sp.is_empty():
			continue
		var nd := Node3D.new()
		body.add_child(nd)
		nd.global_position = sp[0]
		nd.global_basis = MeshGen.basis_from_normal(sp[1])
		MeshGen.inst(nd, MeshGen.sphere(1.0), MeshGen.std(skin.darkened(0.12), 0.6), Vector3(0, -0.002, 0), Vector3(0.011, 0.004, 0.011))
		MeshGen.inst(nd, MeshGen.sphere(1.0), MeshGen.std(Color(0.1, 0.07, 0.05), 0.4), Vector3(0, 0.001, 0), Vector3(0.0065, 0.003, 0.0065))
		items.append({"node": nd, "pos": sp[0], "alive": true})
	items_left = items.size()

func _build_pelos() -> void:
	for i in rng.randi_range(70, 95):
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf())
		var c := global_position + Vector3(cos(a) * d * size * 1.25, 0, sin(a) * d * size * 0.9)
		var sp := body.surface(c.x, c.z)
		if sp.is_empty():
			continue
		var root: Vector3 = sp[0]
		var nn: Vector3 = sp[1]
		var g := Vector3(1, 0, 0).rotated(Vector3.UP, rng.randf_range(-0.6, 0.6) + (0.25 if body.part == "pe" else 0.0))
		g = (g - nn * g.dot(nn)).normalized()
		var L := rng.randf_range(0.06, 0.13)
		var curl := rng.randf_range(-1.0, 1.0) * (2.5 if rng.randf() < 0.3 else 0.6)
		var pts := PackedVector3Array()
		var side := nn.cross(g).normalized()
		var lift := rng.randf_range(0.35, 0.7)
		for k in 6:
			var s := float(k) / 5.0
			var up := lift * (1.0 - s) * (1.0 - s) * 0.6 + 0.01
			pts.append(root + g * L * s + nn * (L * up * s + 0.002) + side * curl * L * s * s * 0.5)
		var col := 0 if rng.randf() < 0.6 else 1
		var radii := _taper(6, rng.randf_range(0.0035, 0.0055), 0.0012)
		var rel := PackedVector3Array()
		for q in pts:
			rel.append(q - global_position)
		var it := {"pos": root, "pts": rel, "radii": radii, "col": col, "alive": true}
		items.append(it)
	items_left = items.size()
	_hair_mi = MeshInstance3D.new()
	_hair_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flat.add_child(_hair_mi)
	var mi2 := MeshInstance3D.new()
	mi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flat.add_child(mi2)
	n["hair2"] = mi2
	_rebuild_hairs()

func _rebuild_hairs() -> void:
	var a := []
	var b := []
	for it in items:
		if it["alive"]:
			(a if it["col"] == 0 else b).append([it["pts"], it["radii"]])
	_hair_mi.mesh = MeshGen.tubes(a, 4)
	_hair_mi.material_override = MeshGen.std(Color(0.1, 0.07, 0.05), 0.55, 0.0, "hair_a")
	n["hair2"].mesh = MeshGen.tubes(b, 4)
	n["hair2"].material_override = MeshGen.std(Color(0.3, 0.19, 0.1), 0.55, 0.0, "hair_b")

func _build_pelo_encravado() -> void:
	n["red"] = _lesion(L_INFLAM, size * 1.3)
	n["dome"] = _dome(D_BUMP, size * 0.55, size * 0.4)
	# pelo enrolado debaixo da pele
	var pts := PackedVector3Array()
	for i in 9:
		var a := -0.3 + i * 0.6
		pts.append(Vector3(cos(a) * size * 0.32, size * 0.18 + 0.002, sin(a) * size * 0.32))
	n["loop"] = _tube(T_HAIR, pts, _taper(9, 0.003, 0.0025), null, 4)
	n["loop"].material_override = MeshGen.std(Color(0.18, 0.1, 0.07, 0.75), 0.6)
	var hair := Node3D.new()
	add_child(hair)
	n["hair"] = hair
	var grip := Node3D.new()
	add_child(grip)
	n["grip"] = grip

func _build_carrapato() -> void:
	n["red"] = _lesion(L_INFLAM, size * 1.2)
	var tick := Node3D.new()
	add_child(tick)
	tick.rotation.y = rng.randf() * TAU
	n["tick"] = tick
	n["grip"] = tick
	var dark := MeshGen.std(Color(0.22, 0.14, 0.1), 0.25, 0.0, "tick_d")
	MeshGen.inst(tick, MeshGen.sphere(1.0), MeshGen.std(Color(0.5, 0.42, 0.42), 0.2, 0.0, "tick_b"), Vector3(0, 0.022, -0.012), Vector3(0.042, 0.03, 0.055))
	MeshGen.inst(tick, MeshGen.sphere(1.0), dark, Vector3(0, 0.03, 0.03), Vector3(0.026, 0.016, 0.022))
	MeshGen.inst(tick, MeshGen.sphere(1.0), dark, Vector3(0, 0.014, 0.052), Vector3(0.011, 0.009, 0.014))
	n["legs"] = []
	for side in [-1.0, 1.0]:
		for i in 4:
			var pv := Node3D.new()
			tick.add_child(pv)
			pv.position = Vector3(side * 0.018, 0.022, 0.035 - i * 0.011)
			pv.rotation.y = side * (0.3 + i * 0.4)
			var pts := PackedVector3Array([Vector3.ZERO, Vector3(side * 0.025, 0.006, 0.0), Vector3(side * 0.045, -0.018, 0.0)])
			_tube(T_DARK, pts, PackedFloat32Array([0.0028, 0.0022, 0.0015]), pv, 5)
			n["legs"].append(pv)

func _build_crosta() -> void:
	n["red"] = _lesion(L_INFLAM, size * 1.5)
	n["crust"] = _lesion(L_CRUST, size * 1.05, Vector2.ZERO, true, 0.006)

func _build_calo() -> void:
	n["callus"] = _lesion(L_CALLUS, size * 1.1, Vector2.ZERO, true)
	n["bump"] = _dome(D_BUMP, size * 0.85, size * 0.2)
	n["bump"].visible = false

func _nail_basics() -> void:
	n["nail_mat"] = nail["mat"]
	var nd: Node3D = nail["node"]
	n["center"] = Node3D.new()
	nd.add_child(n["center"])
	n["center"].position = Vector3(0, 0, nail["len"] * 0.6)

func _nail_line(z: float, x0: float, x1: float, count := 8) -> PackedVector3Array:
	var nd: Node3D = nail["node"]
	var w: float = nail["w"]
	var out := PackedVector3Array()
	for i in count:
		var u := lerpf(x0, x1, float(i) / (count - 1))
		out.append(nd.to_global(Vector3(u * w * 0.5, -w * 0.17 * u * u + 0.006, z)))
	return out

func _build_unha_suja() -> void:
	_nail_basics()
	var mi: MeshInstance3D = nail["mi"]
	var extra: float = nail["len"] * 0.55
	mi.mesh = MeshGen.nail(nail["w"], nail["len"], nail["w"] * 0.17, extra)
	var mat: ShaderMaterial = nail["mat"]
	mat.set_shader_parameter("dirt", 1.0)
	var mk := CleanMask.new()
	n["mask"] = mk
	mat.set_shader_parameter("mask", mk.tex)
	mat.set_shader_parameter("use_mask", 1.0)
	_cut_guide(_nail_line(nail["len"] * 1.02, -1.1, 1.1))

func _build_unha_pus() -> void:
	_nail_basics()
	var nd: Node3D = nail["node"]
	var w: float = nail["w"]
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var p := nd.to_global(Vector3(side * w * 0.55, -0.01, nail["len"] * 0.35))
	n["red"] = _lesion(L_INFLAM, w * 0.85, Vector2(p.x - global_position.x, p.z - global_position.z))
	var holder := Node3D.new()
	nd.add_child(holder)
	holder.position = Vector3(side * w * 0.56, -0.004, nail["len"] * 0.35)
	n["holder"] = holder
	var mat := MeshGen.shader_mat(DOME)
	mat.set_shader_parameter("kind", D_PUSTULE)
	mat.set_shader_parameter("skin", skin)
	n["dome"] = MeshGen.inst(holder, MeshGen.sphere(1.0), mat, Vector3.ZERO, Vector3(w * 0.28, w * 0.22, nail["len"] * 0.35))
	n["dome"].set_meta("base_scale", n["dome"].scale)
	n["center"].position = holder.position

func _build_fungo_unha() -> void:
	_nail_basics()
	var mi: MeshInstance3D = nail["mi"]
	mi.mesh = MeshGen.nail(nail["w"], nail["len"], nail["w"] * 0.16, nail["len"] * 0.15)
	var mat: ShaderMaterial = nail["mat"]
	mat.set_shader_parameter("fungus", 1.0)
	var mk := CleanMask.new()
	n["mask"] = mk
	mat.set_shader_parameter("mask", mk.tex)
	mat.set_shader_parameter("use_mask", 1.0)
	n["thick"] = mi
	mi.scale = Vector3(1.0, 2.2, 1.0)

func _build_unha_encravada() -> void:
	_nail_basics()
	var nd: Node3D = nail["node"]
	var w: float = nail["w"]
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	n["side"] = side
	var p := nd.to_global(Vector3(side * w * 0.6, -0.01, nail["len"] * 0.6))
	n["red"] = _lesion(L_INFLAM, w * 0.95, Vector2(p.x - global_position.x, p.z - global_position.z))
	var holder := Node3D.new()
	nd.add_child(holder)
	holder.position = Vector3(side * w * 0.6, -0.008, nail["len"] * 0.62)
	n["holder"] = holder
	var mat := MeshGen.shader_mat(DOME)
	mat.set_shader_parameter("kind", D_BUMP)
	mat.set_shader_parameter("skin", skin)
	n["swell"] = MeshGen.inst(holder, MeshGen.sphere(1.0), mat, Vector3.ZERO, Vector3(w * 0.22, w * 0.2, nail["len"] * 0.5))
	var pm := MeshGen.shader_mat(DOME)
	pm.set_shader_parameter("kind", D_PUSTULE)
	pm.set_shader_parameter("skin", skin)
	n["dome"] = MeshGen.inst(holder, MeshGen.sphere(1.0), pm, Vector3(side * 0.008, 0.01, nail["len"] * 0.15), Vector3(w * 0.12, w * 0.12, w * 0.14))
	# lasca da unha que entrou na pele
	var sliver := Node3D.new()
	nd.add_child(sliver)
	n["sliver"] = sliver
	n["grip"] = sliver
	var sm := MeshGen.std(Color("f4d8cf"), 0.2)
	MeshGen.inst(sliver, MeshGen.sphere(1.0), sm, Vector3(side * w * 0.43, -0.002, nail["len"] * 0.62), Vector3(w * 0.09, 0.008, nail["len"] * 0.38))
	n["center"].position = holder.position
	_cut_guide(_nail_line_side(side))

func _nail_line_side(side: float) -> PackedVector3Array:
	var nd: Node3D = nail["node"]
	var w: float = nail["w"]
	var out := PackedVector3Array()
	for i in 7:
		var z := lerpf(nail["len"] * 1.0, nail["len"] * 0.3, float(i) / 6.0)
		out.append(nd.to_global(Vector3(side * w * 0.3, 0.006, z)))
	return out

func _build_furunculo() -> void:
	n["red"] = _lesion(L_INFLAM, size * 2.3)
	n["dome"] = _dome(D_BOIL, size * 0.8, size * 0.55)
	var pts := PackedVector3Array()
	var r := size * 0.8
	var h := size * 0.55
	for i in 9:
		var x := lerpf(-r * 0.85, r * 0.85, float(i) / 8.0)
		var y := -h * 0.12 + h * sqrt(maxf(0.0, 1.0 - pow(x / r, 2.0))) + 0.003
		pts.append(to_global(Vector3(x, y, 0)))
	_cut_guide(pts)
	n["slit_pts"] = pts

func _build_verme() -> void:
	n["track"] = _lesion(L_TRACK, size * 1.05, Vector2.ZERO, false, 0.005)
	_lmat(n["track"]).set_shader_parameter("cut", 0.0)
	var mi: MeshInstance3D = n["track"]
	var c: Vector3 = mi.get_meta("c")
	var rot: float = mi.get_meta("rot")
	var half: float = mi.get_meta("half")
	var seed: float = _lmat(mi).get_shader_parameter("seed")
	var path := PackedVector3Array()
	for i in 13:
		var u := lerpf(-0.88, 0.88, float(i) / 12.0)
		var v := sin(u * 5.0 + seed) * 0.22
		var lx := (u * cos(rot) - v * sin(rot)) * half
		var lz := (u * sin(rot) + v * cos(rot)) * half
		var sp := body.surface(c.x + lx, c.z + lz)
		path.append(sp[0] if not sp.is_empty() else c + Vector3(lx, 0, lz))
	_worm_pts = path
	n["bump"] = MeshInstance3D.new()
	flat.add_child(n["bump"])
	n["bump"].material_override = tube_mat(T_SKIN, skin)
	_cut_guide(path)
	var worm := Node3D.new()
	body.add_child(worm)
	n["worm"] = worm
	n["worm_mi"] = MeshGen.inst(worm, null, tube_mat(T_WORM))
	var grip := Node3D.new()
	body.add_child(grip)
	grip.global_position = path[0]
	n["grip"] = grip

func _build_larvas() -> void:
	n["wound"] = _lesion(L_WOUND, size * 1.0, Vector2.ZERO, false, 0.004)
	n["red"] = _lesion(L_INFLAM, size * 1.5, Vector2.ZERO, false, 0.002)
	n["grime"] = _lesion(L_PUS, size * 1.15, Vector2.ZERO, true, 0.008)
	for i in rng.randi_range(7, 10):
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * size * 0.6
		var c := global_position + Vector3(cos(a) * d, 0, sin(a) * d)
		var sp := body.surface(c.x, c.z)
		if sp.is_empty():
			continue
		var nd := Node3D.new()
		body.add_child(nd)
		nd.global_position = sp[0] + sp[1] * 0.006
		nd.global_basis = MeshGen.basis_from_normal(sp[1]).rotated(sp[1], rng.randf() * TAU)
		var pts := PackedVector3Array()
		for k in 7:
			pts.append(Vector3(0, 0.003 * sin(k * 0.8), -0.022 + k * 0.0075))
		var r := rng.randf_range(0.85, 1.25)
		var rad := PackedFloat32Array()
		for k in 7:
			rad.append((0.006 + 0.005 * sin(PI * (k + 0.6) / 7.6)) * r)
		var mi := MeshGen.inst(nd, MeshGen.tube(pts, rad, 10), tube_mat(T_LARVA))
		mi.set_meta("ph", rng.randf() * TAU)
		items.append({"node": nd, "pos": sp[0], "alive": true, "mi": mi})
	items_left = items.size()

func _build_favo() -> void:
	n["red"] = _lesion(L_INFLAM, size * 1.45, Vector2.ZERO, false, 0.002)
	n["favo"] = _lesion(L_FAVO, size * 1.1, Vector2.ZERO, false, 0.004)
	n["grime"] = _lesion(L_PUS, size * 1.05, Vector2.ZERO, true, 0.008)
	for i in rng.randi_range(10, 14):
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * size * 0.7
		var c := global_position + Vector3(cos(a) * d, 0, sin(a) * d)
		var sp := body.surface(c.x, c.z)
		if sp.is_empty():
			continue
		var nd := Node3D.new()
		body.add_child(nd)
		nd.global_position = sp[0]
		nd.global_basis = MeshGen.basis_from_normal(sp[1])
		var r := rng.randf_range(0.011, 0.018)
		var mat := MeshGen.shader_mat(DOME)
		mat.set_shader_parameter("kind", D_PUSTULE)
		mat.set_shader_parameter("skin", Color(0.6, 0.2, 0.15))
		MeshGen.inst(nd, MeshGen.sphere(1.0), mat, Vector3(0, -0.002, 0), Vector3(r, r * 0.8, r))
		items.append({"node": nd, "pos": sp[0], "alive": true})
	items_left = items.size()

func _build_verruga() -> void:
	n["red"] = _lesion(L_INFLAM, size * 1.2)
	_lmat(n["red"]).set_shader_parameter("strength", 0.4)
	n["dome"] = _dome(D_WART, size * 0.72, size * 0.5)

func _build_machucado() -> void:
	n["wound"] = _lesion(L_WOUND, size * 0.9, Vector2.ZERO, false, 0.004)
	n["blood"] = _lesion(L_BLOOD, size * 1.4, Vector2(0.01, 0.01), true, 0.007)
	_burst(global_position + global_basis.y * 0.01, BLOOD_C, 10, 0.7, 0.008)

# =================================================================== animação contínua

func _process(delta: float) -> void:
	t += delta
	match id:
		"carrapato":
			if n.has("legs"):
				var fast := stage == 0 and progress > 0.0
				for i in n["legs"].size():
					n["legs"][i].rotation.z = sin(t * (14.0 if fast else 3.0) + i * 1.3) * 0.25
		"larvas":
			for it in items:
				if it["alive"]:
					var mi: MeshInstance3D = it["mi"]
					var ph: float = mi.get_meta("ph")
					mi.rotation.y = sin(t * 5.0 + ph) * 0.5
					mi.scale = Vector3(1.0, 1.0, 1.0 + sin(t * 8.0 + ph) * 0.18)
		"verme":
			_update_worm()
		"pelos":
			if _hair_dirty:
				_hair_dirty = false
				_rebuild_hairs()

func _update_worm() -> void:
	if _worm_pts.is_empty():
		return
	var path := _worm_pts
	# caroço do verme andando debaixo da pele
	if stage <= 1 and n.has("bump") and is_instance_valid(n["bump"]):
		var hide_k := progress if stage == 1 else 0.0
		var pts := PackedVector3Array()
		var head := 0.35 + 0.25 * sin(t * 0.8)
		var cnt := 10
		for i in cnt:
			var k := clampf(head + (float(i) / (cnt - 1) - 0.5) * 0.45, 0.0, 1.0)
			var f := k * (path.size() - 1)
			var ia := int(f)
			var ib := mini(ia + 1, path.size() - 1)
			var p := path[ia].lerp(path[ib], f - ia)
			p += Vector3(0, -0.006 + sin(t * 6.0 + i) * 0.001, 0)
			pts.append(p - flat.global_position)
		var rr := PackedFloat32Array()
		for i in cnt:
			rr.append(0.02 * sin(PI * (i + 0.5) / cnt) * (1.0 - hide_k) + 0.001)
		n["bump"].mesh = MeshGen.tube(pts, rr, 8)
		n["bump"].visible = stage == 0 or progress < 0.98
	if stage == 1:
		# verme saindo pelo corte
		var mouth := path[path.size() / 2]
		var tip := mouth + Vector3(0, 0.07 + progress * 0.25, 0) + pull_dir * (0.03 + progress * 0.14)
		var pts2 := PackedVector3Array()
		var cnt2 := 14
		for i in cnt2:
			var k := float(i) / (cnt2 - 1)
			var p := mouth.lerp(tip, k)
			p += Vector3(sin(k * 9.0 + t * 7.0), 0, cos(k * 7.0 + t * 6.0)) * 0.012 * k
			p.y += sin(k * PI) * 0.02
			pts2.append(p)
		(n["worm_mi"] as MeshInstance3D).mesh = MeshGen.tube(pts2, _taper(cnt2, 0.017, 0.012), 10)
		n["grip"].global_position = tip

# =================================================================== progresso de cada etapa

func _rub_target() -> MeshInstance3D:
	match id:
		"espinha", "furunculo", "unha_pus", "unha_encravada": return n.get("splat")
		"bolha": return n.get("splat")
		"farpa", "pelo_encravado", "carrapato", "verme": return n.get("blood")
		"sujeira": return n.get("dirt")
		"cravos": return n.get("oily")
		"crosta": return n.get("crust") if stage == 1 else null
		"calo": return n.get("callus") if stage == 0 else null
		"larvas": return n.get("grime") if stage == 0 else n.get("blood")
		"favo": return n.get("grime") if stage == 0 else null
		"machucado": return n.get("blood")
	return null

## Esfregar unha usa a máscara da própria unha
func rub_nail(wpos: Vector3, brush_r: float) -> bool:
	if not n.has("mask") or nail.is_empty():
		return false
	var a := amount()
	if a > 1.0:
		return false
	var nd: Node3D = nail["node"]
	var lp := nd.to_local(wpos)
	var w: float = nail["w"]
	var L: float = nail["len"]
	var u := lp.x / (w * 0.5)
	var v := lp.z / L
	var mk: CleanMask = n["mask"]
	mk.paint(Vector2(u, v / 1.6 * 2.0 - 1.0), brush_r / (w * 0.5), 0.35 * speed)
	mk.flush()
	var cov := 0.0
	var cnt := 0
	for j in 8:
		var vv := 0.1 + 0.9 * (j + 0.5) / 8.0
		for i in 6:
			var uu := -0.8 + 1.6 * (i + 0.5) / 6.0
			var px := clampi(int((uu * 0.5 + 0.5) * CleanMask.SIZE), 0, CleanMask.SIZE - 1)
			var py := clampi(int(vv / 1.6 * CleanMask.SIZE), 0, CleanMask.SIZE - 1)
			cov += mk.img.get_pixel(px, py).r
			cnt += 1
	progress = clampf(cov / cnt / a, 0.0, 1.0)
	if progress >= 0.9:
		progress = 1.0
	_visual()
	if progress >= 1.0:
		_complete_stage()
	return true

func uses_nail_mask() -> bool:
	return (id == "unha_suja" and stage == 1) or (id == "fungo_unha" and stage == 0)

func _visual() -> void:
	var p := clampf(progress, 0.0, 1.0)
	var tl := tool()
	match id:
		"espinha":
			if stage == 1:
				_squeeze_dome(p, 0.75)
				_pus_string(n["dome"].position + Vector3(0, size * 0.42 * (1.0 - p * 0.6), 0), p * 0.11, 0.009)
			elif stage == 0:
				_lset("dome", "swell", p * 0.15)
		"bolha":
			if stage == 0:
				_lset("dome", "swell", p * 0.1)
		"farpa":
			if stage == 0:
				n["splinter"].position = n["dir"] * p * 0.1
		"sujeira":
			for c in n["crumbs"]:
				if is_instance_valid(c) and c.visible and p > c.get_meta("th"):
					_fly_off(c)
		"pelo_encravado":
			if stage == 1:
				var pts := PackedVector3Array()
				var L := 0.02 + p * 0.1
				for i in 6:
					var k := float(i) / 5.0
					pts.append(Vector3(k * L * 0.3, size * 0.2 + k * L, sin(k * 4.0) * 0.004))
				var hair: Node3D = n["hair"]
				for c in hair.get_children():
					c.queue_free()
				_tube(T_HAIR, pts, _taper(6, 0.0032, 0.0018), hair, 5).material_override = MeshGen.std(Color(0.12, 0.08, 0.05), 0.5, 0.0, "hair_a")
				n["grip"].position = pts[5]
				n["loop"].scale = Vector3.ONE * (1.0 - p)
		"carrapato":
			if stage == 0:
				n["tick"].position.y = p * 0.03
				n["tick"].rotation.x = -p * 0.6
		"crosta":
			if stage == 0:
				_lset("crust", "strength", 1.0 - p * 0.15)
		"calo":
			if stage == 1:
				_lset("callus", "strength", 1.0 - p * 0.9)
		"unha_suja":
			pass
		"unha_pus":
			if stage == 1:
				_squeeze_dome(p, 0.8)
				_pus_string(to_local(n["holder"].global_position) + global_basis.inverse() * (nail["normal"] * nail["w"] * 0.2), p * 0.08, 0.008, "pus")
		"fungo_unha":
			if stage == 0:
				n["thick"].scale = Vector3(1.0, lerpf(2.2, 1.0, p), 1.0)
		"furunculo":
			match stage:
				0:
					_lset("red", "strength", 1.0)
					_draw_slit(p)
				1:
					_squeeze_dome(p, 0.85)
					var top := Vector3(0, size * 0.5 * (1.0 - p * 0.7), 0)
					_pus_string(top, p * 0.16, 0.016, "pus")
					if p > 0.4:
						_pus_string(top + Vector3(0.02, 0, 0.015), (p - 0.4) * 0.1, 0.01, "pus2")
		"verme":
			if stage == 0:
				_lset("track", "cut", p)
				_lset("track", "open_amt", p * 0.4)
		"verruga":
			if stage == 0:
				_lset("dome", "frozen", p)
			elif stage == 1:
				var d: MeshInstance3D = n["dome"]
				d.scale = d.get_meta("base_scale") * Vector3(1.0 - p * 0.75, 1.0 - p * 0.95, 1.0 - p * 0.75)
			elif stage == 2:
				_lset("red", "heal", p)
		"larvas":
			if stage == 3:
				_lset("wound", "heal", p)
				_lset("red", "heal", p)
		"favo":
			if stage == 2:
				_lset("favo", "heal", p * 0.45)
			elif stage == 3:
				_lset("favo", "heal", 0.45 + p * 0.55)
				_lset("red", "heal", p)
	if tl == "pomada" and p > 0.0:
		if rng.randf() < 0.3:
			_burst(center() + Vector3(rng.randf_range(-size, size), 0.01, rng.randf_range(-size, size)) * Vector3(1, 1, 1), Color(1, 1, 1), 2, 0.1, 0.008, 80.0)

func _squeeze_dome(p: float, max_shrink: float) -> void:
	if not n.has("dome") or not is_instance_valid(n["dome"]):
		return
	var d: MeshInstance3D = n["dome"]
	var bs: Vector3 = d.get_meta("base_scale", d.scale)
	var pulse := 1.0 + sin(t * 30.0) * 0.03
	d.scale = Vector3(bs.x * (1.0 - p * max_shrink * 0.4) * pulse, bs.y * (1.0 - p * max_shrink), bs.z * (1.0 - p * max_shrink * 0.4) * pulse)

func _draw_slit(p: float) -> void:
	var pts: PackedVector3Array = n["slit_pts"]
	var cnt := maxi(2, int(ceil(p * (pts.size() - 1))) + 1)
	var sub := PackedVector3Array()
	for i in cnt:
		sub.append(to_local(pts[mini(i, pts.size() - 1)]) + Vector3(0, 0.002, 0))
	if not n.has("slit"):
		n["slit"] = MeshGen.inst(self, null, MeshGen.std(Color(0.35, 0.02, 0.04), 0.2, 0.0, "slit"))
	if p > 0.01:
		(n["slit"] as MeshInstance3D).mesh = MeshGen.tube(sub, PackedFloat32Array([0.004]), 6)
		if rng.randf() < 0.3:
			_burst(pts[mini(cnt - 1, pts.size() - 1)], BLOOD_C, 2, 0.3, 0.006, 60.0)

func _remove_item(it: Dictionary) -> void:
	it["alive"] = false
	items_left -= 1
	match id:
		"pelos":
			_hair_dirty = true
			var pts: PackedVector3Array = it["pts"]
			var fall := MeshGen.inst(flat, MeshGen.tube(pts, it["radii"], 4), MeshGen.std(Color(0.1, 0.07, 0.05), 0.55, 0.0, "hair_a" if it["col"] == 0 else "hair_b"))
			var tw := create_tween().set_parallel()
			tw.tween_property(fall, "position", fall.position + Vector3(rng.randf_range(-0.05, 0.05), -0.08, 0.12), 0.6).set_ease(Tween.EASE_IN)
			tw.tween_property(fall, "rotation", Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)), 0.6)
			tw.chain().tween_callback(fall.queue_free)
			Sfx.play_throttled("cut", 0.05)
		"cravos":
			var nd: Node3D = it["node"]
			var plug := MeshGen.inst(nd, MeshGen.tube(PackedVector3Array([Vector3.ZERO, Vector3(0, 0.012, 0), Vector3(0.003, 0.024, 0)]), PackedFloat32Array([0.006, 0.005, 0.004]), 6), tube_mat(T_PUS))
			var tw := create_tween()
			tw.tween_property(plug, "scale", Vector3(1, 1.4, 1), 0.15)
			tw.tween_callback(func():
				_fly_off(plug)
				_burst(it["pos"], Color(1, 0.95, 0.7), 4, 0.5, 0.005, 30.0))
			for c in nd.get_children():
				if c != plug:
					create_tween().tween_property(c, "scale", c.scale * 0.3, 0.3)
			Sfx.play("pop", 0.3)
		"favo":
			var nd2: Node3D = it["node"]
			popped.emit(self, PUS_C)
			var plug2 := MeshGen.inst(nd2, MeshGen.tube(PackedVector3Array([Vector3.ZERO, Vector3(0.002, 0.02, 0), Vector3(0.012, 0.035, 0.004)]), PackedFloat32Array([0.009, 0.007, 0.005]), 8), tube_mat(T_PUS))
			var tw2 := create_tween()
			tw2.tween_property(plug2, "scale", Vector3(1.2, 1.3, 1.2), 0.18)
			tw2.tween_callback(func(): _fly_off(plug2))
			for c in nd2.get_children():
				if c != plug2:
					c.hide()
			_burst(it["pos"], PUS_C, 6, 0.7, 0.008, 35.0)
			Sfx.play("squish", 0.25)
		"larvas":
			_fly_off(it["node"])
			Sfx.play("squish", 0.25)
	GameData.vibrate(15)

# =================================================================== início/fim de etapa

func _on_stage_start(s: int) -> void:
	match id:
		"farpa", "carrapato", "pelo_encravado":
			pass
		"larvas":
			if s == 2:
				n["blood"] = _lesion(L_BLOOD, size * 0.95, Vector2.ZERO, true, 0.009)

func _on_stage_end(s: int) -> void:
	var up := global_basis.y
	var gp := global_position
	match id:
		"espinha":
			if s == 0:
				_lset("dome", "hole", 1.0)
				_lset("dome", "swell", 0.0)
				Sfx.play("poke")
				_burst(gp + up * size * 0.45, PUS_C, 4, 0.3, 0.006, 20.0)
			elif s == 1:
				_drop_pus()
				_burst(gp + up * 0.03, PUS_C, 18, 1.1, 0.011, 35.0)
				n["splat"] = _lesion(L_PUS, size * 1.2, Vector2(rng.randf_range(-0.02, 0.02), rng.randf_range(-0.02, 0.02)), true, 0.008)
				_shrink("dome", 0.3)
				popped.emit(self, PUS_C)
				Sfx.play("splat")
		"bolha":
			if s == 0:
				_lset("dome", "hole", 1.0)
				Sfx.play("poke")
				var d: MeshInstance3D = n["dome"]
				var tw := create_tween()
				tw.tween_property(d, "scale", Vector3(d.scale.x * 1.05, d.scale.y * 0.15, d.scale.z * 1.05), 0.9).set_ease(Tween.EASE_OUT)
				n["splat"] = _lesion(L_FLUID, size * 1.4, Vector2.ZERO, true, 0.008)
				_burst(gp + up * 0.02, Color(1, 1, 0.95, 0.7), 12, 0.5, 0.01, 60.0)
		"farpa":
			if s == 0:
				_fly_off(n["piv"])
				n["blood"] = _lesion(L_BLOOD, 0.03, Vector2.ZERO, true, 0.008)
				Sfx.play("pull")
		"pelo_encravado":
			if s == 0:
				_lset("dome", "hole", 1.0)
				Sfx.play("poke")
			elif s == 1:
				_fly_off(n["hair"])
				n["loop"].hide()
				n["blood"] = _lesion(L_BLOOD, 0.028, Vector2.ZERO, true, 0.008)
				_shrink("dome", 0.6)
				Sfx.play("pull")
		"carrapato":
			if s == 0:
				_fly_off(n["tick"])
				n["blood"] = _lesion(L_BLOOD, 0.035, Vector2.ZERO, true, 0.008)
				Sfx.play("pull")
		"cravos":
			if s == 0:
				pass
		"crosta":
			if s == 0:
				Sfx.play("squish")
		"calo":
			if s == 0:
				Sfx.play("scrub")
		"unha_suja":
			if s == 0:
				_cut_nail_tip(nail["len"] * 1.02)
				_end_guide()
		"unha_pus":
			if s == 0:
				_lset("dome", "hole", 1.0)
				Sfx.play("poke")
			elif s == 1:
				_drop_pus()
				_shrink("dome", 0.3)
				var p: Vector3 = n["holder"].global_position
				n["splat"] = _lesion(L_PUS, nail["w"] * 0.8, Vector2(p.x - gp.x, p.z - gp.z), true, 0.008)
				_burst(p + up * 0.02, PUS_C, 16, 0.9, 0.009, 40.0)
				popped.emit(self, PUS_C)
				Sfx.play("splat")
			elif s == 3:
				_nail_bandage()
		"unha_encravada":
			if s == 0:
				_end_guide()
				Sfx.play("cut")
				_burst(n["holder"].global_position, BLOOD_C, 5, 0.4, 0.006, 40.0)
			elif s == 1:
				_fly_off(n["sliver"])
				_shrink("dome", 0.25)
				var p2: Vector3 = n["holder"].global_position
				n["splat"] = _lesion(L_PUS, nail["w"] * 0.75, Vector2(p2.x - gp.x, p2.z - gp.z), true, 0.008)
				_burst(p2, PUS_C, 14, 0.9, 0.009, 40.0)
				popped.emit(self, PUS_C)
				Sfx.play("splat")
			elif s == 3:
				_nail_bandage()
		"furunculo":
			if s == 0:
				_end_guide()
				Sfx.play("cut")
			elif s == 1:
				_drop_pus("pus")
				_drop_pus("pus2")
				_shrink("dome", 0.35)
				if n.has("slit"):
					n["slit"].hide()
				n["splat"] = _lesion(L_PUS, size * 1.3, Vector2.ZERO, true, 0.008)
				n["blood2"] = _lesion(L_WOUND, size * 0.55, Vector2.ZERO, false, 0.006)
				_burst(gp + up * 0.04, PUS_C, 26, 1.3, 0.014, 40.0)
				_burst(gp + up * 0.04, BLOOD_C, 10, 1.0, 0.01, 50.0)
				popped.emit(self, PUS_C)
				Sfx.play("splat")
			elif s == 3:
				_bandage(size * 2.4, size * 1.6)
		"verme":
			if s == 0:
				_end_guide()
				Sfx.play("cut")
			elif s == 1:
				_fly_off(n["worm"], Vector3(0, 0.3, 0))
				n["bump"].hide()
				n["blood"] = _lesion(L_BLOOD, size * 0.8, Vector2.ZERO, true, 0.009)
				_burst(_worm_pts[_worm_pts.size() / 2], BLOOD_C, 14, 1.0, 0.01, 45.0)
				popped.emit(self, BLOOD_C)
				Sfx.play("splat")
			elif s == 3:
				_heal_lesion("track", 0.6)
				_bandage(size * 2.2, size * 1.0)
		"verruga":
			if s == 0:
				Sfx.play("freeze")
			elif s == 1:
				_shrink("dome", 0.3)
		"larvas":
			if s == 0:
				pass
		"machucado":
			if s == 1:
				_bandage(size * 2.2, size * 1.4)

func _on_done() -> void:
	_end_guide()
	for key in ["red", "splat", "blood", "grime", "oily", "dirt"]:
		if n.has(key) and is_instance_valid(n[key]):
			_fade_lesion(key, 0.9)
	match id:
		"espinha", "pelo_encravado", "bolha":
			_shrink("dome", 0.8)
		"crosta":
			_fade_lesion("crust", 0.9)
		"calo":
			_fade_lesion("callus", 0.9)
		"cravos":
			for it in items:
				var nd: Node3D = it["node"]
				for c in nd.get_children():
					create_tween().tween_property(c, "scale", Vector3.ZERO, 0.6)
		"fungo_unha":
			var mat: ShaderMaterial = nail["mat"]
			create_tween().tween_method(func(v): mat.set_shader_parameter("fungus", v), 1.0, 0.0, 0.8)
		"unha_suja":
			var mat2: ShaderMaterial = nail["mat"]
			create_tween().tween_method(func(v): mat2.set_shader_parameter("dirt", v), 1.0, 0.0, 0.6)
		"unha_encravada", "unha_pus":
			_shrink("swell", 0.8)
		"verruga":
			_fade_lesion("red", 0.8)
		"favo":
			_fade_lesion("favo", 1.0)
		"larvas":
			_fade_lesion("wound", 1.0)

func _cut_nail_tip(at: float) -> void:
	var mat: ShaderMaterial = nail["mat"]
	mat.set_shader_parameter("cut_at", at / nail["len"])
	var piece := MeshInstance3D.new()
	piece.mesh = (nail["mi"] as MeshInstance3D).mesh
	var pm := mat.duplicate() as ShaderMaterial
	pm.shader = load("res://shaders/nail.gdshader")
	pm.set_shader_parameter("cut_at", 9.0)
	pm.set_shader_parameter("keep_from", at / nail["len"])
	piece.material_override = pm
	nail["node"].add_child(piece)
	var tw := create_tween().set_parallel()
	tw.tween_property(piece, "position", piece.position + Vector3(0.05, 0.2, nail["len"] * 1.5), 0.5).set_ease(Tween.EASE_OUT)
	tw.tween_property(piece, "rotation", Vector3(1.2, 0.8, 0.4), 0.5)
	tw.chain().tween_property(piece, "scale", Vector3.ZERO, 0.2)
	tw.chain().tween_callback(piece.queue_free)
	Sfx.play("cut")
