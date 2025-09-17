extends Control
@onready var crash_reason_label: RichTextLabel = $MainMenu/MarginContainer/Background/MarginContainer/Control/Control2/CrashReason
var crash_reason:String



func _ready() -> void:
	crash_reason_label.text = crash_reason
