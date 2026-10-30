class_name Stage
extends RefCounted
## Ambiente comum: luzes, fundo e travesseiro.

static func setup_env(parent: Node3D, pillow_color := Color("8e5ac8")) -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = pillow_color.darkened(0.55)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("fff1f4")
	env.ambient_light_energy = 0.32
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	we.environment = env
	parent.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-62, 25, 0)
	key.light_energy = 0.95
	key.light_color = Color("fff4e8")
	key.shadow_enabled = false
	key.shadow_blur = 2.0
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key.directional_shadow_max_distance = 12.0
	parent.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-40, -140, 0)
	fill.light_color = Color("ffd6ea")
	fill.light_energy = 0.28
	parent.add_child(fill)
	var pillow := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(9.0, 6.0)
	pm.subdivide_width = 90
	pm.subdivide_depth = 60
	pillow.mesh = pm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/pillow.gdshader")
	mat.set_shader_parameter("base", pillow_color)
	pillow.material_override = mat
	pillow.position = Vector3(-0.4, -0.52, 0.0)
	parent.add_child(pillow)
