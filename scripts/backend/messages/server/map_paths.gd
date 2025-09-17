class_name MapPaths
var map_paths:PackedStringArray


func from_content(content:Dictionary) -> void:
	map_paths = content.get("MapPaths").get("map_paths")
	
