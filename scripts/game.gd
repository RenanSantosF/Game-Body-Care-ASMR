extends Node3D
## Tela de tratamento: mão/pé no travesseiro, câmera de cima, ferramentas, dor do paciente.

const EXCLAIMS := ["ECA!", "QUE NOJO!", "SPLASH!", "ARGH!", "SPLOFT!", "NOJENTO!", "BLERGH!"]
const PRAISE := ["PERFEITO!", "LIMPINHO!", "ÓTIMO!", "BRILHANDO!", "ALÍVIO!", "LINDO!"]
const BRUSH := {"pano": 0.07, "algodao": 0.056, "raspador": 0.04, "lixa": 0.035, "pomada": 0.06}
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
var skin_cut: Problem = null       # corte errado sendo feito agora
var stroke_first := true
var press_cur := 0.0
var pull_cur := 0.0
var last_cut_hurt := -10.0
# câmera controlada pelo jogador (pinça para zoom, arrastar para mover)
var cam_dist := 4.6
const WIDE_D := 4.6
const MIN_D := 0.55
# toque: dedo da ferramenta + segundo dedo (aciona) ou gesto de câmera
const TOOL_OFFSET := Vector2(-70, -130)   # ferramenta aparece acima/esquerda do dedo
var touches := {}
var tool_touch := -1
var trig_touch := -1
var triggering := false
var pus_str: PusString = null
var wrong_p: Problem = null
var after_p: Problem = null      # continuando com ferramenta de etapa já feita (efeito leve, sem dor)
var stroke_locked := false
var use_btn: UseButton       # etapa terminou durante o arrasto: só começa outro problema após soltar o dedo      # problema que o jogador está estragando com a ferramenta errada
var buzz_t := 0.0
var cam_gesture := false
var pinch_d0 := 1.0
var cam_d0 := 1.0
var pan_last := Vector2.ZERO
var grip_start := Vector2.ZERO
var pull_max := 0.0
var tool_pos := Vector3.ZERO
var tool_vel := Vector3.ZERO
var guide: GuideArrow
var pending_focus := false
var coach: TwoFingerCoach
var aim_still := 0.0
var coached := false

var hud: CanvasLayer
var hud_root: Control
var tool_bar: GridContainer
var tool_buttons := {}
var progress_bar: ProgressBar
var pain_bar: ProgressBar
var face: PatientFace
var bubble: Label
var lbl_problem: Label
var lbl_hint: Label
var modal_open := false
var restoring := false           # recuperando o progresso salvo (sem efeitos)
var resumed := false

const CKPT := "user://checkpoint.json"
const CKPT_IMG := "user://checkpoint_antes.png"

# =================================================================== setup

func _ready() -> void:
	level = GameData.current_level
	data = LevelGen.make(level)
	# (dev) laboratório: força problemas/parte específicos
	if GameData.has_meta("lab_problems"):
		data["problems"] = GameData.get_meta("lab_problems")
		data["part"] = GameData.get_meta("lab_part", data["part"])
	rng.seed = data["seed"] + 99
	Stage.setup_env(self, data["look"]["pillow"])
	Sfx.play_music("clinic")
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
		var sp_p := _spawn(data["problems"][i], sp, prng)
		sp_p.set_meta("idx", i)
	# cabelo/sobrancelhas (rosto e cabeça), afastado de cada problema
	var excl := []
	for p in problems:
		excl.append([p.center(), p.size * 1.25 + 0.05])
	body.build_hair(data["look"]["hair"], excl)

	cam = Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.current = true
	cam_dist = WIDE_D
	cam_look = Vector3(body.cam_center.x, 0, body.cam_center.z)
	_apply_cam()

	tool_model = ToolModel.new()
	add_child(tool_model)
	tool_model.hide()

	_build_hud()
	hud.visible = false
	# foto do ANTES enquadrada nos machucados (para a comparação mostrar a diferença)
	var fr := _frame_all()
	cam_look = fr[0]
	cam_dist = fr[1]
	_apply_cam()
	var ck := _load_ckpt()
	if not ck.is_empty() and FileAccess.file_exists(CKPT_IMG):
		before_img = Image.load_from_file(ProjectSettings.globalize_path(CKPT_IMG))
	else:
		before_img = await _capture()
		if before_img and not GameData.has_meta("lab_problems"):
			before_img.save_png(CKPT_IMG)
	if not ck.is_empty():
		_restore(ck)
	cam_dist = WIDE_D
	cam_look = Vector3(body.cam_center.x, 0, body.cam_center.z)
	_apply_cam()
	hud.visible = true
	_check_tools()

## ---- progresso salvo dentro da fase (se o app travar/fechar, continua de onde parou)

func _load_ckpt() -> Dictionary:
	if GameData.has_meta("lab_problems") or not FileAccess.file_exists(CKPT):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(CKPT))
	if typeof(d) != TYPE_DICTIONARY or int(d.get("level", -1)) != level:
		clear_ckpt()
		return {}
	return d

func _save_ckpt() -> void:
	if GameData.has_meta("lab_problems") or restoring or finished:
		return
	var st := {}
	for p in problems:
		if p.has_meta("idx"):
			st[str(p.get_meta("idx"))] = -1 if p.done else p.stage
	var d := {"level": level, "stages": st, "earned": earned, "mistakes": mistakes, "max_pain": max_pain}
	var f := FileAccess.open(CKPT, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))

static func clear_ckpt() -> void:
	for f in [CKPT, CKPT_IMG]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))

## Avança cada problema até a etapa salva, sem sons/efeitos
func _restore(ck: Dictionary) -> void:
	var st: Dictionary = ck.get("stages", {})
	restoring = true
	for p in problems:
		if not p.has_meta("idx"):
			continue
		var key := str(p.get_meta("idx"))
		if not st.has(key):
			continue
		var target := int(st[key])
		var base: int = p.def["stages"].size()
		if target < 0:
			target = 999
		var guard := 0
		while not p.done and p.stage < mini(target, base) and guard < 20:
			guard += 1
			p._complete_stage()
		if target == 999 and not p.done:
			p.done = true
			p._on_done()
	restoring = false
	earned = int(ck.get("earned", 0))
	mistakes = int(ck.get("mistakes", 0))
	max_pain = float(ck.get("max_pain", 0.0))
	resumed = done_stages > 0
	_update_progress()
	GameData.log_line("progresso recuperado: %d etapas" % done_stages)

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
	p.extra_stages.connect(func(_q, c):
		total_stages += c
		_update_progress())
	problems.append(p)
	total_stages += p.def["stages"].size()
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
	if img and img.get_width() > 720:
		img.resize(720, int(img.get_height() * 720.0 / img.get_width()), Image.INTERPOLATE_BILINEAR)
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
	var row := GridContainer.new()
	row.columns = 2
	row.add_theme_constant_override("h_separation", 20)
	row.add_theme_constant_override("v_separation", 16)
	var rc := CenterContainer.new()
	rc.add_child(row)
	vb.add_child(rc)
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
		var buy := UIKit.btn(tr("Comprar %d") % price, UIKit.BLUE, 22, Vector2(200, 60))
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

## Saindo da fase (próximo paciente/menu): para animações presas a nós que vão sumir
func _exit_tree() -> void:
	GameData.log_line("saiu da fase %d" % level)
	for tw in get_tree().get_processed_tweens():
		if tw.is_valid():
			tw.kill()
	set_process(false)

func _begin() -> void:
	GameData.log_line("fase %d (%s): %s" % [level, data["part"], str(data["problems"])])
	_toast(tr("Fase %d  -  %s") % [level, tr(data["look"]["name"])], Color.WHITE, 46, 1.4)
	if resumed:
		_toast("Continuando de onde parou!", UIKit.GREEN, 34, 1.6)
	_say("Doutor, me ajuda!")
	if data["extreme"]:
		await get_tree().create_timer(0.9).timeout
		_toast("PACIENTE CHEFE!", UIKit.RED, 64, 1.3)
		shake = 0.03
		GameData.vibrate(120, 1.0)
		Sfx.play("squish")
		await get_tree().create_timer(1.0).timeout
		_toast(tr("%d problemas! Recompensa x3") % problems.size(), Color("ffc43d"), 36, 1.4)
	await get_tree().create_timer(1.0).timeout
	_focus_on(_first_problem())
	input_ok = true
	if level <= 2:
		coach.intro()
	_update_labels()

func _first_problem() -> Problem:
	# começa pela sujeira (limpar antes facilita), depois pelo mais próximo do centro
	for p in problems:
		if not p.done and p.id == "sujeira":
			return p
	return _nearest(body.cam_center)

# =================================================================== câmera

const CAM_UP := Vector3(1, 0, 0)   # retrato: dedos apontam para cima na tela

func _wide_pos() -> Vector3:
	return _cam_pos_for(body.cam_center, WIDE_D)

func _cam_pos_for(look: Vector3, d: float) -> Vector3:
	return look + Vector3(0, d, 0) - CAM_UP * d * 0.36

func _apply_cam() -> void:
	var off := Vector3.ZERO
	if shake > 0.0:
		off = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * shake
	cam_pos = _cam_pos_for(cam_look, cam_dist)
	cam.global_position = cam_pos + off
	cam.look_at(cam_look + off, CAM_UP)
	wide = cam_dist > 2.6

func _move_cam(pos: Vector3, look: Vector3, dur := 0.7) -> void:
	# pos é ignorado: a câmera é definida por alvo + distância
	if cam_tween:
		cam_tween.kill()
	var d := clampf(pos.distance_to(look) / 1.065, MIN_D, WIDE_D)
	cam_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	cam_tween.tween_property(self, "cam_dist", d, dur)
	cam_tween.tween_property(self, "cam_look", look, dur)

## Zoom/pan com dois dedos
func _cam_zoom(factor: float, focus_px := Vector2(-1, -1)) -> void:
	if cam_tween:
		cam_tween.kill()
	var before := _screen_to_plane(focus_px) if focus_px.x >= 0 else cam_look
	cam_dist = clampf(cam_dist * factor, MIN_D, WIDE_D)
	_apply_cam()
	if focus_px.x >= 0:
		var after := _screen_to_plane(focus_px)
		cam_look += before - after
		_clamp_look()

func _cam_pan(delta_px: Vector2) -> void:
	if cam_tween:
		cam_tween.kill()
	var a := _screen_to_plane(pan_last)
	var b := _screen_to_plane(pan_last + delta_px)
	cam_look += a - b
	_clamp_look()

func _clamp_look() -> void:
	cam_look.x = clampf(cam_look.x, -2.4, 2.2)
	cam_look.z = clampf(cam_look.z, -1.3, 1.0)
	cam_look.y = 0.0

func _screen_to_plane(px: Vector2) -> Vector3:
	var o := cam.project_ray_origin(px)
	var d := cam.project_ray_normal(px)
	if absf(d.y) < 0.001:
		return cam_look
	return o + d * ((0.1 - o.y) / d.y)

func _focus_on(p: Problem) -> void:
	if p == null:
		return
	focus = p
	wide = false
	var fr := _frame_for(p.center(), p.focus_radius())
	_move_cam(_cam_pos_for(fr[0], fr[1]), fr[0])
	_update_labels()
	for q in problems:
		q.show_guide(q == p and q.tool() == selected)

## Enquadra o alvo inteiro na área útil: abaixo do HUD e acima da barra de ferramentas,
## com folga para o dedo (a ferramenta fica acima/esquerda dele). Retorna [look, dist].
func _frame_for(target: Vector3, radius: float) -> Array:
	var vr := get_viewport().get_visible_rect().size
	var bar_top := vr.y * 0.82
	if tool_bar and tool_bar.get_parent() is Control:
		var br := (tool_bar.get_parent() as Control).get_global_rect()
		if br.size.y > 1.0:
			bar_top = br.position.y
	var top := vr.y * 0.14
	# deixa livre o botão de usar (canto de baixo, à esquerda)
	var bottom := maxf(top + vr.y * 0.3, bar_top + TOOL_OFFSET.y - 60.0)
	var want := Vector2(vr.x * 0.5 + TOOL_OFFSET.x * 0.25, (top + bottom) * 0.5)
	var max_r := minf(vr.x * 0.36, (bottom - top) * 0.5 * 0.9)
	var d := clampf(0.6 + radius * 2.6, 0.92, WIDE_D * 0.8)
	var look := target
	var saved := cam.global_transform
	for it in 6:
		cam.global_position = _cam_pos_for(look, d)
		cam.look_at(look, CAM_UP)
		var c := cam.unproject_position(target)
		var rp := c.distance_to(cam.unproject_position(target + cam.global_basis.x * radius))
		if rp > max_r:
			d = minf(d * rp / max_r * 1.03, WIDE_D * 0.8)
		var a := _plane_hit(c, target.y)
		var b := _plane_hit(want, target.y)
		look += Vector3(a.x - b.x, 0.0, a.z - b.z)
	cam.global_transform = saved
	return [look, d]

func _plane_hit(px: Vector2, y: float) -> Vector3:
	var o := cam.project_ray_origin(px)
	var dir := cam.project_ray_normal(px)
	if absf(dir.y) < 0.001:
		return o
	return o + dir * ((y - o.y) / dir.y)

## Enquadra todos os problemas da fase (para o antes/depois)
func _frame_all() -> Array:
	var c := Vector3.ZERO
	var n := 0
	for p in problems:
		if p.id == "machucado":
			continue
		c += p.center()
		n += 1
	if n == 0:
		return [Vector3(body.cam_center.x, 0, body.cam_center.z), WIDE_D]
	c /= n
	var r := 0.05
	for p in problems:
		if p.id != "machucado":
			r = maxf(r, Vector2(p.center().x - c.x, p.center().z - c.z).length() + p.size * 1.3)
	return _frame_for(c, r)

func _go_wide() -> void:
	_move_cam(_wide_pos(), Vector3(body.cam_center.x, 0, body.cam_center.z))
	_update_labels()

## Próximo problema sugerido (sujeira primeiro, depois o mais perto)
func _next_problem(from: Vector3) -> Problem:
	for p in problems:
		if not p.done and p.id == "sujeira":
			return p
	return _nearest(from)

## Ensina os dois dedos: aparece quando o jogador mira mas não usa o 2º dedo
func _update_coach(delta: float) -> void:
	if coach == null:
		return
	if use_btn:
		var vr := get_viewport().get_visible_rect().size
		var bar_top := vr.y * 0.82
		if tool_bar and tool_bar.get_parent() is Control:
			var br := (tool_bar.get_parent() as Control).get_global_rect()
			if br.size.y > 1.0:
				bar_top = br.position.y
		use_btn.center = Vector2(use_btn.radius + 26.0, bar_top - use_btn.radius - 22.0)
		use_btn.tool_id = selected
		use_btn.ready_glow = pressing and active != null and not triggering
		use_btn.visible = not modal_open and not finished
		coach.button = use_btn.center
	coach.aim = _screen_from_work(last_pos) if pressing else Vector2(-1, -1)
	coach.action = Vector2(-1, -1)
	if pressing and not triggering and active != null:
		aim_still += delta
	else:
		aim_still = 0.0
	var need := aim_still > (0.6 if not coached else 1.4)
	if need and not coach.showing:
		coach.show_hint(active.tool() if active else selected)
	elif (triggering or not pressing) and coach.showing:
		coach.hide_hint()
		if triggering:
			coached = true

func _screen_from_work(p: Vector2) -> Vector2:
	return p - TOOL_OFFSET if tool_touch >= 0 else p

func _update_guide() -> void:
	if guide == null:
		return
	if pressing and active and not active.done and not triggering and active.mech() in [Defs.Mech.HOLD, Defs.Mech.PULL, Defs.Mech.PICK, Defs.Mech.TAP]:
		var verb: String = {"pinca": "fechar a pinça", "espremedor": "apertar", "agulha": "furar", "spray": "borrifar", "curativo": "colar o curativo"}.get(selected, "usar")
		lbl_hint.text = tr("Segure o botão verde para %s!") % tr(verb)
	var p := focus if focus and not focus.done else _next_problem(cam_look)
	focus = p
	if p == null or finished:
		guide.visible = false
		return
	guide.visible = true
	guide.working = pressing and active == p
	guide.progress = p.progress
	guide.behind = cam.is_position_behind(p.center())
	guide.target = cam.unproject_position(p.center())
	guide.radius = _screen_radius(p)

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

var _diag_t := 0.0
var _diag_frames := 0

## Registro periódico do estado (vai para o relatório se o jogo travar/fechar)
func _diag(delta: float) -> void:
	_diag_frames += 1
	_diag_t += delta
	if delta > 0.4:
		GameData.log_line("quadro lento: %d ms (ferramenta=%s etapa=%s)" % [int(delta * 1000.0), selected, active.id + str(active.stage) if active else "-"])
	if _diag_t >= 5.0:
		GameData.log_line("fps=%d manchas=%d nos=%d mem=%dMB ferramenta=%s ativo=%s dedo=%s botao=%s" % [
			int(_diag_frames / _diag_t), body.stains.size() if body else 0, get_tree().get_node_count(),
			int(OS.get_static_memory_usage() / 1048576), selected, active.id + str(active.stage) if active else "-",
			str(pressing), str(triggering)])
		_diag_t = 0.0
		_diag_frames = 0

func _process(delta: float) -> void:
	now += delta
	_diag(delta)
	shake = maxf(0.0, shake - delta * 0.2)
	_apply_cam()
	if not input_ok:
		return
	pain = maxf(0.0, pain - delta * 1.6)
	# com muita dor o paciente treme
	if body and pain > 55.0 and not (_flinch_tw and _flinch_tw.is_running()):
		var k := (pain - 55.0) / 45.0 * 0.0035
		body.position = Vector3(randf_range(-k, k), 0.0, randf_range(-k, k))
	_update_pain()
	if pressing and active and (active.done or active.tool() != selected):
		active = null
	var a := active
	var oozing := false
	buzz_t -= delta
	if pressing and a:
		a.speed = GameData.speed_mult(selected) * _dirt_mult(a)
		match a.mech():
			Defs.Mech.HOLD:
				if triggering and _within(a, last_pos, 1.9):
					var c := a.hold_color()
					oozing = selected == "espremedor" and c.a > 0.0 and c != Problem.BLOOD_C
					if oozing:
						_ooze(a, delta)
					fx_t -= delta
					if fx_t <= 0.0:
						fx_t = 0.1
						if c.a > 0.0:
							MeshGen.burst(body, a.center() + a.global_basis.y * 0.04, c, 1 if oozing else 4, 0.7, 0.009, a.global_basis.y, 35.0)
						Sfx.play_throttled("freeze" if selected == "spray" else ("ooze" if oozing else "squish"), 0.3 if not oozing else 0.45, 0.2, -6)
					# vibração cresce conforme a pressão/progresso
					if buzz_t <= 0.0 and selected != "spray":
						buzz_t = lerpf(0.22, 0.09, a.progress)
						GameData.vibrate(18, lerpf(0.25, 0.85, a.progress))
					_dirty_pain(a, delta)
					a.hold(delta)
			Defs.Mech.PULL:
				# só puxa com a pinça fechada (segundo dedo); conta o quanto afastou da pegada
				var dnow := last_pos.distance_to(grip_start) if triggering else 0.0
				frame_pull = maxf(0.0, dnow - pull_max) if triggering else 0.0
				pull_max = maxf(pull_max, dnow)
				var cap := 480.0 * delta
				var amt := minf(frame_pull, cap)
				if frame_pull > cap * 2.4:
					_hurt(3.0 * delta * 30.0, Defs.OUCH_FAST, 0.9)
				if amt > 0.0:
					Sfx.play_throttled("pull", 0.3, 0.3, -10)
					if buzz_t <= 0.0:
						buzz_t = 0.12
						GameData.vibrate(12, clampf(0.2 + a.progress * 0.7, 0.2, 0.9))
					_dirty_pain(a, delta)
					a.pull(amt)
	if not oozing and pus_str:
		_end_ooze()
	frame_pull = 0.0
	_update_guide()
	_update_coach(delta)
	_update_tool_model()
	_blade_sweep()
	_update_deform(delta)
	_update_hint_glow()

## Fio de pus saindo enquanto espreme
func _ooze(a: Problem, delta: float) -> void:
	if pus_str and (not is_instance_valid(pus_str) or pus_str.full()):
		_end_ooze()
	if pus_str == null:
		pus_str = PusString.new()
		body.add_child(pus_str)
		var nrm := a.global_basis.y
		var o := a.center() + nrm * a.size * 0.28 * (1.0 - a.progress * 0.5)
		pus_str.global_position = o
		var col := (Problem.PUS_C * a.pus_tint).lerp(Color(0.96, 0.92, 0.75), 0.35).darkened(0.08)
		col.a = 1.0
		pus_str.setup(body, o, nrm, col, clampf(a.size * 0.13, 0.006, 0.014))
	pus_str.grow(delta * (0.05 + 0.08 * a.progress) * a.speed)

func _end_ooze() -> void:
	if pus_str and is_instance_valid(pus_str):
		pus_str.detach()
		Sfx.play("drip", 0.2, -8)
	pus_str = null

var _flinch_tw: Tween
## O paciente recua de dor (puxa a mão/pé um pouquinho e volta)
func _flinch(amount: float) -> void:
	if body == null or amount < 3.0:
		return
	if _flinch_tw and _flinch_tw.is_valid():
		_flinch_tw.kill()
	var k := clampf(amount / 16.0, 0.3, 1.0)
	var away := Vector3(-0.035, 0.012, randf_range(-0.015, 0.015)) * k
	_flinch_tw = create_tween()
	_flinch_tw.tween_property(body, "position", away, 0.07).set_ease(Tween.EASE_OUT)
	_flinch_tw.tween_property(body, "position", away * 0.35, 0.12)
	_flinch_tw.tween_property(body, "position", Vector3.ZERO, 0.35).set_trans(Tween.TRANS_SINE)

func _update_progress() -> void:
	if progress_bar:
		progress_bar.value = 100.0 * done_stages / maxi(1, total_stages)

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
	_flinch(amount)
	# machucou: vibração forte (proporcional ao estrago)
	if amount >= 2.0:
		GameData.vibrate(int(clampf(40.0 + amount * 5.0, 50.0, 140.0)), clampf(0.6 + amount * 0.03, 0.6, 1.0))
	if pain >= 100.0 and not finished:
		_update_pain()
		return
	if min_gap <= 0.0 or now - last_slow > min_gap:
		last_slow = now
		face.hurt()
		_say(lines.pick_random())
		Sfx.play("ouch", 0.15, -2)
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
		# arde e avisa, mas sozinho não faz perder a fase
		if pain < 70.0:
			pain = minf(70.0, pain + delta * 6.0)
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

## A pele afunda sob a ferramenta e a pinça puxa a pele junto
func _update_deform(delta: float) -> void:
	var pa := 0.0
	var pr := 0.04
	var ppos := tool_model.global_position
	var qa := 0.0
	var qpos := Vector3(0, -10, 0)
	# só afunda a pele quando a ferramenta está sendo usada (segurando o botão)
	if pressing and triggering and selected != "" and tool_model.visible:
		match selected:
			"espremedor":
				pa = 0.006
				if active and active.mech() == Defs.Mech.HOLD:
					ppos = active.center()
					pr = active.size * 1.1
					pa = 0.016 + 0.004 * sin(now * 28.0)
			"agulha", "bisturi", "alicate":
				pa = 0.007
				pr = 0.016
			"pano", "algodao", "pomada":
				pa = 0.008
				pr = 0.05
			"raspador", "lixa", "lamina":
				pa = 0.007
				pr = 0.035
			"pinca":
				if active and active.mech() == Defs.Mech.PULL:
					qpos = active.grip_point()
					qa = 0.008 + clampf(active.progress, 0.0, 1.0) * 0.02
			_:
				pa = 0.003
	# pinça tirando item pequeno: a pele estica junto (mesmo depois de soltar o botão)
	for q in problems:
		if q.pick_pull_amt > 0.0:
			qpos = q.pick_pull_pos
			qa = maxf(qa, q.pick_pull_amt)
	press_cur = lerpf(press_cur, pa, minf(1.0, delta * 14.0))
	pull_cur = lerpf(pull_cur, qa, minf(1.0, delta * 10.0))
	_press_pos = ppos
	_press_r = pr
	RenderingServer.global_shader_parameter_set("press_pos", ppos)
	RenderingServer.global_shader_parameter_set("press_amt", press_cur)
	RenderingServer.global_shader_parameter_set("press_r", pr)
	RenderingServer.global_shader_parameter_set("pull_pos", qpos)
	RenderingServer.global_shader_parameter_set("pull_amt", pull_cur)
	RenderingServer.global_shader_parameter_set("pull_r", 0.03)

var _fit := 1.0
## Espremedor do tamanho do caso: pequeno para cravos/espinhas da acne, maior para furúnculos
func _tool_fit() -> float:
	var want := 1.0
	if selected == "espremedor" or selected == "pinca":
		var t := active if active else _pick_problem(last_pos)
		if t and t.tool() == selected:
			if t.mech() == Defs.Mech.PICK:
				# pinça/espremedor pequenos para tirar coisas pequenas
				want = 0.55
			elif selected == "pinca":
				want = clampf(t.size / 0.1, 0.65, 1.1)
			else:
				want = clampf(t.size / 0.12, 0.65, 1.25)
	_fit = lerpf(_fit, want, 0.2)
	return _fit

var _press_pos := Vector3.ZERO
var _press_r := 0.04
## Quanto a pele sobe/desce neste ponto (mesma conta do deform.gdshaderinc)
func _skin_dy(p: Vector3) -> float:
	var dp := Vector2(p.x - _press_pos.x, p.z - _press_pos.z)
	var r2 := _press_r * _press_r
	var k := exp(-dp.dot(dp) / r2)
	var ring := exp(-pow(dp.length() - _press_r * 0.6, 2.0) / (r2 * 0.08))
	return -press_cur * (k * 0.6 + ring * 0.6) + press_cur * 0.5 * exp(-dp.dot(dp) / (r2 * 0.12))

func _update_tool_model() -> void:
	if not pressing or selected == "":
		tool_model.visible = false
		tool_model.set_active(false)
		tool_model.remove_meta("shown")
		return
	tool_model.visible = true
	var hit := _ray_body(last_pos)
	var pos: Vector3
	if hit.is_empty():
		var o := cam.project_ray_origin(last_pos)
		var d := cam.project_ray_normal(last_pos)
		pos = o + d * ((0.05 - o.y) / d.y)
	else:
		# encosta na pele: desce só o quanto a pele afundou ali (não atravessa)
		pos = hit[0] + hit[1] * 0.005 + Vector3(0, _skin_dy(hit[0]), 0)
		# em cima de espinha/furúnculo/bolha a ponta pousa no calombo (não entra antes de furar)
		for q in problems:
			if q.center().distance_to(pos) < q.size * 2.0:
				var top := q.surface_top(pos)
				if top > -INF:
					pos.y = maxf(pos.y, top + 0.004)
	if active and active.mech() == Defs.Mech.PULL and triggering:
		# a ponta da pinça fica exatamente onde está segurando (verme, pelo, carrapato...)
		pos = active.grip_point()
	if not tool_model.has_meta("shown"):
		tool_pos = pos
		tool_model.set_meta("shown", true)
	var prev := tool_pos
	tool_pos = tool_pos.lerp(pos, 0.45)
	tool_vel = tool_vel.lerp((tool_pos - prev) * 60.0, 0.2)
	tool_model.global_position = tool_pos
	tool_model.vel = tool_vel
	var cb := cam.global_basis
	var y := (Vector3.UP * 0.75 + cb.z * 0.35 + cb.x * 0.35 - Vector3(tool_vel.x, 0, tool_vel.z) * 0.15).normalized()
	if selected == "pano" or selected == "lixa":
		# pano e lixa deitam sobre a pele, alinhados com a superfície
		tool_model.drape_body = body
		y = (hit[1] if not hit.is_empty() else Vector3.UP).lerp(Vector3.UP, 0.3).normalized()
	var x := (cb.x - y * cb.x.dot(y)).normalized()
	var z := x.cross(y)
	var dist := cam.global_position.distance_to(pos)
	tool_model.global_basis = Basis(x, y, z).scaled(Vector3.ONE * clampf(dist / 1.3, 0.6, 2.5) * _tool_fit())
	tool_model.grip = triggering
	tool_model.set_active(active != null and triggering, active.mech() if active else -1)

# =================================================================== entrada

func _unhandled_input(e: InputEvent) -> void:
	if not input_ok or modal_open:
		return
	# ---- toque (celular)
	if e is InputEventScreenTouch:
		_on_touch(e.index, e.position, e.pressed)
		return
	if e is InputEventScreenDrag:
		_on_touch_drag(e.index, e.position, e.relative)
		return
	# ---- mouse (PC). Ignora o mouse emulado pelo toque.
	if e.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if e is InputEventMouseButton:
		match e.button_index:
			MOUSE_BUTTON_LEFT:
				if e.pressed:
					_tool_down(e.position)
				else:
					_tool_up()
			MOUSE_BUTTON_RIGHT:
				_trigger(e.pressed)
			MOUSE_BUTTON_WHEEL_UP:
				if e.pressed:
					_cam_zoom(0.9, e.position)
			MOUSE_BUTTON_WHEEL_DOWN:
				if e.pressed:
					_cam_zoom(1.1, e.position)
	elif e is InputEventMouseMotion:
		if e.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			pan_last = e.position - e.relative
			_cam_pan(e.relative)
		elif pressing:
			_drag(e.position)
	elif e is InputEventKey and e.keycode == KEY_SPACE and not e.echo:
		_trigger(e.pressed)

func _on_touch(idx: int, pos: Vector2, down: bool) -> void:
	if down:
		touches[idx] = pos
		if use_btn and use_btn.hit(pos) and trig_touch < 0:
			# segurar o botão verde = usar a ferramenta (a outra mão mira)
			trig_touch = idx
			use_btn.held = true
			if pressing:
				_trigger(true)
		elif tool_touch < 0:
			tool_touch = idx
			_tool_down(pos + TOOL_OFFSET)
			if trig_touch >= 0 and pressing:
				_trigger(true)
	else:
		touches.erase(idx)
		if idx == trig_touch:
			trig_touch = -1
			if use_btn:
				use_btn.held = false
			_trigger(false)
		if idx == tool_touch:
			tool_touch = -1
			_trigger(false)
			_tool_up()

func _on_touch_drag(idx: int, pos: Vector2, _rel: Vector2) -> void:
	touches[idx] = pos
	if idx == tool_touch:
		_drag(pos + TOOL_OFFSET)

func _tool_down(pos: Vector2) -> void:
	if selected == "":
		pressing = false
		last_pos = pos
		_toast("Escolha uma ferramenta embaixo!", UIKit.YELLOW, 32, 1.0)
		_bounce(tool_bar.get_parent())
		return
	_press(pos)

func _tool_up() -> void:
	if pressing:
		_release()

const STICK_PX := 230.0          # arrasto (px, para cima) para colar o curativo inteiro
const HARMFUL := ["agulha", "bisturi", "alicate", "lamina", "raspador", "lixa", "espremedor", "pinca"]

## Segundo dedo: só ele faz a ferramenta agir (furar, cortar, limpar, puxar, colar...)
func _trigger(on: bool) -> void:
	if on == triggering:
		return
	triggering = on
	if not on:
		if active:
			active.end_stroke()
		skin_cut = null
		return
	if not pressing or selected == "":
		return
	GameData.vibrate(10, 0.25)
	var a := active
	if a == null:
		var p := _pick_problem(last_pos)
		if p == null:
			# problema já tratado com uma ferramenta que ele usou: continua fazendo efeito
			var dp := _pick_done(last_pos)
			if dp and dp.used_tool(selected):
				after_p = dp
				return
			_skin_touch(last_pos)
			return
		if p.tool() != selected:
			if p.used_tool(selected):
				after_p = p
				return
			_wrong(p, last_pos)
			return
		_start_on(p, last_pos)
		a = active
	_act_start(a)

func _act_start(a: Problem) -> void:
	if selected in ["agulha", "bisturi"]:
		GameData.vibrate(22, 0.6)
	match a.mech():
		Defs.Mech.PICK:
			if not a.pick(last_pos, 70.0, cam):
				_toast("Mire em cima de um!", UIKit.YELLOW, 30, 0.6)
		Defs.Mech.TAP:
			# curativo: começa a colar embaixo; arrastando para cima ele vai assentando
			grip_start = last_pos
			a.stick(maxf(a.progress, 0.04))
			GameData.vibrate(10, 0.25)
		Defs.Mech.PULL:
			grip_start = last_pos
			pull_max = 0.0
			Sfx.play("pull", 0.2, -10)
		Defs.Mech.CUT:
			stroke_first = true
			if a.has_paint_cut():
				_paint_cut(a, last_pos)
			else:
				_cut_start(a, last_pos)
		Defs.Mech.RUB:
			_do_rub(a, last_pos, 0.0)
		Defs.Mech.SWEEP:
			if selected != "lamina":
				a.sweep(last_pos, _sweep_r(), cam)
			_blade_prev = []

func _screen_radius(p: Problem) -> float:
	var c := cam.unproject_position(p.center())
	var e := cam.unproject_position(p.center() + cam.global_basis.x * p.size)
	return maxf(c.distance_to(e), 26.0)

func _within(p: Problem, pos: Vector2, mult := 1.0) -> bool:
	return cam.unproject_position(p.center()).distance_to(pos) < _screen_radius(p) * mult + 22.0

## Problema sob o dedo. Se houver vários, prefere o que aceita a ferramenta escolhida.
func _pick_done(pos: Vector2) -> Problem:
	var best: Problem = null
	var bd := INF
	for p in problems:
		if not p.done:
			continue
		var d := cam.unproject_position(p.center()).distance_to(pos)
		if d < _screen_radius(p) * 1.3 + 22.0 and d < bd:
			bd = d
			best = p
	return best

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
	stroke_locked = false
	last_pos = pos
	frame_pull = 0.0
	var p := _pick_problem(pos)
	if p and p.tool() == selected:
		_start_on(p, pos)

## Ferramenta afiada em pele saudável machuca
func _skin_touch(pos: Vector2) -> void:
	if selected == "" or not selected in HARMFUL:
		return
	var hit := _ray_body(pos)
	if hit.is_empty() or now - last_skin_hurt < 1.0:
		return
	last_skin_hurt = now
	if not Defs.TOOLS[selected]["sharp"]:
		mistakes += 1
		if selected == "lixa":
			# lixa na pele boa: esfola (machucado pequeno, raso)
			_hurt(6.0, Defs.OUCH)
			_toast("Você esfolou a pele!", UIKit.RED, 30, 1.0)
			var wl := _make_wound(hit[0], hit[1])
			if wl:
				wl.blunt_kind = "lixa"
				wl.wound_stroke(hit[0], true)
				skin_cut = wl
				Sfx.play("scrub")
		else:
			# espremedor/pinça apertando a pele boa: belisca e fica roxo
			_hurt(7.0, Defs.OUCH)
			_bruise(hit[0])
			Sfx.play("squish", 0.2, -6)
		return
	mistakes += 1
	_hurt(10.0, Defs.OUCH)
	if selected in ["bisturi", "lamina", "alicate"]:
		_toast("Cuidado! Você cortou a pele!", UIKit.RED, 34, 1.0)
	var w := _make_wound(hit[0], hit[1])
	if w:
		w.wound_stroke(hit[0], true)
		if selected in ["bisturi", "lamina", "alicate"]:
			skin_cut = w
			Sfx.play("cut")
		else:
			Sfx.play("poke")
			_toast("Você furou a pele! Vai precisar limpar e fazer curativo.", UIKit.RED, 26, 1.6)

## Marca roxa/vermelha de beliscão que some sozinha
func _bruise(pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var rot := randf() * TAU
	mi.mesh = MeshGen.patch(body, pos, 0.035, rot, 0.0035)
	var m := MeshGen.shader_mat(Problem.LESION)
	m.set_shader_parameter("kind", Problem.L_BRUISE)
	m.set_shader_parameter("skin", body.skin_mat.get_shader_parameter("skin"))
	m.set_shader_parameter("seed", randf() * 40.0)
	m.set_shader_parameter("rot", rot)
	m.set_shader_parameter("half_size", 0.035)
	m.set_shader_parameter("strength", 0.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)
	mi.global_position = pos
	var tw := create_tween()
	tw.tween_method(func(v): m.set_shader_parameter("strength", v), 0.0, 0.9, 0.35)
	tw.tween_interval(5.0)
	tw.tween_method(func(v): m.set_shader_parameter("strength", v), 0.9, 0.0, 3.0)
	tw.tween_callback(mi.queue_free)

func _make_wound(pos: Vector3, normal: Vector3) -> Problem:
	if wounds >= MAX_WOUNDS:
		return null
	for q in problems:
		if not q.done and q.center().distance_to(pos) < q.size + 0.05:
			return null
	wounds += 1
	var p := _spawn("machucado", {"pos": pos, "normal": normal}, rng)
	_update_labels()
	p.show_guide(false)
	return p

func _start_on(p: Problem, pos: Vector2) -> void:
	active = p
	if focus == null or focus.done:
		focus = p
	p.speed = GameData.speed_mult(selected) * _dirt_mult(p)
	lbl_hint.text = p.cream_hint() if p.tool() == "pomada" else Defs.MECH_HINT[p.mech()]
	if p.mech() == Defs.Mech.PULL:
		p.pull_dir = Vector3(cam.global_basis.x.x, 0, cam.global_basis.x.z).normalized()

## Corte de verdade: a lâmina risca a pele exatamente onde o dedo passa
func _paint_cut(p: Problem, pos: Vector2) -> void:
	var hit := _ray_body(pos)
	var dh := p.ray_cut_host(cam.project_ray_origin(pos), cam.project_ray_normal(pos))
	# a interseção com o caroço pode escapar em raios rasantes: confia na pele se ficar longe
	if not dh.is_empty() and not hit.is_empty() and Vector2(dh[0].x - hit[0].x, dh[0].z - hit[0].z).length() > p.size * 0.9:
		dh = []
	var wpos: Vector3
	if not dh.is_empty():
		wpos = dh[0]
	elif hit.is_empty():
		var o := cam.project_ray_origin(pos)
		var d := cam.project_ray_normal(pos)
		wpos = o + d * ((p.center().y - o.y) / d.y)
	else:
		wpos = hit[0]
	# cortando a linha de OUTRO machucado que pede a mesma ferramenta: passa a cortar aquele
	if p.path_dist(wpos) > p.size * 0.6:
		for q in problems:
			if q != p and not q.done and q.tool() == selected and q.has_paint_cut() and q.path_dist(wpos) < q.size * 0.6:
				active = q
				p.end_stroke()
				p = q
				stroke_first = true
				break
	var md := p.cut_stroke(wpos, stroke_first)
	stroke_first = false
	Sfx.play_throttled("cut", 0.09, 0.25, -6)
	GameData.vibrate(10, 0.35)
	if md > p.size * 1.0 and now - last_cut_hurt > 0.7:
		last_cut_hurt = now
		mistakes += 1
		_hurt(8.0, ["Fora da linha!!", "AAAI, aí não!"])
		if hit.size() > 0 and md > p.size * 1.3:
			var w := _make_wound(hit[0], hit[1])
			if w:
				skin_cut = w
				w.wound_stroke(hit[0], true)

func _cut_start(p: Problem, pos: Vector2) -> void:
	var path := p.cut_path
	if path.is_empty():
		return
	var d0 := cam.unproject_position(path[0]).distance_to(pos)
	var d1 := cam.unproject_position(path[path.size() - 1]).distance_to(pos)
	cut_rev = d1 < d0
	p.cut_dir = -1.0 if cut_rev else 1.0
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
		if selected == "alicate" and p.id == "unha_suja":
			# cada "nhec" do alicate: estalo seco, farelinho de unha e vibração
			Sfx.play_throttled("clip", 0.08, 0.15, -2)
			MeshGen.burst(body, path[pi], Color(0.96, 0.92, 0.8), 3, 0.35, 0.003, Vector3.UP, 70.0, -6.0, 0.6, false)
			GameData.vibrate(16, 0.55)
		else:
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

var last_lixa_hint := -10.0
func _do_rub(p: Problem, pos: Vector2, px: float, delta := Vector2.ZERO) -> void:
	# lixa só lixa indo e voltando ao longo dela (na horizontal), como na vida real
	if selected == "lixa" and px > 0.0:
		if absf(delta.x) < absf(delta.y) * 1.2:
			if now - last_lixa_hint > 2.5 and px > 4.0:
				last_lixa_hint = now
				_toast("Lixe de um lado para o outro (na horizontal) ↔", UIKit.YELLOW, 28, 1.2)
			return
		px = absf(delta.x)
	var hit := _ray_body(pos)
	var wpos: Vector3
	if not hit.is_empty():
		wpos = hit[0]
	else:
		# entre os dedos: projeta no plano do problema
		var o := cam.project_ray_origin(pos)
		var d := cam.project_ray_normal(pos)
		wpos = o + d * ((p.center().y - o.y) / d.y)
	var gained := 0.0
	if p.uses_nail_mask():
		gained = p.rub_nail(wpos, BRUSH.get(selected, 0.04) * 0.6)
	else:
		var had := p.cream_ready()
		gained = p.rub(wpos, px, BRUSH.get(selected, 0.04))
		if selected == "pomada" and had != p.cream_ready():
			_toast("Agora espalhe a pomada!", UIKit.GREEN, 32, 1.0)
			_update_labels()
	if selected in ["pano", "algodao"]:
		body.clean_stains(wpos, BRUSH.get(selected, 0.04))
	# só mostra efeito/suja a ferramenta quando de fato está tirando algo
	if gained > 0.0004:
		_rub_fx(p)
		if buzz_t <= 0.0:
			buzz_t = 0.09
			GameData.vibrate(6, 0.18)
		if selected in ["pano", "algodao"]:
			tool_model.soil(p.soil_color(), minf(0.05, gained * 2.0))
	_dirty_pain(p, 0.02)

func _drag(pos: Vector2) -> void:
	var rel := pos.distance_to(last_pos)
	var prev_pos := last_pos
	last_pos = pos
	if active == null and selected != "" and not stroke_locked:
		var p := _pick_problem(pos)
		if p and p.tool() == selected:
			_start_on(p, pos)
			if triggering and p.mech() in [Defs.Mech.RUB, Defs.Mech.SWEEP, Defs.Mech.CUT]:
				_act_start(p)
	if not triggering:
		return
	# ferramenta de etapa já feita: continua com efeito leve
	if after_p and is_instance_valid(after_p) and rel > 0.5:
		var ah := _ray_body(pos)
		if not ah.is_empty() and ah[0].distance_to(after_p.center()) < after_p.size * 1.8:
			if after_p.after_effect(ah[0], selected):
				_rub_fx(after_p)
				if buzz_t <= 0.0:
					buzz_t = 0.12
					GameData.vibrate(5, 0.12)
	# arrastando a ferramenta errada por cima: estraga mais e dói
	if wrong_p and is_instance_valid(wrong_p) and not wrong_p.done and selected in HARMFUL:
		var wh := _ray_body(pos)
		if not wh.is_empty() and wh[0].distance_to(wrong_p.center()) < wrong_p.size * 1.7:
			wrong_p.blunt_kind = selected
			wrong_p.aggravate(wh[0], Defs.TOOLS[selected]["sharp"], false)
			pain = minf(100.0, pain + rel * 0.05)
			Sfx.play_throttled("cut" if Defs.TOOLS[selected]["sharp"] else "scrub", 0.1, 0.3, -6)
			if now - last_mistake > 1.2:
				last_mistake = now
				_hurt(4.0, Defs.OUCH)
	if skin_cut and is_instance_valid(skin_cut) and pressing:
		var hit := _ray_body(pos)
		if not hit.is_empty() and hit[0].distance_to(skin_cut.center()) < skin_cut.size * 2.0:
			skin_cut.wound_stroke(hit[0], false)
			pain = minf(100.0, pain + rel * 0.04)
			Sfx.play_throttled("cut", 0.1, 0.3, -6)
	# pano/algodão limpam o que sobrou mesmo depois do problema já "pronto"
	if selected in ["pano", "algodao"] and (active == null or active.tool() != selected):
		_clean_residue(pos)
	var a := active
	if a == null:
		return
	match a.mech():
		Defs.Mech.RUB:
			if _within(a, pos, 1.8):
				_do_rub(a, pos, rel, pos - prev_pos)
		Defs.Mech.CUT:
			if a.has_paint_cut():
				_paint_cut(a, pos)
			else:
				_cut_drag(a, pos, 1.0 / 60.0)
		Defs.Mech.PULL:
			frame_pull += rel
		Defs.Mech.TAP:
			var up := grip_start.y - pos.y
			if up > 0.0:
				var before := a.progress
				a.stick(maxf(a.progress, up / STICK_PX))
				if a.progress - before > 0.03:
					GameData.vibrate(6, 0.15)
		Defs.Mech.SWEEP:
			# o barbeador corta pela linha das lâminas (em _blade_sweep, a cada quadro)
			if selected != "lamina":
				var steps := clampi(int(rel / 20.0), 1, 12)
				for i in steps:
					a.sweep(prev_pos.lerp(pos, float(i + 1) / steps), _sweep_r(), cam)

func _clean_residue(pos: Vector2) -> void:
	var hit := _ray_body(pos)
	if hit.is_empty():
		return
	var wpos: Vector3 = hit[0]
	var br: float = BRUSH.get(selected, 0.04)
	var gained := 0.0
	for p in problems:
		if is_instance_valid(p) and p.center().distance_to(wpos) < p.size * 2.5 + br:
			gained += p.clean_residue(wpos, br)
	body.clean_stains(wpos, br)
	if gained > 0.0004:
		_rub_fx(problems[0])
		tool_model.soil(Color(0.55, 0.42, 0.25), minf(0.05, gained * 2.0))

func _release() -> void:
	pressing = false
	triggering = false
	if pending_focus and not finished:
		pending_focus = false
		var nx := _next_problem(cam_look)
		if nx:
			_focus_on(nx)
	if active:
		active.end_stroke()
	active = null
	skin_cut = null
	wrong_p = null
	after_p = null
	stroke_locked = false
	_update_labels()

func _sweep_r() -> float:
	return 55.0

var _blade_prev: Array = []
## Barbeador encostado e acionado: corta tudo que a linha das lâminas varreu neste quadro
func _blade_sweep() -> void:
	var seg := tool_model.blade_segment()
	if seg.is_empty() or not triggering or active == null or active.mech() != Defs.Mech.SWEEP:
		_blade_prev = []
		return
	var a1 := cam.unproject_position(seg[0])
	var b1 := cam.unproject_position(seg[1])
	var a0: Vector2 = _blade_prev[0] if _blade_prev.size() == 2 else a1
	var b0: Vector2 = _blade_prev[1] if _blade_prev.size() == 2 else b1
	if active.sweep_blade(a0, b0, a1, b1, 16.0, cam) > 0:
		Sfx.play_throttled("cut", 0.06, 0.2, -8)
		GameData.vibrate(6, 0.2)
	_blade_prev = [a1, b1]

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
	if not selected in HARMFUL:
		_toast(tr("%s não serve para isso. Use: %s") % [tr(Defs.TOOLS[selected]["name"]), tr(Defs.TOOLS[p.tool()]["name"])], UIKit.YELLOW, 26, 1.4)
		return
	if now - last_mistake < 0.8:
		return
	last_mistake = now
	mistakes += 1
	var sharp: bool = Defs.TOOLS[selected]["sharp"]
	_hurt(16.0 if sharp else (5.0 if selected == "lixa" else 8.0), Defs.OUCH)
	_float_text("AI!", cam.unproject_position(p.center()) + Vector2(0, -50), UIKit.RED, 46)
	_toast("Ferramenta errada! Piorou!", UIKit.RED, 40, 1.0)
	# fica pior ALI MESMO: corta/esfola o próprio machucado, sangra, inflama
	# e o jogador continua estragando enquanto arrasta a ferramenta errada por cima
	var hit := _ray_body(pos)
	var wp: Vector3 = hit[0] if not hit.is_empty() else p.center()
	wrong_p = p
	p.blunt_kind = selected
	if p.aggravate(wp, sharp, true):
		earned -= 10
		_float_text("-10", cam.unproject_position(p.center()) + Vector2(60, -10), UIKit.RED, 38)
	MeshGen.burst(body, wp, Problem.BLOOD_C if sharp else Color(1, 0.5, 0.5), 6, 0.6, 0.008, Vector3.UP, 50.0)
	body.spawn_drops(wp + Vector3.UP * 0.01, Vector3.UP, 3, 3 if sharp else 1, 0.5, 0.007, 0.5)
	if level <= 3:
		hint_until = maxf(hint_until, now + 4.0)
	_update_labels()

# =================================================================== eventos

func _on_stage_done(p: Problem, fin: bool) -> void:
	if restoring:
		done_stages += 1
		return
	GameData.log_line("%s etapa %d concluida%s" % [p.id, p.stage, " (fim)" if fin else ""])
	if p == active:
		active = null
	if pressing:
		stroke_locked = true
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
	if not fin:
		_toast(tr("PRONTO! Agora: %s") % tr(Defs.TOOLS[p.tool()]["name"]), UIKit.GREEN, 34, 1.2)
	if combo >= 2:
		_toast(tr("COMBO x%d!") % combo, UIKit.PINK, 48, 0.8)
	Sfx.play("coin", 0.05, -8)
	GameData.vibrate(20, 0.45)
	_update_progress()
	_save_ckpt()
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
			pending_focus = true
			await get_tree().create_timer(0.7).timeout
			if not finished and not pressing and pending_focus:
				pending_focus = false
				_focus_on(_next_problem(p.center()))

func _on_popped(p: Problem, _c: Color) -> void:
	if restoring:
		return
	shake = 0.025
	GameData.vibrate(70, 1.0)
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
	vb.add_child(UIKit.label("O PACIENTE FOI\nEMBORA CHORANDO!", 40, UIKit.RED))
	var f := PatientFace.new()
	f.custom_minimum_size = Vector2(150, 150)
	f.skin = data["look"]["skin"]
	f.hair = data["look"]["hair"]
	f.pain = 100.0
	f.hurt_flash = 99.0
	var fc := CenterContainer.new()
	fc.add_child(f)
	vb.add_child(fc)
	var tip := UIKit.label("Ferramenta errada e pressa machucam.\nLimpe antes e vá com calma!", 22, UIKit.DARK, 0)
	vb.add_child(tip)
	var h := VBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	var hc := CenterContainer.new()
	hc.add_child(h)
	vb.add_child(hc)
	var cont := UIKit.btn("Tentar de novo daqui (AD)", UIKit.GREEN, 26, Vector2(380, 84))
	cont.pressed.connect(func(): Ads.show_rewarded(func():
		dim.queue_free()
		modal_open = false
		finished = false
		input_ok = true
		pain = 35.0
		face.hurt_flash = 0.0
		_say("Tá bom... mas com cuidado!")))
	h.add_child(cont)
	var retry := UIKit.btn("Recomeçar a fase", UIKit.BLUE, 22, Vector2(340, 70))
	retry.pressed.connect(func():
		clear_ckpt()
		get_tree().reload_current_scene())
	h.add_child(retry)
	var menu := UIKit.btn("Menu", UIKit.PURPLE, 24, Vector2(340, 76))
	menu.pressed.connect(_to_menu)
	h.add_child(menu)

func _finish() -> void:
	GameData.log_line("fase %d concluida" % level)
	clear_ckpt()
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
	# DEPOIS com o mesmo enquadramento do antes
	var fr := _frame_all()
	_move_cam(_cam_pos_for(fr[0], fr[1]), fr[0], 0.9)
	await get_tree().create_timer(1.3).timeout
	hud.visible = false
	var after := await _capture()
	hud.visible = true
	var stars := 3
	if max_pain >= 70.0 or mistakes > 3:
		stars = 1
	elif max_pain >= 40.0 or mistakes > 0:
		stars = 2
	var base := 40 + 8 * level
	var reward := maxi(10, int(base * [0.6, 0.8, 1.0][stars - 1]) + earned)
	if data["extreme"]:
		reward = reward * 3 + 150
	GameData.complete_level(level, stars, reward)
	_show_result(after, stars, reward)

func _show_result(after: Image, stars: int, reward: int) -> void:
	modal_open = true
	for c in hud_root.get_children():
		c.visible = false
	var m := UIKit.modal(hud_root)
	var vb: VBoxContainer = m[1]
	if data["extreme"]:
		vb.add_child(UIKit.label("CHEFE DERROTADO!", 40, UIKit.RED))
	vb.add_child(UIKit.label("ANTES  E  DEPOIS", 44, UIKit.PINK))
	var ba := BeforeAfter.new(before_img, after)
	ba.custom_minimum_size = Vector2(600, 520)
	var bac := CenterContainer.new()
	bac.add_child(ba)
	vb.add_child(bac)
	ba.intro()
	vb.add_child(UIKit.label("arraste para comparar", 20, UIKit.DARK.lightened(0.3), 0))
	var st := UIKit.StarRow.new()
	st.custom_minimum_size = Vector2(260, 70)
	var sc := CenterContainer.new()
	sc.add_child(st)
	vb.add_child(sc)
	var quote := UIKit.label("\"%s\" - %s" % [tr(Defs.THANKS.pick_random()), tr(data["look"]["name"])], 24, UIKit.DARK, 0)
	quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quote.custom_minimum_size.x = 560
	vb.add_child(quote)
	var coins_row := UIKit.hbox(8)
	var ic := UIKit.CoinIcon.new()
	ic.custom_minimum_size = Vector2(46, 46)
	coins_row.add_child(ic)
	var coin_lbl := UIKit.label("+%d" % reward, 44, Color("ffc43d"))
	coins_row.add_child(coin_lbl)
	vb.add_child(coins_row)
	vb.add_child(UIKit.label(tr("dor máxima: %d%%") % int(max_pain), 22, UIKit.RED if max_pain > 40 else UIKit.GREEN.darkened(0.3), 0))
	var nxt := UIKit.btn("Próximo paciente", UIKit.GREEN, 30, Vector2(460, 84))
	nxt.pressed.connect(_next)
	var nc := CenterContainer.new()
	nc.add_child(nxt)
	vb.add_child(nc)
	var btns := UIKit.hbox(16)
	vb.add_child(btns)
	var dbl := UIKit.btn("x2 Moedas (AD)", UIKit.YELLOW, 26, Vector2(250, 76))
	dbl.pressed.connect(func(): Ads.show_rewarded(func():
		GameData.add_coins(reward)
		coin_lbl.text = "+%d" % (reward * 2)
		dbl.disabled = true
		Sfx.play("coin")))
	btns.add_child(dbl)
	var share := UIKit.btn("Compartilhar", UIKit.PINK, 26, Vector2(230, 76))
	share.pressed.connect(func(): _share(after, stars))
	btns.add_child(share)
	var menu := UIKit.btn("Menu", UIKit.PURPLE, 26, Vector2(160, 76))
	menu.pressed.connect(_to_menu)
	btns.add_child(menu)

	for i in stars:
		await get_tree().create_timer(0.35).timeout
		st.filled = i + 1
		Sfx.play("star", 0.0)

## Monta uma imagem bonita do antes/depois, salva na galeria e abre para compartilhar
func _share(after: Image, stars: int) -> void:
	if before_img == null or after == null:
		_toast("Sem imagem para compartilhar", UIKit.YELLOW, 30, 1.0)
		return
	var vp := SubViewport.new()
	vp.size = Vector2i(720, 960)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	var root := Control.new()
	root.size = Vector2(720, 960)
	root.theme = get_tree().root.theme
	vp.add_child(root)
	var bg := ColorRect.new()
	bg.color = Color("2a1840")
	bg.size = root.size
	root.add_child(bg)
	var logo := TextureRect.new()
	logo.texture = load("res://assets/ui/logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.position = Vector2(110, 10)
	logo.size = Vector2(500, 150)
	root.add_child(logo)
	var ba := BeforeAfter.new(before_img, after)
	ba.position = Vector2(30, 170)
	ba.size = Vector2(660, 660)
	ba.set_process(false)
	root.add_child(ba)
	var cap := UIKit.label(tr("Fase %d  -  %s  %s") % [level, tr(data["look"]["name"]), "★".repeat(stars)], 34, Color.WHITE, 6)
	cap.position = Vector2(0, 850)
	cap.size = Vector2(720, 80)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(cap)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	# janela de compartilhar do Android (plugin); sem plugin, salva na galeria
	var share_path := ProjectSettings.globalize_path("user://compartilhar.png")
	img.save_png(share_path)
	if Engine.has_singleton("GGNative"):
		if Engine.get_singleton("GGNative").share_image(share_path, tr("Olha o antes e depois no Gross to Glow!")):
			return
	var dir := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	var path := ""
	if dir != "":
		dir += "/GrossToGlow"
		if DirAccess.make_dir_recursive_absolute(dir) == OK or DirAccess.dir_exists_absolute(dir):
			path = dir + "/paciente_%d_%d.png" % [level, Time.get_unix_time_from_system()]
			if img.save_png(path) != OK:
				path = ""
	if path == "":
		path = share_path
	var opened := OS.shell_open(path) == OK
	_toast(tr("Foto salva na galeria (GrossToGlow)!") + ("" if opened else "\n" + tr("Abra a galeria para enviar")), UIKit.GREEN, 30, 2.2)

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
	bp.position = Vector2(12, 196)
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
	coins.offset_left = -190
	coins.offset_right = -12
	coins.offset_top = 14

	var top := VBoxContainer.new()
	top.anchor_left = 0.5
	top.anchor_right = 0.5
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.offset_left = -205
	top.offset_right = 150
	top.offset_top = 10
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 4)
	hud_root.add_child(top)
	var head: String = tr("Fase %d  -  %s  (%s)") % [level, tr(data["look"]["name"]), tr(Defs.PART_NAMES[data["part"]])]
	if data["extreme"]:
		head = tr("CHEFE! ") + head
	var hl := UIKit.label(head, 21, UIKit.RED.lightened(0.5) if data["extreme"] else Color.WHITE, 6)
	hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(hl)
	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size = Vector2(340, 20)
	progress_bar.show_percentage = false
	progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_bar.add_theme_stylebox_override("background", UIKit.style(Color(0.15, 0.1, 0.25, 0.6), 11))
	progress_bar.add_theme_stylebox_override("fill", UIKit.style(UIKit.BLUE, 11))
	top.add_child(progress_bar)
	lbl_problem = UIKit.label("", 24, Color("fff3b0"), 7)
	lbl_problem.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(lbl_problem)
	lbl_hint = UIKit.label("", 19, Color.WHITE, 6)
	lbl_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	hint.visible = false
	var zoom := UIKit.btn("Zoom", UIKit.BLUE, 22, Vector2(140, 62))
	zoom.pressed.connect(func():
		if not input_ok:
			return
		if wide:
			_focus_on(_next_problem(cam_look))
		else:
			_go_wide())
	zoom.visible = false

	guide = GuideArrow.new()
	hud_root.add_child(guide)
	hud_root.move_child(guide, 0)
	use_btn = UseButton.new()
	hud_root.add_child(use_btn)
	coach = TwoFingerCoach.new()
	hud_root.add_child(coach)

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
	tool_bar = GridContainer.new()
	tool_bar.columns = 7
	tool_bar.add_theme_constant_override("h_separation", 4)
	tool_bar.add_theme_constant_override("v_separation", 4)
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
		b.custom_minimum_size = Vector2(92, 98)
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
	if not tool_buttons.has(id):
		return
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
	return true

func _hints_old() -> bool:
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
		lbl_problem.text = "Escolha uma ferramenta e mire num problema"
		lbl_hint.text = ""
		return
	if p == null:
		lbl_problem.text = ""
		lbl_hint.text = ""
		return
	var cnt := Defs.stage_count(p.id)
	lbl_problem.text = tr(p.pname()) + ("   " + tr("(etapa %d/%d)") % [p.stage + 1, cnt] if cnt > 1 else "")
	if _dirt_mult(p) < 1.0:
		lbl_hint.text = "Tá sujo em volta: limpe com o Pano primeiro!"
	elif _hints_on():
		var mh: String = p.cream_hint() if p.tool() == "pomada" else Defs.MECH_HINT[p.mech()]
		lbl_hint.text = tr("Use: %s  -  %s (segure o botão verde)") % [tr(Defs.TOOLS[p.tool()]["name"]), tr(mh)]
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

var toasts: Array = []

func _toast(text: String, color := Color.WHITE, size := 40, dur := 1.0) -> void:
	# empurra os avisos anteriores para cima para não sobrepor
	toasts = toasts.filter(func(o): return is_instance_valid(o))
	for o in toasts:
		var up := 58.0 if o.get_line_count() <= 1 else 100.0
		o.create_tween().tween_property(o, "position:y", o.position.y - up, 0.15)
	var l := UIKit.label(text, mini(size, 36), color, 10)
	toasts.append(l)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.anchor_left = 0.0
	l.anchor_right = 1.0
	l.anchor_top = 0.5
	l.anchor_bottom = 0.5
	l.offset_left = 30
	l.offset_right = -30
	l.offset_top = 110
	l.offset_bottom = 230
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
	# opções sempre à mão: vibração, sons e música
	var vib := UIKit.btn("", UIKit.PINK, 26, Vector2(300, 66))
	var upd_vib := func(): vib.text = tr("Vibração: LIGADA") if GameData.vibrate_on else tr("Vibração: DESLIGADA")
	upd_vib.call()
	vib.pressed.connect(func():
		GameData.vibrate_on = not GameData.vibrate_on
		GameData.save_game()
		upd_vib.call()
		GameData.vibrate(120, -1.0))
	vb.add_child(vib)

	var snd := UIKit.btn("", UIKit.YELLOW, 26, Vector2(300, 66))
	var upd_snd := func(): snd.text = tr("Sons: LIGADOS") if GameData.sound_on else tr("Sons: DESLIGADOS")
	upd_snd.call()
	snd.pressed.connect(func():
		GameData.sound_on = not GameData.sound_on
		GameData.save_game()
		upd_snd.call())
	vb.add_child(snd)
	var mus := UIKit.btn("", UIKit.BLUE, 26, Vector2(300, 66))
	var upd_mus := func(): mus.text = tr("Música: LIGADA") if GameData.music_on else tr("Música: DESLIGADA")
	upd_mus.call()
	mus.pressed.connect(func():
		Sfx.set_music_enabled(not GameData.music_on)
		GameData.save_game()
		upd_mus.call())
	vb.add_child(mus)
	var rst := UIKit.btn("Reiniciar", UIKit.BLUE, 30, Vector2(300, 78))
	rst.pressed.connect(func():
		clear_ckpt()
		get_tree().reload_current_scene())
	vb.add_child(rst)
	var menu := UIKit.btn("Menu", UIKit.PURPLE, 30, Vector2(300, 78))
	menu.pressed.connect(_to_menu)
	vb.add_child(menu)
