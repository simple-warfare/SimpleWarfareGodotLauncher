extends Control

const UNIT_SIZE := Vector2(32.0, 32.0)
const CAMERA_MOVE_SPEED := 520.0
const CAMERA_ZOOM_STEP := 0.1
const SELECTION_PADDING := 6.0
const TILE_LAYER_Z_BASE := 10
const OBJECT_LAYER_Z_BASE := 40
const MOVE_TARGET_Z := 80
const MAP_BOUNDS_Z := 90
const UNIT_Z := 100

@onready var _world: Node2D = %World
@onready var _camera: Camera2D = %Camera
@onready var _hud: Control = $HudLayer/Hud
@onready var _status_value: Label = %StatusValue
@onready var _stop_command_button: Button = %StopCommandButton
@onready var _produce_command_button: Button = %ProduceCommandButton
@onready var _diagnostics_button: Button = %DiagnosticsButton

var _unit_nodes: Dictionary = {}
var _unit_snapshots: Dictionary = {}
var _move_target_markers: Dictionary = {}
var _selected_unit_id := 0
var _map_bounds: Line2D
var _tile_layer_root: Node2D
var _object_layer_root: Node2D
var _last_tile_layers_key := ""
var _last_objects_key := ""
var _tile_texture_cache: Dictionary = {}
var _content_package_root := ""
var _camera_initialized := false
var _camera_min_zoom := 0.5
var _camera_max_zoom := 2.0


func _ready() -> void:
	_stop_command_button.pressed.connect(_issue_stop_command)
	_produce_command_button.pressed.connect(_issue_produce_unit_command)
	_diagnostics_button.pressed.connect(RustBackend.open_diagnostics_panel)
	_refresh_from_snapshot()


func _process(delta: float) -> void:
	RustBackend.update_runtime(delta)
	_refresh_from_snapshot()
	_handle_camera_movement(delta)


func _refresh_from_snapshot() -> void:
	var snapshot := RustBackend.get_frontend_snapshot()
	_content_package_root = str(snapshot.get("content_package_root", ""))
	var units: Array = snapshot.get("units", [])
	var objects: Array = snapshot.get("objects", [])
	var map: Dictionary = _snapshot_map(snapshot)
	var resources: Dictionary = _snapshot_resources(snapshot)
	var commands: Dictionary = _snapshot_commands(snapshot)
	var room: Dictionary = _snapshot_room(snapshot)
	_refresh_map(map)
	_refresh_objects(objects)

	var alive_unit_ids := {}
	for unit in units:
		if typeof(unit) != TYPE_DICTIONARY:
			continue

		var unit_id := int(unit.get("id", 0))
		if unit_id == 0:
			continue

		alive_unit_ids[unit_id] = true
		_unit_snapshots[unit_id] = unit
		_update_unit_node(unit_id, unit)
		_sync_move_target_marker(unit_id, unit)

	_remove_missing_units(alive_unit_ids)
	_refresh_command_controls()
	_status_value.text = "map=%s mode=%s room=%s resources=%s control=%s status=%s server_tick=%s client_tick=%s units=%s selected=%s move=%s production=%s commands=%s" % [
		map.get("title", "unknown"),
		snapshot.get("mode", "none"),
		_room_summary(room),
		_resource_summary(resources),
		_control_mode_summary(),
		snapshot.get("status", "unknown"),
		snapshot.get("server_tick", 0),
		snapshot.get("client_tick", 0),
		units.size(),
		_selected_unit_summary(),
		_movement_command_summary(),
		_production_command_summary(),
		_command_lifecycle_summary(commands),
	]
	var latest_diagnostic := RustBackend.get_latest_diagnostic_summary()
	if !latest_diagnostic.is_empty():
		_status_value.text += "\ndiag=%s" % latest_diagnostic


func _snapshot_map(snapshot: Dictionary) -> Dictionary:
	var map_value: Variant = snapshot.get("map", {})
	if typeof(map_value) != TYPE_DICTIONARY:
		return {}
	var map: Dictionary = map_value
	return map


func _snapshot_commands(snapshot: Dictionary) -> Dictionary:
	var commands_value: Variant = snapshot.get("commands", {})
	if typeof(commands_value) != TYPE_DICTIONARY:
		return {}
	var commands: Dictionary = commands_value
	return commands


func _snapshot_resources(snapshot: Dictionary) -> Dictionary:
	var resources_value: Variant = snapshot.get("resources", {})
	if typeof(resources_value) != TYPE_DICTIONARY:
		return {}
	var resources: Dictionary = resources_value
	return resources


func _snapshot_room(snapshot: Dictionary) -> Dictionary:
	var room_value: Variant = snapshot.get("room", {})
	if typeof(room_value) != TYPE_DICTIONARY:
		return {}
	var room: Dictionary = room_value
	return room


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
	_refresh_tile_layers(map, tile_size, map_size)
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


func _refresh_tile_layers(map: Dictionary, tile_size: float, map_size: Vector2) -> void:
	var layers := _map_array(map, "layers")
	var tilesets := _map_array(map, "tilesets")
	var layers_key := "%s|%s|%s" % [str(layers), str(tilesets), map_size]
	if layers_key == _last_tile_layers_key:
		return

	_last_tile_layers_key = layers_key
	var root := _get_or_create_tile_layer_root()
	_clear_children(root)

	var tile_definitions := _map_tile_definitions(tilesets)
	for layer_value in layers:
		if typeof(layer_value) != TYPE_DICTIONARY:
			continue
		var layer: Dictionary = layer_value
		_render_tile_layer(root, layer, tile_definitions, tile_size, map_size)


func _render_tile_layer(root: Node2D, layer: Dictionary, tile_definitions: Dictionary, tile_size: float, map_size: Vector2) -> void:
	var layer_node := Node2D.new()
	layer_node.name = "TileLayer_%s" % str(layer.get("id", "layer"))
	layer_node.z_index = TILE_LAYER_Z_BASE + int(layer.get("z_index", 0))
	root.add_child(layer_node)

	var width := int(layer.get("width", 0))
	var height := int(layer.get("height", 0))
	if width <= 0 || height <= 0:
		return

	var data := _dictionary_array(layer, "data")
	if !data.is_empty() && data.size() == width * height:
		for y in range(height):
			for x in range(width):
				var tile_id := int(data[y * width + x])
				_add_tile(layer_node, Vector2(x * tile_size, y * tile_size), tile_size, _tile_definition(tile_definitions, str(layer.get("tileset", "")), tile_id))
	else:
		var default_tile := int(layer.get("default_tile", 0))
		var default_definition := _tile_definition(tile_definitions, str(layer.get("tileset", "")), default_tile)
		_add_tile_fill(layer_node, map_size, _tile_color(default_definition, default_tile))

	for tile_value in _map_array(layer, "tiles"):
		if typeof(tile_value) != TYPE_DICTIONARY:
			continue
		var tile: Dictionary = tile_value
		var tile_position := Vector2(
			float(int(tile.get("x", 0))) * tile_size,
			float(int(tile.get("y", 0))) * tile_size
		)
		var tile_id := int(tile.get("tile", 0))
		_add_tile(layer_node, tile_position, tile_size, _tile_definition(tile_definitions, str(layer.get("tileset", "")), tile_id))


func _refresh_objects(objects: Array) -> void:
	var objects_key := str(objects)
	if objects_key == _last_objects_key:
		return

	_last_objects_key = objects_key
	var root := _get_or_create_object_layer_root()
	_clear_children(root)

	for object_value in objects:
		if typeof(object_value) != TYPE_DICTIONARY:
			continue
		var object: Dictionary = object_value
		_add_object_rect(root, object)


func _map_tile_definitions(tilesets: Array) -> Dictionary:
	var definitions := {}
	for tileset_value in tilesets:
		if typeof(tileset_value) != TYPE_DICTIONARY:
			continue
		var tileset: Dictionary = tileset_value
		var tileset_id := str(tileset.get("id", ""))
		var source := str(tileset.get("source", ""))
		for tile_value in _map_array(tileset, "tiles"):
			if typeof(tile_value) != TYPE_DICTIONARY:
				continue
			var tile: Dictionary = tile_value
			var tile_id := int(tile.get("id", 0))
			definitions[_tile_definition_key(tileset_id, tile_id)] = {
				"color": _parse_tile_color(str(tile.get("color", "")), tile_id),
				"source": source,
				"source_x": int(tile.get("source_x", -1)),
				"source_y": int(tile.get("source_y", -1)),
				"source_width": int(tile.get("source_width", -1)),
				"source_height": int(tile.get("source_height", -1)),
			}
	return definitions


func _tile_definition_key(tileset_id: String, tile_id: int) -> String:
	return "%s#%s" % [tileset_id, tile_id]


func _tile_definition(tile_definitions: Dictionary, tileset_id: String, tile_id: int) -> Dictionary:
	var key := _tile_definition_key(tileset_id, tile_id)
	if tile_definitions.has(key):
		return tile_definitions[key]
	return {
		"color": _parse_tile_color("", tile_id),
		"source": "",
		"source_x": -1,
		"source_y": -1,
		"source_width": -1,
		"source_height": -1,
	}


func _parse_tile_color(color_text: String, tile_id: int) -> Color:
	if !color_text.is_empty():
		var html := color_text
		if html.begins_with("#"):
			html = html.substr(1)
		return Color.html(html)

	match tile_id:
		1:
			return Color(0.30, 0.31, 0.27, 1.0)
		2:
			return Color(0.14, 0.28, 0.38, 1.0)
		_:
			return Color(0.13, 0.27, 0.18, 1.0)


func _tile_color(tile_definition: Dictionary, tile_id: int) -> Color:
	var color_value: Variant = tile_definition.get("color", _parse_tile_color("", tile_id))
	if typeof(color_value) == TYPE_COLOR:
		return color_value
	return _parse_tile_color("", tile_id)


func _tile_has_texture(tile_definition: Dictionary) -> bool:
	return !str(tile_definition.get("source", "")).is_empty() \
		&& int(tile_definition.get("source_width", -1)) > 0 \
		&& int(tile_definition.get("source_height", -1)) > 0


func _add_tile(parent: Node, position: Vector2, tile_size: float, tile_definition: Dictionary) -> void:
	if _tile_has_texture(tile_definition):
		var texture := _load_tile_texture(str(tile_definition.get("source", "")))
		if texture != null:
			var sprite := Sprite2D.new()
			sprite.position = position
			sprite.centered = false
			sprite.texture = texture
			sprite.region_enabled = true
			var source_width := float(int(tile_definition.get("source_width", 0)))
			var source_height := float(int(tile_definition.get("source_height", 0)))
			sprite.region_rect = Rect2(
				float(int(tile_definition.get("source_x", 0))),
				float(int(tile_definition.get("source_y", 0))),
				source_width,
				source_height
			)
			sprite.scale = Vector2(tile_size / source_width, tile_size / source_height)
			parent.add_child(sprite)
			return

	_add_tile_rect(parent, position, tile_size, _tile_color(tile_definition, 0))


func _add_tile_fill(parent: Node, map_size: Vector2, color: Color) -> void:
	var fill := ColorRect.new()
	fill.position = Vector2.ZERO
	fill.size = map_size
	fill.color = color
	parent.add_child(fill)


func _load_tile_texture(relative_source: String) -> Texture2D:
	var package_root := _content_package_root
	if package_root.is_empty():
		package_root = RustBackend.get_assets_root().path_join("content_packages/official_base_game")
	var source_path := package_root.path_join(relative_source)
	if _tile_texture_cache.has(source_path):
		return _tile_texture_cache[source_path]

	var image := Image.new()
	var load_error := image.load(source_path)
	if load_error != OK:
		_tile_texture_cache[source_path] = null
		return null

	var texture := ImageTexture.create_from_image(image)
	_tile_texture_cache[source_path] = texture
	return texture


func _add_tile_rect(parent: Node, position: Vector2, tile_size: float, color: Color) -> void:
	var rect := ColorRect.new()
	rect.position = position
	rect.size = Vector2(tile_size, tile_size)
	rect.color = color
	parent.add_child(rect)


func _add_object_rect(parent: Node, object: Dictionary) -> void:
	var width: float = max(float(object.get("width", 24.0)), 8.0)
	var height: float = max(float(object.get("height", 24.0)), 8.0)
	var rect := ColorRect.new()
	rect.name = "Object_%s" % str(object.get("id", "object"))
	rect.position = Vector2(
		float(object.get("x", 0.0)) - width * 0.5,
		float(object.get("y", 0.0)) - height * 0.5
	)
	rect.size = Vector2(width, height)
	rect.rotation_degrees = float(object.get("rotation_degrees", 0.0))
	rect.z_index = OBJECT_LAYER_Z_BASE + int(object.get("z_index", 0))
	rect.color = _object_color(str(object.get("kind", "")))
	parent.add_child(rect)


func _object_color(kind: String) -> Color:
	match kind:
		"resource_node":
			return Color(0.96, 0.78, 0.30, 0.55)
		_:
			return Color(0.72, 0.72, 0.78, 0.45)


func _map_array(source: Dictionary, key: String) -> Array:
	var value: Variant = source.get(key, [])
	if typeof(value) != TYPE_ARRAY:
		return []
	var array: Array = value
	return array


func _dictionary_array(source: Dictionary, key: String) -> Array:
	return _map_array(source, key)


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
		if _is_over_hud(event.position):
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_camera_zoom(_camera.zoom.x + CAMERA_ZOOM_STEP)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_camera_zoom(_camera.zoom.x - CAMERA_ZOOM_STEP)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_select_unit_at_screen_position(event.position)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_issue_move_command(event.position)
			get_viewport().set_input_as_handled()


func _set_camera_zoom(value: float) -> void:
	var clamped_zoom: float = clampf(value, _camera_min_zoom, _camera_max_zoom)
	_camera.zoom = Vector2(clamped_zoom, clamped_zoom)


func _is_over_hud(screen_position: Vector2) -> bool:
	return _hud.get_global_rect().has_point(screen_position)


func _update_unit_node(unit_id: int, unit: Dictionary) -> void:
	var unit_node := _get_or_create_unit_node(unit_id)
	unit_node.position = _unit_snapshot_position(unit)
	var body: ColorRect = unit_node.get_node("Body")
	var radius: float = float(unit.get("radius", UNIT_SIZE.x * 0.5))
	var diameter: float = max(radius * 2.0, 8.0)
	body.size = Vector2(diameter, diameter)
	body.position = -body.size * 0.5
	body.color = _team_color(int(unit.get("team", 0)))
	body.rotation_degrees = float(unit.get("facing_degrees", 0.0))

	var selection: Line2D = unit_node.get_node("Selection")
	var selection_radius: float = diameter * 0.5 + SELECTION_PADDING
	selection.points = _selection_points(selection_radius)
	selection.visible = unit_id == _selected_unit_id

	unit_node.get_node("Label").text = "%s\nhp:%s" % [
		unit.get("display_name", unit.get("kind", "unit")),
		"%s/%s" % [unit.get("health", 0), unit.get("max_health", 0)],
	]


func _select_unit_at_screen_position(screen_position: Vector2) -> void:
	var world_position: Vector2 = _screen_to_world_position(screen_position)
	var best_unit_id := 0
	var best_distance: float = INF

	for unit_id in _unit_snapshots.keys():
		var unit: Dictionary = _unit_snapshots[unit_id]
		var unit_position: Vector2 = _unit_snapshot_position(unit)
		var radius: float = float(unit.get("radius", UNIT_SIZE.x * 0.5)) + SELECTION_PADDING
		var distance: float = world_position.distance_to(unit_position)
		if distance <= radius && distance < best_distance:
			best_unit_id = int(unit_id)
			best_distance = distance

	_selected_unit_id = best_unit_id
	_refresh_selection_visuals()
	_refresh_command_controls()


func _issue_move_command(screen_position: Vector2) -> void:
	if _selected_unit_id == 0 || !_unit_snapshots.has(_selected_unit_id):
		return
	if !_selected_unit_can_control():
		push_warning("Selected unit is not controlled by this player.")
		return

	var target_position: Vector2 = _screen_to_world_position(screen_position)
	var feedback := RustBackend.issue_move_command(_selected_unit_id, target_position)
	if !bool(feedback.get("accepted", false)):
		push_warning("Rust move command rejected: %s %s" % [
			feedback.get("rejected_reason", "unknown"),
			feedback.get("detail", ""),
		])
		return


func _issue_stop_command() -> void:
	if _selected_unit_id == 0 || !_unit_snapshots.has(_selected_unit_id):
		return
	if !_selected_unit_can_control():
		push_warning("Selected unit is not controlled by this player.")
		return

	var feedback := RustBackend.issue_stop_command(_selected_unit_id)
	if !bool(feedback.get("accepted", false)):
		push_warning("Rust stop command rejected: %s %s" % [
			feedback.get("rejected_reason", "unknown"),
			feedback.get("detail", ""),
		])
		return

	_stop_command_button.disabled = true


func _issue_produce_unit_command() -> void:
	if _selected_unit_id == 0 || !_unit_snapshots.has(_selected_unit_id):
		return
	if !_selected_unit_can_control():
		push_warning("Selected unit is not controlled by this player.")
		return

	var build_option := _selected_unit_primary_build_option()
	if build_option.is_empty():
		push_warning("Selected unit has no production option.")
		return

	var unit := str(build_option.get("unit", ""))
	var feedback := RustBackend.issue_produce_unit_command(_selected_unit_id, unit)
	if !bool(feedback.get("accepted", false)):
		push_warning("Rust produce command rejected: %s %s" % [
			feedback.get("rejected_reason", "unknown"),
			feedback.get("detail", ""),
		])
		return

	_produce_command_button.disabled = true


func _unit_snapshot_position(unit: Dictionary) -> Vector2:
	return Vector2(
		float(unit.get("x", 0.0)),
		float(unit.get("y", 0.0))
	)


func _unit_move_target(unit: Dictionary) -> Dictionary:
	var move_target_value: Variant = unit.get("move_target", {})
	if typeof(move_target_value) != TYPE_DICTIONARY:
		return {}
	var move_target: Dictionary = move_target_value
	return move_target


func _move_target_position(move_target: Dictionary) -> Vector2:
	return Vector2(
		float(move_target.get("x", 0.0)),
		float(move_target.get("y", 0.0))
	)


func _screen_to_world_position(screen_position: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_position


func _refresh_selection_visuals() -> void:
	for unit_id in _unit_nodes.keys():
		var node: Node2D = _unit_nodes[unit_id]
		var selection: Line2D = node.get_node("Selection")
		selection.visible = int(unit_id) == _selected_unit_id


func _refresh_command_controls() -> void:
	_stop_command_button.disabled = !_selected_unit_can_stop()
	var build_option := _selected_unit_primary_build_option()
	if build_option.is_empty():
		_produce_command_button.text = "Produce"
	else:
		_produce_command_button.text = "Produce %s" % _short_unit_name(str(build_option.get("display_name", build_option.get("unit", "unit"))))
	_produce_command_button.disabled = !_selected_unit_can_produce()


func _selected_unit_can_stop() -> bool:
	if !_selected_unit_can_control():
		return false

	var unit: Dictionary = _unit_snapshots[_selected_unit_id]
	return bool(unit.get("is_moving", false))


func _selected_unit_can_produce() -> bool:
	if !_selected_unit_can_control():
		return false
	if _selected_unit_primary_build_option().is_empty():
		return false
	return _selected_unit_production_queue().is_empty()


func _selected_unit_can_control() -> bool:
	if _selected_unit_id == 0 || !_unit_snapshots.has(_selected_unit_id):
		return false

	var unit: Dictionary = _unit_snapshots[_selected_unit_id]
	return bool(unit.get("can_control", false))


func _selected_unit_primary_build_option() -> Dictionary:
	if _selected_unit_id == 0 || !_unit_snapshots.has(_selected_unit_id):
		return {}

	var unit: Dictionary = _unit_snapshots[_selected_unit_id]
	for option_value in _map_array(unit, "build_options"):
		if typeof(option_value) == TYPE_DICTIONARY:
			var option: Dictionary = option_value
			if !str(option.get("unit", "")).is_empty():
				return option

	return {}


func _selected_unit_production_queue() -> Array:
	if _selected_unit_id == 0 || !_unit_snapshots.has(_selected_unit_id):
		return []

	var unit: Dictionary = _unit_snapshots[_selected_unit_id]
	return _map_array(unit, "production_queue")


func _control_mode_summary() -> String:
	var controllable_count := _controllable_unit_count()
	if controllable_count == 0:
		return "readonly"
	if _selected_unit_id != 0:
		if _selected_unit_can_control():
			return "owned"
		return "readonly"
	return "owned:%s" % controllable_count


func _room_summary(room: Dictionary) -> String:
	var phase := str(room.get("phase", "lobby"))
	var local_team_id := int(room.get("local_team_id", -1))
	var player_slots: Array = room.get("player_slots", [])
	var local_team := "none"
	if local_team_id >= 0:
		local_team = str(local_team_id)
	return "phase:%s team:%s slots:%s" % [phase, local_team, player_slots.size()]


func _resource_summary(resources: Dictionary) -> String:
	var team_id := int(resources.get("team_id", -1))
	if team_id < 0:
		return "none"

	var amounts := _map_array(resources, "amounts")
	if amounts.is_empty():
		return "team:%s empty" % team_id

	var parts := PackedStringArray()
	for amount_value in amounts:
		if typeof(amount_value) != TYPE_DICTIONARY:
			continue
		var amount: Dictionary = amount_value
		parts.append("%s=%s" % [
			_short_resource_name(str(amount.get("resource", "unknown"))),
			amount.get("amount", 0),
		])

	if parts.is_empty():
		return "team:%s empty" % team_id
	return "team:%s %s" % [team_id, " ".join(parts)]


func _short_resource_name(resource: String) -> String:
	var separator_index := resource.find(":")
	if separator_index < 0 || separator_index == resource.length() - 1:
		return resource
	return resource.substr(separator_index + 1)


func _short_unit_name(unit: String) -> String:
	var separator_index := unit.find(":")
	if separator_index < 0 || separator_index == unit.length() - 1:
		return unit
	return unit.substr(separator_index + 1)


func _selected_unit_summary() -> String:
	if _selected_unit_id == 0 || !_unit_snapshots.has(_selected_unit_id):
		return "none"

	var unit: Dictionary = _unit_snapshots[_selected_unit_id]
	return "%s hp:%s/%s team:%s" % [
		unit.get("display_name", unit.get("kind", "unit")),
		unit.get("health", 0),
		unit.get("max_health", 0),
		unit.get("team", 0),
	]


func _controllable_unit_count() -> int:
	var controllable_count := 0
	for unit_value in _unit_snapshots.values():
		if typeof(unit_value) != TYPE_DICTIONARY:
			continue
		var unit: Dictionary = unit_value
		if bool(unit.get("can_control", false)):
			controllable_count += 1
	return controllable_count


func _movement_command_summary() -> String:
	var moving_count := 0
	for unit_value in _unit_snapshots.values():
		if typeof(unit_value) != TYPE_DICTIONARY:
			continue
		var unit: Dictionary = unit_value
		if bool(unit.get("is_moving", false)):
			moving_count += 1

	if moving_count == 0:
		return "none"
	return "rust_snapshot:%s" % moving_count


func _production_command_summary() -> String:
	if _selected_unit_id == 0 || !_unit_snapshots.has(_selected_unit_id):
		return "none"

	var queue := _selected_unit_production_queue()
	if !queue.is_empty() && typeof(queue[0]) == TYPE_DICTIONARY:
		var entry: Dictionary = queue[0]
		return "%s %.1fs" % [
			_short_unit_name(str(entry.get("display_name", entry.get("unit", "unit")))),
			float(entry.get("remaining_seconds", 0.0)),
		]

	var build_option := _selected_unit_primary_build_option()
	if build_option.is_empty():
		return "none"

	var cost_parts := PackedStringArray()
	for amount_value in _map_array(build_option, "cost"):
		if typeof(amount_value) != TYPE_DICTIONARY:
			continue
		var amount: Dictionary = amount_value
		cost_parts.append("%s=%s" % [
			_short_resource_name(str(amount.get("resource", "unknown"))),
			amount.get("amount", 0),
		])

	var cost_summary := "free"
	if !cost_parts.is_empty():
		cost_summary = " ".join(cost_parts)
	return "%s %.1fs %s" % [
		_short_unit_name(str(build_option.get("display_name", build_option.get("unit", "unit")))),
		float(build_option.get("build_time_seconds", 0.0)),
		cost_summary,
	]


func _command_lifecycle_summary(commands: Dictionary) -> String:
	var result_status := str(commands.get("last_result_status", ""))
	var rejected_reason := str(commands.get("last_rejected_reason", ""))
	if result_status == "rejected" && rejected_reason != "":
		return "pending:%s ack:%s result:%s rejected:%s %s" % [
			commands.get("pending_count", 0),
			commands.get("acknowledged_count", 0),
			result_status,
			rejected_reason,
			_reconciliation_summary(commands),
		]
	return "pending:%s ack:%s result:%s applied:%s/%s %s" % [
		commands.get("pending_count", 0),
		commands.get("acknowledged_count", 0),
		result_status,
		commands.get("last_applied_command_id", 0),
		commands.get("last_applied_sequence", 0),
		_reconciliation_summary(commands),
	]


func _reconciliation_summary(commands: Dictionary) -> String:
	var reconciled_count := int(commands.get("reconciled_command_count", 0))
	var mismatch_count := int(commands.get("reconciliation_mismatch_count", 0))
	var status := str(commands.get("last_reconciliation_status", ""))
	if reconciled_count == 0 && status.is_empty():
		return "rec:none"

	var command_id := int(commands.get("last_reconciled_command_id", 0))
	var sequence := int(commands.get("last_reconciled_sequence", 0))
	var round_trip_ticks := int(commands.get("last_reconciliation_round_trip_ticks", 0))
	var target_error := float(commands.get("last_reconciliation_target_error", 0.0))
	var position_error := float(commands.get("last_reconciliation_position_error", 0.0))
	var error := str(commands.get("last_reconciliation_error", ""))
	if !error.is_empty():
		return "rec:%s/%s last:%s/%s status:%s rt:%s pos_err:%.2f error:%s" % [
			reconciled_count,
			mismatch_count,
			command_id,
			sequence,
			status,
			round_trip_ticks,
			position_error,
			error,
		]
	return "rec:%s/%s last:%s/%s status:%s rt:%s target_err:%.2f pos_err:%.2f" % [
		reconciled_count,
		mismatch_count,
		command_id,
		sequence,
		status,
		round_trip_ticks,
		target_error,
		position_error,
	]


func _get_or_create_unit_node(unit_id: int) -> Node2D:
	if _unit_nodes.has(unit_id):
		return _unit_nodes[unit_id]

	var unit_node := Node2D.new()
	unit_node.name = "Unit%s" % unit_id
	unit_node.z_index = UNIT_Z

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
	_unit_nodes[unit_id] = unit_node
	return unit_node


func _get_or_create_map_bounds() -> Line2D:
	if _map_bounds != null:
		return _map_bounds

	_map_bounds = Line2D.new()
	_map_bounds.name = "MapBounds"
	_map_bounds.z_index = MAP_BOUNDS_Z
	_map_bounds.width = 3.0
	_map_bounds.default_color = Color(0.46, 0.72, 0.55, 0.95)
	_world.add_child(_map_bounds)
	return _map_bounds


func _get_or_create_tile_layer_root() -> Node2D:
	if _tile_layer_root != null:
		return _tile_layer_root

	_tile_layer_root = Node2D.new()
	_tile_layer_root.name = "TileLayers"
	_world.add_child(_tile_layer_root)
	return _tile_layer_root


func _get_or_create_object_layer_root() -> Node2D:
	if _object_layer_root != null:
		return _object_layer_root

	_object_layer_root = Node2D.new()
	_object_layer_root.name = "ObjectLayers"
	_world.add_child(_object_layer_root)
	return _object_layer_root


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()


func _update_or_create_move_target_marker(unit_id: int, target_position: Vector2) -> void:
	var marker: Line2D
	if _move_target_markers.has(unit_id):
		marker = _move_target_markers[unit_id]
	else:
		marker = Line2D.new()
		marker.name = "MoveTarget%s" % unit_id
		marker.z_index = MOVE_TARGET_Z
		marker.width = 2.0
		marker.default_color = Color(0.35, 0.72, 1.0, 0.9)
		marker.points = PackedVector2Array([
			Vector2(-8.0, 0.0),
			Vector2(8.0, 0.0),
			Vector2.ZERO,
			Vector2(0.0, -8.0),
			Vector2(0.0, 8.0),
		])
		_world.add_child(marker)
		_move_target_markers[unit_id] = marker

	marker.position = target_position


func _sync_move_target_marker(unit_id: int, unit: Dictionary) -> void:
	var move_target := _unit_move_target(unit)
	if move_target.is_empty():
		_remove_move_target_marker(unit_id)
		return

	_update_or_create_move_target_marker(unit_id, _move_target_position(move_target))


func _remove_move_target_marker(unit_id: int) -> void:
	if !_move_target_markers.has(unit_id):
		return

	var marker: Node = _move_target_markers[unit_id]
	_move_target_markers.erase(unit_id)
	marker.queue_free()


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


func _remove_missing_units(alive_unit_ids: Dictionary) -> void:
	for unit_id in _unit_nodes.keys():
		if alive_unit_ids.has(unit_id):
			continue

		var node: Node = _unit_nodes[unit_id]
		_unit_nodes.erase(unit_id)
		_unit_snapshots.erase(unit_id)
		_remove_move_target_marker(int(unit_id))
		if int(unit_id) == _selected_unit_id:
			_selected_unit_id = 0
		node.queue_free()
