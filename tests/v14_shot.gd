extends Node
# (dev) acne: pus aparece aos poucos; abscesso: pomada grossa sem redemoinho; antes/depois
var out := OS.get_environment("OUT")
func _ready() -> void:
	for tl in Defs.TOOL_ORDER:
		GameData.owned[tl] = 1
	GameData.sound_on = false
	GameData.set_meta("lab_problems", ["acne_costas", "abscesso"])
	GameData.set_meta("lab_part", "costas")
	GameData.current_level = 13
	var runner = load("res://tests/test_runner.gd").new()
	add_child(runner)
	var game = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	while not game.input_ok:
		await get_tree().create_timer(0.2).timeout
	var ac: Problem = game.problems[0]
	var ab: Problem = game.problems[1]
	game._focus_on(ac)
	await _w(1.0)
	game._select_tool("espremedor")
	# espreme 4 espinhas e tira foto (pus só em volta delas)
	var k := 0
	for it in ac.items:
		if k >= 4:
			break
		var ip: Vector2 = game.cam.unproject_position(it["pos"])
		game._press(ip)
		game._trigger(true)
		await get_tree().process_frame
		game._trigger(false)
		game._release()
		k += 1
	await _w(0.6)
	await _shot("1_acne_4_espremidas")
	while not ac.done:
		game._select_tool(ac.tool())
		await runner.solve(game, ac)
		if ac.tool() == "pomada":
			await _w(0.8)
			await _shot("2_acne_limpa_antes_pomada")
	await _w(1.0)
	await _shot("3_acne_final")
	game._focus_on(ab)
	await _w(1.0)
	while ab.tool() != "pomada":
		game._select_tool(ab.tool())
		await runner.solve(game, ab)
	await _w(1.0)
	await _shot("4_abscesso_antes_pomada")
	while ab.tool() == "pomada":
		game._select_tool(ab.tool())
		await runner.solve(game, ab)
	await _w(1.0)
	await _shot("5_abscesso_com_pomada")
	while not ab.done:
		game._select_tool(ab.tool())
		await runner.solve(game, ab)
	await _w(7.0)
	await _shot("6_resultado")
	get_tree().quit()

func _w(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/" + n + ".png")
