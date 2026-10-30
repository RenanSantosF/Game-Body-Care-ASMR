extends Node
## Sons gerados por código (sem arquivos de áudio). Troque por .ogg reais quando quiser.

const RATE := 22050

var streams := {}
var players: Array[AudioStreamPlayer] = []
var _next := 0
var _last := {}

func _ready() -> void:
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
	streams["ouch"] = _voice()
	streams["coin"] = _seq([[988, 0.07], [1318, 0.14]])
	streams["success"] = _seq([[523, 0.1], [659, 0.1], [784, 0.1], [1046, 0.25]])
	streams["star"] = _seq([[1046, 0.08], [1568, 0.16]])

func play(snd: String, pitch_rand := 0.08, vol := 0.0) -> void:
	if not GameData.sound_on or not streams.has(snd):
		return
	var p := players[_next]
	_next = (_next + 1) % players.size()
	p.stream = streams[snd]
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
