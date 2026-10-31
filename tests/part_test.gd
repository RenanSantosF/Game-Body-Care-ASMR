extends Node
# Resolve problemas forçados numa parte do corpo (PART=costas FORCE=a,b,c)
func _ready() -> void:
	for tl in Defs.TOOL_ORDER:
		GameData.owned[tl] = 1
	GameData.sound_on = false
	Engine.time_scale = 6.0
	var runner = load("res://tests/test_runner.gd").new()
	add_child(runner)
	GameData.set_meta("lab_problems", Array(OS.get_environment("FORCE").split(",")))
	GameData.set_meta("lab_part", OS.get_environment("PART"))
	GameData.current_level = 14
	var game = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	while not game.input_ok:
		await get_tree().create_timer(0.2).timeout
	print("problemas colocados: ", game.problems.map(func(q): return q.id))
	var seen := {}
	await runner.play(game, seen)
	print(OS.get_environment("PART"), " fim=", game.finished, " ", game.data["problems"])
	await get_tree().create_timer(4.0).timeout
	get_tree().quit()
