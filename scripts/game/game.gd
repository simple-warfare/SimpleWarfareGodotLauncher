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
const MISSING_UNIT_GRACE_FRAMES := 6
const SELECTION_DRAG_THRESHOLD := 6.0

@onready var _world: Node2D = %World
@onready var _camera: Camera2D = %Camera
@onready var _hud_layer: CanvasLayer = $HudLayer
@onready var _hud: Control = $HudLayer/Hud
@onready var _debug_panel: Control = $HudLayer/DebugPanel
@onready var _status_value: Label = %StatusValue
@onready var _debug_value: Label = %DebugValue
@onready var _stop_command_button: Button = %StopCommandButton
@onready var _produce_command_button: Button = %ProduceCommandButton
@onready var _diagnostics_button: Button = %DiagnosticsButton

var _unit_nodes: Dictionary = {}
var _unit_snapshots: Dictionary = {}
var _missing_unit_counts: Dictionary = {}
var _move_target_markers: Dictionary = {}
var _selected_unit_id := 0
var _selected_unit_ids: Dictionary = {}
var _selection_drag_candidate := false
var _selection_dragging := false
var _selection_drag_start := Vector2.ZERO
var _selection_box: Panel
var _map_bounds: Line2D
var _tile_layer_root: Node2D
var _object_layer_root: Node2D
var _last_tile_layers_key := ""
var _last_objects_key := ""
var _tile_texture_cache: Dictionary = {}
var _unit_texture_cache: Dictionary = {}
var _content_package_root := ""
var _frame_delta := 0.0
var _camera_initialized := false
var _camera_min_zoom := 0.5
var _camera_max_zoom := 2.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stop_command_button.pressed.connect(_issue_stop_command)
	_produce_command_button.pressed.connect(_issue_produce_unit_command)
	_diagnostics_button.pressed.connect(RustBackend.open_diagnostics_panel)
	_create_selection_box()
	_refresh_from_snapshot()


func _process(delta: float) -> void:
	_frame_delta = delta
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
		_missing_unit_counts.erase(unit_id)
		_unit_snapshots[unit_id] = unit
		_update_unit_node(unit_id, unit)
		_sync_move_target_marker(unit_id, unit)

	_remove_missing_units(alive_unit_ids)
	_refresh_command_controls()
	_status_value.text = "map=%s mode=%s room=%s resources=%s control=%s status=%s server_tick=%s client_tick=%s units=%s selected=%s" % [
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
	]
	var debug_lines := [
		"move=%s" % _movement_command_summary(),
		"production=%s" % _production_command_summary(),
		"sync=%s" % _lightyear_prediction_summary(commands),
		"commands=%s" % _command_lifecycle_summary(commands),
	]
	var latest_diagnostic := RustBackend.get_latest_diagnostic_summary()
	if !latest_diagnostic.is_empty():
		debug_lines.append("diag=%s" % latest_diagnostic)
	_debug_value.text = "\n".join(debug_lines)


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
	var definitions: Dictionary = {}
	for tileset_value in tilesets:
		if typeof(tileset_value) != TYPE_DICTIONARY:
			continue
		var tileset: Dictionary = tileset_value
		var tileset_id: String = str(tileset.get("id", ""))
		var tileset_source: String = str(tileset.get("source", ""))
		for tile_value in _map_array(tileset, "tiles"):
			if typeof(tile_value) != TYPE_DICTIONARY:
				continue
			var tile: Dictionary = tile_value
			var tile_id: int = int(tile.get("id", 0))
			var tile_source: String = str(tile.get("source", ""))
			if tile_source.is_empty():
				tile_source = tileset_source
			definitions[_tile_definition_key(tileset_id, tile_id)] = {
				"color": _parse_tile_color(str(tile.get("color", "")), tile_id),
				"source": tile_source,
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


func _add_tile(parent: Node, tile_position: Vector2, tile_size: float, tile_definition: Dictionary) -> void:
	if _tile_has_texture(tile_definition):
		var texture := _load_tile_texture(str(tile_definition.get("source", "")))
		if texture != null:
			var sprite := Sprite2D.new()
			sprite.position = tile_position
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

	_add_tile_rect(parent, tile_position, tile_size, _tile_color(tile_definition, 0))


func _add_tile_fill(parent: Node, map_size: Vector2, color: Color) -> void:
	var fill := ColorRect.new()
	fill.position = Vector2.ZERO
	fill.size = map_size
	fill.color = color
	parent.add_child(fill)


func _load_tile_texture(relative_source: String) -> Texture2D:
	var package_root := _content_package_root
	if package_root.is_empty():
		package_root = RustBackend.get_assets_root().path_join("content_packages/official")
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


func _unit_render(unit: Dictionary) -> Dictionary:
	var render_value: Variant = unit.get("render", {})
	if typeof(render_value) != TYPE_DICTIONARY:
		return {}
	var render: Dictionary = render_value
	return render


func _unit_sprite_frame_grid(sprite: Dictionary) -> Dictionary:
	var frame_grid_value: Variant = sprite.get("frame_grid", {})
	if typeof(frame_grid_value) != TYPE_DICTIONARY:
		return {}
	var frame_grid: Dictionary = frame_grid_value
	return frame_grid


func _unit_sprite_pivot(sprite: Dictionary) -> Dictionary:
	var pivot_value: Variant = sprite.get("pivot", {})
	if typeof(pivot_value) != TYPE_DICTIONARY:
		return {}
	var pivot: Dictionary = pivot_value
	return pivot


func _unit_body_animation(render: Dictionary) -> Dictionary:
	var animation_value: Variant = render.get("body_animation", {})
	if typeof(animation_value) != TYPE_DICTIONARY:
		return {}
	var animation: Dictionary = animation_value
	return animation


func _update_unit_render_visuals(unit_id: int, unit: Dictionary, visuals: Node2D, diameter: float) -> void:
	var render: Dictionary = _unit_render(unit)
	var body_value: Variant = render.get("body", {})
	var body: Dictionary = {}
	if typeof(body_value) == TYPE_DICTIONARY:
		body = body_value
	var body_sprite: Sprite2D = visuals.get_node("BodySprite")
	var fallback_body: ColorRect = visuals.get_node("Body")

	if body.is_empty():
		body_sprite.visible = false
		fallback_body.visible = true
	else:
		var texture: Texture2D = _load_unit_texture(str(body.get("path", "")))
		if texture == null:
			body_sprite.visible = false
			fallback_body.visible = true
		else:
			fallback_body.visible = false
			body_sprite.visible = true
			body_sprite.texture = texture
			_apply_unit_sprite_region(body_sprite, body, _unit_body_animation(render), bool(unit.get("is_moving", false)))
			_scale_unit_sprite(body_sprite, body, diameter)

	_update_unit_attachments(unit_id, render, visuals.get_node("Attachments"), diameter)


func _apply_unit_sprite_region(sprite: Sprite2D, sprite_definition: Dictionary, animation: Dictionary, is_moving: bool) -> void:
	var frame_grid: Dictionary = _unit_sprite_frame_grid(sprite_definition)
	if frame_grid.is_empty():
		sprite.region_enabled = false
		sprite.offset = Vector2.ZERO
		return

	var frame_count: int = max(int(frame_grid.get("frame_count", 1)), 1)
	var frame_index: int = 0
	if !animation.is_empty():
		var mode: String = str(animation.get("mode", ""))
		var should_animate: bool = mode == "ambient_loop" || (mode == "loop_when_moving" && is_moving)
		var frames: Array = _map_array(animation, "frames")
		var frames_per_second: float = max(float(animation.get("frames_per_second", 1.0)), 0.01)
		if should_animate && !frames.is_empty():
			var frame_ms: float = max(1.0, 1000.0 / frames_per_second)
			var animation_index: int = int(float(Time.get_ticks_msec()) / frame_ms) % frames.size()
			frame_index = clampi(int(frames[animation_index]), 0, frame_count - 1)

	var frame_width: int = int(frame_grid.get("frame_width", 0))
	var frame_height: int = int(frame_grid.get("frame_height", 0))
	var columns: int = max(int(frame_grid.get("columns", 1)), 1)
	if frame_width <= 0 || frame_height <= 0:
		sprite.region_enabled = false
		sprite.offset = Vector2.ZERO
		return

	sprite.region_enabled = true
	sprite.region_rect = Rect2(
		float((frame_index % columns) * frame_width),
		float(int(float(frame_index) / float(columns)) * frame_height),
		float(frame_width),
		float(frame_height)
	)
	sprite.offset = Vector2.ZERO


func _scale_unit_sprite(sprite: Sprite2D, sprite_definition: Dictionary, diameter: float) -> void:
	var display_size: Vector2 = _unit_sprite_display_size(sprite, sprite_definition)
	var max_size: float = max(display_size.x, display_size.y)
	if max_size <= 0.0:
		sprite.scale = Vector2.ONE
		return
	var sprite_scale: float = diameter / max_size
	sprite.scale = Vector2(sprite_scale, sprite_scale)


func _unit_sprite_display_size(sprite: Sprite2D, sprite_definition: Dictionary) -> Vector2:
	var frame_grid: Dictionary = _unit_sprite_frame_grid(sprite_definition)
	if !frame_grid.is_empty():
		return Vector2(float(frame_grid.get("frame_width", 0)), float(frame_grid.get("frame_height", 0)))
	if sprite.texture == null:
		return UNIT_SIZE
	return sprite.texture.get_size()


func _update_unit_attachments(_unit_id: int, render: Dictionary, attachments_root: Node2D, diameter: float) -> void:
	var alive_attachment_ids: Dictionary = {}
	for attachment_value in _map_array(render, "attachments"):
		if typeof(attachment_value) != TYPE_DICTIONARY:
			continue
		var attachment: Dictionary = attachment_value
		var attachment_id: String = str(attachment.get("id", "attachment"))
		alive_attachment_ids[attachment_id] = true
		var sprite: Sprite2D = _get_or_create_attachment_sprite(attachments_root, attachment_id)
		var sprite_value: Variant = attachment.get("sprite", {})
		var sprite_definition: Dictionary = {}
		if typeof(sprite_value) == TYPE_DICTIONARY:
			sprite_definition = sprite_value
		var texture: Texture2D = _load_unit_texture(str(sprite_definition.get("path", "")))
		if texture == null:
			sprite.visible = false
			continue
		sprite.visible = true
		sprite.texture = texture
		_apply_unit_sprite_region(sprite, sprite_definition, {}, true)
		_scale_unit_sprite(sprite, sprite_definition, diameter)
		sprite.position = Vector2(float(attachment.get("mount_x", 0.0)), float(attachment.get("mount_y", 0.0)))
		var spin_rate: float = float(attachment.get("spin_rate_degrees_per_second", 0.0))
		if spin_rate != 0.0:
			sprite.rotation_degrees = fmod(float(Time.get_ticks_msec()) * 0.001 * spin_rate, 360.0)
		else:
			sprite.rotation_degrees = 0.0
		var pivot: Dictionary = _unit_sprite_pivot(sprite_definition)
		if !pivot.is_empty():
			sprite.offset = Vector2(-float(pivot.get("x", 0.0)), -float(pivot.get("y", 0.0)))

	for child in attachments_root.get_children():
		if !alive_attachment_ids.has(str(child.name)):
			child.queue_free()


func _get_or_create_attachment_sprite(parent: Node2D, attachment_id: String) -> Sprite2D:
	if parent.has_node(attachment_id):
		return parent.get_node(attachment_id)
	var sprite: Sprite2D = Sprite2D.new()
	sprite.name = attachment_id
	sprite.centered = true
	parent.add_child(sprite)
	return sprite


func _load_unit_texture(relative_source: String) -> Texture2D:
	if relative_source.is_empty():
		return null
	var package_root: String = _content_package_root
	if package_root.is_empty():
		package_root = RustBackend.get_assets_root().path_join("content_packages/official")
	var source_path: String = package_root.path_join(relative_source)
	if _unit_texture_cache.has(source_path):
		return _unit_texture_cache[source_path]

	var image: Image = Image.new()
	var load_error: Error = image.load(source_path)
	if load_error != OK:
		_unit_texture_cache[source_path] = null
		return null

	var texture: ImageTexture = ImageTexture.create_from_image(image)
	_unit_texture_cache[source_path] = texture
	return texture


func _add_tile_rect(parent: Node, rect_position: Vector2, tile_size: float, color: Color) -> void:
	var rect := ColorRect.new()
	rect.position = rect_position
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


func _unhandled_input(event: InputEvent) -> void:
	if !_camera_initialized:
		return
	if event is InputEventMouseMotion:
		if _is_over_ui(event.position) && !_selection_dragging:
			return
		if _selection_drag_candidate || _selection_dragging:
			_update_selection_drag(event.position)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP && event.pressed:
			if _is_over_ui(event.position):
				return
			_set_camera_zoom(_camera.zoom.x + CAMERA_ZOOM_STEP)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN && event.pressed:
			if _is_over_ui(event.position):
				return
			_set_camera_zoom(_camera.zoom.x - CAMERA_ZOOM_STEP)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if _is_over_ui(event.position):
					return
				_begin_selection_drag(event.position)
			else:
				_finish_selection_drag(event.position)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT && event.pressed:
			if _is_over_ui(event.position):
				return
			_issue_move_command(event.position)
			get_viewport().set_input_as_handled()


func _create_selection_box() -> void:
	_selection_box = Panel.new()
	_selection_box.name = "SelectionBox"
	_selection_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_selection_box.visible = false
	_selection_box.z_index = 1000
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.25, 0.82, 0.55, 0.12)
	style.border_color = Color(0.25, 0.82, 0.55, 0.85)
	style.set_border_width_all(1)
	_selection_box.add_theme_stylebox_override("panel", style)
	_hud_layer.add_child(_selection_box)


func _begin_selection_drag(screen_position: Vector2) -> void:
	_selection_drag_candidate = true
	_selection_dragging = false
	_selection_drag_start = screen_position
	_selection_box.visible = false


func _update_selection_drag(screen_position: Vector2) -> void:
	if !_selection_drag_candidate && !_selection_dragging:
		return

	var distance: float = _selection_drag_start.distance_to(screen_position)
	if !_selection_dragging && distance < SELECTION_DRAG_THRESHOLD:
		return

	_selection_dragging = true
	var rect: Rect2 = _selection_rect_from_points(_selection_drag_start, screen_position)
	_selection_box.position = rect.position
	_selection_box.size = rect.size
	_selection_box.visible = true


func _finish_selection_drag(screen_position: Vector2) -> void:
	if !_selection_drag_candidate && !_selection_dragging:
		return

	var was_dragging: bool = _selection_dragging
	_selection_drag_candidate = false
	_selection_dragging = false
	_selection_box.visible = false

	if was_dragging:
		_select_units_in_screen_rect(_selection_rect_from_points(_selection_drag_start, screen_position))
	else:
		_select_unit_at_screen_position(screen_position)


func _selection_rect_from_points(a: Vector2, b: Vector2) -> Rect2:
	var min_position: Vector2 = Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var max_position: Vector2 = Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	return Rect2(min_position, max_position - min_position)


func _set_camera_zoom(value: float) -> void:
	var clamped_zoom: float = clampf(value, _camera_min_zoom, _camera_max_zoom)
	_camera.zoom = Vector2(clamped_zoom, clamped_zoom)


func _is_over_ui(screen_position: Vector2) -> bool:
	var hovered_control: Control = get_viewport().gui_get_hovered_control()
	if _is_control_in_ui(hovered_control):
		return true
	return _hud.get_global_rect().has_point(screen_position)


func _is_control_in_ui(control: Control) -> bool:
	if control == null || control == _selection_box:
		return false
	if control == _hud || _hud.is_ancestor_of(control):
		return true
	if control == _debug_panel || _debug_panel.is_ancestor_of(control):
		return true
	return false


func _update_unit_node(unit_id: int, unit: Dictionary) -> void:
	var unit_node := _get_or_create_unit_node(unit_id)
	unit_node.position = _unit_snapshot_position(unit)
	var visuals: Node2D = unit_node.get_node("Visuals")
	var render: Dictionary = _unit_render(unit)
	var facing_offset: float = float(render.get("facing_offset_degrees", 0.0))
	if bool(render.get("rotates_with_facing", true)):
		visuals.rotation_degrees = float(unit.get("facing_degrees", 0.0)) + facing_offset
	else:
		visuals.rotation_degrees = facing_offset

	var body: ColorRect = visuals.get_node("Body")
	var radius: float = float(unit.get("radius", UNIT_SIZE.x * 0.5))
	var diameter: float = max(radius * 2.0, 8.0)
	body.size = Vector2(diameter, diameter)
	body.position = -body.size * 0.5
	body.color = _team_color(int(unit.get("team", 0)))
	body.rotation_degrees = 0.0
	_update_unit_render_visuals(unit_id, unit, visuals, diameter)

	var selection: Line2D = visuals.get_node("Selection")
	var selection_radius: float = diameter * 0.5 + SELECTION_PADDING
	selection.points = _selection_points(selection_radius)
	selection.visible = _is_unit_selected(unit_id)

	var label: Label = unit_node.get_node("Label")
	label.text = "%s\nhp:%s" % [
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

	if best_unit_id == 0:
		_set_selected_units([])
	else:
		_set_selected_units([best_unit_id])


func _select_units_in_screen_rect(screen_rect: Rect2) -> void:
	var selected_ids: Array = []
	var canvas_transform: Transform2D = get_viewport().get_canvas_transform()

	for unit_id in _unit_snapshots.keys():
		var unit: Dictionary = _unit_snapshots[unit_id]
		if !bool(unit.get("can_control", false)):
			continue

		var screen_position: Vector2 = canvas_transform * _unit_snapshot_position(unit)
		if screen_rect.has_point(screen_position):
			selected_ids.append(int(unit_id))

	selected_ids.sort()
	_set_selected_units(selected_ids)


func _set_selected_units(unit_ids: Array) -> void:
	_selected_unit_ids.clear()
	_selected_unit_id = 0
	for unit_id_value in unit_ids:
		var unit_id := int(unit_id_value)
		if unit_id == 0 || !_unit_snapshots.has(unit_id):
			continue
		_selected_unit_ids[unit_id] = true
		if _selected_unit_id == 0:
			_selected_unit_id = unit_id
	_refresh_selection_visuals()
	_refresh_command_controls()


func _is_unit_selected(unit_id: int) -> bool:
	return _selected_unit_ids.has(unit_id)


func _normalize_selected_primary() -> void:
	if _selected_unit_id != 0 && _selected_unit_ids.has(_selected_unit_id):
		return

	_selected_unit_id = 0
	var remaining_ids: Array = _selected_unit_ids.keys()
	remaining_ids.sort()
	for unit_id_value in remaining_ids:
		var unit_id := int(unit_id_value)
		if _unit_snapshots.has(unit_id):
			_selected_unit_id = unit_id
			return


func _issue_move_command(screen_position: Vector2) -> void:
	var unit_ids: Array = _selected_controllable_unit_ids()
	if unit_ids.is_empty():
		return

	var target_position: Vector2 = _screen_to_world_position(screen_position)
	var reverse := Input.is_key_pressed(KEY_D)
	for unit_id_value in unit_ids:
		var unit_id := int(unit_id_value)
		var feedback := RustBackend.issue_move_command(unit_id, target_position, reverse)
		if !bool(feedback.get("accepted", false)):
			push_warning("Rust move command rejected for unit %s: %s %s" % [
				unit_id,
				feedback.get("rejected_reason", "unknown"),
				feedback.get("detail", ""),
			])


func _issue_stop_command() -> void:
	var unit_ids: Array = _selected_controllable_unit_ids()
	if unit_ids.is_empty():
		push_warning("No controllable selected units to stop.")
		return

	var accepted_any := false
	for unit_id_value in unit_ids:
		var unit_id := int(unit_id_value)
		var feedback := RustBackend.issue_stop_command(unit_id)
		if !bool(feedback.get("accepted", false)):
			push_warning("Rust stop command rejected for unit %s: %s %s" % [
				unit_id,
				feedback.get("rejected_reason", "unknown"),
				feedback.get("detail", ""),
			])
		else:
			accepted_any = true

	if accepted_any:
		_stop_command_button.disabled = true


func _issue_produce_unit_command() -> void:
	var producer: Dictionary = _selected_producer()
	if producer.is_empty():
		push_warning("No selected unit can produce right now.")
		return

	var producer_entity_id := int(producer.get("unit_id", 0))
	var build_option: Dictionary = producer.get("build_option", {})
	if build_option.is_empty():
		push_warning("Selected producer has no production option.")
		return

	var unit := str(build_option.get("unit", ""))
	var feedback := RustBackend.issue_produce_unit_command(producer_entity_id, unit)
	if !bool(feedback.get("accepted", false)):
		push_warning("Rust produce command rejected for unit %s: %s %s" % [
			producer_entity_id,
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
		var selection: Line2D = node.get_node("Visuals/Selection")
		selection.visible = _is_unit_selected(int(unit_id))


func _refresh_command_controls() -> void:
	_stop_command_button.disabled = !_selected_unit_can_stop()
	var producer: Dictionary = _selected_producer()
	var build_option: Dictionary = producer.get("build_option", {})
	if build_option.is_empty():
		_produce_command_button.text = "Produce"
	else:
		_produce_command_button.text = "Produce %s" % _short_unit_name(str(build_option.get("display_name", build_option.get("unit", "unit"))))
	_produce_command_button.disabled = producer.is_empty()


func _selected_unit_can_stop() -> bool:
	return !_selected_controllable_unit_ids().is_empty()


func _selected_unit_can_produce() -> bool:
	return !_selected_producer().is_empty()


func _selected_unit_can_control() -> bool:
	if _selected_unit_id == 0 || !_unit_snapshots.has(_selected_unit_id):
		return false

	var unit: Dictionary = _unit_snapshots[_selected_unit_id]
	return bool(unit.get("can_control", false))


func _selected_controllable_unit_ids() -> Array:
	var unit_ids: Array = []
	for unit_id_value in _selected_unit_ids.keys():
		var unit_id := int(unit_id_value)
		if !_unit_snapshots.has(unit_id):
			continue
		var unit: Dictionary = _unit_snapshots[unit_id]
		if bool(unit.get("can_control", false)):
			unit_ids.append(unit_id)
	unit_ids.sort()
	return unit_ids


func _selected_unit_primary_build_option() -> Dictionary:
	if _selected_unit_id == 0 || !_unit_snapshots.has(_selected_unit_id):
		return {}

	var unit: Dictionary = _unit_snapshots[_selected_unit_id]
	return _unit_primary_build_option(unit)


func _unit_primary_build_option(unit: Dictionary) -> Dictionary:
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


func _unit_production_queue(unit: Dictionary) -> Array:
	return _map_array(unit, "production_queue")


func _selected_producer() -> Dictionary:
	var selected_ids := _selected_controllable_unit_ids()
	if _selected_unit_id != 0 && selected_ids.has(_selected_unit_id):
		var primary_producer := _producer_for_unit_id(_selected_unit_id)
		if !primary_producer.is_empty():
			return primary_producer

	for unit_id_value in selected_ids:
		var unit_id := int(unit_id_value)
		var producer := _producer_for_unit_id(unit_id)
		if !producer.is_empty():
			return producer

	return {}


func _producer_for_unit_id(unit_id: int) -> Dictionary:
	if !_unit_snapshots.has(unit_id):
		return {}
	var unit: Dictionary = _unit_snapshots[unit_id]
	var build_option := _unit_primary_build_option(unit)
	if build_option.is_empty():
		return {}
	if !_unit_production_queue(unit).is_empty():
		return {}
	return {
		"unit_id": unit_id,
		"build_option": build_option,
	}


func _control_mode_summary() -> String:
	var controllable_count := _controllable_unit_count()
	if controllable_count == 0:
		return "readonly"
	if !_selected_unit_ids.is_empty():
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
	var selected_count: int = _selected_unit_ids.size()
	if selected_count > 1:
		return "%s units primary:%s hp:%s/%s team:%s" % [
			selected_count,
			unit.get("display_name", unit.get("kind", "unit")),
			unit.get("health", 0),
			unit.get("max_health", 0),
			unit.get("team", 0),
		]
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
	var producer: Dictionary = _selected_producer()
	if producer.is_empty():
		return "none"

	var producer_unit_id := int(producer.get("unit_id", 0))
	if producer_unit_id == 0 || !_unit_snapshots.has(producer_unit_id):
		return "none"

	var producer_unit: Dictionary = _unit_snapshots[producer_unit_id]
	var queue := _unit_production_queue(producer_unit)
	if !queue.is_empty() && typeof(queue[0]) == TYPE_DICTIONARY:
		var entry: Dictionary = queue[0]
		return "%s %.1fs" % [
			_short_unit_name(str(entry.get("display_name", entry.get("unit", "unit")))),
			float(entry.get("remaining_seconds", 0.0)),
		]

	var build_option: Dictionary = producer.get("build_option", {})
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
	var replay_summary := _replay_summary(commands)
	if result_status == "rejected" && rejected_reason != "":
		return "pending:%s ack:%s result:%s rejected:%s %s %s %s" % [
			commands.get("pending_count", 0),
			commands.get("acknowledged_count", 0),
			result_status,
			rejected_reason,
			replay_summary,
			_reconciliation_summary(commands),
			_prediction_history_summary(commands),
		]
	return "pending:%s ack:%s result:%s applied:%s/%s %s %s %s" % [
		commands.get("pending_count", 0),
		commands.get("acknowledged_count", 0),
		result_status,
		commands.get("last_applied_command_id", 0),
		commands.get("last_applied_sequence", 0),
		replay_summary,
		_reconciliation_summary(commands),
		_prediction_history_summary(commands),
	]


func _replay_summary(commands: Dictionary) -> String:
	var replay_count := int(commands.get("replay_command_count", 0))
	if replay_count == 0:
		return "replay:none"

	return "replay:%s base:%s units:%s seq:%s-%s" % [
		replay_count,
		commands.get("replay_base_server_tick", 0),
		commands.get("replay_base_unit_count", 0),
		commands.get("replay_first_sequence", 0),
		commands.get("replay_last_sequence", 0),
	]


func _lightyear_prediction_summary(commands: Dictionary) -> String:
	var predicted_count := int(commands.get("lightyear_predicted_unit_count", 0))
	var replicated_count := int(commands.get("replicated_unit_count", 0))
	if replicated_count == 0:
		return "ly:none"

	var predicted_ids := PackedStringArray()
	for unit_value in _dictionary_array(commands, "replicated_units"):
		if typeof(unit_value) != TYPE_DICTIONARY:
			continue
		var unit: Dictionary = unit_value
		if bool(unit.get("is_lightyear_predicted", false)):
			predicted_ids.append(str(unit.get("unit_id", 0)))

	if predicted_ids.is_empty():
		return "ly:%s/%s ids:none" % [predicted_count, replicated_count]
	return "ly:%s/%s ids:%s" % [predicted_count, replicated_count, ",".join(predicted_ids)]


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
	var correction := str(commands.get("last_reconciliation_correction", ""))
	var error := str(commands.get("last_reconciliation_error", ""))
	if !error.is_empty():
		return "rec:%s/%s last:%s/%s status:%s rt:%s corr:%s pos_err:%.2f error:%s" % [
			reconciled_count,
			mismatch_count,
			command_id,
			sequence,
			status,
			round_trip_ticks,
			correction,
			position_error,
			error,
		]
	return "rec:%s/%s last:%s/%s status:%s rt:%s corr:%s target_err:%.2f pos_err:%.2f" % [
		reconciled_count,
		mismatch_count,
		command_id,
		sequence,
		status,
		round_trip_ticks,
		correction,
		target_error,
		position_error,
	]


func _prediction_history_summary(commands: Dictionary) -> String:
	var history_count := int(commands.get("prediction_history_count", 0))
	if history_count == 0:
		return "pred:none"

	var history := _dictionary_array(commands, "prediction_history")
	if !history.is_empty():
		var entries := PackedStringArray()
		for entry_value in history:
			if typeof(entry_value) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = entry_value
			entries.append("#%s/%s u:%s err:%.2f corr:%s" % [
				entry.get("command_id", 0),
				entry.get("sequence", 0),
				entry.get("entity_id", 0),
				float(entry.get("position_error", 0.0)),
				str(entry.get("correction", "")),
			])
		if !entries.is_empty():
			return "pred:%s recent:%s" % [history_count, " | ".join(entries)]

	var command_id := int(commands.get("last_prediction_command_id", 0))
	var sequence := int(commands.get("last_prediction_sequence", 0))
	var entity_id := int(commands.get("last_prediction_entity_id", 0))
	var predicted := Vector2(
		float(commands.get("last_prediction_x", 0.0)),
		float(commands.get("last_prediction_y", 0.0))
	)
	var authoritative := Vector2(
		float(commands.get("last_prediction_authoritative_x", 0.0)),
		float(commands.get("last_prediction_authoritative_y", 0.0))
	)
	var position_error := float(commands.get("last_prediction_position_error", 0.0))
	var correction := str(commands.get("last_prediction_correction", ""))
	return "pred:%s last:%s/%s unit:%s p:(%.1f,%.1f) a:(%.1f,%.1f) err:%.2f corr:%s" % [
		history_count,
		command_id,
		sequence,
		entity_id,
		predicted.x,
		predicted.y,
		authoritative.x,
		authoritative.y,
		position_error,
		correction,
	]


func _get_or_create_unit_node(unit_id: int) -> Node2D:
	if _unit_nodes.has(unit_id):
		return _unit_nodes[unit_id]

	var unit_node := Node2D.new()
	unit_node.name = "Unit%s" % unit_id
	unit_node.z_index = UNIT_Z

	var visuals := Node2D.new()
	visuals.name = "Visuals"
	unit_node.add_child(visuals)

	var body := ColorRect.new()
	body.name = "Body"
	body.size = UNIT_SIZE
	body.position = -UNIT_SIZE * 0.5
	body.color = Color(0.25, 0.82, 0.55, 1.0)
	visuals.add_child(body)

	var body_sprite := Sprite2D.new()
	body_sprite.name = "BodySprite"
	body_sprite.visible = false
	visuals.add_child(body_sprite)

	var attachments := Node2D.new()
	attachments.name = "Attachments"
	visuals.add_child(attachments)

	var selection: Line2D = Line2D.new()
	selection.name = "Selection"
	selection.width = 2.5
	selection.default_color = Color(1.0, 0.92, 0.34, 1.0)
	selection.visible = false
	visuals.add_child(selection)

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
		var int_unit_id := int(unit_id)
		if alive_unit_ids.has(int_unit_id):
			_missing_unit_counts.erase(int_unit_id)
			continue
		var missing_count := int(_missing_unit_counts.get(int_unit_id, 0)) + 1
		_missing_unit_counts[int_unit_id] = missing_count
		if missing_count < MISSING_UNIT_GRACE_FRAMES:
			continue

		var node: Node = _unit_nodes[unit_id]
		_unit_nodes.erase(unit_id)
		_unit_snapshots.erase(unit_id)
		_missing_unit_counts.erase(int_unit_id)
		_remove_move_target_marker(int_unit_id)
		if int_unit_id == _selected_unit_id:
			_selected_unit_id = 0
		_selected_unit_ids.erase(int_unit_id)
		node.queue_free()
	_normalize_selected_primary()
