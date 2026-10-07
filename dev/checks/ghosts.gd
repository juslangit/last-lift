extends Node

## Drives a real hosted game through the new drama and checks what happens.
##   Godot --headless --path . -- --host --nosteam --bots=7 --autostart --rooms=spa,daycare,vault \
##         --snap=never --probe=ghosts --log
## Floor 1 (spa): a forced left-behind becomes a ghost and uses every power; loot gets wet.
## Floor 2 (daycare): loot in the ball pit is buried. Floor 3 (vault): the laser sweep moves.

var passes := 0
var failures := 0
var _floor := 0
var _phase := ""
var _t := 0.0
var _done := {}
var _ghost := 0
var _fence_z := 0.0


func check(label: String, ok: bool) -> void:
	if ok:
		passes += 1
		print("  ok    " + label)
	else:
		failures += 1
		print("  FAIL  " + label)


func _process(dt: float) -> void:
	var g: Game = get_parent().game
	if g == null:
		return
	if g.phase != _phase:
		_phase = g.phase
		_t = 0.0
		if _phase == "open":
			_floor += 1
	_t += dt
	if _phase != "open":
		if _phase == "results" or _phase == "crash":
			_finish()
		return
	match _floor:
		1:
			_spa_floor(g)
		2:
			_once("daycare", _t > 1.0, func(): _daycare(g))
		3:
			_once("vault a", _t > 3.0, func(): _fence_z = g.room._fence.position.z)
			_once("vault b", _t > 5.0, func():
				check("the laser sweep moves", absf(g.room._fence.position.z - _fence_z) > 1.0)
				check("standing in the beams is a hit, the gap is not", _laser(g))
				_finish())


func _spa_floor(g: Game) -> void:
	_once("ghost", _t > 1.0, func():
		_ghost = _bot(g, 0)
		g._srv_eliminate(_ghost, "left behind (probe)")
		check("a left-behind player becomes a ghost", g.haunts.has(_ghost))
		var t: int = g.haunts.get(_ghost, 0)
		check("the ghost haunts someone alive", t != 0 and g.players[t].alive))
	_once("button", _t > 1.5, func():
		var before := g.time_left
		g._srv_ghost(_ghost, "button")
		check("a floor button takes %d s off the doors" % int(Rules.BUTTON_CUT), absf(before - g.time_left - Rules.BUTTON_CUT) < 0.1)
		var after := g.time_left
		g._srv_ghost(_ghost, "button")
		check("the same ghost can't press twice on one floor", absf(g.time_left - after) < 0.05)
		g._srv_ghost(_ghost, "lights")
		check("lights out darkens the cab", g.cab.blackout > 0.0)
		var target: Player = g.players[g.haunts[_ghost]]
		g.brains.erase(target.pid)  # keep them still while we check the spook
		target.teleport(Vector3(0, 0, -6))
		g._srv_ghost(_ghost, "spook")
		check("spooking sets the hazard on them (cooldown started)", g._ghost_cool[_ghost].spook > 0.0)
		check("the room knows who is spooked", g.room._spook_id == target.pid and g.room._spook_t > 0.0))
	_once("haunt", _t > 2.5, func():
		var target: int = g.haunts[_ghost]
		g._srv_eliminate(target, "left behind (probe)")
		check("the ghost scores when its person is left behind", g.ghost_pts.get(_ghost, 0) == Rules.HAUNT_POINTS)
		var next: int = g.haunts.get(_ghost, 0)
		check("the ghost moves on to someone still alive", next != 0 and next != target and g.players[next].alive)
		check("the new ghost haunts someone too", g.haunts.has(target)))
	_once("wet", _t > 10.0, func():
		var wet := 0
		var heavier := true
		for lid in g.loot:
			if g.loot[lid].wet:
				wet += 1
				heavier = heavier and g.loot_kg(lid) > Rules.loot_kg(g.loot[lid].kind)
		check("the flood has soaked some loot (%d pieces)" % wet, wet > 0)
		check("wet loot weighs more", heavier)
		check("wading in the spa slows you", g.room.wade(Vector3(0, 0, -8)) < 0.8)
		check("the cab stays dry", g.room.wade(Vector3(0, 0, 2)) == 1.0))


func _daycare(g: Game) -> void:
	var buried := 0
	var in_pit := 0
	for lid in g.loot:
		if g.loot[lid].owner == 0 and g.room.in_pit(g.loot[lid].pos):
			in_pit += 1
			if g._loot_nodes.has(lid) and g._loot_nodes[lid].has_meta("buried"):
				buried += 1

	check("loot landed in the ball pit (%d)" % in_pit, in_pit > 0)
	check("every pit item is buried", buried == in_pit)
	check("the ball pit slows you", g.room.wade(Vector3(0, 0, -9)) < 1.0)


func _laser(g: Game) -> bool:
	var f: Node3D = g.room._fence
	var in_beam := Vector3(f.position.x + 4.0, 0, f.position.z)
	var in_gap := Vector3(f.position.x, 0, f.position.z)
	return g.room.laser_hits(in_beam) and not g.room.laser_hits(in_gap)


func _bot(g: Game, n: int) -> int:
	var ids := []
	for id in g.info:
		if g.info[id].bot and g.players[id].alive:
			ids.append(id)
	ids.sort()
	return ids[n]


func _once(key: String, cond: bool, f: Callable) -> void:
	if cond and not _done.has(key):
		_done[key] = true
		f.call()


func _finish() -> void:
	if _done.has("finished"):
		return
	_done["finished"] = true
	if not _done.has("vault b"):
		print("  note  the round ended on floor %d (everyone left behind); the later floors' checks did not run" % _floor)
	print("%d passed, %d failed" % [passes, failures])
	get_tree().quit(1 if failures > 0 else 0)
