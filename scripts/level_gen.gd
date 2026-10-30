class_name LevelGen
extends RefCounted
## Gera fases de forma determinística a partir do número da fase.

const PARTS := ["rosto", "braco", "costas", "pe"]

static func is_extreme(level: int) -> bool:
	return level % 5 == 0

static func make(level: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = level * 7919 + 1337
	var extreme := is_extreme(level)

	var part: String = PARTS[(level - 1) % PARTS.size()]
	var max_tier := 1
	if level >= 9:
		max_tier = 3
	elif level >= 4:
		max_tier = 2

	var pool := []
	for id in Defs.PROBLEMS:
		var d: Dictionary = Defs.PROBLEMS[id]
		if d["tier"] <= max_tier and Defs.problem_available(id, level):
			pool.append(id)

	var count := clampi(2 + level / 2, 2, 7)
	if extreme:
		count = mini(count + 3, 10)
	if part == "rosto":
		count = mini(count, 7)

	var chosen := []
	if level == 1:
		chosen = ["espinha", "farpa"]
		count = 2
	# Garante que a ferramenta mais nova apareça (ensina o jogador)
	var newest := ""
	for t in Defs.TOOL_ORDER:
		if Defs.TOOLS[t]["unlock"] == level:
			newest = t
	if newest != "":
		var with_new := pool.filter(func(id): return Defs.tools_of(id).has(newest))
		if with_new.size() > 0:
			chosen.append(with_new[rng.randi() % with_new.size()])

	var guard := 0
	while chosen.size() < count and guard < 200:
		guard += 1
		var id := _weighted(pool, rng, max_tier, extreme)
		var same := chosen.count(id)
		var d: Dictionary = Defs.PROBLEMS[id]
		var limit := 3 if d["size"] < 0.15 else 1
		if same >= limit:
			continue
		chosen.append(id)

	# Problemas grandes primeiro para caberem no corpo
	chosen.sort_custom(func(a, b): return Defs.PROBLEMS[a]["size"] > Defs.PROBLEMS[b]["size"])

	var look := {
		"name": Defs.NAMES[rng.randi() % Defs.NAMES.size()],
		"skin": Defs.SKINS[rng.randi() % Defs.SKINS.size()],
		"hair": Defs.HAIRS[rng.randi() % Defs.HAIRS.size()],
		"shirt": Defs.SHIRTS[rng.randi() % Defs.SHIRTS.size()],
		"eyes": Color.from_hsv(rng.randf(), 0.6, 0.55),
		"bald": rng.randf() < 0.15,
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
		for t in Defs.tools_of(id):
			if not out.has(t):
				out.append(t)
	return out
