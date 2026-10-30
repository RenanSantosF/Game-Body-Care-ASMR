extends Node
# Teste automatizado: joga 25 fases simulando o toque.
# Rodar: godot --headless --path . res://tests/test_runner.tscn

func _ready() -> void:
	if get_parent() != get_tree().root:
		return
	for t in Defs.TOOL_ORDER:
		GameData.owned[t] = 1
	GameData.sound_on = false
	Engine.time_scale = 6.0
	Engine.max_fps = 120
	var seen := {}
	var levels := range(1, 26)
	for lvl in levels:
		GameData.current_level = lvl
		var game = load("res://scenes/game.tscn").instantiate()
		add_child(game)
		await _wait(3.2)
		var guard := 0
		while not game.finished and guard < 60:
			guard += 1
			var p: Problem = null
			for q in game.problems:
				if not q.done:
					p = q
					break
			if p == null:
				break
			seen[p.id] = true
			game._focus_on(p)
			await _wait(0.8)
			game._select_tool(p.tool())
			await _solve(game, p)
		print("fase ", lvl, " part=", game.data["part"], " probs=", game.data["problems"], " finished=", game.finished, " mistakes=", game.mistakes)
		await _wait(3.5)
		game.queue_free()
		await _wait(0.2)
	print("tipos testados: ", seen.keys().size(), "/", Defs.PROBLEMS.size(), " ", seen.keys())
	# testa erro de ferramenta e menu
	get_tree().quit()

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _sp(game, pos: Vector3) -> Vector2:
	return game.cam.unproject_position(pos)

func _solve(game, p: Problem) -> void:
	var st := p.stage
	var c := _sp(game, p.global_position)
	match p.mech():
		Defs.Mech.HOLD:
			game._press(c)
			var g := 0
			while p.stage == st and not p.done and g < 400:
				g += 1
				await get_tree().process_frame
			game._release()
		Defs.Mech.RUB, Defs.Mech.CUT:
			game._press(c + Vector2(-30, 0))
			var g := 0
			var k := 0.0
			while p.stage == st and not p.done and g < 2000:
				g += 1
				k += 0.5
				game._drag(c + Vector2(sin(k) * 35.0, cos(k * 0.7) * 15.0))
				await get_tree().process_frame
			game._release()
		Defs.Mech.PULL:
			game._press(c)
			var g := 0
			var pos := c
			while p.stage == st and not p.done and g < 2000:
				g += 1
				pos += Vector2(4, -3) if (g / 20) % 2 == 0 else Vector2(-4, 3)
				game._drag(pos)
				await get_tree().process_frame
			game._release()
		Defs.Mech.TAP:
			game._press(c)
			await get_tree().process_frame
			game._release()
		Defs.Mech.SWEEP, Defs.Mech.PICK:
			var g := 0
			while p.stage == st and not p.done and g < 200:
				g += 1
				for it in p.items:
					if it.get_meta("alive", false):
						var ip := _sp(game, it.global_position)
						game._press(ip)
						game._drag(ip + Vector2(2, 0))
						await get_tree().process_frame
						game._release()
						break
				await get_tree().process_frame
	await _wait(0.2)
