class_name Body
extends Node3D
## Mão ou pé suave (malha gerada por tools/bodygen.py) + mapa de altura para
## posicionar problemas na superfície + textura de pintura dinâmica.

var part := "mao"
var meta := {}
var hmap: Image
var mesh_inst: MeshInstance3D
var skin_mat: ShaderMaterial
var paint_img: Image
var paint_tex: ImageTexture
var paint_rect := Rect2(-3.0, -1.5, 6.0, 3.0)
var paint_dirty := false
var digits: Array = []
var nails: Array = []            # [{node, mat, mesh_inst, w, len, dir, normal, r, i}]
var shadow: MeshInstance3D
var drops: Array = []            # gotas voando: {mi, pos, vel, kind, size}
var stains: Array = []           # manchas no corpo (limpáveis): MeshInstance3D
const MAX_STAINS := 70
var cam_center := Vector3.ZERO
var wide_height := 4.6

const PAINT_W := 1024
const PAINT_H := 512

const KEYS := {"mao": "hand", "pe": "foot", "costas": "back", "rosto": "face", "cabeca": "head"}

## Áreas (x, z) onde cada tipo de lugar fica em cada parte do corpo
const REGIONS := {
	"mao": {"dorso": Rect2(-0.35, -0.36, 0.78, 0.7), "braco": Rect2(-1.55, -0.2, 1.0, 0.4)},
	"pe": {"dorso": Rect2(-0.85, -0.3, 1.35, 0.6), "braco": Rect2(-1.75, -0.2, 0.75, 0.4)},
	"costas": {"dorso": Rect2(-1.5, -0.78, 2.3, 1.56), "braco": Rect2(0.55, -1.0, 0.6, 2.0)},
	"rosto": {"dorso": Rect2(-0.5, -0.68, 1.35, 1.36), "barba": Rect2(-1.18, -0.62, 0.72, 1.24), "braco": Rect2(-1.9, -0.32, 0.55, 0.64)},
	"cabeca": {"cabelo": Rect2(-0.55, -0.5, 1.3, 1.0), "dorso": Rect2(-0.55, -0.5, 1.3, 1.0)},
}
## Lugares onde não se coloca problema (olhos, boca): [x, z, raio]
const AVOID := {"rosto": [[0.22, 0.35, 0.2], [0.22, -0.35, 0.2], [-0.74, 0.0, 0.11], [-0.74, 0.15, 0.1], [-0.74, -0.15, 0.1]]}

var hair_root: Node3D

func region(kind: String) -> Rect2:
	var r: Dictionary = REGIONS.get(part, REGIONS["mao"])
	return r.get(kind, r["dorso"])

func has_region(kind: String) -> bool:
	return REGIONS.get(part, {}).has(kind)

func avoid(p: Vector3) -> bool:
	for a in AVOID.get(part, []):
		if Vector2(p.x - a[0], p.z - a[1]).length() < a[2]:
			return true
	return false

func build(p_part: String, skin: Color) -> void:
	part = p_part
	var key: String = KEYS.get(part, "hand")
	mesh_inst = MeshInstance3D.new()
	mesh_inst.mesh = load("res://assets/body/%s_mesh.res" % key)
	add_child(mesh_inst)
	hmap = load("res://assets/body/%s_hmap.res" % key)
	var f := FileAccess.open("res://assets/body/%s_meta.json" % key, FileAccess.READ)
	meta = JSON.parse_string(f.get_as_text())
	digits = meta["digits"]
	paint_img = Image.create(PAINT_W, PAINT_H, false, Image.FORMAT_RGBA8)
	paint_img.fill(Color(0, 0, 0, 0))
	paint_tex = ImageTexture.create_from_image(paint_img)
	skin_mat = ShaderMaterial.new()
	skin_mat.shader = load("res://shaders/skin.gdshader")
	skin_mat.set_shader_parameter("skin", skin)
	skin_mat.set_shader_parameter("skin_deep", skin.darkened(0.25).lerp(Color("c0504d"), 0.45))
	skin_mat.set_shader_parameter("paint", paint_tex)
	skin_mat.set_shader_parameter("paint_rect", Vector4(paint_rect.position.x, paint_rect.position.y, paint_rect.size.x, paint_rect.size.y))
	mesh_inst.material_override = skin_mat
	cam_center = {"mao": Vector3(0.1, 0, -0.15), "pe": Vector3(-0.1, 0, 0), "costas": Vector3(-0.3, 0, 0),
		"rosto": Vector3(-0.25, 0, 0), "cabeca": Vector3(-0.15, 0, 0)}.get(part, Vector3.ZERO)
	_build_shadow()
	_build_nails()
	_build_towel()

## Toalha enrolada cobrindo o fim do braço/perna (como na clínica)
func _build_towel() -> void:
	var x0: float = float(meta["x0"])
	var fm := MeshGen.shader_mat("res://shaders/fabric.gdshader")
	fm.set_shader_parameter("kind", 0)
	fm.set_shader_parameter("base", Color(0.96, 0.95, 0.92))
	fm.set_shader_parameter("wet", 0.0)
	for k in 2:
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.52 - k * 0.06
		cyl.bottom_radius = cyl.top_radius
		cyl.height = 3.2
		cyl.radial_segments = 40
		cyl.rings = 4
		var mi := MeshInstance3D.new()
		mi.mesh = cyl
		mi.material_override = fm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.rotation.x = PI / 2
		mi.position = Vector3(x0 + 0.42 - k * 0.62, -0.05 + k * 0.04, -0.15)
		if part == "costas":
			# lençol também cobrindo a nuca/cabeça
			var top := mi.duplicate() as MeshInstance3D
			add_child(top)
			top.position = Vector3(1.95 + k * 0.62, 0.0 + k * 0.04, 0.0)

## Sombra de contato macia no travesseiro (silhueta borrada do mapa de altura)
func _build_shadow() -> void:
	var nz := hmap.get_width()
	var nx := hmap.get_height()
	var small := Image.create(nx / 4, nz / 4, false, Image.FORMAT_RGBA8)
	for zi in small.get_height():
		for xi in small.get_width():
			var v := hmap.get_pixel(zi * 4, xi * 4).r
			small.set_pixel(xi, zi, Color(0.12, 0.02, 0.18, 0.6 if v > -5.0 else 0.0))
	for i in 3:
		var sw := small.get_width()
		var sh := small.get_height()
		small.resize(maxi(4, sw / 3), maxi(4, sh / 3), Image.INTERPOLATE_BILINEAR)
		small.resize(sw, sh, Image.INTERPOLATE_BILINEAR)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(small)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var pm := PlaneMesh.new()
	var res: float = meta["res"]
	pm.size = Vector2(nx * res, nz * res)
	shadow = MeshInstance3D.new()
	shadow.mesh = pm
	shadow.material_override = mat
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shadow)
	shadow.position = Vector3(float(meta["x0"]) + nx * res * 0.5 + 0.06, -0.15, float(meta["z0"]) + nz * res * 0.5 + 0.1)

func _build_nails() -> void:
	for i in digits.size():
		var an := nail_anchor(i)
		if an.is_empty():
			continue
		var r: float = an[3]
		var big := (part == "pe" and i == 0) or (part == "mao" and i == 0)
		var w := r * (1.45 if big else 1.4)
		var L := r * (1.55 if big else 1.6)
		var dir: Vector3 = an[1]
		dir.y = 0
		dir = dir.normalized()
		var tip: Vector3 = an[0] + dir * r * 0.5
		var base := tip - dir * L * 0.95
		var sb := surface(base.x, base.z)
		if sb.is_empty():
			continue
		var n: Vector3 = sb[1]
		var node := Node3D.new()
		add_child(node)
		node.position = sb[0] + n * 0.007
		node.basis = MeshGen.basis_from_normal(n, dir)
		var mat := MeshGen.shader_mat("res://shaders/nail.gdshader")
		mat.set_shader_parameter("seed", float(i) * 3.1)
		var mi := MeshGen.inst(node, MeshGen.nail(w, L, w * 0.17), mat)
		nails.append({"node": node, "mat": mat, "mi": mi, "w": w, "len": L, "dir": dir, "normal": n, "r": r, "i": i})

## Altura e normal da superfície vista de cima. Retorna [] fora do corpo.
func surface(x: float, z: float) -> Array:
	var res: float = meta["res"]
	var fx := (z - float(meta["z0"])) / res
	var fy := (x - float(meta["x0"])) / res
	var w := hmap.get_width()
	var h := hmap.get_height()
	if fx < 0 or fy < 0 or fx >= w - 1 or fy >= h - 1:
		return []
	var ix := int(fx)
	var iy := int(fy)
	var tx := fx - ix
	var ty := fy - iy
	var c00 := hmap.get_pixel(ix, iy)
	var c10 := hmap.get_pixel(ix + 1, iy)
	var c01 := hmap.get_pixel(ix, iy + 1)
	var c11 := hmap.get_pixel(ix + 1, iy + 1)
	if minf(minf(c00.r, c10.r), minf(c01.r, c11.r)) < -5.0:
		return []
	var c := c00.lerp(c10, tx).lerp(c01.lerp(c11, tx), ty)
	return [to_global(Vector3(x, c.r, z)), (global_basis * Vector3(c.g, c.b, c.a)).normalized()]

## Ponto da ponta do dedo/artelho para a unha: [pos, direção, normal, largura]
func nail_anchor(i: int) -> Array:
	var d: Dictionary = digits[i]
	var pts: Array = d["pts"]
	var rr: Array = d["r"]
	var a := Vector3(pts[pts.size() - 2][0], pts[pts.size() - 2][1], pts[pts.size() - 2][2])
	var b := Vector3(pts[pts.size() - 1][0], pts[pts.size() - 1][1], pts[pts.size() - 1][2])
	var dir := (b - a).normalized()
	var r: float = rr[rr.size() - 1]
	var c := b - dir * r * 0.55
	var s := surface(c.x, c.z)
	if s.is_empty():
		return []
	return [s[0], dir, s[1], r]

func digit_point(i: int, t: float) -> Vector3:
	var pts: Array = digits[i]["pts"]
	var seg := clampf(t, 0.0, 0.999) * (pts.size() - 1)
	var k := int(seg)
	var a := Vector3(pts[k][0], pts[k][1], pts[k][2])
	var b := Vector3(pts[k + 1][0], pts[k + 1][1], pts[k + 1][2])
	return a.lerp(b, seg - k)

# ------------------------------------------------------------- pintura

func _to_px(x: float, z: float) -> Vector2:
	return Vector2((x - paint_rect.position.x) / paint_rect.size.x * PAINT_W,
		(z - paint_rect.position.y) / paint_rect.size.y * PAINT_H)

## Carimba um pincel macio (Image com alfa) na pele.
func stamp(x: float, z: float, brush: Image, scale_px := 1.0) -> void:
	var b := brush
	if scale_px != 1.0:
		b = brush.duplicate()
		var s := maxi(2, int(brush.get_width() * scale_px))
		b.resize(s, s, Image.INTERPOLATE_BILINEAR)
	var p := _to_px(x, z) - Vector2(b.get_width(), b.get_height()) * 0.5
	paint_img.blend_rect(b, Rect2i(0, 0, b.get_width(), b.get_height()), Vector2i(p))
	paint_dirty = true

func _process(delta: float) -> void:
	if paint_dirty:
		paint_dirty = false
		paint_tex.update(paint_img)
	_step_drops(delta)

# ------------------------------------------------------------- fluidos

## Gotas físicas (pus/sangue/água): voam, caem e viram mancha onde pousam.
## kind: 2 = pus, 3 = sangue, 11 = líquido claro
func spawn_drops(pos: Vector3, dir: Vector3, kind: int, count: int, speed := 0.8, size := 0.012, spread := 0.6) -> void:
	var col := Color(0.95, 0.8, 0.32) if kind == 2 else (Color(0.5, 0.03, 0.05) if kind == 3 else Color(1, 0.98, 0.9, 0.6))
	var mat := MeshGen.std(col, 0.08, 0.0, "drop%d" % kind)
	mat.metallic_specular = 0.9
	for i in count:
		if drops.size() > 60:
			break
		var d := (dir.normalized() + Vector3(randf_range(-1, 1), randf_range(-0.2, 1), randf_range(-1, 1)) * spread).normalized()
		var sz := size * randf_range(0.5, 1.3)
		var mi := MeshGen.inst(self, MeshGen.sphere(1.0), mat, pos, Vector3.ONE * sz)
		drops.append({"mi": mi, "pos": pos, "vel": d * speed * randf_range(0.5, 1.2), "kind": kind, "size": sz})

func _step_drops(dt: float) -> void:
	if drops.is_empty():
		return
	var keep := []
	for d in drops:
		var v: Vector3 = d["vel"]
		v.y -= 6.0 * dt
		v *= 1.0 - dt * 0.8
		var p: Vector3 = d["pos"] + v * dt
		d["vel"] = v
		d["pos"] = p
		var mi: MeshInstance3D = d["mi"]
		mi.position = p
		# estica na direção do movimento (gota de verdade)
		var sp := v.length()
		if sp > 0.05:
			mi.basis = MeshGen.basis_from_normal(v.normalized()).scaled(Vector3(d["size"], d["size"] * (1.0 + sp * 0.8), d["size"]))
		var s := surface(p.x, p.z)
		var ground: float = s[0].y if not s.is_empty() else -0.15
		if p.y <= ground:
			mi.queue_free()
			if not s.is_empty():
				add_stain(s[0], d["kind"], d["size"] * (2.2 + sp * 0.6), Vector2(v.x, v.z))
				Sfx.play_throttled("drip", 0.07, 0.35, -14)
			continue
		keep.append(d)
	drops = keep

func add_stain(pos: Vector3, kind: int, r: float, smear := Vector2.ZERO) -> MeshInstance3D:
	if stains.size() >= MAX_STAINS:
		var old: MeshInstance3D = stains.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var rot := atan2(smear.y, smear.x) if smear.length() > 0.01 else randf() * TAU
	var mi := MeshInstance3D.new()
	mi.mesh = MeshGen.patch(self, pos, r, rot, 0.006 + randf() * 0.002, 6)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := MeshGen.shader_mat("res://shaders/lesion.gdshader")
	mat.set_shader_parameter("kind", kind)
	mat.set_shader_parameter("skin", skin_mat.get_shader_parameter("skin"))
	mat.set_shader_parameter("seed", randf() * 50.0)
	mat.set_shader_parameter("rot", rot)
	mat.set_shader_parameter("half_size", r)
	var mk := CleanMask.new()
	mat.set_shader_parameter("mask", mk.tex)
	mat.set_shader_parameter("use_mask", 1.0)
	mi.set_meta("mask", mk)
	mi.set_meta("c", pos)
	mi.set_meta("rot", rot)
	mi.set_meta("half", r)
	mi.material_override = mat
	add_child(mi)
	mi.position = pos
	mi.scale = Vector3(0.2, 1, 0.2)
	create_tween().tween_property(mi, "scale", Vector3.ONE, 0.12)
	stains.append(mi)
	return mi

## Limpa tudo no fim (para a foto do depois)
func fade_stains() -> void:
	for st in stains:
		if is_instance_valid(st):
			var m := st.material_override as ShaderMaterial
			create_tween().tween_method(func(v): m.set_shader_parameter("heal", v), 0.0, 1.0, 0.8)

## Esfrega manchas sob o pano/algodão
func clean_stains(wpos: Vector3, brush_r: float) -> void:
	for st in stains:
		if not is_instance_valid(st):
			continue
		var c: Vector3 = st.get_meta("c")
		var half: float = st.get_meta("half")
		if Vector2(c.x - wpos.x, c.z - wpos.z).length() > half + brush_r:
			continue
		var rot: float = st.get_meta("rot")
		var mk: CleanMask = st.get_meta("mask")
		var dx := wpos.x - c.x
		var dz := wpos.z - c.z
		var u := (dx * cos(rot) + dz * sin(rot)) / half
		var v := (-dx * sin(rot) + dz * cos(rot)) / half
		mk.paint(Vector2(u, v), brush_r / half, 0.35)
		mk.flush()
		var m := st.material_override as ShaderMaterial
		m.set_shader_parameter("wet", 1.0)

# ------------------------------------------------------------- cabelo

## Cabelo/sobrancelhas/cílios (rosto e cabeça) num único mesh por cor (leve para celular).
## excl: [[pos, raio]] — áreas sem cabelo (onde há problema: o cabelo fica afastado)
func build_hair(color: Color, excl: Array) -> void:
	if part != "rosto" and part != "cabeca":
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var a := []
	var b := []
	if part == "cabeca":
		var crown := Vector2(0.4, 0.05)
		for i in 2300:
			var x := rng.randf_range(-0.85, 1.05)
			var z := rng.randf_range(-0.85, 0.85)
			var dir2 := (Vector2(x, z) - crown)
			if dir2.length() < 0.02:
				continue
			dir2 = dir2.normalized().rotated(rng.randf_range(-0.25, 0.25))
			var s := _strand(Vector3(x, 0, z), Vector3(dir2.x, 0, dir2.y), rng.randf_range(0.18, 0.32), rng.randf_range(0.0032, 0.0048), excl, 0.25, rng)
			if s.size() > 0:
				(a if rng.randf() < 0.65 else b).append(s)
	else:
		# linha do cabelo na testa, penteado para trás
		for i in 800:
			var x := rng.randf_range(0.92, 1.35)
			var z := rng.randf_range(-0.8, 0.8)
			if x < 0.92 + 0.2 * (z * z):
				continue
			var d3 := Vector3(1.0, 0, z * 0.6 + rng.randf_range(-0.2, 0.2))
			var s2 := _strand(Vector3(x, 0, z), d3, rng.randf_range(0.18, 0.34), rng.randf_range(0.005, 0.0065), excl, 0.2, rng)
			if s2.size() > 0:
				(a if rng.randf() < 0.65 else b).append(s2)
		# sobrancelhas e cílios (pálpebras fechadas)
		for side in [-1.0, 1.0]:
			for i in 80:
				var t := rng.randf()
				var z2: float = side * lerpf(0.13, 0.58, t)
				var x2 := 0.43 + sin(t * PI) * 0.05 + rng.randf_range(-0.025, 0.025)
				var s3 := _strand(Vector3(x2, 0, z2), Vector3(0.35, 0, side), rng.randf_range(0.03, 0.05), 0.0026, excl, 0.1, rng)
				if s3.size() > 0:
					a.append(s3)
			for i in 34:
				var t2 := rng.randf()
				var z3: float = side * lerpf(0.2, 0.5, t2)
				var x3 := 0.14 - sin(t2 * PI) * 0.025
				var s4 := _strand(Vector3(x3, 0, z3), Vector3(-1.0, 0, side * 0.3), 0.04, 0.0017, excl, 0.6, rng)
				if s4.size() > 0:
					a.append(s4)
	_tint_scalp(color, excl)
	hair_root = Node3D.new()
	add_child(hair_root)
	for pair in [[a, color.darkened(0.08)], [b, color.lightened(0.12)]]:
		if pair[0].is_empty():
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = MeshGen.tubes(pair[0], 3)
		mi.material_override = MeshGen.std(pair[1], 0.5, 0.0, "scalp_hair_%s" % pair[1].to_html())
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hair_root.add_child(mi)

## Pinta (nas cores dos vértices) onde há cabelo, deixando a pele livre em volta dos problemas
func _tint_scalp(color: Color, excl: Array) -> void:
	var arr := mesh_inst.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var cs: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	for i in vs.size():
		var v := vs[i]
		var cov := 0.0
		if part == "cabeca":
			cov = smoothstep(0.15, 0.4, ns[i].y) * smoothstep(-0.95, -0.7, v.x)
		else:
			cov = smoothstep(0.95 + 0.2 * v.z * v.z, 1.12 + 0.2 * v.z * v.z, v.x) * smoothstep(0.1, 0.35, ns[i].y)
		for e in excl:
			var dd := Vector2(v.x - e[0].x, v.z - e[0].z).length()
			cov *= smoothstep(e[1] * 0.85, e[1] + 0.05, dd)
		cs[i] = Color(cs[i].r, cov, 0.0, 1.0)
	arr[Mesh.ARRAY_COLOR] = cs
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh_inst.mesh = m
	skin_mat.set_shader_parameter("hair_on", 1.0)
	skin_mat.set_shader_parameter("hair_col", color.darkened(0.15))

## Um fio deitado na pele seguindo a superfície. Para ao entrar numa área excluída.
func _strand(root: Vector3, dir: Vector3, L: float, r: float, excl: Array, lift: float, rng: RandomNumberGenerator) -> Array:
	var sp := surface(root.x, root.z)
	if sp.is_empty() or sp[1].y < 0.2:
		return []
	for e in excl:
		if Vector2(root.x - e[0].x, root.z - e[0].z).length() < e[1]:
			return []
	var pts := PackedVector3Array()
	var p := Vector3(root.x, 0, root.z)
	var d := dir.normalized()
	var curl := rng.randf_range(-3.0, 3.0)
	var wave := rng.randf_range(0.5, 1.5) * (1.0 if rng.randf() < 0.5 else -1.0)
	for k in 6:
		var s := float(k) / 5.0
		var q := surface(p.x, p.z)
		if q.is_empty():
			break
		var blocked := false
		for e in excl:
			if Vector2(p.x - e[0].x, p.z - e[0].z).length() < e[1]:
				blocked = true
		if blocked and k > 1:
			break
		var nn: Vector3 = q[1]
		pts.append(q[0] + nn * (r * 1.2 + 0.002 + lift * L * s * (1.0 - s) * 0.5))
		d = d.rotated(Vector3.UP, curl * 0.06 + sin(k * 1.9) * wave * 0.22)
		p += d * L / 5.0
	if pts.size() < 3:
		return []
	var rr := PackedFloat32Array()
	for k in pts.size():
		rr.append(lerpf(r, r * 0.35, float(k) / (pts.size() - 1)))
	return [pts, rr]
