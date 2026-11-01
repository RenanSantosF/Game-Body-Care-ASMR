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
var language := ""          # "pt", "en" ou "es" ("" = do sistema)
var patients_treated := 0

const RUN_FLAG := "user://running.flag"
var crashed_last := false   # a última sessão terminou sem pausar/fechar (fechou sozinho)
var crash_report := ""

func _ready() -> void:
	crashed_last = FileAccess.file_exists(RUN_FLAG)
	if crashed_last:
		crash_report = _last_log_tail()
	_mark_running(true)
	log_line("inicio | %s | Android %s | tela %s" % [OS.get_model_name(), OS.get_version(), str(DisplayServer.window_get_size())])
	_limit_3d_res()
	load_game()
	set_language(language, false)
	current_level = level
	var th := Theme.new()
	th.default_font_size = 26
	var fv := FontVariation.new()
	fv.base_font = load("res://assets/fonts/Fredoka.ttf")
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600}
	th.default_font = fv
	get_tree().root.theme = th

## Linha de diagnóstico no log. printerr grava no arquivo na hora (print fica em buffer na versão final
## e se perde se o app travar e for fechado à força).
func log_line(msg: String) -> void:
	printerr("[log] " + msg)

## Telas grandes (tablets): limita a resolução do 3D para não sobrecarregar a placa de vídeo
func _limit_3d_res() -> void:
	var s := DisplayServer.window_get_size()
	var px := float(s.x * s.y)
	const MAX_PX := 2.6e6
	if px > MAX_PX:
		get_tree().root.scaling_3d_scale = clampf(sqrt(MAX_PX / px), 0.6, 1.0)
		log_line("tela %dx%d: 3D em %d%%" % [s.x, s.y, int(get_tree().root.scaling_3d_scale * 100.0)])

## Marca "rodando"; some quando o app vai para o fundo ou fecha normalmente
func _mark_running(on: bool) -> void:
	if on:
		var f := FileAccess.open(RUN_FLAG, FileAccess.WRITE)
		if f:
			f.store_string("fase %d" % current_level)
	elif FileAccess.file_exists(RUN_FLAG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RUN_FLAG))

func _exit_tree() -> void:
	_mark_running(false)

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_FOCUS_OUT:
			_mark_running(false)
		NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN:
			_mark_running(true)

## Últimas linhas do log da sessão anterior (o Godot renomeia o log antigo ao abrir)
func _last_log_tail() -> String:
	var dir := "user://logs"
	var files := Array(DirAccess.get_files_at(dir)).filter(func(f): return f.begins_with("godot") and f != "godot.log")
	if files.is_empty():
		return "(sem log)"
	files.sort()
	var txt := FileAccess.get_file_as_string(dir + "/" + files[-1])
	var lines := txt.split("\n")
	var keep := lines.slice(maxi(0, lines.size() - 60))
	var info := "Gross to Glow %s | %s | %s\n" % [ProjectSettings.get_setting("application/config/version", "?"), OS.get_model_name(), OS.get_version()]
	return info + "\n".join(keep)

## Idioma do jogo: o escolhido nas opções ou o do celular (português, espanhol; senão inglês)
func set_language(lang: String, save := true) -> void:
	if lang == "":
		var sys := OS.get_locale_language()
		lang = sys if sys in ["pt", "es"] else "en"
	language = lang
	TranslationServer.set_locale(lang)
	if save:
		save_game()

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
func vibrate(ms: int, amp := -1.0, force := false) -> void:
	if not vibrate_on or not OS.has_feature("mobile"):
		return
	var now := Time.get_ticks_msec()
	if not force and now < _vib_until and (amp < 0.8 and amp >= 0.0):
		return
	# motores de vibração mais simples não sentem pulsos curtos/fracos: mínimo de 25ms e força
	ms = maxi(ms, 25)
	if amp >= 0.0:
		amp = clampf(amp * 1.3, 0.4, 1.0)
	# forte = força padrão do sistema (alguns celulares ignoram intensidade escolhida)
	if amp >= 0.75:
		amp = -1.0
	_vib_until = now + ms
	# plugin nativo (vibra mesmo com a "vibração de mídia" desligada no celular); senão, a do Godot
	if Engine.has_singleton("GGNative"):
		Engine.get_singleton("GGNative").vibrate(ms, -1 if amp < 0.0 else int(amp * 255.0))
	else:
		Input.vibrate_handheld(ms, amp)

func save_game() -> void:
	var d := {
		"coins": coins, "level": level, "stars": stars, "owned": owned,
		"streak": streak, "last_daily": last_daily, "levels_since_ad": levels_since_ad,
		"sound_on": sound_on, "music_on": music_on, "vibrate_on": vibrate_on, "language": language, "patients": patients_treated,
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
	language = str(d.get("language", ""))
	patients_treated = int(d.get("patients", 0))
