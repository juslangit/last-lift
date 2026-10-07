class_name Cab
extends Node3D

## The elevator itself. It never moves: the falling is faked with shake, flicker and the
## floor display, and each floor is built in front of the doors while they are shut.

const STEEL := Color("a3a9ae")
const BRASS := Color("c9a24a")
const LED := Color("ff7a3d")

var door_l: AnimatableBody3D
var door_r: AnimatableBody3D
var led_in: Label3D
var led_out: Label3D
var lamp: OmniLight3D
var lamp_strip: MeshInstance3D
var hold_lamp: MeshInstance3D
var hold_pos := Vector3(1.62, 1.25, 0.2)
var open_amount := 0.0           # 0 shut, 1 fully open
var flicker := 0.0               # set by the game during descent
var blackout := 0.0              # a ghost killed the lights: seconds left
var _tween: Tween
var _font: Font


func _ready() -> void:
	_font = load("res://assets/fonts/ChakraPetch-Bold.ttf")
	var steel := Build.mat(STEEL, 0.32, 0.75)
	var dark_steel := Build.mat(Color("6b7177"), 0.4, 0.7)
	var brass := Build.mat(BRASS, 0.3, 0.9)
	var wood := Build.mat(Color("7a4a2a"), 0.6)
	var floor_m := Build.mat(Color("2f2b27"), 0.9)
	var w := Rules.CAB_HALF_W
	var d := Rules.CAB_DEPTH
	var h := Rules.CAB_HEIGHT
	var t := 0.12
	# floor and ceiling
	Build.box(self, Vector3(w * 2 + t * 2, 0.2, d + t), Vector3(0, -0.1, d / 2.0), floor_m)
	for i in 4:  # brass floor inlays
		Build.box(self, Vector3(w * 2 - 0.3, 0.012, 0.05), Vector3(0, 0.006, 0.6 + i * 0.95), brass, false)
	Build.box(self, Vector3(w * 2 + t * 2, 0.15, d + t), Vector3(0, h + 0.075, d / 2.0), dark_steel)
	# side and back walls
	Build.box(self, Vector3(t, h, d), Vector3(-w - t / 2.0, h / 2.0, d / 2.0), steel)
	Build.box(self, Vector3(t, h, d), Vector3(w + t / 2.0, h / 2.0, d / 2.0), steel)
	Build.box(self, Vector3(w * 2, h, t), Vector3(0, h / 2.0, d + t / 2.0), steel)
	# panel seams on the walls, so the steel reads as panels
	for i in 3:
		var z := 1.0 + i * 1.0
		Build.box(self, Vector3(0.01, h, 0.02), Vector3(-w + 0.006, h / 2.0, z), dark_steel, false)
		Build.box(self, Vector3(0.01, h, 0.02), Vector3(w - 0.006, h / 2.0, z), dark_steel, false)
	# front wall with the doorway
	Build.wall_with_hole(self, -w - t, w + t, 0.0, h, Rules.DOOR_HALF_W, 2.4, t, steel)
	Build.box(self, Vector3(Rules.DOOR_HALF_W * 2 + 0.1, 0.08, 0.16), Vector3(0, 2.42, 0.0), brass, false)
	# wooden hand rail on three walls
	Build.box(self, Vector3(0.05, 0.06, d - 0.4), Vector3(-w + 0.08, 1.0, d / 2.0 + 0.1), wood, false)
	Build.box(self, Vector3(0.05, 0.06, d - 0.4), Vector3(w - 0.08, 1.0, d / 2.0 + 0.1), wood, false)
	Build.box(self, Vector3(w * 2 - 0.4, 0.06, 0.05), Vector3(0, 1.0, d - 0.08), wood, false)
	# ceiling light
	lamp_strip = Build.mesh(self, Build.box_mesh(Vector3(2.4, 0.03, 0.5)), Vector3(0, h - 0.02, d / 2.0),
		Build.mat(Color("ffe2b0"), 0.5, 0.0, 2.0).duplicate())
	lamp = Build.light(self, Vector3(0, h - 0.3, d / 2.0), Color("ffd9a0"), 2.2, 7.0, true)
	# the doors
	door_l = _door(-Rules.DOOR_HALF_W / 2.0)
	door_r = _door(Rules.DOOR_HALF_W / 2.0)
	# the control panel with the Door-Hold button
	Build.box(self, Vector3(0.34, 0.9, 0.04), Vector3(hold_pos.x, 1.3, 0.08), brass, false)
	for i in 6:
		Build.mesh(self, Build.cyl_mesh(0.035, 0.02), Vector3(hold_pos.x - 0.07 + (i % 2) * 0.14, 1.62 - (i / 2) * 0.1, 0.11),
			Build.mat(Color("f0e6cc"), 0.4, 0.0, 0.6), Vector3(PI / 2, 0, 0))
	hold_lamp = Build.mesh(self, Build.cyl_mesh(0.07, 0.04), Vector3(hold_pos.x, 1.12, 0.11),
		Build.mat(Color("ff3b2f"), 0.4, 0.0, 2.5).duplicate(), Vector3(PI / 2, 0, 0))
	var hl := Build.label(self, "HOLD", Vector3(hold_pos.x, 1.0, 0.105), 28, Color("1f1d1a"), _font)
	hl.pixel_size = 0.003
	# floor displays, inside over the doors and outside for whoever is on the landing
	Build.box(self, Vector3(0.7, 0.28, 0.04), Vector3(0, 2.72, 0.08), Build.mat(Color("140d08")), false)
	led_in = Build.label(self, "40", Vector3(0, 2.72, 0.105), 72, LED, _font)
	Build.box(self, Vector3(0.7, 0.28, 0.04), Vector3(0, 2.72, -0.08), Build.mat(Color("140d08")), false)
	led_out = Build.label(self, "40", Vector3(0, 2.72, -0.105), 72, LED, _font)
	led_out.rotation.y = PI
	for l in [led_in, led_out]:
		l.modulate = LED
		(l as Label3D).shaded = false


func _door(x: float) -> AnimatableBody3D:
	var b := AnimatableBody3D.new()
	b.sync_to_physics = false
	b.collision_layer = Build.DOORS
	b.collision_mask = 0
	var size := Vector3(Rules.DOOR_HALF_W, 2.4, 0.06)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	b.add_child(shape)
	Build.mesh(b, Build.box_mesh(size), Vector3.ZERO, Build.mat(Color("b8bec4"), 0.22, 0.85))
	Build.mesh(b, Build.box_mesh(Vector3(0.02, 2.3, 0.07)), Vector3(-x / absf(x) * size.x / 2.0, 0, 0), Build.mat(BRASS, 0.3, 0.9))
	b.position = Vector3(x, 1.2, 0.12)
	add_child(b)
	return b


func set_doors(open: bool, instant := false) -> void:
	if _tween:
		_tween.kill()
	var target := 1.0 if open else 0.0
	if instant:
		_apply(target)
		return
	_tween = create_tween()
	_tween.tween_method(_apply, open_amount, target, Rules.DOOR_ANIM).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


func _apply(v: float) -> void:
	open_amount = v
	var slide := Rules.DOOR_HALF_W * 0.92 * v
	door_l.position.x = -Rules.DOOR_HALF_W / 2.0 - slide
	door_r.position.x = Rules.DOOR_HALF_W / 2.0 + slide


func set_floor_text(text: String) -> void:
	led_in.text = text
	led_out.text = text


func set_hold_used(used: bool) -> void:
	(hold_lamp.material_override as StandardMaterial3D).emission_energy_multiplier = 0.2 if used else 2.5


func _process(dt: float) -> void:
	var base := 2.2
	var strip := 2.0
	blackout = maxf(blackout - dt, 0.0)
	if flicker > 0.0 and randf() < flicker * 0.25:
		base *= randf_range(0.05, 0.6)
		strip *= 0.2
	if blackout > 0.0:
		base = 0.0 if randf() > 0.04 else 0.8
		strip = 0.0
	lamp.light_energy = lerpf(lamp.light_energy, base, 0.5)
	for l in [led_in, led_out]:
		(l as Label3D).visible = blackout <= 0.0
	(lamp_strip.material_override as StandardMaterial3D).emission_energy_multiplier = strip
