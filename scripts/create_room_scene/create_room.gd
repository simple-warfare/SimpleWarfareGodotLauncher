extends Control
@export var create_scene_button_group: ButtonGroup

const CREATE_ROOM_SCENE = preload("res://scenes/create_room.tscn")


func _ready() -> void:
	create_scene_button_group.pressed.connect(button_pressed)
	
			
func button_pressed(button:Button) -> void:
	match button.kind:
		CreateSceneButton.Kind.ChangeMap:
			pass
		CreateSceneButton.Kind.ChangeMap:
			pass
		CreateSceneButton.Kind.Back:
			self.queue_free()
			pass
	
	button.button_pressed = false
