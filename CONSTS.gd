@tool
extends Node

var SERVER_PATH:Dictionary = {
	Globals.OsKind.Linux:"user://simple_warfare_server",
	Globals.OsKind.Windows:"user://simple_warfare_server.exe"
}

const LOADING_SCENE:PackedScene = preload("res://scenes/loading.tscn")
const CRASH_SCENE:PackedScene = preload("res://scenes/crash.tscn")
const NOW_USE_MOD_SET_CONF:String = "user://assets/mod_set/now_use.conf"
const DEFALUT_MOD_SET:String = "user://assets/mod_set/default.json"


const MOD_SET_DIR:String  = "user://assets/mod_set/"
const MODS_DIR:String  = "user://assets/mods/"
const CUSTOM_MODS_DIR:String  = "user://assets/mods/custom/"


const MAIN_SCENE_PATH:String = "res://scenes/main.tscn"
const CRASH_SCENE_PATH:String = "res://scenes/crash.tscn"
const CREATE_ROOM_SCENE_PATH:String = "res://scenes/create_room.tscn"
const GAME_SCENE_PATH:String = "res://scenes/game.tscn"
const INIT_SCENE_PATH:String = "res://scenes/init.tscn"
const LOADING_SCENE_PATH:String = "res://scenes/loading.tscn"
const MODS_SCENE_PATH:String = "res://scenes/mods.tscn"
const MULTIPLAYER_LOBBY_SCENE_PATH:String = "res://scenes/multiplayer_lobby.tscn"
const ROOM_SCENE_PATH:String = "res://scenes/room.tscn"
const SETTINGS_SCENE_PATH:String = "res://scenes/settings.tscn"
const WAITING_SCENE_PATH:String = "res://scenes/waiting.tscn"
