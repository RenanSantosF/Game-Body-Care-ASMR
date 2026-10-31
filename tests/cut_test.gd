extends Node
# Um único corte reto atravessando o furúnculo/abscesso deve concluir a etapa do bisturi.

func _ready() -> void:
	for tl in Defs.TOOL_ORDER:
		GameData.owned[tl] = 1
	GameData.sound_on = false
	for id in ["furunculo", "abscesso"]:
		for part in ["pe", "mao"]:
			GameData.set_meta("lab_problems", [id])
			GameData.set_meta("lab_part", part)
			GameData.current_level = 12
			var game = load("res://scenes/game.tscn").instantiate()
			add_child(game)
			while not game.input_ok:
				await get_tree().create_timer(0.2).timeout
			var p: Problem = game.problems[0]
			game._focus_on(p)
			await get_tree().create_timer(1.0).timeout
			game._select_tool("bisturi")
			var a: Vector2 = game.cam.unproject_position(p.cut_path[0])
			var b: Vector2 = game.cam.unproject_position(p.cut_path[p.cut_path.size() - 1])
			game._press(a)
			game._trigger(true)
			for i in 16:
				game._drag(a.lerp(b, (i + 1) / 16.0))
				await get_tree().process_frame
			game._trigger(false)
			game._release()
			print(id, " ", part, ": etapa=", p.stage, " (1 = cortou com um corte só) prog=", snappedf(p.progress, 0.01))
			game.queue_free()
			await get_tree().create_timer(0.2).timeout
	get_tree().quit()
