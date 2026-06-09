extends RefCounted
class_name GameUnitRenderer

const UNIT_SIZE := Vector2(32.0, 32.0)
const SELECTION_PADDING := 6.0
const MOVE_TARGET_Z := 80
const UNIT_Z := 100
const MISSING_UNIT_GRACE_FRAMES := 6

var _world: Node2D
var _asset_resolver: GameAssetResolver
var _unit_nodes: Dictionary = {}
var _missing_unit_counts: Dictionary = {}
var _move_target_markers: Dictionary = {}


func setup(world: Node2D, asset_resolver: GameAssetResolver) -> void:
	_world = world
	_asset_resolver = asset_resolver


func update_unit(unit_id: int, unit: Dictionary, selected_unit_id: int) -> void:
	_missing_unit_counts.erase(unit_id)

	var unit_node := _get_or_create_unit_node(unit_id)
	unit_node.position = FrontendFrame.unit_position(unit)
	var visuals: Node2D = unit_node.get_node("Visuals")
	visuals.rotation_degrees = float(unit.get("facing_degrees", 0.0))

	var radius: float = float(unit.get("radius", UNIT_SIZE.x * 0.5))
	var diameter: float = max(radius * 2.0, 8.0)
	var team_color: Color = _team_color(int(unit.get("team", 0)))

	_update_body_visual(visuals, unit, diameter, team_color)
	_update_selection_visual(visuals, diameter, unit_id == selected_unit_id)
	_update_label(unit_node, unit)
	_sync_move_target_marker(unit_id, unit)


func refresh_selection(selected_unit_id: int) -> void:
	for unit_id in _unit_nodes.keys():
		var node: Node2D = _unit_nodes[unit_id]
		var selection: Line2D = node.get_node("Visuals/Selection")
		selection.visible = int(unit_id) == selected_unit_id


func remove_missing_units(alive_unit_ids: Dictionary) -> Array[int]:
	var removed_unit_ids: Array[int] = []
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
		_missing_unit_counts.erase(int_unit_id)
		_remove_move_target_marker(int_unit_id)
		removed_unit_ids.append(int_unit_id)
		node.queue_free()

	return removed_unit_ids


func _update_body_visual(visuals: Node2D, unit: Dictionary, diameter: float, team_color: Color) -> void:
	var body_texture_path := str(unit.get("body_texture", ""))
	var body_sprite: Sprite2D = visuals.get_node_or_null("BodySprite") as Sprite2D
	if !body_texture_path.is_empty():
		var texture := _asset_resolver.load_unit_body_texture(body_texture_path)
		if texture != null:
			body_sprite = _get_or_create_body_sprite(visuals, body_sprite)
			body_sprite.texture = texture
			_apply_body_sprite_region(body_sprite, unit, texture, diameter)
			body_sprite.modulate = team_color
			body_sprite.visible = true
			_apply_unit_animation(body_sprite, unit)
		elif body_sprite != null:
			body_sprite.visible = false
	elif body_sprite != null:
		body_sprite.visible = false

	var body: ColorRect = visuals.get_node("Body")
	body.size = Vector2(diameter, diameter)
	body.position = -body.size * 0.5
	body.color = team_color
	body.rotation_degrees = 0.0
	if body_sprite != null && body_sprite.visible:
		body.modulate.a = 0.3
	else:
		body.modulate.a = 1.0


func _get_or_create_body_sprite(visuals: Node2D, body_sprite: Sprite2D) -> Sprite2D:
	if body_sprite != null:
		return body_sprite

	var sprite := Sprite2D.new()
	sprite.name = "BodySprite"
	sprite.centered = true
	sprite.z_index = 1
	visuals.add_child(sprite)
	return sprite


func _apply_body_sprite_region(
	body_sprite: Sprite2D,
	unit: Dictionary,
	texture: Texture2D,
	diameter: float
) -> void:
	var body_source: Dictionary = unit.get("body_source", {})
	if !body_source.is_empty():
		body_sprite.region_enabled = true
		body_sprite.region_rect = Rect2(
			float(body_source.get("x", 0)),
			float(body_source.get("y", 0)),
			float(body_source.get("width", 0)),
			float(body_source.get("height", 0))
		)
		var source_width: float = float(body_source.get("width", texture.get_width()))
		var scale_factor: float = diameter / max(source_width, 1.0)
		body_sprite.scale = Vector2(scale_factor, scale_factor)
		return

	body_sprite.region_enabled = false
	var texture_size: Vector2 = texture.get_size()
	var scale_factor: float = diameter / max(texture_size.x, 1.0)
	body_sprite.scale = Vector2(scale_factor, scale_factor)


func _apply_unit_animation(sprite: Sprite2D, unit: Dictionary) -> void:
	var anim: Dictionary = unit.get("animation", {})
	if anim.is_empty():
		return

	var frame_width: float = float(anim.get("frame_width", 0))
	var frame_height: float = float(anim.get("frame_height", 0))
	var frame_count: int = int(anim.get("frame_count", 0))
	var frame_duration: float = float(anim.get("frame_duration_seconds", 0.15))
	var frames_per_row: int = int(anim.get("frames_per_row", 1))

	if frame_width <= 0 || frame_height <= 0 || frame_count <= 0:
		return

	var elapsed: float = Time.get_ticks_msec() / 1000.0
	var total_duration: float = frame_duration * float(frame_count)
	var cycle_time: float = fmod(elapsed, total_duration)
	var frame_index: int = int(cycle_time / frame_duration)
	if frame_index >= frame_count:
		frame_index = frame_count - 1

	var column: int = frame_index % max(frames_per_row, 1)
	var row: int = frame_index / max(frames_per_row, 1)
	sprite.region_enabled = true
	sprite.region_rect = Rect2(
		float(column) * frame_width,
		float(row) * frame_height,
		frame_width,
		frame_height
	)


func _update_selection_visual(visuals: Node2D, diameter: float, selected: bool) -> void:
	var selection: Line2D = visuals.get_node("Selection")
	var selection_radius: float = diameter * 0.5 + SELECTION_PADDING
	selection.points = _selection_points(selection_radius)
	selection.visible = selected


func _update_label(unit_node: Node2D, unit: Dictionary) -> void:
	var label: Label = unit_node.get_node("Label")
	label.text = "%s\nhp:%s" % [
		unit.get("display_name", unit.get("kind", "unit")),
		"%s/%s" % [unit.get("health", 0), unit.get("max_health", 0)],
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

	var selection := Line2D.new()
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


func _sync_move_target_marker(unit_id: int, unit: Dictionary) -> void:
	var move_target := FrontendFrame.unit_move_target(unit)
	if move_target.is_empty():
		_remove_move_target_marker(unit_id)
		return

	_update_or_create_move_target_marker(unit_id, FrontendFrame.move_target_position(move_target))


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
