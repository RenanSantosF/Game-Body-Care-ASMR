extends Node
# (dev) para cada fase 1..20 e cada etapa intermediária: recupera e termina a fase
var runner

func _ready() -> void:
	for tl in Defs.TOOL_ORDER:
		GameData.owned[tl] = 1
	GameData.sound_on = false
	runner = load("res://tests/test_runner.gd").new()
	add_child(runner)
	var bad := 0
	for lvl in range(int(OS.get_environment("L0")), int(OS.get_environment("L1"))):
		for k in [1, 2]:
			var data := LevelGen.make(lvl)
			var st := {}
			for i in data["problems"].size():
				var ns: int = Defs.PROBLEMS[data["problems"][i]]["stages"].size()
				st[str(i)] = mini(k, ns - 1) if i % 2 == 0 else -1
			var f := FileAccess.open("user://checkpoint.json", FileAccess.WRITE)
			f.store_string(JSON.stringify({"level": lvl, "stages": st, "earned": 0, "mistakes": 0, "max_pain": 0.0}))
			f = null
			GameData.current_level = lvl
			var g = load("res://scenes/game.tscn").instantiate()
			add_child(g)
			while not g.input_ok:
				await get_tree().create_timer(0.2).timeout
			var t0 := Time.get_ticks_msec()
			for p in g.problems:
				var tries := 0
				while not p.done and tries < 8:
					tries += 1
					g._focus_on(p)
					await get_tree().create_timer(0.2).timeout
					g._select_tool(p.tool())
					await runner.solve(g, p)
				if not p.done:
					print("PRESO fase ", lvl, " k=", k, " ", p.id, " etapa ", p.stage, " ", p.tool())
					bad += 1
			await get_tree().create_timer(3.0).timeout
			print("fase ", lvl, " k=", k, " terminou=", g.finished)
			g.queue_free()
			await get_tree().process_frame
	print("RESULTADO presos=", bad)
	get_tree().quit()
