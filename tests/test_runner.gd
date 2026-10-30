extends Node
# Teste automatizado: joga várias fases simulando o toque.
# Rodar: godot --headless --path . res://tests/test_runner.tscn

func _ready() -> void:
	if get_parent() != get_tree().root:
		return
	for tl in Defs.TOOL_ORDER:
		GameData.owned[tl] = 1
	GameData.sound_on = false
	Engine.time_scale = 6.0
	var seen := {}
	var last := int(OS.get_environment("LEVELS")) if OS.get_environment("LEVELS") != "" else 20
	var first := int(OS.get_environment("START")) if OS.get_environment("START") != "" else 1
	for lvl in range(first, last + 1):
		GameData.current_level = lvl
		var game = load("res://scenes/game.tscn").instantiate()
		add_child(game)
		await _wait(3.2)
		await play(game, seen)
		print("fase ", lvl, " ", game.data["part"], " ", game.data["problems"], " fim=", game.finished, " dor_max=", int(game.max_pain), " erros=", game.mistakes)
		await _wait(3.5)
		game.queue_free()
		await _wait(0.2)
	print("tipos testados: ", seen.keys().size(), "/", Defs.PROBLEMS.size() - 1, " ", seen.keys())
	get_tree().quit()

func play(game, seen: Dictionary) -> void:
	var guard := 0
	var tries := {}
	while not game.finished and guard < 80:
		guard += 1
		var p: Problem = null
		for q in game.problems:
			if not q.done:
				p = q
				break
		if p == null:
			break
		seen[p.id] = true
		var key := "%s_%d_%d" % [p.id, p.get_instance_id(), p.stage]
		tries[key] = tries.get(key, 0) + 1
		if tries[key] > 4:
			print("   TRAVOU: ", p.id, " etapa ", p.stage, " ", p.tool(), " prog ", p.progress)
			break
		game._focus_on(p)
		await _wait(0.8)
		game._select_tool(p.tool())
		if OS.get_environment("VERBOSE") != "":
			print("   ", p.id, " etapa ", p.stage, " ", p.tool(), " mech ", p.mech(), " prog ", snappedf(p.progress, 0.01), " dor ", int(game.pain), " erros ", game.mistakes)
		await solve(game, p)

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _sp(game, pos: Vector3) -> Vector2:
	return game.cam.unproject_position(pos)

func solve(game, p: Problem) -> void:
	var st := p.stage
	var c := _sp(game, p.center())
	match p.mech():
		Defs.Mech.HOLD:
			game._press(c)
			game._trigger(true)
			var g := 0
			while p.stage == st and not p.done and g < 500:
				g += 1
				await get_tree().process_frame
			game._trigger(false)
			game._release()
		Defs.Mech.RUB:
			var R: float = game._screen_radius(p) * 1.25
			game._press(c)
			var g := 0
			while p.stage == st and not p.done and g < 3000:
				g += 1
				var a := g * 0.35
				var rr := R * (0.5 + 0.5 * sin(g * 0.021))
				game._drag(c + Vector2(cos(a), sin(a)) * rr)
				await get_tree().process_frame
			game._release()
		Defs.Mech.CUT:
			var path: PackedVector3Array = p.cut_path
			game._press(_sp(game, path[0]))
			for i in range(1, path.size()):
				var a2 := _sp(game, path[i - 1])
				var b2 := _sp(game, path[i])
				for k in 4:
					game._drag(a2.lerp(b2, (k + 1) / 4.0))
					await get_tree().process_frame
			game._release()
		Defs.Mech.PULL:
			# pega com o segundo dedo, puxa, solta e pega de novo (mão sobre mão)
			game._press(c)
			var g := 0
			while p.stage == st and not p.done and g < 40:
				g += 1
				game._drag(c)
				game._trigger(true)
				for k in 60:
					game._drag(c + Vector2(k * 3.0, -k * 2.0))
					await get_tree().process_frame
					if p.stage != st or p.done:
						break
				game._trigger(false)
				await get_tree().process_frame
			game._release()
		Defs.Mech.TAP:
			game._press(c)
			game._trigger(true)
			await get_tree().process_frame
			game._trigger(false)
			game._release()
		Defs.Mech.SWEEP, Defs.Mech.PICK:
			var g := 0
			while p.stage == st and not p.done and g < 300:
				g += 1
				for it in p.items:
					if it["alive"]:
						var ip := _sp(game, it["pos"])
						game._press(ip)
						game._drag(ip + Vector2(2, 0))
						if p.mech() == Defs.Mech.PICK:
							game._trigger(true)
						await get_tree().process_frame
						game._trigger(false)
						game._release()
						break
				await get_tree().process_frame
	await _wait(0.2)
