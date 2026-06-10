extends Control

const ResourceBootstrapScript := preload("res://scripts/bootstrap/resource_bootstrap.gd")

@onready var _version_value: Label = %VersionValue
@onready var _status_value: Label = %StatusValue
@onready var _result_value: Label = %ResultValue
@onready var _assets_status_value: Label = %AssetsStatusValue
@onready var _assets_result_value: Label = %AssetsResultValue
@onready var _initialize_button: Button = %InitializeButton
@onready var _shutdown_button: Button = %ShutdownButton

var _resource_bootstrap := ResourceBootstrapScript.new()


func _ready() -> void:
	RustBackend.state_changed.connect(_refresh_backend_status)
	_initialize_button.pressed.connect(_initialize_backend)
	_shutdown_button.pressed.connect(_shutdown_backend)

	_initialize_resources()


func _initialize_backend() -> void:
	RustBackend.initialize_with_paths(_get_assets_root(), _get_official_content_package_root())


func _shutdown_backend() -> void:
	RustBackend.shutdown()


func _refresh_backend_status() -> void:
	_version_value.text = RustBackend.get_version() if RustBackend.is_available() else "unavailable"
	_status_value.text = RustBackend.get_status()
	_result_value.text = _format_backend_result()
	_initialize_button.disabled = !RustBackend.is_available() || RustBackend.is_initialized()
	_shutdown_button.disabled = !RustBackend.is_available() || !RustBackend.is_initialized()


func _initialize_resources() -> void:
	var result := _resource_bootstrap.ensure_ready()
	_assets_status_value.text = str(result.status)
	_assets_result_value.text = str(result.message)

	# 资源目录创建成功后，再把 Godot 的虚拟路径转换成真实路径交给 Rust。
	if result.ok && RustBackend.is_available() && !RustBackend.is_initialized():
		RustBackend.initialize_with_paths(_get_assets_root(), _get_official_content_package_root())

	AppState.set_bootstrap_status(bool(result.ok), RustBackend.is_initialized())

	if result.ok && RustBackend.is_initialized():
		SceneRouter.call_deferred("go_to_main_menu")


func _format_backend_result() -> String:
	var result := RustBackend.get_last_result()
	var detail := RustBackend.get_last_error_detail()
	if detail.is_empty():
		return result
	return "%s: %s" % [result, detail]


func _get_assets_root() -> String:
	return ProjectSettings.globalize_path("user://assets")


func _get_official_content_package_root() -> String:
	return ProjectSettings.globalize_path("user://assets/content_packages/official")
