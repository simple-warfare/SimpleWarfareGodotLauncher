extends Control

@onready var _world: Node2D = %World
@onready var _camera: Camera2D = %Camera
@onready var _hud: Control = $HudLayer/Hud
@onready var _status_value: Label = %StatusValue
@onready var _debug_value: Label = %DebugValue
@onready var _stop_command_button: Button = %StopCommandButton
@onready var _produce_command_button: Button = %ProduceCommandButton
@onready var _diagnostics_button: Button = %DiagnosticsButton

var _selection := GameSelectionState.new()
var _asset_resolver := GameAssetResolver.new()
var _map_renderer := GameMapRenderer.new()
var _unit_renderer := GameUnitRenderer.new()
var _hud_presenter := GameHudPresenter.new()
var _camera_controller := GameCameraController.new()
var _input_controller := GameInputController.new()


func _ready() -> void:
	_camera_controller.setup(_camera)
	_input_controller.setup(_hud, _camera_controller)
	_map_renderer.setup(_world, _asset_resolver)
	_unit_renderer.setup(_world, _asset_resolver)
	_hud_presenter.setup(
		_status_value,
		_debug_value,
		_stop_command_button,
		_produce_command_button
	)
	_stop_command_button.pressed.connect(_issue_stop_command)
	_produce_command_button.pressed.connect(_issue_produce_unit_command)
	_diagnostics_button.pressed.connect(RustBackend.open_diagnostics_panel)
	_refresh_from_frame()


func _process(delta: float) -> void:
	RustBackend.update_runtime(delta)
	_refresh_from_frame()
	_camera_controller.update_movement(delta)


func _refresh_from_frame() -> void:
	var frame := RustBackend.get_frontend_frame()
	_asset_resolver.set_content_package_root(FrontendFrame.content_package_root(frame))
	var units := FrontendFrame.units(frame)
	var objects := FrontendFrame.objects(frame)
	var map := FrontendFrame.map(frame)
	var resources := FrontendFrame.resources(frame)
	var commands := FrontendFrame.commands(frame)
	var room := FrontendFrame.room(frame)
	_map_renderer.refresh_map(map)
	_map_renderer.refresh_objects(objects)
	_unit_renderer.refresh_units(units)
	_unit_renderer.refresh_selection(_selection.selected_unit_id)
	_selection.refresh_unit_snapshots(units)
	_hud_presenter.refresh_status(
		frame,
		_selection,
		units.size(),
		RustBackend.get_latest_diagnostic_summary()
	)


func _input(event: InputEvent) -> void:
	_input_controller.handle_input(
		event,
		get_viewport(),
		Callable(self, "_select_unit_at_world_position"),
		Callable(self, "_issue_move_command_at_world_position")
	)


func _select_unit_at_world_position(world_position: Vector2) -> void:
	_selection.select_at_world_position(world_position)
	_unit_renderer.refresh_selection(_selection.selected_unit_id)
	_hud_presenter.refresh_command_controls(_selection)


func _issue_move_command_at_world_position(target_position: Vector2) -> void:
	if !_selection.has_selected_unit():
		return
	if !_selection.selected_unit_can_control():
		push_warning("Selected unit is not controlled by this player.")
		return

	var feedback := RustBackend.issue_move_command(_selection.selected_unit_id, target_position)
	if !bool(feedback.get("accepted", false)):
		push_warning("Rust move command rejected: %s %s" % [
			feedback.get("rejected_reason", "unknown"),
			feedback.get("detail", ""),
		])
		return


func _issue_stop_command() -> void:
	if !_selection.has_selected_unit():
		return
	if !_selection.selected_unit_can_control():
		push_warning("Selected unit is not controlled by this player.")
		return

	var feedback := RustBackend.issue_stop_command(_selection.selected_unit_id)
	if !bool(feedback.get("accepted", false)):
		push_warning("Rust stop command rejected: %s %s" % [
			feedback.get("rejected_reason", "unknown"),
			feedback.get("detail", ""),
		])
		return

	_hud_presenter.disable_stop_command()


func _issue_produce_unit_command() -> void:
	if !_selection.has_selected_unit():
		return
	if !_selection.selected_unit_can_control():
		push_warning("Selected unit is not controlled by this player.")
		return

	var build_option := _selection.selected_unit_primary_build_option()
	if build_option.is_empty():
		push_warning("Selected unit has no production option.")
		return

	var unit := str(build_option.get("unit", ""))
	var feedback := RustBackend.issue_produce_unit_command(_selection.selected_unit_id, unit)
	if !bool(feedback.get("accepted", false)):
		push_warning("Rust produce command rejected: %s %s" % [
			feedback.get("rejected_reason", "unknown"),
			feedback.get("detail", ""),
		])
		return

	_hud_presenter.disable_produce_command()
