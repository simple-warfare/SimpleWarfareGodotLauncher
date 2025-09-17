extends Control
@export var multiplayer_scene_button_group: ButtonGroup

const CREATE_ROOM_SCENE = preload("res://scenes/create_room.tscn")


func _ready() -> void:
	multiplayer_scene_button_group.pressed.connect(button_pressed)
	
			
func button_pressed(button:Button) -> void:
	match button.kind:
		MultiplayerSceneButton.Kind.FilterGames:
			pass
		MultiplayerSceneButton.Kind.DirectIp:
			pass
		MultiplayerSceneButton.Kind.Create:
			var create_room_plane = CREATE_ROOM_SCENE.instantiate()
			add_child(create_room_plane)
		MultiplayerSceneButton.Kind.LeaveChat:
			pass
		MultiplayerSceneButton.Kind.Back:
			Globals.next_scene("res://scenes/main.tscn")
	
	button.button_pressed = false
