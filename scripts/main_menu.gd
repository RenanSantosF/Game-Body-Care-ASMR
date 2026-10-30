extends Control
## Menu principal: jogar, fases, loja, bônus diário e moedas grátis.

var bubbles := []
var overlay: Control

func _ready() -> void:
	var bg := TextureRect.new()
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color("ff9ccf"))
	g.set_color(1, Color("7d6bff"))
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0.4, 1)
	bg.texture = gt
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	for i in 18:
		bubbles.append([Vector2(randf(), randf()), randf_range(14, 60), randf_range(0.02, 0.07), randf() * TAU])
	var deco := Control.new()
	deco.set_anchors_preset(Control.PRESET_FULL_RECT)
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deco.draw.connect(func(): _draw_bubbles(deco))
	add_child(deco)
	set_process(true)
	deco.set_meta("is_deco", true)

	# topo: moedas e configurações
	var coins := UIKit.coin_box()
	add_child(coins)
	coins.anchor_left = 1.0
	coins.anchor_right = 1.0
	coins.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	coins.offset_left = -240
	coins.offset_right = -20
	coins.offset_top = 20

	var cfg := UIKit.btn("Opções", UIKit.PURPLE, 24, Vector2(140, 60))
	cfg.position = Vector2(20, 20)
	add_child(cfg)
	cfg.pressed.connect(_settings)

	var center := VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 16)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var logo := TextureRect.new()
	logo.texture = load("res://assets/ui/logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(620, 520)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(logo)
	logo.pivot_offset = Vector2(310, 260)
	var ltw := logo.create_tween().set_loops()
	ltw.tween_property(logo, "scale", Vector2(1.03, 1.03), 1.2).set_trans(Tween.TRANS_SINE)
	ltw.tween_property(logo, "scale", Vector2.ONE, 1.2).set_trans(Tween.TRANS_SINE)
	Sfx.play_music("menu")
	var tag := UIKit.label("Clínica de cuidados nojentos\ne satisfatórios", 28, Color.WHITE, 6)
	center.add_child(tag)
	var sub := UIKit.label("Pacientes atendidos: %d  |  Estrelas: %d" % [GameData.patients_treated, GameData.total_stars()], 22, Color(1, 1, 1, 0.9), 5)
	center.add_child(sub)

	var play_row := UIKit.hbox()
	play_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var play := UIKit.btn("JOGAR  -  Fase %d" % GameData.level, UIKit.GREEN, 44, Vector2(540, 120))
	play.pressed.connect(func(): _start(GameData.level))
	play_row.add_child(play)
	center.add_child(play_row)
	_pulse(play)

	var row := UIKit.hbox(18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lv := UIKit.btn("Fases", UIKit.BLUE, 30, Vector2(200, 80))
	lv.pressed.connect(_levels)
	row.add_child(lv)
	var shop := UIKit.btn("Loja", UIKit.PINK, 30, Vector2(200, 80))
	shop.pressed.connect(_shop)
	row.add_child(shop)
	center.add_child(row)
	var free := UIKit.btn("+60 moedas grátis (AD)", UIKit.YELLOW, 28, Vector2(418, 84))
	free.pressed.connect(func(): Ads.show_rewarded(func():
		GameData.add_coins(60)
		Sfx.play("coin")))
	var fc := CenterContainer.new()
	fc.add_child(free)
	center.add_child(fc)

	if GameData.daily_available():
		await get_tree().create_timer(0.4).timeout
		_daily()

func _process(delta: float) -> void:
	for b in bubbles:
		b[0].y -= b[2] * delta
		b[3] += delta
		if b[0].y < -0.1:
			b[0] = Vector2(randf(), 1.1)
	for c in get_children():
		if c.has_meta("is_deco"):
			c.queue_redraw()

func _draw_bubbles(c: Control) -> void:
	var s := c.size
	for b in bubbles:
		var p := Vector2(b[0].x * s.x + sin(b[3]) * 12.0, b[0].y * s.y)
		c.draw_circle(p, b[1], Color(1, 1, 1, 0.12))
		c.draw_circle(p + Vector2(-b[1] * 0.3, -b[1] * 0.3), b[1] * 0.25, Color(1, 1, 1, 0.25))

func _pulse(b: Control) -> void:
	await get_tree().process_frame
	b.pivot_offset = b.size * 0.5
	var tw := b.create_tween().set_loops()
	tw.tween_property(b, "scale", Vector2(1.05, 1.05), 0.6).set_trans(Tween.TRANS_SINE)
	tw.tween_property(b, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_SINE)

func _start(lvl: int) -> void:
	GameData.current_level = lvl
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _close_overlay() -> void:
	if overlay and is_instance_valid(overlay):
		overlay.queue_free()
	overlay = null

# ----------------------------------------------------------- bônus diário

func _daily() -> void:
	_close_overlay()
	var m := UIKit.modal(self)
	overlay = m[0]
	var vb: VBoxContainer = m[1]
	vb.add_child(UIKit.label("BÔNUS DIÁRIO!", 48, UIKit.YELLOW))
	var next := GameData.streak + 1 if GameData.last_daily == GameData._yesterday() else 1
	vb.add_child(UIKit.label("Dia %d seguido" % next, 30, UIKit.DARK, 0))
	var amount := GameData.daily_reward()
	var row := UIKit.hbox(8)
	var ic := UIKit.CoinIcon.new()
	ic.custom_minimum_size = Vector2(56, 56)
	row.add_child(ic)
	row.add_child(UIKit.label(str(amount), 54, Color("ffe066")))
	vb.add_child(row)
	vb.add_child(UIKit.label("Volte amanhã para ganhar mais!", 22, UIKit.DARK, 0))
	var h := UIKit.hbox()
	var take := UIKit.btn("Pegar", UIKit.BLUE, 30, Vector2(200, 80))
	take.pressed.connect(func():
		GameData.claim_daily(1)
		Sfx.play("coin")
		_close_overlay())
	h.add_child(take)
	var triple := UIKit.btn("x3 com AD", UIKit.GREEN, 30, Vector2(240, 80))
	triple.pressed.connect(func(): Ads.show_rewarded(func():
		GameData.claim_daily(3)
		Sfx.play("success")
		_close_overlay()))
	h.add_child(triple)
	vb.add_child(h)

# ----------------------------------------------------------- fases

func _levels() -> void:
	_close_overlay()
	var m := UIKit.modal(self)
	overlay = m[0]
	var vb: VBoxContainer = m[1]
	vb.add_child(UIKit.label("FASES", 44, UIKit.PINK))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(640, 760)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	var shown := int(ceil((GameData.level + 4) / 5.0)) * 5
	for i in range(1, shown + 1):
		var unlocked := i <= GameData.level
		var col := UIKit.RED if LevelGen.is_extreme(i) else UIKit.BLUE
		var b := UIKit.btn(str(i) if unlocked else "?", col, 34, Vector2(122, 110))
		b.disabled = not unlocked
		if unlocked:
			b.pressed.connect(func(): _start(i))
			var st := UIKit.StarRow.new()
			st.filled = int(GameData.stars.get(str(i), 0))
			st.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
			st.offset_top = -34
			st.offset_bottom = -6
			st.offset_left = 12
			st.offset_right = -12
			b.add_child(st)
		grid.add_child(b)
	vb.add_child(UIKit.label("Vermelhas = CASO EXTREMO\n(moedas em dobro)", 20, UIKit.DARK, 0))
	var close := UIKit.btn("Fechar", UIKit.PURPLE, 28, Vector2(200, 70))
	close.pressed.connect(_close_overlay)
	var cc := CenterContainer.new()
	cc.add_child(close)
	vb.add_child(cc)

# ----------------------------------------------------------- loja

func _shop() -> void:
	_close_overlay()
	var m := UIKit.modal(self)
	overlay = m[0]
	var vb: VBoxContainer = m[1]
	vb.add_child(UIKit.label("LOJA", 48, UIKit.PINK))
	var cbx := CenterContainer.new()
	cbx.add_child(UIKit.coin_box())
	vb.add_child(cbx)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(620, 820)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	var row := GridContainer.new()
	row.columns = 2
	row.add_theme_constant_override("h_separation", 12)
	row.add_theme_constant_override("v_separation", 12)
	scroll.add_child(row)
	for id in Defs.TOOL_ORDER:
		row.add_child(_tool_card(id))
	var close := UIKit.btn("Fechar", UIKit.PURPLE, 28, Vector2(200, 70))
	close.pressed.connect(_close_overlay)
	var cc := CenterContainer.new()
	cc.add_child(close)
	vb.add_child(cc)

func _tool_card(id: String) -> Control:
	var d: Dictionary = Defs.TOOLS[id]
	var card := UIKit.panel(Color.WHITE, 24, 4, Color("d9cff0"))
	card.custom_minimum_size = Vector2(296, 380)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 8)
	card.add_child(vb)
	var icon := ToolIcon.new()
	icon.custom_minimum_size = Vector2(120, 120)
	icon.tool_id = id
	var ic := CenterContainer.new()
	ic.add_child(icon)
	vb.add_child(ic)
	vb.add_child(UIKit.label(d["name"], 28, UIKit.DARK, 0))
	var desc := UIKit.label(d["desc"], 18, Color("6d6680"), 0)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(180, 50)
	vb.add_child(desc)
	var owned := GameData.has_tool(id)
	var lvl := GameData.tool_level(id)
	if owned:
		vb.add_child(UIKit.label("Nível %d/3  (velocidade x%.2f)" % [lvl, GameData.speed_mult(id)], 18, UIKit.GREEN.darkened(0.3), 0))
		if lvl < 3:
			var price := Defs.upgrade_price(id, lvl)
			var b := UIKit.btn("Melhorar %d" % price, UIKit.GREEN, 22, Vector2(190, 64))
			b.disabled = GameData.coins < price
			b.pressed.connect(func():
				if GameData.spend(price):
					GameData.upgrade_tool(id)
					Sfx.play("success")
					_shop())
			vb.add_child(b)
		else:
			vb.add_child(UIKit.label("MÁXIMO!", 24, UIKit.YELLOW))
	else:
		icon.locked = GameData.level < d["unlock"]
		if GameData.level < d["unlock"]:
			vb.add_child(UIKit.label("Libera na fase %d" % d["unlock"], 20, UIKit.RED, 0))
		var b := UIKit.btn("Comprar %d" % d["price"], UIKit.BLUE, 22, Vector2(190, 60))
		b.disabled = GameData.coins < d["price"]
		b.pressed.connect(func():
			if GameData.spend(d["price"]):
				GameData.unlock_tool(id)
				Sfx.play("success")
				_shop())
		vb.add_child(b)
		var ad := UIKit.btn("Grátis (AD)", UIKit.YELLOW, 22, Vector2(190, 60))
		ad.pressed.connect(func(): Ads.show_rewarded(func():
			GameData.unlock_tool(id)
			Sfx.play("success")
			_shop()))
		vb.add_child(ad)
	return card

# ----------------------------------------------------------- opções

func _settings() -> void:
	_close_overlay()
	var m := UIKit.modal(self)
	overlay = m[0]
	var vb: VBoxContainer = m[1]
	vb.add_child(UIKit.label("OPÇÕES", 44, UIKit.PURPLE))
	var mus := UIKit.btn("", UIKit.PINK, 28, Vector2(360, 76))
	var snd := UIKit.btn("", UIKit.BLUE, 28, Vector2(360, 76))
	var vib := UIKit.btn("", UIKit.BLUE, 28, Vector2(360, 76))
	var refresh := func():
		mus.text = "Música: " + ("LIGADA" if GameData.music_on else "DESLIGADA")
		snd.text = "Som: " + ("LIGADO" if GameData.sound_on else "DESLIGADO")
		vib.text = "Vibração: " + ("LIGADA" if GameData.vibrate_on else "DESLIGADA")
	refresh.call()
	snd.pressed.connect(func():
		GameData.sound_on = not GameData.sound_on
		GameData.save_game()
		refresh.call())
	vib.pressed.connect(func():
		GameData.vibrate_on = not GameData.vibrate_on
		GameData.save_game()
		refresh.call())
	mus.pressed.connect(func():
		Sfx.set_music_enabled(not GameData.music_on)
		GameData.save_game()
		refresh.call())
	vb.add_child(mus)
	vb.add_child(snd)
	vb.add_child(vib)
	var close := UIKit.btn("Fechar", UIKit.PURPLE, 28, Vector2(200, 70))
	close.pressed.connect(_close_overlay)
	var cc := CenterContainer.new()
	cc.add_child(close)
	vb.add_child(cc)
