@tool
extends Node
enum ClientMessageKind{
	StartServer,
	GetServerInfo
}
enum ServerMessageKind{
	ServerInfo,
	MapPaths,
}
var SERVER_MESSAGE_KIND_VALUE_MAP = {
	ServerMessageKind.ServerInfo:"ServerInfo",
	ServerMessageKind.MapPaths:"MapPaths",
}

var CLIENT_MESSAGE_KIND_VALUE_MAP = {
	ClientMessageKind.StartServer:"StartServer",
	ClientMessageKind.GetServerInfo:"GetServerInfo",
}

var GetServerInfoMessage = {
	kind = CLIENT_MESSAGE_KIND_VALUE_MAP.get(ClientMessageKind.GetServerInfo)
}

var StartServerMessage = {
	kind = CLIENT_MESSAGE_KIND_VALUE_MAP.get(ClientMessageKind.StartServer)
}
