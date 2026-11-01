extends Node
# (dev) progresso dentro da fase: trata alguns problemas, "trava" (recarrega) e confere que continua
var runner

func _game():
	var game = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	while not game.input_ok:
		await get_tree().create_timer(0.2).timeout
	return game

func _ready() -> void:
	for tl in Defs.TOOL_ORDER:
		GameData.owned[tl] = 1
	GameData.sound_on = false
	runner = load("res://tests/test_runner.gd").new()
	add_child(runner)
	for lvl in [6, 11, 15]:
		GameData.current_level = lvl
		var game = await _game()
		var n: int = game.problems.size()
		var want := []
		for i in n - 1:
			var p: Problem = game.problems[i]
			game._focus_on(p)
			await get_tree().create_timer(0.3).timeout
			game._select_tool(p.tool())
			await runner.solve(game, p)
		# uma etapa do último
		var lp: Problem = game.problems[n - 1]
		game._focus_on(lp)
		await get_tree().create_timer(0.3).timeout
		game._select_tool(lp.tool())
		if lp.def["stages"].size() > 1:
			await runner.solve(game, lp)
		for p in game.problems:
			want.append(-1 if p.done else p.stage)
		var earned: int = game.earned
		game.queue_free()
		await get_tree().process_frame
		var g2 = await _game()
		var got := []
		for p in g2.problems:
			if p.has_meta("idx"):
				got.append(-1 if p.done else p.stage)
		print("fase ", lvl, " antes=", want, " depois=", got, " moedas ", earned, "/", g2.earned, " -> ", "OK" if str(want.slice(0, got.size())) == str(got) else "FALHOU")
		# termina a fase
		for p in g2.problems:
			while not p.done:
				g2._focus_on(p)
				await get_tree().create_timer(0.3).timeout
				g2._select_tool(p.tool())
				await runner.solve(g2, p)
		await get_tree().create_timer(4.0).timeout
		print("terminou: ", g2.finished, " checkpoint apagado: ", not FileAccess.file_exists("user://checkpoint.json"))
		g2.queue_free()
		await get_tree().process_frame
	get_tree().quit()
