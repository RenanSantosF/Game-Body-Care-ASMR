extends Node
# (dev) foto do erro: bisturi arrastado em cima da ferida (LAB/PART)
var out := OS.get_environment("OUT")
func _ready() -> void:
	for tl in Defs.TOOL_ORDER:
		GameData.owned[tl] = 1
	GameData.sound_on = false
	GameData.set_meta("lab_problems", Array(OS.get_environment("LAB").split(",")))
	GameData.set_meta("lab_part", OS.get_environment("PART"))
	GameData.current_level = 12
	var game = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	while not game.input_ok:
		await get_tree().create_timer(0.2).timeout
	var p: Problem = game.problems[0]
	game._focus_on(p)
	await get_tree().create_timer(1.5).timeout
	await _shot("a_antes")
	game._select_tool("bisturi")
	var c: Vector2 = game.cam.unproject_position(p.center())
	game._press(c + Vector2(-50, -20))
	game._trigger(true)
	for i in 14:
		game._drag(c + Vector2(-50 + i * 7, -20 + i * 3))
		await get_tree().process_frame
	game._trigger(false)
	game._release()
	await get_tree().create_timer(2.5).timeout
	await _shot("b_depois_do_erro")
	get_tree().quit()

func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/" + n + ".png")
