extends Control

const UNIT_SIZE := Vector2(32.0, 32.0)

@onready var _world: Node2D = %World
@onready var _status_value: Label = %StatusValue

var _entity_nodes: Dictionary = {}
var _map_bounds: Line2D


func _ready() -> void:
	_refresh_from_snapshot()


func _process(delta: float) -> void:
	RustBackend.update_runtime(delta)
	_refresh_from_snapshot()


func _refresh_from_snapshot() -> void:
	var snapshot := RustBackend.get_frontend_snapshot()
	var entities: Array = snapshot.get("entities", [])
	var map: Dictionary = _snapshot_map(snapshot)
	_refresh_map(map)

	_status_value.text = "map=%s mode=%s status=%s server_tick=%s client_tick=%s entities=%s" % [
		map.get("title", "unknown"),
		snapshot.get("mode", "none"),
		snapshot.get("status", "unknown"),
		snapshot.get("server_tick", 0),
		snapshot.get("client_tick", 0),
		entities.size(),
	]

	var alive_entity_ids := {}
	for entity in entities:
		if typeof(entity) != TYPE_DICTIONARY:
			continue

		var entity_id := int(entity.get("id", 0))
		if entity_id == 0:
			continue

		alive_entity_ids[entity_id] = true
		_update_entity_node(entity_id, entity)

	_remove_missing_entities(alive_entity_ids)


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

	unit_node.get_node("Label").text = "%s\nhp:%s" % [
		entity.get("display_name", entity.get("kind", "unit")),
		"%s/%s" % [entity.get("health", 0), entity.get("max_health", 0)],
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


func _remove_missing_entities(alive_entity_ids: Dictionary) -> void:
	for entity_id in _entity_nodes.keys():
		if alive_entity_ids.has(entity_id):
			continue

		var node: Node = _entity_nodes[entity_id]
		_entity_nodes.erase(entity_id)
		node.queue_free()
