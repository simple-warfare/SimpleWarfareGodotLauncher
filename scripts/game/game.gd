extends Control

const UNIT_SIZE := Vector2(32.0, 32.0)
const CAMERA_MOVE_SPEED := 520.0
const CAMERA_ZOOM_STEP := 0.1
const SELECTION_PADDING := 6.0

@onready var _world: Node2D = %World
@onready var _camera: Camera2D = %Camera
@onready var _status_value: Label = %StatusValue

var _entity_nodes: Dictionary = {}
var _entity_snapshots: Dictionary = {}
var _selected_entity_id := 0
var _map_bounds: Line2D
var _camera_initialized := false
var _camera_min_zoom := 0.5
var _camera_max_zoom := 2.0


func _ready() -> void:
	_refresh_from_snapshot()


func _process(delta: float) -> void:
	RustBackend.update_runtime(delta)
	_refresh_from_snapshot()
	_handle_camera_movement(delta)


func _refresh_from_snapshot() -> void:
	var snapshot := RustBackend.get_frontend_snapshot()
	var entities: Array = snapshot.get("entities", [])
	var map: Dictionary = _snapshot_map(snapshot)
	_refresh_map(map)

	var alive_entity_ids := {}
	for entity in entities:
		if typeof(entity) != TYPE_DICTIONARY:
			continue

		var entity_id := int(entity.get("id", 0))
		if entity_id == 0:
			continue

		alive_entity_ids[entity_id] = true
		_entity_snapshots[entity_id] = entity
		_update_entity_node(entity_id, entity)

	_remove_missing_entities(alive_entity_ids)
	_status_value.text = "map=%s mode=%s status=%s server_tick=%s client_tick=%s entities=%s selected=%s" % [
		map.get("title", "unknown"),
		snapshot.get("mode", "none"),
		snapshot.get("status", "unknown"),
		snapshot.get("server_tick", 0),
		snapshot.get("client_tick", 0),
		entities.size(),
		_selected_entity_summary(),
	]


func _snapshot_map(snapshot: Dictionary) -> Dictionary:
	var map_value: Variant = snapshot.get("map", {})
	if typeof(map_value) != TYPE_DICTIONARY:
		return {}
	var map: Dictionary = map_value
	return map


func _refresh_map(map: Dictionary) -> void:
	if map.is_empty():
		return

	var width: float = float(map.get("width", 0))
	var height: float = float(map.get("height", 0))
	var tile_size: float = float(map.get("tile_size", 0))
	if width <= 0.0 || height <= 0.0 || tile_size <= 0.0:
		return

	var map_size: Vector2 = Vector2(width * tile_size, height * tile_size)
	var bounds: Line2D = _get_or_create_map_bounds()
	bounds.points = PackedVector2Array([
		Vector2.ZERO,
		Vector2(map_size.x, 0.0),
		map_size,
		Vector2(0.0, map_size.y),
		Vector2.ZERO,
	])
	_apply_camera_config(map, map_size)


func _apply_camera_config(map: Dictionary, map_size: Vector2) -> void:
	if _camera_initialized:
		return

	var camera: Dictionary = _map_camera(map)
	_camera_min_zoom = float(camera.get("min_zoom", 0.5))
	_camera_max_zoom = float(camera.get("max_zoom", 2.0))
	if _camera_min_zoom <= 0.0:
		_camera_min_zoom = 0.5
	if _camera_max_zoom < _camera_min_zoom:
		_camera_max_zoom = _camera_min_zoom

	_camera.position = Vector2(
		float(camera.get("start_x", map_size.x * 0.5)),
		float(camera.get("start_y", map_size.y * 0.5))
	)
	_camera.zoom = Vector2.ONE
	_camera.limit_left = 0
	_camera.limit_top = 0
	_camera.limit_right = int(map_size.x)
	_camera.limit_bottom = int(map_size.y)
	_camera_initialized = true


func _map_camera(map: Dictionary) -> Dictionary:
	var camera_value: Variant = map.get("camera", {})
	if typeof(camera_value) != TYPE_DICTIONARY:
		return {}
	var camera: Dictionary = camera_value
	return camera


func _handle_camera_movement(delta: float) -> void:
	if !_camera_initialized:
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

	var normalized_direction: Vector2 = direction.normalized()
	_camera.position += normalized_direction * CAMERA_MOVE_SPEED * delta / _camera.zoom.x


func _input(event: InputEvent) -> void:
	if !_camera_initialized:
		return
	if event is InputEventMouseButton && event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_camera_zoom(_camera.zoom.x + CAMERA_ZOOM_STEP)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_camera_zoom(_camera.zoom.x - CAMERA_ZOOM_STEP)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_select_entity_at_screen_position(event.position)
			get_viewport().set_input_as_handled()


func _set_camera_zoom(value: float) -> void:
	var clamped_zoom: float = clampf(value, _camera_min_zoom, _camera_max_zoom)
	_camera.zoom = Vector2(clamped_zoom, clamped_zoom)


func _update_entity_node(entity_id: int, entity: Dictionary) -> void:
	var unit_node := _get_or_create_entity_node(entity_id)
	unit_node.position = Vector2(
		float(entity.get("x", 0.0)),
		float(entity.get("y", 0.0))
	)
	var body: ColorRect = unit_node.get_node("Body")
	var radius: float = float(entity.get("radius", UNIT_SIZE.x * 0.5))
	var diameter: float = max(radius * 2.0, 8.0)
	body.size = Vector2(diameter, diameter)
	body.position = -body.size * 0.5
	body.color = _team_color(int(entity.get("team", 0)))
	body.rotation_degrees = float(entity.get("facing_degrees", 0.0))

	var selection: Line2D = unit_node.get_node("Selection")
	var selection_radius: float = diameter * 0.5 + SELECTION_PADDING
	selection.points = _selection_points(selection_radius)
	selection.visible = entity_id == _selected_entity_id

	unit_node.get_node("Label").text = "%s\nhp:%s" % [
		entity.get("display_name", entity.get("kind", "unit")),
		"%s/%s" % [entity.get("health", 0), entity.get("max_health", 0)],
	]


func _select_entity_at_screen_position(screen_position: Vector2) -> void:
	var world_position: Vector2 = _screen_to_world_position(screen_position)
	var best_entity_id := 0
	var best_distance: float = INF

	for entity_id in _entity_snapshots.keys():
		var entity: Dictionary = _entity_snapshots[entity_id]
		var entity_position: Vector2 = Vector2(
			float(entity.get("x", 0.0)),
			float(entity.get("y", 0.0))
		)
		var radius: float = float(entity.get("radius", UNIT_SIZE.x * 0.5)) + SELECTION_PADDING
		var distance: float = world_position.distance_to(entity_position)
		if distance <= radius && distance < best_distance:
			best_entity_id = int(entity_id)
			best_distance = distance

	_selected_entity_id = best_entity_id
	_refresh_selection_visuals()


func _screen_to_world_position(screen_position: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_position


func _refresh_selection_visuals() -> void:
	for entity_id in _entity_nodes.keys():
		var node: Node2D = _entity_nodes[entity_id]
		var selection: Line2D = node.get_node("Selection")
		selection.visible = int(entity_id) == _selected_entity_id


func _selected_entity_summary() -> String:
	if _selected_entity_id == 0 || !_entity_snapshots.has(_selected_entity_id):
		return "none"

	var entity: Dictionary = _entity_snapshots[_selected_entity_id]
	return "%s hp:%s/%s team:%s" % [
		entity.get("display_name", entity.get("kind", "unit")),
		entity.get("health", 0),
		entity.get("max_health", 0),
		entity.get("team", 0),
	]


func _get_or_create_entity_node(entity_id: int) -> Node2D:
	if _entity_nodes.has(entity_id):
		return _entity_nodes[entity_id]

	var unit_node := Node2D.new()
	unit_node.name = "Entity%s" % entity_id

	var body := ColorRect.new()
	body.name = "Body"
	body.size = UNIT_SIZE
	body.position = -UNIT_SIZE * 0.5
	body.color = Color(0.25, 0.82, 0.55, 1.0)
	unit_node.add_child(body)

	var selection: Line2D = Line2D.new()
	selection.name = "Selection"
	selection.width = 2.5
	selection.default_color = Color(1.0, 0.92, 0.34, 1.0)
	selection.visible = false
	unit_node.add_child(selection)

	var label := Label.new()
	label.name = "Label"
	label.position = Vector2(-36.0, 22.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	unit_node.add_child(label)

	_world.add_child(unit_node)
	_entity_nodes[entity_id] = unit_node
	return unit_node


func _get_or_create_map_bounds() -> Line2D:
	if _map_bounds != null:
		return _map_bounds

	_map_bounds = Line2D.new()
	_map_bounds.name = "MapBounds"
	_map_bounds.width = 3.0
	_map_bounds.default_color = Color(0.46, 0.72, 0.55, 0.95)
	_world.add_child(_map_bounds)
	_world.move_child(_map_bounds, 0)
	return _map_bounds


func _team_color(team: int) -> Color:
	match team:
		0:
			return Color(0.25, 0.82, 0.55, 1.0)
		1:
			return Color(0.92, 0.32, 0.24, 1.0)
		_:
			return Color(0.50, 0.62, 0.95, 1.0)


func _selection_points(radius: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-radius, -radius),
		Vector2(radius, -radius),
		Vector2(radius, radius),
		Vector2(-radius, radius),
		Vector2(-radius, -radius),
	])


func _remove_missing_entities(alive_entity_ids: Dictionary) -> void:
	for entity_id in _entity_nodes.keys():
		if alive_entity_ids.has(entity_id):
			continue

		var node: Node = _entity_nodes[entity_id]
		_entity_nodes.erase(entity_id)
		_entity_snapshots.erase(entity_id)
		if int(entity_id) == _selected_entity_id:
			_selected_entity_id = 0
		node.queue_free()
