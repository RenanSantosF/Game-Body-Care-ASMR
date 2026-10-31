extends Node
# (dev) fotos das mecânicas: corte de unha, pano moldado, fio de pus, antes/depois
var out := OS.get_environment("OUT")

func _ready() -> void:
	for tl in Defs.TOOL_ORDER:
		GameData.owned[tl] = 1
	GameData.sound_on = false
	GameData.set_meta("lab_problems", ["unha_suja", "espinha", "sujeira"])
	GameData.set_meta("lab_part", "pe")
	GameData.current_level = 12
	var runner = load("res://tests/test_runner.gd").new()
	add_child(runner)
	var game = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	await _w(3.5)
	var nail_p: Problem = null
	var pim: Problem = null
	var dirt: Problem = null
	for p in game.problems:
		match p.id:
			"unha_suja": nail_p = p
			"espinha": pim = p
			"sujeira": dirt = p
	# --- corte da unha até 60%
	game._focus_on(nail_p)
	await _w(1.0)
	game._select_tool("alicate")
	var path: PackedVector3Array = nail_p.cut_path
	game._press(game.cam.unproject_position(path[0]))
	game._trigger(true)
	for i in int(path.size() * 0.6):
		game._drag(game.cam.unproject_position(path[i]))
		await get_tree().process_frame
	await _shot("1_unha_corte_60")
	for i in range(int(path.size() * 0.6), path.size()):
		game._drag(game.cam.unproject_position(path[i]))
		await get_tree().process_frame
	await _w(0.15)
	await _shot("2_unha_lasca_voando")
	game._trigger(false)
	game._release()
	await _w(0.6)
	await _shot("3_unha_cortada")
	# --- espinha: agulha e espremer pela metade (fio de pus)
	game._focus_on(pim)
	await _w(1.0)
	game._select_tool(pim.tool())
	await runner.solve(game, pim)
	game._select_tool(pim.tool())
	var c: Vector2 = game.cam.unproject_position(pim.center())
	game._press(c)
	game._trigger(true)
	var g := 0
	while pim.progress < 0.7 and g < 400:
		g += 1
		await get_tree().process_frame
	await _shot("4_fio_pus")
	game._trigger(false)
	game._release()
	await _w(0.8)
	await _shot("5_fio_pus_solto")
	# --- pano sobre a sujeira
	game._focus_on(dirt)
	await _w(1.0)
	game._select_tool("pano")
	var dc: Vector2 = game.cam.unproject_position(dirt.center())
	game._press(dc)
	game._trigger(true)
	for f in 20:
		game._drag(dc + Vector2(sin(f * 0.5) * 60.0, cos(f * 0.4) * 40.0))
		await get_tree().process_frame
	await _shot("6_pano")
	game._trigger(false)
	game._release()
	# pula direto para o resultado (no xvfb resolver tudo é lento demais)
	game._finish()
	await _w(6.0)
	await _shot("7_resultado")
	await game._share(game.before_img, 3)
	await _w(1.0)
	await _shot("8_compartilhar")
	print("arquivos: ", DirAccess.get_files_at(OS.get_system_dir(OS.SYSTEM_DIR_PICTURES) + "/GrossToGlow"))
	get_tree().quit()

func _w(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _shot(n: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("foto ", n)
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/" + n + ".png")
