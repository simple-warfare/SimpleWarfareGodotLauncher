class_name ServerConfig

var server_url:String = "ws://127.0.0.1:25570"
var client_url:String = "ws://127.0.0.1:25571"
var server_path:String

func save(path:String) -> void:
	var config = ConfigFile.new()
	
	config.set_value("server","url",server_url)
	config.set_value("client","url",client_url)
	config.save(path)
	
func load(path:String) -> void:
	var config = ConfigFile.new()
	var err = config.load(path)
	if err != OK:
		return
	self.server_path = Consts.SERVER_PATH.get(Globals.get_os_type(),"Unkown")
	if server_path == "Unkown":
		return
	var sections = config.get_sections()
	self.server_url = config.get_value(sections.get(sections.find("server")), "url")
	self.client_url = config.get_value(sections.get(sections.find("client")), "url")
	
