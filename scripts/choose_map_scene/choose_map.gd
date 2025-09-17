extends Control
@export var choose_map_button_group: ButtonGroup


func _ready() -> void:
	choose_map_button_group.pressed.connect(choose_map_button_pressed)
	
	
	
func choose_map_button_pressed(button:Button) -> void:
	match button.kind:
		ChooseMapButton.Kind.RandomMap:
			pass
		ChooseMapButton.Kind.Back:
			Globals.quick_to_main_scene()
