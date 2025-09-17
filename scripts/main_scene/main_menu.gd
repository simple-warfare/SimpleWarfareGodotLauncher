extends NinePatchRect
@onready var main_menu_button_container:VBoxContainer = $MarginContainer/VBoxContainer


func _ready() -> void:
	self.resized.connect(_update_layout)
	_update_layout()
func _update_layout():
	self.size.y = main_menu_button_container.get_rect().size.y + 30
