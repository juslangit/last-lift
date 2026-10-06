class_name Player
extends CharacterBody3D

## One person in the cab. Exactly one peer moves each player: you move yourself (LOCAL),
## the host moves the bots (BOT), and everyone else sees a smoothed copy (PUPPET).

enum Mode { LOCAL, BOT, PUPPET }

var pid := 0
var pname := ""
var color := Color.WHITE
var mode := Mode.PUPPET
var alive := true
var carried: Array[int] = []          # loot ids, newest last
var carried_kinds: Array[String] = []
var carried_kg := 0.0

# control: set by input (LOCAL) or the bot brain (BOT)
var move_dir := Vector3.ZERO          # world space, length <= 1
var want_run := false
var want_jump := false
var stun := 0.0
var shake := 0.0
var shove_cool := 0.0

# camera (LOCAL only)
var cam_yaw := PI                     # looking from the back of the cab toward the doors
var cam_pitch := -0.3
var sensitivity := 0.0025
var camera: Camera3D
var _pivot: Node3D
var _arm: SpringArm3D

var model: Node3D
var facing := PI                      # yaw of the model; forward is -Z rotated by this
var _stack: Node3D
var _label: Label3D
var _walk_phase := 0.0
var _target_pos := Vector3.ZERO
var _target_yaw := 0.0
var _last_pos := Vector3.ZERO
var _anim_speed := 0.0


func setup(id: int, display_name: String, c: Color, m: Mode, spawn: Vector3) -> void:
	pid = id
	pname = display_name
	color = c
	mode = m
	name = "P%d" % id
	position = spawn
	_target_pos = spawn
	_last_pos = spawn


func _ready() -> void:
	collision_layer = Build.PLAYERS
	collision_mask = Build.WORLD | Build.PLAYERS | Build.DOORS
	floor_snap_length = 0.3
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.34
	cap.height = 1.62
	shape.shape = cap
	shape.position.y = 0.81
	add_child(shape)
	var skin: Color = Body.SKINS[absi(pid) % Body.SKINS.size()]
	model = Body.person(color, skin)
	add_child(model)
	model.rotation.y = facing
	_stack = Node3D.new()
	_stack.position = Vector3(0, 1.62, 0)
	model.get_node("Bob").add_child(_stack)
	_label = Build.label(self, pname, Vector3(0, 2.15, 0), 28, Color.WHITE, load("res://assets/fonts/ChakraPetch-Bold.ttf"))
	_label.pixel_size = 0.004
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.outline_size = 10
	_label.outline_modulate = Color(0, 0, 0, 0.75)
	_label.no_depth_test = false
	_label.fixed_size = false
	if mode == Mode.LOCAL:
		_label.visible = false
		_pivot = Node3D.new()
		_pivot.position = Vector3(0, 1.85, 0)
		_stack.scale = Vector3.ONE * 0.6  # your own tower stays out of the camera's way
		add_child(_pivot)
		_arm = SpringArm3D.new()
		_arm.spring_length = 3.3
		_arm.collision_mask = Build.WORLD | Build.DOORS
		_arm.margin = 0.15
		var s := SphereShape3D.new()
		s.radius = 0.18
		_arm.shape = s
		_arm.position = Vector3(0.35, 0, 0)
		_pivot.add_child(_arm)
		camera = Camera3D.new()
		camera.fov = 70
		camera.near = 0.05
		_arm.add_child(camera)
		_arm.add_excluded_object(get_rid())
		camera.current = true


func is_controlled_here() -> bool:
	return mode != Mode.PUPPET


func forward() -> Vector3:
	return Vector3(-sin(facing), 0, -cos(facing))


func _unhandled_input(event: InputEvent) -> void:
	if mode != Mode.LOCAL or not alive:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		cam_yaw -= event.relative.x * sensitivity
		cam_pitch = clampf(cam_pitch - event.relative.y * sensitivity, -1.2, 0.6)


func _physics_process(dt: float) -> void:
	stun = maxf(stun - dt, 0.0)
	shove_cool = maxf(shove_cool - dt, 0.0)
	if mode == Mode.PUPPET:
		var k := 1.0 - exp(-14.0 * dt)
		position = position.lerp(_target_pos, k)
		facing = lerp_angle(facing, _target_yaw, k)
		model.rotation.y = facing
		_animate(dt)
		return
	if not alive:
		return
	if mode == Mode.LOCAL:
		_read_input()
	var speed := (Rules.RUN_SPEED if want_run else Rules.WALK_SPEED) * Rules.speed_factor(carried_kg)
	var target := move_dir.limit_length(1.0) * speed
	var flat := Vector3(velocity.x, 0, velocity.z)
	if stun > 0.0:
		flat = flat.lerp(Vector3.ZERO, 1.0 - exp(-2.0 * dt))
	else:
		flat = flat.lerp(target, 1.0 - exp(-(14.0 if is_on_floor() else 3.0) * dt))
	velocity.x = flat.x
	velocity.z = flat.z
	velocity.y -= Rules.GRAVITY * dt
	if want_jump and is_on_floor() and stun <= 0.0:
		velocity.y = Rules.JUMP_SPEED
	want_jump = false
	move_and_slide()
	if position.y < -20.0:  # fell out of the world somehow: back into the cab
		position = Rules.spawn_spot(absi(pid) % 8)
		velocity = Vector3.ZERO
	if move_dir.length() > 0.1 and stun <= 0.0:
		facing = lerp_angle(facing, atan2(-move_dir.x, -move_dir.z), 1.0 - exp(-12.0 * dt))
	model.rotation.y = facing
	_animate(dt)
	if _pivot:
		if Net.flag("autopilot"):  # let the camera follow where the brain walks
			cam_yaw = lerp_angle(cam_yaw, facing, 1.0 - exp(-2.5 * dt))
		_pivot.rotation = Vector3(cam_pitch, cam_yaw, 0)
		if shake > 0.0:
			camera.h_offset = randf_range(-1, 1) * shake * 0.08
			camera.v_offset = randf_range(-1, 1) * shake * 0.08
		else:
			camera.h_offset = 0.0
			camera.v_offset = 0.0


func _read_input() -> void:
	var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not Net.flag("autopilot"):
		v = Vector2.ZERO
	if Net.flag("autopilot"):
		return  # the bot brain is driving this player
	var basis_yaw := Basis(Vector3.UP, cam_yaw)
	move_dir = basis_yaw * Vector3(v.x, 0, v.y)
	want_run = Input.is_action_pressed("run")
	if Input.is_action_just_pressed("jump") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		want_jump = true


func _process(_dt: float) -> void:
	if _label and mode != Mode.LOCAL:
		var cam := get_viewport().get_camera_3d()
		_label.visible = cam != null and cam.global_position.distance_to(global_position) > 2.6


func _animate(dt: float) -> void:
	var moved := Vector2(position.x - _last_pos.x, position.z - _last_pos.z).length() / maxf(dt, 0.001)
	_last_pos = position
	_anim_speed = lerpf(_anim_speed, moved, 0.3)
	_walk_phase += dt * (6.0 + _anim_speed * 1.6)
	Body.animate(model, _anim_speed, _walk_phase)
	if stun > 0.0:
		(model.get_node("Bob") as Node3D).rotation.x = sin(stun * 30.0) * 0.3


func knock(impulse: Vector3, stun_time: float) -> void:
	velocity = impulse
	stun = stun_time


## Where this player really is: a puppet's latest reported spot, not its smoothed copy.
func true_pos() -> Vector3:
	return _target_pos if mode == Mode.PUPPET else position


func set_remote_state(pos: Vector3, yaw: float) -> void:
	_target_pos = pos
	_target_yaw = yaw


func teleport(pos: Vector3) -> void:
	position = pos
	_target_pos = pos
	_last_pos = pos
	velocity = Vector3.ZERO


func set_alive(v: bool) -> void:
	alive = v
	visible = v
	collision_layer = Build.PLAYERS if v else 0
	collision_mask = (Build.WORLD | Build.PLAYERS | Build.DOORS) if v else 0
	if not v:
		velocity = Vector3.ZERO


## Redraw the tower of loot balanced on the player's head.
func set_carried(ids: Array[int], kinds: Array[String]) -> void:
	carried = ids
	carried_kinds = kinds
	carried_kg = 0.0
	for c in _stack.get_children():
		c.queue_free()
	var y := 0.0
	for k in kinds:
		carried_kg += Rules.loot_kg(k)
		var size: Vector3 = Rules.LOOT[k][5]
		var s := clampf(0.55 / maxf(size.x, size.y), 0.35, 1.0)
		var mi := Build.mesh(_stack, Build.loot_mesh(k), Vector3(0, y + size.y * s / 2.0, 0), Build.mat(Rules.LOOT[k][4], 0.45, 0.2))
		mi.scale = Vector3.ONE * s
		y += size.y * s
	_label.position.y = 2.15 + y
