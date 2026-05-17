extends Node

# Rust 状态变化后通知 UI 刷新，避免界面层主动轮询 Rust 状态。
signal state_changed

var _rusty_core: Object
var _available := false
var _last_result := "not_initialized"
var _last_error_detail := ""


func _ready() -> void:
	# 这里是 Godot 与 Rust GDExtension 的边界。
	# 其他 GDScript 代码应通过 RustBackend 调用 Rust，不要直接实例化 RustyCore。
	if !ClassDB.class_exists("RustyCore"):
		_last_result = "rusty_core_unavailable"
		push_warning("RustyCore is not available. Build and copy the GDExtension library first.")
		return

	_rusty_core = ClassDB.instantiate("RustyCore")
	_available = _rusty_core != null
	_last_result = "created"
	state_changed.emit()


func is_available() -> bool:
	return _available


func get_version() -> String:
	if !_available:
		return ""
	return str(_rusty_core.call("get_version"))


func get_status() -> String:
	if !_available:
		return "unavailable"
	return str(_rusty_core.call("get_status"))


func get_assets_root() -> String:
	if !_available:
		return ""
	return str(_rusty_core.call("get_assets_root"))


func get_runtime_mode() -> String:
	if !_available:
		return "none"
	return str(_rusty_core.call("get_runtime_mode"))


func is_initialized() -> bool:
	if !_available:
		return false
	return bool(_rusty_core.call("is_initialized"))


func get_last_result() -> String:
	return _last_result


func get_last_error_detail() -> String:
	return _last_error_detail


func get_frontend_snapshot() -> Dictionary:
	if !_available:
		return _empty_frontend_snapshot("unavailable")

	var snapshot = _rusty_core.call("get_frontend_snapshot")
	if typeof(snapshot) != TYPE_DICTIONARY:
		return _empty_frontend_snapshot("invalid_snapshot")

	return snapshot


func initialize_with_assets_path(assets_path: String) -> String:
	return initialize_with_paths(assets_path, assets_path.path_join("content_packages/official_base_game"))


func initialize_with_paths(assets_path: String, content_package_path: String) -> String:
	if !_available:
		_last_result = "rusty_core_unavailable"
		_last_error_detail = "RustyCore class is not available."
		state_changed.emit()
		return _last_result

	if assets_path.is_empty():
		_last_result = "invalid_assets_root"
		_last_error_detail = "assets path is empty before calling Rust."
		state_changed.emit()
		return _last_result

	if content_package_path.is_empty():
		_last_result = "invalid_content_root"
		_last_error_detail = "content package path is empty before calling Rust."
		state_changed.emit()
		return _last_result

	# Godot 的 user:// 是虚拟路径；传给 Rust 前必须转成平台真实路径。
	_last_result = str(_rusty_core.call("initialize_with_paths", assets_path, content_package_path))
	_refresh_error_detail()
	state_changed.emit()
	return _last_result


func start_singleplayer() -> String:
	return _call_runtime_mode("start_singleplayer")


func start_host() -> String:
	return _call_runtime_mode("start_host")


func start_client(server_addr: String) -> String:
	if !_available:
		_last_result = "rusty_core_unavailable"
		_last_error_detail = "RustyCore class is not available."
		state_changed.emit()
		return _last_result

	# 当前只把目标地址交给 Rust runtime 记录；真实联网连接会在下一阶段实现。
	_last_result = str(_rusty_core.call("start_client", server_addr))
	_refresh_error_detail()
	state_changed.emit()
	return _last_result


func shutdown() -> String:
	if !_available:
		_last_result = "rusty_core_unavailable"
		_last_error_detail = "RustyCore class is not available."
		state_changed.emit()
		return _last_result

	_last_result = str(_rusty_core.call("shutdown"))
	_refresh_error_detail()
	state_changed.emit()
	return _last_result


func update_runtime(delta_seconds: float) -> String:
	if !_available:
		_last_result = "rusty_core_unavailable"
		_last_error_detail = "RustyCore class is not available."
		return _last_result

	# 只有进入运行态后才每帧推进 Rust，避免菜单空闲时刷出 not_running。
	if get_status() != "running":
		return _last_result

	_last_result = str(_rusty_core.call("update", delta_seconds))
	_refresh_error_detail()
	return _last_result


func _call_runtime_mode(method_name: String) -> String:
	if !_available:
		_last_result = "rusty_core_unavailable"
		_last_error_detail = "RustyCore class is not available."
		state_changed.emit()
		return _last_result

	_last_result = str(_rusty_core.call(method_name))
	_refresh_error_detail()
	state_changed.emit()
	return _last_result


func _refresh_error_detail() -> void:
	if !_available:
		return
	if _last_result == "ok":
		_last_error_detail = ""
		return
	_last_error_detail = str(_rusty_core.call("get_last_error_detail"))


func _empty_frontend_snapshot(status: String) -> Dictionary:
	return {
		"mode": "none",
		"status": status,
		"server_tick": 0,
		"client_tick": 0,
		"entities": [],
	}
