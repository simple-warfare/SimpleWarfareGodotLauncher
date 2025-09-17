@tool
extends Node

var server_info:ServerInfo = ServerInfo.new()
var state:State = State.Executing
signal receive_server_info
enum State{
	Executing,
	Executed,
	Connecting,
	Open,
	Closing,
	Closed
}

func start() -> void:
	Adaptor.on_server_executed.connect(on_server_executed)
	Adaptor.on_server_connecting.connect(on_server_connecting)
	Adaptor.on_server_open.connect(on_server_open)
	Adaptor.on_server_closing.connect(on_server_closing)
	Adaptor.on_server_closed.connect(on_server_closed)
	Adaptor.server_message_received.connect(server_message_received)
	Adaptor.connect_adaptor()

func on_server_executed():
	state = State.Executed

func on_server_connecting():
	state = State.Connecting

func on_server_closing():
	state = State.Closing

func on_server_closed(reason:String):
	state = State.Closed
	Globals.crash(reason)
	
func on_server_open() -> void:
	state = State.Open
	Adaptor.send_to_server(JSON.stringify(Message.GetServerInfoMessage))
	Adaptor.on_server_open.disconnect(on_server_open)
	
func crate_sandbox_room() -> void:
	pass

func server_message_received(message:Variant) -> void:
	var json = JSON.new()
	var server_message = json.parse_string(message)
	var server_message_kind = Message.SERVER_MESSAGE_KIND_VALUE_MAP.find_key(server_message.kind)
	match server_message_kind:
		Message.ServerMessageKind.ServerInfo:
			server_info.from_content(server_message.content)
			receive_server_info.emit()
			Backend.start_server()
			
			
func start_server() -> void:
	Adaptor.send_to_server(JSON.stringify(Message.StartServerMessage))
	
	
func get_ready_state() -> State:
	return state
