extends RefCounted
class_name GameInputController

var _hud: Control
var _camera: GameCameraController


func setup(hud: Control, camera: GameCameraController) -> void:
	_hud = hud
	_camera = camera


func handle_input(
	event: InputEvent,
	viewport: Viewport,
	select_unit_at: Callable,
	issue_move_to: Callable
) -> void:
	if !_camera.is_initialized():
		return
	if !(event is InputEventMouseButton):
		return

	var mouse_event: InputEventMouseButton = event
	if !mouse_event.pressed || _is_over_hud(mouse_event.position):
		return

	if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_camera.zoom_in()
		viewport.set_input_as_handled()
	elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_camera.zoom_out()
		viewport.set_input_as_handled()
	elif mouse_event.button_index == MOUSE_BUTTON_LEFT:
		select_unit_at.call(_world_position(mouse_event.position, viewport))
		viewport.set_input_as_handled()
	elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		issue_move_to.call(_world_position(mouse_event.position, viewport))
		viewport.set_input_as_handled()


func _is_over_hud(screen_position: Vector2) -> bool:
	return _hud.get_global_rect().has_point(screen_position)


func _world_position(screen_position: Vector2, viewport: Viewport) -> Vector2:
	return _camera.screen_to_world_position(screen_position, viewport)
