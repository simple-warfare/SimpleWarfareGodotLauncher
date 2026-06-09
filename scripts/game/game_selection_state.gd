extends RefCounted
class_name GameSelectionState

const DEFAULT_UNIT_RADIUS := 16.0
const SELECTION_HIT_PADDING := 6.0

var selected_unit_id := 0

var _unit_views: Dictionary = {}


func track_unit(unit_id: int, unit: Dictionary) -> void:
	_unit_views[unit_id] = unit


func remove_units(unit_ids: Array) -> void:
	for unit_id in unit_ids:
		remove_unit(int(unit_id))


func remove_unit(unit_id: int) -> void:
	_unit_views.erase(unit_id)
	if unit_id == selected_unit_id:
		selected_unit_id = 0


func select_at_world_position(world_position: Vector2) -> int:
	var best_unit_id := 0
	var best_distance: float = INF

	for unit_id_value in _unit_views.keys():
		var unit_id := int(unit_id_value)
		var unit: Dictionary = _unit_views[unit_id_value]
		var unit_position := FrontendFrame.unit_position(unit)
		var radius: float = float(unit.get("radius", DEFAULT_UNIT_RADIUS)) + SELECTION_HIT_PADDING
		var distance := world_position.distance_to(unit_position)
		if distance <= radius && distance < best_distance:
			best_unit_id = unit_id
			best_distance = distance

	selected_unit_id = best_unit_id
	return selected_unit_id


func unit_count() -> int:
	return _unit_views.size()


func has_selected_unit() -> bool:
	return selected_unit_id != 0 && _unit_views.has(selected_unit_id)


func selected_unit() -> Dictionary:
	if !has_selected_unit():
		return {}
	return _unit_views[selected_unit_id]


func selected_unit_can_control() -> bool:
	if !has_selected_unit():
		return false

	var unit := selected_unit()
	return bool(unit.get("can_control", false))


func selected_unit_can_stop() -> bool:
	if !selected_unit_can_control():
		return false

	var unit := selected_unit()
	return bool(unit.get("is_moving", false))


func selected_unit_can_produce() -> bool:
	if !selected_unit_can_control():
		return false
	if selected_unit_primary_build_option().is_empty():
		return false
	return selected_unit_production_queue().is_empty()


func selected_unit_primary_build_option() -> Dictionary:
	var unit := selected_unit()
	if unit.is_empty():
		return {}

	for option_value in FrontendFrame.array(unit, "build_options"):
		if typeof(option_value) != TYPE_DICTIONARY:
			continue
		var option: Dictionary = option_value
		if !str(option.get("unit", "")).is_empty():
			return option

	return {}


func selected_unit_production_queue() -> Array:
	var unit := selected_unit()
	if unit.is_empty():
		return []
	return FrontendFrame.array(unit, "production_queue")


func controllable_unit_count() -> int:
	var controllable_count := 0
	for unit_value in _unit_views.values():
		if typeof(unit_value) != TYPE_DICTIONARY:
			continue
		var unit: Dictionary = unit_value
		if bool(unit.get("can_control", false)):
			controllable_count += 1
	return controllable_count


func moving_unit_count() -> int:
	var moving_count := 0
	for unit_value in _unit_views.values():
		if typeof(unit_value) != TYPE_DICTIONARY:
			continue
		var unit: Dictionary = unit_value
		if bool(unit.get("is_moving", false)):
			moving_count += 1
	return moving_count
