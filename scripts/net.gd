extends Node

## The connection, and the options the game was started with.
## One player hosts (peer id 1) and is the authority for everything. Over Steam (scripts/lobby.gd)
## the peer is a SteamMultiplayerPeer; on the same Wi-Fi it is ENet by IP.

signal joined                    # a client reached the host
signal failed(reason: String)    # could not connect, or the host went away

var my_name := "Player"
var bots := Rules.FULL_CAB - 1
var opts := {}                   # command-line flags: --host, --join=IP, --bots=N, --autopilot ...


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var a := arg.trim_prefix("--")
		var eq := a.find("=")
		if eq >= 0:
			opts[a.substr(0, eq)] = a.substr(eq + 1)
		else:
			opts[a] = true
	if opts.has("name"):
		my_name = str(opts["name"])
	if opts.has("bots"):
		bots = int(opts["bots"])
	multiplayer.connected_to_server.connect(func(): joined.emit())
	multiplayer.connection_failed.connect(func(): _drop("Could not reach the host."))
	multiplayer.server_disconnected.connect(func(): _drop("The host left the game."))


func flag(name: String) -> bool:
	return opts.has(name)


func host(port := Rules.PORT) -> String:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, Rules.MAX_PLAYERS)
	if err != OK:
		return "Port %d is busy. Is another game already hosting on this computer?" % port
	multiplayer.multiplayer_peer = peer
	return ""


func join(address: String, port := Rules.PORT) -> String:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address.strip_edges(), port)
	if err != OK:
		return "That address doesn't look right."
	multiplayer.multiplayer_peer = peer
	return ""


## Use a peer made elsewhere (the Steam lobby code makes SteamMultiplayerPeers).
func use_peer(peer: MultiplayerPeer) -> void:
	multiplayer.multiplayer_peer = peer


func leave() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	Lobby.leave()


func is_host() -> bool:
	return multiplayer.is_server()


func _drop(reason: String) -> void:
	leave()
	failed.emit(reason)


## Addresses a friend can type to join this computer: home Wi-Fi and Tailscale first.
func local_addresses() -> Array[String]:
	var out: Array[String] = []
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254"):
			out.append(a)
	out.sort_custom(func(x, y): return x.begins_with("192.168") and not y.begins_with("192.168"))
	return out
