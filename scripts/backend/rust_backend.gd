extends Node

# Rust 状态变化后通知 UI 刷新，避免界面层主动轮询 Rust 状态。
signal state_changed

var _rusty_core: Object
var _available := false
var _last_result := "not_initialized"
var _last_error_detail := ""
var _diagnostics_window: Window
var _diagnostics_text: TextEdit
var _diagnostics_status_label: Label
var _diagnostics_level_filter: OptionButton
var _diagnostics_target_filter: LineEdit


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


func get_diagnostics_snapshot() -> Dictionary:
	if !_available:
		return _empty_diagnostics_snapshot()

	var diagnostics = _rusty_core.call("get_diagnostics_snapshot")
	if typeof(diagnostics) != TYPE_DICTIONARY:
		return _empty_diagnostics_snapshot()

	return diagnostics


func get_latest_diagnostic_summary() -> String:
	var entries := _diagnostic_entries()
	if entries.is_empty():
		return ""

	var entry_value: Variant = entries[entries.size() - 1]
	if typeof(entry_value) != TYPE_DICTIONARY:
		return ""

	var entry: Dictionary = entry_value
	return "#%s %s %s" % [
		entry.get("sequence", 0),
		entry.get("level", "info"),
		entry.get("message", ""),
	]


func get_recent_diagnostics_text(limit: int = 5, min_level: String = "", target_filter: String = "") -> String:
	var diagnostics := get_diagnostics_snapshot()
	return _format_diagnostics_snapshot(diagnostics, limit, min_level, target_filter)


func open_diagnostics_panel() -> void:
	if _diagnostics_window == null || !is_instance_valid(_diagnostics_window):
		_create_diagnostics_panel()

	_refresh_diagnostics_panel()
	_diagnostics_window.popup_centered(Vector2i(920, 640))


func export_diagnostics() -> String:
	var export_path := "user://rust_diagnostics.log"
	var file := FileAccess.open(export_path, FileAccess.WRITE)
	if file == null:
		var error_message := "failed to export diagnostics: %s" % error_string(FileAccess.get_open_error())
		_set_diagnostics_status(error_message)
		return ""

	file.store_string(get_recent_diagnostics_text(128, _current_diagnostics_min_level(), _current_diagnostics_target_filter()))
	var global_path := ProjectSettings.globalize_path(export_path)
	_set_diagnostics_status("exported to %s" % global_path)
	return global_path


func copy_diagnostics_to_clipboard() -> void:
	DisplayServer.clipboard_set(get_recent_diagnostics_text(128, _current_diagnostics_min_level(), _current_diagnostics_target_filter()))
	_set_diagnostics_status("copied diagnostics to clipboard")


func clear_diagnostics() -> void:
	if _available:
		_rusty_core.call("clear_diagnostics")
	_refresh_diagnostics_panel()


func _format_diagnostics_snapshot(diagnostics: Dictionary, limit: int, min_level: String = "", target_filter: String = "") -> String:
	var entries := _filter_diagnostic_entries(
		_diagnostic_entries_from_snapshot(diagnostics),
		min_level,
		target_filter
	)
	var lines := PackedStringArray()
	var dropped_count := int(diagnostics.get("dropped_count", 0))
	var latest_panic := str(diagnostics.get("latest_panic", ""))
	if dropped_count > 0:
		lines.append("dropped_count=%s" % dropped_count)
	if !latest_panic.is_empty():
		lines.append("latest_panic=%s" % latest_panic)
	if entries.is_empty() || limit <= 0:
		return "\n".join(lines)

	var start_index: int = max(0, entries.size() - limit)
	for index in range(start_index, entries.size()):
		var entry: Dictionary = entries[index]
		lines.append("#%s %s %s: %s" % [
			entry.get("sequence", 0),
			entry.get("level", "info"),
			entry.get("target", "rust"),
			entry.get("message", ""),
		])

	return "\n".join(lines)


func get_frontend_snapshot() -> Dictionary:
	if !_available:
		return _empty_frontend_snapshot("unavailable")

	var snapshot = _rusty_core.call("get_frontend_snapshot")
	if typeof(snapshot) != TYPE_DICTIONARY:
		return _empty_frontend_snapshot("invalid_snapshot")

	return snapshot


func initialize_with_assets_path(assets_path: String) -> Dictionary:
	return initialize_with_paths(assets_path, assets_path.path_join("content_packages/official_base_game"))


func initialize_with_paths(assets_path: String, content_package_path: String) -> Dictionary:
	if !_available:
		var result := _runtime_result(false, "rusty_core_unavailable", "RustyCore class is not available.")
		_store_runtime_result(result)
		state_changed.emit()
		return result

	if assets_path.is_empty():
		var result := _runtime_result(false, "invalid_assets_root", "assets path is empty before calling Rust.")
		_store_runtime_result(result)
		state_changed.emit()
		return result

	if content_package_path.is_empty():
		var result := _runtime_result(false, "invalid_content_root", "content package path is empty before calling Rust.")
		_store_runtime_result(result)
		state_changed.emit()
		return result

	# Godot 的 user:// 是虚拟路径；传给 Rust 前必须转成平台真实路径。
	var result := _store_runtime_result(_rusty_core.call("initialize_with_paths", assets_path, content_package_path))
	state_changed.emit()
	return result


func start_singleplayer() -> Dictionary:
	return _call_runtime_mode("start_singleplayer")


func start_host() -> Dictionary:
	return _call_runtime_mode("start_host")


func start_client(server_addr: String) -> Dictionary:
	if !_available:
		var result := _runtime_result(false, "rusty_core_unavailable", "RustyCore class is not available.")
		_store_runtime_result(result)
		state_changed.emit()
		return result

	# Rust runtime 会启动 UDP client；菜单层负责等待首个 server snapshot 后进入游戏场景。
	var result := _store_runtime_result(_rusty_core.call("start_client", server_addr))
	state_changed.emit()
	return result


func shutdown() -> Dictionary:
	if !_available:
		var result := _runtime_result(false, "rusty_core_unavailable", "RustyCore class is not available.")
		_store_runtime_result(result)
		state_changed.emit()
		return result

	var result := _store_runtime_result(_rusty_core.call("shutdown"))
	state_changed.emit()
	return result


func update_runtime(delta_seconds: float) -> Dictionary:
	if !_available:
		return _store_runtime_result(_runtime_result(false, "rusty_core_unavailable", "RustyCore class is not available."))

	# 只有进入运行态后才每帧推进 Rust，避免菜单空闲时刷出 not_running。
	if get_status() != "running":
		return _runtime_result(_last_result == "ok", _last_result, _last_error_detail)

	return _store_runtime_result(_rusty_core.call("update", delta_seconds))


func issue_move_command(entity_id: int, target_position: Vector2) -> Dictionary:
	return submit_player_command({
		"type": "move_entity",
		"entity_id": entity_id,
		"target_x": target_position.x,
		"target_y": target_position.y,
	})


func issue_stop_command(entity_id: int) -> Dictionary:
	return submit_player_command({
		"type": "stop_entity",
		"entity_id": entity_id,
	})


func issue_produce_unit_command(producer_entity_id: int, unit: String) -> Dictionary:
	return submit_player_command({
		"type": "produce_unit",
		"producer_entity_id": producer_entity_id,
		"unit": unit,
	})


func issue_start_game_command() -> Dictionary:
	return submit_player_command({
		"type": "start_game",
	})


func submit_player_command(command: Dictionary) -> Dictionary:
	if !_available:
		return _command_feedback(false, "rejected", "rusty_core_unavailable", "RustyCore class is not available.")

	if get_status() != "running":
		return _command_feedback(false, "rejected", "not_running", "Rust runtime is not running.")

	# 跨语言边界只传基础 Dictionary，避免 Godot 对象泄漏进 Rust 核心接口。
	var feedback = _rusty_core.call("submit_player_command", command)
	if typeof(feedback) != TYPE_DICTIONARY:
		return _command_feedback(false, "rejected", "invalid_command_feedback", "Rust returned an invalid command feedback value.")

	var command_feedback: Dictionary = feedback
	return _store_command_feedback(command_feedback)


func _call_runtime_mode(method_name: String) -> Dictionary:
	if !_available:
		var result := _runtime_result(false, "rusty_core_unavailable", "RustyCore class is not available.")
		_store_runtime_result(result)
		state_changed.emit()
		return result

	var result := _store_runtime_result(_rusty_core.call(method_name))
	state_changed.emit()
	return result


func _command_feedback(accepted: bool, status: String, rejected_reason: String, detail: String) -> Dictionary:
	_last_result = status
	_last_error_detail = detail
	return {
		"accepted": accepted,
		"status": status,
		"command_id": 0,
		"sequence": 0,
		"rejected_reason": rejected_reason,
		"detail": detail,
	}


func _store_command_feedback(feedback: Dictionary) -> Dictionary:
	_last_result = str(feedback.get("status", "rejected"))
	_last_error_detail = str(feedback.get("detail", ""))
	return feedback


func _runtime_result(ok: bool, code: String, detail: String) -> Dictionary:
	return {
		"ok": ok,
		"code": code,
		"detail": detail,
	}


func _store_runtime_result(result_value: Variant) -> Dictionary:
	var result := _runtime_result(false, "invalid_runtime_result", "Rust returned an invalid runtime result value.")
	if typeof(result_value) == TYPE_DICTIONARY:
		var dictionary: Dictionary = result_value
		result = _runtime_result(
			bool(dictionary.get("ok", false)),
			str(dictionary.get("code", "invalid_runtime_result")),
			str(dictionary.get("detail", ""))
		)

	_last_result = str(result.get("code", "invalid_runtime_result"))
	_last_error_detail = str(result.get("detail", ""))
	return result


func _empty_frontend_snapshot(status: String) -> Dictionary:
	return {
		"mode": "none",
		"status": status,
		"server_tick": 0,
		"client_tick": 0,
		"commands": {
			"pending_count": 0,
			"acknowledged_count": 0,
			"last_acknowledged_command_id": 0,
			"last_acknowledged_sequence": 0,
			"last_applied_command_id": 0,
			"last_applied_sequence": 0,
			"last_result_status": "",
			"last_rejected_reason": "",
			"last_rejected_detail": "",
		},
		"room": {
			"phase": "lobby",
			"local_player_key": "",
			"local_team_id": -1,
			"player_slots": [],
		},
		"resources": {
			"team_id": -1,
			"amounts": [],
		},
		"objects": [],
		"units": [],
	}


func _create_diagnostics_panel() -> void:
	_diagnostics_window = Window.new()
	_diagnostics_window.title = "Rust Diagnostics"
	_diagnostics_window.size = Vector2i(920, 640)
	_diagnostics_window.min_size = Vector2i(640, 420)
	_diagnostics_window.close_requested.connect(_close_diagnostics_panel)
	get_tree().root.add_child(_diagnostics_window)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_diagnostics_window.add_child(root)

	var header := Label.new()
	header.text = "Recent Rust diagnostics"
	header.add_theme_font_size_override("font_size", 18)
	root.add_child(header)

	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 8)
	root.add_child(filters)

	var level_label := Label.new()
	level_label.text = "Level"
	filters.add_child(level_label)

	_diagnostics_level_filter = OptionButton.new()
	for label in ["All", "Trace", "Debug", "Info", "Warn", "Error"]:
		_diagnostics_level_filter.add_item(label)
	_diagnostics_level_filter.item_selected.connect(_on_diagnostics_filter_changed)
	filters.add_child(_diagnostics_level_filter)

	var target_label := Label.new()
	target_label.text = "Target"
	filters.add_child(target_label)

	_diagnostics_target_filter = LineEdit.new()
	_diagnostics_target_filter.placeholder_text = "substring"
	_diagnostics_target_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_diagnostics_target_filter.text_changed.connect(_on_diagnostics_filter_changed)
	filters.add_child(_diagnostics_target_filter)

	_diagnostics_text = TextEdit.new()
	_diagnostics_text.editable = false
	_diagnostics_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_diagnostics_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_diagnostics_text)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	root.add_child(actions)

	actions.add_child(_make_diagnostics_button("Refresh", _refresh_diagnostics_panel))
	actions.add_child(_make_diagnostics_button("Copy", copy_diagnostics_to_clipboard))
	actions.add_child(_make_diagnostics_button("Export", export_diagnostics))
	actions.add_child(_make_diagnostics_button("Clear", clear_diagnostics))
	actions.add_child(_make_diagnostics_button("Close", _close_diagnostics_panel))

	_diagnostics_status_label = Label.new()
	_diagnostics_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_diagnostics_status_label)


func _make_diagnostics_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	return button


func _refresh_diagnostics_panel() -> void:
	if _diagnostics_text == null || !is_instance_valid(_diagnostics_text):
		return

	var text := get_recent_diagnostics_text(128, _current_diagnostics_min_level(), _current_diagnostics_target_filter())
	if text.is_empty():
		text = "No Rust diagnostics recorded."
	_diagnostics_text.text = text


func _on_diagnostics_filter_changed(_value: Variant = null) -> void:
	_refresh_diagnostics_panel()


func _close_diagnostics_panel() -> void:
	if _diagnostics_window != null && is_instance_valid(_diagnostics_window):
		_diagnostics_window.hide()


func _set_diagnostics_status(message: String) -> void:
	if _diagnostics_status_label != null && is_instance_valid(_diagnostics_status_label):
		_diagnostics_status_label.text = message


func _diagnostic_entries() -> Array:
	var diagnostics := get_diagnostics_snapshot()
	return _diagnostic_entries_from_snapshot(diagnostics)


func _diagnostic_entries_from_snapshot(diagnostics: Dictionary) -> Array:
	var entries_value: Variant = diagnostics.get("entries", [])
	if typeof(entries_value) != TYPE_ARRAY:
		return []

	var entries: Array = entries_value
	return entries


func _filter_diagnostic_entries(entries: Array, min_level: String, target_filter: String) -> Array[Dictionary]:
	var filtered: Array[Dictionary] = []
	var min_level_rank := _diagnostic_level_rank(min_level)
	var target_query := target_filter.strip_edges().to_lower()

	for entry_value in entries:
		if typeof(entry_value) != TYPE_DICTIONARY:
			continue

		var entry: Dictionary = entry_value
		if min_level_rank >= 0 && _diagnostic_level_rank(str(entry.get("level", "info"))) < min_level_rank:
			continue
		if !target_query.is_empty() && !str(entry.get("target", "rust")).to_lower().contains(target_query):
			continue

		filtered.append(entry)

	return filtered


func _diagnostic_level_rank(level: String) -> int:
	match level.strip_edges().to_lower():
		"trace":
			return 0
		"debug":
			return 1
		"info":
			return 2
		"warn", "warning":
			return 3
		"error":
			return 4
		_:
			return -1


func _current_diagnostics_min_level() -> String:
	if _diagnostics_level_filter == null || !is_instance_valid(_diagnostics_level_filter):
		return ""

	return _diagnostics_level_filter.get_item_text(_diagnostics_level_filter.selected)


func _current_diagnostics_target_filter() -> String:
	if _diagnostics_target_filter == null || !is_instance_valid(_diagnostics_target_filter):
		return ""

	return _diagnostics_target_filter.text


func _empty_diagnostics_snapshot() -> Dictionary:
	return {
		"capacity": 0,
		"dropped_count": 0,
		"latest_panic": "",
		"entries": [],
	}
