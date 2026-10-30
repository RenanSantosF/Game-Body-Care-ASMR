extends Node
## Anúncios recompensados e intersticiais.
##
## Por padrão roda em modo SIMULADO (mostra uma tela de anúncio falsa), assim o
## jogo funciona no editor e no celular sem nenhum plugin.
## Para anúncios reais com AdMob veja o README (seção "Anúncios reais"):
## basta implementar _real_show_rewarded / _real_show_interstitial abaixo.

signal ad_started
signal ad_finished

# IDs de TESTE oficiais do Google. Troque pelos seus antes de publicar.
const REWARDED_ID := "ca-app-pub-3940256099942544/5224354917"
const INTERSTITIAL_ID := "ca-app-pub-3940256099942544/1033173712"

const MOCK_REWARDED_SECONDS := 3
const MOCK_INTERSTITIAL_SECONDS := 2

var busy := false

func use_real_ads() -> bool:
	# Troque para true depois de instalar e configurar um plugin AdMob.
	return false

## Mostra anúncio recompensado. on_reward só é chamado se o jogador assistir até o fim.
func show_rewarded(on_reward: Callable) -> void:
	if busy:
		return
	if use_real_ads():
		_real_show_rewarded(on_reward)
	else:
		_mock(true, on_reward)

## Mostra intersticial e chama on_done ao fechar (com ou sem anúncio).
func show_interstitial(on_done: Callable) -> void:
	if busy:
		return
	if use_real_ads():
		_real_show_interstitial(on_done)
	else:
		_mock(false, on_done)

func _real_show_rewarded(on_reward: Callable) -> void:
	# TODO: integrar plugin AdMob (ex.: Poing Studios godot-admob-plugin).
	# Carregue o RewardedAd com REWARDED_ID e, no callback "user earned reward",
	# chame on_reward.call(). Emita ad_started / ad_finished.
	_mock(true, on_reward)

func _real_show_interstitial(on_done: Callable) -> void:
	# TODO: integrar plugin AdMob. Ao fechar o anúncio, chame on_done.call().
	_mock(false, on_done)

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
	vb.add_child(UIKit.label("(simulado - integre o AdMob para anúncios reais)", 24, Color(1, 1, 1, 0.7), 0))
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
