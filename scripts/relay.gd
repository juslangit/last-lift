class_name Relay
extends Node

## The browser version's matchmaking. A WebSocket to the Last Lift relay (a Cloudflare Worker,
## relay/src/index.js) hands out room codes, finds Quickplay rooms and passes WebRTC offers,
## answers and ICE candidates. The game itself then runs over WebRTC data channels straight
## between each player and the host's browser; the relay never sees a game message.

signal hosted(code: String)
signal joined_room(code: String, mode: String, host_name: String)
signal none_found
signal failed(reason: String)

const DEFAULT_URL := "wss://last-lift-relay.claude-501.workers.dev/ws"

var url := DEFAULT_URL
var rtc: WebRTCMultiplayerPeer
var _ws := WebSocketPeer.new()
var _state := WebSocketPeer.STATE_CLOSED
var _queue: Array = []
var _ice: Array = []
var _ping := 0.0


func _ready() -> void:
	if Net.opts.has("relay"):
		url = str(Net.opts["relay"])


func send(msg: Dictionary) -> void:
	if _state == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(msg))
		return
	_queue.append(msg)
	if _state == WebSocketPeer.STATE_CLOSED:
		var err := _ws.connect_to_url(url)
		if err != OK:
			_queue.clear()
			failed.emit("Couldn't reach the matchmaking server.")
			return
		_state = WebSocketPeer.STATE_CONNECTING


func close() -> void:
	_queue.clear()
	if _state != WebSocketPeer.STATE_CLOSED:
		_ws.close()
	_state = WebSocketPeer.STATE_CLOSED
	rtc = null


func _process(dt: float) -> void:
	if _state == WebSocketPeer.STATE_CLOSED:
		return
	_ws.poll()
	var s := _ws.get_ready_state()
	if s == WebSocketPeer.STATE_CLOSED:
		var was := _state
		_state = s
		if was == WebSocketPeer.STATE_CONNECTING:
			_queue.clear()
			failed.emit("Couldn't reach the matchmaking server. Check your connection.")
		elif rtc == null:
			failed.emit("Lost the matchmaking server.")
		return
	_state = s
	if s != WebSocketPeer.STATE_OPEN:
		return
	while _ws.get_available_packet_count() > 0:
		var m = JSON.parse_string(_ws.get_packet().get_string_from_utf8())
		if m is Dictionary:
			_on_message(m)
	# keep the socket warm so a host can still be found mid-match
	_ping -= dt
	if _ping <= 0.0:
		_ping = 30.0
		_ws.send_text(JSON.stringify({"t": "ping"}))


func _on_message(m: Dictionary) -> void:
	match str(m.get("t", "")):
		"hello":
			_ice = m.get("ice", [])
			for q in _queue:
				_ws.send_text(JSON.stringify(q))
			_queue.clear()
		"hosted":
			rtc = WebRTCMultiplayerPeer.new()
			rtc.create_server()
			hosted.emit(str(m.code))
		"none":
			none_found.emit()
		"joined":
			var id := int(m.id)
			rtc = WebRTCMultiplayerPeer.new()
			rtc.create_client(id)
			var conn := _connection(1)
			conn.create_offer()
			joined_room.emit(str(m.code), str(m.mode), str(m.get("host", "")))
		"peer":
			if rtc:
				_connection(int(m.id))  # the joiner sends the offer
		"signal":
			_on_signal(int(m.from), m.data)
		"closed":
			# still waiting to connect: the room went away under us (mid-match, WebRTC notices by itself)
			if rtc and rtc.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
				failed.emit("The host closed the room.")
		"error":
			match str(m.get("why", "")):
				"no_room":
					failed.emit("There's no room with that code. Check the number with your friend.")
				"full":
					failed.emit("That room is full.")
				_:
					failed.emit("The matchmaking server is busy. Try again.")


## One WebRTC connection to `peer`, added to the multiplayer peer before any offer is made.
func _connection(peer: int) -> WebRTCPeerConnection:
	var conn := WebRTCPeerConnection.new()
	conn.initialize({"iceServers": _ice})
	conn.session_description_created.connect(func(type: String, sdp: String):
		conn.set_local_description(type, sdp)
		send({"t": "signal", "to": peer, "data": {"type": type, "sdp": sdp}}))
	conn.ice_candidate_created.connect(func(media: String, index: int, cname: String):
		send({"t": "signal", "to": peer, "data": {"type": "ice", "media": media, "index": index, "name": cname}}))
	rtc.add_peer(conn, peer)
	return conn


func _on_signal(from: int, data) -> void:
	if rtc == null or not data is Dictionary or not rtc.has_peer(from):
		return
	var conn: WebRTCPeerConnection = rtc.get_peer(from).connection
	match str(data.get("type", "")):
		"offer", "answer":
			conn.set_remote_description(str(data.type), str(data.sdp))
		"ice":
			conn.add_ice_candidate(str(data.media), int(data.index), str(data.name))
