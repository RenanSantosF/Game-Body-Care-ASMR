class_name LP
extends RefCounted
## Helpers de malhas low poly (sombreamento flat) e materiais com cache.

static var _meshes := {}
static var _mats := {}

static func _flat(src: Mesh) -> ArrayMesh:
	var arr := src.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var ov := PackedVector3Array()
	var on := PackedVector3Array()
	var n_idx := idx.size()
	for i in range(0, n_idx, 3):
		var ia := idx[i]
		var ib := idx[i + 1]
		var ic := idx[i + 2]
		var a := verts[ia]
		var b := verts[ib]
		var c := verts[ic]
		var fn := (b - a).cross(c - a)
		var ref := norms[ia] + norms[ib] + norms[ic]
		if fn.length_squared() < 1e-12:
			fn = ref
		fn = fn.normalized()
		if fn.dot(ref) < 0.0:
			fn = -fn
		ov.append(a); ov.append(b); ov.append(c)
		on.append(fn); on.append(fn); on.append(fn)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = ov
	out[Mesh.ARRAY_NORMAL] = on
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return m

static func mesh(key: String) -> Mesh:
	if _meshes.has(key):
		return _meshes[key]
	var src: PrimitiveMesh
	match key:
		"sphere_lo":
			var s := SphereMesh.new(); s.radial_segments = 8; s.rings = 5; s.radius = 1.0; s.height = 2.0; src = s
		"sphere":
			var s := SphereMesh.new(); s.radial_segments = 12; s.rings = 7; s.radius = 1.0; s.height = 2.0; src = s
		"sphere_hi":
			var s := SphereMesh.new(); s.radial_segments = 26; s.rings = 16; s.radius = 1.0; s.height = 2.0; src = s
		"cyl":
			var c := CylinderMesh.new(); c.top_radius = 1.0; c.bottom_radius = 1.0; c.height = 1.0
			c.radial_segments = 7; c.rings = 1; src = c
		"cone":
			var c := CylinderMesh.new(); c.top_radius = 0.0; c.bottom_radius = 1.0; c.height = 1.0
			c.radial_segments = 6; c.rings = 1; src = c
		"disc":
			var c := CylinderMesh.new(); c.top_radius = 1.0; c.bottom_radius = 1.0; c.height = 1.0
			c.radial_segments = 10; c.rings = 1; c.cap_bottom = false; src = c
		"box":
			var b := BoxMesh.new(); src = b
		"torus":
			var t := TorusMesh.new(); t.inner_radius = 0.75; t.outer_radius = 1.0; t.rings = 12; t.ring_segments = 4; src = t
		_:
			push_error("mesh desconhecida " + key)
			return null
	var m := _flat(src)
	_meshes[key] = m
	return m

static func mat(color: Color, unique := false, glossy := false) -> StandardMaterial3D:
	var key := color.to_html() + ("g" if glossy else "")
	if not unique and _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.25 if glossy else 0.75
	m.metallic_specular = 0.8 if glossy else 0.35
	if color.a < 1.0 or unique:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if not unique:
		_mats[key] = m
	return m

static func add(parent: Node3D, key: String, color: Color, scale: Vector3, pos := Vector3.ZERO, unique := false, glossy := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh(key)
	mi.material_override = mat(color, unique, glossy)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = scale
	mi.position = pos
	parent.add_child(mi)
	return mi

static func sphere(parent: Node3D, r: Vector3, color: Color, pos := Vector3.ZERO, unique := false, glossy := false, key := "sphere") -> MeshInstance3D:
	return add(parent, key, color, r, pos, unique, glossy)

static func cyl(parent: Node3D, r: float, h: float, color: Color, pos := Vector3.ZERO, unique := false) -> MeshInstance3D:
	return add(parent, "cyl", color, Vector3(r, h, r), pos, unique)

static func box(parent: Node3D, size: Vector3, color: Color, pos := Vector3.ZERO, unique := false, glossy := false) -> MeshInstance3D:
	return add(parent, "box", color, size, pos, unique, glossy)

static func disc(parent: Node3D, r: float, color: Color, y := 0.004, unique := true) -> MeshInstance3D:
	return add(parent, "disc", color, Vector3(r, 0.004, r), Vector3(0, y, 0), unique)

static func set_color(mi: MeshInstance3D, c: Color) -> void:
	var m := mi.material_override as StandardMaterial3D
	if m:
		m.albedo_color = c

static func get_color(mi: MeshInstance3D) -> Color:
	var m := mi.material_override as StandardMaterial3D
	return m.albedo_color if m else Color.WHITE

static func set_alpha(mi: MeshInstance3D, a: float) -> void:
	var m := mi.material_override as StandardMaterial3D
	if m:
		var c := m.albedo_color
		c.a = a
		m.albedo_color = c
	mi.visible = a > 0.01

static func basis_from_normal(n: Vector3) -> Basis:
	var y := n.normalized()
	var ref := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


## Partículas simples (CPU, leves para celular)
static var _pmesh := {}

static func burst(parent: Node, pos: Vector3, color: Color, amount := 16, speed := 1.2, size := 0.025,
		dir := Vector3.UP, spread := 60.0, gravity := -5.0, life := 0.7) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := CPUParticles3D.new()
	var key := color.to_html() + str(size)
	if not _pmesh.has(key):
		var m := SphereMesh.new()
		m.radius = size
		m.height = size * 2.0
		m.radial_segments = 6
		m.rings = 3
		var mt := StandardMaterial3D.new()
		mt.albedo_color = color
		mt.roughness = 0.4
		m.material = mt
		_pmesh[key] = m
	p.mesh = _pmesh[key]
	p.one_shot = true
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 0.9
	p.direction = dir.normalized()
	p.spread = spread
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, gravity, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.3
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	parent.get_tree().create_timer(life + 0.3).timeout.connect(p.queue_free)
