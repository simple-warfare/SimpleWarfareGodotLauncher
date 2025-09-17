@tool
extends GridContainer
@export var map_container_reference:Panel

func _ready() -> void:
	resized.connect(suit_column)
	
	
func suit_column() -> void:
	columns = int(size.x/map_container_reference.size.x)
