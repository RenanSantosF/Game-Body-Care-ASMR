extends Node
# A pomada tem que aparecer enquanto passa (não só no fim)
func _ready() -> void:
	for tl in Defs.TOOL_ORDER:
		GameData.owned[tl] = 1
	GameData.sound_on = false
	var runner = load("res://tests/test_runner.gd").new()
	add_child(runner)
	GameData.set_meta("lab_problems", ["ralado"])
	GameData.set_meta("lab_part", "mao")
	GameData.current_level = 12
	var game = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	while not game.input_ok:
		await get_tree().create_timer(0.2).timeout
	var p: Problem = game.problems[0]
	game._focus_on(p)
	await get_tree().create_timer(1.0).timeout
	var g := 0
	while p.tool() != "pomada" and g < 10:
		g += 1
		print("etapa ", p.stage, " ", p.tool(), " prog ", p.progress)
		game._select_tool(p.tool())
		await runner.solve(game, p)
	game._select_tool("pomada")
	var c: Vector2 = game.cam.unproject_position(p.center())
	game._press(c)
	game._trigger(true)
	for i in 12:
		game._drag(c + Vector2(cos(i * 0.9), sin(i * 0.9)) * 60.0)
		await get_tree().process_frame
	var mk: CleanMask = p.n["cream"].get_meta("mask") if p.n.has("cream") else null
	var dl: Array = p.n.get("dollops", [])
	print("depois de 12 passadas: creme existe=", mk != null, " cobertura=", snappedf(mk.coverage(), 0.01) if mk else -1.0, " bolinhas=", dl.size(), " etapa=", p.stage, " prog=", snappedf(p.progress, 0.01))
	for i in 120:
		game._drag(c + Vector2(cos(i * 0.3), sin(i * 0.3)) * 50.0)
		await get_tree().process_frame
	var vis := 0
	for b in p.n.get("dollops", []):
		if b.visible: vis += 1
	print("depois de espalhar: cobertura=", snappedf(mk.coverage(), 0.01) if mk else -1.0, " bolinhas visiveis=", vis, " etapa=", p.stage, " (3 = foi pro curativo)")
	game._trigger(false)
	game._release()
	get_tree().quit()
