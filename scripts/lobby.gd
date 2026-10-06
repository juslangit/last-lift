extends Node

## Steam matchmaking: Quickplay, 4-digit room codes and Steam invites.
## Every match is a Steam lobby (so it can be found and joined) plus a SteamMultiplayerPeer
## between the members and the lobby's owner, who hosts the game. Steam relays the traffic,
## so nobody has to forward ports.
##
## During development this runs on Valve's test app 480 (Spacewar). Lobbies from other test
## games share that app, so every search filters on game = last_lift and our protocol version.

signal hosting                   # we created a lobby and are the host: start the game
signal failed(reason: String)
signal status(text: String)

const APP_ID := 480
const GAME_KEY := "last_lift"
const PROTOCOL := "1"
const PUBLIC := 2                # Steam.LOBBY_TYPE_PUBLIC
const EQUAL := 0                 # Steam.LOBBY_COMPARISON_EQUAL
const WORLDWIDE := 3             # Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE
const ENTER_OK := 1              # Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS

var steam: Object
var ok := false
var why_not := "Steam isn't running."
var user_name := ""
var lobby_id := 0
var mode := ""                   # "quick", "code" or "" (not in a Steam match)
var code := ""
var is_host := false
var _search := ""
var _candidates: Array = []
var _code_tries := 0


func _ready() -> void:
	if Net.flag("nosteam") or DisplayServer.get_name() == "headless":
		why_not = "Steam is switched off for this run."
		return
	if not Engine.has_singleton("Steam"):
		why_not = "The Steam plug-in didn't load."
		return
	steam = Engine.get_singleton("Steam")
	steam.lobby_created.connect(_on_created)
	steam.lobby_joined.connect(_on_joined)
	steam.lobby_match_list.connect(_on_list)
	steam.join_requested.connect(func(id: int, _friend: int): accept_invite(id))
	connect_steam()
	# started by accepting an invite while the game was closed: +connect_lobby <id>
	var args := OS.get_cmdline_args()
	var i := args.find("+connect_lobby")
	if ok and i >= 0 and i + 1 < args.size():
		accept_invite.call_deferred(int(args[i + 1]))


## Start (or retry) the connection to the Steam client.
func connect_steam() -> bool:
	if steam == null:
		return false
	if ok:
		return true
	var r: Dictionary = steam.steamInitEx(APP_ID, true)
	ok = r.status == 0
	if ok:
		user_name = steam.getPersonaName()
	else:
		why_not = "Open Steam and sign in, then try again."
	return ok


# --- what the menu calls -----------------------------------------------------------------

func quickplay() -> void:
	if not _ready_check():
		return
	mode = "quick"
	status.emit("Looking for a lobby…")
	_request("quick", {"mode": "quick"})


func create_room() -> void:
	if not _ready_check():
		return
	mode = "code"
	_code_tries = 0
	_new_code()


func join_code(c: String) -> void:
	if not _ready_check():
		return
	c = c.strip_edges()
	if c.length() != 4 or not c.is_valid_int():
		failed.emit("Room codes are 4 numbers, like 4821.")
		return
	mode = "code"
	code = c
	status.emit("Looking for room %s…" % c)
	_request("code", {"mode": "code", "code": c})


func accept_invite(id: int) -> void:
	if not ok:
		return
	get_tree().call_group("main", "leave_for_invite")  # drop out of any current match first
	leave()
	mode = ""
	status.emit("Joining your friend's room…")
	steam.joinLobby(id)


func invite_friends() -> void:
	if ok and lobby_id != 0:
		steam.activateGameOverlayInviteDialog(lobby_id)


## The host keeps the lobby's listing current, so Quickplay prefers rooms still waiting.
func set_state(state: String) -> void:
	if ok and is_host and lobby_id != 0:
		steam.setLobbyData(lobby_id, "state", state)


func leave() -> void:
	if ok and lobby_id != 0:
		steam.leaveLobby(lobby_id)
	lobby_id = 0
	is_host = false
	mode = ""
	code = ""


# --- searching ---------------------------------------------------------------------------

func _ready_check() -> bool:
	if not connect_steam():
		failed.emit(why_not)
		return false
	leave()
	return true


func _request(kind: String, filters: Dictionary) -> void:
	_search = kind
	steam.addRequestLobbyListStringFilter("game", GAME_KEY, EQUAL)
	steam.addRequestLobbyListStringFilter("ver", PROTOCOL, EQUAL)
	for k in filters:
		steam.addRequestLobbyListStringFilter(k, filters[k], EQUAL)
	steam.addRequestLobbyListDistanceFilter(WORLDWIDE)
	if kind == "quick":
		steam.addRequestLobbyListFilterSlotsAvailable(1)
	steam.requestLobbyList()


func _new_code() -> void:
	code = "%04d" % randi_range(1000, 9999)
	_code_tries += 1
	status.emit("Making a room…")
	_request("codecheck", {"mode": "code", "code": code})


func _on_list(lobbies: Array) -> void:
	match _search:
		"quick":
			# rooms still in their lobby first, then the fullest, so players gather together
			lobbies.sort_custom(func(a, b):
				var wa: bool = steam.getLobbyData(a, "state") == "lobby"
				var wb: bool = steam.getLobbyData(b, "state") == "lobby"
				if wa != wb:
					return wa
				return steam.getNumLobbyMembers(a) > steam.getNumLobbyMembers(b))
			_candidates = lobbies
			_try_next()
		"code":
			if lobbies.is_empty():
				failed.emit("There's no room with code %s. Check the number with your friend." % code)
			else:
				status.emit("Joining room %s…" % code)
				steam.joinLobby(lobbies[0])
		"codecheck":
			if not lobbies.is_empty() and _code_tries < 6:
				_new_code()
			else:
				_create()
	_search = ""


func _try_next() -> void:
	if _candidates.is_empty():
		status.emit("No open games right now. Starting one; other players will join you.")
		_create()
		return
	var id: int = _candidates.pop_front()
	status.emit("Joining %s's game…" % steam.getLobbyData(id, "host"))
	steam.joinLobby(id)


func _create() -> void:
	is_host = true
	steam.createLobby(PUBLIC, Rules.FULL_CAB)


func _on_created(result: int, id: int) -> void:
	if result != 1:
		is_host = false
		failed.emit("Steam couldn't make a room (error %d). Try again." % result)
		return
	lobby_id = id
	steam.setLobbyData(id, "game", GAME_KEY)
	steam.setLobbyData(id, "ver", PROTOCOL)
	steam.setLobbyData(id, "mode", mode)
	steam.setLobbyData(id, "code", code)
	steam.setLobbyData(id, "host", user_name)
	steam.setLobbyData(id, "state", "lobby")
	steam.setLobbyJoinable(id, true)
	if Net.flag("log"):
		print("[steam] lobby %d mode=%s code=%s" % [id, mode, code])
	var peer: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer")
	var err: int = peer.create_host(0)
	if err != OK:
		leave()
		failed.emit("Couldn't start hosting over Steam (error %d)." % err)
		return
	Net.use_peer(peer)
	hosting.emit()


func _on_joined(id: int, _permissions: int, _locked: bool, response: int) -> void:
	if is_host:
		return  # Steam also tells the creator it joined its own lobby
	if response != ENTER_OK:
		if mode == "quick":
			_try_next()
		else:
			failed.emit("Couldn't get into that room. It may be full or closed.")
		return
	lobby_id = id
	if Net.flag("log"):
		print("[steam] joined lobby %d, host %s" % [id, steam.getLobbyOwner(id)])
	if mode == "":
		mode = steam.getLobbyData(id, "mode")
	code = steam.getLobbyData(id, "code")
	var owner: int = steam.getLobbyOwner(id)
	var peer: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer")
	var err: int = peer.create_client(owner, 0)
	if err != OK:
		leave()
		failed.emit("Couldn't connect to the host over Steam (error %d)." % err)
		return
	status.emit("Connecting to %s…" % steam.getLobbyData(id, "host"))
	Net.use_peer(peer)
	# Net.joined fires when the host answers; give up after 20 seconds
	var expected := peer
	get_tree().create_timer(20.0).timeout.connect(func():
		if Net.multiplayer.multiplayer_peer == expected \
				and expected.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
			Net.leave()
			failed.emit("The host didn't answer. Try Quickplay again."))
