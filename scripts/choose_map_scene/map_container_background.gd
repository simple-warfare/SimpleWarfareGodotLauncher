@tool
extends Panel

@export var map_container_reference:GridContainer
@onready var map_name_label: Label = $Control/MarginContainer/Control/MarginContainer/VBoxContainer/MapName
@onready var conqueset_label: Label = $Control/MarginContainer/Control/MarginContainer/VBoxContainer/Conqueset
@onready var created_by_label: Label = $Control/MarginContainer/Control/MarginContainer/VBoxContainer/CreatedBy
@onready var map_size_label: Label = $Control/MarginContainer/Control/MarginContainer/VBoxContainer/MapSize

var map_name:String
var conqueset:String
var created_by:String
var map_size:String


func _ready() -> void:
	map_container_reference.resized.connect(suit_size)
	resized.connect(suit_size)
	map_name_label.text = map_name
	conqueset_label.text = conqueset
	created_by_label.text = created_by
	map_size_label.text = map_size
	suit_size()
	
func suit_size() -> void:
	var width = map_container_reference.size.x
	var columns = map_container_reference.columns
	var h_separation = map_container_reference.theme.get_constant("h_separation","GridContainer")
	custom_minimum_size.x = (width - ((columns -1) * h_separation))/columns
	custom_minimum_size.y = custom_minimum_size.x * 1.2
