class_name MeshGen
extends RefCounted
## Malhas suaves geradas por código: tubos (pelos, vermes, pus), remendos que
## acompanham a pele, placas de unha e cúpulas.

static var _cache := {}
static var _mats := {}

## Tubo suave ao longo de uma curva. radii pode ter 1 valor ou um por ponto.
static func tube(pts: PackedVector3Array, radii: PackedFloat32Array, sides := 8, cap := true) -> ArrayMesh:
	var o := {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(), "i": PackedInt32Array()}
	_tube_into(o, pts, radii, sides, cap)
	return _commit(o)

## Vários tubos numa malha só (ex.: tufo de pelos = 1 draw call)
static func tubes(list: Array, sides := 4) -> ArrayMesh:
	var o := {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(), "i": PackedInt32Array()}
	for t in list:
		_tube_into(o, t[0], t[1], sides, true)
	return _commit(o)

static func _commit(o: Dictionary) -> ArrayMesh:
	if o["v"].size() == 0:
		return null
	var m := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = o["v"]
	arr[Mesh.ARRAY_NORMAL] = o["n"]
	arr[Mesh.ARRAY_TEX_UV] = o["uv"]
	arr[Mesh.ARRAY_INDEX] = o["i"]
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

static func _tube_into(o: Dictionary, pts: PackedVector3Array, radii: PackedFloat32Array, sides: int, cap: bool) -> void:
	var n := pts.size()
	if n < 2:
		return
	var verts: PackedVector3Array = o["v"]
	var norms: PackedVector3Array = o["n"]
	var uvs: PackedVector2Array = o["uv"]
	var idx: PackedInt32Array = o["i"]
	var base := verts.size()
	var prev_side := Vector3.ZERO
	var total := 0.0
	var lens := PackedFloat32Array([0.0])
	for i in range(1, n):
		total += pts[i].distance_to(pts[i - 1])
		lens.append(total)
	for i in n:
		var t: Vector3
		if i == 0:
			t = pts[1] - pts[0]
		elif i == n - 1:
			t = pts[n - 1] - pts[n - 2]
		else:
			t = pts[i + 1] - pts[i - 1]
		t = t.normalized()
		var side := prev_side
		if side == Vector3.ZERO or absf(side.dot(t)) > 0.95:
			side = t.cross(Vector3.UP if absf(t.y) < 0.9 else Vector3.RIGHT).normalized()
		side = (side - t * side.dot(t)).normalized()
		prev_side = side
		var up := t.cross(side).normalized()
		var r: float = radii[mini(i, radii.size() - 1)]
		for s in sides:
			var a := TAU * s / sides
			var dirv := side * cos(a) + up * sin(a)
			verts.append(pts[i] + dirv * r)
			norms.append(dirv)
			uvs.append(Vector2(float(s) / sides, lens[i] / maxf(total, 0.0001)))
	for i in n - 1:
		for s in sides:
			var a := base + i * sides + s
			var b := base + i * sides + (s + 1) % sides
			var c := a + sides
			var d := b + sides
			idx.append_array([a, c, b, b, c, d])
	if cap:
		for e in [0, n - 1]:
			var center := verts.size()
			var t2 := (pts[1] - pts[0]).normalized() if e == 0 else (pts[n - 1] - pts[n - 2]).normalized()
			var rr: float = radii[mini(e, radii.size() - 1)]
			verts.append(pts[e] + t2 * (rr * (0.7 if e == n - 1 else -0.7)))
			norms.append(t2 * (1.0 if e == n - 1 else -1.0))
			uvs.append(Vector2(0.5, 1.0 if e == n - 1 else 0.0))
			for s in sides:
				var a2: int = base + e * sides + s
				var b2: int = base + e * sides + (s + 1) % sides
				if e == 0:
					idx.append_array([center, a2, b2])
				else:
					idx.append_array([center, b2, a2])
	o["v"] = verts
	o["n"] = norms
	o["uv"] = uvs
	o["i"] = idx

## Remendo quadrado (UV -1..1) colado na pele do corpo, em coordenadas locais do nó.
## center/basis definem onde o nó vai ficar (o mesh é construído relativo a ele).
static func patch(body: Body, center: Vector3, half: float, rot: float, lift := 0.004, res := 18) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var c := cos(rot)
	var s := sin(rot)
	for j in res + 1:
		for i in res + 1:
			var u := -1.0 + 2.0 * i / res
			var v := -1.0 + 2.0 * j / res
			var lx := (u * c - v * s) * half
			var lz := (u * s + v * c) * half
			var sp := body.surface(center.x + lx, center.z + lz)
			if sp.is_empty():
				verts.append(Vector3(lx, -0.3, lz))
				norms.append(Vector3.UP)
				cols.append(Color(1, 1, 1, 0))
			else:
				var wpos: Vector3 = sp[0] + sp[1] * lift
				verts.append(wpos - center)
				norms.append(sp[1])
				cols.append(Color(1, 1, 1, 1))
			uvs.append(Vector2(u, v))
	for j in res:
		for i in res:
			var a := j * (res + 1) + i
			var b := a + 1
			var d := a + res + 1
			var e := d + 1
			idx.append_array([a, b, d, b, e, d])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

## Placa de unha curva. Local: X = largura, Z = comprimento (0 cutícula -> +len ponta), Y = para fora.
static func nail(width: float, length: float, curve: float, tip_extra := 0.0, res := 14) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var L := length + tip_extra
	for j in res + 1:
		for i in res + 1:
			var u := -1.0 + 2.0 * i / res
			var v := float(j) / res
			# contorno arredondado na cutícula e na ponta
			var w := width * 0.5
			var base_round := sqrt(maxf(0.0, 1.0 - pow(1.0 - minf(v * 5.0, 1.0), 2.0)))
			var tip_round := 1.0
			if v * L > length - width * 0.25:
				var k := clampf((v * L - (length - width * 0.25)) / (width * 0.25 + tip_extra + 0.0001), 0.0, 1.0)
				tip_round = lerpf(1.0, 0.82, k * k)
			var x := u * w * lerpf(0.82, 1.0, base_round) * tip_round
			var y := -curve * u * u + 0.006 * sin(v * PI)
			var z := v * L
			verts.append(Vector3(x, y, z))
			var n := Vector3(2.0 * curve * u / w * 0.5, 1.0, 0.0).normalized()
			norms.append(n)
			uvs.append(Vector2(u, v * L / length))
	for j in res:
		for i in res:
			var a := j * (res + 1) + i
			var b := a + 1
			var d := a + res + 1
			var e := d + 1
			idx.append_array([a, b, d, b, e, d])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

## Perfil do inchaço: 1 no topo, 0 e plano na borda (encaixa na pele sem quina)
static func bump_profile(r: float) -> float:
	return pow(maxf(0.0, 1.0 - r * r), 1.6)

## Malha de inchaço suave (raio 1, altura 1) com uma saia para dentro da pele
static func bump() -> ArrayMesh:
	if _cache.has("bump"):
		return _cache["bump"]
	var rings := 18
	var segs := 36
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	verts.append(Vector3(0, 1, 0))
	norms.append(Vector3.UP)
	uvs.append(Vector2(0.5, 0.5))
	for ri in range(1, rings + 2):
		var r := minf(float(ri) / rings, 1.0) if ri <= rings else 1.06
		var y := bump_profile(r) if ri <= rings else -0.08
		# derivada do perfil
		var dy := -1.6 * pow(maxf(0.0001, 1.0 - r * r), 0.6) * 2.0 * r if r < 1.0 else 0.0
		for si in segs:
			var a := TAU * si / segs
			var x := cos(a) * r
			var z := sin(a) * r
			verts.append(Vector3(x, y, z))
			norms.append(Vector3(-dy * cos(a), 1.0, -dy * sin(a)).normalized())
			uvs.append(Vector2(x * 0.5 + 0.5, z * 0.5 + 0.5))
	for si in segs:
		idx.append_array([0, 1 + si, 1 + (si + 1) % segs])
	for ri in range(0, rings):
		var b0 := 1 + ri * segs
		var b1 := b0 + segs
		for si in segs:
			var a0 := b0 + si
			var a1 := b0 + (si + 1) % segs
			var c0 := b1 + si
			var c1 := b1 + (si + 1) % segs
			idx.append_array([a0, c0, a1, a1, c0, c1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_cache["bump"] = m
	return m

static func sphere(r := 1.0) -> SphereMesh:
	var key := "sph%.3f" % r
	if _cache.has(key):
		return _cache[key]
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 24
	s.rings = 12
	_cache[key] = s
	return s

static func cylinder(r := 1.0, h := 1.0, r2 := -1.0) -> CylinderMesh:
	var key := "cyl%.3f_%.3f_%.3f" % [r, h, r2]
	if _cache.has(key):
		return _cache[key]
	var c := CylinderMesh.new()
	c.top_radius = r if r2 < 0 else r2
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 20
	c.rings = 1
	_cache[key] = c
	return c

static func shader_mat(path: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(path)
	return m

static func std(color: Color, rough := 0.5, metal := 0.0, key := "") -> StandardMaterial3D:
	var k := key if key != "" else "%s_%.2f_%.2f" % [color.to_html(), rough, metal]
	if _mats.has(k):
		return _mats[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	m.metallic_specular = 0.6
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[k] = m
	return m

static func inst(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, scale := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scale
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

static func basis_from_normal(n: Vector3, fwd := Vector3(1, 0, 0)) -> Basis:
	var y := n.normalized()
	var z := fwd - y * fwd.dot(y)
	if z.length() < 0.01:
		z = Vector3.FORWARD - y * Vector3.FORWARD.dot(y)
	z = z.normalized()
	var x := y.cross(z).normalized()
	return Basis(x, y, z)


## Partículas (CPU, leves) com malha suave
static var _pm := {}

static func burst(parent: Node, pos: Vector3, color: Color, amount := 14, speed := 1.0, size := 0.02,
		dir := Vector3.UP, spread := 45.0, gravity := -6.0, life := 0.8, glossy := true) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var key := color.to_html() + str(size) + str(glossy)
	if not _pm.has(key):
		var m := SphereMesh.new()
		m.radius = size
		m.height = size * 2.0
		m.radial_segments = 10
		m.rings = 5
		var mt := StandardMaterial3D.new()
		mt.albedo_color = color
		mt.roughness = 0.15 if glossy else 0.8
		mt.metallic_specular = 0.8
		if color.a < 1.0:
			mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.material = mt
		_pm[key] = m
	var p := CPUParticles3D.new()
	p.mesh = _pm[key]
	p.one_shot = true
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 0.85
	p.direction = dir.normalized()
	p.spread = spread
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, gravity, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.3
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	parent.get_tree().create_timer(life + 0.3).timeout.connect(p.queue_free)
