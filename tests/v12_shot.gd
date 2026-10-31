extends Node
# (dev) fotos: bisturi sobre o furúnculo (sem entrar), bolinhas de pomada, pomada espalhando, pinça puxando o verme
var out := OS.get_environment("OUT")
func _ready() -> void:
	for tl in Defs.TOOL_ORDER:
		GameData.owned[tl] = 1
	GameData.sound_on = false
	GameData.set_meta("lab_problems", ["furunculo", "verme"])
	GameData.set_meta("lab_part", "costas")
	GameData.current_level = 12
	var runner = load("res://tests/test_runner.gd").new()
	add_child(runner)
	var game = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	while not game.input_ok:
		await get_tree().create_timer(0.2).timeout
	var fu: Problem = game.problems[0]
	var ve: Problem = game.problems[1]
	game._focus_on(fu)
	await _w(1.0)
	game._select_tool("bisturi")
	var c: Vector2 = game.cam.unproject_position(fu.center())
	game._press(c)
	await _w(0.5)
	await _shot("1_bisturi_sobre_furunculo")
	game._release()
	while fu.tool() != "pomada":
		game._select_tool(fu.tool())
		await runner.solve(game, fu)
	game._select_tool("pomada")
	c = game.cam.unproject_position(fu.center())
	game._press(c)
	game._trigger(true)
	for i in 6:
		game._drag(c + Vector2(cos(i * 1.2), sin(i * 1.2)) * 45.0)
		await get_tree().process_frame
	await _w(0.3)
	await _shot("2_pomada_bolinhas")
	for i in 40:
		game._drag(c + Vector2(cos(i * 0.35), sin(i * 0.35)) * 40.0)
		await get_tree().process_frame
	await _shot("3_pomada_espalhando")
	game._trigger(false)
	game._release()
	# verme: corta e puxa até a metade
	game._focus_on(ve)
	await _w(1.0)
	game._select_tool(ve.tool())
	await runner.solve(game, ve)
	game._select_tool("pinca")
	var vc: Vector2 = game.cam.unproject_position(ve.grip_point())
	game._press(vc)
	game._trigger(true)
	for k in 30:
		game._drag(vc + Vector2(k * 3.0, -k * 2.0))
		await get_tree().process_frame
		if ve.progress > 0.5:
			break
	await _shot("4_pinca_verme")
	get_tree().quit()

func _w(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/" + n + ".png")
