class_name Patient
extends Node3D
## Monta a parte do corpo do paciente (low poly) e fornece pontos de superfície.

var part := "rosto"
var look := {}
var radii := Vector3.ONE        # elipsoide principal (a, b, c)
var u_range := Vector2(-0.7, 0.7)
var v_range := Vector2(-0.6, 0.5)
var exclusions := []            # [[pos, raio], ...]
var skin_mi: MeshInstance3D
var mouth_dots: Array[MeshInstance3D] = []
var brows: Array[Node3D] = []
var cam_center := Vector3.ZERO
var wide_dist := 4.5
var focus_dist := 1.5
var prob_scale := 1.0           # problemas maiores em partes grandes
var mood := 0.0

func build(p_part: String, p_look: Dictionary) -> void:
	part = p_part
	look = p_look
	var skin: Color = look["skin"]
	var hair: Color = look["hair"]
	var shirt: Color = look["shirt"]
	match part:
		"rosto":
			radii = Vector3(1.0, 1.25, 0.95)
			u_range = Vector2(-0.8, 0.8)
			v_range = Vector2(-0.7, 0.52)
			wide_dist = 4.4
			focus_dist = 1.45
			cam_center = Vector3(0, 0.05, 0)
			skin_mi = LP.sphere(self, radii, skin, Vector3.ZERO, false, false, "sphere_hi")
			_face(skin, hair, shirt)
		"braco":
			radii = Vector3(2.4, 0.55, 0.55)
			u_range = Vector2(-1.0, 1.05)
			v_range = Vector2(-0.6, 0.6)
			wide_dist = 6.2
			focus_dist = 1.6
			prob_scale = 1.15
			skin_mi = LP.sphere(self, radii, skin, Vector3.ZERO, false, false, "sphere_hi")
			_arm(skin, shirt)
		"costas":
			radii = Vector3(1.5, 1.9, 0.8)
			u_range = Vector2(-0.7, 0.7)
			v_range = Vector2(-0.6, 0.62)
			wide_dist = 7.6
			focus_dist = 1.5
			prob_scale = 1.5
			cam_center = Vector3(0, 0.55, 0)
			skin_mi = LP.sphere(self, radii, skin, Vector3.ZERO, false, false, "sphere_hi")
			_back(skin, hair, shirt)
		"pe":
			radii = Vector3(0.85, 1.75, 0.5)
			u_range = Vector2(-0.65, 0.65)
			v_range = Vector2(-0.62, 0.5)
			wide_dist = 6.0
			focus_dist = 1.4
			prob_scale = 1.15
			cam_center = Vector3(0, 0.35, 0)
			skin_mi = LP.sphere(self, radii, skin, Vector3.ZERO, false, false, "sphere_hi")
			_foot(skin, shirt)

func curvature() -> float:
	return minf(radii.x, minf(radii.y, radii.z)) * 1.2

## Ponto na superfície do elipsoide. u = longitude (0 = frente), v = latitude.
func surface(u: float, v: float) -> Array:
	var p := Vector3(radii.x * cos(v) * sin(u), radii.y * sin(v), radii.z * cos(v) * cos(u))
	var n := Vector3(p.x / (radii.x * radii.x), p.y / (radii.y * radii.y), p.z / (radii.z * radii.z)).normalized()
	return [p, n]

## Interseção de um raio (coords globais) com o elipsoide. Retorna [] se errar.
func ray_hit(origin: Vector3, dir: Vector3) -> Array:
	var o := to_local(origin)
	var d := (global_basis.inverse() * dir)
	var os := o / radii
	var ds := d / radii
	var a := ds.dot(ds)
	var b := 2.0 * os.dot(ds)
	var c := os.dot(os) - 1.0
	var disc := b * b - 4.0 * a * c
	if disc < 0.0:
		return []
	var t := (-b - sqrt(disc)) / (2.0 * a)
	if t < 0.0:
		return []
	var p := o + d * t
	var n := Vector3(p.x / (radii.x * radii.x), p.y / (radii.y * radii.y), p.z / (radii.z * radii.z)).normalized()
	return [to_global(p), (global_basis * n).normalized()]

## Sorteia posições para os problemas sem sobreposição.
func sample_spots(sizes: Array, rng: RandomNumberGenerator) -> Array:
	var out := []
	for s in sizes:
		var best := []
		var best_score := -INF
		for attempt in 60:
			var u := rng.randf_range(u_range.x, u_range.y)
			var v := rng.randf_range(v_range.x, v_range.y)
			var sp := surface(u, v)
			var pos: Vector3 = sp[0]
			var score := 10.0
			for ex in exclusions:
				var d: float = pos.distance_to(ex[0]) - ex[1] - s
				score = minf(score, d)
			for o in out:
				var d2: float = pos.distance_to(o[0]) - o[2] - s
				score = minf(score, d2)
			# leve preferência pelo centro (melhor para câmera)
			score -= absf(u) * 0.05
			if score > best_score:
				best_score = score
				best = [pos, sp[1], s]
			if score > 0.05 and attempt > 8:
				break
		out.append(best)
	return out

func set_mood(m: float) -> void:
	mood = clampf(m, 0.0, 1.0)
	if mouth_dots.is_empty():
		return
	var n := mouth_dots.size()
	var curve := lerpf(-0.07, 0.11, mood)  # negativo = triste
	for i in n:
		var x := lerpf(-0.24, 0.24, float(i) / (n - 1))
		var k := x / 0.24
		var y := -0.5 + curve * (k * k) - curve * 0.4
		var sp := surface(x / radii.x * 1.05, y / radii.y)
		mouth_dots[i].position = sp[0] + sp[1] * 0.01
	for i in brows.size():
		var side := -1.0 if i == 0 else 1.0
		brows[i].rotation.z = side * lerpf(0.35, -0.12, mood)

func flinch() -> void:
	var tw := create_tween()
	var base := position
	tw.tween_property(self, "position", base + Vector3(randf_range(-0.03, 0.03), 0.02, 0), 0.05)
	tw.tween_property(self, "position", base, 0.08)

# ---------------------------------------------------------------- partes

func _face(skin: Color, hair: Color, shirt: Color) -> void:
	var eye_y := 0.1
	for side in [-1.0, 1.0]:
		var sp := surface(side * 0.36, eye_y)
		var ep: Vector3 = sp[0]
		LP.sphere(self, Vector3(0.17, 0.13, 0.08), Color.WHITE, ep + Vector3(0, 0, -0.02))
		LP.sphere(self, Vector3(0.085, 0.085, 0.05), look["eyes"], ep + Vector3(0, -0.01, 0.045))
		LP.sphere(self, Vector3(0.045, 0.045, 0.03), Color("1b1b1b"), ep + Vector3(0, -0.01, 0.075))
		LP.sphere(self, Vector3(0.02, 0.02, 0.01), Color.WHITE, ep + Vector3(0.03, 0.03, 0.09))
		exclusions.append([ep, 0.23])
		# sobrancelha
		var bp := surface(side * 0.36, eye_y + 0.2)
		var brow := Node3D.new()
		add_child(brow)
		brow.position = bp[0] + Vector3(0, 0, 0.02)
		LP.box(brow, Vector3(0.26, 0.05, 0.05), hair.darkened(0.2))
		brows.append(brow)
		exclusions.append([bp[0], 0.12])
		# orelha
		var ear := LP.sphere(self, Vector3(0.12, 0.22, 0.1), skin.darkened(0.05), Vector3(side * 0.98, 0.0, -0.05))
		ear.rotation.y = side * 0.4
	# nariz
	var np := surface(0.0, -0.12)
	LP.sphere(self, Vector3(0.13, 0.2, 0.17), skin.darkened(0.04), np[0] + Vector3(0, 0, -0.02), false, false, "sphere_lo")
	exclusions.append([np[0], 0.16])
	# boca (pontinhos que fazem a curva do sorriso)
	for i in 11:
		mouth_dots.append(LP.sphere(self, Vector3(0.034, 0.026, 0.024), Color("7a3b2e"), Vector3.ZERO, false, false, "sphere_lo"))
	exclusions.append([surface(0.0, -0.42)[0], 0.2])
	set_mood(0.0)
	# cabelo
	if not look.get("bald", false):
		var h := LP.sphere(self, Vector3(1.06, 0.78, 1.02), hair, Vector3(0, 0.62, -0.1), false, false, "sphere")
		h.rotation.x = -0.25
		exclusions.append([surface(0.0, 0.95)[0], 0.55])
	# pescoço e ombros
	LP.cyl(self, 0.42, 0.8, skin.darkened(0.08), Vector3(0, -1.4, -0.15))
	LP.sphere(self, Vector3(2.0, 0.55, 0.9), shirt, Vector3(0, -2.0, -0.3), false, false, "sphere")

func _arm(skin: Color, shirt: Color) -> void:
	# mão
	var hand := Node3D.new()
	add_child(hand)
	hand.position = Vector3(2.45, 0.0, 0.0)
	LP.sphere(hand, Vector3(0.42, 0.22, 0.42), skin, Vector3(0.25, 0, 0))
	for i in 4:
		var f := LP.add(hand, "sphere_lo", skin.darkened(0.03), Vector3(0.28, 0.09, 0.08), Vector3(0.75, 0.05, -0.25 + i * 0.17))
		f.rotation.z = -0.15
	var thumb := LP.add(hand, "sphere_lo", skin.darkened(0.03), Vector3(0.22, 0.09, 0.09), Vector3(0.3, 0.05, 0.42))
	thumb.rotation.y = -0.7
	# manga
	var sleeve := LP.cyl(self, 0.6, 0.7, shirt, Vector3(-2.25, 0, 0))
	sleeve.rotation.z = PI / 2
	exclusions.append([Vector3(2.3, 0, 0.3), 0.35])
	exclusions.append([Vector3(-2.15, 0, 0.3), 0.3])

func _back(skin: Color, hair: Color, shirt: Color) -> void:
	# coluna
	LP.box(self, Vector3(0.05, 2.6, 0.02), skin.darkened(0.08), Vector3(0, 0.1, 0.79))
	# pescoço e nuca
	LP.cyl(self, 0.38, 0.6, skin.darkened(0.05), Vector3(0, 1.95, -0.1))
	LP.sphere(self, Vector3(0.75, 0.8, 0.75), skin, Vector3(0, 2.6, -0.1))
	if not look.get("bald", false):
		LP.sphere(self, Vector3(0.8, 0.75, 0.8), hair, Vector3(0, 2.75, -0.05))
	# braços
	for side in [-1.0, 1.0]:
		var a := LP.sphere(self, Vector3(0.38, 1.4, 0.38), skin.darkened(0.04), Vector3(side * 1.75, 0.2, -0.1))
		a.rotation.z = side * 0.12
	# calça
	LP.sphere(self, Vector3(1.55, 0.5, 0.85), shirt.darkened(0.25), Vector3(0, -1.85, 0))

func _foot(skin: Color, shirt: Color) -> void:
	# dedos
	var sizes := [0.2, 0.15, 0.135, 0.12, 0.105]
	var xs := [-0.5, -0.2, 0.06, 0.3, 0.52]
	var ys := [1.72, 1.82, 1.78, 1.68, 1.55]
	for i in 5:
		var s: float = sizes[i]
		var tp := Vector3(xs[i], ys[i], 0.05)
		LP.sphere(self, Vector3(s, s * 1.25, s * 0.95), skin.darkened(0.02), tp)
		LP.sphere(self, Vector3(s * 0.6, s * 0.55, s * 0.3), Color("f3dfe0"), tp + Vector3(0, s * 0.35, s * 0.75), false, true, "sphere_lo")
	exclusions.append([Vector3(0, 1.65, 0.3), 0.35])
	# tornozelo / perna
	LP.cyl(self, 0.6, 1.6, skin.darkened(0.06), Vector3(0, -2.1, -0.4))
	LP.cyl(self, 0.68, 0.8, shirt.darkened(0.2), Vector3(0, -2.9, -0.4))
