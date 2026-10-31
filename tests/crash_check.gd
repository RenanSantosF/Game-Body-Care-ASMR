extends Node
# (dev) confere a detecção de "fechou sozinho": crie user://running.flag antes de rodar
func _ready() -> void:
	print("crashed_last=", GameData.crashed_last, " relatorio=", GameData.crash_report.length(), " chars")
	print(GameData.crash_report.substr(0, 160))
	get_tree().quit()
