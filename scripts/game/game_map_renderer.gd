extends RefCounted
class_name GameMapRenderer

const TILE_LAYER_Z_BASE := 10
const OBJECT_LAYER_Z_BASE := 40
const MAP_BOUNDS_Z := 90

var _world: Node2D
var _asset_resolver: GameAssetResolver
var _map_bounds: Line2D
var _tile_layer_root: Node2D
var _object_layer_root: Node2D
var _last_tile_layers_key := ""
var _last_objects_key := ""


func setup(world: Node2D, asset_resolver: GameAssetResolver) -> void:
	_world = world
	_asset_resolver = asset_resolver


func refresh_map(map: Dictionary) -> Dictionary:
	if map.is_empty():
		return {}

	var width: float = float(map.get("width", 0))
	var height: float = float(map.get("height", 0))
	var tile_size: float = float(map.get("tile_size", 0))
	if width <= 0.0 || height <= 0.0 || tile_size <= 0.0:
		return {}

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

	return {
		"map_size": map_size,
		"camera": _map_camera(map),
	}


func refresh_objects(objects: Array) -> void:
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


func _map_camera(map: Dictionary) -> Dictionary:
	var camera_value: Variant = map.get("camera", {})
	if typeof(camera_value) != TYPE_DICTIONARY:
		return {}
	var camera: Dictionary = camera_value
	return camera


func _refresh_tile_layers(map: Dictionary, tile_size: float, map_size: Vector2) -> void:
	var layers := FrontendFrame.array(map, "layers")
	var tilesets := FrontendFrame.array(map, "tilesets")
	var layers_key := "%s|%s|%s" % [str(layers), str(tilesets), map_size]
	if layers_key == _last_tile_layers_key:
		return

	_last_tile_layers_key = layers_key
	var root := _get_or_create_tile_layer_root()
	_clear_children(root)

	var tile_definitions := _asset_resolver.map_tile_definitions(tilesets)
	for layer_value in layers:
		if typeof(layer_value) != TYPE_DICTIONARY:
			continue
		var layer: Dictionary = layer_value
		_render_tile_layer(root, layer, tile_definitions, tile_size, map_size)


func _render_tile_layer(
	root: Node2D,
	layer: Dictionary,
	tile_definitions: Dictionary,
	tile_size: float,
	map_size: Vector2
) -> void:
	var layer_node := Node2D.new()
	layer_node.name = "TileLayer_%s" % str(layer.get("id", "layer"))
	layer_node.z_index = TILE_LAYER_Z_BASE + int(layer.get("z_index", 0))
	root.add_child(layer_node)

	var width := int(layer.get("width", 0))
	var height := int(layer.get("height", 0))
	if width <= 0 || height <= 0:
		return

	var data := FrontendFrame.array(layer, "data")
	if !data.is_empty() && data.size() == width * height:
		for y in range(height):
			for x in range(width):
				var tile_id := int(data[y * width + x])
				var tile_definition := _asset_resolver.tile_definition(tile_definitions, str(layer.get("tileset", "")), tile_id)
				_add_tile(layer_node, Vector2(x * tile_size, y * tile_size), tile_size, tile_definition, tile_id)
	else:
		var default_tile := int(layer.get("default_tile", 0))
		var default_definition := _asset_resolver.tile_definition(tile_definitions, str(layer.get("tileset", "")), default_tile)
		_add_tile_fill(layer_node, map_size, _asset_resolver.tile_color(default_definition, default_tile))

	for tile_value in FrontendFrame.array(layer, "tiles"):
		if typeof(tile_value) != TYPE_DICTIONARY:
			continue
		var tile: Dictionary = tile_value
		var tile_position := Vector2(
			float(int(tile.get("x", 0))) * tile_size,
			float(int(tile.get("y", 0))) * tile_size
		)
		var tile_id := int(tile.get("tile", 0))
		var tile_definition := _asset_resolver.tile_definition(tile_definitions, str(layer.get("tileset", "")), tile_id)
		_add_tile(layer_node, tile_position, tile_size, tile_definition, tile_id)


func _add_tile(parent: Node, position: Vector2, tile_size: float, tile_definition: Dictionary, tile_id: int) -> void:
	if _asset_resolver.tile_has_texture(tile_definition):
		var texture := _asset_resolver.load_tile_texture(str(tile_definition.get("source", "")))
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

	_add_tile_rect(parent, position, tile_size, _asset_resolver.tile_color(tile_definition, tile_id))


func _add_tile_fill(parent: Node, map_size: Vector2, color: Color) -> void:
	var fill := ColorRect.new()
	fill.position = Vector2.ZERO
	fill.size = map_size
	fill.color = color
	parent.add_child(fill)


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
	rect.color = _asset_resolver.object_color(str(object.get("kind", "")))
	parent.add_child(rect)


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
