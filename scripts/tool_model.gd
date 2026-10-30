class_name ToolModel
extends Node3D
## Ferramenta 3D que segue o dedo. Ponta na origem, cabo em +Y.

var tool_id := ""
var active := false
var grip := false                # segundo dedo pressionado
var mech := -1
var t := 0.0
var root: Node3D
var parts := {}
var spray_fx: CPUParticles3D

func _metal() -> StandardMaterial3D:
	return MeshGen.std(Color(0.82, 0.85, 0.9), 0.22, 0.85, "metal")

func _plastic(c: Color) -> StandardMaterial3D:
	return MeshGen.std(c, 0.35, 0.0)

func _cyl(parent: Node3D, r: float, h: float, mat: Material, pos: Vector3, r2 := -1.0) -> MeshInstance3D:
	return MeshGen.inst(parent, MeshGen.cylinder(1.0, 1.0, r2 / r if r2 > 0 else -1.0), mat, pos, Vector3(r, h, r))

func _sph(parent: Node3D, s: Vector3, mat: Material, pos: Vector3) -> MeshInstance3D:
	return MeshGen.inst(parent, MeshGen.sphere(1.0), mat, pos, s)

func set_tool(id: String) -> void:
	if id == tool_id:
		return
	tool_id = id
	if root:
		root.queue_free()
	root = Node3D.new()
	add_child(root)
	parts.clear()
	_soil.clear()
	spray_fx = null
	var metal := _metal()
	match id:
		"pano":
			var cloth := Node3D.new()
			root.add_child(cloth)
			parts["cloth"] = cloth
			var fm := MeshGen.shader_mat("res://shaders/fabric.gdshader")
			fm.set_shader_parameter("kind", 0)
			fm.set_shader_parameter("base", Color("8cc9ef"))
			MeshGen.inst(cloth, _cloth_mesh(), fm)
			parts["mat"] = fm
		"algodao":
			var ball := Node3D.new()
			root.add_child(ball)
			parts["ball"] = ball
			var cm := MeshGen.shader_mat("res://shaders/fabric.gdshader")
			cm.set_shader_parameter("kind", 1)
			parts["mat"] = cm
			_sph(ball, Vector3(0.032, 0.022, 0.032), cm, Vector3(0, 0.02, 0))
			_sph(ball, Vector3(0.024, 0.021, 0.025), cm, Vector3(0.017, 0.032, 0.007))
			# pinça segurando o algodão
			for side in [-1.0, 1.0]:
				var arm := MeshGen.inst(root, MeshGen.cylinder(1.0, 1.0, 0.5), metal, Vector3(side * 0.012, 0.22, 0), Vector3(0.008, 0.34, 0.004))
				arm.rotation.z = side * 0.06
		"agulha":
			var nd := Node3D.new()
			root.add_child(nd)
			parts["needle"] = nd
			_cyl(nd, 0.0035, 0.2, metal, Vector3(0, 0.1, 0), 0.0035)
			_cyl(nd, 0.0035, 0.02, metal, Vector3(0, 0.005, 0), 0.0008)
			_cyl(nd, 0.018, 0.05, _plastic(Color("ff7eb6")), Vector3(0, 0.22, 0), 0.012)
			_cyl(nd, 0.03, 0.22, MeshGen.std(Color(0.92, 0.96, 1.0, 0.55), 0.1), Vector3(0, 0.36, 0))
			_cyl(nd, 0.034, 0.012, _plastic(Color("ff7eb6")), Vector3(0, 0.48, 0))
		"espremedor":
			var nd2 := Node3D.new()
			root.add_child(nd2)
			parts["press"] = nd2
			var ring := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.026
			tm.outer_radius = 0.034
			tm.rings = 24
			tm.ring_segments = 8
			ring.mesh = tm
			ring.material_override = metal
			nd2.add_child(ring)
			ring.position = Vector3(0, 0.004, 0)
			_cyl(nd2, 0.006, 0.12, metal, Vector3(0, 0.07, 0.03)).rotation.x = -0.45
			_cyl(nd2, 0.008, 0.36, metal, Vector3(0, 0.3, 0.055))
			_cyl(nd2, 0.016, 0.16, _plastic(Color("ff7eb6")), Vector3(0, 0.38, 0.055))
		"pinca":
			for side in [-1.0, 1.0]:
				var arm := Node3D.new()
				root.add_child(arm)
				arm.position = Vector3(0, 0.42, 0)
				parts["arm%d" % int(side)] = arm
				var a := MeshGen.inst(arm, MeshGen.cylinder(1.0, 1.0, 0.4), metal, Vector3(side * 0.012, -0.21, 0), Vector3(0.012, 0.42, 0.005))
				a.rotation.z = side * 0.03
				MeshGen.inst(arm, MeshGen.sphere(1.0), _plastic(Color("ffcf4f")), Vector3(side * 0.016, -0.12, 0), Vector3(0.012, 0.06, 0.007))
		"curativo":
			_sph(root, Vector3(0.11, 0.012, 0.045), MeshGen.std(Problem.BAND, 0.8), Vector3(0, 0.012, 0))
			_sph(root, Vector3(0.04, 0.014, 0.038), MeshGen.std(Color("fbf4ea"), 0.9), Vector3(0, 0.016, 0))
		"lamina":
			var head := Node3D.new()
			root.add_child(head)
			parts["head"] = head
			MeshGen.inst(head, MeshGen.sphere(1.0), _plastic(Color("9b7bff")), Vector3(0, 0.02, 0), Vector3(0.16, 0.018, 0.03))
			var blade := MeshGen.inst(head, BoxMesh.new(), metal, Vector3(0, 0.006, 0.0), Vector3(0.3, 0.004, 0.022))
			blade.name = "blade"
			_cyl(root, 0.014, 0.36, _plastic(Color("9b7bff")), Vector3(0, 0.21, 0.0))
		"alicate":
			var jaw_a := Node3D.new()
			root.add_child(jaw_a)
			var jaw_b := Node3D.new()
			root.add_child(jaw_b)
			parts["jaw_a"] = jaw_a
			parts["jaw_b"] = jaw_b
			for j in [jaw_a, jaw_b]:
				j.position = Vector3(0, 0.12, 0)
				MeshGen.inst(j, MeshGen.sphere(1.0), metal, Vector3(0, -0.06, 0), Vector3(0.035, 0.07, 0.008))
				MeshGen.inst(j, MeshGen.cylinder(1.0, 1.0, 0.7), metal, Vector3(0, 0.12, 0), Vector3(0.014, 0.25, 0.007))
			jaw_a.position.z = 0.006
			jaw_b.position.z = -0.006
			_cyl(root, 0.022, 0.18, _plastic(Color("ff8f4f")), Vector3(0, 0.33, 0.02))
		"bisturi":
			var blade2 := MeshGen.inst(root, MeshGen.sphere(1.0), MeshGen.std(Color(0.94, 0.97, 1.0), 0.1, 0.95, "blade"), Vector3(0, 0.03, 0), Vector3(0.012, 0.045, 0.002))
			blade2.rotation.z = 0.25
			MeshGen.inst(root, BoxMesh.new(), metal, Vector3(0, 0.25, 0), Vector3(0.022, 0.36, 0.01))
		"raspador":
			var plate := MeshGen.inst(root, MeshGen.sphere(1.0), metal, Vector3(0, 0.012, 0), Vector3(0.06, 0.006, 0.04))
			plate.name = "plate"
			_cyl(root, 0.008, 0.2, metal, Vector3(0, 0.12, 0))
			_cyl(root, 0.02, 0.2, _plastic(Color("7ed957")), Vector3(0, 0.3, 0))
		"pomada":
			var tb := Node3D.new()
			root.add_child(tb)
			parts["tube"] = tb
			_cyl(tb, 0.035, 0.24, _plastic(Color("ffffff")), Vector3(0, 0.2, 0))
			_cyl(tb, 0.035, 0.08, _plastic(Color("4cd07d")), Vector3(0, 0.25, 0))
			_cyl(tb, 0.012, 0.04, _plastic(Color("4cd07d")), Vector3(0, 0.06, 0), 0.008)
			_sph(tb, Vector3(0.02, 0.012, 0.02), MeshGen.std(Color(1, 1, 1), 0.2), Vector3(0, 0.03, 0))
		"lixa":
			var board := Node3D.new()
			root.add_child(board)
			parts["board"] = board
			MeshGen.inst(board, MeshGen.sphere(1.0), MeshGen.std(Color("c9a3a3"), 0.95), Vector3(0, 0.15, 0), Vector3(0.025, 0.17, 0.006))
			MeshGen.inst(board, MeshGen.sphere(1.0), MeshGen.std(Color("ff7eb6"), 0.6), Vector3(0, 0.28, 0), Vector3(0.026, 0.05, 0.007))
		"spray":
			var can := Node3D.new()
			root.add_child(can)
			can.position = Vector3(0, 0.22, 0)
			_cyl(can, 0.05, 0.22, _plastic(Color("8fd3ff")), Vector3(0, 0.08, 0))
			_sph(can, Vector3(0.05, 0.03, 0.05), _plastic(Color("ffffff")), Vector3(0, -0.04, 0))
			_cyl(can, 0.01, 0.03, _plastic(Color("4fb3ff")), Vector3(0, -0.07, 0))
			spray_fx = CPUParticles3D.new()
			root.add_child(spray_fx)
			spray_fx.position = Vector3(0, 0.14, 0)
			var m := SphereMesh.new()
			m.radius = 0.01
			m.height = 0.02
			var mt := StandardMaterial3D.new()
			mt.albedo_color = Color(0.85, 0.95, 1.0, 0.6)
			mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.material = mt
			spray_fx.mesh = m
			spray_fx.amount = 30
			spray_fx.lifetime = 0.35
			spray_fx.local_coords = true
			spray_fx.direction = Vector3(0, -1, 0)
			spray_fx.spread = 15.0
			spray_fx.initial_velocity_min = 0.3
			spray_fx.initial_velocity_max = 0.45
			spray_fx.gravity = Vector3.ZERO
			spray_fx.scale_amount_min = 0.6
			spray_fx.scale_amount_max = 2.0
			spray_fx.emitting = false
	set_active(false)

var _soil := {}

## Pano e algodão ficam sujos com o que limpam
func soil(c: Color, amt: float) -> void:
	if tool_id != "pano" and tool_id != "algodao":
		return
	if not parts.has("mat"):
		return
	var m: ShaderMaterial = parts["mat"]
	var cur: float = _soil.get("amt", 0.0)
	var cc: Color = _soil.get("col", c)
	cur = minf(1.0, cur + clampf(amt, 0.0, 0.05))
	cc = cc.lerp(c, 0.08)
	_soil["amt"] = cur
	_soil["col"] = cc
	m.set_shader_parameter("soil", cur)
	m.set_shader_parameter("soil_col", cc)

## Pano dobrado: tecido com pregas, apertado embaixo e solto em cima
func _cloth_mesh() -> ArrayMesh:
	var res := 16
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for j in res + 1:
		for i in res + 1:
			var u := float(i) / res
			var v := float(j) / res
			var x := (u - 0.5) * 0.17
			var z := (v - 0.5) * 0.13
			var r := Vector2(x / 0.085, z / 0.065).length()
			# centro encostado na pele, bordas sobem (dedos segurando) com pregas
			var y := pow(r, 2.2) * 0.07 + sin(u * 19.0 + v * 3.0) * 0.006 * r + sin(v * 13.0) * 0.004 * r
			verts.append(Vector3(x, y + 0.004, z))
			uvs.append(Vector2(u, v))
	for j in res:
		for i in res:
			var a := j * (res + 1) + i
			idx.append_array([a, a + 1, a + res + 1, a + 1, a + res + 2, a + res + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var st := SurfaceTool.new()
	st.create_from_arrays(arr)
	st.generate_normals()
	return st.commit()

func set_active(a: bool, m := -1) -> void:
	active = a
	mech = m
	if spray_fx:
		spray_fx.emitting = a

func _process(delta: float) -> void:
	if root == null:
		return
	t += delta
	root.position = Vector3.ZERO
	root.rotation = Vector3.ZERO
	match tool_id:
		"pinca":
			var closed := grip
			for side in [-1, 1]:
				var arm: Node3D = parts["arm%d" % side]
				arm.rotation.z = lerpf(arm.rotation.z, (0.0 if closed else 0.06) * -side, 0.35)
		"agulha":
			if active and grip:
				parts["needle"].position.y = -absf(sin(t * 10.0)) * 0.02
		"espremedor":
			if active and grip:
				parts["press"].position.y = -0.008 - sin(t * 16.0) * 0.004
		"pano", "algodao":
			if active:
				root.rotation.z = sin(t * 18.0) * 0.18
				root.rotation.x = cos(t * 15.0) * 0.12
				var k := "cloth" if tool_id == "pano" else "ball"
				parts[k].scale = Vector3(1.0 + sin(t * 20.0) * 0.06, 1.0 - sin(t * 20.0) * 0.08, 1.0)
		"lamina", "raspador", "lixa":
			if active:
				root.rotation.z = sin(t * 22.0) * 0.1
		"alicate":
			var close := 0.0
			if active and (grip or mech == Defs.Mech.CUT):
				close = 0.5 + 0.5 * sin(t * 12.0)
			parts["jaw_a"].rotation.x = lerpf(0.18, 0.0, close)
			parts["jaw_b"].rotation.x = -lerpf(0.18, 0.0, close)
		"pomada":
			if active:
				parts["tube"].scale = Vector3(1.0 + sin(t * 10.0) * 0.06, 1.0, 1.0 + sin(t * 10.0) * 0.06)
		"spray":
			if spray_fx:
				spray_fx.emitting = active and grip
			if active and grip:
				root.position.x = sin(t * 30.0) * 0.003
