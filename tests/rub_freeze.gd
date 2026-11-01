extends Node
# (dev) reproduz: espinha no rosto, etapa do algodão, esfregando por muito tempo com toques reais
var runner
var worst := 0.0
var frames := 0

func _ready() -> void:
	for tl in Defs.TOOL_ORDER:
		GameData.owned[tl] = 1
	GameData.sound_on = false
	runner = load("res://tests/test_runner.gd").new()
	add_child(runner)
	GameData.set_meta("lab_problems", ["espinha", "espinha", "cravos"])
	GameData.set_meta("lab_part", "rosto")
	GameData.current_level = 4
	var game = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	while not game.input_ok:
		await get_tree().create_timer(0.2).timeout
	var p: Problem = game.problems[0]
	game._focus_on(p)
	await get_tree().create_timer(1.0).timeout
	for i in 2:
		game._select_tool(p.tool())
		await runner.solve(game, p)
	print("etapa ", p.stage, " ", p.tool())
	game._select_tool("algodao")
	var c: Vector2 = game.cam.unproject_position(p.center()) - game.TOOL_OFFSET
	game._on_touch(0, c, true)
	game._on_touch(1, game.use_btn.center, true)
	var t0 := Time.get_ticks_msec()
	var last := t0
	for g in 900:
		var a := g * 0.3
		var rr := 260.0 * (0.5 + 0.5 * sin(g * 0.017))
		game._on_touch_drag(0, c + Vector2(cos(a), sin(a)) * rr, Vector2.ZERO)
		if g % 300 == 150:
			game._on_touch(1, game.use_btn.center, false)
			game._on_touch(1, game.use_btn.center, true)
		await get_tree().process_frame
		var n := Time.get_ticks_msec()
		worst = maxf(worst, n - last)
		last = n
		if g % 400 == 0:
			print("g=", g, " prog=", snappedf(p.progress, 0.01), " stage=", p.stage, " done=", p.done, " worst_ms=", worst, " stains=", game.body.stains.size(), " nodes=", get_tree().get_node_count())
			worst = 0.0
	print("FIM total_ms=", Time.get_ticks_msec() - t0)
	get_tree().quit()
