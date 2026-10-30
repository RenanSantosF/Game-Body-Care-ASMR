extends Node
## Renderiza as ferramentas 3D como ícones bonitos (uma vez, em segundo plano).

signal icon_ready(id: String)

var cache := {}
var queue: Array = []
var busy := false

func get_tex(id: String) -> Texture2D:
	if cache.has(id):
		return cache[id]
	if not queue.has(id) and DisplayServer.get_name() != "headless":
		queue.append(id)
	return null

func _process(_d: float) -> void:
	if busy or queue.is_empty():
		return
	busy = true
	_render(queue.pop_front())

func _render(id: String) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(200, 200)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var root := Node3D.new()
	vp.add_child(root)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 0.97, 1)
	env.ambient_light_energy = 0.6
	we.environment = env
	root.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 35, 0)
	key.light_energy = 1.3
	root.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, -150, 0)
	rim.light_energy = 0.6
	rim.light_color = Color("ffd0ec")
	root.add_child(rim)
	var tm := ToolModel.new()
	root.add_child(tm)
	tm.set_tool(id)
	tm.rotation = Vector3(0.35, 0.5, -0.75)
	await get_tree().process_frame
	# enquadra a ferramenta pelo tamanho real
	var box := AABB()
	var first := true
	for mi in tm.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var b := m.global_transform * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(maxf(box.size.x, box.size.y), 0.05) * 1.18
	root.add_child(cam)
	var c := box.get_center()
	cam.position = Vector3(c.x, c.y, c.z + 2.0)
	cam.current = true
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if img:
		img.convert(Image.FORMAT_RGBA8)
		cache[id] = ImageTexture.create_from_image(img)
		icon_ready.emit(id)
	vp.queue_free()
	busy = false
