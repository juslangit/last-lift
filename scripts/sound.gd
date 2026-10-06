extends Node

## Every sound in the game is a Kenney CC0 sample in assets/sounds (see CREDITS.md).

const NAMES := ["ding", "door_open", "door_close", "rumble", "crash", "snap", "pickup", "drop",
	"shove", "slam", "buzzer", "left_behind", "fanfare", "click", "tick", "button", "fire"]

var _streams := {}
var _loops := {}
var volume := 0.8:
	set(v):
		volume = clampf(v, 0.0, 1.0)
		AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))


func _ready() -> void:
	for n in NAMES:
		var s := load("res://assets/sounds/%s.ogg" % n) as AudioStream
		if s:
			_streams[n] = s
	volume = volume


func play(sound: String, db := 0.0, pitch := 1.0) -> void:
	if not _streams.has(sound):
		return
	var p := AudioStreamPlayer.new()
	p.stream = _streams[sound]
	p.volume_db = db
	p.pitch_scale = pitch
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func play_at(sound: String, pos: Vector3, db := 0.0) -> void:
	if not _streams.has(sound):
		return
	var tree := get_tree()
	if tree == null or tree.root.get_viewport().get_camera_3d() == null:
		play(sound, db - 6.0)
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = _streams[sound]
	p.volume_db = db
	p.unit_size = 4.0
	p.max_distance = 40.0
	p.pitch_scale = randf_range(0.92, 1.08)
	add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)


func loop(sound: String, on: bool, db := -6.0) -> void:
	if on and not _loops.has(sound) and _streams.has(sound):
		var p := AudioStreamPlayer.new()
		var s: AudioStream = _streams[sound].duplicate()
		if s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true
		p.stream = s
		p.volume_db = db
		add_child(p)
		p.play()
		_loops[sound] = p
	elif not on and _loops.has(sound):
		_loops[sound].queue_free()
		_loops.erase(sound)


func stop_loops() -> void:
	for k in _loops.keys():
		loop(k, false)
