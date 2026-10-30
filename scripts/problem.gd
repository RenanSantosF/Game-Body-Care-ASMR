class_name Problem
extends Node3D
## Um problema na pele: monta o visual e reage às etapas de tratamento.

signal stage_done(p: Problem, finished: bool)
signal popped(p: Problem, color: Color)

const INFLAM := Color("e2636a")
const PUS := Color("f2cf4a")
const PUS_W := Color("fff1a8")
const BLOOD := Color("9e1b22")
const DIRT := Color("6b4a2b")
const MUD := Color("4a3220")
const ICE := Color("bfe6ff")
const BAND := Color("e9c49a")
const MAGGOT := Color("f1e9d2")

var id := ""
var def := {}
var stage := 0
var progress := 0.0
var size := 0.12
var done := false
var skin := Color.WHITE
var curv := 1.0
var speed := 1.0
var parts := {}
var items: Array = []
var items_left := 0
var t := 0.0
var rng := RandomNumberGenerator.new()
var _base_scale := {}

func setup(p_id: String, p_rng: RandomNumberGenerator, p_skin: Color, p_curv: float) -> void:
	id = p_id
	def = Defs.PROBLEMS[id]
	size = def["size"]
	skin = p_skin
	curv = p_curv
	rng.seed = p_rng.randi()
	rotate_object_local(Vector3.UP, rng.randf() * TAU)
	call("_build_" + id)
	for k in parts:
		if parts[k] is Node3D:
			_base_scale[k] = parts[k].scale

func pname() -> String:
	return def["name"]

func tool() -> String:
	return "" if done else def["stages"][stage][0]

func mech() -> int:
	return -1 if done else def["stages"][stage][1]

func amount() -> float:
	return def["stages"][stage][2]

func is_cluster_stage() -> bool:
	return mech() == Defs.Mech.SWEEP or mech() == Defs.Mech.PICK

## Cor das partículas ao esfregar/raspar
func fx_color() -> Color:
	match id:
		"sujeira", "lama": return DIRT
		"chiclete": return Color("ff7eb6")
		"crosta": return Color("7a2e1f")
		"verruga": return Color("d8cbb4")
		"cravo", "cravos": return PUS_W
		"pelos": return Color("2b1d14")
	return Color(1, 1, 1)

## Cor do "jorro" ao segurar (HOLD). Alfa 0 = nada.
func hold_color() -> Color:
	if def["stages"][stage][0] == "spray":
		return ICE
	match id:
		"espinha": return Color(0, 0, 0, 0) if progress < 0.75 else PUS_W
		"capa_pus": return PUS
		"furunculo": return PUS if rng.randf() < 0.75 else BLOOD
		"berne": return PUS_W
	return Color(0, 0, 0, 0)

# ------------------------------------------------------------- entrada

func add_progress(px: float) -> void:
	if done:
		return
	progress += px * speed / amount()
	_visual()
	if progress >= 1.0:
		_complete_stage()

func tap() -> void:
	if mech() == Defs.Mech.TAP:
		progress = 1.0
		_complete_stage()

## Remove itens perto do dedo (SWEEP). Retorna quantos removeu.
func sweep(screen_pos: Vector2, radius_px: float, cam: Camera3D) -> int:
	var n := 0
	for it in items:
		if it.get_meta("alive", false):
			var sp := cam.unproject_position(it.global_position)
			if sp.distance_to(screen_pos) < radius_px:
				_remove_item(it)
				n += 1
	if n > 0:
		_after_items()
	return n

## Pega o item mais próximo do toque (PICK).
func pick(screen_pos: Vector2, radius_px: float, cam: Camera3D) -> bool:
	var best: Node3D = null
	var bd := radius_px
	for it in items:
		if it.get_meta("alive", false):
			var d := cam.unproject_position(it.global_position).distance_to(screen_pos)
			if d < bd:
				bd = d
				best = it
	if best:
		_remove_item(best)
		_after_items()
		return true
	return false

func _after_items() -> void:
	progress = 1.0 - float(items_left) / maxf(1.0, items.size())
	_visual()
	if items_left <= 0:
		_complete_stage()

func _remove_item(it: Node3D) -> void:
	it.set_meta("alive", false)
	items_left -= 1
	var tw := create_tween().set_parallel()
	var up := global_basis.y * 0.12
	match id:
		"pelos":
			tw.tween_property(it, "global_position", it.global_position + Vector3(rng.randf_range(-0.1, 0.1), -0.25, 0.1), 0.45).set_ease(Tween.EASE_IN)
			tw.tween_property(it, "scale", Vector3.ZERO, 0.45)
			Sfx.play_throttled("cut", 0.05)
		"espinhas":
			popped.emit(self, PUS_W)
			LP.burst(self, it.global_position, PUS_W, 8, 0.8, 0.012, global_basis.y, 35.0)
			var splat := LP.disc(self, 0.035, Color(PUS, 0.9), 0.006)
			splat.position = it.position + Vector3(0, 0.003, 0)
			parts["splats"].append(splat)
			tw.tween_property(it, "scale", Vector3.ZERO, 0.12)
			Sfx.play("pop", 0.25)
		_:
			tw.tween_property(it, "global_position", it.global_position + up + Vector3(rng.randf_range(-0.15, 0.15), 0.1, 0.1), 0.35)
			tw.tween_property(it, "scale", Vector3.ZERO, 0.35).set_delay(0.1)
			Sfx.play("squish" if id == "larvas" else "pop", 0.25)
			if id == "cravos":
				LP.burst(self, it.global_position, PUS_W, 4, 0.5, 0.01, global_basis.y, 30.0)
	GameData.vibrate(15)

func _complete_stage() -> void:
	progress = 1.0
	_visual()
	_on_stage_end(stage)
	stage += 1
	progress = 0.0
	if stage >= def["stages"].size():
		done = true
		_on_done()
	else:
		_visual()
	stage_done.emit(self, done)

# ------------------------------------------------------------- animação

func _process(delta: float) -> void:
	t += delta
	match id:
		"verme":
			_worm_pose(parts.get("out", 0.0))
		"larvas":
			for it in items:
				if it.get_meta("alive", false):
					var ph: float = it.get_meta("ph")
					it.rotation.y = ph + sin(t * 6.0 + ph) * 0.6
					it.scale = Vector3.ONE * (1.0 + sin(t * 9.0 + ph) * 0.12)
		"pulgas":
			for it in items:
				if it.get_meta("alive", false):
					var ph: float = it.get_meta("ph")
					var hop := maxf(0.0, sin(t * 5.0 + ph))
					it.position.y = it.get_meta("y") + hop * hop * 0.05
		"carrapato":
			if parts.has("legs"):
				for i in parts["legs"].size():
					parts["legs"][i].rotation.x = sin(t * (8.0 if stage == 0 and progress > 0 else 2.5) + i) * 0.25
		"sanguessuga":
			if stage == 0:
				var pulse := 1.0 + sin(t * 3.0) * 0.08
				parts["leech"].scale = Vector3(1, pulse, pulse)
		"berne":
			if parts.has("larva") and parts["larva"].visible:
				parts["larva"].rotation.z = sin(t * 7.0) * 0.15

# ------------------------------------------------------------- helpers

func _ellipse_y(p: Vector3) -> float:
	# afunda itens afastados do centro para acompanhar a curvatura
	return -(p.x * p.x + p.z * p.z) / (2.0 * curv)

func _rand_in_disc(r: float) -> Vector3:
	var a := rng.randf() * TAU
	var d := sqrt(rng.randf()) * r
	var p := Vector3(cos(a) * d, 0, sin(a) * d)
	p.y = _ellipse_y(p)
	return p

func _red(r: float, strength := 0.7) -> MeshInstance3D:
	var c := skin.lerp(INFLAM, 0.75)
	c.a = strength
	var d := LP.disc(self, r, c, 0.002)
	parts["red"] = d
	return d

func _fade(mi: Node3D, dur := 0.4, free_after := false) -> void:
	if mi == null or not is_instance_valid(mi):
		return
	var tw := create_tween()
	if mi is MeshInstance3D and (mi as MeshInstance3D).material_override:
		# duplica para não apagar outros objetos que dividem o mesmo material
		var m: StandardMaterial3D = (mi as MeshInstance3D).material_override.duplicate()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		(mi as MeshInstance3D).material_override = m
		var c := m.albedo_color
		c.a = 0.0
		tw.tween_property(m, "albedo_color", c, dur)
	else:
		tw.tween_property(mi, "scale", Vector3.ZERO, dur)
	if free_after:
		tw.tween_callback(mi.queue_free)

func _fly_off(n: Node3D, extra := Vector3.ZERO) -> void:
	var tw := create_tween().set_parallel()
	var target := n.global_position + global_basis.y * 0.5 + extra + Vector3(rng.randf_range(-0.2, 0.2), 0.3, 0.2)
	tw.tween_property(n, "global_position", target, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(n, "scale", Vector3.ZERO, 0.35).set_delay(0.25)
	tw.chain().tween_callback(n.hide)

func _bandage() -> void:
	var b := Node3D.new()
	add_child(b)
	b.position = Vector3(0, 0.01, 0)
	LP.box(b, Vector3(size * 2.2, 0.012, size * 1.2), BAND)
	LP.box(b, Vector3(size * 0.9, 0.016, size * 0.9), Color("fbf3e6"))
	for i in 6:
		LP.box(b, Vector3(0.008, 0.018, 0.008), BAND.darkened(0.15), Vector3((i % 3 - 1) * size * 0.7, 0.0, (int(i / 3) - 0.5) * size * 0.7))
	b.scale = Vector3.ZERO
	var tw := create_tween()
	tw.tween_property(b, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.play("tap")

func _shake(n: Node3D, amt: float) -> void:
	n.position.x = rng.randf_range(-amt, amt)
	n.position.z = rng.randf_range(-amt, amt)

func _sc(key: String, f: float) -> void:
	if parts.has(key) and is_instance_valid(parts[key]):
		parts[key].scale = _base_scale.get(key, Vector3.ONE) * f

func _splat(key: String, r: float, c: Color, y := 0.006) -> void:
	var d := LP.disc(self, r, c, y)
	d.scale = Vector3(0.001, 1, 0.001)
	parts[key] = d
	_base_scale[key] = Vector3(r, 0.004, r)
	var tw := create_tween()
	tw.tween_property(d, "scale", Vector3(r, 0.004, r), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _cleanup_alpha(key: String, base_a: float) -> void:
	if parts.has(key) and is_instance_valid(parts[key]):
		LP.set_alpha(parts[key], base_a * (1.0 - progress))

# ===================================================================
# Construção de cada tipo
# ===================================================================

func _build_espinha() -> void:
	_red(0.1)
	parts["bump"] = LP.sphere(self, Vector3(0.065, 0.045, 0.065), skin.lerp(INFLAM, 0.85), Vector3(0, 0.0, 0), false, true)
	parts["tip"] = LP.sphere(self, Vector3(0.028, 0.02, 0.028), PUS_W, Vector3(0, 0.04, 0), false, true)

func _build_capa_pus() -> void:
	_red(0.14, 0.85)
	parts["dome"] = LP.sphere(self, Vector3(0.1, 0.075, 0.1), PUS, Vector3(0, 0.005, 0), false, true)
	parts["shine"] = LP.sphere(self, Vector3(0.025, 0.012, 0.018), Color(1, 1, 1, 0.8), Vector3(-0.03, 0.07, -0.03), false, true)
	var cut := LP.box(self, Vector3(0.17, 0.008, 0.012), Color("5a1010"), Vector3(0, 0.078, 0))
	cut.visible = false
	parts["cut"] = cut

func _build_furunculo() -> void:
	_red(0.22, 0.85)
	parts["dome"] = LP.sphere(self, Vector3(0.17, 0.12, 0.17), Color("b8384f"), Vector3(0, 0, 0), false, true)
	parts["core"] = LP.sphere(self, Vector3(0.065, 0.04, 0.065), PUS, Vector3(0, 0.105, 0), false, true)
	for i in 5:
		var a := i * TAU / 5.0
		var v := LP.box(self, Vector3(0.09, 0.004, 0.008), Color("7a1830"), Vector3(cos(a) * 0.16, 0.0, sin(a) * 0.16))
		v.rotation.y = -a
	var cut := LP.box(self, Vector3(0.22, 0.01, 0.014), Color("4a0c0c"), Vector3(0, 0.125, 0))
	cut.visible = false
	parts["cut"] = cut

func _build_cravo() -> void:
	parts["pore"] = LP.sphere(self, Vector3(0.04, 0.012, 0.04), skin.darkened(0.15), Vector3.ZERO, false, false, "sphere_lo")
	var plug := Node3D.new()
	add_child(plug)
	parts["plug"] = plug
	LP.cyl(plug, 0.016, 0.05, Color("f0e2a0"), Vector3(0, -0.015, 0))
	LP.cyl(plug, 0.019, 0.012, Color("1e140d"), Vector3(0, 0.012, 0))

func _build_cravos() -> void:
	var oil := LP.disc(self, 0.24, Color(1.0, 0.95, 0.6, 0.18), 0.003)
	parts["oil"] = oil
	var n := rng.randi_range(16, 24)
	for i in n:
		var it := Node3D.new()
		add_child(it)
		it.position = _rand_in_disc(0.2)
		LP.cyl(it, 0.012, 0.03, Color("f0e2a0"), Vector3(0, -0.005, 0))
		LP.cyl(it, 0.014, 0.012, Color("1e140d"), Vector3(0, 0.012, 0))
		it.set_meta("alive", true)
		items.append(it)
	items_left = items.size()

func _build_espinhas() -> void:
	_red(0.24, 0.55)
	parts["splats"] = []
	var n := rng.randi_range(8, 13)
	for i in n:
		var it := Node3D.new()
		add_child(it)
		it.position = _rand_in_disc(0.2)
		var s := rng.randf_range(0.7, 1.3)
		LP.sphere(it, Vector3(0.032, 0.022, 0.032) * s, skin.lerp(INFLAM, 0.8), Vector3.ZERO, false, true)
		LP.sphere(it, Vector3(0.015, 0.012, 0.015) * s, PUS_W, Vector3(0, 0.02 * s, 0), false, true)
		it.set_meta("alive", true)
		items.append(it)
	items_left = items.size()

func _build_sujeira() -> void:
	parts["stains"] = []
	for i in rng.randi_range(4, 6):
		var c := DIRT.lerp(Color("3d2a18"), rng.randf())
		c.a = 0.85
		var d := LP.disc(self, rng.randf_range(0.05, 0.1), c, 0.003 + i * 0.0015)
		d.position += _rand_in_disc(0.08)
		parts["stains"].append(d)
	parts["specks"] = []
	for i in 7:
		var s := LP.sphere(self, Vector3.ONE * rng.randf_range(0.008, 0.016), Color("2e1f12"), _rand_in_disc(0.13), false, false, "sphere_lo")
		parts["specks"].append(s)

func _build_lama() -> void:
	parts["stains"] = []
	for i in 3:
		var c := Color("5b4026")
		c.a = 0.8
		var d := LP.disc(self, rng.randf_range(0.09, 0.14), c, 0.003 + i * 0.0015)
		d.position += _rand_in_disc(0.05)
		parts["stains"].append(d)
	parts["lumps"] = []
	for i in rng.randi_range(6, 8):
		var r := rng.randf_range(0.035, 0.07)
		var c := MUD.lerp(Color("4f5a2a"), rng.randf() * 0.5)
		var l := LP.sphere(self, Vector3(r, r * 0.5, r), c, _rand_in_disc(0.12), false, true, "sphere_lo")
		parts["lumps"].append(l)
		l.set_meta("base", l.scale)
		l.set_meta("th", rng.randf())

func _build_farpa() -> void:
	_red(0.05, 0.6)
	var pivot := Node3D.new()
	add_child(pivot)
	pivot.rotation.z = deg_to_rad(55)
	parts["pivot"] = pivot
	var sp := LP.box(pivot, Vector3(0.026, 0.22, 0.02), Color("8b5a2b"), Vector3(0, 0.0, 0))
	LP.box(sp, Vector3(0.6, 0.3, 1.1), Color("6b3f1a"), Vector3(0.2, 0.3, 0))
	parts["splinter"] = sp

func _build_pelo_encravado() -> void:
	_red(0.08, 0.6)
	parts["bump"] = LP.sphere(self, Vector3(0.05, 0.025, 0.05), skin.lerp(INFLAM, 0.7), Vector3.ZERO, false, true)
	parts["arc"] = []
	for i in 5:
		var a := -0.9 + i * 0.45
		var seg := LP.box(self, Vector3(0.022, 0.006, 0.006), Color("2b1d14"), Vector3(cos(a) * 0.035, 0.022, sin(a) * 0.035))
		seg.rotation.y = -a - PI / 2
		parts["arc"].append(seg)
	var hair := Node3D.new()
	add_child(hair)
	hair.rotation.z = 0.4
	LP.cyl(hair, 0.005, 1.0, Color("2b1d14"), Vector3(0, 0.5, 0))
	hair.scale = Vector3(1, 0.001, 1)
	parts["hair"] = hair

func _build_pelos() -> void:
	var cols := [Color("1a1a1a"), Color("2b1d14"), Color("5a3a22"), Color("c94f2e"), Color("d9d4c7"), Color("e3c27a")]
	var n := rng.randi_range(32, 46)
	for i in n:
		var it := Node3D.new()
		add_child(it)
		it.position = _rand_in_disc(0.22)
		it.rotation = Vector3(rng.randf_range(-0.9, 0.9), rng.randf() * TAU, rng.randf_range(-0.9, 0.9))
		var L := rng.randf_range(0.07, 0.3)
		var col: Color = cols[rng.randi() % cols.size()]
		var w := rng.randf_range(0.004, 0.008)
		LP.cyl(it, w, L, col, Vector3(0, L * 0.5, 0))
		if rng.randf() < 0.3:  # pelo enrolado
			var c2 := Node3D.new()
			it.add_child(c2)
			c2.position = Vector3(0, L, 0)
			c2.rotation.z = rng.randf_range(1.0, 2.2)
			LP.cyl(c2, w, L * 0.5, col, Vector3(0, L * 0.25, 0))
		it.set_meta("alive", true)
		items.append(it)
	items_left = items.size()

func _build_verme() -> void:
	_red(0.07, 0.7)
	LP.disc(self, 0.035, Color("3a0a0a"), 0.004)
	var worm := Node3D.new()
	add_child(worm)
	parts["worm"] = worm
	parts["segs"] = []
	for i in 12:
		var c := Color("d9a08f") if i % 2 == 0 else Color("c88a7a")
		var r := 0.022 if i > 0 else 0.019
		parts["segs"].append(LP.sphere(worm, Vector3(r, r, r), c, Vector3.ZERO, false, true, "sphere_lo"))
	parts["out"] = 0.0
	_worm_pose(0.0)

func _worm_pose(out: float) -> void:
	var segs: Array = parts["segs"]
	var spacing := 0.028
	var visible_len := 0.07 + out * 0.26
	var n := segs.size()
	var wig := 0.6 + out * 1.5
	for i in n:
		var s := visible_len - i * spacing  # 0 = boca do buraco
		var seg: Node3D = segs[i]
		if s < 0.0:
			seg.visible = false
			continue
		seg.visible = true
		var x := sin(s * 25.0 + t * 6.0) * 0.012 * wig * (s / 0.1)
		var bend := s * s * 2.5
		seg.position = Vector3(x + bend, s * 0.9, 0)

func _build_berne() -> void:
	_red(0.13, 0.8)
	parts["bump"] = LP.sphere(self, Vector3(0.11, 0.07, 0.11), skin.lerp(INFLAM, 0.6), Vector3.ZERO, false, true)
	LP.disc(self, 0.018, Color("2a0808"), 0.071)
	var larva := Node3D.new()
	add_child(larva)
	larva.position = Vector3(0, 0.03, 0)
	parts["larva"] = larva
	for i in 5:
		var r := 0.03 - i * 0.004
		var c := MAGGOT if i % 2 == 0 else Color("d8c7a5")
		LP.sphere(larva, Vector3(r, r * 0.9, r), c, Vector3(0, -i * 0.035, 0), false, true, "sphere_lo")
		for k in 4:
			var a := k * TAU / 4.0
			LP.sphere(larva, Vector3.ONE * 0.004, Color("3a2a1a"), Vector3(cos(a) * r, -i * 0.035, sin(a) * r), false, false, "sphere_lo")
	larva.scale = Vector3.ONE

func _build_carrapato() -> void:
	_red(0.08, 0.6)
	var tick := Node3D.new()
	add_child(tick)
	parts["tick"] = tick
	LP.sphere(tick, Vector3(0.06, 0.045, 0.08), Color("7d6b6b"), Vector3(0, 0.03, -0.02), false, true)
	LP.sphere(tick, Vector3(0.035, 0.02, 0.03), Color("3b2a22"), Vector3(0, 0.035, 0.04), false, true)
	LP.sphere(tick, Vector3(0.015, 0.012, 0.02), Color("5a1f14"), Vector3(0, 0.02, 0.075), false, false, "sphere_lo")
	parts["legs"] = []
	for side in [-1.0, 1.0]:
		for i in 4:
			var pv := Node3D.new()
			tick.add_child(pv)
			pv.position = Vector3(side * 0.03, 0.03, 0.04 - i * 0.018)
			pv.rotation.y = side * (0.4 + i * 0.35) + (PI / 2 if side > 0 else -PI / 2)
			var leg := LP.box(pv, Vector3(0.06, 0.006, 0.006), Color("2a1d14"), Vector3(0.03, -0.01, 0))
			leg.rotation.z = -0.4
			parts["legs"].append(pv)

func _build_verruga() -> void:
	parts["base"] = LP.disc(self, 0.07, Color(skin.darkened(0.2), 0.8), 0.003)
	parts["bits"] = []
	for i in 10:
		var p := _rand_in_disc(0.045)
		p.y += 0.01 + rng.randf() * 0.02
		var r := rng.randf_range(0.022, 0.035)
		var b := LP.sphere(self, Vector3(r, r, r), Color("b8a58a").lerp(Color("8d7a60"), rng.randf()), p, true, false, "sphere_lo")
		b.set_meta("base", b.scale)
		b.set_meta("th", rng.randf())
		b.set_meta("col", LP.get_color(b))
		parts["bits"].append(b)

func _build_sanguessuga() -> void:
	_red(0.08, 0.7)
	var leech := Node3D.new()
	add_child(leech)
	parts["leech"] = leech
	parts["segs"] = []
	for i in 7:
		var k := float(i) / 6.0
		var r := 0.028 + sin(k * PI) * 0.018
		var s := LP.sphere(leech, Vector3(r, r * 0.75, r * 1.1), Color("1f2a1c").lerp(Color("3b4a26"), float(i % 2)), Vector3(0, r * 0.6, i * 0.035), true, true, "sphere_lo")
		parts["segs"].append(s)

func _build_pulgas() -> void:
	parts["bites"] = []
	for i in 12:
		var d := LP.disc(self, rng.randf_range(0.01, 0.018), Color(INFLAM, 0.8), 0.003)
		d.position += _rand_in_disc(0.2)
		parts["bites"].append(d)
	for i in rng.randi_range(9, 13):
		var it := Node3D.new()
		add_child(it)
		it.position = _rand_in_disc(0.19)
		it.rotation.y = rng.randf() * TAU
		LP.sphere(it, Vector3(0.014, 0.012, 0.022), Color("5a2e14"), Vector3(0, 0.012, 0), false, true, "sphere_lo")
		LP.box(it, Vector3(0.03, 0.003, 0.004), Color("2a1408"), Vector3(0, 0.004, -0.008))
		it.set_meta("alive", true)
		it.set_meta("ph", rng.randf() * TAU)
		it.set_meta("y", it.position.y)
		items.append(it)
	items_left = items.size()

func _build_larvas() -> void:
	LP.disc(self, 0.22, Color(skin.lerp(INFLAM, 0.85), 0.85), 0.002)
	parts["wound"] = LP.disc(self, 0.17, Color("6e1a1a"), 0.004)
	parts["wound2"] = LP.disc(self, 0.1, Color("4a0e0e"), 0.006)
	parts["splats"] = []
	for i in rng.randi_range(7, 10):
		var it := Node3D.new()
		add_child(it)
		it.position = _rand_in_disc(0.13) + Vector3(0, 0.01, 0)
		for k in 3:
			var r := 0.017 - k * 0.003
			LP.sphere(it, Vector3(r, r * 0.8, r * 1.3), MAGGOT.darkened(k * 0.05), Vector3(0, 0, k * 0.03), false, true, "sphere_lo")
		it.set_meta("alive", true)
		it.set_meta("ph", rng.randf() * TAU)
		items.append(it)
	items_left = items.size()

func _build_crosta() -> void:
	parts["pink"] = LP.disc(self, 0.11, Color(Color("f08a9a"), 0.9), 0.003)
	parts["bits"] = []
	for i in 8:
		var r := rng.randf_range(0.04, 0.065)
		var b := LP.sphere(self, Vector3(r, r * 0.28, r), Color("7a2e1f").lerp(Color("a8743a"), rng.randf() * 0.6), _rand_in_disc(0.06), false, false, "sphere_lo")
		b.set_meta("base", b.scale)
		b.set_meta("th", float(i) / 8.0)
		parts["bits"].append(b)

func _build_chiclete() -> void:
	var blob := Node3D.new()
	add_child(blob)
	parts["blob"] = blob
	for i in 5:
		var r := rng.randf_range(0.04, 0.07)
		LP.sphere(blob, Vector3(r, r * 0.45, r), Color("ff7eb6").lerp(Color("ff5aa0"), rng.randf()), _rand_in_disc(0.05), false, true, "sphere_lo")
	for i in 3:
		var s := LP.cyl(blob, 0.005, 0.12, Color("ffa0cc"), Vector3(0, 0.04, 0))
		s.rotation = Vector3(rng.randf_range(0.6, 1.2), rng.randf() * TAU, 0)

# ===================================================================
# Visual durante o progresso de cada etapa
# ===================================================================

func _visual() -> void:
	var p := clampf(progress, 0.0, 1.0)
	match id:
		"espinha":
			if stage == 0:
				_sc("bump", 1.0 + p * 0.7)
				_sc("tip", 1.0 + p * 1.2)
				parts["tip"].position.y = 0.04 + p * 0.03
				_shake(parts["bump"], p * 0.006)
			else:
				_cleanup_alpha("splat", 0.9)
				_cleanup_alpha("red", 0.7 - 0.0)
		"capa_pus", "furunculo":
			var dome_y := 0.078 if id == "capa_pus" else 0.125
			match stage:
				0:
					parts["cut"].visible = p > 0.02
					parts["cut"].scale.x = (0.17 if id == "capa_pus" else 0.22) * p
					parts["cut"].position.y = dome_y
				1:
					_sc("dome", 1.0 - p * 0.8)
					if parts.has("core"):
						_sc("core", 1.0 - p)
					if parts.has("shine"):
						parts["shine"].visible = false
					parts["cut"].position.y = dome_y * (1.0 - p * 0.8)
					_shake(parts["dome"], 0.004)
				2:
					_cleanup_alpha("splat", 0.95)
					_cleanup_alpha("splat2", 0.9)
		"cravo":
			var plug: Node3D = parts["plug"]
			plug.position.y = p * 0.04
			plug.scale = Vector3(1, 1.0 + p * 1.5, 1)
		"sujeira":
			for d in parts["stains"]:
				LP.set_alpha(d, 0.85 * (1.0 - p))
			for s in parts["specks"]:
				s.scale = Vector3.ONE * 0.012 * (1.0 - p)
		"lama":
			if stage == 0:
				for l in parts["lumps"]:
					var th: float = l.get_meta("th")
					var f := clampf(1.0 - (p - th * 0.6) / 0.4, 0.0, 1.0)
					l.scale = l.get_meta("base") * f
			else:
				for d in parts["stains"]:
					LP.set_alpha(d, 0.8 * (1.0 - p))
		"farpa":
			parts["splinter"].position.y = p * 0.12
		"pelo_encravado":
			if stage == 0:
				var hair: Node3D = parts["hair"]
				hair.scale = Vector3(1, maxf(0.001, p * 0.22), 1)
				for i in parts["arc"].size():
					parts["arc"][i].visible = p < 1.0 - float(i) / 5.0
			else:
				_cleanup_alpha("blood", 0.9)
				_cleanup_alpha("red", 0.6)
		"verme":
			if stage == 0:
				parts["out"] = p
				_worm_pose(p)
			elif stage == 1:
				_cleanup_alpha("splat", 0.9)
		"berne":
			if stage == 0:
				_sc("bump", 1.0 + p * 0.35)
				parts["larva"].position.y = 0.03 + p * 0.05
				_shake(parts["bump"], 0.004)
			elif stage == 1:
				parts["larva"].position.y = 0.08 + p * 0.12
				_sc("bump", 1.35 - p * 0.9)
		"carrapato":
			if stage == 0:
				parts["tick"].position.y = p * 0.035
				parts["tick"].rotation.x = -p * 0.5
			else:
				_cleanup_alpha("blood", 0.9)
		"verruga":
			if stage == 0:
				for b in parts["bits"]:
					LP.set_color(b, (b.get_meta("col") as Color).lerp(ICE, p))
			else:
				for b in parts["bits"]:
					var th: float = b.get_meta("th")
					var f := clampf(1.0 - (p - th * 0.7) / 0.3, 0.0, 1.0)
					b.scale = b.get_meta("base") * f
				LP.set_alpha(parts["base"], 0.8 * (1.0 - p * 0.7))
		"sanguessuga":
			if stage == 0:
				for s in parts["segs"]:
					LP.set_color(s, Color("1f2a1c").lerp(ICE, p * 0.8))
			elif stage == 1:
				parts["leech"].rotation.x = -p * 0.9
				parts["leech"].position.y = p * 0.04
			else:
				_cleanup_alpha("blood", 0.9)
		"larvas":
			if stage == 1:
				LP.set_color(parts["wound"], Color("6e1a1a").lerp(Color("e8909a"), p))
				LP.set_alpha(parts["wound2"], 1.0 - p)
		"espinhas":
			if stage == 1:
				for s in parts["splats"]:
					LP.set_alpha(s, 0.9 * (1.0 - p))
				_cleanup_alpha("red", 0.55)
		"crosta":
			if stage == 0:
				for b in parts["bits"]:
					var th: float = b.get_meta("th")
					var f := clampf(1.0 - (p - th * 0.7) / 0.3, 0.0, 1.0)
					b.scale = b.get_meta("base") * f
			else:
				LP.set_alpha(parts["pink"], 0.9 * (1.0 - p * 0.8))
		"chiclete":
			parts["blob"].scale = Vector3.ONE * (1.0 - p * 0.9)
			parts["blob"].position.y = p * 0.01

# ===================================================================
# Fim de cada etapa (estouros, respingos...)
# ===================================================================

func _on_stage_end(s: int) -> void:
	var up := global_basis.y
	var gp := global_position
	match id:
		"espinha":
			if s == 0:
				parts["bump"].hide()
				parts["tip"].hide()
				LP.burst(get_parent(), gp + up * 0.05, PUS_W, 22, 1.4, 0.016, up, 35.0)
				LP.burst(get_parent(), gp + up * 0.05, PUS, 12, 1.0, 0.012, up, 50.0)
				_splat("splat", 0.09, Color(PUS, 0.9))
				LP.sphere(self, Vector3(0.04, 0.012, 0.04), skin.lerp(INFLAM, 0.6), Vector3.ZERO, false, false, "sphere_lo")
				popped.emit(self, PUS)
				Sfx.play("pop")
		"capa_pus", "furunculo":
			match s:
				0:
					Sfx.play("cut")
					LP.burst(get_parent(), gp + up * 0.08, PUS, 6, 0.6, 0.012, up, 40.0)
				1:
					parts["dome"].hide()
					if parts.has("core"):
						parts["core"].hide()
					parts["cut"].hide()
					LP.burst(get_parent(), gp + up * 0.05, PUS, 30, 1.6, 0.018, up, 45.0)
					_splat("splat", size * 0.85, Color(PUS, 0.95))
					if id == "furunculo":
						LP.burst(get_parent(), gp + up * 0.05, BLOOD, 14, 1.2, 0.014, up, 50.0)
						_splat("splat2", size * 0.45, Color(BLOOD, 0.9), 0.008)
					LP.sphere(self, Vector3(size * 0.35, 0.01, size * 0.35), skin.lerp(INFLAM, 0.7), Vector3.ZERO, false, false, "sphere_lo")
					popped.emit(self, PUS)
					Sfx.play("splat")
				2:
					if id == "furunculo":
						pass
				3:
					_bandage()
		"cravo":
			var plug: Node3D = parts["plug"]
			_fly_off(plug)
			LP.burst(get_parent(), gp + up * 0.04, PUS_W, 8, 0.8, 0.01, up, 30.0)
			popped.emit(self, PUS_W)
			Sfx.play("pop", 0.2)
			_fade(parts["pore"], 0.6)
		"farpa":
			_fly_off(parts["pivot"])
			LP.burst(get_parent(), gp, BLOOD, 6, 0.6, 0.01, up, 40.0)
			Sfx.play("pull")
		"pelo_encravado":
			if s == 0:
				_fly_off(parts["hair"])
				_splat("blood", 0.025, Color(BLOOD, 0.9))
				Sfx.play("pull")
		"verme":
			if s == 0:
				_fly_off(parts["worm"], up * 0.3)
				LP.burst(get_parent(), gp + up * 0.03, BLOOD, 16, 1.2, 0.014, up, 45.0)
				_splat("splat", 0.07, Color(BLOOD, 0.9))
				popped.emit(self, BLOOD)
				Sfx.play("splat")
			elif s == 2:
				_bandage()
		"berne":
			if s == 0:
				Sfx.play("squish")
			elif s == 1:
				_fly_off(parts["larva"], up * 0.2)
				LP.burst(get_parent(), gp + up * 0.05, PUS_W, 18, 1.3, 0.015, up, 40.0)
				popped.emit(self, PUS_W)
				Sfx.play("splat")
			elif s == 2:
				_bandage()
		"carrapato":
			if s == 0:
				_fly_off(parts["tick"])
				_splat("blood", 0.03, Color(BLOOD, 0.9))
				Sfx.play("pull")
		"verruga":
			if s == 0:
				Sfx.play("freeze")
		"sanguessuga":
			if s == 0:
				Sfx.play("freeze")
			elif s == 1:
				_fly_off(parts["leech"], up * 0.2)
				_splat("blood", 0.05, Color(BLOOD, 0.9))
				LP.burst(get_parent(), gp, BLOOD, 10, 1.0, 0.012, up, 50.0)
				popped.emit(self, BLOOD)
				Sfx.play("pull")
		"larvas":
			if s == 2:
				_bandage()
		"chiclete":
			parts["blob"].hide()
			Sfx.play("pop", 0.2)

func _on_done() -> void:
	# cura o vermelhão que sobrou
	if parts.has("red"):
		_fade(parts["red"], 0.8)
	match id:
		"espinha", "capa_pus":
			for c in get_children():
				if c is MeshInstance3D and c.visible and c != parts.get("cut"):
					_fade(c, 0.9)
		"espinhas":
			for c in get_children():
				if c is MeshInstance3D:
					_fade(c, 0.9)
		"cravos":
			_fade(parts["oil"], 0.6)
		"pulgas":
			for b in parts["bites"]:
				_fade(b, 1.0)
		"verruga":
			_fade(parts["base"], 0.8)
		"crosta":
			_fade(parts["pink"], 0.8)
		"pelo_encravado":
			_fade(parts["bump"], 0.8)
		"carrapato", "sanguessuga":
			for c in get_children():
				if c is MeshInstance3D:
					_fade(c, 0.9)
