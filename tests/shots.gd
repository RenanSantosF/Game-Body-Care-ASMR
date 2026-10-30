extends Node
# (dev) captura telas jogando uma fase
var out := OS.get_environment("OUT")

func _ready() -> void:
	for tl in Defs.TOOL_ORDER:
		GameData.owned[tl] = 1
	GameData.sound_on = false
	var runner = load("res://tests/test_runner.gd").new()
	add_child(runner)
	var lvl := int(OS.get_environment("LVL")) if OS.get_environment("LVL") != "" else 12
	if OS.get_environment("LAB") != "":
		GameData.set_meta("lab_problems", Array(OS.get_environment("LAB").split(",")))
		GameData.set_meta("lab_part", OS.get_environment("PART") if OS.get_environment("PART") != "" else "mao")
	GameData.current_level = lvl
	var game = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	await _wait(0.5)
	await _shot("L%d_00_wide" % lvl)
	await _wait(3.0)
	if OS.get_environment("CUTSKIN") != "":
		# corte errado na pele saudável, depois espera sangrar
		game._go_wide()
		await _wait(0.8)
		var c0: Vector3 = game.body.cam_center + Vector3(-0.25, 0, 0.15)
		var s0 = game.body.surface(c0.x, c0.z)
		game._focus_on(game.problems[0])
		await _wait(0.9)
		game.cam_look = s0[0]
		game.cam_pos = s0[0] + Vector3(-0.35, 0.85, 0)
		await _wait(0.3)
		game._select_tool("bisturi")
		var a: Vector2 = game.cam.unproject_position(s0[0])
		game._press(a)
		for f in 30:
			game._drag(a + Vector2(f * 4.0, sin(f * 0.3) * 6.0 - f * 1.5))
			await get_tree().process_frame
		game._release()
		await _shot("L%d_80_corte_pele_0s" % lvl)
		await _wait(2.0)
		await _shot("L%d_81_corte_pele_2s" % lvl)
		await _wait(3.0)
		await _shot("L%d_82_corte_pele_5s" % lvl)
	var i := 0
	var only := OS.get_environment("ONLY")
	for p in game.problems.duplicate():
		if only != "" and p.id != only:
			continue
		i += 1
		game._focus_on(p)
		await _wait(0.9)
		game._select_tool(p.tool())
		await _shot("L%d_%02d_%s_a" % [lvl, i, p.id])
		var k := 0
		while not p.done and k < 8:
			k += 1
			# meio da etapa: começa e tira foto
			await _partial(game, p)
			await _shot("L%d_%02d_%s_s%d_mid" % [lvl, i, p.id, k])
			game._release()
			game._select_tool(p.tool())
			await runner.solve(game, p)
			game._select_tool(p.tool() if not p.done else game.selected)
			await _wait(0.3)
			await _shot("L%d_%02d_%s_s%d_end" % [lvl, i, p.id, k])
	for p in game.problems:
		while not p.done:
			game._focus_on(p)
			await _wait(0.5)
			game._select_tool(p.tool())
			await runner.solve(game, p)
	await _wait(4.5)
	await _shot("L%d_99_result" % lvl)
	get_tree().quit()

func _partial(game, p: Problem) -> void:
	var c: Vector2 = game.cam.unproject_position(p.center())
	game._press(c)
	match p.mech():
		Defs.Mech.HOLD:
			for f in 20:
				await get_tree().process_frame
		Defs.Mech.PULL:
			for f in 25:
				game._drag(c + Vector2(f * 2.5, -f * 1.5))
				await get_tree().process_frame
		Defs.Mech.RUB:
			for f in 40:
				game._drag(c + Vector2(cos(f * 0.4), sin(f * 0.4)) * 25.0)
				await get_tree().process_frame
		Defs.Mech.CUT:
			game._release()
			var path: PackedVector3Array = p.cut_path
			game._press(game.cam.unproject_position(path[0]))
			for j in range(1, path.size() / 2 + 1):
				var a2: Vector2 = game.cam.unproject_position(path[j - 1])
				var b2: Vector2 = game.cam.unproject_position(path[j])
				for k in 5:
					game._drag(a2.lerp(b2, (k + 1) / 5.0))
					await get_tree().process_frame
			for f in 40:
				await get_tree().process_frame
		_:
			await get_tree().process_frame

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/" + n + ".png")
