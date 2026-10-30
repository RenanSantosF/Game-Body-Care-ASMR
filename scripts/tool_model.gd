class_name ToolModel
extends Node3D
## Ferramenta 3D que segue o dedo. A ponta fica na origem e o cabo em +Y.

const METAL := Color("cfd8e3")
const METAL_D := Color("8a96a6")

var tool_id := ""
var active := false
var mech := -1
var t := 0.0
var root: Node3D
var arm_l: Node3D
var arm_r: Node3D
var spray_fx: CPUParticles3D

func set_tool(id: String) -> void:
	if id == tool_id:
		return
	tool_id = id
	if root:
		root.queue_free()
	root = Node3D.new()
	add_child(root)
	arm_l = null
	arm_r = null
	spray_fx = null
	match id:
		"algodao":
			LP.cyl(root, 0.012, 0.5, Color("8fd3ff"), Vector3(0, 0.3, 0))
			LP.sphere(root, Vector3(0.06, 0.07, 0.06), Color("fbfbf7"), Vector3(0, 0.05, 0), false, false, "sphere_lo")
		"espremedor":
			var ring := LP.add(root, "torus", METAL, Vector3(0.035, 0.06, 0.035), Vector3(0, 0.01, 0), false, true)
			ring.rotation.x = 0.0
			LP.cyl(root, 0.008, 0.4, METAL, Vector3(0, 0.23, 0))
			LP.cyl(root, 0.02, 0.18, Color("ff7eb6"), Vector3(0, 0.36, 0))
		"pinca":
			arm_l = Node3D.new(); root.add_child(arm_l); arm_l.position = Vector3(0, 0.5, 0)
			arm_r = Node3D.new(); root.add_child(arm_r); arm_r.position = Vector3(0, 0.5, 0)
			LP.box(arm_l, Vector3(0.022, 0.5, 0.01), METAL, Vector3(-0.0, -0.25, 0), false, true)
			LP.box(arm_r, Vector3(0.022, 0.5, 0.01), METAL, Vector3(0.0, -0.25, 0), false, true)
			LP.box(arm_l, Vector3(0.03, 0.12, 0.014), Color("ffcf4f"), Vector3(0, -0.12, 0))
			LP.box(arm_r, Vector3(0.03, 0.12, 0.014), Color("ffcf4f"), Vector3(0, -0.12, 0))
		"escova":
			LP.box(root, Vector3(0.14, 0.04, 0.09), Color("4fb3ff"), Vector3(0, 0.06, 0))
			LP.box(root, Vector3(0.13, 0.05, 0.08), Color("fff6d6"), Vector3(0, 0.025, 0))
			LP.box(root, Vector3(0.05, 0.36, 0.035), Color("4fb3ff"), Vector3(0, 0.25, 0))
		"espatula":
			LP.box(root, Vector3(0.08, 0.13, 0.006), METAL, Vector3(0, 0.06, 0), false, true)
			LP.cyl(root, 0.012, 0.25, METAL_D, Vector3(0, 0.24, 0))
			LP.cyl(root, 0.022, 0.16, Color("7ed957"), Vector3(0, 0.4, 0))
		"bisturi":
			var blade := LP.box(root, Vector3(0.025, 0.08, 0.004), Color("eef6ff"), Vector3(0.005, 0.04, 0), false, true)
			blade.rotation.z = 0.15
			LP.box(root, Vector3(0.03, 0.38, 0.016), METAL_D, Vector3(0, 0.27, 0), false, true)
		"lamina":
			LP.box(root, Vector3(0.18, 0.04, 0.045), Color("9b7bff"), Vector3(0, 0.03, 0))
			LP.box(root, Vector3(0.17, 0.008, 0.05), METAL, Vector3(0, 0.005, 0), false, true)
			LP.cyl(root, 0.018, 0.36, Color("9b7bff"), Vector3(0, 0.23, 0))
		"pente":
			LP.box(root, Vector3(0.24, 0.04, 0.012), Color("ff8f4f"), Vector3(0, 0.09, 0))
			for i in 11:
				LP.box(root, Vector3(0.008, 0.07, 0.008), Color("ff8f4f"), Vector3(-0.11 + i * 0.022, 0.035, 0))
			LP.box(root, Vector3(0.05, 0.25, 0.012), Color("ff8f4f"), Vector3(0, 0.23, 0))
		"spray":
			var can := Node3D.new(); root.add_child(can); can.position = Vector3(0, 0.25, 0)
			LP.cyl(can, 0.06, 0.28, Color("8fd3ff"), Vector3(0, 0.1, 0))
			LP.cyl(can, 0.045, 0.04, Color("ffffff"), Vector3(0, -0.06, 0))
			LP.cyl(can, 0.012, 0.03, Color("4fb3ff"), Vector3(0, -0.09, 0))
			spray_fx = CPUParticles3D.new()
			root.add_child(spray_fx)
			spray_fx.position = Vector3(0, 0.14, 0)
			var m := SphereMesh.new(); m.radius = 0.012; m.height = 0.024; m.radial_segments = 6; m.rings = 3
			var mt := StandardMaterial3D.new(); mt.albedo_color = Color(0.85, 0.95, 1.0, 0.7)
			mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.material = mt
			spray_fx.mesh = m
			spray_fx.amount = 24
			spray_fx.lifetime = 0.35
			spray_fx.local_coords = true
			spray_fx.direction = Vector3(0, -1, 0)
			spray_fx.spread = 18.0
			spray_fx.initial_velocity_min = 0.3
			spray_fx.initial_velocity_max = 0.5
			spray_fx.gravity = Vector3.ZERO
			spray_fx.scale_amount_min = 0.6
			spray_fx.scale_amount_max = 1.8
			spray_fx.emitting = false
		"curativo":
			LP.box(root, Vector3(0.22, 0.012, 0.09), Problem.BAND, Vector3(0, 0.01, 0))
			LP.box(root, Vector3(0.08, 0.016, 0.08), Color("fbf3e6"), Vector3(0, 0.012, 0))
	set_active(false)

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
			var open := 0.09 if not (active and (mech == Defs.Mech.PULL or mech == Defs.Mech.PICK)) else 0.0
			arm_l.rotation.z = lerpf(arm_l.rotation.z, open, 0.3)
			arm_r.rotation.z = lerpf(arm_r.rotation.z, -open, 0.3)
		"espremedor":
			if active:
				root.position.y = -0.015 - sin(t * 14.0) * 0.004
		"escova", "algodao", "lamina":
			if active:
				root.rotation.z = sin(t * 22.0) * 0.12
		"spray":
			if active:
				root.position.x = sin(t * 30.0) * 0.004
