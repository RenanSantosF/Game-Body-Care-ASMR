extends Node
# Controle total: ferramenta de etapa feita não machuca; lixa só na horizontal; pele boa machuca.
func _ready() -> void:
	for tl in Defs.TOOL_ORDER:
		GameData.owned[tl] = 1
	GameData.sound_on = false
	var runner = load("res://tests/test_runner.gd").new()
	add_child(runner)
	GameData.set_meta("lab_problems", ["espinha", "calo"])
	GameData.set_meta("lab_part", "pe")
	GameData.current_level = 12
	var game = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	while not game.input_ok:
		await get_tree().create_timer(0.2).timeout
	var esp: Problem = game.problems[0]
	var calo: Problem = game.problems[1]
	game._focus_on(esp)
	await get_tree().create_timer(1.0).timeout
	game._select_tool("agulha")
	await runner.solve(game, esp)
	var m0: int = game.mistakes
	game._select_tool("agulha")
	var c: Vector2 = game.cam.unproject_position(esp.center())
	game._press(c)
	game._trigger(true)
	game._drag(c + Vector2(5, 0))
	game._trigger(false)
	game._release()
	print("agulha de novo na espinha (etapa já feita): erros ", m0, "->", game.mistakes, " (tem que ser igual)")
	# lixa no calo: precisa terminar o raspador antes
	game._focus_on(calo)
	await get_tree().create_timer(1.0).timeout
	game._select_tool(calo.tool())
	await runner.solve(game, calo)
	game._select_tool("lixa")
	var cc: Vector2 = game.cam.unproject_position(calo.center())
	game._press(cc)
	game._trigger(true)
	var p0: float = calo.progress
	for i in 30:
		game._drag(cc + Vector2(0, sin(i * 0.5) * 40))
		await get_tree().process_frame
	var p1: float = calo.progress
	for i in 30:
		game._drag(cc + Vector2(sin(i * 0.5) * 40, 0))
		await get_tree().process_frame
	var p2: float = calo.progress
	game._trigger(false)
	game._release()
	print("lixa vertical: ", snappedf(p1 - p0, 0.001), " (0)  horizontal: ", snappedf(p2 - p1, 0.001), " (>0)")
	# pele boa: espremedor belisca, lixa esfola
	var skin_pt: Vector3 = esp.center() + Vector3(0.0, 0, 0.22)
	var sp: Array = game.body.surface(skin_pt.x, skin_pt.z)
	game._focus_on(esp)
	await get_tree().create_timer(0.8).timeout
	var s2: Vector2 = game.cam.unproject_position(sp[0])
	var m1: int = game.mistakes
	var n1: int = game.problems.size()
	game._select_tool("espremedor")
	game._press(s2)
	game._trigger(true)
	game._trigger(false)
	game._release()
	await get_tree().create_timer(1.2).timeout
	print("espremedor na pele boa: erros ", m1, "->", game.mistakes, " problemas ", n1, "->", game.problems.size(), " (só marca roxa)")
	game._select_tool("lixa")
	game._press(s2 + Vector2(20, 0))
	game._trigger(true)
	for i in 10:
		game._drag(s2 + Vector2(20 + i * 6, 0))
		await get_tree().process_frame
	game._trigger(false)
	game._release()
	print("lixa na pele boa: erros ->", game.mistakes, " problemas ->", game.problems.size(), " (esfolado = +1)")
	get_tree().quit()
