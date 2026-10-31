class_name Problem
extends Node3D
## Um problema na pele/unha: monta o visual suave e anima cada etapa do tratamento.

signal stage_done(p: Problem, finished: bool)
signal popped(p: Problem, color: Color)
signal extra_stages(p: Problem, count: int)

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
const L_SCRAPE := 13
const L_SCAR := 14
const L_STUBBLE := 15
const L_CREAM := 16
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
var fx_hosts: Array = []          # nós com FxMap (corte/sangue pintado ao vivo)
var cut_host: Node3D              # onde a lâmina corta neste problema
var guide_uv := PackedVector2Array()
var wet := 0.0
var pus_tint := Color.WHITE
var cut_dir := 1.0
var rub_stall := 0.0
var cut_len := 0.0
var last_cut_w := Vector3.ZERO   # lado de onde o jogador começou o corte (alicate)
var blood_peak := 0.0
var domes: Array = []          # calombos (para a ferramenta pousar em cima)
var damage := 0                 # quantas vezes o jogador piorou este problema (ferramenta errada)

static var _tube_mats := {}

func setup(p_id: String, p_body: Body, p_rng: RandomNumberGenerator, extra := {}) -> void:
	id = p_id
	def = Defs.PROBLEMS[id]
	# pomada é opcional enquanto o jogador ainda não tem (não pode travar a fase)
	if not GameData.owned.has("pomada"):
		var has_p := false
		for st in def["stages"]:
			if st[0] == "pomada":
				has_p = true
		if has_p and def["stages"].size() > 1:
			def = def.duplicate(true)
			def["stages"] = def["stages"].filter(func(st): return st[0] != "pomada")
	size = def["size"]
	body = p_body
	skin = body.skin_mat.get_shader_parameter("skin")
	rng.seed = p_rng.randi()
	flat = Node3D.new()
	add_child(flat)
	flat.global_basis = Basis()
	if extra.has("nail"):
		nail = extra["nail"]
	# cada paciente é diferente: tamanho e cor do pus variam
	if id in ["espinha", "cisto", "furunculo", "abscesso", "carbunculo", "bolha", "verruga", "crosta", "sujeira", "favo", "larvas", "ralado", "calo", "acne_costas", "queimadura", "pontos", "piolhos", "caspa"]:
		size *= rng.randf_range(0.85, 1.35)
	var tints := [Color(1, 1, 1), Color(0.88, 1.0, 0.6), Color(1.05, 1.0, 0.85), Color(1.0, 0.85, 0.7)]
	pus_tint = tints[rng.randi() % tints.size()]
	if id == "abscesso":
		pus_tint = Color(0.75, 1.0, 0.45)
	elif id == "cisto":
		pus_tint = Color(1.08, 1.06, 0.95)
	call("_build_" + id)
	for key in n:
		var nd = n[key]
		if nd is MeshInstance3D and (nd as MeshInstance3D).material_override is ShaderMaterial:
			var m := (nd as MeshInstance3D).material_override as ShaderMaterial
			m.set_shader_parameter("tint", pus_tint)
			m.set_shader_parameter("pus_col", Color(0.93, 0.78, 0.36) * pus_tint)

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
## Esfregar. Retorna o quanto avançou (0 = não limpou nada novo).
func rub(wpos: Vector3, px: float, brush_r: float) -> float:
	if done:
		return 0.0
	var before := progress
	wet = 1.0
	if tool() == "algodao" or tool() == "pano":
		for h in fx_hosts:
			if is_instance_valid(h):
				var fx: FxMap = h.get_meta("fx")
				fx.wipe(host_uv(h, wpos), brush_r / _host_half(h) * FxMap.SIZE * 0.5, 0.45 * speed)
	if tool() == "pomada":
		_spread_cream(wpos, brush_r)
		if not cream_ready():
			return 0.0
	var a := amount()
	var target := _rub_target()
	var bhost: MeshInstance3D = n.get("aggr") if _aggr_stage() and tool() == "algodao" else (cut_host if id == "machucado" and tool() == "algodao" else null)
	if bhost:
		var fx: FxMap = bhost.get_meta("fx")
		var b := fx.blood_total()
		blood_peak = maxf(blood_peak, b)
		var pr := 0.0
		if blood_peak > 0.0015:
			pr = clampf((1.0 - b / blood_peak) / 0.8, 0.0, 1.0)
		else:
			# quase sem sangue: ainda precisa esfregar um pouco
			pr = clampf(progress + px / 250.0, 0.0, 1.0)
		var g0 := maxf(0.0, pr - progress)
		progress = maxf(progress, pr)
		if progress >= 0.985:
			progress = 1.0
		# sangue que insiste em brotar: esfregando sem ganho com quase tudo limpo, conclui
		rub_stall = 0.0 if g0 > 0.0005 else rub_stall + px
		if progress >= 0.8 and rub_stall > 800.0:
			progress = 1.0
		_visual()
		if progress >= 1.0:
			_complete_stage()
		return g0
	if a <= 1.0 and target != null:
		var cov := _paint(target, wpos, brush_r, 0.55 * speed)
		# precisa limpar de verdade quase a área toda (cobertura ponderada >= 84%)
		progress = clampf(cov / 0.84, 0.0, 1.0)
		if progress >= 0.985:
			progress = 1.0
		# sobrou só um restinho que não sai (canto/dobra): esfregando sem ganho, conclui
		if progress - before > 0.0005:
			rub_stall = 0.0
		else:
			rub_stall += px
		if progress >= 0.85 and rub_stall > 800.0:
			progress = 1.0
		var g := progress - before
		_visual()
		if progress >= 1.0:
			_complete_stage()
		return g
	_add(px)
	return 1.0 if px > 0.0 else 0.0

## Corte pintado onde a lâmina passa. Retorna a distância (mundo) até a linha guia.
func has_paint_cut() -> bool:
	return cut_host != null and mech() == Defs.Mech.CUT

## Distância (no plano) do ponto até a linha de corte
func path_dist(wpos: Vector3) -> float:
	var md := INF
	for q in cut_path:
		md = minf(md, Vector2(q.x - wpos.x, q.z - wpos.z).length())
	return md

func cut_stroke(wpos: Vector3, first: bool) -> float:
	var fx: FxMap = cut_host.get_meta("fx")
	if first:
		fx.end_stroke()
	fx.cut_to(host_uv(cut_host, wpos), 2.4 if cut_host is MeshInstance3D and cut_host.has_meta("half") else 3.2)
	var covered := 0
	for g in guide_uv:
		if fx.cut_near(g) > 0.5:
			covered += 1
	var md := INF
	var plen := 0.0
	for i in cut_path.size():
		var q := cut_path[i]
		md = minf(md, Vector2(q.x - wpos.x, q.z - wpos.z).length())
		if i > 0:
			plen += q.distance_to(cut_path[i - 1])
	# um corte simples basta: conta o comprimento cortado perto da linha (qualquer sentido)
	if not first and md < size * 0.6:
		cut_len += minf(wpos.distance_to(last_cut_w), size * 0.5)
	last_cut_w = wpos
	set_cut(maxf(float(covered) / maxf(1.0, guide_uv.size()) / 0.8, cut_len / maxf(0.001, plen * 0.6)))
	return md

## Raio do dedo contra a cúpula (para cortar em cima do furúnculo)
func ray_cut_host(o: Vector3, d: Vector3) -> Array:
	if cut_host == null or cut_host.has_meta("half"):
		return []
	var lo := cut_host.to_local(o)
	var ld := cut_host.global_basis.inverse() * d
	var a := ld.dot(ld)
	var b := 2.0 * lo.dot(ld)
	var c := lo.dot(lo) - 1.0
	var disc := b * b - 4.0 * a * c
	if disc < 0.0:
		return []
	var tt := (-b - sqrt(disc)) / (2.0 * a)
	var lp := lo + ld * tt
	for i in 6:
		var f := MeshGen.bump_profile(Vector2(lp.x, lp.z).length())
		tt += (lp.y - f) / maxf(-ld.y, 0.05)
		lp = lo + ld * tt
	if lp.y < -0.05:
		return []
	return [cut_host.to_global(lp)]

func end_stroke() -> void:
	if cut_host:
		(cut_host.get_meta("fx") as FxMap).end_stroke()

func host_uv(h: Node3D, wpos: Vector3) -> Vector2:
	if h.has_meta("half"):
		var c: Vector3 = h.get_meta("c")
		var rot: float = h.get_meta("rot")
		var half: float = h.get_meta("half")
		var d := Vector2(wpos.x - c.x, wpos.z - c.z)
		return Vector2((d.x * cos(rot) + d.y * sin(rot)) / half, (-d.x * sin(rot) + d.y * cos(rot)) / half)
	var lp := h.to_local(wpos)
	return Vector2(lp.x, lp.z)

func _host_half(h: Node3D) -> float:
	if h.has_meta("half"):
		return h.get_meta("half")
	return h.scale.x

func _add_fx(h: MeshInstance3D) -> FxMap:
	var fx := FxMap.new()
	h.set_meta("fx", fx)
	var m := h.material_override as ShaderMaterial
	m.set_shader_parameter("fx", fx.tex)
	m.set_shader_parameter("fxw", fx.wtex)
	m.set_shader_parameter("use_fx", 1.0)
	# direção "morro abaixo" em pixels do mapa
	var nn := global_basis.y
	var dw := Vector2(nn.x, nn.z)
	if dw.length() < 0.05:
		dw = Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1))
	if h.has_meta("rot"):
		var rot: float = h.get_meta("rot")
		dw = Vector2(dw.x * cos(rot) + dw.y * sin(rot), -dw.x * sin(rot) + dw.y * cos(rot))
	fx.down = dw.normalized() if dw.length() > 0.001 else Vector2(0, 1)
	fx.slope = clampf(Vector2(nn.x, nn.z).length() * 2.0, 0.0, 1.0)
	fx_hosts.append(h)
	return fx

func _set_guide_uv() -> void:
	guide_uv = PackedVector2Array()
	for q in cut_path:
		guide_uv.append(host_uv(cut_host, q))

## Limpa sujeira/pus/sangue que sobrou, mesmo depois da etapa terminar. Retorna o quanto limpou.
func clean_residue(wpos: Vector3, brush_r: float) -> float:
	var gained := 0.0
	for key in ["dirt", "splat", "blood", "grime", "oily", "splat2"]:
		if not n.has(key) or not is_instance_valid(n[key]):
			continue
		var mi: MeshInstance3D = n[key]
		if not mi.has_meta("mask"):
			continue
		var c: Vector3 = mi.get_meta("c")
		var half: float = mi.get_meta("half")
		if Vector2(c.x - wpos.x, c.z - wpos.z).length() > half + brush_r:
			continue
		var mk: CleanMask = mi.get_meta("mask")
		var before := mk.coverage()
		var after := _paint(mi, wpos, brush_r, 0.35)
		gained += maxf(0.0, after - before)
		(mi.material_override as ShaderMaterial).set_shader_parameter("wet", 1.0)
		wet = 1.0
	for h in fx_hosts:
		if is_instance_valid(h):
			var fx: FxMap = h.get_meta("fx")
			var uvp := host_uv(h, wpos)
			if absf(uvp.x) < 1.2 and absf(uvp.y) < 1.2:
				var b0 := fx.blood_at(uvp)
				fx.wipe(uvp, brush_r / _host_half(h) * FxMap.SIZE * 0.5, 0.3)
				gained += b0 * 0.02
	return gained

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

## Barbeador: corta os pelos que a linha das lâminas varreu entre o quadro anterior (a0-b0) e o atual (a1-b1)
func sweep_blade(a0: Vector2, b0: Vector2, a1: Vector2, b1: Vector2, half_w: float, cam: Camera3D) -> int:
	var c := 0
	for it in items:
		if not it["alive"]:
			continue
		var sp := cam.unproject_position(it["pos"])
		var hit := false
		for k in 5:
			var f := k / 4.0
			var q := Geometry2D.get_closest_point_to_segment(sp, a0.lerp(a1, f), b0.lerp(b1, f))
			if q.distance_to(sp) < half_w:
				hit = true
				break
		if hit:
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
	# esfregar por distância (pomada etc.) pede ~15% menos que antes
	progress += x * speed / (amount() * (0.7 if mech() == Defs.Mech.RUB else 1.0))
	# pomada: só termina quando as bolinhas forem espalhadas de verdade
	if tool() == "pomada" and n.has("dollops"):
		progress = minf(progress, 0.15 + cream_spread() * 0.9)
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

## Cor que a ferramenta de limpeza pega ao esfregar
func soil_color() -> Color:
	match id:
		"sujeira": return Color(0.35, 0.24, 0.13)
		"cravos": return Color(0.75, 0.68, 0.4)
		"crosta", "calo": return Color(0.55, 0.35, 0.2)
		"unha_suja": return Color(0.3, 0.2, 0.1)
		"farpa", "pelo_encravado", "carrapato", "verme", "machucado": return Color(0.6, 0.08, 0.1)
		"larvas", "favo":
			return Color(0.8, 0.7, 0.3) if stage == 0 else Color(0.6, 0.1, 0.1)
	return Color(0.9, 0.78, 0.35)

## Partículas durante o HOLD
func hold_color() -> Color:
	var tl := tool()
	if tl == "spray":
		return Color(0.85, 0.95, 1.0, 0.8)
	if tl == "agulha" and id == "queimadura" and progress > 0.05:
		return Color(1, 1, 0.95, 0.6)
	if tl == "espremedor" and progress > 0.3:
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
	mat.set_shader_parameter("tint", pus_tint)
	mat.set_shader_parameter("seed", rng.randf() * 50.0)
	mat.set_shader_parameter("rot", rot)
	mat.set_shader_parameter("half_size", half)
	if use_mask:
		var mk := CleanMask.new()
		# partes do remendo fora da pele (entre os dedos) já contam como limpas
		var cell := CleanMask.SIZE / 24
		for j in 24:
			for i in 24:
				var u := -1.0 + 2.0 * (i + 0.5) / 24.0
				var v := -1.0 + 2.0 * (j + 0.5) / 24.0
				var lx := (u * cos(rot) - v * sin(rot)) * half
				var lz := (u * sin(rot) + v * cos(rot)) * half
				if body.surface(c.x + lx, c.z + lz).is_empty():
					mk.img.fill_rect(Rect2i(i * cell, j * cell, cell, cell), Color(1, 1, 1, 1))
		mk.dirty = true
		mk.flush()
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
	return mk.coverage()

func _lmat(mi: MeshInstance3D) -> ShaderMaterial:
	return mi.material_override as ShaderMaterial

func _lget(key: String, param: String) -> float:
	if n.has(key) and is_instance_valid(n[key]):
		var v = (n[key].material_override as ShaderMaterial).get_shader_parameter(param)
		return v if v != null else 0.0
	return 0.0

func _lset(key: String, param: String, value) -> void:
	if n.has(key) and is_instance_valid(n[key]):
		(n[key].material_override as ShaderMaterial).set_shader_parameter(param, value)

func _dome(kind: int, r: float, h: float, pos := Vector3.ZERO) -> MeshInstance3D:
	var mat := MeshGen.shader_mat(DOME)
	mat.set_shader_parameter("kind", kind)
	mat.set_shader_parameter("skin", skin)
	mat.set_shader_parameter("seed", rng.randf() * 20.0)
	var mi := MeshGen.inst(self, MeshGen.bump(), mat, pos + Vector3(0, -0.003, 0), Vector3(r * 1.25, h, r * 1.25))
	mi.set_meta("base_scale", mi.scale)
	domes.append(mi)
	return mi

## Altura (mundo) do topo dos calombos neste ponto, para a ferramenta pousar em cima e não entrar
func surface_top(wpos: Vector3) -> float:
	var top := -INF
	for d in domes:
		if not is_instance_valid(d) or not d.is_visible_in_tree():
			continue
		var lp: Vector3 = d.global_transform.affine_inverse() * wpos
		var r := Vector2(lp.x, lp.z).length()
		if r >= 1.0:
			continue
		var m := d.material_override as ShaderMaterial
		var dfv = m.get_shader_parameter("deflate") if m else 0.0
		var df: float = dfv if dfv != null else 0.0
		var hy: float = MeshGen.bump_profile(r) * (1.0 - df * 0.75)
		top = maxf(top, d.to_global(Vector3(lp.x, hy, lp.z)).y)
	return top

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

## Raio da ferida que o curativo precisa cobrir
func wound_radius() -> float:
	var k := 1.0
	match id:
		"furunculo", "abscesso", "carbunculo": k = 1.08
		"queimadura", "larvas", "favo", "ralado": k = 1.05
		"bolha", "cisto", "espinha": k = 0.95
		"machucado": k = 1.3
		"pontos": k = 1.0
	if damage > 0:
		k = maxf(k, 1.25)
	# a pomada já cobre a ferida toda: o curativo só precisa tapar o centro (menor, não atrapalha os outros)
	return size * k * 0.68

## Arrancado com a pinça: tranco rápido na direção do puxão, fica preso na pinça e depois cai
func _pluck(nd: Node3D) -> void:
	if nd == null or not is_instance_valid(nd):
		return
	var dirv := (pull_dir + Vector3.UP * 1.3).normalized()
	var start := nd.global_position
	var tw := create_tween()
	tw.tween_property(nd, "global_position", start + dirv * 0.08, 0.06).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(nd, "rotation", nd.rotation + Vector3(rng.randf_range(-0.9, 0.9), 0, rng.randf_range(-0.7, 0.7)), 0.06)
	tw.tween_property(nd, "global_position", start + dirv * 0.11 + Vector3.UP * 0.03, 0.2).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.35)
	tw.tween_property(nd, "global_position", start + dirv * 0.18 + Vector3(0.05, 0.45, 0.1), 0.35).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(nd, "scale", nd.scale * 0.01, 0.35)
	tw.tween_callback(nd.hide)
	Sfx.play("pop", 0.2, -4)
	GameData.vibrate(28, 0.55)

## Curativo adesivo de verdade: fita perfurada + gaze (a gaze cobre a ferida inteira),
## colado acompanhando a pele. manual = vai colando conforme o jogador arrasta (stick()).
func _bandage(r_along: float, r_side: float, at := Vector3.INF, along := Vector3.INF, lift := 0.014, manual := false) -> void:
	if n.has("bandage"):
		return
	var c := global_position if at == Vector3.INF else at
	var fwd := Vector3(1, 0, 0) if along == Vector3.INF else along
	fwd.y = 0.0
	if fwd.length() < 0.01:
		fwd = Vector3(1, 0, 0)
	fwd = fwd.normalized()
	var rot := atan2(fwd.z, fwd.x)
	# gaze ocupa |u| < 0.7 e |v| < aspect*0.82 do adesivo
	var half := maxf(r_along, 0.02) / 0.7
	# não pode cobrir outro machucado que ainda não foi tratado
	for q in body.get_children():
		if q is Problem and q != self and not q.done:
			var qc: Vector3 = q.center()
			var dq: float = Vector2(qc.x - c.x, qc.z - c.z).length() - q.size * 0.9
			half = minf(half, maxf(r_along * 1.12, dq))
	var aspect := clampf(r_side / (0.82 * half), 0.32, 0.95)
	var mi := MeshInstance3D.new()
	mi.mesh = MeshGen.patch(body, c, half, rot, lift, 24)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := MeshGen.shader_mat("res://shaders/bandage.gdshader")
	m.set_shader_parameter("aspect", aspect)
	m.set_shader_parameter("rot", rot)
	m.set_shader_parameter("half_size", half)
	m.set_shader_parameter("unroll", 0.0)
	m.set_shader_parameter("stain", 0.0)
	m.set_shader_parameter("stain_col", Color(0.62, 0.08, 0.1) if _bleedy() else Color(0.85, 0.72, 0.35))
	m.render_priority = 20
	mi.material_override = m
	body.add_child(mi)
	var sp := body.surface(c.x, c.z)
	mi.global_position = sp[0] if not sp.is_empty() else c
	n["bandage"] = mi
	if not manual:
		var tw := create_tween()
		tw.tween_method(func(v): m.set_shader_parameter("unroll", v), 0.0, 1.0, 0.55).set_ease(Tween.EASE_OUT)
		_bandage_done()
	Sfx.play("tap")

func _bleedy() -> bool:
	return id in ["furunculo", "verme", "machucado", "unha_encravada", "larvas", "carbunculo", "abscesso", "pontos", "queimadura"] or damage > 0

## Curativo assentado: a mancha de sangue/pus atravessa a gaze aos poucos
func _bandage_done() -> void:
	if not n.has("bandage"):
		return
	var m: ShaderMaterial = n["bandage"].material_override
	create_tween().tween_method(func(v): m.set_shader_parameter("stain", v), 0.0, 0.55 if _bleedy() else 0.25, 2.5)
	Sfx.play_throttled("scrub", 0.1, 0.1, -12)

## Curativo na unha: cobre a unha toda e a ponta do dedo (levantado acima da unha)
func _nail_bandage(manual := false) -> void:
	var nd: Node3D = nail["node"]
	var at := nd.to_global(Vector3(0, 0, nail["len"] * 0.5))
	_bandage(nail["len"] * 0.62, nail["w"] * 0.66, at, nail["dir"], 0.03, manual)

## Colar o curativo arrastando: f vai de 0 (começo) a 1 (colado até o fim)
func stick(f: float) -> void:
	if done or mech() != Defs.Mech.TAP:
		return
	if not n.has("bandage"):
		if nail.is_empty():
			_bandage(wound_radius(), wound_radius(), _bandage_center(), Vector3.INF, 0.014, true)
		else:
			_nail_bandage(true)
	f = clampf(f, 0.0, 1.0)
	if f <= progress:
		return
	progress = f
	var m: ShaderMaterial = n["bandage"].material_override
	m.set_shader_parameter("unroll", f)
	Sfx.play_throttled("scrub", 0.12, 0.2, -14)
	if f >= 1.0:
		_bandage_done()
		_complete_stage()

func _bandage_center() -> Vector3:
	return center()

func _burst(pos: Vector3, c: Color, amount := 16, spd := 1.0, sz := 0.012, spread := 40.0) -> void:
	var kind := -1
	if c.is_equal_approx(PUS_C):
		kind = L_PUS
	elif c.is_equal_approx(BLOOD_C):
		kind = L_BLOOD
	elif c.a < 0.9 and c.r > 0.9:
		kind = L_FLUID
	if kind >= 0:
		body.spawn_drops(pos, global_basis.y, kind, mini(amount / 2 + 1, 10), spd * 0.9, sz * 0.9, spread / 90.0)
		MeshGen.burst(body, pos, c, amount / 3, spd * 0.8, sz * 0.6, global_basis.y, spread)
	else:
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
		n[key] = MeshGen.inst(self, MeshGen.tube(pts, radii, 10), tube_mat(T_PUS, pus_tint))
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

func _build_pelos(count := -1, len_range := Vector2(0.06, 0.13), extent := Vector2.ZERO, grow := Vector3(1, 0, 0)) -> void:
	if count < 0:
		count = rng.randi_range(230, 300)
	if extent == Vector2.ZERO:
		extent = Vector2(size * 1.25, size * 0.9)
	for i in count:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf())
		var c := global_position + Vector3(cos(a) * d * extent.x, 0, sin(a) * d * extent.y)
		var sp := body.surface(c.x, c.z)
		if sp.is_empty() or body.avoid(c):
			continue
		var root: Vector3 = sp[0]
		var nn: Vector3 = sp[1]
		var g := grow.rotated(Vector3.UP, rng.randf_range(-0.6, 0.6) + (0.25 if body.part == "pe" else 0.0))
		# barba: cresce para baixo e para os lados acompanhando o queixo
		if body.part == "rosto":
			g = (grow + Vector3(0, 0, signf(c.z - body.cam_center.z) * absf(c.z) * 1.4)).normalized().rotated(Vector3.UP, rng.randf_range(-0.35, 0.35))
		g = (g - nn * g.dot(nn)).normalized()
		var L := rng.randf_range(len_range.x, len_range.y)
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
	n["dome"] = MeshGen.inst(holder, MeshGen.bump(), mat, Vector3.ZERO, Vector3(w * 0.36, w * 0.2, nail["len"] * 0.45))
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
	n["swell"] = MeshGen.inst(holder, MeshGen.bump(), mat, Vector3.ZERO, Vector3(w * 0.3, w * 0.2, nail["len"] * 0.65))
	var pm := MeshGen.shader_mat(DOME)
	pm.set_shader_parameter("kind", D_PUSTULE)
	pm.set_shader_parameter("skin", skin)
	n["dome"] = MeshGen.inst(holder, MeshGen.bump(), pm, Vector3(side * 0.008, 0.012, nail["len"] * 0.15), Vector3(w * 0.16, w * 0.12, w * 0.18))
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
		var y := -0.003 + h * MeshGen.bump_profile(x / (r * 1.25)) + 0.003
		pts.append(to_global(Vector3(x, y, 0)))
	_cut_guide(pts)
	n["slit_pts"] = pts
	cut_host = n["dome"]
	_add_fx(n["dome"])
	_set_guide_uv()

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
	cut_host = n["track"]
	_add_fx(n["track"])
	_set_guide_uv()
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

func _build_cisto() -> void:
	n["red"] = _lesion(L_INFLAM, size * 1.4)
	_lmat(n["red"]).set_shader_parameter("strength", 0.5)
	n["dome"] = _dome(D_BUMP, size * 0.8, size * 0.6)
	_lset("dome", "hole", 1.0)
	n["grip"] = n["dome"]

func _build_abscesso() -> void:
	_build_furunculo()
	_lset("dome", "pus_col", Color(0.62, 0.66, 0.2))
	# veias inchadas em volta
	for i in 6:
		var a := i * TAU / 6.0 + rng.randf() * 0.4
		var v := _lesion(L_TRACK, size * 0.9, Vector2(cos(a), sin(a)) * size * 1.2, false, 0.003)
		_lmat(v).set_shader_parameter("strength", 0.45)

func _build_ralado() -> void:
	n["red"] = _lesion(L_INFLAM, size * 1.5)
	n["scrape"] = _lesion(L_SCRAPE, size * 1.15, Vector2.ZERO, false, 0.004)
	n["grime"] = _lesion(L_PUS, size * 1.05, Vector2.ZERO, true, 0.008)
	_lmat(n["grime"]).set_shader_parameter("tint", Color(0.56, 0.46, 0.34))
	_lmat(n["grime"]).set_shader_parameter("strength", 0.55)
	# pedrinhas e terra cravadas no ralado
	for i in rng.randi_range(7, 11):
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * size * 0.75
		var c := global_position + Vector3(cos(a) * d, 0, sin(a) * d)
		var sp := body.surface(c.x, c.z)
		if sp.is_empty():
			continue
		var nd := Node3D.new()
		body.add_child(nd)
		nd.global_position = sp[0]
		var r := rng.randf_range(0.006, 0.013)
		var col := Color(0.35, 0.32, 0.3).lerp(Color(0.5, 0.38, 0.25), rng.randf())
		var st := MeshGen.inst(nd, MeshGen.sphere(1.0), MeshGen.std(col, 0.95), Vector3(0, r * 0.2, 0), Vector3(r, r * 0.7, r * rng.randf_range(0.7, 1.3)))
		st.rotation = Vector3(rng.randf(), rng.randf() * TAU, rng.randf())
		items.append({"node": nd, "pos": sp[0], "alive": true})
	items_left = items.size()

func _build_bicho_pe() -> void:
	n["red"] = _lesion(L_INFLAM, size * 1.5)
	n["dome"] = _dome(D_BUMP, size * 0.7, size * 0.4)
	_lset("dome", "skin", skin.lerp(Color(1.0, 0.95, 0.8), 0.45))
	_lset("dome", "hole", 1.0)
	var sac := Node3D.new()
	add_child(sac)
	sac.position = Vector3(0, -0.006, 0)
	MeshGen.inst(sac, MeshGen.sphere(1.0), MeshGen.std(Color(0.96, 0.92, 0.8), 0.3), Vector3.ZERO, Vector3(0.016, 0.014, 0.016))
	MeshGen.inst(sac, MeshGen.sphere(1.0), MeshGen.std(Color(0.15, 0.08, 0.05), 0.4), Vector3(0, 0.013, 0), Vector3.ONE * 0.004)
	n["sac"] = sac
	n["grip"] = sac

func _build_espinhos() -> void:
	n["red"] = _lesion(L_INFLAM, size * 1.4)
	_lmat(n["red"]).set_shader_parameter("strength", 0.6)
	var tm := tube_mat(T_WOOD, Color(1.5, 1.4, 0.95))
	for i in rng.randi_range(9, 15):
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * size * 0.85
		var c := global_position + Vector3(cos(a) * d, 0, sin(a) * d)
		var sp := body.surface(c.x, c.z)
		if sp.is_empty():
			continue
		var nd := Node3D.new()
		body.add_child(nd)
		nd.global_position = sp[0]
		nd.global_basis = MeshGen.basis_from_normal(sp[1]).rotated(sp[1], rng.randf() * TAU)
		var L := rng.randf_range(0.03, 0.06)
		var tilt := Vector3(rng.randf_range(0.3, 0.9), 1.0, rng.randf_range(-0.3, 0.3)).normalized()
		var pts := PackedVector3Array([-tilt * 0.008, tilt * L * 0.5, tilt * L])
		MeshGen.inst(nd, MeshGen.tube(pts, PackedFloat32Array([0.0022, 0.0016, 0.0004]), 5), tm)
		MeshGen.inst(nd, MeshGen.sphere(1.0), MeshGen.std(Color(0.7, 0.12, 0.12), 0.4), Vector3.ZERO, Vector3(0.006, 0.002, 0.006))
		items.append({"node": nd, "pos": sp[0], "alive": true})
	items_left = items.size()

func _build_unha_roxa() -> void:
	_nail_basics()
	var mat: ShaderMaterial = nail["mat"]
	mat.set_shader_parameter("hematoma", 1.0)

func _build_verruga() -> void:
	n["red"] = _lesion(L_INFLAM, size * 1.2)
	_lmat(n["red"]).set_shader_parameter("strength", 0.4)
	n["dome"] = _dome(D_WART, size * 0.72, size * 0.5)

## Ponto da superfície perto do centro (deslocamento no plano) -> [pos, normal] ou []
func _surf_near(off: Vector2) -> Array:
	var c := global_position + Vector3(off.x, 0, off.y)
	return body.surface(c.x, c.z)

func _build_carbunculo() -> void:
	_build_furunculo()
	_lset("red", "strength", 1.35)
	_lset("dome", "pus_col", Color(0.86, 0.78, 0.3))
	# várias cabeças de pus espalhadas pelo caroço
	var r := size * 0.8
	var h := size * 0.55
	n["heads"] = []
	var hm := MeshGen.std(Color(0.97, 0.88, 0.5), 0.2, 0.0, "carb_head")
	for i in rng.randi_range(5, 7):
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * r * 0.75
		var lp := Vector3(cos(a) * d, 0, sin(a) * d)
		lp.y = h * MeshGen.bump_profile(Vector2(lp.x, lp.z).length() / (r * 1.25)) - 0.002
		var rr := size * rng.randf_range(0.07, 0.12)
		var hd := MeshGen.inst(self, MeshGen.sphere(1.0), hm, lp, Vector3(rr, rr * 0.55, rr))
		n["heads"].append(hd)
	for i in 8:
		var a2 := i * TAU / 8.0 + rng.randf() * 0.4
		var v := _lesion(L_TRACK, size * 0.8, Vector2(cos(a2), sin(a2)) * size * 1.25, false, 0.003)
		_lmat(v).set_shader_parameter("strength", 0.5)

func _build_acne_costas() -> void:
	n["red"] = _lesion(L_INFLAM, size * 1.35)
	_lmat(n["red"]).set_shader_parameter("strength", 0.75)
	n["oily"] = _lesion(L_OILY, size * 1.25, Vector2.ZERO, false, 0.004)
	_lmat(n["oily"]).set_shader_parameter("strength", 0.6)
	var dark := MeshGen.std(Color(0.1, 0.07, 0.05), 0.4, 0.0, "blackhead")
	var ring := MeshGen.std(Color(0.78, 0.25, 0.22), 0.55, 0.0, "acne_ring")
	for i in rng.randi_range(14, 19):
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * size
		var sp := _surf_near(Vector2(cos(a), sin(a)) * d)
		if sp.is_empty():
			continue
		var nd := Node3D.new()
		body.add_child(nd)
		nd.global_position = sp[0]
		nd.global_basis = MeshGen.basis_from_normal(sp[1])
		var rr := rng.randf_range(0.018, 0.036)
		# base vermelha inchada + cabeça amarela de pus
		MeshGen.inst(nd, MeshGen.sphere(1.0), ring, Vector3(0, -0.003, 0), Vector3(rr * 1.7, rr * 0.45, rr * 1.7))
		var mat := MeshGen.shader_mat(DOME)
		mat.set_shader_parameter("kind", D_PUSTULE)
		mat.set_shader_parameter("skin", skin.lerp(Color(0.85, 0.3, 0.25), 0.5))
		MeshGen.inst(nd, MeshGen.sphere(1.0), mat, Vector3(0, -0.001, 0), Vector3(rr, rr * 0.85, rr))
		items.append({"node": nd, "pos": sp[0], "alive": true, "r": rr})
	# cravos espalhados no meio (enfeite nojento)
	for i in rng.randi_range(8, 12):
		var a2 := rng.randf() * TAU
		var sp2 := _surf_near(Vector2(cos(a2), sin(a2)) * sqrt(rng.randf()) * size * 1.1)
		if sp2.is_empty():
			continue
		MeshGen.inst(body, MeshGen.sphere(1.0), dark, sp2[0], Vector3(0.0055, 0.002, 0.0055))
	items_left = items.size()

func _build_queimadura() -> void:
	n["red"] = _lesion(L_INFLAM, size * 1.7)
	_lmat(n["red"]).set_shader_parameter("strength", 1.3)
	n["burn"] = _lesion(L_SCRAPE, size * 1.2, Vector2.ZERO, false, 0.005)
	n["blisters"] = []
	for i in rng.randi_range(4, 6):
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * size * 0.7
		var sp := _surf_near(Vector2(cos(a), sin(a)) * d)
		if sp.is_empty():
			continue
		var r := size * rng.randf_range(0.17, 0.32)
		var bl := _dome(D_BLISTER, r, r * rng.randf_range(0.55, 0.85), to_local(sp[0]))
		n["blisters"].append(bl)
	# pele morta soltando (pedaços para tirar com a pinça)
	var dead := MeshGen.std(skin.lerp(Color(0.97, 0.94, 0.88), 0.55), 0.75, 0.0, "burn_flap_%s" % skin.to_html())
	for i in rng.randi_range(5, 7):
		var a2 := rng.randf() * TAU
		var sp2 := _surf_near(Vector2(cos(a2), sin(a2)) * rng.randf_range(0.4, 1.0) * size)
		if sp2.is_empty():
			continue
		var nd := Node3D.new()
		body.add_child(nd)
		nd.global_position = sp2[0]
		nd.global_basis = MeshGen.basis_from_normal(sp2[1]).rotated(sp2[1], rng.randf() * TAU)
		var rr := rng.randf_range(0.018, 0.032)
		MeshGen.inst(nd, MeshGen.sphere(1.0), dead, Vector3(0, 0.002, 0), Vector3(rr, 0.0022, rr * 0.7))
		# borda enrolada da pele
		var pts := PackedVector3Array()
		for k in 6:
			var t2 := -1.0 + 2.0 * k / 5.0
			pts.append(Vector3(rr * 0.95, 0.004 + 0.004 * (1.0 - t2 * t2), t2 * rr * 0.6))
		MeshGen.inst(nd, MeshGen.tube(pts, PackedFloat32Array([0.0025]), 5), dead)
		items.append({"node": nd, "pos": sp2[0], "alive": true})
	items_left = items.size()

func _build_pontos() -> void:
	n["red"] = _lesion(L_INFLAM, size * 1.5)
	_lmat(n["red"]).set_shader_parameter("strength", 0.95)
	var host := _lesion(L_INFLAM, size * 1.3, Vector2.ZERO, false, 0.006)
	_lmat(host).set_shader_parameter("strength", 0.0)
	_lmat(host).set_shader_parameter("scar", 0.55)
	n["cut"] = host
	var fx := _add_fx(host)
	var ang := rng.randf() * TAU
	var dirv := Vector3(cos(ang), 0, sin(ang))
	n["dir"] = dirv
	var L := size * 1.7
	for k in 25:
		var wp := global_position + dirv * (float(k) / 24.0 - 0.5) * L
		fx.cut_to(host_uv(host, wp), 2.6, 1.0)
	fx.end_stroke()
	fx.bleed = 0.0
	fx.flush()
	n["splat"] = _lesion(L_PUS, size * 0.6, Vector2.ZERO, true, 0.008)
	_lmat(n["splat"]).set_shader_parameter("strength", 0.5)
	var thread := MeshGen.std(Color(0.06, 0.06, 0.1), 0.35, 0.0, "stitch")
	var perp := dirv.cross(Vector3.UP).normalized()
	var cnt := rng.randi_range(5, 7)
	for i in cnt:
		var t2 := (float(i) + 0.5) / cnt - 0.5
		var sp := body.surface(global_position.x + dirv.x * t2 * L * 0.9, global_position.z + dirv.z * t2 * L * 0.9)
		if sp.is_empty():
			continue
		var nd := Node3D.new()
		body.add_child(nd)
		nd.global_position = sp[0]
		var w := size * rng.randf_range(0.2, 0.28)
		var pts := PackedVector3Array()
		for k in 7:
			var s := -1.0 + 2.0 * k / 6.0
			pts.append(perp * s * w + Vector3.UP * (0.006 * (1.0 - s * s) + 0.002))
		MeshGen.inst(nd, MeshGen.tube(pts, PackedFloat32Array([0.0024]), 5), thread)
		MeshGen.inst(nd, MeshGen.sphere(1.0), thread, perp * w + Vector3.UP * 0.003, Vector3.ONE * 0.0045)
		# crosta amarela em volta de cada ponto
		MeshGen.inst(nd, MeshGen.sphere(1.0), MeshGen.std(Color(0.85, 0.7, 0.3), 0.3, 0.0, "stitch_crust"), -perp * w, Vector3(0.007, 0.003, 0.007))
		items.append({"node": nd, "pos": sp[0], "alive": true})
	items_left = items.size()

func _build_piolhos() -> void:
	n["red"] = _lesion(L_INFLAM, size * 1.3)
	_lmat(n["red"]).set_shader_parameter("strength", 0.65)
	n["blood"] = _lesion(L_BLOOD, size * 1.05, Vector2.ZERO, true, 0.009)
	_lmat(n["blood"]).set_shader_parameter("strength", 0.45)
	var louse := MeshGen.std(Color(0.5, 0.38, 0.26), 0.35, 0.0, "louse")
	var dark := MeshGen.std(Color(0.22, 0.13, 0.08), 0.35, 0.0, "louse_d")
	for i in rng.randi_range(6, 9):
		var a := rng.randf() * TAU
		var sp := _surf_near(Vector2(cos(a), sin(a)) * sqrt(rng.randf()) * size * 0.8)
		if sp.is_empty():
			continue
		var nd := Node3D.new()
		body.add_child(nd)
		var k := rng.randf_range(0.8, 1.25)
		MeshGen.inst(nd, MeshGen.sphere(1.0), louse, Vector3(0, 0.005, -0.006) * k, Vector3(0.008, 0.004, 0.012) * k)
		MeshGen.inst(nd, MeshGen.sphere(1.0), dark, Vector3(0, 0.005, -0.008) * k, Vector3(0.004, 0.0035, 0.006) * k)
		MeshGen.inst(nd, MeshGen.sphere(1.0), louse, Vector3(0, 0.004, 0.009) * k, Vector3(0.005, 0.0035, 0.005) * k)
		var legs := []
		for side in [-1.0, 1.0]:
			for j in 3:
				var leg := Node3D.new()
				nd.add_child(leg)
				leg.position = Vector3(side * 0.005, 0.004, 0.004 - j * 0.004) * k
				MeshGen.inst(leg, MeshGen.tube(PackedVector3Array([Vector3.ZERO, Vector3(side * 0.006, 0.002, 0.002), Vector3(side * 0.01, -0.003, 0.003)]), PackedFloat32Array([0.0012, 0.001, 0.0008]), 4), dark)
				legs.append(leg)
		items.append({"node": nd, "pos": sp[0], "alive": true, "head": rng.randf() * TAU, "legs": legs, "spd": rng.randf_range(0.012, 0.025)})
	items_left = items.size()
	_place_lice(0.0)
	# lêndeas: ovinhos brancos grudados
	n["crumbs"] = []
	var nit := MeshGen.std(Color(0.95, 0.93, 0.85), 0.4, 0.0, "nit")
	for i in rng.randi_range(28, 40):
		var a2 := rng.randf() * TAU
		var sp2 := _surf_near(Vector2(cos(a2), sin(a2)) * sqrt(rng.randf()) * size * 1.1)
		if sp2.is_empty():
			continue
		var mi := MeshGen.inst(body, MeshGen.sphere(1.0), nit, sp2[0] + sp2[1] * 0.003, Vector3(0.003, 0.0025, 0.0048))
		mi.rotation.y = rng.randf() * TAU
		mi.set_meta("th", rng.randf() * 0.75)
		n["crumbs"].append(mi)

## Piolhos andando devagar pelo couro cabeludo (dá para pegar, mas fogem um pouco)
func _place_lice(delta: float) -> void:
	for it in items:
		if not it["alive"]:
			continue
		var nd: Node3D = it["node"]
		it["head"] += rng.randf_range(-1.0, 1.0) * delta * 4.0
		var dirv := Vector3(cos(it["head"]), 0, sin(it["head"]))
		var p: Vector3 = it["pos"] + dirv * it["spd"] * delta
		var off := Vector2(p.x - global_position.x, p.z - global_position.z)
		if off.length() > size * 0.85:
			it["head"] = atan2(-off.y, -off.x)
		var sp := body.surface(p.x, p.z)
		if sp.is_empty():
			it["head"] += PI
			continue
		it["pos"] = sp[0]
		nd.global_position = sp[0]
		nd.global_basis = MeshGen.basis_from_normal(sp[1], dirv)
		var legs: Array = it["legs"]
		for j in legs.size():
			(legs[j] as Node3D).rotation.y = sin(t * 18.0 + j * 1.7) * 0.35

func _build_caspa() -> void:
	n["red"] = _lesion(L_INFLAM, size * 1.25)
	_lmat(n["red"]).set_shader_parameter("strength", 0.45)
	# placas amareladas grossas e oleosas
	n["crust"] = _lesion(L_CALLUS, size * 1.1, Vector2.ZERO, true, 0.007)
	n["crumbs"] = []
	var flake := MeshGen.std(Color(0.96, 0.95, 0.9), 0.85, 0.0, "flake")
	var yel := MeshGen.std(Color(0.9, 0.84, 0.6), 0.5, 0.0, "flake_y")
	for i in rng.randi_range(35, 50):
		var a := rng.randf() * TAU
		var sp := _surf_near(Vector2(cos(a), sin(a)) * sqrt(rng.randf()) * size * 1.25)
		if sp.is_empty():
			continue
		var r := rng.randf_range(0.005, 0.013)
		var mi := MeshGen.inst(body, MeshGen.sphere(1.0), flake if rng.randf() < 0.7 else yel, sp[0] + sp[1] * rng.randf_range(0.002, 0.012), Vector3(r, 0.0016, r * rng.randf_range(0.5, 1.0)))
		mi.rotation = Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, rng.randf_range(-0.4, 0.4))
		mi.set_meta("th", rng.randf() * 0.8)
		n["crumbs"].append(mi)

func _build_barba() -> void:
	# barba cheia: queixo, mandíbula e bigode (a boca fica livre)
	global_position = Vector3(-0.92, global_position.y, 0.0)
	var sp := body.surface(-0.92, 0.0)
	if not sp.is_empty():
		global_position = sp[0]
	_build_pelos(rng.randi_range(780, 900), Vector2(0.04, 0.085), Vector2(size * 1.15, size * 2.3), Vector3(-1, 0, 0))

func _build_machucado() -> void:
	n["wound"] = _lesion(L_INFLAM, size * 2.2, Vector2.ZERO, true, 0.004)
	_lmat(n["wound"]).set_shader_parameter("strength", 0.35)
	cut_host = n["wound"]
	_add_fx(n["wound"])
	n["blood"] = n["wound"]

## Ferramenta errada EM CIMA do problema: piora ali mesmo (corta/esfola, sangra, inflama)
## e cobra trabalho extra: limpar o sangue (e curativo, se tiver). Retorna true no 1º dano do toque.
var blunt_kind := ""   # ferramenta sem corte que está estragando (lixa esfola; outras apertam)

func aggravate(wpos: Vector3, sharp: bool, first: bool) -> bool:
	if done:
		return false
	var fresh := first
	if not n.has("aggr"):
		var host := _lesion(L_INFLAM, size * 1.9, Vector2.ZERO, false, 0.011)
		_lmat(host).set_shader_parameter("strength", 0.0)
		# o estrago fica por cima da ferida original
		_lmat(host).render_priority = 4
		n["aggr"] = host
		var fx := _add_fx(host)
		fx.bleed = 0.0
	var host2: MeshInstance3D = n["aggr"]
	var fx2: FxMap = host2.get_meta("fx")
	var uv := host_uv(host2, wpos)
	if absf(uv.x) > 0.92 or absf(uv.y) > 0.92:
		return false
	if first:
		fx2.end_stroke()
		damage += 1
		_add_extra_stages()
		# mais inchado e vermelho a cada erro
		var st := minf(1.0, 0.25 * damage)
		_lmat(host2).set_shader_parameter("strength", st)
		if n.has("red") and is_instance_valid(n["red"]):
			var m := _lmat(n["red"])
			var cur = m.get_shader_parameter("strength")
			m.set_shader_parameter("strength", minf(1.6, (cur if cur != null else 1.0) + 0.25))
		if n.has("dome") and is_instance_valid(n["dome"]):
			var d: MeshInstance3D = n["dome"]
			var bs: Vector3 = d.get_meta("base_scale", d.scale)
			d.set_meta("base_scale", bs * Vector3(1.06, 1.1, 1.06))
			d.scale = d.get_meta("base_scale")
	if sharp:
		fx2.cut_to(uv, 2.8, 1.0)
		fx2.bleed = minf(1.0, fx2.bleed + 0.12)
	elif blunt_kind == "lixa":
		# esfolado pequeno: arranha a pele e brotam pontinhos de sangue
		fx2.add_blood(uv + Vector2(randf_range(-0.03, 0.03), randf_range(-0.03, 0.03)), 2.2, 0.05)
		fx2.cut_to(uv, 2.4, 0.18)
		fx2.bleed = minf(0.35, fx2.bleed + 0.015)
	else:
		# apertou/beliscou: fica roxo e vermelho, quase sem sangue
		_lmat(host2).set_shader_parameter("strength", minf(1.2, 0.35 + 0.25 * damage))
		fx2.add_blood(uv, 1.6, 0.03)
	return fresh

## A ferramenta já foi usada numa etapa anterior deste problema (continuar não machuca)
func used_tool(t: String) -> bool:
	var st: Array = def["stages"]
	var upto := st.size() if done else stage
	for i in upto:
		if st[i][0] == t:
			return true
	return false

## Continuar usando uma ferramenta de etapa já feita: ainda faz um efeito leve e satisfatório
func after_effect(wpos: Vector3, t: String) -> bool:
	match t:
		"pomada":
			_spread_cream(wpos, 0.06, false)
		"lixa", "raspador":
			for key in ["callus", "crust"]:
				if n.has(key) and is_instance_valid(n[key]):
					var m := _lmat(n[key])
					var hv = m.get_shader_parameter("heal")
					m.set_shader_parameter("heal", minf(1.0, (hv if hv != null else 0.0) + 0.004))
		"espremedor":
			if id in ["espinha", "cisto", "furunculo", "abscesso", "carbunculo", "unha_pus", "acne_costas"] and rng.randf() < 0.08:
				_burst(wpos + Vector3.UP * 0.01, PUS_C, 2, 0.3, 0.005, 30.0)
		"pano", "algodao", "lamina":
			pass
		_:
			return false
	return true

## Depois de piorar: precisa limpar o sangue (e fechar com curativo, se tiver)
func _add_extra_stages() -> void:
	if def.has("_aggr"):
		return
	def = def.duplicate(true)
	def["_aggr"] = true
	var st: Array = def["stages"]
	var before := st.size()
	# entra antes do curativo final (se ainda não chegou nele) ou no fim — nunca no meio,
	# para não mexer na numeração das etapas originais
	var last := st.size() - 1
	if st[last][0] == "curativo" and last > stage:
		st.insert(last, ["algodao", Defs.Mech.RUB, 0.75, "aggr"])
	else:
		st.append(["algodao", Defs.Mech.RUB, 0.75, "aggr"])
		if GameData.owned.has("curativo"):
			st.append(["curativo", Defs.Mech.TAP, 1.0, "aggr"])
	extra_stages.emit(self, st.size() - before)

func _aggr_stage() -> bool:
	return not done and def["stages"][stage].size() > 3 and def["stages"][stage][3] == "aggr"

const DOLLOPS := 4

## Pomada em 2 tempos: primeiro aperta bolinhas de creme sobre a ferida, depois espalha
func cream_ready() -> bool:
	return n.get("dollops", []).size() >= DOLLOPS

## Quanto das bolinhas de pomada já foi espalhado (0..1)
func cream_spread() -> float:
	var dl: Array = n.get("dollops", [])
	if dl.is_empty():
		return 0.0
	var s := 0.0
	for b in dl:
		var nd: Node3D = b
		var full: Vector3 = nd.get_meta("full")
		s += 1.0 if not nd.visible else clampf(1.0 - (nd.scale.y / full.y - 0.22) / 0.78, 0.0, 1.0)
	return s / DOLLOPS

func cream_hint() -> String:
	if not cream_ready():
		return "Aperte a pomada sobre a ferida (%d/%d)" % [n.get("dollops", []).size(), DOLLOPS]
	return "Agora ESPALHE a pomada por toda a ferida!"

func _add_dollop(wpos: Vector3) -> void:
	var sp := body.surface(wpos.x, wpos.z)
	if sp.is_empty():
		return
	var dl: Array = n.get("dollops", [])
	n["dollops"] = dl
	var mi := MeshInstance3D.new()
	mi.mesh = MeshGen.sphere(1.0)
	var mat := MeshGen.std(Color(0.98, 0.97, 0.94), 0.18, 0.0, "cream_dollop")
	mat.metallic_specular = 0.8
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)
	mi.global_position = sp[0] + sp[1] * 0.004
	mi.global_basis = MeshGen.basis_from_normal(sp[1]).rotated(sp[1], rng.randf() * TAU)
	var r := clampf(size * 0.2, 0.014, 0.03)
	mi.scale = Vector3.ONE * 0.001
	mi.set_meta("full", Vector3(r, r * 0.75, r * 1.15))
	create_tween().tween_property(mi, "scale", mi.get_meta("full"), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	dl.append(mi)
	Sfx.play("squish", 0.3, -10)
	GameData.vibrate(12, 0.3)

## Pomada: camada branca que aparece onde se espalha (fica por baixo do curativo)
func _spread_cream(wpos: Vector3, brush_r: float, apply := true) -> void:
	var dl: Array = n.get("dollops", [])
	if apply and dl.size() < DOLLOPS and not done:
		if dl.is_empty() or (dl[dl.size() - 1] as Node3D).global_position.distance_to(wpos) > maxf(size * 0.3, 0.025):
			_add_dollop(wpos)
		return
	# espalhando: as bolinhas achatam e viram a camada
	for b in dl:
		var nd: Node3D = b
		if nd.visible and nd.global_position.distance_to(wpos) < brush_r * 1.7:
			var full: Vector3 = nd.get_meta("full")
			nd.scale = Vector3(minf(nd.scale.x * 1.025, full.x * 1.6), nd.scale.y * 0.9, minf(nd.scale.z * 1.025, full.z * 1.6))
			if nd.scale.y < full.y * 0.22:
				nd.hide()
	if not n.has("cream"):
		var cr := _lesion(L_CREAM, maxf(size * 1.35, 0.06), Vector2.ZERO, true, 0.0095)
		var mk: CleanMask = cr.get_meta("mask")
		mk.img.fill(Color(0, 0, 0, 1))
		mk.dirty = true
		mk.flush()
		_lmat(cr).render_priority = 2
		n["cream"] = cr
	_paint(n["cream"], wpos, brush_r * 1.6, 0.6 * speed)

## Corte feito pelo jogador (erro) — pintado onde arrastou
func wound_stroke(wpos: Vector3, first: bool) -> void:
	var fx: FxMap = cut_host.get_meta("fx")
	if first:
		fx.end_stroke()
	if blunt_kind == "lixa":
		# arranhão de lixa: raso e com pontinhos de sangue
		var uv := host_uv(cut_host, wpos)
		fx.cut_to(uv, 2.6, 0.22)
		fx.add_blood(uv + Vector2(randf_range(-0.04, 0.04), randf_range(-0.04, 0.04)), 2.0, 0.08)
		fx.bleed = maxf(fx.bleed, 0.3)
		return
	fx.cut_to(host_uv(cut_host, wpos), 3.4)
	fx.bleed = 1.0

# =================================================================== animação contínua

func _process(delta: float) -> void:
	t += delta
	for h in fx_hosts:
		if is_instance_valid(h):
			var fx: FxMap = h.get_meta("fx")
			fx.step(delta)
			var m := h.material_override as ShaderMaterial
			var cur = m.get_shader_parameter("open_amt")
			var target := 0.85 if fx.cut_pts.size() > 3 else 0.0
			m.set_shader_parameter("open_amt", lerpf(cur if cur != null else 0.0, target, delta * 1.5))
	if wet > 0.0:
		wet = maxf(0.0, wet - delta * 0.35)
		for key in ["dirt", "splat", "blood", "grime", "oily", "crust", "callus", "wound"]:
			if n.has(key) and is_instance_valid(n[key]) and n[key] is MeshInstance3D:
				(n[key].material_override as ShaderMaterial).set_shader_parameter("wet", wet)
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
		"pelos", "barba":
			if _hair_dirty:
				_hair_dirty = false
				_rebuild_hairs()
		"piolhos":
			_place_lice(delta)

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
		"espinha", "cisto", "furunculo", "abscesso", "carbunculo", "unha_pus", "unha_encravada", "unha_roxa": return n.get("splat")
		"acne_costas", "pontos": return n.get("splat") if stage == 1 else null
		"piolhos": return n.get("blood") if stage == 1 else null
		"caspa": return n.get("crust") if stage == 0 else null
		"ralado": return n.get("grime") if stage == 1 else null
		"bicho_pe", "espinhos": return n.get("blood")
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
func rub_nail(wpos: Vector3, brush_r: float) -> float:
	if not n.has("mask") or nail.is_empty():
		return 0.0
	var a := amount()
	if a > 1.0:
		return 0.0
	var before := progress
	var nd: Node3D = nail["node"]
	var lp := nd.to_local(wpos)
	var w: float = nail["w"]
	var L: float = nail["len"]
	var u := lp.x / (w * 0.5)
	var v := lp.z / L
	var mk: CleanMask = n["mask"]
	mk.paint(Vector2(u, v / 1.6 * 2.0 - 1.0), brush_r / (w * 0.5), 0.6 * speed)
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
	progress = clampf(cov / cnt / 0.86, 0.0, 1.0)
	# as bordas da unha (cutícula/cantos) quase não pegam o pincel: não exige 100%
	if progress >= 0.95:
		progress = 1.0
	var g := progress - before
	_visual()
	if progress >= 1.0:
		_complete_stage()
	return g

func uses_nail_mask() -> bool:
	return (id == "unha_suja" and stage == 1) or (id == "fungo_unha" and stage == 0)

func _visual() -> void:
	var p := clampf(progress, 0.0, 1.0)
	var tl := tool()
	if _aggr_stage():
		return
	match id:
		"espinha", "cisto":
			if stage == 1:
				_squeeze_dome(p, 0.75)
			elif stage == 0:
				_lset("dome", "swell", p * 0.15)
		"bolha":
			if stage == 0:
				_lset("dome", "swell", p * 0.1)
		"ralado":
			if stage == 2:
				_lset("scrape", "heal", p * 0.8)
				_lset("red", "heal", p * 0.5)
		"bicho_pe":
			if stage == 0:
				_lset("dome", "swell", p * 0.25)
			elif stage == 1:
				n["sac"].position.y = -0.006 + p * 0.03
				n["sac"].scale = Vector3.ONE * (1.0 + p * 0.25)
		"unha_roxa":
			if stage == 0:
				(nail["mat"] as ShaderMaterial).set_shader_parameter("hematoma", 1.0 - p * 0.15)
		"farpa":
			if stage == 0:
				n["splinter"].position = n["dir"] * p * 0.1
		"sujeira":
			for c in n["crumbs"]:
				if is_instance_valid(c) and c.visible and p > c.get_meta("th"):
					_fly_off(c)
		"caspa", "piolhos":
			if (id == "caspa" and stage == 0) or (id == "piolhos" and stage == 1):
				for c in n["crumbs"]:
					if is_instance_valid(c) and c.visible and p > c.get_meta("th"):
						_fly_off(c)
			if stage == 1:
				_lset("red", "heal", p * 0.7)
		"queimadura":
			if stage == 0:
				for bl in n["blisters"]:
					var d: MeshInstance3D = bl
					var bs: Vector3 = d.get_meta("base_scale")
					(d.material_override as ShaderMaterial).set_shader_parameter("deflate", p)
					d.scale = Vector3(bs.x * (1.0 + p * 0.05), bs.y * (1.0 - p * 0.65), bs.z * (1.0 + p * 0.05))
				if rng.randf() < 0.25:
					var bl2: MeshInstance3D = n["blisters"].pick_random()
					_burst(bl2.global_position + Vector3.UP * 0.01, Color(1, 1, 0.95, 0.7), 2, 0.3, 0.006, 60.0)
			elif stage == 2:
				_lset("burn", "heal", p * 0.6)
				_lset("red", "heal", p * 0.5)
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
				# raiz branca (bulbo) aparecendo conforme sai
				MeshGen.inst(hair, MeshGen.sphere(1.0), MeshGen.std(Color(0.97, 0.95, 0.9), 0.4, 0.0, "bulb"), pts[0], Vector3(0.0045, 0.006, 0.0045))
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
			if stage == 0:
				var nm: ShaderMaterial = nail["mat"]
				nm.set_shader_parameter("groove_at", 1.02)
				nm.set_shader_parameter("groove_prog", p)
				nm.set_shader_parameter("groove_dir", cut_dir)
				nm.set_shader_parameter("lift_amt", nail["len"] * 0.45)
		"unha_pus":
			if stage == 1:
				_squeeze_dome(p, 0.8)
		"fungo_unha":
			if stage == 0:
				n["thick"].scale = Vector3(1.0, lerpf(2.2, 1.0, p), 1.0)
		"furunculo", "abscesso", "carbunculo":
			match stage:
				0:
					_lset("red", "strength", 1.0)
					pass
				1:
					_squeeze_dome(p, 0.85)
					if n.has("heads"):
						var hs: Array = n["heads"]
						for i in hs.size():
							var hd: MeshInstance3D = hs[i]
							if hd.visible and p > (i + 1.0) / (hs.size() + 1.0):
								hd.hide()
								_burst(hd.global_position, PUS_C, 8, 0.8, 0.008, 35.0)
								body.spawn_drops(hd.global_position + Vector3.UP * 0.01, Vector3.UP, 2, 3, 0.7, 0.007, 0.6)
								Sfx.play("squish", 0.3)
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
	if tl == "pomada" and p > 0.0 and not id in ["ralado", "queimadura", "crosta", "calo", "verruga", "larvas", "favo", "fungo_unha"]:
		_lset("red", "heal", maxf(_lget("red", "heal"), p * 0.45))
	if tl == "pomada" and p > 0.0:
		if rng.randf() < 0.3:
			_burst(center() + Vector3(rng.randf_range(-size, size), 0.01, rng.randf_range(-size, size)) * Vector3(1, 1, 1), Color(1, 1, 1), 2, 0.1, 0.008, 80.0)

func _deflate(key: String, dur: float) -> void:
	if not n.has(key) or not is_instance_valid(n[key]):
		return
	var d: MeshInstance3D = n[key]
	var m := d.material_override as ShaderMaterial
	var bs: Vector3 = d.get_meta("base_scale", d.scale)
	var tw := create_tween().set_parallel()
	tw.tween_method(func(v): m.set_shader_parameter("deflate", v), 0.5, 1.0, dur)
	tw.tween_property(d, "scale", Vector3(bs.x * 0.85, bs.y * 0.6, bs.z * 0.85), dur)

func _squeeze_dome(p: float, max_shrink: float) -> void:
	if not n.has("dome") or not is_instance_valid(n["dome"]):
		return
	var d: MeshInstance3D = n["dome"]
	var m := d.material_override as ShaderMaterial
	var bs: Vector3 = d.get_meta("base_scale", d.scale)
	var pulse := 1.0 + sin(t * 30.0) * 0.03
	# 1º a pressão estufa e clareia o caroço; depois o pus sai e ele murcha
	var build := clampf(p / 0.3, 0.0, 1.0)
	var out := clampf((p - 0.3) / 0.7, 0.0, 1.0)
	var up := 1.0 + 0.35 * build * (1.0 - out)
	m.set_shader_parameter("swell", 0.12 * build * (1.0 - out))
	m.set_shader_parameter("deflate", out * 0.5)
	d.scale = Vector3(bs.x * (1.0 - out * max_shrink * 0.4) * pulse, bs.y * up * (1.0 - out * max_shrink), bs.z * (1.0 - out * max_shrink * 0.4) * pulse)

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
		"pelos", "barba":
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
		"ralado":
			_fly_off(it["node"])
			_burst(it["pos"], BLOOD_C, 3, 0.3, 0.005, 40.0)
			Sfx.play("pull", 0.3, -6)
		"espinhos":
			_fly_off(it["node"])
			_burst(it["pos"], BLOOD_C, 2, 0.25, 0.004, 40.0)
			Sfx.play("pull", 0.3, -8)
		"acne_costas":
			# espremida: a cabeça estoura, o pus sai em fio e voa gotinha
			var nd3: Node3D = it["node"]
			var rr: float = it.get("r", 0.016)
			var plug3 := MeshGen.inst(nd3, MeshGen.tube(PackedVector3Array([Vector3.ZERO, Vector3(0.002, rr * 1.2, 0), Vector3(rr * 0.8, rr * 2.0, 0.003)]), PackedFloat32Array([rr * 0.45, rr * 0.38, rr * 0.25]), 6), tube_mat(T_PUS, pus_tint))
			var tw3 := create_tween()
			tw3.tween_property(plug3, "scale", Vector3(1.2, 1.4, 1.2), 0.14)
			tw3.tween_callback(func(): _fly_off(plug3))
			for c in nd3.get_children():
				if c != plug3:
					create_tween().tween_property(c, "scale", c.scale * Vector3(0.85, 0.3, 0.85), 0.3)
			body.spawn_drops(it["pos"] + Vector3.UP * 0.01, Vector3.UP, 2, 3, 0.6, 0.006, 0.6)
			popped.emit(self, PUS_C)
			Sfx.play("squish", 0.3)
		"queimadura":
			_fly_off(it["node"])
			_burst(it["pos"], Color(1, 0.95, 0.85, 0.7), 3, 0.25, 0.005, 40.0)
			Sfx.play("pull", 0.3, -8)
		"pontos":
			_fly_off(it["node"], Vector3(0, 0.15, 0))
			_burst(it["pos"], BLOOD_C, 2, 0.3, 0.004, 40.0)
			if n.has("cut"):
				var fx: FxMap = n["cut"].get_meta("fx")
				fx.add_blood(host_uv(n["cut"], it["pos"]), 3.5, 0.35)
			Sfx.play("pull", 0.3, -6)
		"piolhos":
			_fly_off(it["node"])
			Sfx.play("pop", 0.4, -6)
	GameData.vibrate(14, 0.3)

# =================================================================== início/fim de etapa

func _on_stage_start(s: int) -> void:
	match id:
		"farpa", "carrapato", "pelo_encravado":
			pass
		"larvas":
			if s == 2:
				n["blood"] = _lesion(L_BLOOD, size * 0.95, Vector2.ZERO, true, 0.009)
		"espinhos":
			if s == 1:
				n["blood"] = _lesion(L_BLOOD, size * 1.0, Vector2.ZERO, true, 0.009)
				_lmat(n["blood"]).set_shader_parameter("strength", 0.7)

func _on_stage_end(s: int) -> void:
	if def["stages"][s].size() > 3:
		# etapa extra (o jogador piorou): limpar estanca, curativo fecha
		if def["stages"][s][0] == "curativo":
			if nail.is_empty():
				_bandage(wound_radius(), wound_radius())
			else:
				_nail_bandage()
		else:
			for h in fx_hosts:
				if is_instance_valid(h):
					var fx: FxMap = h.get_meta("fx")
					fx.bleed = 0.0
					fx.drips.clear()
		return
	if def["stages"][s][0] == "curativo" and not n.has("bandage"):
		if nail.is_empty():
			_bandage(wound_radius(), wound_radius())
		else:
			_nail_bandage()
		_on_stage_end_rest(s)
		return
	_on_stage_end_rest(s)

func _on_stage_end_rest(s: int) -> void:
	# terminou a pomada: o creme branco cobre o machucado todo (o curativo vai por cima)
	if def["stages"][s][0] == "pomada" and n.has("cream") and is_instance_valid(n["cream"]):
		var cm := _lmat(n["cream"])
		create_tween().tween_method(func(v): cm.set_shader_parameter("fill", v), 0.0, 0.85, 0.7)
		for b in n.get("dollops", []):
			var nd: Node3D = b
			if nd.visible:
				var tw := create_tween()
				tw.tween_property(nd, "scale", nd.scale * Vector3(1.4, 0.05, 1.4), 0.5)
				tw.tween_callback(nd.hide)
	# antisséptico estanca o sangramento
	if def["stages"][s][0] == "algodao":
		for h in fx_hosts:
			if is_instance_valid(h):
				var fx: FxMap = h.get_meta("fx")
				fx.bleed = 0.0
				fx.drips.clear()
	var up := global_basis.y
	var gp := global_position
	match id:
		"espinha", "cisto":
			if s == 0:
				_lset("dome", "hole", 1.0)
				_lset("dome", "swell", 0.0)
				Sfx.play("poke")
				_burst(gp + up * size * 0.45, PUS_C, 4, 0.3, 0.006, 20.0)
			elif s == 1:
				_drop_pus()
				_burst(gp + up * 0.03, PUS_C, 18, 1.1, 0.011, 35.0)
				n["splat"] = _lesion(L_PUS, size * 1.2, Vector2(rng.randf_range(-0.02, 0.02), rng.randf_range(-0.02, 0.02)), true, 0.008)
				_deflate("dome", 0.5)
				popped.emit(self, PUS_C)
				Sfx.play("splat")
		"bolha":
			if s == 0:
				_lset("dome", "hole", 1.0)
				Sfx.play("poke")
				var d: MeshInstance3D = n["dome"]
				var dm := d.material_override as ShaderMaterial
				var tw := create_tween().set_parallel()
				tw.tween_property(d, "scale", Vector3(d.scale.x * 1.05, d.scale.y * 0.5, d.scale.z * 1.05), 1.2).set_ease(Tween.EASE_OUT)
				tw.tween_method(func(v): dm.set_shader_parameter("deflate", v), 0.0, 1.0, 1.2)
				n["splat"] = _lesion(L_FLUID, size * 1.4, Vector2.ZERO, true, 0.008)
				_burst(gp + up * 0.02, Color(1, 1, 0.95, 0.7), 12, 0.5, 0.01, 60.0)
		"bicho_pe":
			if s == 0:
				Sfx.play("poke")
				_burst(global_position + global_basis.y * 0.02, Color(1, 1, 0.95, 0.7), 5, 0.3, 0.006, 40.0)
			elif s == 1:
				_pluck(n["sac"])
				_deflate("dome", 0.5)
				n["blood"] = _lesion(L_BLOOD, 0.035, Vector2.ZERO, true, 0.009)
				n["crater"] = _lesion(L_WOUND, 0.025, Vector2.ZERO, false, 0.006)
				_burst(global_position, BLOOD_C, 8, 0.6, 0.008, 40.0)
				popped.emit(self, BLOOD_C)
				Sfx.play("pull")
		"unha_roxa":
			if s == 0:
				var nm: ShaderMaterial = nail["mat"]
				create_tween().tween_method(func(v): nm.set_shader_parameter("hematoma", v), 0.85, 0.3, 0.8)
				var cp: Vector3 = n["center"].global_position
				n["splat"] = _lesion(L_BLOOD, nail["w"] * 0.9, Vector2(cp.x - global_position.x, cp.z - global_position.z), true, 0.012)
				body.spawn_drops(cp + nail["normal"] * 0.01, nail["normal"], L_BLOOD, 8, 0.7, 0.008, 0.35)
				popped.emit(self, BLOOD_C)
				Sfx.play("splat")
		"farpa":
			if s == 0:
				_pluck(n["piv"])
				n["blood"] = _lesion(L_BLOOD, 0.03, Vector2.ZERO, true, 0.008)
				Sfx.play("pull")
		"pelo_encravado":
			if s == 0:
				_lset("dome", "hole", 1.0)
				Sfx.play("poke")
			elif s == 1:
				_pluck(n["hair"])
				n["loop"].hide()
				n["blood"] = _lesion(L_BLOOD, 0.028, Vector2.ZERO, true, 0.008)
				_shrink("dome", 0.6)
				Sfx.play("pull")
		"carrapato":
			if s == 0:
				_pluck(n["tick"])
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
				_deflate("dome", 0.5)
				var p: Vector3 = n["holder"].global_position
				n["splat"] = _lesion(L_PUS, nail["w"] * 0.8, Vector2(p.x - gp.x, p.z - gp.z), true, 0.008)
				_burst(p + up * 0.02, PUS_C, 16, 0.9, 0.009, 40.0)
				popped.emit(self, PUS_C)
				Sfx.play("splat")
			elif s == 4:
				_nail_bandage()
		"unha_encravada":
			if s == 0:
				_end_guide()
				Sfx.play("cut")
				_burst(n["holder"].global_position, BLOOD_C, 5, 0.4, 0.006, 40.0)
			elif s == 1:
				_pluck(n["sliver"])
				_shrink("dome", 0.25)
				var p2: Vector3 = n["holder"].global_position
				n["splat"] = _lesion(L_PUS, nail["w"] * 0.75, Vector2(p2.x - gp.x, p2.z - gp.z), true, 0.008)
				_burst(p2, PUS_C, 14, 0.9, 0.009, 40.0)
				popped.emit(self, PUS_C)
				Sfx.play("splat")
			elif s == 4:
				_nail_bandage()
		"furunculo", "abscesso", "carbunculo":
			if s == 0:
				_end_guide()
				Sfx.play("cut")
			elif s == 1:
				_drop_pus("pus")
				_drop_pus("pus2")
				_deflate("dome", 0.6)
				if n.has("slit"):
					n["slit"].hide()
				n["splat"] = _lesion(L_PUS, size * 1.3, Vector2.ZERO, true, 0.008)
				n["blood2"] = _lesion(L_WOUND, size * 0.55, Vector2.ZERO, false, 0.006)
				_burst(gp + up * 0.04, PUS_C, 26, 1.3, 0.014, 40.0)
				_burst(gp + up * 0.04, BLOOD_C, 10, 1.0, 0.01, 50.0)
				popped.emit(self, PUS_C)
				Sfx.play("splat")
			elif s == 4:
				_bandage(wound_radius(), wound_radius())
		"verme":
			if s == 0:
				_end_guide()
				Sfx.play("cut")
			elif s == 1:
				_pluck(n["worm"])
				n["bump"].hide()
				n["blood"] = _lesion(L_BLOOD, size * 0.8, Vector2.ZERO, true, 0.009)
				_burst(_worm_pts[_worm_pts.size() / 2], BLOOD_C, 14, 1.0, 0.01, 45.0)
				popped.emit(self, BLOOD_C)
				Sfx.play("splat")
			elif s == 4:
				_heal_lesion("track", 0.6)
				_bandage(wound_radius(), wound_radius() * 0.7)
		"verruga":
			if s == 0:
				Sfx.play("freeze")
			elif s == 1:
				_shrink("dome", 0.3)
		"larvas":
			if s == 0:
				pass
		"machucado":
			if s == 2:
				_bandage(wound_radius(), wound_radius())
		"acne_costas":
			if s == 0:
				n["splat"] = _lesion(L_PUS, size * 1.15, Vector2.ZERO, true, 0.008)
				Sfx.play("splat")
		"queimadura":
			if s == 0:
				for bl in n["blisters"]:
					(bl.material_override as ShaderMaterial).set_shader_parameter("hole", 1.0)
				n["splat"] = _lesion(L_FLUID, size * 1.3, Vector2.ZERO, true, 0.008)
				Sfx.play("splat")

func _on_done() -> void:
	_end_guide()
	# vermelhidão diminui mas deixa marca; sujeira/pus que sobrou fica (limpe direito!)
	if n.has("red") and is_instance_valid(n["red"]):
		_heal_lesion("red", 0.55, 1.2)
	if id in ["espinha", "cisto", "bolha", "farpa", "pelo_encravado", "carrapato", "crosta", "calo", "furunculo", "abscesso", "carbunculo", "verme", "larvas", "favo", "verruga", "machucado", "ralado", "bicho_pe", "espinhos", "acne_costas", "queimadura", "pontos"]:
		var mk := _lesion(14, size * (1.1 if id in ["larvas", "favo", "furunculo"] else 0.75), Vector2.ZERO, false, 0.003)
		var mm := _lmat(mk)
		mm.set_shader_parameter("pore", 1.0 if id in ["espinha", "cisto", "pelo_encravado", "carrapato", "farpa", "bicho_pe"] else 0.0)
		mm.set_shader_parameter("strength", 0.0)
		create_tween().tween_method(func(v): mm.set_shader_parameter("strength", v), 0.0, 1.0, 1.2)
		n["mark"] = mk
	for h in fx_hosts:
		if is_instance_valid(h):
			var hm := h.material_override as ShaderMaterial
			create_tween().tween_method(func(v): hm.set_shader_parameter("scar", v), 0.0, 1.0, 1.5)
	# a pomada vai sendo absorvida (fica um brilho fino)
	if n.has("cream") and is_instance_valid(n["cream"]):
		var cm := _lmat(n["cream"])
		create_tween().tween_method(func(v): cm.set_shader_parameter("strength", v), 1.0, 0.45, 6.0).set_delay(2.0)
	match id:
		"espinha", "cisto", "pelo_encravado", "bolha", "furunculo", "abscesso", "carbunculo", "unha_pus", "bicho_pe":
			_shrink("dome", 1.2)
		"queimadura":
			for bl in n["blisters"]:
				var tw := create_tween()
				tw.tween_property(bl, "scale", bl.scale * Vector3(1, 0.05, 1), 1.0)
		"caspa":
			_fade_lesion("crust", 0.9)
		"pelos", "barba":
			# depois de raspar fica a barbinha
			var st := _lesion(15, size * 1.3, Vector2.ZERO, false, 0.003)
			var sm := _lmat(st)
			sm.set_shader_parameter("strength", 0.0)
			create_tween().tween_method(func(v): sm.set_shader_parameter("strength", v), 0.0, 1.0, 0.8)
		"unha_roxa":
			var nm: ShaderMaterial = nail["mat"]
			create_tween().tween_method(func(v): nm.set_shader_parameter("hematoma", v), 0.3, 0.18, 1.0)
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
	mat.set_shader_parameter("groove_prog", 0.0)
	mat.set_shader_parameter("lift_amt", 0.0)
	var piece := MeshInstance3D.new()
	piece.mesh = (nail["mi"] as MeshInstance3D).mesh
	var pm := mat.duplicate() as ShaderMaterial
	pm.shader = load("res://shaders/nail.gdshader")
	pm.set_shader_parameter("cut_at", 9.0)
	pm.set_shader_parameter("keep_from", at / nail["len"])
	piece.material_override = pm
	nail["node"].add_child(piece)
	# a lasca solta: dá um pulinho, cai por gravidade na pele/toalha ao lado, quica e some
	var start := piece.global_transform
	piece.top_level = true
	piece.global_transform = start
	var side: Vector3 = nail["dir"]
	var land: Vector3 = start.origin + side * nail["len"] * 1.6 + Vector3(rng.randf_range(-0.04, 0.04), 0, rng.randf_range(-0.04, 0.04))
	var sp := body.surface(land.x, land.z)
	land.y = (sp[0].y + 0.004) if not sp.is_empty() else start.origin.y - 0.12
	var up_pt := start.origin.lerp(land, 0.3) + Vector3(0, 0.05, 0)
	var rot_end := Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(-1.5, 1.5), rng.randf_range(2.6, 3.3))
	var tw := create_tween()
	tw.tween_property(piece, "global_position", up_pt, 0.16).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(piece, "rotation", rot_end * 0.5, 0.16)
	tw.tween_property(piece, "global_position", land, 0.26).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(piece, "rotation", rot_end, 0.26)
	tw.tween_property(piece, "global_position", land + Vector3(0, 0.012, 0), 0.08).set_ease(Tween.EASE_OUT)
	tw.tween_property(piece, "global_position", land, 0.1).set_ease(Tween.EASE_IN)
	tw.tween_interval(1.6)
	tw.tween_property(piece, "scale", Vector3(0.001, 0.001, 0.001), 0.3)
	tw.tween_callback(piece.queue_free)
	Sfx.play("clip")
	Sfx.play("tap", 0.2, -10)
