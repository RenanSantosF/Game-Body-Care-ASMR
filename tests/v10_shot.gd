extends Node
# (dev) fotos: barbeador em uso, pano esfregando, pomada branca e curativo por cima
var out := OS.get_environment("OUT")
func _ready() -> void:
	for tl in Defs.TOOL_ORDER:
		GameData.owned[tl] = 1
	GameData.sound_on = false
	GameData.set_meta("lab_problems", ["pelos", "ralado"])
	GameData.set_meta("lab_part", "mao")
	GameData.current_level = 12
	var runner = load("res://tests/test_runner.gd").new()
	add_child(runner)
	var game = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	while not game.input_ok:
		await get_tree().create_timer(0.2).timeout
	var hair: Problem = game.problems[0]
	var rl: Problem = game.problems[1]
	# barbeador
	game._focus_on(hair)
	await _w(1.0)
	game._select_tool("lamina")
	var c: Vector2 = game.cam.unproject_position(hair.center())
	var start: Vector2 = c + Vector2(-20, 60) - game.TOOL_OFFSET
	game._on_touch(0, start, true)
	game._on_touch(1, game.use_btn.center, true)
	for i in 24:
		game._on_touch_drag(0, start + Vector2(0, -i * 6), Vector2.ZERO)
		await get_tree().process_frame
	await _shot("1_barbeador")
	game._on_touch(1, game.use_btn.center, false)
	game._on_touch(0, start, false)
	# ralado: pinça (robô), depois pano esfregando
	game._focus_on(rl)
	await _w(1.0)
	game._select_tool(rl.tool())
	await runner.solve(game, rl)
	game._select_tool("pano")
	var c2: Vector2 = game.cam.unproject_position(rl.center()) - game.TOOL_OFFSET
	game._on_touch(0, c2, true)
	game._on_touch(1, game.use_btn.center, true)
	for i in 30:
		game._on_touch_drag(0, c2 + Vector2(sin(i * 0.45) * 50, cos(i * 0.35) * 30), Vector2.ZERO)
		await get_tree().process_frame
	await _shot("2_pano")
	game._on_touch(1, game.use_btn.center, false)
	game._on_touch(0, c2, false)
	game._select_tool(rl.tool())
	await runner.solve(game, rl)
	# pomada: espalha um pouco (meio da etapa) e tira foto
	game._select_tool("pomada")
	game._on_touch(0, c2, true)
	game._on_touch(1, game.use_btn.center, true)
	for i in 40:
		game._on_touch_drag(0, c2 + Vector2(sin(i * 0.5) * 45, cos(i * 0.31) * 35), Vector2.ZERO)
		await get_tree().process_frame
	await _shot("3_pomada")
	game._on_touch(1, game.use_btn.center, false)
	game._on_touch(0, c2, false)
	while not rl.done:
		game._select_tool(rl.tool())
		await runner.solve(game, rl)
	await _w(1.0)
	await _shot("4_curativo")
	get_tree().quit()

func _w(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/" + n + ".png")
