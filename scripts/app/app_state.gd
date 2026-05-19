extends Node

signal current_scene_changed(scene_path: String)

enum LaunchMode {
	NONE,
	SINGLEPLAYER,
	HOST,
	CLIENT,
}

var current_scene_path := ""
var launch_mode := LaunchMode.NONE
var server_addr := ""
var assets_ready := false
var rust_ready := false
var last_error := ""


func set_current_scene(scene_path: String) -> void:
	current_scene_path = scene_path
	current_scene_changed.emit(scene_path)


func set_bootstrap_status(is_assets_ready: bool, is_rust_ready: bool) -> void:
	assets_ready = is_assets_ready
	rust_ready = is_rust_ready


func set_error(message: String) -> void:
	last_error = message


func clear_error() -> void:
	last_error = ""


func clear_runtime_session() -> void:
	launch_mode = LaunchMode.NONE
	server_addr = ""
