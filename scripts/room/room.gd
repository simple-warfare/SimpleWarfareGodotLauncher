extends Control

const FRAME_WARNING_SECONDS := 8.0

@onready var _title: Label = %Title
@onready var _status_value: Label = %StatusValue
@onready var _local_value: Label = %LocalValue
@onready var _content_value: Label = %ContentValue
@onready var _slot_list: VBoxContainer = %SlotList
@onready var _start_button: Button = %StartButton
@onready var _diagnostics_button: Button = %DiagnosticsButton
@onready var _leave_button: Button = %LeaveButton

var _wait_seconds := 0.0
var _last_slots_key := ""
var _start_requested := false
var _start_command_id := 0
var _start_wait_seconds := 0.0
var _start_status := ""
var _routing_to_game := false


func _ready() -> void:
	_start_button.pressed.connect(_start_game)
	_diagnostics_button.pressed.connect(RustBackend.open_diagnostics_panel)
	_leave_button.pressed.connect(_leave_room)
	_refresh_from_frame()


func _process(delta: float) -> void:
	if RustBackend.get_status() == "running":
		RustBackend.update_runtime(delta)
		_wait_seconds += delta
		if _start_requested:
			_start_wait_seconds += delta

	_refresh_from_frame()


func _refresh_from_frame() -> void:
	var frame := RustBackend.get_frontend_frame()
	var room := FrontendFrame.room(frame)
	var network := FrontendFrame.network(frame)
	var commands := FrontendFrame.commands(frame)
	var slots := _room_slots(room)
	var phase := _effective_room_phase(room, network)
	var local_is_host := _local_is_host(slots)
	var server_tick := FrontendFrame.server_tick(frame)
	var client_tick := FrontendFrame.client_tick(frame)

	_refresh_start_request_state(commands, phase)

	if phase == "in_game":
		_route_to_game_when_started()
		return

	_title.text = _mode_title()
	_status_value.text = "phase=%s status=%s server_tick=%s client_tick=%s result=%s" % [
		phase,
		FrontendFrame.status(frame),
		server_tick,
		client_tick,
		RustBackend.get_last_result(),
	]
	var latest_diagnostic := RustBackend.get_latest_diagnostic_summary()
	if !latest_diagnostic.is_empty():
		_status_value.text += "\ndiag=%s" % latest_diagnostic
	if !_start_status.is_empty():
		_status_value.text += "\nstart=%s" % _start_status
	var network_summary := _network_summary(network)
	if !network_summary.is_empty():
		_status_value.text += "\nnetwork=%s" % network_summary

	if AppState.launch_mode == AppState.LaunchMode.CLIENT && server_tick <= 0:
		_status_value.text += "\nwaiting for server %s (%.1fs)" % [AppState.server_addr, _wait_seconds]
		if _wait_seconds >= FRAME_WARNING_SECONDS:
			_status_value.text += "\nno server frame yet"

	var local_player_key := str(room.get("local_player_key", ""))
	if local_player_key.is_empty():
		local_player_key = "none"

	var local_team_id := int(room.get("local_team_id", -1))
	var local_team := "none"
	if local_team_id >= 0:
		local_team = str(local_team_id)

	_local_value.text = "player=%s team=%s host=%s slots=%s" % [
		local_player_key,
		local_team,
		"yes" if local_is_host else "no",
		slots.size(),
	]
	_content_value.text = _content_summary(room, slots)

	_start_button.disabled = !local_is_host || phase != "lobby" || _start_requested || !_content_ready(room, slots)
	_refresh_slots(slots)


func _effective_room_phase(room: Dictionary, network: Dictionary) -> String:
	var room_phase := str(room.get("phase", ""))
	var network_phase := str(network.get("room_phase", ""))
	if room_phase == "in_game" || network_phase == "in_game":
		return "in_game"
	if room_phase.is_empty():
		return "lobby"
	return room_phase


func _room_slots(room: Dictionary) -> Array:
	return FrontendFrame.array(room, "player_slots")


func _local_is_host(slots: Array) -> bool:
	for slot_value in slots:
		if typeof(slot_value) != TYPE_DICTIONARY:
			continue
		var slot: Dictionary = slot_value
		if bool(slot.get("is_local", false)) && bool(slot.get("is_host", false)) && bool(slot.get("connected", false)):
			return true
	return AppState.launch_mode == AppState.LaunchMode.HOST && slots.is_empty()


func _mode_title() -> String:
	match AppState.launch_mode:
		AppState.LaunchMode.HOST:
			return "Host Room"
		AppState.LaunchMode.CLIENT:
			return "Join Room"
		_:
			return "Room"


func _refresh_slots(slots: Array) -> void:
	var slots_key := str(slots)
	if slots_key == _last_slots_key:
		return

	_last_slots_key = slots_key
	for child in _slot_list.get_children():
		child.queue_free()

	if slots.is_empty():
		_slot_list.add_child(_make_slot_label("No player slots yet"))
		return

	for slot_value in slots:
		if typeof(slot_value) != TYPE_DICTIONARY:
			continue
		var slot: Dictionary = slot_value
		_slot_list.add_child(_make_slot_label(_slot_summary(slot)))


func _content_summary(room: Dictionary, slots: Array) -> String:
	var protocol_version := int(room.get("protocol_version", 0))
	var server_content := _room_content(room, "content")
	var local_content := _room_content(room, "local_content")
	var content_state := _content_state_summary(room, slots)
	return "protocol=%s server=%s local=%s status=%s" % [
		protocol_version,
		_content_brief(server_content),
		_content_brief(local_content),
		content_state,
	]


func _room_content(room: Dictionary, key: String) -> Dictionary:
	var content_value: Variant = room.get(key, {})
	if typeof(content_value) != TYPE_DICTIONARY:
		return {}
	var content: Dictionary = content_value
	return content


func _content_brief(content: Dictionary) -> String:
	if content.is_empty():
		return "unknown"

	var package_id := str(content.get("package_id", "unknown"))
	var package_version := str(content.get("package_version", "unknown"))
	var schema_version := int(content.get("schema_version", 0))
	var lock_hash := _short_hash(str(content.get("package_lock_hash", "")))
	return "%s@%s schema=%s lock=%s" % [
		package_id,
		package_version,
		schema_version,
		lock_hash,
	]


func _short_hash(value: String) -> String:
	if value.is_empty():
		return "unknown"
	return value.substr(0, min(8, value.length()))


func _content_state_summary(room: Dictionary, slots: Array) -> String:
	var mismatch := str(room.get("content_mismatch", ""))
	if !mismatch.is_empty():
		return "mismatch %s" % mismatch

	for slot_value in slots:
		if typeof(slot_value) != TYPE_DICTIONARY:
			continue
		var slot: Dictionary = slot_value
		if !bool(slot.get("connected", false)):
			continue
		var status := str(slot.get("content_status", "unknown"))
		if status != "match":
			return "waiting %s=%s" % [slot.get("player_key", "unknown"), status]

	return "match"


func _content_ready(room: Dictionary, slots: Array) -> bool:
	if !str(room.get("content_mismatch", "")).is_empty():
		return false
	if slots.is_empty():
		return true

	for slot_value in slots:
		if typeof(slot_value) != TYPE_DICTIONARY:
			continue
		var slot: Dictionary = slot_value
		if !bool(slot.get("connected", false)):
			continue
		if str(slot.get("content_status", "unknown")) != "match":
			return false

	return true


func _network_summary(network: Dictionary) -> String:
	if network.is_empty():
		return ""
	return "mode=%s replicated=%s predicted=%s results=%s room=%s" % [
		network.get("smoothing_mode", "none"),
		network.get("replicated_unit_count", 0),
		network.get("lightyear_predicted_unit_count", 0),
		network.get("command_result_count", 0),
		network.get("room_phase", "lobby"),
	]


func _slot_summary(slot: Dictionary) -> String:
	var team_id := int(slot.get("team_id", -1))
	var team := "none"
	if team_id >= 0:
		team = str(team_id)

	var flags := PackedStringArray()
	if bool(slot.get("is_local", false)):
		flags.append("local")
	if bool(slot.get("is_host", false)):
		flags.append("host")
	flags.append("connected" if bool(slot.get("connected", false)) else "offline")
	var protocol_version := int(slot.get("protocol_version", 0))
	var content_status := str(slot.get("content_status", "unknown"))
	var mismatch := str(slot.get("content_mismatch", ""))
	if !mismatch.is_empty():
		content_status = "%s:%s" % [content_status, mismatch]

	return "%s | team=%s | protocol=%s | content=%s | %s" % [
		slot.get("player_key", "unknown"),
		team,
		"unknown" if protocol_version == 0 else str(protocol_version),
		content_status,
		", ".join(flags),
	]


func _make_slot_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _start_game() -> void:
	if _start_button.disabled:
		return

	_start_requested = true
	_start_wait_seconds = 0.0
	_start_status = "queued"
	_start_button.disabled = true
	var feedback := RustBackend.issue_start_game_command()
	if !bool(feedback.get("accepted", false)):
		_start_requested = false
		_start_command_id = 0
		_start_status = "rejected: %s %s" % [
			feedback.get("rejected_reason", "unknown"),
			feedback.get("detail", ""),
		]
		push_warning("Rust start_game command rejected: %s %s" % [
			feedback.get("rejected_reason", "unknown"),
			feedback.get("detail", ""),
		])
		return

	_start_command_id = int(feedback.get("command_id", 0))
	_start_status = "queued id=%s" % _start_command_id


func _refresh_start_request_state(commands: Dictionary, phase: String) -> void:
	if phase == "in_game":
		_start_requested = false
		_start_command_id = 0
		_start_wait_seconds = 0.0
		_start_status = ""
		return

	if !_start_requested:
		return

	var pending_count := int(commands.get("pending_count", 0))
	var last_acknowledged_command_id := int(commands.get("last_acknowledged_command_id", 0))
	var last_result_status := str(commands.get("last_result_status", ""))
	if _start_command_id > 0 && last_acknowledged_command_id == _start_command_id && last_result_status == "rejected":
		var rejected_reason := str(commands.get("last_rejected_reason", "unknown"))
		var rejected_detail := str(commands.get("last_rejected_detail", ""))
		_start_requested = false
		_start_status = "rejected: %s %s" % [rejected_reason, rejected_detail]
		push_warning("Rust start_game command rejected asynchronously: %s %s" % [
			rejected_reason,
			rejected_detail,
		])
		return

	if _start_wait_seconds >= FRAME_WARNING_SECONDS:
		_start_status = "pending id=%s pending_count=%s %.1fs" % [
			_start_command_id,
			pending_count,
			_start_wait_seconds,
		]


func _route_to_game_when_started() -> void:
	if _routing_to_game:
		return
	_routing_to_game = true
	_start_status = "routing to game"
	AppState.clear_error()
	SceneRouter.go_to_game()
	if !AppState.last_error.is_empty():
		_routing_to_game = false
		_start_status = "route failed: %s" % AppState.last_error


func _leave_room() -> void:
	RustBackend.shutdown()
	AppState.clear_runtime_session()
	SceneRouter.go_to_main_menu()
