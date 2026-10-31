extends Node
# Ferramenta errada em cima do problema: piora ali mesmo, cria etapas extras e a fase ainda termina.

func _ready() -> void:
	for tl in Defs.TOOL_ORDER:
		GameData.owned[tl] = 1
	GameData.sound_on = false
	var runner = load("res://tests/test_runner.gd").new()
	add_child(runner)
	for case in [["espinha", "bisturi"], ["furunculo", "lixa"], ["favo", "bisturi"]]:
		GameData.set_meta("lab_problems", [case[0]])
		GameData.set_meta("lab_part", "pe")
		GameData.current_level = 12
		var game = load("res://scenes/game.tscn").instantiate()
		add_child(game)
		while not game.input_ok:
			await get_tree().create_timer(0.2).timeout
		var p: Problem = game.problems[0]
		game._focus_on(p)
		await get_tree().create_timer(1.0).timeout
		var st0: int = p.def["stages"].size()
		var tot0: int = game.total_stages
		game._select_tool(case[1])
		var c: Vector2 = game.cam.unproject_position(p.center())
		game._press(c)
		game._trigger(true)
		for i in 20:
			game._drag(c + Vector2(-60 + i * 6, sin(i * 0.6) * 10))
			await get_tree().process_frame
		game._trigger(false)
		game._release()
		await get_tree().create_timer(0.5).timeout
		var fx: FxMap = p.n["aggr"].get_meta("fx") if p.n.has("aggr") else null
		print(case, ": dano=", p.damage, " etapas ", st0, "->", p.def["stages"].size(), " total ", tot0, "->", game.total_stages,
			" sangue=", snappedf(fx.blood_total(), 0.0001) if fx else -1.0, " corte_pts=", fx.cut_pts.size() if fx else 0, " dor=", int(game.pain), " ganho=", game.earned,
			" defs_intactas=", Defs.PROBLEMS[case[0]]["stages"].size() == st0)
		var g := 0
		while not p.done and g < 20:
			g += 1
			game._focus_on(p)
			await get_tree().create_timer(0.6).timeout
			game._select_tool(p.tool())
			await runner.solve(game, p)
		await get_tree().create_timer(4.0).timeout
		print("   terminou=", p.done, " fase_fim=", game.finished)
		game.queue_free()
		await get_tree().create_timer(0.3).timeout
	get_tree().quit()
