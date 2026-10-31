extends Node
# (dev) capturas para a Play Store: cenas bonitas/nojentas de cada parte do jogo
var out := OS.get_environment("OUT")
var runner

func _ready() -> void:
	for tl in Defs.TOOL_ORDER:
		GameData.owned[tl] = 1
	GameData.sound_on = false
	GameData.set_language("pt", false)
	runner = load("res://tests/test_runner.gd").new()
	add_child(runner)
	await _scene_squeeze()
	await _scene_acne()
	await _scene_beard()
	await _scene_lice()
	await _scene_ointment()
	await _scene_result()
	get_tree().quit()

func _game(lab: Array, part: String, lvl := 12):
	GameData.set_meta("lab_problems", lab)
	GameData.set_meta("lab_part", part)
	GameData.current_level = lvl
	var game = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	while not game.input_ok:
		await get_tree().create_timer(0.2).timeout
	return game

func _hold(game, p: Problem, frames: int, wiggle := 0.0) -> void:
	var c: Vector2 = game.cam.unproject_position(p.center()) - game.TOOL_OFFSET
	game._on_touch(0, c, true)
	game._on_touch(1, game.use_btn.center, true)
	for i in frames:
		game._on_touch_drag(0, c + Vector2(sin(i * 0.4), cos(i * 0.33)) * wiggle, Vector2.ZERO)
		await get_tree().process_frame

func _release(game) -> void:
	game._on_touch(1, game.use_btn.center, false)
	game._on_touch(0, Vector2.ZERO, false)

func _scene_squeeze() -> void:
	var game = await _game(["carbunculo"], "costas")
	var p: Problem = game.problems[0]
	game._focus_on(p)
	await _w(1.0)
	game._select_tool(p.tool())
	await runner.solve(game, p)
	game._select_tool("espremedor")
	await _w(0.6)
	var c: Vector2 = game.cam.unproject_position(p.center()) - game.TOOL_OFFSET
	game._on_touch(0, c, true)
	game._on_touch(1, game.use_btn.center, true)
	var g := 0
	while p.progress < 0.62 and g < 600:
		g += 1
		await get_tree().process_frame
	await _shot("1_espremendo")
	_release(game)
	game.queue_free()
	await _w(0.3)

func _scene_acne() -> void:
	var game = await _game(["acne_costas"], "costas")
	var p: Problem = game.problems[0]
	game._focus_on(p)
	await _w(1.0)
	game._select_tool("espremedor")
	var k := 0
	for it in p.items:
		if k >= 5:
			break
		game._press(game.cam.unproject_position(it["pos"]))
		game._trigger(true)
		await get_tree().process_frame
		game._trigger(false)
		game._release()
		k += 1
		await _w(0.25)
	var last: Dictionary = p.items[6] if p.items.size() > 6 else p.items[0]
	game._on_touch(0, game.cam.unproject_position(last["pos"]) - game.TOOL_OFFSET, true)
	await _w(0.5)
	await _shot("2_acne")
	_release(game)
	game.queue_free()
	await _w(0.3)

func _scene_beard() -> void:
	var game = await _game(["barba"], "rosto")
	var p: Problem = game.problems[0]
	game._focus_on(p)
	await _w(1.0)
	game._select_tool("lamina")
	var c: Vector2 = game.cam.unproject_position(p.center()) + Vector2(-40, 120) - game.TOOL_OFFSET
	game._on_touch(0, c, true)
	game._on_touch(1, game.use_btn.center, true)
	for i in 34:
		game._on_touch_drag(0, c + Vector2(0, -i * 7), Vector2.ZERO)
		await get_tree().process_frame
	await _shot("3_barba")
	_release(game)
	game.queue_free()
	await _w(0.3)

func _scene_lice() -> void:
	var game = await _game(["piolhos"], "cabeca")
	var p: Problem = game.problems[0]
	game._focus_on(p)
	await _w(1.0)
	game._select_tool("pinca")
	var it: Dictionary = p.items[0]
	game._on_touch(0, game.cam.unproject_position(it["pos"]) - game.TOOL_OFFSET, true)
	await _w(1.2)
	await _shot("4_piolhos")
	_release(game)
	game.queue_free()
	await _w(0.3)

func _scene_ointment() -> void:
	var game = await _game(["furunculo"], "pe")
	var p: Problem = game.problems[0]
	game._focus_on(p)
	await _w(1.0)
	while p.tool() != "pomada":
		game._select_tool(p.tool())
		await runner.solve(game, p)
	game._select_tool("pomada")
	await _w(0.8)
	var c: Vector2 = game.cam.unproject_position(p.center()) - game.TOOL_OFFSET
	game._on_touch(0, c, true)
	game._on_touch(1, game.use_btn.center, true)
	for i in 8:
		game._on_touch_drag(0, c + Vector2(cos(i * 1.1), sin(i * 1.1)) * 50.0, Vector2.ZERO)
		await get_tree().process_frame
	await _w(0.3)
	await _shot("5_pomada")
	_release(game)
	game.queue_free()
	await _w(0.3)

func _scene_result() -> void:
	var game = await _game(["abscesso", "espinha", "sujeira"], "mao", 9)
	for p in game.problems:
		while not p.done:
			game._focus_on(p)
			await _w(0.4)
			game._select_tool(p.tool())
			await runner.solve(game, p)
	await _w(7.5)
	await _shot("6_antes_depois")
	game.queue_free()

func _w(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/" + n + ".png")
	print("foto ", n)
