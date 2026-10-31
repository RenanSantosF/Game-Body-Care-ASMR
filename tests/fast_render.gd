extends Node
# (dev) passa por uma fase inteira com renderização real concluindo cada etapa direto
# (todos os efeitos de fim de etapa, curativos, cicatrizes, fim de fase e tela de resultado).
# LVL=8 xvfb-run godot --path . --rendering-driver opengl3 res://tests/fast_render.tscn

func _ready() -> void:
	for tl in Defs.TOOL_ORDER:
		GameData.owned[tl] = 1
	GameData.sound_on = false
	GameData.current_level = int(OS.get_environment("LVL")) if OS.get_environment("LVL") != "" else 8
	var game = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	while not game.input_ok:
		await get_tree().create_timer(0.2).timeout
	for p in game.problems:
		while not p.done:
			game._focus_on(p)
			game._select_tool(p.tool())
			await get_tree().create_timer(0.5).timeout
			print("etapa ", p.id, " ", p.stage, " ", p.tool())
			p._complete_stage()
			await get_tree().create_timer(0.6).timeout
	print("todas concluídas, esperando resultado")
	var g := 0
	while not game.modal_open and g < 200:
		g += 1
		await get_tree().create_timer(0.1).timeout
	await get_tree().create_timer(3.0).timeout
	print("RESULTADO OK modal=", game.modal_open)
	get_tree().quit()
