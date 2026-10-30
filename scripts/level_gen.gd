class_name LevelGen
extends RefCounted
## Gera fases de forma determinística a partir do número da fase.

const PARTS := ["mao", "pe"]

static func is_extreme(level: int) -> bool:
	return level % 5 == 0

static func make(level: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = level * 7919 + 4242
	var extreme := is_extreme(level)
	var part: String = PARTS[(level - 1) % PARTS.size()]
	var max_tier := 1
	if level >= 8:
		max_tier = 3
	elif level >= 4:
		max_tier = 2

	var pool := []
	for id in Defs.PROBLEMS:
		var d: Dictionary = Defs.PROBLEMS[id]
		if d["tier"] <= max_tier and Defs.problem_available(id, level):
			if d["where"] == "calo" and part != "pe":
				continue
			pool.append(id)

	var count := clampi(2 + level / 2, 2, 7)
	if extreme:
		count = mini(count + 3, 10)

	var chosen := []
	if level == 1:
		chosen = ["espinha", "sujeira", "farpa"]
	else:
		var newest := ""
		for tl in Defs.TOOL_ORDER:
			if Defs.TOOLS[tl]["unlock"] == level:
				newest = tl
		if newest != "":
			var with_new := pool.filter(func(id): return Defs.tools_of(id).has(newest))
			if with_new.size() > 0:
				chosen.append(with_new[rng.randi() % with_new.size()])
	var nails := 0
	var guard := 0
	while chosen.size() < count and guard < 300:
		guard += 1
		var id := _weighted(pool, rng, max_tier, extreme)
		var d: Dictionary = Defs.PROBLEMS[id]
		if d["where"] == "unha":
			if nails >= 3:
				continue
		var limit := 2 if d["size"] < 0.1 else 1
		if chosen.count(id) >= limit:
			continue
		if d["where"] == "unha":
			nails += 1
		chosen.append(id)
	chosen.sort_custom(func(a, b): return Defs.PROBLEMS[a]["size"] > Defs.PROBLEMS[b]["size"])
	var look := {
		"name": Defs.NAMES[rng.randi() % Defs.NAMES.size()],
		"skin": Defs.SKINS[rng.randi() % Defs.SKINS.size()],
		"hair": [Color("2b1d14"), Color("5a3a22"), Color("a0522d"), Color("e3c27a"), Color("1a1a1a")][rng.randi() % 5],
		"pillow": [Color("8e5ac8"), Color("e06aa8"), Color("4f8fd8"), Color("4fb89a"), Color("e8935a")][level % 5],
	}
	return {"level": level, "part": part, "problems": chosen, "extreme": extreme, "look": look, "seed": rng.seed}

static func _weighted(pool: Array, rng: RandomNumberGenerator, max_tier: int, extreme: bool) -> String:
	var total := 0.0
	var ws := []
	for id in pool:
		var d: Dictionary = Defs.PROBLEMS[id]
		var w: float = d["w"]
		if d["tier"] == max_tier:
			w *= 1.6
		if extreme and d["tier"] >= 2:
			w *= 2.0
		ws.append(w)
		total += w
	var r := rng.randf() * total
	for i in pool.size():
		r -= ws[i]
		if r <= 0.0:
			return pool[i]
	return pool[pool.size() - 1]

static func needed_tools(data: Dictionary) -> Array:
	var out := []
	for id in data["problems"]:
		for tl in Defs.tools_of(id):
			if not out.has(tl):
				out.append(tl)
	return out

## Escolhe posições na mão/pé. Retorna [{pos, normal, fwd, nail}] na ordem dos problemas.
static func place(body: Body, ids: Array, rng: RandomNumberGenerator) -> Array:
	var out := []
	var used := []        # [pos, raio]
	var used_nails := []
	var hand := body.part == "mao"
	var dorso := Rect2(-0.35, -0.36, 0.78, 0.7) if hand else Rect2(-0.85, -0.3, 1.35, 0.6)
	var arm := Rect2(-1.55, -0.2, 1.0, 0.4) if hand else Rect2(-1.75, -0.2, 0.75, 0.4)
	for id in ids:
		var d: Dictionary = Defs.PROBLEMS[id]
		var r: float = d["size"]
		var where: String = d["where"]
		var res := {}
		if where == "unha":
			var order := range(body.nails.size())
			order.shuffle()
			if id == "unha_encravada":
				order.erase(0)
				order.push_front(0)
			for i in order:
				if not used_nails.has(i):
					used_nails.append(i)
					var nl: Dictionary = body.nails[i]
					var nd: Node3D = nl["node"]
					var cpos := nd.to_global(Vector3(0, 0, nl["len"] * 0.5))
					res = {"pos": cpos, "normal": nl["normal"], "fwd": nl["dir"], "nail": nl}
					used.append([cpos, nl["w"]])
					break
		else:
			var best := {}
			var best_score := -INF
			for attempt in 50:
				var p := Vector3.ZERO
				var fwd := Vector3(1, 0, 0)
				var kind := where
				if kind == "pele":
					kind = ["dorso", "dorso", "braco", "dedo"][rng.randi() % 4]
					if r > 0.1:
						kind = "dorso" if rng.randf() < 0.7 else "braco"
				if kind == "calo":
					if rng.randf() < 0.6:
						var di := rng.randi() % body.digits.size()
						var q := body.digit_point(di, 0.45)
						p = Vector3(q.x, 0, q.z)
					else:
						p = Vector3(-1.2, 0, rng.randf_range(-0.2, 0.2))
				elif kind == "dedo":
					var di2 := rng.randi_range(0 if hand else 0, body.digits.size() - 1)
					var tt := rng.randf_range(0.3, 0.62) if hand else rng.randf_range(0.2, 0.45)
					var q2 := body.digit_point(di2, tt)
					var q3 := body.digit_point(di2, tt + 0.1)
					p = Vector3(q2.x, 0, q2.z)
					fwd = (q3 - q2).normalized()
				elif kind == "braco":
					p = Vector3(rng.randf_range(arm.position.x, arm.end.x), 0, rng.randf_range(arm.position.y, arm.end.y))
				else:
					p = Vector3(rng.randf_range(dorso.position.x, dorso.end.x), 0, rng.randf_range(dorso.position.y, dorso.end.y))
				var sp := body.surface(p.x, p.z)
				if sp.is_empty():
					continue
				var pos: Vector3 = sp[0]
				var nrm: Vector3 = sp[1]
				if nrm.y < 0.55:
					continue
				var score := 10.0
				for u in used:
					score = minf(score, pos.distance_to(u[0]) - u[1] - r)
				score -= (1.0 - nrm.y) * 0.1
				if score > best_score:
					best_score = score
					best = {"pos": pos, "normal": nrm, "fwd": fwd}
				if score > 0.04 and attempt > 6:
					break
			res = best
			if not res.is_empty():
				used.append([res["pos"], r])
		out.append(res)
	return out
