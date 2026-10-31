extends Node
# Botão de segurar: mirar com um dedo + segurar o botão = usa. Em qualquer ordem.
func _ready() -> void:
	for tl in Defs.TOOL_ORDER:
		GameData.owned[tl] = 1
	GameData.sound_on = false
	GameData.set_meta("lab_problems", ["sujeira"])
	GameData.set_meta("lab_part", "mao")
	GameData.current_level = 12
	var game = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	while not game.input_ok:
		await get_tree().create_timer(0.2).timeout
	var p: Problem = game.problems[0]
	game._focus_on(p)
	await get_tree().create_timer(1.0).timeout
	game._select_tool("pano")
	await get_tree().process_frame
	var b: Vector2 = game.use_btn.center
	var aim: Vector2 = game.cam.unproject_position(p.center()) - game.TOOL_OFFSET
	# toque fora do botão sozinho: só mira
	game._on_touch(0, aim, true)
	await get_tree().process_frame
	print("so mirando: pressing=", game.pressing, " triggering=", game.triggering)
	game._on_touch(1, b, true)
	print("mirando + botao: triggering=", game.triggering, " held=", game.use_btn.held)
	for i in 30:
		game._on_touch_drag(0, aim + Vector2(sin(i * 0.5) * 40, cos(i * 0.4) * 30), Vector2.ZERO)
		await get_tree().process_frame
	print("limpou algo=", snappedf(p.progress, 0.01))
	game._on_touch(1, b, false)
	print("soltou botao: triggering=", game.triggering, " pressing=", game.pressing)
	game._on_touch(0, aim, false)
	# ordem inversa: segura o botão antes e depois mira
	game._on_touch(3, b, true)
	game._on_touch(4, aim, true)
	await get_tree().process_frame
	print("botao antes, depois mira: triggering=", game.triggering)
	game._on_touch(4, aim, false)
	game._on_touch(3, b, false)
	print("tudo solto: triggering=", game.triggering, " pressing=", game.pressing, " btn=", b)
	get_tree().quit()
