extends Control

@export var all_menus:Dictionary
@export var all_development_menus:Array
@export var different_setting_button_group: ButtonGroup
@export var development_button_group: ButtonGroup
@onready var input_control:Control = $MainMenu/MarginContainer/Control/Control2/Development/MarginContainer/Control/Control


var menu_kind:SettingMenuKind

func _ready() -> void:
	different_setting_button_group.pressed.connect(different_setting_button_pressed)
	development_button_group.pressed.connect(development_button_pressed)
	

func different_setting_button_pressed(button:Button) -> void:
	match button.kind:
		DifferentSettingsButton.Kind.Display:
			pass
		DifferentSettingsButton.Kind.Audio:
			pass
		DifferentSettingsButton.Kind.Inputs:
			pass
		DifferentSettingsButton.Kind.Hotkeys:
			pass
		DifferentSettingsButton.Kind.Advanced:
			pass
		DifferentSettingsButton.Kind.Development:
			change_menu(SettingMenuKind.Kind.Development)
		DifferentSettingsButton.Kind.ModSettings:
			pass
		DifferentSettingsButton.Kind.Back:
			Globals.quick_to_main_scene()
	button.button_pressed = false

func development_button_pressed(button:Button) -> void:
	if button.kind != DevelopmentButton.Kind.Back:
		input_control.visible = true
		close_all_development_menus()
		get_node(all_development_menus.get(button.kind)).visible = true
	
	match button.kind:
		DevelopmentButton.Kind.ServerBackend:
			pass
		DevelopmentButton.Kind.ClientBackend:
			pass
		DevelopmentButton.Kind.Back:
			close_all_development_menus()
			input_control.visible = false
			change_menu(SettingMenuKind.Kind.Main)
	button.button_pressed = false
	
	
func close_all_development_menus() -> void:
	for menu_node_path in all_development_menus:
		get_node(menu_node_path).visible = false

func change_menu(kind:SettingMenuKind.Kind) -> void:
	menu_kind = all_menus.keys().get(kind)
	update_menu_show()
	
func update_menu_show():
	for menu_node_path in all_menus.values():
		get_node(menu_node_path).visible = false
	get_node(all_menus.get(menu_kind)).visible = true
	
