extends Node
# (dev) fotos: curativo colando na unha (meio e fim), pinça aberta/fechada, lixa deitada
var out := OS.get_environment("OUT")
func _ready() -> void:
	for tl in Defs.TOOL_ORDER:
		GameData.owned[tl] = 1
	GameData.sound_on = false
	GameData.set_meta("lab_problems", ["unha_pus", "carbunculo"])
	GameData.set_meta("lab_part", "pe")
	GameData.current_level = 12
	var runner = load("res://tests/test_runner.gd").new()
	add_child(runner)
	var game = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	while not game.input_ok:
		await get_tree().create_timer(0.2).timeout
	var un: Problem
	var cb: Problem
	for q in game.problems:
		if q.id == "unha_pus": un = q
		else: cb = q
	# pinça aberta (só mirando) e fechada (segurando o botão)
	game._focus_on(un)
	await _w(1.0)
	game._select_tool("pinca")
	var c: Vector2 = game.cam.unproject_position(un.center() + Vector3(-0.15, 0, 0.1)) - game.TOOL_OFFSET
	game._on_touch(0, c, true)
	await _w(0.4)
	await _shot("1_pinca_aberta")
	game._on_touch(1, game.use_btn.center, true)
	await _w(0.4)
	await _shot("2_pinca_fechada")
	game._on_touch(1, game.use_btn.center, false)
	game._on_touch(0, c, false)
	# lixa deitada
	game._select_tool("lixa")
	game._on_touch(0, c, true)
	await _w(0.4)
	await _shot("3_lixa")
	game._on_touch(0, c, false)
	# unha: resolve até o curativo e cola pela metade, depois inteiro
	while un.tool() != "curativo":
		game._select_tool(un.tool())
		await runner.solve(game, un)
	game._select_tool("curativo")
	var cu: Vector2 = game.cam.unproject_position(un.center()) + Vector2(0, 110)
	game._press(cu)
	game._trigger(true)
	for k in 10:
		game._drag(cu + Vector2(0, -k * 12.0))
		await get_tree().process_frame
	await _w(0.2)
	await _shot("4_curativo_unha_meio")
	for k in range(10, 24):
		game._drag(cu + Vector2(0, -k * 12.0))
		await get_tree().process_frame
	game._trigger(false)
	game._release()
	await _w(1.0)
	await _shot("5_curativo_unha")
	# carbúnculo até o curativo
	game._focus_on(cb)
	await _w(1.0)
	while not cb.done:
		game._select_tool(cb.tool())
		await runner.solve(game, cb)
		if cb.tool() == "curativo":
			await _w(0.6)
			await _shot("6_carbunculo_pomada")
	await _w(1.0)
	await _shot("7_carbunculo_curativo")
	get_tree().quit()

func _w(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/" + n + ".png")
