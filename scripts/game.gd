extends Node3D
## Tela de tratamento: mão/pé no travesseiro, câmera de cima, ferramentas, dor do paciente.

const EXCLAIMS := ["ECA!", "QUE NOJO!", "SPLASH!", "ARGH!", "SPLOFT!", "NOJENTO!", "BLERGH!"]
const PRAISE := ["PERFEITO!", "LIMPINHO!", "ÓTIMO!", "BRILHANDO!", "ALÍVIO!", "LINDO!"]
const BRUSH := {"pano": 0.05, "algodao": 0.04, "raspador": 0.035, "lixa": 0.03, "pomada": 0.045}
const MAX_WOUNDS := 4

var data: Dictionary
var level := 1
var body: Body
var problems: Array[Problem] = []
var cam: Camera3D
var tool_model: ToolModel
var cam_pos := Vector3(0, 5, 2)
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
var last_dirty := -10.0
var last_skin_hurt := -10.0
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
var pain := 0.0
var max_pain := 0.0
var wounds := 0
var cut_idx := 0
var cut_rev := false
var off_path_t := 0.0
var rng := RandomNumberGenerator.new()

var hud: CanvasLayer
var hud_root: Control
var tool_bar: HBoxContainer
var tool_buttons := {}
var progress_bar: ProgressBar
var pain_bar: ProgressBar
var face: PatientFace
var bubble: Label
var lbl_problem: Label
var lbl_hint: Label
var modal_open := false

# =================================================================== setup

func _ready() -> void:
	level = GameData.current_level
	data = LevelGen.make(level)
	rng.seed = data["seed"] + 99
	Stage.setup_env(self, data["look"]["pillow"])
	body = Body.new()
	add_child(body)
	body.build(data["part"], data["look"]["skin"])

	var prng := RandomNumberGenerator.new()
	prng.seed = data["seed"]
	var spots := LevelGen.place(body, data["problems"], prng)
	for i in data["problems"].size():
		var sp: Dictionary = spots[i]
		if sp.is_empty():
			continue
		_spawn(data["problems"][i], sp, prng)

	cam = Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.current = true
	cam_pos = _wide_pos()
	cam_look = body.cam_center
	_apply_cam()

	tool_model = ToolModel.new()
	add_child(tool_model)
	tool_model.hide()

	_build_hud()
	hud.visible = false
	before_img = await _capture()
	hud.visible = true
	_check_tools()

func _spawn(id: String, sp: Dictionary, prng: RandomNumberGenerator) -> Problem:
	var p := Problem.new()
	body.add_child(p)
	p.global_position = sp["pos"]
	p.global_basis = MeshGen.basis_from_normal(sp["normal"], sp.get("fwd", Vector3(1, 0, 0)))
	var extra := {}
	if sp.has("nail") and sp["nail"] != null:
		extra["nail"] = sp["nail"]
	p.setup(id, body, prng, extra)
	p.stage_done.connect(_on_stage_done)
	p.popped.connect(_on_popped)
	problems.append(p)
	total_stages += Defs.stage_count(id)
	return p

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
	for tl in LevelGen.needed_tools(data):
		if not GameData.has_tool(tl):
			missing.append(tl)
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
		for tl in missing:
			if not GameData.has_tool(tl):
				return
		dim.queue_free()
		modal_open = false
		_rebuild_tools()
		_begin()
	for tl in missing:
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", 8)
		row.add_child(col)
		var ic := ToolIcon.new()
		ic.tool_id = tl
		ic.custom_minimum_size = Vector2(100, 100)
		var cc := CenterContainer.new()
		cc.add_child(ic)
		col.add_child(cc)
		col.add_child(UIKit.label(Defs.TOOLS[tl]["name"], 26, UIKit.DARK, 0))
		var desc := UIKit.label(Defs.TOOLS[tl]["desc"], 17, Color("6d6680"), 0)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(200, 40)
		col.add_child(desc)
		var price: int = Defs.TOOLS[tl]["price"]
		var buy := UIKit.btn("Comprar %d" % price, UIKit.BLUE, 22, Vector2(200, 60))
		buy.disabled = GameData.coins < price
		var ad := UIKit.btn("Grátis (AD)", UIKit.GREEN, 22, Vector2(200, 60))
		buy.pressed.connect(func():
			if GameData.spend(price):
				GameData.unlock_tool(tl)
				Sfx.play("success")
				buy.disabled = true
				ad.disabled = true
				refresh.call())
		ad.pressed.connect(func(): Ads.show_rewarded(func():
			GameData.unlock_tool(tl)
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
	_toast("Fase %d  -  %s" % [level, data["look"]["name"]], Color.WHITE, 46, 1.4)
	_say("Doutor, me ajuda!")
	if data["extreme"]:
		await get_tree().create_timer(0.9).timeout
		_toast("CASO EXTREMO!", UIKit.RED, 64, 1.3)
	await get_tree().create_timer(1.0).timeout
	_focus_on(_first_problem())
	input_ok = true
	if level == 1:
		_toast("Escolha a ferramenta e toque no problema!", UIKit.YELLOW, 32, 3.0)
	_update_labels()

func _first_problem() -> Problem:
	# começa pela sujeira (limpar antes facilita), depois pelo mais próximo do centro
	for p in problems:
		if not p.done and p.id == "sujeira":
			return p
	return _nearest(body.cam_center)

# =================================================================== câmera

func _wide_pos() -> Vector3:
	return body.cam_center + Vector3(0, 3.7, 1.55)

func _apply_cam() -> void:
	var off := Vector3.ZERO
	if shake > 0.0:
		off = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * shake
	cam.global_position = cam_pos + off
	cam.look_at(cam_look + off, Vector3.UP)

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
	var target := p.center()
	var d := clampf(0.7 + p.focus_radius() * 4.0, 0.95, 1.9)
	# um pouco acima do centro da tela por causa da barra de ferramentas
	var look := target + Vector3(0, 0, d * 0.08)
	_move_cam(look + Vector3(0, d, d * 0.42), look)
	_update_labels()
	for q in problems:
		q.show_guide(q == p and q.tool() == selected)

func _go_wide() -> void:
	wide = true
	_move_cam(_wide_pos(), body.cam_center)
	_update_labels()

func _nearest(from: Vector3) -> Problem:
	var best: Problem = null
	var bd := INF
	for p in problems:
		if not p.done:
			var d := p.center().distance_to(from)
			if d < bd:
				bd = d
				best = p
	return best

# =================================================================== loop

func _process(delta: float) -> void:
	now += delta
	shake = maxf(0.0, shake - delta * 0.2)
	_apply_cam()
	if not input_ok:
		return
	pain = maxf(0.0, pain - delta * 1.6)
	_update_pain()
	if pressing and active and (active.done or active.tool() != selected):
		active = null
	var a := active
	if pressing and a:
		a.speed = GameData.speed_mult(selected) * _dirt_mult(a)
		match a.mech():
			Defs.Mech.HOLD:
				if _within(a, last_pos, 1.9):
					fx_t -= delta
					if fx_t <= 0.0:
						fx_t = 0.1
						var c := a.hold_color()
						if c.a > 0.0:
							MeshGen.burst(body, a.center() + a.global_basis.y * 0.04, c, 4, 0.7, 0.009, a.global_basis.y, 35.0)
						Sfx.play_throttled("freeze" if selected == "spray" else "squish", 0.3, 0.2, -6)
					_dirty_pain(a, delta)
					a.hold(delta)
			Defs.Mech.PULL:
				var cap := 480.0 * delta
				var amt := minf(frame_pull, cap)
				if frame_pull > cap * 2.4:
					_hurt(3.0 * delta * 30.0, Defs.OUCH_FAST, 0.9)
				if amt > 0.0:
					Sfx.play_throttled("pull", 0.3, 0.3, -10)
					_dirty_pain(a, delta)
					a.pull(amt)
	frame_pull = 0.0
	_update_tool_model()
	_update_hint_glow()

func _update_pain() -> void:
	max_pain = maxf(max_pain, pain)
	if pain_bar:
		pain_bar.value = pain
		var sb := pain_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if sb:
			sb.bg_color = UIKit.GREEN.lerp(UIKit.RED, pain / 100.0)
	if face:
		face.pain = pain
	if pain >= 100.0 and not finished:
		_fail()

func _hurt(amount: float, lines: Array, min_gap := 0.0) -> void:
	pain = minf(100.0, pain + amount)
	if min_gap <= 0.0 or now - last_slow > min_gap:
		last_slow = now
		face.hurt()
		_say(lines.pick_random())
		Sfx.play("ouch", 0.15, -2)
		GameData.vibrate(60)
		body_flinch()

func body_flinch() -> void:
	shake = maxf(shake, 0.02)

func _dirt_mult(p: Problem) -> float:
	if p.id == "sujeira":
		return 1.0
	for q in problems:
		if q != p and q.dirt_left() > 0.35 and q.center().distance_to(p.center()) < q.size + p.size + 0.12:
			return 0.55
	return 1.0

func _dirty_pain(p: Problem, delta: float) -> void:
	if _dirt_mult(p) < 1.0:
		pain = minf(100.0, pain + delta * 6.0)
		if now - last_dirty > 3.0:
			last_dirty = now
			_say(Defs.OUCH_DIRTY.pick_random())
			_toast("Limpe a sujeira com o pano primeiro!", UIKit.YELLOW, 30, 1.2)

## Raio do dedo até a pele (mapa de altura)
func _ray_body(pos: Vector2) -> Array:
	var o := cam.project_ray_origin(pos)
	var d := cam.project_ray_normal(pos)
	if absf(d.y) < 0.01:
		return []
	var p := o + d * ((0.1 - o.y) / d.y)
	var s := []
	for i in 4:
		s = body.surface(p.x, p.z)
		if s.is_empty():
			return []
		var h: float = s[0].y
		p = o + d * ((h - o.y) / d.y)
	s = body.surface(p.x, p.z)
	return s

func _update_tool_model() -> void:
	if not pressing or selected == "":
		tool_model.visible = false
		tool_model.set_active(false)
		return
	tool_model.visible = true
	var hit := _ray_body(last_pos)
	var pos: Vector3
	if hit.is_empty():
		var o := cam.project_ray_origin(last_pos)
		var d := cam.project_ray_normal(last_pos)
		pos = o + d * ((0.05 - o.y) / d.y)
	else:
		pos = hit[0] + hit[1] * 0.006
	if active and active.mech() == Defs.Mech.PULL:
		pos = pos.lerp(active.grip_point(), 0.6)
	tool_model.global_position = pos
	var cb := cam.global_basis
	var y := (Vector3.UP * 0.75 + cb.z * 0.35 + cb.x * 0.35).normalized()
	var x := (cb.x - y * cb.x.dot(y)).normalized()
	var z := x.cross(y)
	var dist := cam.global_position.distance_to(pos)
	tool_model.global_basis = Basis(x, y, z).scaled(Vector3.ONE * clampf(dist / 1.3, 0.6, 2.5))
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
	var c := cam.unproject_position(p.center())
	var e := cam.unproject_position(p.center() + cam.global_basis.x * p.size)
	return maxf(c.distance_to(e), 26.0)

func _within(p: Problem, pos: Vector2, mult := 1.0) -> bool:
	return cam.unproject_position(p.center()).distance_to(pos) < _screen_radius(p) * mult + 22.0

## Problema sob o dedo. Se houver vários, prefere o que aceita a ferramenta escolhida.
func _pick_problem(pos: Vector2, mult := 1.25) -> Problem:
	var best: Problem = null
	var bd := INF
	var mb: Problem = null
	var md := INF
	for p in problems:
		if p.done:
			continue
		var d := cam.unproject_position(p.center()).distance_to(pos)
		if d < _screen_radius(p) * mult + 22.0:
			if d < bd:
				bd = d
				best = p
			if p.tool() == selected and d < md:
				md = d
				mb = p
	if mb == null and selected != "":
		# itens de grupos (cravos, larvas, pelos...) podem estar fora do raio do centro
		for p in problems:
			if p.done or p.tool() != selected:
				continue
			for it in p.items:
				if it["alive"] and cam.unproject_position(it["pos"]).distance_to(pos) < 60.0:
					return p
		# a linha de corte também conta como área do problema
		for p in problems:
			if p.done or p.tool() != selected or p.mech() != Defs.Mech.CUT:
				continue
			for q in p.cut_path:
				if cam.unproject_position(q).distance_to(pos) < 50.0:
					return p
	return mb if mb else best

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
		_skin_touch(pos)
		return
	if selected == "":
		_toast("Escolha uma ferramenta!", UIKit.YELLOW, 38, 1.0)
		_bounce(tool_bar.get_parent())
		return
	if p.tool() != selected:
		_wrong(p, pos)
		return
	_start_on(p, pos)

## Ferramenta afiada em pele saudável machuca
func _skin_touch(pos: Vector2) -> void:
	if selected == "" or not Defs.TOOLS[selected]["sharp"]:
		return
	var hit := _ray_body(pos)
	if hit.is_empty() or now - last_skin_hurt < 1.0:
		return
	last_skin_hurt = now
	mistakes += 1
	_hurt(10.0, Defs.OUCH)
	_toast("Cuidado! Você machucou a pele!", UIKit.RED, 34, 1.0)
	_make_wound(hit[0], hit[1])

func _make_wound(pos: Vector3, normal: Vector3) -> void:
	if wounds >= MAX_WOUNDS:
		return
	for q in problems:
		if not q.done and q.center().distance_to(pos) < q.size + 0.05:
			return
	wounds += 1
	var p := _spawn("machucado", {"pos": pos, "normal": normal}, rng)
	_update_labels()
	p.show_guide(false)

func _start_on(p: Problem, pos: Vector2) -> void:
	active = p
	if focus == null or focus.done:
		focus = p
	p.speed = GameData.speed_mult(selected) * _dirt_mult(p)
	lbl_hint.text = Defs.MECH_HINT[p.mech()]
	match p.mech():
		Defs.Mech.TAP:
			p.tap()
		Defs.Mech.PICK:
			p.pick(pos, 60.0, cam)
		Defs.Mech.SWEEP:
			p.sweep(pos, _sweep_r(), cam)
		Defs.Mech.CUT:
			_cut_start(p, pos)
		Defs.Mech.PULL:
			var hit := _ray_body(pos)
			p.pull_dir = Vector3(cam.global_basis.x.x, 0, cam.global_basis.x.z).normalized()
			if not hit.is_empty():
				pass
		Defs.Mech.RUB:
			_do_rub(p, pos, 0.0)

func _cut_start(p: Problem, pos: Vector2) -> void:
	var path := p.cut_path
	if path.is_empty():
		return
	var d0 := cam.unproject_position(path[0]).distance_to(pos)
	var d1 := cam.unproject_position(path[path.size() - 1]).distance_to(pos)
	cut_rev = d1 < d0
	cut_idx = 0
	off_path_t = 0.0

func _cut_drag(p: Problem, pos: Vector2, delta_t: float) -> void:
	var path := p.cut_path
	var n := path.size()
	if n < 2:
		return
	var nxt := cut_idx + 1
	if nxt >= n:
		return
	var pi := (n - 1 - nxt) if cut_rev else nxt
	var sp := cam.unproject_position(path[pi])
	if sp.distance_to(pos) < 40.0:
		cut_idx = nxt
		p.set_cut(float(cut_idx) / (n - 1))
		Sfx.play_throttled("cut", 0.12, 0.2, -4)
		MeshGen.burst(body, path[pi], Problem.BLOOD_C, 2, 0.3, 0.006, Vector3.UP, 60.0)
		off_path_t = 0.0
	else:
		var cur := (n - 1 - cut_idx) if cut_rev else cut_idx
		var cs := cam.unproject_position(path[cur])
		if cs.distance_to(pos) > 110.0 and sp.distance_to(pos) > 110.0:
			off_path_t += delta_t
			if off_path_t > 0.25:
				off_path_t = -0.6
				mistakes += 1
				_hurt(9.0, ["Fora da linha!!", "AAAI, aí não!"])
				var hit := _ray_body(pos)
				if not hit.is_empty() and selected == "bisturi":
					_make_wound(hit[0], hit[1])

func _do_rub(p: Problem, pos: Vector2, px: float) -> void:
	var hit := _ray_body(pos)
	var wpos: Vector3
	if not hit.is_empty():
		wpos = hit[0]
	else:
		# entre os dedos: projeta no plano do problema
		var o := cam.project_ray_origin(pos)
		var d := cam.project_ray_normal(pos)
		wpos = o + d * ((p.center().y - o.y) / d.y)
	if p.uses_nail_mask():
		p.rub_nail(wpos, BRUSH.get(selected, 0.04) * 0.6)
	else:
		p.rub(wpos, px, BRUSH.get(selected, 0.04))
	_dirty_pain(p, 0.02)

func _drag(pos: Vector2) -> void:
	var rel := pos.distance_to(last_pos)
	last_pos = pos
	if active == null and selected != "" and not wide:
		var p := _pick_problem(pos)
		if p and p.tool() == selected and p.mech() in [Defs.Mech.RUB, Defs.Mech.SWEEP]:
			_start_on(p, pos)
	var a := active
	if a == null:
		return
	match a.mech():
		Defs.Mech.RUB:
			if _within(a, pos, 1.8):
				_rub_fx(a)
				_do_rub(a, pos, rel)
		Defs.Mech.CUT:
			_cut_drag(a, pos, 1.0 / 60.0)
		Defs.Mech.PULL:
			frame_pull += rel
		Defs.Mech.SWEEP:
			if a.sweep(pos, _sweep_r(), cam) == 0:
				_rub_fx(a)

func _release() -> void:
	pressing = false
	active = null
	_update_labels()

func _sweep_r() -> float:
	return 55.0

func _rub_fx(p: Problem) -> void:
	if now - rub_t < 0.07:
		return
	rub_t = now
	var pos := tool_model.global_position
	var up := Vector3.UP
	match selected:
		"pano":
			MeshGen.burst(body, pos, Color(0.85, 0.95, 1.0, 0.8), 3, 0.4, 0.012, up, 70.0, -1.0, 0.5)
			Sfx.play_throttled("scrub", 0.12)
		"algodao":
			MeshGen.burst(body, pos, Color(1, 1, 1), 2, 0.3, 0.008, up, 80.0, -1.0, 0.4, false)
			Sfx.play_throttled("scrub", 0.16, 0.2, -10)
		"raspador", "lixa":
			var c := Color(0.95, 0.88, 0.7) if p.id in ["calo", "fungo_unha", "verruga"] else Color(0.5, 0.2, 0.12)
			if p.id == "fungo_unha":
				c = Color(0.85, 0.7, 0.3)
			MeshGen.burst(body, pos, c, 3, 0.7, 0.007, up, 60.0, -5.0, 0.7, false)
			Sfx.play_throttled("scrub", 0.1, 0.3, -6)
		"pomada":
			MeshGen.burst(body, pos, Color(1, 1, 1), 2, 0.15, 0.01, up, 80.0, -0.5, 0.8)
			Sfx.play_throttled("scrub", 0.2, 0.2, -12)
		"lamina":
			Sfx.play_throttled("scrub", 0.15, 0.2, -10)

func _wrong(p: Problem, pos: Vector2) -> void:
	if now - last_mistake < 0.8:
		return
	last_mistake = now
	mistakes += 1
	var sharp: bool = Defs.TOOLS[selected]["sharp"]
	_hurt(16.0 if sharp else 9.0, Defs.OUCH)
	_float_text("AI!", cam.unproject_position(p.center()) + Vector2(0, -50), UIKit.RED, 46)
	_toast("Ferramenta errada! Piorou!", UIKit.RED, 40, 1.0)
	# fica pior: inflama mais / sangra
	var hit := _ray_body(pos)
	if sharp and not hit.is_empty():
		_make_wound(hit[0] + Vector3(randf_range(-0.03, 0.03), 0, randf_range(-0.03, 0.03)), hit[1])
	MeshGen.burst(body, p.center(), Problem.BLOOD_C if sharp else Color(1, 0.5, 0.5), 6, 0.6, 0.008, Vector3.UP, 50.0)
	if level <= 3:
		hint_until = maxf(hint_until, now + 4.0)
	_update_labels()

# =================================================================== eventos

func _on_stage_done(p: Problem, fin: bool) -> void:
	if p == active:
		active = null
	done_stages += 1
	combo = combo + 1 if now - last_stage_t < 4.0 else 1
	last_stage_t = now
	var c := 5 + (combo - 1) * 3
	earned += c
	pain = maxf(0.0, pain - 6.0)
	face.relieve()
	if randf() < 0.5:
		_say(Defs.RELIEF.pick_random())
	var sp := cam.unproject_position(p.center())
	_float_text("+%d" % c, sp + Vector2(0, -40), UIKit.YELLOW, 40)
	if combo >= 2:
		_toast("COMBO x%d!" % combo, UIKit.PINK, 48, 0.8)
	Sfx.play("coin", 0.05, -8)
	GameData.vibrate(25)
	progress_bar.value = 100.0 * done_stages / total_stages
	for q in problems:
		q.show_guide(q == focus and q.tool() == selected)
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
			await get_tree().create_timer(0.6).timeout
			if not finished and not pressing:
				_focus_on(_nearest(p.center()))
			elif not finished:
				focus = _nearest(p.center())

func _on_popped(p: Problem, _c: Color) -> void:
	shake = 0.025
	GameData.vibrate(40)
	if randf() < 0.7:
		var sp := cam.unproject_position(p.center())
		_float_text(EXCLAIMS.pick_random(), sp + Vector2(randf_range(-60, 60), -80), Color("b6ff6b"), 42)

# =================================================================== fim

func _fail() -> void:
	finished = true
	input_ok = false
	pressing = false
	active = null
	tool_model.hide()
	face.pain = 100.0
	_say("BUÁÁÁ! Vou embora!!")
	Sfx.play("wrong")
	await get_tree().create_timer(1.0).timeout
	modal_open = true
	var m := UIKit.modal(hud_root)
	var dim: Control = m[0]
	var vb: VBoxContainer = m[1]
	vb.add_child(UIKit.label("O PACIENTE FOI EMBORA CHORANDO!", 40, UIKit.RED))
	var f := PatientFace.new()
	f.custom_minimum_size = Vector2(150, 150)
	f.skin = data["look"]["skin"]
	f.hair = data["look"]["hair"]
	f.pain = 100.0
	f.hurt_flash = 99.0
	var fc := CenterContainer.new()
	fc.add_child(f)
	vb.add_child(fc)
	vb.add_child(UIKit.label("Ferramenta errada e pressa machucam. Limpe antes e vá com calma!", 22, UIKit.DARK, 0))
	var h := UIKit.hbox(16)
	vb.add_child(h)
	var cont := UIKit.btn("Acalmar e continuar (AD)", UIKit.GREEN, 24, Vector2(340, 76))
	cont.pressed.connect(func(): Ads.show_rewarded(func():
		dim.queue_free()
		modal_open = false
		finished = false
		input_ok = true
		pain = 35.0
		face.hurt_flash = 0.0
		_say("Tá bom... mas com cuidado!")))
	h.add_child(cont)
	var retry := UIKit.btn("Tentar de novo", UIKit.BLUE, 24, Vector2(230, 76))
	retry.pressed.connect(func(): get_tree().reload_current_scene())
	h.add_child(retry)
	var menu := UIKit.btn("Menu", UIKit.PURPLE, 24, Vector2(150, 76))
	menu.pressed.connect(_to_menu)
	h.add_child(menu)

func _finish() -> void:
	finished = true
	input_ok = false
	pressing = false
	active = null
	tool_model.hide()
	face.happy = true
	_say("Ficou perfeito!!")
	Sfx.play("success")
	_toast("PACIENTE CURADO!", UIKit.GREEN, 60, 1.4)
	await get_tree().create_timer(1.0).timeout
	_go_wide()
	await get_tree().create_timer(1.2).timeout
	hud.visible = false
	var after := await _capture()
	hud.visible = true
	var stars := 3
	if max_pain >= 70.0 or mistakes > 3:
		stars = 1
	elif max_pain >= 40.0 or mistakes > 0:
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
	vb.add_child(UIKit.label("\"%s\" - %s" % [Defs.THANKS.pick_random(), data["look"]["name"]], 24, UIKit.DARK, 0))
	var coins_row := UIKit.hbox(8)
	var ic := UIKit.CoinIcon.new()
	ic.custom_minimum_size = Vector2(46, 46)
	coins_row.add_child(ic)
	var coin_lbl := UIKit.label("+%d" % reward, 44, Color("ffc43d"))
	coins_row.add_child(coin_lbl)
	coins_row.add_child(UIKit.label("   dor máxima: %d%%" % int(max_pain), 22, UIKit.RED if max_pain > 40 else UIKit.GREEN.darkened(0.3), 0))
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

	# paciente (rosto + dor)
	var pp := PanelContainer.new()
	pp.add_theme_stylebox_override("panel", UIKit.style(Color(1, 1, 1, 0.85), 24, 4, Color("d9cff0")))
	pp.position = Vector2(12, 12)
	pp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(pp)
	var pv := VBoxContainer.new()
	pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pv.add_theme_constant_override("separation", 2)
	pp.add_child(pv)
	face = PatientFace.new()
	face.custom_minimum_size = Vector2(118, 104)
	face.skin = data["look"]["skin"]
	face.hair = data["look"]["hair"]
	pv.add_child(face)
	var pl := UIKit.label("DOR", 16, UIKit.DARK, 0)
	pv.add_child(pl)
	pain_bar = ProgressBar.new()
	pain_bar.custom_minimum_size = Vector2(118, 16)
	pain_bar.show_percentage = false
	pain_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pain_bar.add_theme_stylebox_override("background", UIKit.style(Color(0.15, 0.1, 0.25, 0.3), 8))
	pain_bar.add_theme_stylebox_override("fill", UIKit.style(UIKit.GREEN, 8))
	pv.add_child(pain_bar)
	bubble = UIKit.label("", 22, UIKit.DARK, 0)
	var bp := PanelContainer.new()
	bp.add_theme_stylebox_override("panel", UIKit.style(Color.WHITE, 18, 3, UIKit.DARK))
	bp.position = Vector2(160, 30)
	bp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bp.add_child(bubble)
	bp.visible = false
	hud_root.add_child(bp)
	bubble.set_meta("panel", bp)

	var pause := UIKit.btn("II", UIKit.PURPLE, 28, Vector2(70, 64))
	hud_root.add_child(pause)
	pause.anchor_left = 1.0
	pause.anchor_right = 1.0
	pause.offset_left = -86
	pause.offset_right = -16
	pause.offset_top = 86
	pause.offset_bottom = 150
	pause.pressed.connect(_pause)

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
	progress_bar.custom_minimum_size = Vector2(460, 22)
	progress_bar.show_percentage = false
	progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_bar.add_theme_stylebox_override("background", UIKit.style(Color(0.15, 0.1, 0.25, 0.6), 11))
	progress_bar.add_theme_stylebox_override("fill", UIKit.style(UIKit.BLUE, 11))
	top.add_child(progress_bar)
	lbl_problem = UIKit.label("", 28, Color("fff3b0"), 7)
	top.add_child(lbl_problem)
	lbl_hint = UIKit.label("", 22, Color.WHITE, 6)
	top.add_child(lbl_hint)

	var side := VBoxContainer.new()
	side.anchor_left = 1.0
	side.anchor_right = 1.0
	side.anchor_top = 0.5
	side.anchor_bottom = 0.5
	side.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	side.offset_left = -160
	side.offset_right = -14
	side.offset_top = -80
	side.offset_bottom = 70
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_theme_constant_override("separation", 12)
	hud_root.add_child(side)
	var hint := UIKit.btn("Dica (AD)", UIKit.YELLOW, 22, Vector2(140, 62))
	hint.pressed.connect(func(): Ads.show_rewarded(func():
		hint_until = now + 30.0
		_toast("Dicas ligadas por 30s!", UIKit.YELLOW, 36, 1.2)
		_update_labels()))
	side.add_child(hint)
	var zoom := UIKit.btn("Zoom", UIKit.BLUE, 22, Vector2(140, 62))
	zoom.pressed.connect(func():
		if not input_ok:
			return
		if wide:
			_focus_on(focus if focus and not focus.done else _nearest(body.cam_center))
		else:
			_go_wide())
	side.add_child(zoom)

	var bar_panel := PanelContainer.new()
	var sb := UIKit.style(Color(1, 1, 1, 0.88), 24, 4, Color("d9cff0"))
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	bar_panel.add_theme_stylebox_override("panel", sb)
	bar_panel.anchor_left = 0.5
	bar_panel.anchor_right = 0.5
	bar_panel.anchor_top = 1.0
	bar_panel.anchor_bottom = 1.0
	bar_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar_panel.offset_bottom = -8
	bar_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	hud_root.add_child(bar_panel)
	tool_bar = UIKit.hbox(6)
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
		b.custom_minimum_size = Vector2(86, 100)
		b.focus_mode = Control.FOCUS_NONE
		_style_tool(b, false)
		var ic := ToolIcon.new()
		ic.tool_id = id
		ic.set_anchors_preset(Control.PRESET_FULL_RECT)
		ic.offset_left = 12
		ic.offset_right = -12
		ic.offset_top = 6
		ic.offset_bottom = -32
		b.add_child(ic)
		var l := UIKit.label(Defs.TOOLS[id]["name"], 14, UIKit.DARK, 0)
		l.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		l.offset_top = -28
		l.offset_bottom = -6
		b.add_child(l)
		b.pressed.connect(func(): _select_tool(id))
		tool_bar.add_child(b)
		tool_buttons[id] = b
	if selected != "" and tool_buttons.has(selected):
		_style_tool(tool_buttons[selected], true)

func _style_tool(b: Button, sel: bool) -> void:
	var st := UIKit.style(Color("fff6d6") if sel else Color.WHITE, 18, 5 if sel else 3, UIKit.YELLOW if sel else Color("d9cff0"))
	for k in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(k, st)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

func _select_tool(id: String) -> void:
	if selected != "" and tool_buttons.has(selected):
		_style_tool(tool_buttons[selected], false)
	selected = id
	_style_tool(tool_buttons[id], true)
	tool_model.set_tool(id)
	Sfx.play("tap")
	_bounce(tool_buttons[id])
	for q in problems:
		q.show_guide(q == focus and q.tool() == selected)
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
	var cnt := Defs.stage_count(p.id)
	lbl_problem.text = p.pname() + ("   (etapa %d/%d)" % [p.stage + 1, cnt] if cnt > 1 else "")
	if _dirt_mult(p) < 1.0:
		lbl_hint.text = "Tá sujo em volta: limpe com o Pano primeiro!"
	elif _hints_on():
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

func _say(text: String) -> void:
	if bubble == null:
		return
	bubble.text = text
	var bp: Control = bubble.get_meta("panel")
	bp.visible = true
	bp.modulate.a = 1.0
	bp.scale = Vector2(0.6, 0.6)
	var tw := bp.create_tween()
	tw.tween_property(bp, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.6)
	tw.tween_property(bp, "modulate:a", 0.0, 0.3)

func _toast(text: String, color := Color.WHITE, size := 40, dur := 1.0) -> void:
	var l := UIKit.label(text, size, color, 10)
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.grow_vertical = Control.GROW_DIRECTION_BOTH
	l.offset_top = 110
	l.offset_bottom = 180
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
