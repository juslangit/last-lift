class_name Game
extends Node3D

## One match. The host (peer 1) runs the clock, the hazards, the loot and who is left
## behind; every peer moves only its own player and draws everyone else from the host's
## snapshots. Methods starting s_ run on the host, c_ on the clients, _srv_ host-only.

signal left_game(reason: String)

# --- shared state (mirrored on every peer) -----------------------------------------------
var phase := "lobby"
var floor_now := Rules.START_FLOOR
var floor_from := Rules.START_FLOOR
var floor_next := Rules.START_FLOOR
var time_left := 0.0
var phase_dur := 0.0
var room_kind := ""
var room_seed := 0
var hold_used := false
var overweight := false
var waiting_weight := false
var cab_kg := 0.0
var round_no := 0
var totals := {}                  # player id -> points over the session
var countdown := -1.0             # Quickplay: seconds until the next round starts, -1 if none
var snap_t := -1.0                # cable snap: seconds left to grab a rail (0 = brake about to bite), -1 when the cable holds
var presses := 0                  # floor buttons ghosts have pressed on this floor
var haunts := {}                  # ghost id -> the living player id it haunts
var ghost_pts := {}               # ghost id -> haunt points this round
var ghost_cd := {}                # my own ghost's powers -> seconds until ready (drawn by the HUD)
var ghost_used_floor := -1        # the floor my ghost last pressed a button on

var info := {}                    # player id -> {name, color, bot}
var players := {}                 # player id -> Player
var loot := {}                    # loot id -> {kind, pos, owner}
var carried := {}                 # player id -> Array[int] of loot ids, oldest first
var brains := {}                  # player id -> Brain, for bots (host) and --autopilot
var nav_map: RID
var me := 1

# --- scene -------------------------------------------------------------------------------
var world: Node3D
var cab: Cab
var room: Room
var nav_region: NavigationRegion3D
var loot_root: Node3D
var people: Node3D
var env_node: WorldEnvironment
var cab_env: Environment
var hud: Hud
var spectator_cam: Camera3D
var ghost_cam: Camera3D
var ghost_yaw := PI
var ghost_pitch := -0.35
var _ghost_pivot: Node3D
var _ghosts_root: Node3D
var _ghost_nodes := {}
var _loot_nodes := {}
var _jolt_shake := 0.0

# --- host only ---------------------------------------------------------------------------
var _rng := RandomNumberGenerator.new()
var _stops: Array[int] = []
var _stop_i := 0
var _t_open := 0.0
var _over_t := 0.0
var _buzz_t := 0.0
var _next_loot := 1
var _ready_peers := {}
var _send_t := 0.0
var _npc_t := 0.0
var _weight_t := 0.0
var _room_order: Array = []
var _bot_seq := 0
var _auto_t := 0.0
var _last_stage := 0
var _alive_at_close := {}
var _snap_stop := -1
var _snap_pending := false
var _descent_t := 0.0
var _jolt_at := -1.0
var _ghost_cool := {}             # ghost id -> {lights, spook, floor}: seconds left, floor of the last button


func _ready() -> void:
	name = "Game"
	me = multiplayer.get_unique_id()
	_build_scene()
	hud = Hud.new()
	add_child(hud)
	hud.game = self
	hud.start_pressed.connect(_on_start)
	hud.bots_changed.connect(_on_bots_changed)
	hud.leave_pressed.connect(func(): _leave(""))
	multiplayer.peer_disconnected.connect(_on_peer_left)
	if multiplayer.is_server():
		_rng.randomize()
		multiplayer.peer_connected.connect(func(id): _log("peer %d connected" % id))
		info[1] = {"name": Net.my_name, "color": 0, "bot": false}
		for i in clampi(Net.bots, 0, Rules.MAX_PLAYERS - 1):
			_add_bot()
		_sync_player_nodes()
		_apply_phase("lobby", Rules.START_FLOOR, Rules.START_FLOOR, 0.0, "", 0)
	else:
		_apply_phase("lobby", Rules.START_FLOOR, Rules.START_FLOOR, 0.0, "", 0)
		s_register.rpc_id(1, Net.my_name)
	if not DisplayServer.get_name() == "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_scene() -> void:
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	cab_env = Environment.new()
	cab_env.background_mode = Environment.BG_COLOR
	cab_env.background_color = Color("0a0806")
	cab_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	cab_env.ambient_light_color = Color("ffe0b8")
	cab_env.ambient_light_energy = 0.35
	cab_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	cab_env.glow_enabled = true
	cab_env.glow_intensity = 0.5
	env_node = WorldEnvironment.new()
	env_node.environment = cab_env
	add_child(env_node)
	cab = Cab.new()
	cab.name = "Cab"
	world.add_child(cab)
	nav_region = NavigationRegion3D.new()
	world.add_child(nav_region)
	nav_map = get_world_3d().navigation_map
	loot_root = Node3D.new()
	loot_root.name = "Loot"
	add_child(loot_root)
	people = Node3D.new()
	people.name = "People"
	add_child(people)
	spectator_cam = Camera3D.new()
	spectator_cam.fov = 78
	add_child(spectator_cam)
	spectator_cam.position = Vector3(1.8, 2.78, 3.85)
	spectator_cam.look_at(Vector3(-0.4, 0.7, 0.2))
	# a ghost's camera floats around the person it haunts
	_ghost_pivot = Node3D.new()
	add_child(_ghost_pivot)
	var arm := SpringArm3D.new()
	arm.spring_length = 3.8
	arm.collision_mask = Build.WORLD
	arm.margin = 0.2
	_ghost_pivot.add_child(arm)
	ghost_cam = Camera3D.new()
	ghost_cam.fov = 72
	ghost_cam.near = 0.05
	arm.add_child(ghost_cam)
	_ghosts_root = Node3D.new()
	_ghosts_root.name = "Ghosts"
	add_child(_ghosts_root)
	_bake_nav()


func _log(msg: String) -> void:
	if Net.flag("log"):
		print("[%s] %s" % ["host" if multiplayer.is_server() else "peer", msg])


# --- players -----------------------------------------------------------------------------

func _add_bot() -> void:
	if info.size() >= Rules.MAX_PLAYERS:
		return
	_bot_seq += 1
	var id := 1000 + _bot_seq
	var used := []
	for v in info.values():
		used.append(v.name)
	var bot_name := "Bot"
	for n in Rules.BOT_NAMES:
		if not used.has(n):
			bot_name = n
			break
	info[id] = {"name": bot_name, "color": _free_color(), "bot": true}


func _remove_bot() -> bool:
	var ids := info.keys()
	ids.sort()
	ids.reverse()
	for id in ids:
		if info[id].bot:
			info.erase(id)
			return true
	return false


func _free_color() -> int:
	var used := []
	for v in info.values():
		used.append(v.color)
	for i in Rules.PLAYER_COLORS.size():
		if not used.has(i):
			return i
	return 0


func _spawn_for(id: int) -> Vector3:
	var ids := info.keys()
	ids.sort()
	return Rules.spawn_spot(maxi(ids.find(id), 0))


func _sync_player_nodes() -> void:
	for id in players.keys():
		if not info.has(id):
			players[id].queue_free()
			players.erase(id)
			brains.erase(id)
			carried.erase(id)
	for id in info:
		if players.has(id):
			continue
		var d: Dictionary = info[id]
		var mode := Player.Mode.PUPPET
		if id == me:
			mode = Player.Mode.LOCAL
		elif d.bot and multiplayer.is_server():
			mode = Player.Mode.BOT
		var p := Player.new()
		p.setup(id, d.name, Rules.PLAYER_COLORS[d.color], mode, _spawn_for(id))
		people.add_child(p)
		players[id] = p
		carried[id] = [] as Array[int]
		if mode == Player.Mode.BOT or (mode == Player.Mode.LOCAL and Net.flag("autopilot")):
			brains[id] = Brain.new(id * 7919 + _rng.randi())
			brains[id].careful = mode == Player.Mode.LOCAL and Net.flag("careful")
	hud.refresh_players()


func _alive_map() -> Dictionary:
	var out := {}
	for id in players:
		out[id] = players[id].alive
	return out


func alive_count() -> int:
	var n := 0
	for p in players.values():
		if p.alive:
			n += 1
	return n


func local_player() -> Player:
	return players.get(me)


@rpc("any_peer", "call_remote", "reliable")
func s_register(display_name: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if info.size() >= Rules.MAX_PLAYERS and not _remove_bot():
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	if info.size() >= Rules.FULL_CAB:
		_remove_bot()  # a person takes a bot's place
	var clean := display_name.strip_edges().substr(0, 16)
	info[id] = {"name": clean if clean != "" else "Player %d" % (info.size() + 1), "color": _free_color(), "bot": false}
	_ready_peers[id] = true
	_sync_player_nodes()
	if phase != "lobby" and phase != "results":
		players[id].set_alive(false)  # joined mid-round: haunt someone until the next one
	_log("%s joined" % info[id].name)
	var loot_list := []
	for lid in loot:
		loot_list.append([lid, loot[lid].kind, loot[lid].pos, loot[lid].owner, loot[lid].wet])
	var state := {
		"phase": phase, "floor": floor_now, "from": floor_from, "next": floor_next, "time": time_left,
		"kind": room_kind, "seed": room_seed, "hold": hold_used, "loot": loot_list, "totals": totals,
		"round": round_no, "stage": room.stage if room else 0, "countdown": countdown,
		"snap": snap_t, "presses": presses,
	}
	c_welcome.rpc_id(id, info, _alive_map(), state)
	_broadcast_players()
	_srv_reassign()
	hud.feed("%s joined the lift" % info[id].name)


func _broadcast_players() -> void:
	var alive := _alive_map()
	for pid in _ready_peers:
		c_players.rpc_id(pid, info, alive)


@rpc("authority", "call_remote", "reliable")
func c_welcome(all: Dictionary, alive: Dictionary, state: Dictionary) -> void:
	info = all
	_sync_player_nodes()
	for id in alive:
		if players.has(id):
			players[id].set_alive(alive[id])
	totals = state.totals
	round_no = state.round
	countdown = state.get("countdown", -1.0)
	_apply_phase(state.phase, state.from, state.next, state.time, state.kind, state.seed)
	floor_now = state.floor
	hold_used = state.hold
	if room:
		room.stage = state.stage
	snap_t = state.get("snap", -1.0)
	presses = state.get("presses", 0)
	for l in state.loot:
		_loot_add(l[0], l[1], l[2], l[3], l[4])
	_after_alive_change()
	_log("welcomed: phase %s, %d players" % [phase, info.size()])


@rpc("authority", "call_remote", "reliable")
func c_players(all: Dictionary, alive: Dictionary) -> void:
	info = all
	_sync_player_nodes()
	for id in alive:
		if players.has(id):
			players[id].set_alive(alive[id])
	_after_alive_change()


func _on_peer_left(id: int) -> void:
	if not multiplayer.is_server() or not info.has(id):
		return
	var who: String = info[id].name
	for lid in carried.get(id, []).duplicate():
		_srv_place(lid, players[id].position * Vector3(1, 0, 1))
	info.erase(id)
	_ready_peers.erase(id)
	_sync_player_nodes()
	_broadcast_players()
	_fx_all("feed:%s left the game" % who, Vector3.ZERO)
	_srv_reassign()


func _on_bots_changed(delta: int) -> void:
	if not multiplayer.is_server() or (phase != "lobby" and phase != "results"):
		return
	if delta > 0:
		_add_bot()
	else:
		_remove_bot()
	_sync_player_nodes()
	_broadcast_players()


# --- phases ------------------------------------------------------------------------------

func _apply_phase(p: String, from: int, to: int, dur: float, kind: String, seed_value: int) -> void:
	phase = p
	phase_dur = dur
	time_left = dur
	floor_from = from
	floor_next = to
	_log("phase %s %d->%d %.1fs %s" % [p, from, to, dur, kind])
	match p:
		"lobby":
			floor_now = Rules.START_FLOOR
			cab.set_doors(false, true)
			cab.set_floor_text(Rules.floor_label(floor_now))
			Sound.stop_loops()
		"descent":
			floor_now = from
			cab.set_doors(false)
			hold_used = false
			presses = 0
			snap_t = -1.0
			cab.set_hold_used(false)
			env_node.environment = cab_env
			_build_room(kind, seed_value)
			Sound.stop_loops()
			Sound.loop("rumble", true, -4.0)
		"open":
			floor_now = to
			cab.set_floor_text(Rules.floor_label(floor_now))
			cab.set_doors(true)
			if room and room.env:
				env_node.environment = room.env
			Sound.loop("rumble", false)
			Sound.play("ding", -2.0)
			Sound.play("door_open", -6.0)
			hud.banner(Rules.ROOM_NAMES.get(room_kind, ""), Rules.ROOM_HAZARDS.get(room_kind, ""))
		"closing":
			cab.set_doors(false)
			Sound.play("door_close", -4.0)
			Sound.loop("fire", false)
		"crash":
			Sound.stop_loops()
			Sound.loop("rumble", true, 0.0)
			env_node.environment = cab_env
			_clear_room()
			hud.banner("BRAKES GONE", "Hold on. Next stop: the lobby.")
			Sound.play("snap")
		"results":
			Sound.stop_loops()
			cab.set_floor_text("L")
	hud.on_phase()


func _build_room(kind: String, seed_value: int) -> void:
	if room and room_kind == kind and room_seed == seed_value:
		return
	_clear_room(false)
	room_kind = kind
	room_seed = seed_value
	room = Room.create(kind, seed_value)
	world.add_child(room)
	_bake_nav()


func _clear_room(rebake := true) -> void:
	if room:
		room.queue_free()
		world.remove_child(room)
		room = null
		if rebake:
			_bake_nav()


func _bake_nav() -> void:
	var nm := NavigationMesh.new()
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.agent_radius = 0.5
	nm.agent_height = 1.5
	nm.agent_max_climb = 0.25
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = Build.WORLD | Build.NAV_ONLY
	nm.filter_baking_aabb = AABB(Vector3(-10, -0.5, -17), Vector3(20, 4, 22))
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, src, world)
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	nav_region.navigation_mesh = nm


func _send_phase(p: String, from: int, to: int, dur: float, kind := "", seed_value := 0) -> void:
	_apply_phase(p, from, to, dur, kind, seed_value)
	Lobby.set_state("lobby" if p == "lobby" or p == "results" else "playing")
	for pid in _ready_peers:
		c_phase.rpc_id(pid, p, from, to, dur, kind, seed_value)


@rpc("authority", "call_remote", "reliable")
func c_phase(p: String, from: int, to: int, dur: float, kind: String, seed_value: int) -> void:
	_apply_phase(p, from, to, dur, kind, seed_value)


func _on_start() -> void:
	if multiplayer.is_server() and (phase == "lobby" or phase == "results"):
		_srv_start_round()


func _srv_start_round() -> void:
	round_no += 1
	_set_countdown(-1.0)
	_stops = Rules.floor_plan(_rng)
	_stop_i = 0
	# most rounds have one snap, never on the first drop (everyone is still finding their feet)
	_snap_stop = _rng.randi_range(1, _stops.size() - 1) if _rng.randf() < Rules.SNAP_CHANCE else -1
	match str(Net.opts.get("snap", "")):
		"always":
			_snap_stop = -2
		"never":
			_snap_stop = -1
	_ghost_cool.clear()
	for lid in loot.keys():
		_srv_remove(lid)
	for id in info:
		totals[id] = totals.get(id, 0)
	var alive := {}
	for id in players:
		alive[id] = true
	_round_start(round_no, alive)
	for pid in _ready_peers:
		c_round_start.rpc_id(pid, round_no, alive)
	_log("round %d: stops %s" % [round_no, str(_stops)])
	_srv_descent(_stops[0], Rules.DESCENT_TIME - 1.0)


@rpc("authority", "call_remote", "reliable")
func c_round_start(n: int, alive: Dictionary) -> void:
	_round_start(n, alive)


func _round_start(n: int, alive: Dictionary) -> void:
	round_no = n
	for id in alive:
		if players.has(id):
			var p: Player = players[id]
			p.set_alive(alive[id])
			if p.is_controlled_here():
				p.teleport(_spawn_for(id))
			p.set_carried([] as Array[int], [] as Array[String])
			carried[id] = [] as Array[int]
	haunts.clear()
	ghost_pts.clear()
	ghost_cd.clear()
	ghost_used_floor = -1
	snap_t = -1.0
	hud.hide_results()
	_after_alive_change()
	hud.feed("Round %d. Floor 40. The cable is fraying." % n)


func _srv_descent(to: int, dur := Rules.DESCENT_TIME) -> void:
	if _room_order.is_empty():
		_room_order = Rules.ROOMS.duplicate()
		if Net.opts.has("rooms"):
			_room_order = str(Net.opts["rooms"]).split(",")
		else:
			_shuffle(_room_order)
	var kind: String = _room_order.pop_front()
	_descent_t = 0.0
	_jolt_at = -1.0
	_snap_pending = _snap_stop == -2 or _snap_stop == _stop_i
	if _snap_pending:
		dur += Rules.SNAP_EXTRA
	_send_phase("descent", floor_now, to, dur, kind, _rng.randi())
	# lay out the loot for the floor while the doors are still shut
	var pts := room.loot_points.duplicate()
	_shuffle(pts)
	var count := mini(pts.size(), 5 + int(ceil(alive_count() * 1.25)))
	var kinds: Array = Rules.ROOM_LOOT[kind]
	var list := []
	for i in count:
		var lid := _next_loot
		_next_loot += 1
		var k: String = kinds[_rng.randi() % kinds.size()]
		_loot_add(lid, k, pts[i], 0)
		list.append([lid, k, pts[i], 0, false])
	for pid in _ready_peers:
		c_loot_spawn.rpc_id(pid, list)


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


func _srv_open() -> void:
	_t_open = 0.0
	_over_t = 0.0
	_last_stage = 0
	_send_phase("open", floor_from, floor_next, Rules.OPEN_TIME, room_kind, room_seed)


func _srv_close() -> void:
	waiting_weight = false
	_send_phase("closing", floor_now, floor_now, Rules.DOOR_ANIM, room_kind, room_seed)


func _srv_after_close() -> void:
	for id in players:
		var p: Player = players[id]
		if p.alive and not Rules.inside_cab(p.true_pos()):
			_srv_eliminate(id, "left behind on floor %d" % floor_now)
	for lid in loot.keys():
		if loot[lid].owner == 0 and not Rules.inside_cab(loot[lid].pos):
			_srv_remove(lid)
	if alive_count() == 0:
		_srv_results()
		return
	_stop_i += 1
	if _stop_i < _stops.size():
		_srv_descent(_stops[_stop_i])
	else:
		_send_phase("crash", floor_now, 0, Rules.CRASH_TIME, "", 0)


func _srv_eliminate(id: int, why: String) -> void:
	for lid in carried.get(id, []).duplicate():
		_srv_remove(lid)
	_eliminated(id, why)
	for pid in _ready_peers:
		c_eliminated.rpc_id(pid, id, why)
	# whoever was haunting them gets the credit
	for g in haunts:
		if haunts[g] == id and g != id:
			ghost_pts[g] = ghost_pts.get(g, 0) + Rules.HAUNT_POINTS
			_fx_all("feed:%s's ghost cackles  +%d" % [info[g].name if info.has(g) else "?", Rules.HAUNT_POINTS], Vector3.ZERO)
			_log("HAUNT %s scored on %s" % [info[g].name if info.has(g) else "?", info[id].name])
	_srv_reassign()


## Every ghost haunts someone alive: a new ghost, or one whose person just died, picks the
## living player carrying the most.
func _srv_reassign() -> void:
	if not multiplayer.is_server():
		return
	var in_round := phase == "descent" or phase == "open" or phase == "closing" or phase == "crash"
	var changed := false
	for id in players:
		var p: Player = players[id]
		if p.alive or not in_round:
			if haunts.has(id):
				haunts.erase(id)
				changed = true
			continue
		var t: int = haunts.get(id, 0)
		if t == 0 or not players.has(t) or not players[t].alive:
			var best := _richest_alive(id)
			if best != t:
				changed = true
				if best == 0:
					haunts.erase(id)
				else:
					haunts[id] = best
	for g in haunts.keys():
		if not players.has(g):
			haunts.erase(g)
			changed = true
	if changed:
		_send_haunts()


func _richest_alive(except: int) -> int:
	var best := 0
	var best_v := -1
	for id in players:
		var p: Player = players[id]
		if id == except or not p.alive:
			continue
		var v := carried_value(id) * 10 + _rng.randi_range(0, 9)
		if v > best_v:
			best_v = v
			best = id
	return best


func carried_value(id: int) -> int:
	var v := 0
	for lid in carried.get(id, []):
		v += Rules.loot_value(loot[lid].kind)
	return v


func _send_haunts() -> void:
	_haunts(haunts, ghost_pts)
	for pid in _ready_peers:
		c_haunts.rpc_id(pid, haunts, ghost_pts)


@rpc("authority", "call_remote", "reliable")
func c_haunts(h: Dictionary, pts: Dictionary) -> void:
	_haunts(h, pts)


func _haunts(h: Dictionary, pts: Dictionary) -> void:
	var before := _haunting_me()
	haunts = h.duplicate()
	ghost_pts = pts.duplicate()
	var now := _haunting_me()
	var lp := local_player()
	if lp and lp.alive and now > before:
		hud.feed("A ghost is haunting you" if now == 1 else "%d ghosts are haunting you" % now)


func _haunting_me() -> int:
	var n := 0
	for g in haunts:
		if haunts[g] == me:
			n += 1
	return n


@rpc("authority", "call_remote", "reliable")
func c_eliminated(id: int, why: String) -> void:
	_eliminated(id, why)


func _eliminated(id: int, why: String) -> void:
	if not players.has(id):
		return
	players[id].set_alive(false)
	var who: String = info[id].name if info.has(id) else "?"
	hud.feed("%s was %s" % [who, why])
	_log("ELIMINATED %s %s" % [who, why])
	Sound.play("left_behind", -4.0)
	if id == me:
		hud.big("LEFT BEHIND", "You were %s. Now you're a ghost. Haunt the living." % why)
	_after_alive_change()


func _after_alive_change() -> void:
	var lp := local_player()
	if lp == null:
		return
	if lp.alive and lp.camera:
		lp.camera.current = true
	else:
		spectator_cam.current = true
	hud.set_spectating(not lp.alive)


func _srv_results() -> void:
	var rows := []
	for id in info:
		var p: Player = players.get(id)
		var alive_now: bool = p != null and p.alive
		var ghost: int = ghost_pts.get(id, 0)
		var haul := (carried_value(id) if alive_now else 0) + ghost
		totals[id] = totals.get(id, 0) + haul
		rows.append([id, info[id].name, haul, totals[id], alive_now, ghost])
	rows.sort_custom(func(a, b): return a[2] > b[2] if a[2] != b[2] else a[3] > b[3])
	_send_phase("results", 0, 0, 0.0)
	_results(rows, totals)
	for pid in _ready_peers:
		c_results.rpc_id(pid, rows, totals)
	_auto_t = 0.0


@rpc("authority", "call_remote", "reliable")
func c_results(rows: Array, all_totals: Dictionary) -> void:
	_results(rows, all_totals)


func _results(rows: Array, all_totals: Dictionary) -> void:
	totals = all_totals
	for r in rows:
		_log("RESULT round=%d name=%s haul=%d total=%d survived=%s" % [round_no, r[1], r[2], r[3], r[4]])
	Sound.play("crash", 0.0)
	Sound.play("fanfare", -6.0)
	hud.flash()
	hud.show_results(rows)
	if not multiplayer.is_server() and Net.flag("quit") and round_no >= int(Net.opts.get("rounds", 1)):
		get_tree().create_timer(1.0).timeout.connect(get_tree().quit)


# --- the host's clock --------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	var wading := room != null and (phase == "open" or phase == "closing")
	for id in players:
		var p: Player = players[id]
		if p.is_controlled_here():
			p.slow = room.wade(p.position) if wading else 1.0
	if snap_t > 0.0:
		snap_t = maxf(snap_t - dt, 0.0)
	var lp := local_player()
	if lp and lp.mode == Player.Mode.LOCAL and not Net.flag("autopilot"):
		lp.gripping = lp.alive and snap_active() and Input.is_action_pressed("interact") \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Rules.can_hold_rail(lp.position)
	for id in brains:
		var p: Player = players.get(id)
		if p and p.is_controlled_here():
			brains[id].tick(dt, p, self)
	if multiplayer.is_server():
		_srv_tick(dt)
	else:
		time_left = maxf(time_left - dt, 0.0)
	_send_t -= dt
	if _send_t <= 0.0:
		_send_t = 0.05
		_send_states()


func _process(dt: float) -> void:
	# the fake fall: shake, flicker and the floor display counting down
	var shake := 0.0
	cab.flicker = 0.0
	if phase == "descent" and phase_dur > 0.0:
		var k := 1.0 - time_left / phase_dur
		cab.set_floor_text(Rules.floor_label(int(round(lerpf(floor_from, floor_next, k)))))
		shake = 0.35
		cab.flicker = 0.3
	elif phase == "crash" and phase_dur > 0.0:
		var k := 1.0 - time_left / phase_dur
		cab.set_floor_text(Rules.floor_label(int(round(lerpf(floor_from, 0, k * k)))))
		shake = 0.6 + k * 2.6
		cab.flicker = 0.9
	if snap_active():
		shake = 1.3
		cab.flicker = 1.0
	_jolt_shake = maxf(_jolt_shake - dt, 0.0)
	shake += _jolt_shake * 6.0
	var lp := local_player()
	if lp:
		lp.shake = shake
	for n in loot_root.get_children():
		(n as Node3D).rotate_y(dt * 0.8)
	_draw_hidden_loot()
	_draw_ghosts()
	_pick_camera()
	for k in ghost_cd.keys():
		ghost_cd[k] = maxf(ghost_cd[k] - dt, 0.0)
	hud.update_hud(dt)


func _srv_tick(dt: float) -> void:
	match phase:
		"lobby":
			_auto_t += dt
			if Lobby.mode == "quick":
				_quick_lobby(dt)
			if Net.flag("autostart") and _auto_t > 1.5:
				var need := 1
				if Net.opts["autostart"] is String:
					need = int(Net.opts["autostart"])
				if _humans() >= need:
					_srv_start_round()
		"descent":
			time_left -= dt
			_descent_t += dt
			if _snap_pending and _descent_t >= Rules.SNAP_AT:
				_snap_pending = false
				_jolt_at = _descent_t + Rules.SNAP_GRAB
				_snap(Rules.SNAP_GRAB)
				for pid in _ready_peers:
					c_snap.rpc_id(pid, Rules.SNAP_GRAB)
				_log("SNAP the cable went on the way to %d" % floor_next)
			if _jolt_at > 0.0 and snap_t <= 0.0:
				_jolt_at = -1.0
				_srv_jolt()
			if time_left <= 0.0:
				_srv_open()
		"open":
			_t_open += dt
			time_left = maxf(time_left - dt, 0.0)
			_srv_hazard(dt)
			_srv_weight(dt)
			if time_left <= 0.0:
				if overweight:
					waiting_weight = true
					_over_t += dt
					_buzz_t -= dt
					if _buzz_t <= 0.0:
						_buzz_t = 1.2
						_fx_all("buzzer", Vector3(0, 2, 0.5))
					if _over_t >= Rules.OVERWEIGHT_GRACE:
						_srv_strain()
						_srv_close()
				else:
					_srv_close()
		"closing":
			time_left -= dt
			if time_left <= 0.0:
				_srv_after_close()
		"crash":
			time_left -= dt
			if time_left <= 0.0:
				_srv_results()
		"results":
			_auto_t += dt
			if Lobby.mode == "quick":
				if countdown < 0.0:
					_set_countdown(Rules.QUICK_NEXT)
				_set_countdown(countdown - dt)
				if countdown <= 0.0:
					_srv_start_round()
					return
			var rounds := int(Net.opts.get("rounds", 0))
			if rounds > 0 and _auto_t > 3.0:
				if round_no < rounds:
					_srv_start_round()
				elif Net.flag("quit") and _auto_t > 4.0:
					get_tree().quit()


## Quickplay rooms start themselves: a countdown once a second person arrives.
func _quick_lobby(dt: float) -> void:
	var humans := _humans()
	if humans < 2:
		_set_countdown(-1.0)
		return
	var t := countdown if countdown >= 0.0 else Rules.QUICK_WAIT
	if humans >= Rules.FULL_CAB:
		t = minf(t, Rules.QUICK_FULL_WAIT)
	_set_countdown(t - dt)
	if countdown <= 0.0:
		_srv_start_round()


func _set_countdown(t: float) -> void:
	var before := int(ceil(countdown))
	countdown = t
	if int(ceil(t)) != before:
		for pid in _ready_peers:
			c_countdown.rpc_id(pid, t)


@rpc("authority", "call_remote", "reliable")
func c_countdown(t: float) -> void:
	countdown = t


func _humans() -> int:
	var n := 0
	for v in info.values():
		if not v.bot:
			n += 1
	return n


func _people_list() -> Array:
	var out := []
	for id in players:
		var p: Player = players[id]
		if p.alive:
			out.append({"id": id, "pos": p.true_pos(), "out": not Rules.inside_cab(p.true_pos()), "value": carried_value(id)})
	return out


func _srv_hazard(dt: float) -> void:
	if room == null:
		return
	for h in room.server_tick(dt, _t_open, _people_list(), nav_map):
		var p: Player = players.get(h.id)
		if p == null:
			continue
		_knock(h.id, h.impulse, h.stun)
		if h.get("steal", false) and not carried[h.id].is_empty():
			var took: int = carried[h.id].back()
			var what := Rules.loot_name(loot[took].kind)
			_srv_place(took, room.pit_spot())
			_fx_all("feed:The toddler took %s's %s back to the ball pit" % [info[h.id].name, what.to_lower()], Vector3.ZERO)
		for i in h.drop:
			if not carried[h.id].is_empty():
				var lid: int = carried[h.id].back()
				_srv_place(lid, _ground(p.position + Vector3(randf_range(-0.8, 0.8), 0, randf_range(-0.8, 0.8))))
		_fx_all(h.get("sound", "shove"), p.position)
	if room.stage != _last_stage:
		_last_stage = room.stage
		for pid in _ready_peers:
			c_hazard.rpc_id(pid, room.stage)
		_hazard_changed(room.stage)
	if room.kind == "fire":
		for lid in loot.keys():
			if loot[lid].owner == 0 and room.burning(loot[lid].pos):
				_srv_remove(lid)
	if room.kind == "spa":
		var level := room.water_level()
		for lid in loot:
			var l: Dictionary = loot[lid]
			if l.owner == 0 and not l.wet and l.pos.z < Room.FRONT and l.pos.y + 0.05 < level:
				_set_wet(lid)
				for pid in _ready_peers:
					c_loot_wet.rpc_id(pid, lid)
	_npc_t -= dt
	if _npc_t <= 0.0 and not room.npcs.is_empty():
		_npc_t = 1.0 / 15.0
		var st := room.npc_state()
		for pid in _ready_peers:
			c_npcs.rpc_id(pid, st)


@rpc("authority", "call_remote", "reliable")
func c_hazard(stage: int) -> void:
	if room:
		room.stage = stage
	_hazard_changed(stage)


func _hazard_changed(stage: int) -> void:
	if room_kind == "fire" and stage > 0:
		Sound.loop("fire", true, -8.0 + stage * 1.5)
		hud.feed("The fire has reached row %d" % stage)


@rpc("authority", "call_remote", "unreliable_ordered")
func c_npcs(state: Array) -> void:
	if room:
		room.apply_npc_state(state)


func _srv_weight(dt: float) -> void:
	var kg := 0.0
	for id in players:
		var p: Player = players[id]
		if p.alive and Rules.inside_cab(p.true_pos()):
			kg += Rules.PLAYER_KG + p.carried_kg
	for lid in loot:
		if loot[lid].owner == 0 and Rules.inside_cab(loot[lid].pos):
			kg += loot_kg(lid)
	cab_kg = kg
	overweight = kg > Rules.CAB_LIMIT_KG
	_weight_t -= dt
	if _weight_t <= 0.0:
		_weight_t = 0.2
		for pid in _ready_peers:
			c_weight.rpc_id(pid, cab_kg, overweight, waiting_weight)


@rpc("authority", "call_remote", "unreliable_ordered")
func c_weight(kg: float, over: bool, waiting: bool) -> void:
	cab_kg = kg
	overweight = over
	waiting_weight = waiting


## The cable gives: everything in the cab is lost, and the doors slam.
func _srv_strain() -> void:
	for id in players:
		var p: Player = players[id]
		if p.alive and Rules.inside_cab(p.true_pos()):
			for lid in carried[id].duplicate():
				_srv_remove(lid)
	for lid in loot.keys():
		if loot[lid].owner == 0 and Rules.inside_cab(loot[lid].pos):
			_srv_remove(lid)
	_fx_all("snap", Vector3(0, 2, 2))
	_fx_all("feed:The cable strained. Everything in the cab fell down the shaft.", Vector3.ZERO)


# --- the cable snap ----------------------------------------------------------------------

func snap_active() -> bool:
	return snap_t >= 0.0


@rpc("authority", "call_remote", "reliable")
func c_snap(grab: float) -> void:
	_snap(grab)


func _snap(grab: float) -> void:
	snap_t = grab
	Sound.play("snap", 0.0)
	Sound.play("buzzer", -6.0)
	var lp := local_player()
	if lp and lp.alive:
		hud.big("CABLE SNAPPED!", "Get to a wall rail and hold E")
	else:
		hud.feed("The cable snapped. Will they hold on?")


## The emergency brake bites. Anyone not holding a rail is thrown and loses half their loot
## onto the cab floor, where anyone can pick it up.
func _srv_jolt() -> void:
	var lost := []
	for id in players:
		var p: Player = players[id]
		if not p.alive or not Rules.inside_cab(p.true_pos()):
			continue
		if p.gripping and Rules.can_hold_rail(p.true_pos()):
			continue
		var n := Rules.snap_drops(carried[id].size())
		for i in n:
			var lid: int = carried[id].back()
			_srv_place(lid, Vector3(_rng.randf_range(-1.6, 1.6), 0.0, _rng.randf_range(0.6, 3.6)))
		_knock(id, Vector3(_rng.randf_range(-3, 3), 4.5, _rng.randf_range(-1, 2)), 1.0)
		lost.append([id, n])
	_jolt(lost)
	for pid in _ready_peers:
		c_jolt.rpc_id(pid, lost)
	_log("JOLT %d people lost their grip" % lost.size())


@rpc("authority", "call_remote", "reliable")
func c_jolt(lost: Array) -> void:
	_jolt(lost)


func _jolt(lost: Array) -> void:
	snap_t = -1.0
	_jolt_shake = 0.6
	Sound.play("slam", 0.0)
	Sound.play("crash", -10.0)
	for id in players:
		players[id].gripping = false
	var names := []
	var mine := -1
	for l in lost:
		if info.has(l[0]):
			names.append(info[l[0]].name)
		if l[0] == me:
			mine = l[1]
	var lp := local_player()
	if lp and lp.alive:
		if mine < 0:
			hud.big("HELD ON!", "The brakes caught. Your loot is safe.")
		elif mine == 0:
			hud.big("THROWN!", "You weren't holding a rail. Good thing your hands were empty.")
		else:
			hud.big("LOST YOUR GRIP!", "%d item%s went flying. Grab them off the floor." % [mine, "" if mine == 1 else "s"])
	if not names.is_empty():
		hud.feed("Lost their grip: " + ", ".join(names))
	else:
		hud.feed("Everyone held on")


# --- ghosts ------------------------------------------------------------------------------

## A ghost's three powers: "lights" (the cab goes dark), "button" (the doors close sooner) and
## "spook" (the room's hazard goes for the haunted person).
func act_ghost(p: Player, power: String) -> void:
	if multiplayer.is_server():
		_srv_ghost(p.pid, power)
	elif p.pid == me:
		s_ghost.rpc_id(1, power)


func act_haunt(p: Player, target: int) -> void:
	if multiplayer.is_server():
		_srv_haunt(p.pid, target)
	elif p.pid == me:
		s_haunt.rpc_id(1, target)


@rpc("any_peer", "call_remote", "reliable")
func s_ghost(power: String) -> void:
	_srv_ghost(multiplayer.get_remote_sender_id(), power)


@rpc("any_peer", "call_remote", "reliable")
func s_haunt(target: int) -> void:
	_srv_haunt(multiplayer.get_remote_sender_id(), target)


func _srv_haunt(gid: int, target: int) -> void:
	if not haunts.has(gid) or not players.has(target) or not players[target].alive or target == gid:
		return
	if haunts[gid] != target:
		haunts[gid] = target
		_send_haunts()


func _srv_ghost(gid: int, power: String) -> void:
	if not haunts.has(gid) or not players.has(gid) or players[gid].alive:
		return
	var target: int = haunts[gid]
	var c: Dictionary = _ghost_cool.get(gid, {"lights": 0.0, "spook": 0.0, "floor": -1})
	_ghost_cool[gid] = c
	var why := ""
	var value := 0.0
	match power:
		"lights":
			if c.lights > 0.0:
				why = "Lights out recharging"
			elif cab.blackout > 0.0:
				why = "The lights are already out"
			elif phase != "descent" and phase != "open" and phase != "closing":
				why = "Nothing to haunt right now"
			else:
				c.lights = Rules.FLICKER_COOL
		"button":
			if phase != "open" or waiting_weight:
				why = "The doors aren't open"
			elif c.floor == floor_now:
				why = "You already pressed a button on this floor"
			elif presses >= Rules.BUTTON_PER_FLOOR:
				why = "The panel's jammed: too many ghosts pressing it"
			elif time_left <= Rules.BUTTON_MIN_LEFT + 0.5:
				why = "Too late to press it"
			else:
				c.floor = floor_now
				value = maxf(time_left - Rules.BUTTON_CUT, Rules.BUTTON_MIN_LEFT)
		"spook":
			var t: Player = players.get(target)
			if c.spook > 0.0:
				why = "Spook recharging"
			elif phase != "open" or room == null:
				why = "The doors aren't open"
			elif t == null or not t.alive or Rules.inside_cab(t.true_pos()):
				why = "%s is inside the cab. Wait until they step out" % (info[target].name if info.has(target) else "They")
			else:
				c.spook = Rules.SPOOK_COOL
				room.spook(target)
		_:
			return
	if why != "":
		if gid == me:
			hud.ghost_says(why)
		elif _ready_peers.has(gid):
			c_ghost_denied.rpc_id(gid, why)
		return
	_log("GHOST %s used %s on %s" % [info[gid].name, power, info[target].name if info.has(target) else "?"])
	_power(gid, power, target, value)
	for pid in _ready_peers:
		c_power.rpc_id(pid, gid, power, target, value)


@rpc("authority", "call_remote", "reliable")
func c_ghost_denied(why: String) -> void:
	hud.ghost_says(why)


@rpc("authority", "call_remote", "reliable")
func c_power(gid: int, power: String, target: int, value: float) -> void:
	_power(gid, power, target, value)


func _power(gid: int, power: String, target: int, value: float) -> void:
	var ghost: String = info[gid].name if info.has(gid) else "Someone"
	var who: String = info[target].name if info.has(target) else "someone"
	match power:
		"lights":
			cab.blackout = Rules.FLICKER_TIME
			Sound.play("buzzer", -8.0, 0.6)
			hud.feed("%s's ghost killed the lights" % ghost)
		"button":
			presses += 1
			time_left = value
			Sound.play("button", 0.0, 0.8)
			hud.feed("%s's ghost pressed a button: doors close in %d" % [ghost, int(ceil(value))])
		"spook":
			Sound.play("slam", -6.0, 0.7)
			var hazard := {"office": "the conga line", "fire": "a flare-up", "zoo": "the gorilla", "spa": "a wave",
				"vault": "the lasers", "daycare": "the toddler"}
			hud.feed("%s's ghost set %s on %s" % [ghost, hazard.get(room_kind, "the room"), who])
	if gid == me:
		match power:
			"lights":
				ghost_cd["lights"] = Rules.FLICKER_COOL
			"spook":
				ghost_cd["spook"] = Rules.SPOOK_COOL
			"button":
				ghost_used_floor = floor_now


## What my ghost is haunting right now (0 if I'm alive or have no one).
func my_haunt() -> int:
	var lp := local_player()
	if lp == null or lp.alive:
		return 0
	var t: int = haunts.get(me, 0)
	return t if players.has(t) and players[t].alive else 0


func _cycle_haunt(step: int) -> void:
	var lp := local_player()
	if lp == null or lp.alive or not haunts.has(me):
		return
	var ids := []
	for id in players:
		if players[id].alive:
			ids.append(id)
	if ids.is_empty():
		return
	ids.sort()
	var i := ids.find(haunts[me])
	var next: int = ids[posmod(i + step, ids.size())]
	act_haunt(lp, next)


func _pick_camera() -> void:
	var lp := local_player()
	if lp == null:
		return
	if lp.alive:
		if lp.camera and not lp.camera.current:
			lp.camera.current = true
		return
	var t := my_haunt()
	if t == 0:
		if not spectator_cam.current:
			spectator_cam.current = true
		return
	var tp: Player = players[t]
	_ghost_pivot.position = _ghost_pivot.position.lerp(tp.position + Vector3(0, 1.7, 0), 0.25)
	_ghost_pivot.rotation = Vector3(ghost_pitch, ghost_yaw, 0)
	if not ghost_cam.current:
		_ghost_pivot.position = tp.position + Vector3(0, 1.7, 0)
		ghost_cam.current = true


## Pale floating ghosts hover behind whoever they haunt, so everyone can see who is cursed.
func _draw_ghosts() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for gid in _ghost_nodes.keys():
		if not haunts.has(gid) or not players.has(haunts[gid]):
			_ghost_nodes[gid].queue_free()
			_ghost_nodes.erase(gid)
	var count := {}
	for gid in haunts:
		var target: int = haunts[gid]
		if not players.has(target):
			continue
		if not _ghost_nodes.has(gid):
			var c: Color = Rules.PLAYER_COLORS[info[gid].color] if info.has(gid) else Color.WHITE
			var node := Body.ghost(c)
			_ghosts_root.add_child(node)
			node.position = players[target].position
			_ghost_nodes[gid] = node
		var n: Node3D = _ghost_nodes[gid]
		var k: int = count.get(target, 0)
		count[target] = k + 1
		var tp: Player = players[target]
		# hover over a shoulder, above head height; more ghosts on the same person spread round them
		var a := tp.facing + PI * 0.75 + k * 1.3
		var want := tp.position + Vector3(-sin(a) * 0.75, 1.75 + sin(t * 2.2 + gid) * 0.12, -cos(a) * 0.75)
		n.position = n.position.lerp(want, 0.08)
		n.rotation.y = lerp_angle(n.rotation.y, tp.facing, 0.1)
		# never your own ghost, and never one sitting in front of your ghost camera
		var cam := get_viewport().get_camera_3d()
		n.visible = gid != me and not (cam == ghost_cam and cam.global_position.distance_to(n.global_position) < 1.8)
		Body.ghost_glow(n, 2.5 if cab.blackout > 0.0 else 0.6)


## Daycare: loot in the ball pit stays buried until you are right next to it.
func _draw_hidden_loot() -> void:
	var lp := local_player()
	var eye: Vector3 = lp.position if lp and lp.alive else (ghost_cam.global_position if ghost_cam.current else Vector3.INF)
	for lid in _loot_nodes:
		var n: Node3D = _loot_nodes[lid]
		if not n.has_meta("buried"):
			continue
		var near := eye != Vector3.INF and Vector2(eye.x - n.position.x, eye.z - n.position.z).length() < 2.6
		n.get_child(0).position.y = n.get_meta("y") if near else -0.2
		(n.get_child(1) as Label3D).visible = near


# --- actions: what a player can do -------------------------------------------------------

func act_pickup(p: Player, lid: int) -> void:
	if multiplayer.is_server():
		_srv_pickup(p.pid, lid)
	elif p.pid == me:
		s_pickup.rpc_id(1, lid)


func act_drop(p: Player) -> void:
	if multiplayer.is_server():
		_srv_drop(p.pid)
	elif p.pid == me:
		s_drop.rpc_id(1, p.position, p.facing)


func act_shove(p: Player, target: int) -> void:
	p.shove_cool = Rules.SHOVE_COOLDOWN
	if multiplayer.is_server():
		_srv_shove(p.pid, target)
	elif p.pid == me:
		s_shove.rpc_id(1, target)


func act_hold(p: Player) -> void:
	if multiplayer.is_server():
		_srv_hold(p.pid)
	elif p.pid == me:
		s_hold.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func s_pickup(lid: int) -> void:
	_srv_pickup(multiplayer.get_remote_sender_id(), lid)


@rpc("any_peer", "call_remote", "reliable")
func s_drop(pos: Vector3, yaw: float) -> void:
	var id := multiplayer.get_remote_sender_id()
	if players.has(id):
		players[id].set_remote_state(pos, yaw)
		players[id].facing = yaw
	_srv_drop(id)


@rpc("any_peer", "call_remote", "reliable")
func s_shove(target: int) -> void:
	_srv_shove(multiplayer.get_remote_sender_id(), target)


@rpc("any_peer", "call_remote", "reliable")
func s_hold() -> void:
	_srv_hold(multiplayer.get_remote_sender_id())


func _srv_pickup(pid: int, lid: int) -> void:
	var p: Player = players.get(pid)
	if p == null or not p.alive or not loot.has(lid) or loot[lid].owner != 0:
		return
	if carried[pid].size() >= Rules.SLOTS or phase == "results" or phase == "crash":
		return
	var lp: Vector3 = loot[lid].pos
	var pp := p.true_pos()
	if Vector2(pp.x - lp.x, pp.z - lp.z).length() > Rules.PICKUP_RANGE + 0.6 or absf(pp.y - lp.y) > 1.8:
		return
	_set_owner(lid, pid)
	for peer in _ready_peers:
		c_loot_owner.rpc_id(peer, lid, pid)
	_fx_all("pickup", lp)
	_log("PICKUP %s took %s" % [info[pid].name, loot[lid].kind])


func _srv_drop(pid: int) -> void:
	var p: Player = players.get(pid)
	if p == null or not p.alive or carried[pid].is_empty():
		return
	var lid: int = carried[pid].back()
	_srv_place(lid, _ground(p.true_pos() + p.forward() * 0.75))
	_fx_all("drop", p.position)


func _srv_shove(pid: int, target: int) -> void:
	var a: Player = players.get(pid)
	var t: Player = players.get(target)
	if a == null or t == null or not a.alive or not t.alive or pid == target:
		return
	if a.true_pos().distance_to(t.true_pos()) > Rules.SHOVE_RANGE + 0.7 or phase == "results":
		return
	var dir := t.true_pos() - a.true_pos()
	dir.y = 0
	dir = dir.normalized() if dir.length() > 0.01 else a.forward()
	_knock(target, dir * Rules.SHOVE_FORCE + Vector3.UP * 2.5, 0.6)
	if not carried[target].is_empty():
		var lid: int = carried[target].back()
		_srv_place(lid, _ground(t.true_pos() + dir * 0.6))
	_fx_all("shove", t.true_pos())
	_log("SHOVE %s shoved %s" % [info[pid].name, info[target].name])


func _srv_hold(pid: int) -> void:
	var p: Player = players.get(pid)
	if p == null or not p.alive or phase != "open" or hold_used or time_left <= 0.0:
		return
	if p.true_pos().distance_to(Vector3(cab.hold_pos.x, 0, cab.hold_pos.z)) > 1.8:
		return
	time_left += Rules.HOLD_EXTRA
	_hold(time_left, info[pid].name)
	for peer in _ready_peers:
		c_hold.rpc_id(peer, time_left, info[pid].name)


@rpc("authority", "call_remote", "reliable")
func c_hold(t: float, who: String) -> void:
	_hold(t, who)


func _hold(t: float, who: String) -> void:
	hold_used = true
	time_left = t
	cab.set_hold_used(true)
	Sound.play("button")
	hud.feed("%s is holding the doors (+%d s)" % [who, int(Rules.HOLD_EXTRA)])


func _knock(id: int, impulse: Vector3, stun: float) -> void:
	var p: Player = players.get(id)
	if p == null:
		return
	if p.is_controlled_here():
		p.knock(impulse, stun)
	else:
		c_knock.rpc_id(id, impulse, stun)


@rpc("authority", "call_remote", "reliable")
func c_knock(impulse: Vector3, stun: float) -> void:
	var lp := local_player()
	if lp:
		lp.knock(impulse, stun)


func _ground(pos: Vector3) -> Vector3:
	return Vector3(clampf(pos.x, -8.6, 8.6), 0.0, clampf(pos.z, -15.6, Rules.CAB_DEPTH - 0.3))


func _fx_all(what: String, pos: Vector3) -> void:
	_fx(what, pos)
	for peer in _ready_peers:
		c_fx.rpc_id(peer, what, pos)


@rpc("authority", "call_remote", "reliable")
func c_fx(what: String, pos: Vector3) -> void:
	_fx(what, pos)


func _fx(what: String, pos: Vector3) -> void:
	if what.begins_with("feed:"):
		hud.feed(what.substr(5))
	elif what == "buzzer":
		Sound.play("buzzer", -4.0)
	else:
		Sound.play_at(what, pos)


# --- loot --------------------------------------------------------------------------------

func loot_info(lid: int) -> Dictionary:
	return loot.get(lid, {})


func loot_burning(pos: Vector3) -> bool:
	return room != null and room.burning(pos)


## A piece of loot's weight right now: spa loot soaked in the flood is heavier.
func loot_kg(lid: int) -> float:
	var l: Dictionary = loot[lid]
	return Rules.loot_kg(l.kind) * (Rules.WET_KG if l.wet else 1.0)


func kg_text(lid: int) -> String:
	var kg := loot_kg(lid)
	var t := str(int(kg)) if is_equal_approx(kg, roundf(kg)) else "%.1f" % kg
	return t + (" kg, wet" if loot[lid].wet else " kg")


func _loot_add(lid: int, kind: String, pos: Vector3, owner: int, wet := false) -> void:
	loot[lid] = {"kind": kind, "pos": pos, "owner": 0, "wet": wet}
	if owner == 0:
		_show_ground(lid)
	else:
		_set_owner(lid, owner)


@rpc("authority", "call_remote", "reliable")
func c_loot_spawn(list: Array) -> void:
	for l in list:
		_loot_add(l[0], l[1], l[2], l[3], l[4])


@rpc("authority", "call_remote", "reliable")
func c_loot_owner(lid: int, owner: int) -> void:
	_set_owner(lid, owner)


@rpc("authority", "call_remote", "reliable")
func c_loot_place(lid: int, pos: Vector3) -> void:
	_place(lid, pos)


@rpc("authority", "call_remote", "reliable")
func c_loot_remove(lid: int) -> void:
	_remove(lid)


@rpc("authority", "call_remote", "reliable")
func c_loot_wet(lid: int) -> void:
	_set_wet(lid)


func _set_wet(lid: int) -> void:
	if not loot.has(lid):
		return
	loot[lid].wet = true
	if loot[lid].owner == 0:
		_show_ground(lid)
	else:
		_refresh_carry(loot[lid].owner)


func _srv_place(lid: int, pos: Vector3) -> void:
	_place(lid, pos)
	for peer in _ready_peers:
		c_loot_place.rpc_id(peer, lid, pos)


func _srv_remove(lid: int) -> void:
	_remove(lid)
	for peer in _ready_peers:
		c_loot_remove.rpc_id(peer, lid)


func _set_owner(lid: int, owner: int) -> void:
	if not loot.has(lid):
		return
	_release(lid)
	loot[lid].owner = owner
	if _loot_nodes.has(lid):
		_loot_nodes[lid].queue_free()
		_loot_nodes.erase(lid)
	if carried.has(owner):
		carried[owner].append(lid)
		_refresh_carry(owner)


func _place(lid: int, pos: Vector3) -> void:
	if not loot.has(lid):
		return
	_release(lid)
	loot[lid].owner = 0
	loot[lid].pos = pos
	_show_ground(lid)


func _remove(lid: int) -> void:
	if not loot.has(lid):
		return
	_release(lid)
	if _loot_nodes.has(lid):
		_loot_nodes[lid].queue_free()
		_loot_nodes.erase(lid)
	loot.erase(lid)


func _release(lid: int) -> void:
	var owner: int = loot[lid].owner
	if owner != 0 and carried.has(owner):
		carried[owner].erase(lid)
		_refresh_carry(owner)


func _refresh_carry(pid: int) -> void:
	var p: Player = players.get(pid)
	if p == null:
		return
	var kinds: Array[String] = []
	var kg := 0.0
	for lid in carried[pid]:
		kinds.append(loot[lid].kind)
		kg += loot_kg(lid)
	var ids: Array[int] = []
	ids.assign(carried[pid])
	p.set_carried(ids, kinds, kg)


func _show_ground(lid: int) -> void:
	if _loot_nodes.has(lid):
		_loot_nodes[lid].queue_free()
	var l: Dictionary = loot[lid]
	var size: Vector3 = Rules.LOOT[l.kind][5]
	var n := Node3D.new()
	n.position = l.pos
	loot_root.add_child(n)
	var col: Color = Rules.LOOT[l.kind][4]
	if l.wet:
		col = col.darkened(0.25)
	Build.mesh(n, Build.loot_mesh(l.kind), Vector3(0, size.y / 2.0 + 0.02, 0), Build.mat(col, 0.1 if l.wet else 0.4, 0.2, 0.15))
	var tag := Build.label(n, str(Rules.loot_value(l.kind)) + ("  wet" if l.wet else ""), Vector3(0, size.y + 0.28, 0), 30,
		Color("8fd3ff") if l.wet else Color("ffd36b"), load("res://assets/fonts/ChakraPetch-Bold.ttf"))
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.outline_size = 8
	tag.outline_modulate = Color(0, 0, 0, 0.8)
	if room and room.in_pit(l.pos):
		n.set_meta("buried", true)
		n.set_meta("y", size.y / 2.0 + 0.02)
	_loot_nodes[lid] = n


# --- networking of movement --------------------------------------------------------------

func _send_states() -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return
	if multiplayer.is_server():
		if _ready_peers.is_empty():
			return
		var arr := []
		for id in players:
			var p: Player = players[id]
			arr.append([id, p.true_pos(), p.facing, p.gripping])
		for peer in _ready_peers:
			c_states.rpc_id(peer, arr)
	else:
		var lp := local_player()
		if lp and lp.alive:
			s_state.rpc_id(1, lp.position, lp.facing, lp.gripping)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func s_state(pos: Vector3, yaw: float, grip: bool) -> void:
	var id := multiplayer.get_remote_sender_id()
	var p: Player = players.get(id)
	if p and p.mode == Player.Mode.PUPPET:
		p.set_remote_state(pos, yaw)
		p.gripping = grip and snap_active()


@rpc("authority", "call_remote", "unreliable_ordered")
func c_states(arr: Array) -> void:
	for s in arr:
		if s[0] == me:
			continue
		var p: Player = players.get(s[0])
		if p:
			p.set_remote_state(s[1], s[2])
			if p.mode == Player.Mode.PUPPET:
				p.gripping = s[3]


# --- local input -------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		hud.toggle_pause()
		return
	if event.is_action_pressed("start"):
		_on_start()
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not hud.paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return
	var lp := local_player()
	if lp and not lp.alive and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_ghost_input(event, lp)
		return
	if lp == null or not lp.alive or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event.is_action_pressed("interact") and snap_active():
		return  # E is for the rail right now (read every frame in _physics_process)
	if event.is_action_pressed("interact"):
		var target := interact_target()
		if target.type == "hold":
			act_hold(lp)
		elif target.type == "loot":
			act_pickup(lp, target.id)
	elif event.is_action_pressed("drop"):
		act_drop(lp)
	elif event.is_action_pressed("shove") and lp.shove_cool <= 0.0:
		var t := shove_target(lp)
		if t != 0:
			act_shove(lp, t)


func _ghost_input(event: InputEvent, lp: Player) -> void:
	if event is InputEventMouseMotion:
		ghost_yaw -= event.relative.x * lp.sensitivity
		ghost_pitch = clampf(ghost_pitch - event.relative.y * lp.sensitivity, -1.2, 0.4)
	elif event.is_action_pressed("shove") or event.is_action_pressed("haunt_next"):
		_cycle_haunt(1)
	elif event.is_action_pressed("haunt_prev"):
		_cycle_haunt(-1)
	elif event.is_action_pressed("ghost_lights"):
		act_ghost(lp, "lights")
	elif event.is_action_pressed("ghost_button"):
		act_ghost(lp, "button")
	elif event.is_action_pressed("ghost_spook"):
		act_ghost(lp, "spook")


## What E would do right now: {type: "hold" | "loot" | "full" | "rail" | "", id, text}.
func interact_target() -> Dictionary:
	var lp := local_player()
	if lp == null or not lp.alive:
		return {"type": ""}
	if snap_active():
		if lp.gripping:
			return {"type": "rail", "text": "Holding on!  Keep E down"}
		if Rules.can_hold_rail(lp.position):
			return {"type": "rail", "text": "[Hold E]  Grab the rail"}
		return {"type": "rail", "text": "Get to a wall rail!"}
	if phase == "open" and not hold_used and time_left > 0.0 \
			and lp.position.distance_to(Vector3(cab.hold_pos.x, 0, cab.hold_pos.z)) < 1.5:
		return {"type": "hold", "text": "Hold the doors  +%d s" % int(Rules.HOLD_EXTRA)}
	var best := -1
	var best_d := Rules.PICKUP_RANGE
	var cam_fwd := Vector3(-sin(lp.cam_yaw), 0, -cos(lp.cam_yaw))
	for lid in loot:
		if loot[lid].owner != 0:
			continue
		var to: Vector3 = loot[lid].pos - lp.position
		to.y = 0
		var d := to.length()
		if d < best_d and (d < 0.9 or to.normalized().dot(cam_fwd) > 0.2):
			best_d = d
			best = lid
	if best < 0:
		return {"type": ""}
	var k: String = loot[best].kind
	if lp.carried.size() >= Rules.SLOTS:
		return {"type": "full", "text": "Hands full. Q drops your top item."}
	return {"type": "loot", "id": best,
		"text": "Pick up %s   %d pts  ·  %s" % [Rules.loot_name(k), Rules.loot_value(k), kg_text(best)]}


func shove_target(lp: Player) -> int:
	var cam_fwd := Vector3(-sin(lp.cam_yaw), 0, -cos(lp.cam_yaw))
	var best := 0
	var best_d := Rules.SHOVE_RANGE
	for id in players:
		var o: Player = players[id]
		if o == lp or not o.alive:
			continue
		var to := o.position - lp.position
		to.y = 0
		var d := to.length()
		if d < best_d and to.normalized().dot(cam_fwd) > 0.35:
			best_d = d
			best = id
	return best


func my_haul() -> int:
	return carried_value(me)


func _leave(reason: String) -> void:
	Sound.stop_loops()
	Net.leave()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	left_game.emit(reason)
