extends Node3D
## Tela de tratamento: paciente 3D, câmera aproximada, ferramentas e HUD.

const EXCLAIMS := ["ECA!", "QUE NOJO!", "SPLASH!", "ARGH!", "SPLOFT!", "NOJENTO!", "BLERGH!"]
const PRAISE := ["PERFEITO!", "LIMPINHO!", "ÓTIMO!", "BRILHANDO!", "ALÍVIO!", "LINDO!"]
const BG_COLORS := [Color("8fe0d8"), Color("c7b8ff"), Color("ffc9a8"), Color("a8e0ff"), Color("ffd1e8")]

var data: Dictionary
var level := 1
var patient: Patient
var problems: Array[Problem] = []
var cam: Camera3D
var tool_model: ToolModel
var cam_pos := Vector3(0, 0, 5)
var cam_look := Vector3.ZERO
var cam_tween: Tween
var selected := ""
var active: Problem = null
var focus: Problem = null
var pressing := false
var last_pos := Vector2.ZERO
var wide := true
var input_ok := false
var finished := false
var mistakes := 0
var last_mistake := -10.0
var last_slow := -10.0
var combo := 0
var last_stage_t := -10.0
var earned := 0
var hint_until := 0.0
var frame_pull := 0.0
var fx_t := 0.0
var rub_t := 0.0
var shake := 0.0
var total_stages := 0
var done_stages := 0
var now := 0.0
var before_img: Image

var hud: CanvasLayer
var hud_root: Control
var tool_bar: HBoxContainer
var tool_buttons := {}
var progress_bar: ProgressBar
var lbl_problem: Label
var lbl_hint: Label
var modal_open := false

# =================================================================== setup

func _ready() -> void:
	level = GameData.current_level
	data = LevelGen.make(level)
	_env()
	patient = Patient.new()
	add_child(patient)
	patient.build(data["part"], data["look"])

	var rng := RandomNumberGenerator.new()
	rng.seed = data["seed"]
	var sizes := []
	for id in data["problems"]:
		sizes.append(Defs.PROBLEMS[id]["size"] * patient.prob_scale)
	var spots := patient.sample_spots(sizes, rng)
	for i in data["problems"].size():
		var id: String = data["problems"][i]
		var p := Problem.new()
		patient.add_child(p)
		p.position = spots[i][0] - spots[i][1] * 0.006
		p.basis = LP.basis_from_normal(spots[i][1])
		p.scale = Vector3.ONE * patient.prob_scale
		p.setup(id, rng, data["look"]["skin"], patient.curvature() / patient.prob_scale)
		p.stage_done.connect(_on_stage_done)
		p.popped.connect(_on_popped)
		problems.append(p)
		total_stages += Defs.stage_count(id)

	cam = Camera3D.new()
	cam.fov = 42.0
	add_child(cam)
	cam.current = true
	cam_look = patient.cam_center
	cam_pos = cam_look + Vector3(0, 0, patient.wide_dist)
	_apply_cam()

	tool_model = ToolModel.new()
	add_child(tool_model)
	tool_model.hide()

	_build_hud()
	hud.visible = false
	before_img = await _capture()
	hud.visible = true
	_check_tools()

func _env() -> void:
	var bg: Color = BG_COLORS[level % BG_COLORS.size()]
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = bg
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("fff0f5")
	env.ambient_light_energy = 0.55
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 25, 0)
	sun.light_energy = 1.05
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, -50, 0)
	fill.light_color = Color("ffc2e0")
	fill.light_energy = 0.35
	add_child(fill)
	# azulejos de clínica ao fundo
	var wall := Node3D.new()
	add_child(wall)
	for x in range(-4, 5):
		for y in range(-3, 4):
			var c := bg.lightened(0.12) if (x + y) % 2 == 0 else bg.darkened(0.03)
			LP.box(wall, Vector3(1.9, 1.9, 0.1), c, Vector3(x * 2.0, y * 2.0, -7.0))

func _capture() -> Image:
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		return null
	await RenderingServer.frame_post_draw
	var tex := get_viewport().get_texture()
	if tex == null:
		return null
	var img := tex.get_image()
	if img and img.get_width() > 960:
		img.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_BILINEAR)
	return img

func _check_tools() -> void:
	var missing := []
	for t in LevelGen.needed_tools(data):
		if not GameData.has_tool(t):
			missing.append(t)
	if missing.is_empty():
		_begin()
		return
	modal_open = true
	var m := UIKit.modal(hud_root)
	var dim: Control = m[0]
	var vb: VBoxContainer = m[1]
	vb.add_child(UIKit.label("NOVA FERRAMENTA!", 46, UIKit.PINK))
	vb.add_child(UIKit.label("Este paciente precisa de:", 26, UIKit.DARK, 0))
	var row := UIKit.hbox(24)
	vb.add_child(row)
	var refresh := func():
		for t in missing:
			if not GameData.has_tool(t):
				return
		dim.queue_free()
		modal_open = false
		_rebuild_tools()
		_begin()
	for t in missing:
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", 8)
		row.add_child(col)
		var ic := ToolIcon.new()
		ic.tool_id = t
		ic.custom_minimum_size = Vector2(110, 110)
		var cc := CenterContainer.new()
		cc.add_child(ic)
		col.add_child(cc)
		col.add_child(UIKit.label(Defs.TOOLS[t]["name"], 26, UIKit.DARK, 0))
		var price: int = Defs.TOOLS[t]["price"]
		var buy := UIKit.btn("Comprar %d" % price, UIKit.BLUE, 22, Vector2(200, 62))
		buy.disabled = GameData.coins < price
		var ad := UIKit.btn("Grátis (AD)", UIKit.GREEN, 22, Vector2(200, 62))
		buy.pressed.connect(func():
			if GameData.spend(price):
				GameData.unlock_tool(t)
				Sfx.play("success")
				buy.disabled = true
				ad.disabled = true
				refresh.call())
		ad.pressed.connect(func(): Ads.show_rewarded(func():
			GameData.unlock_tool(t)
			Sfx.play("success")
			buy.disabled = true
			ad.disabled = true
			refresh.call()))
		col.add_child(buy)
		col.add_child(ad)
	var back := UIKit.btn("Voltar ao menu", UIKit.PURPLE, 24, Vector2(260, 64))
	back.pressed.connect(_to_menu)
	var bc := CenterContainer.new()
	bc.add_child(back)
	vb.add_child(bc)

func _begin() -> void:
	var title := "Fase %d  -  %s" % [level, data["look"]["name"]]
	_toast(title, Color.WHITE, 46, 1.6)
	if data["extreme"]:
		await get_tree().create_timer(0.9).timeout
		_toast("CASO EXTREMO!", UIKit.RED, 64, 1.4)
		Sfx.play("wrong", 0.0, -6)
	await get_tree().create_timer(1.0).timeout
	var first: Problem = problems[0]
	var bd := INF
	for p in problems:
		var d := p.global_position.distance_to(patient.cam_center + Vector3(0, 0, 2))
		if d < bd:
			bd = d
			first = p
	_focus_on(first)
	input_ok = true
	if level == 1:
		_toast("Escolha a ferramenta e toque no problema!", UIKit.YELLOW, 32, 3.0)
	_update_labels()

# =================================================================== câmera

func _apply_cam() -> void:
	var off := Vector3.ZERO
	if shake > 0.0:
		off = Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake
	cam.global_position = cam_pos + off
	cam.look_at(cam_look, Vector3.UP)
	cam.v_offset = -0.08 * cam_pos.distance_to(cam_look)

func _move_cam(pos: Vector3, look: Vector3, dur := 0.7) -> void:
	if cam_tween:
		cam_tween.kill()
	cam_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	cam_tween.tween_property(self, "cam_pos", pos, dur)
	cam_tween.tween_property(self, "cam_look", look, dur)

func _focus_on(p: Problem) -> void:
	if p == null:
		return
	focus = p
	wide = false
	var target := p.global_position
	var n := p.global_basis.y
	var dir := (n * 0.6 + Vector3(0, 0, 1) * 0.4).normalized()
	var dist := patient.focus_dist * (0.75 + p.size * 1.6) * p.scale.x
	_move_cam(target + dir * dist, target)
	_update_labels()

func _go_wide() -> void:
	wide = true
	_move_cam(patient.cam_center + Vector3(0, 0, patient.wide_dist), patient.cam_center)
	_update_labels()

func _nearest(from: Vector3) -> Problem:
	var best: Problem = null
	var bd := INF
	for p in problems:
		if not p.done:
			var d := p.global_position.distance_to(from)
			if d < bd:
				bd = d
				best = p
	return best

# =================================================================== loop

func _process(delta: float) -> void:
	now += delta
	shake = maxf(0.0, shake - delta * 0.25)
	_apply_cam()
	if not input_ok:
		return
	if pressing and active and (active.done or active.tool() != selected):
		active = null
	var a := active
	if pressing and a:
		a.speed = GameData.speed_mult(selected)
		match a.mech():
			Defs.Mech.HOLD:
				if _within(a, last_pos, 1.9):
					fx_t -= delta
					if fx_t <= 0.0:
						fx_t = 0.1
						var c := a.hold_color()
						var up := a.global_basis.y
						if c.a > 0.0:
							LP.burst(patient, a.global_position + up * 0.05, c, 5, 0.9, 0.013, up, 35.0)
						Sfx.play_throttled("freeze" if selected == "spray" else "squish", 0.28, 0.2, -6)
					a.add_progress(delta)
			Defs.Mech.PULL:
				var cap := 520.0 * delta
				var amt := minf(frame_pull, cap)
				if frame_pull > cap * 2.4 and now - last_slow > 1.2:
					last_slow = now
					_toast("Devagar!", UIKit.YELLOW, 40, 0.7)
				if amt > 0.0:
					Sfx.play_throttled("pull", 0.3, 0.3, -10)
					a.add_progress(amt)
	frame_pull = 0.0
	_update_tool_model()
	_update_hint_glow()

func _update_tool_model() -> void:
	if not pressing or selected == "":
		tool_model.visible = false
		tool_model.set_active(false)
		return
	tool_model.visible = true
	var o := cam.project_ray_origin(last_pos)
	var d := cam.project_ray_normal(last_pos)
	var hit := patient.ray_hit(o, d)
	var pos: Vector3
	if hit.is_empty():
		pos = o + d * cam_pos.distance_to(cam_look)
	else:
		pos = hit[0] + hit[1] * 0.01
	var dist := cam.global_position.distance_to(pos)
	tool_model.global_position = pos
	var cb := cam.global_basis
	var y := (cb.y * 0.6 + cb.z * 0.6 + cb.x * 0.25).normalized()
	var x := cb.x - y * cb.x.dot(y)
	x = x.normalized()
	var z := x.cross(y)
	tool_model.global_basis = Basis(x, y, z).scaled(Vector3.ONE * clampf(dist / 1.5, 0.6, 3.0))
	tool_model.set_active(active != null, active.mech() if active else -1)

# =================================================================== entrada

func _unhandled_input(e: InputEvent) -> void:
	if not input_ok or modal_open:
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_press(e.position)
		else:
			_release()
	elif e is InputEventMouseMotion and pressing:
		_drag(e.position)

func _screen_radius(p: Problem) -> float:
	var c := cam.unproject_position(p.global_position)
	var e := cam.unproject_position(p.global_position + cam.global_basis.x * p.size * p.scale.x)
	return maxf(c.distance_to(e), 26.0)

func _within(p: Problem, pos: Vector2, mult := 1.0) -> bool:
	if cam.is_position_behind(p.global_position):
		return false
	return cam.unproject_position(p.global_position).distance_to(pos) < _screen_radius(p) * mult + 22.0

## Problema sob o dedo. Se houver vários, prefere o que aceita a ferramenta escolhida.
func _pick_problem(pos: Vector2, mult := 1.25) -> Problem:
	var best: Problem = null
	var bd := INF
	var match_best: Problem = null
	var md := INF
	for p in problems:
		if p.done or cam.is_position_behind(p.global_position):
			continue
		var d := cam.unproject_position(p.global_position).distance_to(pos)
		if d < _screen_radius(p) * mult + 22.0:
			if d < bd:
				bd = d
				best = p
			if p.tool() == selected and d < md:
				md = d
				match_best = p
	return match_best if match_best else best

func _press(pos: Vector2) -> void:
	pressing = true
	last_pos = pos
	frame_pull = 0.0
	var p := _pick_problem(pos)
	if wide:
		if p == null:
			p = _pick_problem(pos, 2.5)
		if p:
			_focus_on(p)
		pressing = false
		return
	if p == null:
		return
	if selected == "":
		_toast("Escolha uma ferramenta!", UIKit.YELLOW, 38, 1.0)
		_bounce(tool_bar.get_parent())
		return
	if p.tool() != selected:
		_wrong(p)
		return
	_start_on(p, pos)

func _start_on(p: Problem, pos: Vector2) -> void:
	active = p
	if focus == null or focus.done:
		focus = p
	p.speed = GameData.speed_mult(selected)
	lbl_hint.text = Defs.MECH_HINT[p.mech()]
	match p.mech():
		Defs.Mech.TAP:
			p.tap()
		Defs.Mech.PICK:
			p.pick(pos, 70.0, cam)
		Defs.Mech.SWEEP:
			p.sweep(pos, _sweep_r(), cam)

func _drag(pos: Vector2) -> void:
	var rel := pos.distance_to(last_pos)
	last_pos = pos
	if active == null and selected != "" and not wide:
		# arrastar de fora para dentro do problema também vale
		var p := _pick_problem(pos)
		if p and p.tool() == selected and p.mech() in [Defs.Mech.RUB, Defs.Mech.CUT, Defs.Mech.SWEEP]:
			_start_on(p, pos)
	var a := active
	if a == null:
		return
	match a.mech():
		Defs.Mech.RUB, Defs.Mech.CUT:
			if _within(a, pos, 1.8):
				_rub_fx(a)
				a.add_progress(rel)
		Defs.Mech.PULL:
			frame_pull += rel
		Defs.Mech.SWEEP:
			if a.sweep(pos, _sweep_r(), cam) == 0:
				_rub_fx(a)
		Defs.Mech.PICK:
			pass

func _release() -> void:
	pressing = false
	active = null
	_update_labels()

func _sweep_r() -> float:
	match selected:
		"lamina": return 60.0
		"pente": return 55.0
	return 48.0

func _rub_fx(p: Problem) -> void:
	if now - rub_t < 0.07:
		return
	rub_t = now
	var pos := tool_model.global_position
	var up := p.global_basis.y
	match selected:
		"escova":
			LP.burst(patient, pos, Color(1, 1, 1, 0.9), 4, 0.6, 0.018, up, 70.0, -0.5, 0.6)
			LP.burst(patient, pos, p.fx_color(), 2, 0.7, 0.01, up, 70.0)
			Sfx.play_throttled("scrub", 0.12)
		"algodao":
			LP.burst(patient, pos, Color(1, 1, 1), 2, 0.4, 0.012, up, 80.0, -1.0, 0.5)
			Sfx.play_throttled("scrub", 0.16, 0.2, -10)
		"espatula":
			LP.burst(patient, pos, p.fx_color(), 3, 0.8, 0.012, up, 60.0)
			Sfx.play_throttled("scrub", 0.14, 0.3, -6)
		"bisturi":
			LP.burst(patient, pos, Problem.BLOOD, 2, 0.4, 0.008, up, 50.0)
			Sfx.play_throttled("cut", 0.15)
		_:
			Sfx.play_throttled("scrub", 0.15, 0.2, -8)

func _wrong(p: Problem) -> void:
	if now - last_mistake < 0.8:
		return
	last_mistake = now
	mistakes += 1
	Sfx.play("wrong", 0.05, -4)
	GameData.vibrate(70)
	patient.flinch()
	_float_text("AI!", cam.unproject_position(p.global_position) + Vector2(0, -50), UIKit.RED, 44)
	_toast("Ferramenta errada!", UIKit.RED, 40, 1.0)
	if level <= 3:
		hint_until = maxf(hint_until, now + 4.0)
	_update_labels()

# =================================================================== eventos

func _on_stage_done(p: Problem, fin: bool) -> void:
	if p == active:
		active = null
	done_stages += 1
	combo = combo + 1 if now - last_stage_t < 3.5 else 1
	last_stage_t = now
	var c := 5 + (combo - 1) * 3
	earned += c
	var sp := cam.unproject_position(p.global_position)
	_float_text("+%d" % c, sp + Vector2(0, -40), UIKit.YELLOW, 40)
	if combo >= 2:
		_toast("COMBO x%d!" % combo, UIKit.PINK, 48, 0.9)
	Sfx.play("coin", 0.05, -8)
	GameData.vibrate(25)
	patient.set_mood(float(done_stages) / total_stages)
	progress_bar.value = 100.0 * done_stages / total_stages
	_update_labels()
	if fin:
		_float_text(PRAISE.pick_random(), sp + Vector2(0, -100), UIKit.GREEN, 46)
		var all_done := true
		for q in problems:
			if not q.done:
				all_done = false
		if all_done:
			_finish()
			return
		if p == focus:
			await get_tree().create_timer(0.5).timeout
			if not finished and not pressing:
				_focus_on(_nearest(p.global_position))
			elif not finished:
				focus = _nearest(p.global_position)

func _on_popped(p: Problem, _c: Color) -> void:
	shake = 0.04
	GameData.vibrate(40)
	if randf() < 0.7:
		var sp := cam.unproject_position(p.global_position)
		_float_text(EXCLAIMS.pick_random(), sp + Vector2(randf_range(-60, 60), -80), Color("b6ff6b"), 42)

# =================================================================== fim

func _finish() -> void:
	finished = true
	input_ok = false
	pressing = false
	active = null
	tool_model.hide()
	Sfx.play("success")
	_toast("PACIENTE CURADO!", UIKit.GREEN, 60, 1.4)
	await get_tree().create_timer(1.0).timeout
	_go_wide()
	patient.set_mood(1.0)
	await get_tree().create_timer(1.1).timeout
	hud.visible = false
	var after := await _capture()
	hud.visible = true
	var stars := 3
	if mistakes > 2:
		stars = 1
	elif mistakes > 0:
		stars = 2
	var base := 40 + 8 * level
	var reward := int(base * [0.6, 0.8, 1.0][stars - 1]) + earned
	if data["extreme"]:
		reward *= 2
	GameData.complete_level(level, stars, reward)
	_show_result(after, stars, reward)

func _show_result(after: Image, stars: int, reward: int) -> void:
	modal_open = true
	for c in hud_root.get_children():
		c.visible = false
	var m := UIKit.modal(hud_root)
	var vb: VBoxContainer = m[1]
	vb.add_child(UIKit.label("ANTES  E  DEPOIS", 44, UIKit.PINK))
	var row := UIKit.hbox(24)
	vb.add_child(row)
	for pair in [[before_img, "ANTES", UIKit.RED], [after, "DEPOIS", UIKit.GREEN]]:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		row.add_child(col)
		var frame := PanelContainer.new()
		frame.add_theme_stylebox_override("panel", UIKit.style(pair[2], 18, 0))
		col.add_child(frame)
		var tr := TextureRect.new()
		tr.custom_minimum_size = Vector2(400, 225)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		if pair[0] != null:
			tr.texture = ImageTexture.create_from_image(pair[0])
		frame.add_child(tr)
		col.add_child(UIKit.label(pair[1], 28, pair[2]))
	var st := UIKit.StarRow.new()
	st.custom_minimum_size = Vector2(260, 70)
	var sc := CenterContainer.new()
	sc.add_child(st)
	vb.add_child(sc)
	var quote := UIKit.label("\"%s\" - %s" % [Defs.THANKS.pick_random(), data["look"]["name"]], 24, UIKit.DARK, 0)
	vb.add_child(quote)
	var coins_row := UIKit.hbox(8)
	var ic := UIKit.CoinIcon.new()
	ic.custom_minimum_size = Vector2(46, 46)
	coins_row.add_child(ic)
	var coin_lbl := UIKit.label("+%d" % reward, 44, Color("ffc43d"))
	coins_row.add_child(coin_lbl)
	if mistakes > 0:
		coins_row.add_child(UIKit.label("  (erros: %d)" % mistakes, 22, UIKit.RED, 0))
	vb.add_child(coins_row)
	var btns := UIKit.hbox(16)
	vb.add_child(btns)
	var dbl := UIKit.btn("x2 Moedas (AD)", UIKit.YELLOW, 26, Vector2(250, 76))
	dbl.pressed.connect(func(): Ads.show_rewarded(func():
		GameData.add_coins(reward)
		coin_lbl.text = "+%d" % (reward * 2)
		dbl.disabled = true
		Sfx.play("coin")))
	btns.add_child(dbl)
	var menu := UIKit.btn("Menu", UIKit.PURPLE, 26, Vector2(160, 76))
	menu.pressed.connect(_to_menu)
	btns.add_child(menu)
	var nxt := UIKit.btn("Próximo paciente", UIKit.GREEN, 28, Vector2(300, 76))
	nxt.pressed.connect(_next)
	btns.add_child(nxt)
	for i in stars:
		await get_tree().create_timer(0.35).timeout
		st.filled = i + 1
		Sfx.play("star", 0.0)

func _next() -> void:
	GameData.current_level = level + 1
	if GameData.levels_since_ad >= 3:
		GameData.levels_since_ad = 0
		GameData.save_game()
		Ads.show_interstitial(func(): get_tree().reload_current_scene())
	else:
		get_tree().reload_current_scene()

func _to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

# =================================================================== HUD

func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	hud_root = Control.new()
	hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(hud_root)

	var pause := UIKit.btn("II", UIKit.PURPLE, 30, Vector2(76, 70))
	pause.position = Vector2(16, 14)
	pause.pressed.connect(_pause)
	hud_root.add_child(pause)

	var coins := UIKit.coin_box()
	hud_root.add_child(coins)
	coins.anchor_left = 1.0
	coins.anchor_right = 1.0
	coins.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	coins.offset_left = -220
	coins.offset_right = -16
	coins.offset_top = 16

	var top := VBoxContainer.new()
	top.anchor_left = 0.5
	top.anchor_right = 0.5
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.offset_left = -300
	top.offset_right = 300
	top.offset_top = 10
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 4)
	hud_root.add_child(top)
	var head := "Fase %d  -  %s  (%s)" % [level, data["look"]["name"], Defs.PART_NAMES[data["part"]]]
	if data["extreme"]:
		head = "EXTREMO! " + head
	top.add_child(UIKit.label(head, 26, UIKit.RED.lightened(0.5) if data["extreme"] else Color.WHITE, 7))
	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size = Vector2(520, 26)
	progress_bar.show_percentage = false
	progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_bar.add_theme_stylebox_override("background", UIKit.style(Color(0.15, 0.1, 0.25, 0.6), 13))
	progress_bar.add_theme_stylebox_override("fill", UIKit.style(UIKit.GREEN, 13))
	top.add_child(progress_bar)
	lbl_problem = UIKit.label("", 28, Color("fff3b0"), 7)
	top.add_child(lbl_problem)
	lbl_hint = UIKit.label("", 24, Color.WHITE, 6)
	top.add_child(lbl_hint)

	# botões laterais
	var side := VBoxContainer.new()
	side.anchor_left = 1.0
	side.anchor_right = 1.0
	side.anchor_top = 0.5
	side.anchor_bottom = 0.5
	side.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	side.grow_vertical = Control.GROW_DIRECTION_BOTH
	side.offset_left = -170
	side.offset_right = -14
	side.offset_top = -110
	side.offset_bottom = 40
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_theme_constant_override("separation", 12)
	hud_root.add_child(side)
	var hint := UIKit.btn("Dica (AD)", UIKit.YELLOW, 24, Vector2(150, 68))
	hint.pressed.connect(func(): Ads.show_rewarded(func():
		hint_until = now + 30.0
		_toast("Dicas ligadas por 30s!", UIKit.YELLOW, 36, 1.2)
		_update_labels()))
	side.add_child(hint)
	var zoom := UIKit.btn("Zoom", UIKit.BLUE, 24, Vector2(150, 68))
	zoom.pressed.connect(func():
		if not input_ok:
			return
		if wide:
			_focus_on(focus if focus and not focus.done else _nearest(patient.cam_center + Vector3(0, 0, 2)))
		else:
			_go_wide())
	side.add_child(zoom)

	# barra de ferramentas
	var bar_panel := PanelContainer.new()
	var sb := UIKit.style(Color(1, 1, 1, 0.85), 26, 4, Color("d9cff0"))
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	bar_panel.add_theme_stylebox_override("panel", sb)
	bar_panel.anchor_left = 0.5
	bar_panel.anchor_right = 0.5
	bar_panel.anchor_top = 1.0
	bar_panel.anchor_bottom = 1.0
	bar_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar_panel.offset_bottom = -10
	bar_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	hud_root.add_child(bar_panel)
	tool_bar = UIKit.hbox(10)
	bar_panel.add_child(tool_bar)
	_rebuild_tools()

func _rebuild_tools() -> void:
	for c in tool_bar.get_children():
		c.queue_free()
	tool_buttons.clear()
	for id in Defs.TOOL_ORDER:
		if not GameData.has_tool(id):
			continue
		var b := Button.new()
		b.custom_minimum_size = Vector2(98, 112)
		b.focus_mode = Control.FOCUS_NONE
		_style_tool(b, false)
		var ic := ToolIcon.new()
		ic.tool_id = id
		ic.set_anchors_preset(Control.PRESET_FULL_RECT)
		ic.offset_left = 13
		ic.offset_right = -13
		ic.offset_top = 6
		ic.offset_bottom = -34
		b.add_child(ic)
		var l := UIKit.label(Defs.TOOLS[id]["name"], 16, UIKit.DARK, 0)
		l.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		l.offset_top = -30
		l.offset_bottom = -6
		b.add_child(l)
		b.pressed.connect(func(): _select_tool(id))
		tool_bar.add_child(b)
		tool_buttons[id] = b
	if selected != "" and tool_buttons.has(selected):
		_style_tool(tool_buttons[selected], true)

func _style_tool(b: Button, sel: bool) -> void:
	var n := UIKit.style(Color("fff6d6") if sel else Color.WHITE, 20, 5 if sel else 3, UIKit.YELLOW if sel else Color("d9cff0"))
	for k in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(k, n)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

func _select_tool(id: String) -> void:
	if selected != "" and tool_buttons.has(selected):
		_style_tool(tool_buttons[selected], false)
	selected = id
	_style_tool(tool_buttons[id], true)
	tool_model.set_tool(id)
	Sfx.play("tap")
	_bounce(tool_buttons[id])
	_update_labels()

func _hints_on() -> bool:
	return level <= 2 or now < hint_until

func _target() -> Problem:
	if active and not active.done:
		return active
	if focus and not focus.done:
		return focus
	return null

func _update_labels() -> void:
	if lbl_problem == null:
		return
	var p := _target()
	if wide:
		lbl_problem.text = "Toque num problema para aproximar"
		lbl_hint.text = ""
		return
	if p == null:
		lbl_problem.text = ""
		lbl_hint.text = ""
		return
	var n := Defs.stage_count(p.id)
	lbl_problem.text = p.pname() + ("   (etapa %d/%d)" % [p.stage + 1, n] if n > 1 else "")
	if _hints_on():
		lbl_hint.text = "Use: %s  -  %s" % [Defs.TOOLS[p.tool()]["name"], Defs.MECH_HINT[p.mech()]]
	elif selected == "":
		lbl_hint.text = "Escolha uma ferramenta"
	else:
		lbl_hint.text = "Qual ferramenta resolve isso?"

func _update_hint_glow() -> void:
	var p := _target()
	var want := p.tool() if (p and _hints_on() and not wide) else ""
	for id in tool_buttons:
		var b: Button = tool_buttons[id]
		if id == want and id != selected:
			var k := 0.5 + 0.5 * sin(now * 8.0)
			b.modulate = Color(1, 1, 1).lerp(Color(1.4, 1.3, 0.6), k)
		else:
			b.modulate = Color.WHITE

func _toast(text: String, color := Color.WHITE, size := 40, dur := 1.0) -> void:
	var l := UIKit.label(text, size, color, 10)
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.grow_vertical = Control.GROW_DIRECTION_BOTH
	l.offset_top = 120
	l.offset_bottom = 190
	hud_root.add_child(l)
	await get_tree().process_frame
	if not is_instance_valid(l):
		return
	l.pivot_offset = l.size * 0.5
	l.scale = Vector2(0.3, 0.3)
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(dur)
	tw.tween_property(l, "modulate:a", 0.0, 0.3)
	tw.tween_callback(l.queue_free)

func _float_text(text: String, pos: Vector2, color: Color, size := 36) -> void:
	var l := UIKit.label(text, size, color, 9)
	hud_root.add_child(l)
	l.position = pos - Vector2(100, 30)
	l.size = Vector2(200, 60)
	l.pivot_offset = Vector2(100, 30)
	l.rotation = randf_range(-0.2, 0.2)
	var tw := l.create_tween().set_parallel()
	tw.tween_property(l, "position:y", l.position.y - 70, 0.9).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.4).set_delay(0.5)
	tw.chain().tween_callback(l.queue_free)

func _bounce(c: Control) -> void:
	c.pivot_offset = c.size * 0.5
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2(1.12, 1.12), 0.07)
	tw.tween_property(c, "scale", Vector2.ONE, 0.12)

func _pause() -> void:
	if modal_open or finished:
		return
	modal_open = true
	pressing = false
	active = null
	var m := UIKit.modal(hud_root)
	var dim: Control = m[0]
	var vb: VBoxContainer = m[1]
	vb.add_child(UIKit.label("PAUSADO", 48, UIKit.PURPLE))
	var cont := UIKit.btn("Continuar", UIKit.GREEN, 30, Vector2(300, 78))
	cont.pressed.connect(func():
		dim.queue_free()
		modal_open = false)
	vb.add_child(cont)
	var rst := UIKit.btn("Reiniciar", UIKit.BLUE, 30, Vector2(300, 78))
	rst.pressed.connect(func(): get_tree().reload_current_scene())
	vb.add_child(rst)
	var menu := UIKit.btn("Menu", UIKit.PURPLE, 30, Vector2(300, 78))
	menu.pressed.connect(_to_menu)
	vb.add_child(menu)
