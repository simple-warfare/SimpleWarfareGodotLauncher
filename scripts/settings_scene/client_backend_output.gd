extends RichTextLabel




func _ready() -> void:
	var output_buffer:PackedStringArray = Adaptor.client_backend_output_buffer
	for line in output_buffer:
		self.append_text(line+'\n')
