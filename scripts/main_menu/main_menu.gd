extends Control

const DEFAULT_SERVER_ADDR := "127.0.0.1:5888"

@onready var _status_value: Label = %StatusValue
@onready var _singleplayer_button: Button = %SingleplayerButton
@onready var _host_button: Button = %HostButton
@onready var _join_address_input: LineEdit = %JoinAddressInput
@onready var _join_button: Button = %JoinButton
@onready var _diagnostics_button: Button = %DiagnosticsButton
@onready var _mods_button: Button = %ModsButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton


func _ready() -> void:
	_join_address_input.text = DEFAULT_SERVER_ADDR
	_join_address_input.text_submitted.connect(_join_remote_game_from_text)
	_singleplayer_button.pressed.connect(_start_singleplayer)
	_host_button.pressed.connect(_start_host)
	_join_button.pressed.connect(_join_remote_game)
	_diagnostics_button.pressed.connect(RustBackend.open_diagnostics_panel)
	_mods_button.pressed.connect(_open_mods)
	_settings_button.pressed.connect(_open_settings)
	_quit_button.pressed.connect(_quit)

	_refresh_status()


func _process(delta: float) -> void:
	if RustBackend.get_status() != "running":
		return

	RustBackend.update_runtime(delta)
	_refresh_status()


func _refresh_status() -> void:
	var rust_state := "ready" if AppState.rust_ready else "unavailable"
	var assets_state := "ready" if AppState.assets_ready else "unavailable"
	var snapshot := RustBackend.get_frontend_snapshot()
	var units: Array = snapshot.get("units", [])
	var first_unit_text := "none"

	if !units.is_empty() && typeof(units[0]) == TYPE_DICTIONARY:
		var first_unit: Dictionary = units[0]
		first_unit_text = "%s#%s pos=(%s, %s) hp=%s" % [
			first_unit.get("kind", "unknown"),
			first_unit.get("id", 0),
			first_unit.get("x", 0.0),
			first_unit.get("y", 0.0),
			first_unit.get("health", 0),
		]

	_status_value.text = "Rust: %s | Assets: %s | Mode: %s | Result: %s\nSnapshot: status=%s server_tick=%s client_tick=%s units=%s first=%s" % [
		rust_state,
		assets_state,
		snapshot.get("mode", RustBackend.get_runtime_mode()),
		RustBackend.get_last_result(),
		snapshot.get("status", "unknown"),
		snapshot.get("server_tick", 0),
		snapshot.get("client_tick", 0),
		units.size(),
		first_unit_text,
	]

	var error_detail := str(RustBackend.get_last_error_detail())
	if !error_detail.is_empty():
		_status_value.text += "\nError: %s" % error_detail

	var diagnostics_text := RustBackend.get_recent_diagnostics_text(4)
	if !diagnostics_text.is_empty():
		_status_value.text += "\nDiagnostics:\n%s" % diagnostics_text
	if !AppState.last_error.is_empty():
		_status_value.text += "\nNotice: %s" % AppState.last_error

	_refresh_action_state()


func _refresh_action_state() -> void:
	var can_start_runtime := RustBackend.is_available() && AppState.assets_ready
	var is_running := RustBackend.get_status() == "running"
	_singleplayer_button.disabled = !can_start_runtime || is_running
	_host_button.disabled = !can_start_runtime || is_running
	_join_button.disabled = !can_start_runtime || is_running
	_join_address_input.editable = can_start_runtime && !is_running


func _start_singleplayer() -> void:
	AppState.clear_error()
	var result := RustBackend.start_singleplayer()
	if bool(result.get("ok", false)):
		AppState.launch_mode = AppState.LaunchMode.SINGLEPLAYER
		AppState.server_addr = ""
		SceneRouter.go_to_game()
		return
	_refresh_status()


func _start_host() -> void:
	AppState.clear_error()
	var result := RustBackend.start_host()
	if bool(result.get("ok", false)):
		AppState.launch_mode = AppState.LaunchMode.HOST
		AppState.server_addr = DEFAULT_SERVER_ADDR
		SceneRouter.go_to_room()
		return
	_refresh_status()


func _join_remote_game_from_text(_submitted_text: String) -> void:
	_join_remote_game()


func _join_remote_game() -> void:
	AppState.clear_error()
	var server_addr := _join_address_input.text.strip_edges()
	if server_addr.is_empty():
		server_addr = DEFAULT_SERVER_ADDR
		_join_address_input.text = server_addr

	var result := RustBackend.start_client(server_addr)
	if bool(result.get("ok", false)):
		AppState.launch_mode = AppState.LaunchMode.CLIENT
		AppState.server_addr = server_addr
		SceneRouter.go_to_room()
		return
	else:
		AppState.clear_runtime_session()
	_refresh_status()


func _open_mods() -> void:
	_show_not_implemented("Mods scene will be migrated after SceneRouter/AppState are stable.")


func _open_settings() -> void:
	_show_not_implemented("Settings scene will be migrated after SceneRouter/AppState are stable.")


func _quit() -> void:
	get_tree().quit()


func _show_not_implemented(message: String) -> void:
	AppState.set_error(message)
	_refresh_status()
