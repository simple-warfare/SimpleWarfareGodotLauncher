extends RefCounted
class_name GameAssetResolver

var _content_package_root := ""
var _texture_cache: Dictionary = {}


func set_content_package_root(content_package_root: String) -> void:
	_content_package_root = content_package_root


func map_tile_definitions(tilesets: Array) -> Dictionary:
	var definitions := {}
	for tileset_value in tilesets:
		if typeof(tileset_value) != TYPE_DICTIONARY:
			continue
		var tileset: Dictionary = tileset_value
		var tileset_id := str(tileset.get("id", ""))
		var source := str(tileset.get("source", ""))
		for tile_value in FrontendFrame.array(tileset, "tiles"):
			if typeof(tile_value) != TYPE_DICTIONARY:
				continue
			var tile: Dictionary = tile_value
			var tile_id := int(tile.get("id", 0))
			definitions[tile_definition_key(tileset_id, tile_id)] = {
				"color": parse_tile_color(str(tile.get("color", "")), tile_id),
				"source": source,
				"source_x": int(tile.get("source_x", -1)),
				"source_y": int(tile.get("source_y", -1)),
				"source_width": int(tile.get("source_width", -1)),
				"source_height": int(tile.get("source_height", -1)),
			}
	return definitions


func tile_definition_key(tileset_id: String, tile_id: int) -> String:
	return "%s#%s" % [tileset_id, tile_id]


func tile_definition(tile_definitions: Dictionary, tileset_id: String, tile_id: int) -> Dictionary:
	var key := tile_definition_key(tileset_id, tile_id)
	if tile_definitions.has(key):
		return tile_definitions[key]
	return {
		"color": parse_tile_color("", tile_id),
		"source": "",
		"source_x": -1,
		"source_y": -1,
		"source_width": -1,
		"source_height": -1,
	}


func parse_tile_color(color_text: String, tile_id: int) -> Color:
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


func tile_color(tile_definition: Dictionary, tile_id: int) -> Color:
	var color_value: Variant = tile_definition.get("color", parse_tile_color("", tile_id))
	if typeof(color_value) == TYPE_COLOR:
		return color_value
	return parse_tile_color("", tile_id)


func tile_has_texture(tile_definition: Dictionary) -> bool:
	return !str(tile_definition.get("source", "")).is_empty() \
		&& int(tile_definition.get("source_width", -1)) > 0 \
		&& int(tile_definition.get("source_height", -1)) > 0


func load_tile_texture(relative_source: String) -> Texture2D:
	return _load_texture(relative_source, "content_packages/official_base_game")


func load_unit_body_texture(relative_path: String) -> Texture2D:
	return _load_texture(relative_path, "content_packages/official")


func object_color(kind: String) -> Color:
	match kind:
		"resource_node":
			return Color(0.96, 0.78, 0.30, 0.55)
		_:
			return Color(0.72, 0.72, 0.78, 0.45)


func _load_texture(relative_path: String, fallback_package: String) -> Texture2D:
	if relative_path.is_empty():
		return null

	var package_root := _content_package_root
	if package_root.is_empty():
		package_root = RustBackend.get_assets_root().path_join(fallback_package)

	var source_path := package_root.path_join(relative_path)
	if _texture_cache.has(source_path):
		return _texture_cache[source_path]

	var image := Image.new()
	var load_error := image.load(source_path)
	if load_error != OK:
		_texture_cache[source_path] = null
		return null

	var texture := ImageTexture.create_from_image(image)
	_texture_cache[source_path] = texture
	return texture
