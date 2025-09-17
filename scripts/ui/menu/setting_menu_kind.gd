extends Resource
class_name SettingMenuKind
enum Kind{
	Main,
	#Display,
	#Audio,
	#Inputs,
	#Hotkeys,
	#Advanced,
	Development,
	ModSettings
}

@export var kind: Kind = Kind.Main:
	set(v):
		kind = v
	get():
		return kind
