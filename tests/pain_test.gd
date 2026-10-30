extends Node
# Teste: ferramenta errada machuca, cria ferida e o paciente vai embora com dor 100.

func _ready() -> void:
	for tl in Defs.TOOL_ORDER:
		GameData.owned[tl] = 1
	GameData.sound_on = false
	GameData.current_level = 1
	var game = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	await get_tree().create_timer(3.2).timeout
	var p: Problem = null
	for q in game.problems:
		if q.id == "espinha":
			p = q
	game._focus_on(p)
	await get_tree().create_timer(1.0).timeout
	game._select_tool("bisturi")
	var n0: int = game.problems.size()
	for i in 12:
		var c: Vector2 = game.cam.unproject_position(p.center())
		game._press(c)
		game._trigger(true)
		game._trigger(false)
		game._release()
		await get_tree().create_timer(0.9).timeout
		if game.finished:
			break
	print("erros=", game.mistakes, " dor=", int(game.pain), " feridas=", game.problems.size() - n0, " perdeu=", game.finished and game.modal_open)
	# resolve um machucado
	var w: Problem = null
	for q in game.problems:
		if q.id == "machucado":
			w = q
	print("machucado criado: ", w != null)
	var out := OS.get_environment("OUT")
	if out != "":
		await get_tree().create_timer(1.6).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out + "/fail.png")
	get_tree().quit()
