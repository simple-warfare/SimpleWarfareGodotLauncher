extends Control

const UNIT_SIZE := Vector2(32.0, 32.0)

@onready var _world: Node2D = %World
@onready var _status_value: Label = %StatusValue

var _entity_nodes: Dictionary = {}


func _ready() -> void:
	_refresh_from_snapshot()


func _process(delta: float) -> void:
	RustBackend.update_runtime(delta)
	_refresh_from_snapshot()


func _refresh_from_snapshot() -> void:
	var snapshot := RustBackend.get_frontend_snapshot()
	var entities: Array = snapshot.get("entities", [])

	_status_value.text = "mode=%s status=%s server_tick=%s client_tick=%s entities=%s" % [
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


func _update_entity_node(entity_id: int, entity: Dictionary) -> void:
	var unit_node := _get_or_create_entity_node(entity_id)
	unit_node.position = Vector2(
		float(entity.get("x", 0.0)),
		float(entity.get("y", 0.0))
	)
	unit_node.get_node("Label").text = "%s\nhp:%s" % [
		entity.get("kind", "unit"),
		entity.get("health", 0),
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


func _remove_missing_entities(alive_entity_ids: Dictionary) -> void:
	for entity_id in _entity_nodes.keys():
		if alive_entity_ids.has(entity_id):
			continue

		var node: Node = _entity_nodes[entity_id]
		_entity_nodes.erase(entity_id)
		node.queue_free()
