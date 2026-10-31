extends Node
## Anúncios premiados e intersticiais (AdMob pelo plugin Android próprio: addons/gg_native).
##
## No celular usa o plugin GGNative. No editor/PC (sem plugin) mostra uma tela simulada.
## Versão de teste (debug) usa os IDs de TESTE do Google; a versão de publicação usa os blocos reais.

signal ad_started
signal ad_finished

# blocos reais (AdMob: app "Gross To Glow")
const REAL_INTERSTITIAL := "ca-app-pub-4311255826061303/1230926730"   # "Próxima fase"
const REAL_REWARDED := "ca-app-pub-4311255826061303/7604763396"       # "Anúncio premiado"
# IDs de teste oficiais do Google (versão debug)
const TEST_INTERSTITIAL := "ca-app-pub-3940256099942544/1033173712"
const TEST_REWARDED := "ca-app-pub-3940256099942544/5224354917"

const MOCK_REWARDED_SECONDS := 3
const MOCK_INTERSTITIAL_SECONDS := 2

var busy := false
var native: Object = null
var _on_reward: Callable
var _on_done: Callable

func _ready() -> void:
	if Engine.has_singleton("GGNative"):
		native = Engine.get_singleton("GGNative")
		native.connect("interstitial_closed", _native_inter_closed)
		native.connect("rewarded_closed", _native_reward_closed)
		native.connect("ad_error", func(m): print("[ads] ", m))
		var debug := OS.is_debug_build()
		native.init_ads(TEST_INTERSTITIAL if debug else REAL_INTERSTITIAL, TEST_REWARDED if debug else REAL_REWARDED)

func use_real_ads() -> bool:
	return native != null

## Mostra anúncio premiado. on_reward só é chamado se o jogador assistir até o fim.
func show_rewarded(on_reward: Callable) -> void:
	if busy:
		return
	if not use_real_ads():
		_mock(true, on_reward)
		return
	if not native.is_rewarded_ready():
		_notice(tr("O anúncio ainda está carregando. Tente de novo em instantes!"))
		return
	busy = true
	_on_reward = on_reward
	ad_started.emit()
	_mute(true)
	native.show_rewarded()

## Mostra intersticial e chama on_done ao fechar (com ou sem anúncio).
func show_interstitial(on_done: Callable) -> void:
	if busy:
		return
	if not use_real_ads():
		_mock(false, on_done)
		return
	if not native.is_interstitial_ready():
		on_done.call()
		return
	busy = true
	_on_done = on_done
	ad_started.emit()
	_mute(true)
	native.show_interstitial()

func _native_inter_closed() -> void:
	busy = false
	_mute(false)
	ad_finished.emit()
	if _on_done.is_valid():
		_on_done.call()
	_on_done = Callable()

func _native_reward_closed(earned: bool) -> void:
	busy = false
	_mute(false)
	ad_finished.emit()
	if earned and _on_reward.is_valid():
		_on_reward.call()
	_on_reward = Callable()

func _mute(on: bool) -> void:
	AudioServer.set_bus_mute(0, on)

func _notice(text: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 120
	get_tree().root.add_child(layer)
	var l := UIKit.label(text, 30, Color.WHITE, 8)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.custom_minimum_size = Vector2(600, 0)
	l.position -= Vector2(300, 40)
	layer.add_child(l)
	await get_tree().create_timer(1.8).timeout
	layer.queue_free()

# ------------------------------------------------------------- simulado

func _mock(rewarded: bool, cb: Callable) -> void:
	busy = true
	ad_started.emit()
	var layer := CanvasLayer.new()
	layer.layer = 120
	get_tree().root.add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.04, 0.12, 0.96)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(bg)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 18)
	bg.add_child(vb)
	vb.add_child(UIKit.label("ANÚNCIO", 64, UIKit.YELLOW))
	vb.add_child(UIKit.label("(simulado)", 24, Color(1, 1, 1, 0.7), 0))
	var count := UIKit.label("", 44)
	vb.add_child(count)
	var close := UIKit.btn("Receber recompensa" if rewarded else "Fechar", UIKit.GREEN, 30, Vector2(360, 80))
	close.visible = false
	var cc := CenterContainer.new()
	cc.add_child(close)
	vb.add_child(cc)
	close.pressed.connect(func():
		layer.queue_free()
		busy = false
		ad_finished.emit()
		if cb.is_valid():
			cb.call())
	var secs := MOCK_REWARDED_SECONDS if rewarded else MOCK_INTERSTITIAL_SECONDS
	for i in range(secs, 0, -1):
		count.text = str(i)
		await get_tree().create_timer(1.0).timeout
	count.text = "Obrigado por assistir!" if rewarded else ""
	close.visible = true
	UIKit.pop_in(close)
