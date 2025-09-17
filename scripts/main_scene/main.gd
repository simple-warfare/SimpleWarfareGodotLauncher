extends Control
@export var main_menu_button_group: ButtonGroup
@export var singleplayer_menu_button_group: ButtonGroup
@export var main_menu:Node
@export var singleplayer_menu:Node
@export var all_menus:Dictionary
@export var server_backend_version:Label

var menu_kind:MainMenuKind

func _ready() -> void:
	main_menu_button_group.pressed.connect(main_menu_button_pressed)
	singleplayer_menu_button_group.pressed.connect(singleplayer_menu_button_pressed)
	Backend.receive_server_info.connect(show_server_info)
	change_menu(MainMenuKind.Kind.Main)
	update_menu_show()
		
func main_menu_button_pressed(button:Button) -> void:
	match button.kind:
		MainMenuButton.Kind.Singleplayer:
			change_menu(MainMenuKind.Kind.Singleplayer)
		MainMenuButton.Kind.Multiplayer:
			Globals.quick_to_multiplayer_lobby_scene()
		MainMenuButton.Kind.Mods:
			Globals.quick_to_mods_scene()
		MainMenuButton.Kind.Settings:
			Globals.quick_to_settings_scene()
		MainMenuButton.Kind.Community:
			pass
		MainMenuButton.Kind.News:
			pass
		MainMenuButton.Kind.Quit:
			get_tree().quit()
	
	button.button_pressed = false
func singleplayer_menu_button_pressed(button:Button) -> void:
	match button.kind:
		SingleplayerMenuButton.Kind.Missions:
			pass
		SingleplayerMenuButton.Kind.Skirmish:
			pass
		SingleplayerMenuButton.Kind.SandBox:
			Globals.quick_to_room_scene()
		SingleplayerMenuButton.Kind.Back:
			change_menu(MainMenuKind.Kind.Main)
	button.button_pressed = false

func change_menu(kind:MainMenuKind.Kind) -> void:
	menu_kind = all_menus.keys().get(kind)
	update_menu_show()
	
func update_menu_show():
	for menu_node_path in all_menus.values():
		get_node(menu_node_path).visible = false
	get_node(all_menus.get(menu_kind)).visible = true
	
func show_server_info():
	server_backend_version.text = "Server Backend Version:  " + Backend.server_info.game_version
