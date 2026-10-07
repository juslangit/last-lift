extends Node

## Screenshots for the project record and for checking the look by eye.
##   Godot --path . --resolution 1920x1080 -- --shots=dev/shots --host --bots=7 --autostart \
##         --autopilot --rooms=office,fire,zoo,office,fire --rounds=1 --quit
##   Godot --path . --resolution 1920x1080 -- --shots=dev/shots --menu     (the title screen)
## One picture per moment: the lobby, each floor a few seconds after the doors open and again
## near the end, the fall, the crash, and the results.

var dir := ""
var _t := 0.0
var _phase := ""
var _phase_t := 0.0
var _taken := {}
var _floors := 0
var _ghost_t := 0.0


func _ready() -> void:
	dir = str(Net.opts["shots"])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + dir))


func _process(dt: float) -> void:
	_t += dt
	var main := get_parent()
	if Net.flag("menu"):
		if _t > 2.0 and not _taken.has("01_menu"):
			_shot("01_menu")
			get_tree().create_timer(0.5).timeout.connect(get_tree().quit)
		return
	var g: Game = main.game
	if g == null:
		return
	if g.phase != _phase:
		_phase = g.phase
		_phase_t = 0.0
		if _phase == "open":
			_floors += 1
	_phase_t += dt
	match _phase:
		"lobby":
			_once("02_lobby", _phase_t > 1.2)
		"descent":
			_once("03_falling", _phase_t > 2.0 and _floors == 0 and not g.snap_active())
			_once("20_cable_snap", g.snap_active() and g.snap_t < 1.2)
			_once("21_snap_jolt", _taken.has("20_cable_snap") and not g.snap_active() and _phase_t > 3.5)
		"open":
			_once("1%d_%s_doors_open" % [_floors, g.room_kind], _phase_t > 2.2)
			_once("1%d_%s_looting" % [_floors, g.room_kind], _phase_t > 7.5)
			_once("1%d_%s_last_seconds" % [_floors, g.room_kind], g.time_left < 2.5 and g.time_left > 0.0)
		"crash":
			_once("40_crash", _phase_t > 2.5)
		"results":
			_once("41_results", _phase_t > 1.5)
	var lp := g.local_player()
	# --ghostshot: on the second floor, leave yourself behind to see the ghost's view
	if Net.flag("ghostshot") and _phase == "open" and _floors == 2 and _phase_t > 4.0 and lp and lp.alive:
		g._srv_eliminate(g.me, "left behind (screenshot)")
	if lp and not lp.alive:
		_once("30_left_behind", true)
		if _phase == "open" and _taken.has("30_left_behind") and not _taken.has("31_ghost_view") and g.my_haunt() != 0:
			_ghost_t += dt
			if _ghost_t > 1.5:
				_shot("31_ghost_view")
				g._srv_ghost(g.me, "lights")
		if _taken.has("31_ghost_view"):
			_once("32_ghost_lights_out", _phase == "open" and g.cab.blackout > 0.0 and g.cab.blackout < 2.0)


func _once(name: String, cond: bool) -> void:
	if cond and not _taken.has(name):
		_shot(name)


func _shot(name: String) -> void:
	_taken[name] = true
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://%s/%s.png" % [dir, name]))
	print("shot ", name)
