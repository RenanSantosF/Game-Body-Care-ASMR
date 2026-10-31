extends Node
## Progresso salvo: moedas, fases, ferramentas e bônus diário.

signal coins_changed(coins: int)

const SAVE_PATH := "user://save.json"

var coins := 0
var level := 1               # maior fase liberada
var current_level := 1       # fase sendo jogada
var stars := {}              # "fase" -> estrelas
var owned := {"pano": 1, "algodao": 1, "agulha": 1, "espremedor": 1, "pinca": 1}   # ferramenta -> nível de melhoria
var streak := 0
var last_daily := ""
var levels_since_ad := 0
var sound_on := true
var music_on := true
var vibrate_on := true
var patients_treated := 0

func _ready() -> void:
	load_game()
	current_level = level
	var th := Theme.new()
	th.default_font_size = 26
	var fv := FontVariation.new()
	fv.base_font = load("res://assets/fonts/Fredoka.ttf")
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600}
	th.default_font = fv
	get_tree().root.theme = th

func add_coins(n: int) -> void:
	coins = maxi(0, coins + n)
	coins_changed.emit(coins)
	save_game()

func spend(n: int) -> bool:
	if coins < n:
		return false
	add_coins(-n)
	return true

func has_tool(id: String) -> bool:
	return owned.has(id)

func unlock_tool(id: String) -> void:
	if not owned.has(id):
		owned[id] = 1
		save_game()

func tool_level(id: String) -> int:
	return owned.get(id, 0)

func upgrade_tool(id: String) -> void:
	owned[id] = mini(3, tool_level(id) + 1)
	save_game()

func speed_mult(id: String) -> float:
	return 1.0 + 0.35 * (tool_level(id) - 1)

func complete_level(lvl: int, st: int, reward: int) -> void:
	var key := str(lvl)
	stars[key] = maxi(stars.get(key, 0), st)
	if lvl >= level:
		level = lvl + 1
	levels_since_ad += 1
	patients_treated += 1
	add_coins(reward)

func total_stars() -> int:
	var s := 0
	for k in stars:
		s += int(stars[k])
	return s

# ---------------------------------------------------- bônus diário

func daily_available() -> bool:
	return last_daily != _today()

func daily_reward() -> int:
	var next := streak + 1 if last_daily == _yesterday() else 1
	return 40 + 30 * mini(next, 7)

func claim_daily(mult := 1) -> int:
	if last_daily == _yesterday():
		streak += 1
	else:
		streak = 1
	var r := (40 + 30 * mini(streak, 7)) * mult
	last_daily = _today()
	add_coins(r)
	return r

func _today() -> String:
	return Time.get_date_string_from_system()

func _yesterday() -> String:
	return Time.get_date_string_from_unix_time(int(Time.get_unix_time_from_system()) - 86400)

# ---------------------------------------------------- utilidades

var _vib_until := 0

## amp 0..1 (força). Não empilha: ignora pulsos enquanto outro ainda vibra, exceto se mais forte.
func vibrate(ms: int, amp := -1.0) -> void:
	if not vibrate_on or not OS.has_feature("mobile"):
		return
	var now := Time.get_ticks_msec()
	if now < _vib_until and amp < 0.8:
		return
	_vib_until = now + ms
	Input.vibrate_handheld(ms, amp)

func save_game() -> void:
	var d := {
		"coins": coins, "level": level, "stars": stars, "owned": owned,
		"streak": streak, "last_daily": last_daily, "levels_since_ad": levels_since_ad,
		"sound_on": sound_on, "music_on": music_on, "vibrate_on": vibrate_on, "patients": patients_treated,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))

func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return
	coins = int(d.get("coins", 0))
	level = int(d.get("level", 1))
	stars = d.get("stars", {})
	var o: Dictionary = d.get("owned", {})
	for k in o:
		owned[k] = int(o[k])
	streak = int(d.get("streak", 0))
	last_daily = str(d.get("last_daily", ""))
	levels_since_ad = int(d.get("levels_since_ad", 0))
	sound_on = bool(d.get("sound_on", true))
	music_on = bool(d.get("music_on", true))
	vibrate_on = bool(d.get("vibrate_on", true))
	patients_treated = int(d.get("patients", 0))
