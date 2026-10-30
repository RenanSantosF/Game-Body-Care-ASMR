extends Node
# (dev) treinador dos dois dedos + curativo colado
func _ready() -> void:
	var out := OS.get_environment("OUT")
	for tl in Defs.TOOL_ORDER:
		GameData.owned[tl] = 1
	GameData.set_meta("lab_problems", ["bolha"])
	GameData.set_meta("lab_part", "mao")
	GameData.current_level = 2
	var g = load("res://scenes/game.tscn").instantiate()
	add_child(g)
	var runner = load("res://tests/test_runner.gd").new()
	add_child(runner)
	await get_tree().create_timer(3.5).timeout
	var p: Problem = g.problems[0]
	g._select_tool("agulha")
	var c: Vector2 = g.cam.unproject_position(p.center())
	g._press(c)
	await get_tree().create_timer(1.6).timeout
	await _shot(out + "/coach.png")
	g._release()
	while not p.done:
		g._select_tool(p.tool())
		await runner.solve(g, p)
	await get_tree().create_timer(1.5).timeout
	await _shot(out + "/curativo.png")
	get_tree().quit()

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
