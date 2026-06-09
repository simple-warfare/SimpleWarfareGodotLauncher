extends RefCounted
class_name GameCameraController

const MOVE_SPEED := 520.0
const ZOOM_STEP := 0.1

var _camera: Camera2D
var _initialized := false
var _min_zoom := 0.5
var _max_zoom := 2.0


func setup(camera: Camera2D) -> void:
	_camera = camera


func is_initialized() -> bool:
	return _initialized


func apply_map_context(map_context: Dictionary) -> void:
	if _initialized || map_context.is_empty():
		return

	var camera_config := FrontendFrame.dictionary(map_context, "camera")
	var map_size: Vector2 = map_context.get("map_size", Vector2.ZERO)
	_min_zoom = float(camera_config.get("min_zoom", 0.5))
	_max_zoom = float(camera_config.get("max_zoom", 2.0))
	if _min_zoom <= 0.0:
		_min_zoom = 0.5
	if _max_zoom < _min_zoom:
		_max_zoom = _min_zoom

	_camera.position = Vector2(
		float(camera_config.get("start_x", map_size.x * 0.5)),
		float(camera_config.get("start_y", map_size.y * 0.5))
	)
	_camera.zoom = Vector2.ONE
	_camera.limit_left = 0
	_camera.limit_top = 0
	_camera.limit_right = int(map_size.x)
	_camera.limit_bottom = int(map_size.y)
	_initialized = true


func update_movement(delta: float) -> void:
	if !_initialized:
		return

	var direction := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) || Input.is_key_pressed(KEY_LEFT):
		direction.x -= 1.0
	if Input.is_key_pressed(KEY_D) || Input.is_key_pressed(KEY_RIGHT):
		direction.x += 1.0
	if Input.is_key_pressed(KEY_W) || Input.is_key_pressed(KEY_UP):
		direction.y -= 1.0
	if Input.is_key_pressed(KEY_S) || Input.is_key_pressed(KEY_DOWN):
		direction.y += 1.0

	if direction == Vector2.ZERO:
		return

	_camera.position += direction.normalized() * MOVE_SPEED * delta / _camera.zoom.x


func zoom_in() -> void:
	_set_zoom(_camera.zoom.x + ZOOM_STEP)


func zoom_out() -> void:
	_set_zoom(_camera.zoom.x - ZOOM_STEP)


func screen_to_world_position(screen_position: Vector2, viewport: Viewport) -> Vector2:
	return viewport.get_canvas_transform().affine_inverse() * screen_position


func _set_zoom(value: float) -> void:
	var clamped_zoom := clampf(value, _min_zoom, _max_zoom)
	_camera.zoom = Vector2(clamped_zoom, clamped_zoom)
