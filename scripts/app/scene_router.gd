extends Node

const BOOTSTRAP_SCENE := "res://scenes/bootstrap.tscn"
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const ROOM_SCENE := "res://scenes/room.tscn"
const GAME_SCENE := "res://scenes/game.tscn"


func go_to_bootstrap() -> void:
	_change_scene(BOOTSTRAP_SCENE)


func go_to_main_menu() -> void:
	_change_scene(MAIN_MENU_SCENE)


func go_to_room() -> void:
	_change_scene(ROOM_SCENE)


func go_to_game() -> void:
	_change_scene(GAME_SCENE)


func _change_scene(scene_path: String) -> void:
	# 场景切换集中在这里，避免按钮脚本到处直接 change_scene，后续 loading/error 流程也能统一处理。
	var error := get_tree().change_scene_to_file(scene_path)
	if error != OK:
		AppState.set_error("failed to change scene to %s: %s" % [scene_path, error_string(error)])
		push_error(AppState.last_error)
		return

	AppState.set_current_scene(scene_path)
