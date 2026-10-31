extends Node
# Confere as traduções: alguns textos em pt/en/es
func _ready() -> void:
	for lang in ["pt", "en", "es"]:
		TranslationServer.set_locale(lang)
		print(lang, ": ", tr("PACIENTE CURADO!"), " | ", tr("Fase %d  -  %s") % [3, "Bruna"], " | ", tr("Micose na unha"), " | ", tr("Segure o botão verde para %s!") % tr("cortar"))
	get_tree().quit()
