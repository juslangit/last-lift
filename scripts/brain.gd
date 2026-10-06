class_name Brain
extends RefCounted

## A bot's mind. Each floor it rolls how greedy it feels and how badly it will misjudge the
## clock, so some bots come back early with one item and some get left behind holding three.
## The same brain drives your own player under --autopilot, through the same actions you have.

var rng := RandomNumberGenerator.new()
var greed := 0.5
var carry_goal := 2
var misjudge := 0.0
var home := Vector3(0, 0, 2.5)
var target_loot := -1
var careful := false          # never misjudges the clock (used for screenshots)
var _path := PackedVector3Array()
var _path_target := Vector3.INF
var _repath := 0.0
var _stuck := 0.0
var _unstick := 0.0
var _unstick_dir := Vector3.ZERO
var _last := Vector3.ZERO
var _floor_seen := -1
var _drop_wait := 0.0


func _init(seed_value: int) -> void:
	rng.seed = seed_value


func new_floor() -> void:
	greed = rng.randf_range(0.2, 0.95)
	carry_goal = rng.randi_range(1, 3)
	misjudge = rng.randf_range(-2.6, 1.2)   # negative: thinks it has more time than it does
	if careful:
		misjudge = 2.0
		greed = 0.9
	home = Vector3(rng.randf_range(-1.4, 1.4), 0, rng.randf_range(1.6, 3.4))
	target_loot = -1


func tick(dt: float, p: Player, g: Game) -> void:
	p.want_run = false
	p.move_dir = Vector3.ZERO
	if not p.alive:
		return
	if g.floor_now != _floor_seen and g.phase == "open":
		_floor_seen = g.floor_now
		new_floor()
	var inside := Rules.inside_cab(p.position)
	if g.phase != "open":
		if inside:
			_walk(p, home, dt, g, false, 0.5)
		else:
			_walk(p, home, dt, g, true, 0.3)  # doors are closing: dive for it
		return
	_drop_wait = maxf(_drop_wait - dt, 0.0)
	# too heavy to leave: carry something to the door and throw it out
	if g.overweight and inside and p.carried.size() > 0:
		var door := Vector3(0, 0, 0.75)
		if Vector2(p.position.x - door.x, p.position.z - door.z).length() > 0.35:
			_walk(p, door, dt, g, true, 0.2)
		else:
			p.facing = 0.0  # face out of the cab, toward -z
			if _drop_wait <= 0.0:
				_drop_wait = 0.6
				g.act_drop(p)
		return
	var speed := Rules.RUN_SPEED * Rules.speed_factor(p.carried_kg)
	var dist_home := Vector2(p.position.x - home.x, p.position.z - home.z).length() * 1.25
	var need := dist_home / speed + 1.2 + (1.0 - greed) * 3.0 + misjudge
	var going_home := g.time_left < need or p.carried.size() >= carry_goal
	if not going_home:
		var loot := g.loot_info(target_loot)
		if loot.is_empty() or loot.owner != 0 or Rules.inside_cab(loot.pos):
			target_loot = _choose(p, g)
			loot = g.loot_info(target_loot)
		if loot.is_empty():
			going_home = true
		else:
			var lp: Vector3 = loot.pos
			if Vector2(p.position.x - lp.x, p.position.z - lp.z).length() < Rules.PICKUP_RANGE - 0.6:
				g.act_pickup(p, target_loot)
				target_loot = -1
			else:
				_walk(p, Vector3(lp.x, 0, lp.z), dt, g, true, 0.0)
	if going_home:
		_walk(p, home, dt, g, true, 0.4)
	# greedy bots shove whoever is carrying the most nearby
	if greed > 0.75 and p.shove_cool <= 0.0 and rng.randf() < dt * 0.6:
		for other in g.players.values():
			var o := other as Player
			if o == p or not o.alive or o.carried.is_empty():
				continue
			if o.position.distance_to(p.position) < Rules.SHOVE_RANGE - 0.3:
				g.act_shove(p, o.pid)
				break


func _choose(p: Player, g: Game) -> int:
	var best := -1
	var best_score := -INF
	for id in g.loot:
		var l: Dictionary = g.loot[id]
		if l.owner != 0 or Rules.inside_cab(l.pos) or g.loot_burning(l.pos):
			continue
		var d: float = p.position.distance_to(l.pos)
		var kg := Rules.loot_kg(l.kind)
		var score: float = Rules.loot_value(l.kind) * (0.4 + greed) / (d + 4.0) - kg * (1.0 - greed) * 0.4 + rng.randf() * 6.0
		if score > best_score:
			best_score = score
			best = id
	return best


func _walk(p: Player, target: Vector3, dt: float, g: Game, run: bool, arrive: float) -> void:
	var flat := Vector2(target.x - p.position.x, target.z - p.position.z)
	if flat.length() < arrive:
		return
	_repath -= dt
	if _repath <= 0.0 or target.distance_to(_path_target) > 0.5:
		_repath = 0.5
		_path_target = target
		_path = PackedVector3Array()
		if g.nav_map.is_valid():
			_path = NavigationServer3D.map_get_path(g.nav_map, p.position, target, true)
	while _path.size() > 1 and Vector2(_path[0].x - p.position.x, _path[0].z - p.position.z).length() < 0.35:
		_path.remove_at(0)
	var step := target
	if _path.size() > 0:
		step = _path[0]
	var dir := Vector3(step.x - p.position.x, 0, step.z - p.position.z)
	if dir.length() < 0.05:
		dir = Vector3(flat.x, 0, flat.y)
	# unstick: if it has not moved for a second, sidestep at random
	var moved := Vector2(p.position.x - _last.x, p.position.z - _last.z).length()
	_last = p.position
	_stuck = _stuck + dt if moved < 0.4 * dt else 0.0
	if _stuck > 0.8:
		_stuck = 0.0
		_unstick = 0.5
		_unstick_dir = Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
		_repath = 0.0
	if _unstick > 0.0:
		_unstick -= dt
		dir = _unstick_dir
		if rng.randf() < 0.05:
			p.want_jump = true
	p.move_dir = dir.normalized()
	p.want_run = run
