@tool
extends Node
var server_backend:Dictionary
var server_stdio:FileAccess
var server = WebSocketPeer.new()
var client = WebSocketPeer.new()

var tls_options: TLSOptions = null

signal on_server_executed()
signal on_server_closed(reason:String)
signal on_server_closing()
signal on_server_open()
signal on_server_connecting()

signal on_client_closed(reason:String)
signal on_client_closing()
signal on_client_open()
signal on_client_connecting()
signal server_message_received(message: Variant)
signal client_message_received(message: Variant)

signal server_backend_output(str:String)

var server_backend_output_buffer:PackedStringArray
var client_backend_output_buffer:PackedStringArray

func _ready() -> void:
	set_process(false)

func connect_adaptor() -> int:
	var server_backend_path = FileAccess.open(Globals.server_config.server_path,FileAccess.READ).get_path_absolute()
	server_backend = OS.execute_with_pipe(server_backend_path, [])
	await get_tree().create_timer(1).timeout
	print("start server backend at: " + server_backend_path)
	if server_backend.is_empty():
		Globals.crash("无法启动服务端")
		#Globals.next_scene()
	on_server_executed.emit()
	#print(FileAccess.open(Globals.server_config.server_path,FileAccess.READ).get_path_absolute())
	server_stdio = server_backend.get("stderr")
	set_process(true)
	return connect_to_url(Globals.server_config.server_url,Globals.server_config.client_url)

func connect_to_url(server_url,client_url) -> int:
	var server_err = server.connect_to_url(server_url, tls_options)
	var client_err = client.connect_to_url(client_url, tls_options)
	if server_err != OK:
		return server_err
	if client_err != OK:
		return client_err
	return OK

func send_to_server(message:Variant) -> int:
	return send(server,message)
	
func send_to_client(message:Variant) -> int:
	return send(client,message)
	
func send(socket:WebSocketPeer,message:Variant) -> int:
	if typeof(message) == TYPE_STRING:
		return socket.send_text(message)
	return socket.send(var_to_bytes(message))


func get_message(socket:WebSocketPeer) -> Variant:
	if socket.get_available_packet_count() < 1:
		return null
	var pkt = socket.get_packet()
	return pkt.get_string_from_utf8()


func close(code := 1000, reason := "") -> void:
	server.close(code, reason)


func clear() -> void:
	server = WebSocketPeer.new()


func get_socket() -> WebSocketPeer:
	return server


func poll(socket:WebSocketPeer,connecting:Signal,open:Signal,closing:Signal,closed:Signal,message_received:Signal) -> void:
	var state = socket.get_ready_state()
	if state != socket.STATE_CLOSED:
		socket.poll()
	match state:
		socket.STATE_CONNECTING:
			connecting.emit()
		socket.STATE_OPEN:
			open.emit()
		socket.STATE_CLOSING:
			closing.emit()
		socket.STATE_CLOSED:
			closed.emit(socket.get_close_reason())
	while state == socket.STATE_OPEN and socket.get_available_packet_count():
		server_message_received.emit(get_message(socket))

func read_process_output() :
	if server_stdio.is_open() and server_stdio.get_error() == OK and server_stdio.get_position() < server_stdio.get_length():
		var output = server_stdio.get_line()
		output = output.replace("[0m","[/color]")
		output = output.replace("[31m","[color=red]")
		output = output.replace("[32m","[color=green]")
		output = output.replace("[2m","[color=gray]")
		server_backend_output_buffer.append(output)
		server_backend_output.emit(output)

func _process(delta):
	poll(server,on_server_connecting,on_server_open,on_server_closing,on_client_closed,server_message_received)
	poll(client,on_client_connecting,on_client_open,on_client_closing,on_client_closed,client_message_received)
	read_process_output()
	
func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		OS.kill(server_backend.pid)
		get_tree().quit() # default behavior
