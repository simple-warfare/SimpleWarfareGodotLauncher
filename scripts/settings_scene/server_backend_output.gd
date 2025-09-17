extends RichTextLabel


func _ready() -> void:
	var output_buffer:PackedStringArray = Adaptor.server_backend_output_buffer
	Adaptor.server_backend_output.connect(receive_output)
	for line in output_buffer:
		self.append_text(line+'\n')



func receive_output(line:String):
	self.append_text(line+'\n')
