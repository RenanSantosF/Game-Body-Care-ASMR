extends Node
# (dev) foto do menu e da loja
func _ready() -> void:
	var out := OS.get_environment("OUT")
	var m = load("res://scenes/main_menu.tscn").instantiate()
	add_child(m)
	GameData.last_daily = Time.get_date_string_from_system()
	await get_tree().create_timer(4.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/menu.png")
	m._shop()
	await get_tree().create_timer(4.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/shop.png")
	get_tree().quit()
