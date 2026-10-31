extends Node
# (dev) menu e jogo em outro idioma (LANG=en|es)
func _ready() -> void:
	var out := OS.get_environment("OUT")
	GameData.set_language(OS.get_environment("LANG_GAME"), false)
	GameData.last_daily = Time.get_date_string_from_system()
	var m = load("res://scenes/main_menu.tscn").instantiate()
	add_child(m)
	await get_tree().create_timer(3.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/menu.png")
	m.queue_free()
	GameData.set_meta("lab_problems", ["espinhos", "acne_costas"])
	GameData.set_meta("lab_part", "mao")
	GameData.current_level = 12
	var game = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	while not game.input_ok:
		await get_tree().create_timer(0.2).timeout
	game._focus_on(game.problems[0])
	game._select_tool("pinca")
	await get_tree().create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/game.png")
	get_tree().quit()
