extends RefCounted
class_name FrontendFrame


static func mode(frame: Dictionary) -> String:
	return str(frame.get("mode", "none"))


static func status(frame: Dictionary) -> String:
	return str(frame.get("status", "unknown"))


static func content_package_root(frame: Dictionary) -> String:
	return str(frame.get("content_package_root", ""))


static func server_tick(frame: Dictionary) -> int:
	return int(frame.get("server_tick", 0))


static func client_tick(frame: Dictionary) -> int:
	return int(frame.get("client_tick", 0))


static func room(frame: Dictionary) -> Dictionary:
	return dictionary(frame, "room")


static func map(frame: Dictionary) -> Dictionary:
	return dictionary(frame, "map")


static func resources(frame: Dictionary) -> Dictionary:
	return dictionary(frame, "resources")


static func commands(frame: Dictionary) -> Dictionary:
	return dictionary(frame, "commands")


static func command_queue(commands: Dictionary) -> Dictionary:
	return dictionary(commands, "queue")


static func command_replay(commands: Dictionary) -> Dictionary:
	return dictionary(commands, "replay")


static func command_prediction(commands: Dictionary) -> Dictionary:
	return dictionary(commands, "prediction")


static func command_reconciliation(commands: Dictionary) -> Dictionary:
	return dictionary(commands, "reconciliation")


static func command_acknowledgements(commands: Dictionary) -> Dictionary:
	return dictionary(commands, "acknowledgements")


static func command_replication(commands: Dictionary) -> Dictionary:
	return dictionary(commands, "replication")


static func debug(frame: Dictionary) -> Dictionary:
	return dictionary(frame, "debug")


static func network(frame: Dictionary) -> Dictionary:
	return dictionary(debug(frame), "network")


static func units(frame: Dictionary) -> Array:
	return array(frame, "units")


static func objects(frame: Dictionary) -> Array:
	return array(frame, "objects")


static func dictionary(source: Dictionary, key: String) -> Dictionary:
	return dictionary_value(source.get(key, {}))


static func dictionary_value(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var dictionary: Dictionary = value
	return dictionary


static func array(source: Dictionary, key: String) -> Array:
	var value: Variant = source.get(key, [])
	if typeof(value) != TYPE_ARRAY:
		return []
	var array: Array = value
	return array


static func unit_position(unit: Dictionary) -> Vector2:
	return Vector2(
		float(unit.get("x", 0.0)),
		float(unit.get("y", 0.0))
	)


static func unit_move_target(unit: Dictionary) -> Dictionary:
	return dictionary(unit, "move_target")


static func move_target_position(move_target: Dictionary) -> Vector2:
	return Vector2(
		float(move_target.get("x", 0.0)),
		float(move_target.get("y", 0.0))
	)
