extends Control

const SNAPSHOT_WARNING_SECONDS := 8.0

@onready var _title: Label = %Title
@onready var _status_value: Label = %StatusValue
@onready var _local_value: Label = %LocalValue
@onready var _slot_list: VBoxContainer = %SlotList
@onready var _start_button: Button = %StartButton
@onready var _leave_button: Button = %LeaveButton

var _wait_seconds := 0.0
var _last_slots_key := ""


func _ready() -> void:
	_start_button.pressed.connect(_start_game)
	_leave_button.pressed.connect(_leave_room)
	_refresh_from_snapshot()


func _process(delta: float) -> void:
	if RustBackend.get_status() == "running":
		RustBackend.update_runtime(delta)
		_wait_seconds += delta

	_refresh_from_snapshot()


func _refresh_from_snapshot() -> void:
	var snapshot := RustBackend.get_frontend_snapshot()
	var room := _snapshot_room(snapshot)
	var slots := _room_slots(room)
	var local_is_host := _local_is_host(slots)
	var server_tick := int(snapshot.get("server_tick", 0))
	var client_tick := int(snapshot.get("client_tick", 0))

	_title.text = _mode_title()
	_status_value.text = "status=%s server_tick=%s client_tick=%s result=%s" % [
		snapshot.get("status", "unknown"),
		server_tick,
		client_tick,
		RustBackend.get_last_result(),
	]

	if AppState.launch_mode == AppState.LaunchMode.CLIENT && server_tick <= 0:
		_status_value.text += "\nwaiting for server %s (%.1fs)" % [AppState.server_addr, _wait_seconds]
		if _wait_seconds >= SNAPSHOT_WARNING_SECONDS:
			_status_value.text += "\nno server snapshot yet"

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

	_start_button.disabled = !local_is_host
	_refresh_slots(slots)


func _snapshot_room(snapshot: Dictionary) -> Dictionary:
	var room_value: Variant = snapshot.get("room", {})
	if typeof(room_value) != TYPE_DICTIONARY:
		return {}
	var room: Dictionary = room_value
	return room


func _room_slots(room: Dictionary) -> Array:
	var slots_value: Variant = room.get("player_slots", [])
	if typeof(slots_value) != TYPE_ARRAY:
		return []
	var slots: Array = slots_value
	return slots


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

	return "%s | team=%s | %s" % [
		slot.get("player_key", "unknown"),
		team,
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
	SceneRouter.go_to_game()


func _leave_room() -> void:
	RustBackend.shutdown()
	AppState.clear_runtime_session()
	SceneRouter.go_to_main_menu()
