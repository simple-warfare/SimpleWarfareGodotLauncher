extends Control

@onready var change_mod_set_menu_btn:MenuButton = $MainMenu/MarginContainer/Background/ToolBar/MarginContainer2/HBoxContainer/ChangeModSet/MenuButton
@onready var enable_mods_container:VBoxContainer = $MainMenu/MarginContainer/Background/ModViewer/Control/EnableMods/MarginContainer/PanelContainer/MarginContainer/VBoxContainer
@onready var all_mods_container:VBoxContainer = $MainMenu/MarginContainer/Background/ModViewer/Control/AllMods/MarginContainer/PanelContainer/VBoxContainer
@onready var mod_description_label:RichTextLabel = $MainMenu/MarginContainer/Background/ModViewer/Control2/MarginContainer/MarginContainer/Control/ModDescriptionLabel
@export var enable_mod_info_button_group: ButtonGroup
@export var all_mod_info_button_group: ButtonGroup
@export var tool_button_group: ButtonGroup

@onready var timer:Timer = $Timer
var last_mod_info_btn:Button
var popup_menu:PopupMenu
var ckecked_index:int
var now_edit_mod_set:ModSet
var now_edit_mod_file:String
var now_enable_mod_infos:Array = []
var mod_view = preload("res://components/mod_view.tscn")

func _ready() -> void:
	timer.wait_time = 0.5
	popup_menu = change_mod_set_menu_btn.get_popup()
	popup_menu.index_pressed.connect(on_menu_btn_index_pressed)
	now_edit_mod_set = Globals.mod_set
	now_edit_mod_file = Globals.all_mod_sets.find_key(now_edit_mod_set)
	for mod_set_file in Globals.all_mod_sets:
		var index = popup_menu.item_count
		popup_menu.add_check_item(now_edit_mod_file)
		if now_edit_mod_file == mod_set_file:
			ckecked_index = index
			popup_menu.set_item_checked(index,true)
			
	enable_mod_info_button_group.pressed.connect(enable_mod_info_btn_pressed)
	all_mod_info_button_group.pressed.connect(all_mod_info_btn_pressed)
	tool_button_group.pressed.connect(tool_button_pressed)
	update_mod_list()
	
func add_mod_view_to(mod_info:ModInfo,to:VBoxContainer,button_group:ButtonGroup):
	var new_mod_view = mod_view.instantiate()
	new_mod_view.button_group = button_group
	new_mod_view.new(mod_info)
	to.add_child(new_mod_view)

func on_menu_btn_index_pressed(index:int) -> void:
	popup_menu.set_item_checked(ckecked_index,false)
	ckecked_index = index
	popup_menu.set_item_checked(index,true)
	update_mod_set(popup_menu.get_item_text(index))
	
func update_mod_set(mod_set:String) -> void:
	now_edit_mod_set.refresh()
	now_edit_mod_set = Globals.all_mod_sets.get(mod_set)
	update_mod_list()

func update_mod_list() -> void:
	clean_mods_container(all_mods_container)
	clean_mods_container(enable_mods_container)
	for mod_info_file in Globals.all_mod_infos:
		var mod_info = Globals.all_mod_infos[mod_info_file]
		add_mod_view_to(mod_info,all_mods_container,all_mod_info_button_group)
		if now_edit_mod_set.enable_mods.has(mod_info_file):
			add_mod_view_to(mod_info,enable_mods_container,enable_mod_info_button_group)
func clean_mods_container(mods_container:VBoxContainer) -> void:
	for child in mods_container.get_children():
		mods_container.remove_child(child)

func enable_mod_info_btn_pressed(button:Button) -> void:
	if timer.time_left == 0:
		timer.start()
	elif timer.time_left >= 0.3:
		if last_mod_info_btn == button:
			now_edit_mod_set.remove_mod(button.mod_info)
			update_mod_list()
	mod_description_label.text = button.mod_info.description
	last_mod_info_btn = button
	
func all_mod_info_btn_pressed(button:Button) -> void:
	if timer.time_left == 0:
		timer.start()
	elif timer.time_left >= 0.2:
		if last_mod_info_btn == button:
			now_edit_mod_set.add_mod(button.mod_info)
			update_mod_list()
	mod_description_label.text = button.mod_info.description
	last_mod_info_btn = button

func tool_button_pressed(button:Button) -> void:
	match button.kind:
		ModSceneButton.Kind.SaveAndUse:
			now_edit_mod_set.save()
			Globals.next_scene("res://scenes/main.tscn")
		ModSceneButton.Kind.ModAssetLib:
			pass
		ModSceneButton.Kind.EnableMod:
			now_edit_mod_set.add_mod(last_mod_info_btn.mod_info)
			update_mod_list()
		ModSceneButton.Kind.DisableMod:
			now_edit_mod_set.remove_mod(last_mod_info_btn.mod_info)
			update_mod_list()
		ModSceneButton.Kind.SaveModSet:
			pass
		ModSceneButton.Kind.ChangeModSet:
			change_mod_set_menu_btn.show_popup()
	
	button.button_pressed = false
