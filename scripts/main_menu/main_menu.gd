extends Control

const DEFAULT_SERVER_ADDR := "127.0.0.1:5888"

@onready var _status_value: Label = %StatusValue
@onready var _singleplayer_button: Button = %SingleplayerButton
@onready var _host_button: Button = %HostButton
@onready var _join_button: Button = %JoinButton
@onready var _mods_button: Button = %ModsButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton


func _ready() -> void:
	_singleplayer_button.pressed.connect(_start_singleplayer)
	_host_button.pressed.connect(_start_host)
	_join_button.pressed.connect(_join_remote_game)
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
	var entities: Array = snapshot.get("entities", [])
	var first_entity_text := "none"

	if !entities.is_empty() && typeof(entities[0]) == TYPE_DICTIONARY:
		var first_entity: Dictionary = entities[0]
		first_entity_text = "%s#%s pos=(%s, %s) hp=%s" % [
			first_entity.get("kind", "unknown"),
			first_entity.get("id", 0),
			first_entity.get("x", 0.0),
			first_entity.get("y", 0.0),
			first_entity.get("health", 0),
		]

	_status_value.text = "Rust: %s | Assets: %s | Mode: %s | Result: %s\nSnapshot: status=%s server_tick=%s client_tick=%s entities=%s first=%s" % [
		rust_state,
		assets_state,
		snapshot.get("mode", RustBackend.get_runtime_mode()),
		RustBackend.get_last_result(),
		snapshot.get("status", "unknown"),
		snapshot.get("server_tick", 0),
		snapshot.get("client_tick", 0),
		entities.size(),
		first_entity_text,
	]


func _start_singleplayer() -> void:
	var result := RustBackend.start_singleplayer()
	if result == "ok":
		AppState.launch_mode = AppState.LaunchMode.SINGLEPLAYER
		SceneRouter.go_to_game()
		return
	_refresh_status()


func _start_host() -> void:
	var result := RustBackend.start_host()
	if result == "ok":
		AppState.launch_mode = AppState.LaunchMode.HOST
	_refresh_status()


func _join_remote_game() -> void:
	var result := RustBackend.start_client(DEFAULT_SERVER_ADDR)
	if result == "ok":
		AppState.launch_mode = AppState.LaunchMode.CLIENT
	_refresh_status()


func _open_mods() -> void:
	_show_not_implemented("Mods scene will be migrated after SceneRouter/AppState are stable.")


func _open_settings() -> void:
	_show_not_implemented("Settings scene will be migrated after SceneRouter/AppState are stable.")


func _quit() -> void:
	get_tree().quit()


func _show_not_implemented(message: String) -> void:
	AppState.set_error(message)
	_status_value.text = message
