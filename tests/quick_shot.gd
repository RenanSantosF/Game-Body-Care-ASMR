extends Node
# (dev) foto rápida de cada problema, sem resolver — para conferir visual/shaders
var out := OS.get_environment("OUT")

func _ready() -> void:
	GameData.sound_on = false
	GameData.set_meta("lab_problems", Array(OS.get_environment("LAB").split(",")))
	GameData.set_meta("lab_part", OS.get_environment("PART") if OS.get_environment("PART") != "" else "mao")
	GameData.current_level = 12
	var game = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	await get_tree().create_timer(0.5).timeout
	var i := 0
	for p in game.problems:
		i += 1
		game._focus_on(p)
		game.cam_dist = game.cam_dist
		await get_tree().create_timer(2.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out + "/%02d_%s.png" % [i, p.id])
	get_tree().quit()
