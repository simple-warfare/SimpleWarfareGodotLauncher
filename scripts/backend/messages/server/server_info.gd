class_name ServerInfo
var game_version:String


func from_content(content:Dictionary) -> void:
	game_version = content.get("ServerInfo").get("game_version")
	
