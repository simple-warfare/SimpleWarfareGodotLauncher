extends Resource
class_name MainMenuKind
enum Kind{
	Main,
	Singleplayer,
}

@export var kind: Kind = Kind.Main:
	set(v):
		kind = v
	get():
		return kind
