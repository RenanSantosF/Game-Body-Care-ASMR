extends Node
## Sons gerados por código (sem arquivos de áudio). Troque por .ogg reais quando quiser.

const RATE := 22050

var streams := {}
var players: Array[AudioStreamPlayer] = []
var _next := 0
var _last := {}

var music: AudioStreamPlayer
var _track := ""

## Música de fundo (composta em tools/compose.py)
func play_music(track: String) -> void:
	if track == _track:
		return
	_track = track
	var st: AudioStream = load("res://assets/music/%s.ogg" % track)
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = true
	var tw := create_tween()
	if music.playing:
		tw.tween_property(music, "volume_db", -40.0, 0.5)
	tw.tween_callback(func():
		music.stream = st
		music.volume_db = -40.0
		if GameData.music_on:
			music.play())
	tw.tween_property(music, "volume_db", -9.0, 0.8)

func set_music_enabled(on: bool) -> void:
	GameData.music_on = on
	if on:
		if music.stream:
			music.play()
	else:
		music.stop()

func _ready() -> void:
	music = AudioStreamPlayer.new()
	add_child(music)
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	streams["pop"] = _synth(0.18, 520, 90, 0.35, 3.0, 0.0, 0.5)
	streams["splat"] = _synth(0.32, 120, 40, 0.7, 1.6, 14.0, 0.18)
	streams["squish"] = _synth(0.3, 160, 70, 0.75, 1.5, 22.0, 0.14)
	streams["scrub"] = _synth(0.16, 300, 300, 1.0, 0.8, 0.0, 0.35)
	streams["pull"] = _synth(0.28, 260, 760, 0.25, 1.2, 0.0, 0.4)
	streams["cut"] = _synth(0.12, 900, 500, 0.9, 2.0, 0.0, 0.85)
	streams["freeze"] = _synth(0.5, 2000, 1500, 0.95, 1.0, 0.0, 0.75)
	streams["tap"] = _synth(0.1, 420, 300, 0.2, 2.5, 0.0, 0.3)
	streams["click"] = _synth(0.05, 880, 640, 0.1, 3.0, 0.0, 0.5)
	streams["wrong"] = _synth(0.3, 150, 110, 0.0, 1.0, 0.0, 0.5, true)
	streams["poke"] = _synth(0.09, 1400, 700, 0.5, 2.5, 0.0, 0.7)
	streams["clip"] = [_synth(0.05, 3200, 1900, 0.7, 4.0, 0.0, 0.95), _synth(0.06, 2800, 1600, 0.75, 4.0, 0.0, 0.9)]
	streams["ouch"] = _voice()
	# líquidos: várias versões para não soar repetido (escolhidas ao acaso)
	streams["splat"] = [streams["splat"], _liquid(0.3, 7, 180, 520, 0.35, 0.2), _liquid(0.36, 10, 140, 420, 0.45, 0.15), _liquid(0.26, 5, 220, 700, 0.3, 0.25)]
	streams["squish"] = [streams["squish"], _liquid(0.32, 6, 120, 360, 0.55, 0.12), _liquid(0.4, 9, 100, 300, 0.6, 0.1), _liquid(0.28, 4, 160, 460, 0.5, 0.14)]
	streams["pop"] = [streams["pop"], _liquid(0.16, 1, 380, 620, 0.15, 0.4), _liquid(0.2, 2, 300, 560, 0.2, 0.35)]
	streams["drip"] = [_liquid(0.12, 1, 600, 1100, 0.05, 0.5), _liquid(0.1, 1, 750, 1300, 0.05, 0.5), _liquid(0.14, 1, 500, 900, 0.08, 0.45)]
	streams["ooze"] = [_liquid(0.5, 14, 90, 260, 0.65, 0.08), _liquid(0.55, 16, 80, 240, 0.7, 0.07)]
	streams["coin"] = _seq([[988, 0.07], [1318, 0.14]])
	streams["success"] = _seq([[523, 0.1], [659, 0.1], [784, 0.1], [1046, 0.25]])
	streams["star"] = _seq([[1046, 0.08], [1568, 0.16]])

func play(snd: String, pitch_rand := 0.08, vol := 0.0) -> void:
	if not GameData.sound_on or not streams.has(snd):
		return
	var p := players[_next]
	_next = (_next + 1) % players.size()
	var st = streams[snd]
	p.stream = st.pick_random() if st is Array else st
	p.pitch_scale = 1.0 + randf_range(-pitch_rand, pitch_rand)
	p.volume_db = vol
	p.play()

func play_throttled(snd: String, interval: float, pitch_rand := 0.15, vol := -4.0) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last.get(snd, -10.0) < interval:
		return
	_last[snd] = now
	play(snd, pitch_rand, vol)

func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w

func _synth(dur: float, f0: float, f1: float, noise: float, decay: float, wobble: float, lp: float, square := false) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase := 0.0
	var y := 0.0
	for i in n:
		var k := float(i) / n
		var tt := float(i) / RATE
		var f := lerpf(f0, f1, k)
		phase += TAU * f / RATE
		var tone := sin(phase)
		if square:
			tone = signf(tone) * 0.6
		y += lp * ((randf() * 2.0 - 1.0) - y)
		var env := pow(1.0 - k, decay) * minf(1.0, tt / 0.004)
		var w := 1.0
		if wobble > 0.0:
			w = 0.6 + 0.4 * sin(TAU * wobble * tt)
		s[i] = (tone * (1.0 - noise) + y * noise * 1.8) * env * w * 0.7
	return _wav(s)

func _seq(notes: Array) -> AudioStreamWAV:
	var s := PackedFloat32Array()
	for nt in notes:
		var n := int(nt[1] * RATE)
		var phase := 0.0
		for i in n:
			var k := float(i) / n
			phase += TAU * nt[0] / RATE
			s.append((sin(phase) * 0.6 + sin(phase * 2.0) * 0.15) * pow(1.0 - k, 1.5) * 0.6)
	return _wav(s)

## Som molhado: bolhas (seno com pitch subindo e decaindo rápido) + ruído grave grudento
func _liquid(dur: float, bubbles: int, fmin: float, fmax: float, noise: float, lp: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var y := 0.0
	var y2 := 0.0
	for i in n:
		var k := float(i) / n
		y += lp * ((randf() * 2.0 - 1.0) - y)
		y2 += 0.08 * (y - y2)
		s[i] = y2 * noise * 2.5 * pow(1.0 - k, 1.5) * minf(1.0, k * 30.0)
	for b in bubbles:
		var t0 := int(randf_range(0.0, 0.7) * n)
		var f := randf_range(fmin, fmax)
		var tau := randf_range(0.015, 0.05)
		var amp := randf_range(0.4, 0.9)
		var ph := 0.0
		var m := mini(n - t0, int(tau * 5.0 * RATE))
		for j in m:
			var tt := float(j) / RATE
			ph += TAU * f * (1.0 + tt * 60.0) / RATE
			s[t0 + j] += sin(ph) * amp * exp(-tt / tau) * minf(1.0, tt / 0.002)
	for i in n:
		s[i] *= 0.55
	return _wav(s)

## "Ai!" sintetizado (formante simples)
func _voice() -> AudioStreamWAV:
	var n := int(0.35 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in n:
		var k := float(i) / n
		var f := lerpf(520.0, 300.0, k) * (1.0 + 0.03 * sin(i * 0.004))
		ph += TAU * f / RATE
		var saw := fmod(ph / TAU, 1.0) * 2.0 - 1.0
		var form := sin(ph * 2.0) * 0.5 + sin(ph * 3.0) * 0.3
		var env := minf(1.0, k * 20.0) * pow(1.0 - k, 1.2)
		s[i] = (saw * 0.35 + form * 0.4) * env * 0.6
	return _wav(s)
