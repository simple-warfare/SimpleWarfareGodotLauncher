@tool
extends "res://components/main_button.gd"
class_name  DifferentSettingsButton

enum Kind{
	Display,
	Audio,
	Inputs,
	Hotkeys,
	Advanced,
	Development,
	ModSettings,
	Back
}
	
@export var kind : Kind:
	set(v):
		kind = v
		if lbl:
			description = Kind.keys()[v]
			lbl.text = description
			_update_layout()
		

func _on_ready() -> void:
	description = Kind.keys()[kind]
	lbl.text = description
