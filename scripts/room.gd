class_name Room
extends Node3D

## One floor of the building, built in front of the cab doors from (kind, seed), so every
## peer builds the same room. The host runs the hazard; everyone else just draws it.
##
## Room space: x in [-9, 9], z in [-16, -0.2]. The cab doorway is at x in [-1.1, 1.1], z = 0.

const HALF_W := 9.0
const BACK := -16.0
const FRONT := -0.2

var kind := "office"
var seed_value := 0
var loot_points: Array[Vector3] = []
var npcs: Array[Node3D] = []
var env: Environment
var stage := 0                    # fire: how many rack rows are burning
var _rng := RandomNumberGenerator.new()
var _font: Font
var _cool := {}                   # player id -> seconds until a hazard may hit them again
var _npc_vel: Array[Vector3] = []
var _gorilla_rest := 0.0
var _gorilla_path: PackedVector3Array = []
var _gorilla_repath := 0.0
var _fires: Array[Node3D] = []
var _disco: OmniLight3D
var _t := 0.0
# ghosts: a spooked hazard goes for one person for a few seconds
var _spook_id := 0
var _spook_t := 0.0
var _spook_new := false
var _conga_off := Vector3.ZERO
var _flare: Node3D                # fire: a flare-up under a spooked person
var _flare_t := 0.0
var _water: Node3D                # spa: its height is the water level
var _fence: Node3D                # vault: z is the sweep, x the gap in the beams
var _fence_dir := 1.0
var _balls: MultiMeshInstance3D
var _kid_rest := 0.0
var _kid_path: PackedVector3Array = []
var _kid_repath := 0.0

const FIRE_ROWS := [-13.5, -10.5, -7.5, -4.5]   # back to front: the order they catch
const FIRE_START := 3.0
const FIRE_EVERY := 3.0
const CONGA_LOOP := [Vector3(-3.2, 0, -5.2), Vector3(3.2, 0, -5.2), Vector3(3.2, 0, -12.8), Vector3(-3.2, 0, -12.8)]
const CONGA_SPEED := 2.3
const GORILLA_SPEED := 3.4
const GORILLA_RELEASE := 2.0
const FLARE_RADIUS := 1.6
const WATER_START := 2.0
const WATER_RISE := 12.0          # seconds from dry to full
const WATER_MAX := 0.75
const FENCE_NEAR := -1.4          # the laser sweep turns back before it reaches the cab
const FENCE_FAR := -15.2
const FENCE_SPEED := 1.9
const FENCE_GAP := 1.1            # half-width of the opening in the beams
const PIT := Rect2(-4.0, -12.0, 8.0, 6.0)   # daycare ball pit, in (x, z)
const KID_SPEED := 3.3
const KID_RELEASE := 1.5


static func create(room_kind: String, room_seed: int) -> Room:
	var r := Room.new()
	r.name = "Room"
	r.kind = room_kind
	r.seed_value = room_seed
	r._rng.seed = room_seed
	r._font = load("res://assets/fonts/Bungee-Regular.ttf")
	match room_kind:
		"office":
			r._build_office()
		"fire":
			r._build_fire()
		"spa":
			r._build_spa()
		"vault":
			r._build_vault()
		"daycare":
			r._build_daycare()
		_:
			r._build_zoo()
	return r


# --- building -----------------------------------------------------------------------------

func _shell(floor_c: Color, wall_c: Color, ceiling := true, wall_h := 3.6) -> void:
	var wall := Build.mat(wall_c, 0.85)
	Build.box(self, Vector3(HALF_W * 2 + 0.4, 0.2, -BACK + 0.4), Vector3(0, -0.1, BACK / 2.0 - 0.1), Build.mat(floor_c, 0.9))
	Build.box(self, Vector3(0.3, wall_h, -BACK), Vector3(-HALF_W - 0.15, wall_h / 2.0, BACK / 2.0), wall)
	Build.box(self, Vector3(0.3, wall_h, -BACK), Vector3(HALF_W + 0.15, wall_h / 2.0, BACK / 2.0), wall)
	Build.box(self, Vector3(HALF_W * 2 + 0.6, wall_h, 0.3), Vector3(0, wall_h / 2.0, BACK - 0.15), wall)
	Build.wall_with_hole(self, -HALF_W - 0.3, HALF_W + 0.3, FRONT - 0.05, maxf(wall_h, 3.6), 1.25, 2.5, 0.1, wall)
	if ceiling:
		Build.box(self, Vector3(HALF_W * 2 + 0.6, 0.2, -BACK + 0.4), Vector3(0, wall_h + 0.1, BACK / 2.0), Build.mat(wall_c.lightened(0.15), 0.9))


func _indoor_env(ambient: Color, energy: float, bg: Color) -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = bg
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = ambient
	env.ambient_light_energy = energy
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05


func _point(x: float, y: float, z: float) -> void:
	loot_points.append(Vector3(x, y, z))


func _build_office() -> void:
	_shell(Color("4a5a78"), Color("e3dac4"))
	_indoor_env(Color("fff1dc"), 0.55, Color("141210"))
	var desk := Build.mat(Color("b88b5e"), 0.7)
	var screen := Build.mat(Color("1d2733"), 0.4, 0.0, 0.0)
	var glow := Build.mat(Color("8fd3ff"), 0.4, 0.0, 1.4)
	for row in [-4.5, -8.0, -11.5]:
		for side in [-1, 1]:
			var x: float = 6.2 * side
			Build.box(self, Vector3(3.0, 0.76, 1.2), Vector3(x, 0.38, row), desk)
			Build.nav_block(self, Vector3(3.0, 0.76, 1.2), Vector3(x, 0.38, row))
			for k in [-0.7, 0.7]:
				Build.mesh(self, Build.box_mesh(Vector3(0.55, 0.36, 0.05)), Vector3(x + k, 0.98, row + 0.3), screen)
				Build.mesh(self, Build.box_mesh(Vector3(0.5, 0.3, 0.01)), Vector3(x + k, 0.98, row + 0.27), glow)
			_point(x + _rng.randf_range(-1.1, 1.1), 0.76, row - 0.25)
	# the party table in the middle of the conga loop
	Build.box(self, Vector3(3.6, 0.76, 1.0), Vector3(0, 0.38, -9.0), Build.mat(Color("f2f2f2"), 0.6))
	Build.nav_block(self, Vector3(3.6, 0.76, 1.0), Vector3(0, 0.38, -9.0))
	_point(-1.0, 0.76, -9.0)
	_point(1.0, 0.76, -9.0)
	for i in 5:
		_point(_rng.randf_range(-8.0, 8.0), 0.0, _rng.randf_range(-15.0, -2.5))
	# ceiling lights
	for z in [-3.5, -8.5, -13.5]:
		for x in [-5.0, 0.0, 5.0]:
			Build.mesh(self, Build.box_mesh(Vector3(1.2, 0.03, 0.6)), Vector3(x, 3.58, z), Build.mat(Color("fff6e0"), 0.5, 0.0, 1.6))
		Build.light(self, Vector3(0, 3.2, z), Color("fff1dc"), 1.4, 11.0, z == -8.5)
	# party: balloons, a banner and a disco light
	var colors := [Color("ef4444"), Color("f59e0b"), Color("22c55e"), Color("3b82f6"), Color("ec4899")]
	for i in 14:
		var p := Vector3(_rng.randf_range(-8.5, 8.5), _rng.randf_range(2.4, 3.3), _rng.randf_range(-15.5, -2.0))
		Build.mesh(self, Build.sphere_mesh(0.22, 0.52), p, Build.mat(colors[i % colors.size()], 0.3))
	var banner := Build.label(self, "HAPPY RETIREMENT, GARY!", Vector3(0, 2.7, BACK + 0.02), 120, Color("d0342c"), _font)
	banner.pixel_size = 0.006
	_disco = Build.light(self, Vector3(0, 3.0, -9.0), Color("ff4fd8"), 1.6, 9.0)
	# the conga line
	for i in 6:
		var hat: Color = colors[i % colors.size()]
		var dancer := Body.person(Color("394150").lerp(hat, 0.25), Body.SKINS[i % Body.SKINS.size()], hat)
		add_child(dancer)
		npcs.append(dancer)
		_npc_vel.append(Vector3.ZERO)
	_place_conga(0.0)


func _build_fire() -> void:
	_shell(Color("34373c"), Color("25282c"))
	_indoor_env(Color("ffb08a"), 0.5, Color("0b0909"))
	var rack := Build.mat(Color("1b1e22"), 0.5, 0.4)
	var green := Build.mat(Color("3cff8a"), 0.4, 0.0, 2.0)
	var amber := Build.mat(Color("ffb02e"), 0.4, 0.0, 2.0)
	for row in FIRE_ROWS:
		for side in [-1, 1]:
			var cx: float = 4.35 * side
			Build.box(self, Vector3(6.3, 2.2, 0.9), Vector3(cx, 1.1, row), rack)
			for k in 8:
				var lx := cx - 2.8 + k * 0.8
				for j in 4:
					Build.mesh(self, Build.box_mesh(Vector3(0.05, 0.03, 0.01)), Vector3(lx, 0.5 + j * 0.45, row + 0.46),
						green if (k + j) % 3 else amber)
	# loot in the aisles: the far aisles hold the most
	for aisle in [-15.0, -12.0, -9.0, -6.0]:
		for i in 2:
			_point(_rng.randf_range(-7.5, 7.5), 0.0, aisle + _rng.randf_range(-0.4, 0.4))
	_point(_rng.randf_range(-7.0, 7.0), 0.0, -2.6)
	_point(_rng.randf_range(-7.0, -2.0), 0.0, -14.8)
	_point(_rng.randf_range(2.0, 7.0), 0.0, -14.8)
	# red warning lamps
	for z in [-3.0, -9.0, -15.0]:
		Build.light(self, Vector3(0, 3.1, z), Color("ff4433"), 0.9, 9.0)
		Build.mesh(self, Build.cyl_mesh(0.15, 0.1), Vector3(0, 3.5, z), Build.mat(Color("ff4433"), 0.4, 0.0, 3.0))
	Build.light(self, Vector3(0, 2.5, -1.5), Color("ffd9b0"), 1.0, 7.0)
	for z in [-6.0, -12.0]:
		for x in [-4.5, 4.5]:
			Build.light(self, Vector3(x, 3.0, z), Color("ffe1c4"), 0.7, 6.0)
	# one fire per rack row, hidden until it catches
	var flame := Build.mat(Color("ff7a1a"), 0.5, 0.0, 4.0)
	var core := Build.mat(Color("ffd25a"), 0.5, 0.0, 5.0)
	for row in FIRE_ROWS:
		var f := Node3D.new()
		f.position = Vector3(0, 0, row)
		f.visible = false
		add_child(f)
		for i in 16:
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = _rng.randf_range(0.25, 0.45)
			cone.height = _rng.randf_range(0.9, 1.9)
			cone.radial_segments = 6
			var x := -8.0 + i * (16.0 / 15.0) + _rng.randf_range(-0.3, 0.3)
			var z := _rng.randf_range(-1.3, 1.3)
			Build.mesh(f, cone, Vector3(x, cone.height / 2.0, z), flame if i % 3 else core)
		Build.light(f, Vector3(-4, 1.4, 0), Color("ff7a1a"), 3.0, 7.0)
		Build.light(f, Vector3(4, 1.4, 0), Color("ff7a1a"), 3.0, 7.0)
		_fires.append(f)
	# the flare-up a ghost can call down on someone; parked under the floor until then
	_flare = Node3D.new()
	_flare.position = Vector3(0, -50, 0)
	add_child(_flare)
	for i in 9:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = _rng.randf_range(0.25, 0.4)
		cone.height = _rng.randf_range(0.8, 1.6)
		cone.radial_segments = 6
		var a := i * TAU / 9.0
		var r := 0.4 + (i % 3) * 0.4
		Build.mesh(_flare, cone, Vector3(cos(a) * r, cone.height / 2.0, sin(a) * r), flame if i % 3 else core)
	Build.light(_flare, Vector3(0, 1.2, 0), Color("ff7a1a"), 3.0, 6.0)
	npcs.append(_flare)
	_npc_vel.append(Vector3.ZERO)


func _build_zoo() -> void:
	# a rooftop: low parapet walls, open sky
	var roof := Build.mat(Color("8f8b82"), 0.95)
	var para := Build.mat(Color("b5aea0"), 0.9)
	Build.box(self, Vector3(HALF_W * 2 + 0.4, 0.2, -BACK + 0.4), Vector3(0, -0.1, BACK / 2.0 - 0.1), roof)
	Build.box(self, Vector3(0.3, 1.0, -BACK), Vector3(-HALF_W - 0.15, 0.5, BACK / 2.0), para)
	Build.box(self, Vector3(0.3, 1.0, -BACK), Vector3(HALF_W + 0.15, 0.5, BACK / 2.0), para)
	Build.box(self, Vector3(HALF_W * 2 + 0.6, 1.0, 0.3), Vector3(0, 0.5, BACK - 0.15), para)
	# the lift housing the doors open out of
	Build.wall_with_hole(self, -3.0, 3.0, FRONT - 0.05, 3.8, 1.25, 2.5, 0.1, Build.mat(Color("cfc6b4"), 0.85))
	for side in [-1, 1]:  # low parapet either side of the housing
		Build.box(self, Vector3(HALF_W - 3.0, 1.0, 0.3), Vector3(side * (3.0 + (HALF_W - 3.0) / 2.0), 0.5, FRONT - 0.15), para)
	env = Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("3d7fd1")
	sm.sky_horizon_color = Color("bcd6ee")
	sm.ground_horizon_color = Color("a9b8c8")
	sm.ground_bottom_color = Color("4a5866")
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 35, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)
	# skyline: other towers around this one
	var tower := Build.mat(Color("8aa0b8"), 0.6, 0.2)
	for i in 18:
		var a := -PI * 0.9 + i * (PI * 1.8 / 17.0)
		var dist := _rng.randf_range(45.0, 80.0)
		var h := _rng.randf_range(10.0, 40.0)
		var w := _rng.randf_range(6.0, 14.0)
		Build.mesh(self, Build.box_mesh(Vector3(w, h, w)), Vector3(sin(a) * dist, h / 2.0 - 25.0, -cos(a) * dist - 8.0), tower)
	# pens
	var fence := Build.mat(Color("6b5136"), 0.8)
	_pen(-8.2, -3.2, -14.8, -8.8, fence, "left")
	_pen(3.2, 8.2, -14.8, -8.8, fence, "right")
	Build.box(self, Vector3(2.8, 0.05, 2.6), Vector3(5.6, 0.02, -12.0), Build.mat(Color("4aa3d8"), 0.15, 0.1), false)
	# the gorilla enclosure at the back, open to the front
	var rock := Build.mat(Color("6d6a62"), 0.95)
	Build.box(self, Vector3(1.6, 1.4, 1.2), Vector3(-1.4, 0.7, -15.2), rock)
	Build.box(self, Vector3(1.2, 1.0, 1.0), Vector3(1.5, 0.5, -15.3), rock)
	Build.nav_block(self, Vector3(1.6, 1.4, 1.2), Vector3(-1.4, 0.7, -15.2))
	Build.nav_block(self, Vector3(1.2, 1.0, 1.0), Vector3(1.5, 0.5, -15.3))
	# trees
	var trunk := Build.mat(Color("6b4a2e"), 0.9)
	var leaf := Build.mat(Color("4f9a4a"), 0.8)
	for p in [Vector3(-5.5, 0, -4.0), Vector3(5.5, 0, -4.5), Vector3(-7.8, 0, -7.0), Vector3(7.8, 0, -15.0)]:
		Build.cyl(self, 0.18, 2.2, p + Vector3(0, 1.1, 0), trunk)
		Build.mesh(self, Build.sphere_mesh(1.0, 1.6), p + Vector3(0, 2.7, 0), leaf)
	# loot
	for i in 3:
		_point(_rng.randf_range(-7.4, -4.0), 0.0, _rng.randf_range(-14.0, -9.6))
		_point(_rng.randf_range(4.0, 7.4), 0.0, _rng.randf_range(-14.0, -9.6))
	for i in 4:
		_point(_rng.randf_range(-7.5, 7.5), 0.0, _rng.randf_range(-8.0, -2.5))
	_point(0.0, 0.0, -13.6)
	# the gorilla
	var g := Body.gorilla()
	g.position = Vector3(0, 0, -14.0)
	add_child(g)
	npcs.append(g)
	_npc_vel.append(Vector3.ZERO)


func _build_spa() -> void:
	_shell(Color("4f7f88"), Color("b9cfcc"))
	_indoor_env(Color("dff3ff"), 0.42, Color("0d1416"))
	var tile := Build.mat(Color("7fb8c0"), 0.3)
	var wood := Build.mat(Color("a47148"), 0.7)
	var cushion := Build.mat(Color("f6f1e7"), 0.9)
	# two hot tubs: raised, solid, water steaming
	for x in [-5.0, 5.0]:
		Build.box(self, Vector3(3.0, 0.6, 3.0), Vector3(x, 0.3, -11.0), tile)
		Build.nav_block(self, Vector3(3.0, 0.6, 3.0), Vector3(x, 0.3, -11.0))
		Build.mesh(self, Build.box_mesh(Vector3(2.6, 0.02, 2.6)), Vector3(x, 0.61, -11.0), Build.mat(Color("38bdf8"), 0.05, 0.1, 0.3))
		var mist := Build.mesh(self, Build.sphere_mesh(1.4, 0.35), Vector3(x, 0.9, -11.0), Build.mat(Color(1, 1, 1, 0.12), 1.0))
		(mist.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# loungers along both walls, loot on the cushions (dry for longer than the floor)
	for side in [-1, 1]:
		for z in [-3.5, -6.5, -14.4]:
			var x: float = 7.7 * side
			Build.box(self, Vector3(0.9, 0.4, 1.9), Vector3(x, 0.2, z), wood)
			Build.nav_block(self, Vector3(0.9, 0.4, 1.9), Vector3(x, 0.2, z))
			Build.mesh(self, Build.box_mesh(Vector3(0.8, 0.08, 1.8)), Vector3(x, 0.44, z), cushion)
			_point(x, 0.48, z + _rng.randf_range(-0.5, 0.5))
	# a fountain in the middle, the cherub's old spot
	Build.cyl(self, 0.9, 0.5, Vector3(0, 0.25, -7.5), tile)
	Build.nav_block(self, Vector3(1.8, 0.5, 1.8), Vector3(0, 0.25, -7.5))
	for i in 6:
		_point(_rng.randf_range(-6.5, 6.5), 0.0, _rng.randf_range(-15.0, -2.5))
	_point(0.0, 0.0, -14.8)
	_point(_rng.randf_range(-2.0, 2.0), 0.0, -4.0)
	for z in [-4.0, -10.0, -15.0]:
		Build.light(self, Vector3(0, 3.2, z), Color("e6f6ff"), 1.3, 11.0, z == -10.0)
	var sign := Build.label(self, "SERENITY SPA  ·  PLEASE WALK", Vector3(0, 2.7, BACK + 0.02), 110, Color("0e7490"), _font)
	sign.pixel_size = 0.006
	# the flood: one sheet of water that rises over the floor
	_water = Node3D.new()
	_water.position = Vector3(0, 0.02, 0)
	add_child(_water)
	var sheet := PlaneMesh.new()
	sheet.size = Vector2(HALF_W * 2.0, -BACK + FRONT)
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.12, 0.5, 0.68, 0.62)
	wm.roughness = 0.05
	wm.metallic = 0.2
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	Build.mesh(_water, sheet, Vector3(0, 0, (BACK + FRONT) / 2.0), wm)
	npcs.append(_water)
	_npc_vel.append(Vector3.ZERO)


func _build_vault() -> void:
	_shell(Color("2a2d33"), Color("3b4048"))
	_indoor_env(Color("ffe8c2"), 0.45, Color("08080a"))
	var steel := Build.mat(Color("8a9099"), 0.35, 0.8)
	var gold := Build.mat(Color("eab308"), 0.3, 0.9, 0.2)
	var velvet := Build.mat(Color("7f1d1d"), 0.9)
	# walls of safe-deposit boxes
	for side in [-1, 1]:
		for j in 5:
			for k in 14:
				Build.mesh(self, Build.box_mesh(Vector3(0.04, 0.5, 0.95)), Vector3(side * (HALF_W - 0.02), 0.5 + j * 0.6, -1.2 - k * 1.05),
					steel if (j + k) % 2 else Build.mat(Color("6b7280"), 0.4, 0.7))
	# pedestals with velvet tops; loot sits on them
	for p in [Vector3(-4.0, 0, -5.5), Vector3(4.0, 0, -5.5), Vector3(-4.0, 0, -12.0), Vector3(4.0, 0, -12.0), Vector3(0, 0, -9.0)]:
		Build.box(self, Vector3(1.0, 0.9, 1.0), p + Vector3(0, 0.45, 0), steel)
		Build.nav_block(self, Vector3(1.0, 0.9, 1.0), p + Vector3(0, 0.45, 0))
		Build.mesh(self, Build.box_mesh(Vector3(0.9, 0.04, 0.9)), p + Vector3(0, 0.92, 0), velvet)
		_point(p.x, 0.94, p.z)
	# a gold pile at the back
	for i in 22:
		Build.mesh(self, Build.box_mesh(Vector3(0.36, 0.12, 0.18)),
			Vector3(_rng.randf_range(-2.5, 2.5), 0.06 + (i % 4) * 0.12, -15.3 + _rng.randf_range(-0.3, 0.3)), gold,
			Vector3(0, _rng.randf_range(-0.5, 0.5), 0))
	for i in 7:
		_point(_rng.randf_range(-7.5, 7.5), 0.0, _rng.randf_range(-14.5, -2.5))
	_point(_rng.randf_range(-2.0, 2.0), 0.0, -14.3)
	# the big round vault door, open, against the left wall
	var door := Build.mesh(self, Build.cyl_mesh(1.5, 0.4, 20), Vector3(-HALF_W + 0.3, 1.6, -15.0), steel, Vector3(0, 0, PI / 2))
	door.name = "VaultDoor"
	for z in [-4.0, -9.0, -14.0]:
		Build.light(self, Vector3(0, 3.2, z), Color("ffe1b0"), 1.0, 9.0, z == -9.0)
	# the laser sweep: three red beams across the room, with one gap that wanders
	_fence = Node3D.new()
	_fence.position = Vector3(0, 0, FENCE_FAR)
	add_child(_fence)
	var beam := Build.mat(Color("ff2020"), 0.4, 0.0, 6.0)
	for y in [0.3, 0.85, 1.4]:
		for side in [-1, 1]:
			var length := 20.0
			Build.mesh(_fence, Build.box_mesh(Vector3(length, 0.035, 0.035)), Vector3(side * (FENCE_GAP + length / 2.0), y, 0), beam)
	Build.light(_fence, Vector3(0, 0.9, 0), Color("ff2020"), 1.4, 5.0)
	npcs.append(_fence)
	_npc_vel.append(Vector3.ZERO)


func _build_daycare() -> void:
	_shell(Color("5b8fd6"), Color("f2c98a"))
	_indoor_env(Color("fff7e6"), 0.42, Color("141210"))
	var colors := [Color("ef4444"), Color("f59e0b"), Color("22c55e"), Color("3b82f6"), Color("ec4899"), Color("a855f7")]
	# the ball pit: a low padded rim with an opening in the middle of each side
	var rim := Build.mat(Color("f472b6"), 0.8)
	var x0 := PIT.position.x
	var x1 := PIT.end.x
	var z0 := PIT.position.y
	var z1 := PIT.end.y
	var gap := 0.9
	for z in [z0, z1]:
		for half in [[x0, -gap], [gap, x1]]:
			var w: float = half[1] - half[0]
			Build.box(self, Vector3(w, 0.35, 0.25), Vector3((half[0] + half[1]) / 2.0, 0.175, z), rim)
	for x in [x0, x1]:
		var zm := (z0 + z1) / 2.0
		for half in [[z0, zm - gap], [zm + gap, z1]]:
			var d: float = half[1] - half[0]
			Build.box(self, Vector3(0.25, 0.35, d), Vector3(x, 0.175, (half[0] + half[1]) / 2.0), rim)
	_balls = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = Build.sphere_mesh(0.14)
	mm.instance_count = 1100
	for i in mm.instance_count:
		var pos := Vector3(_rng.randf_range(x0 + 0.2, x1 - 0.2), _rng.randf_range(0.08, 0.4), _rng.randf_range(z0 + 0.2, z1 - 0.2))
		mm.set_instance_transform(i, Transform3D(Basis(), pos))
		mm.set_instance_color(i, colors[i % colors.size()])
	_balls.multimesh = mm
	var bm := StandardMaterial3D.new()
	bm.vertex_color_use_as_albedo = true
	bm.roughness = 0.35
	_balls.material_override = bm
	add_child(_balls)
	# loot buried in the pit
	for i in 6:
		_point(_rng.randf_range(x0 + 0.6, x1 - 0.6), 0.0, _rng.randf_range(z0 + 0.6, z1 - 0.6))
	# toy shelves along the back wall, loot on top
	var shelf := Build.mat(Color("fde68a"), 0.7)
	for x in [-6.5, 6.5]:
		Build.box(self, Vector3(2.4, 0.9, 0.7), Vector3(x, 0.45, -15.2), shelf)
		Build.nav_block(self, Vector3(2.4, 0.9, 0.7), Vector3(x, 0.45, -15.2))
		_point(x + _rng.randf_range(-0.8, 0.8), 0.9, -15.1)
	for i in 5:
		var side := -1.0 if i % 2 else 1.0
		_point(side * _rng.randf_range(5.0, 8.0), 0.0, _rng.randf_range(-14.0, -2.5))
	_point(_rng.randf_range(-2.0, 2.0), 0.0, -14.0)
	# play mats and big soft blocks
	for i in 10:
		var c: Color = colors[i % colors.size()]
		Build.mesh(self, Build.box_mesh(Vector3(1.4, 0.02, 1.4)), Vector3(-7.6 + (i % 2) * 15.2, 0.01, -2.0 - i * 1.4), Build.mat(c.lightened(0.3), 0.9))
	for z in [-4.0, -9.0, -14.0]:
		Build.light(self, Vector3(0, 3.2, z), Color("fff4dd"), 1.3, 11.0, z == -9.0)
	var sign := Build.label(self, "LITTLE STARS DAYCARE", Vector3(0, 2.7, BACK + 0.02), 120, Color("db2777"), _font)
	sign.pixel_size = 0.006
	# the toddler: small, fast enough, wants whatever you are holding
	var kid := Body.person(Color("fbbf24"), Body.SKINS[0], Color("38bdf8"))
	kid.scale = Vector3.ONE * 0.55
	kid.position = Vector3(-7.0, 0, -14.0)
	add_child(kid)
	npcs.append(kid)
	_npc_vel.append(Vector3.ZERO)


func _pen(x0: float, x1: float, z0: float, z1: float, m: Material, side: String) -> void:
	var h := 1.1
	Build.box(self, Vector3(x1 - x0, h, 0.1), Vector3((x0 + x1) / 2.0, h / 2.0, z0), m)
	# the front fence has a 2 m gap in the middle to walk through
	var mid := (x0 + x1) / 2.0
	Build.box(self, Vector3(mid - 1.0 - x0, h, 0.1), Vector3((x0 + mid - 1.0) / 2.0, h / 2.0, z1), m)
	Build.box(self, Vector3(x1 - mid - 1.0, h, 0.1), Vector3((mid + 1.0 + x1) / 2.0, h / 2.0, z1), m)
	var outer := x0 if side == "left" else x1
	var inner := x1 if side == "left" else x0
	Build.box(self, Vector3(0.1, h, z1 - z0), Vector3(inner, h / 2.0, (z0 + z1) / 2.0), m)
	if absf(outer) < HALF_W - 0.5:
		Build.box(self, Vector3(0.1, h, z1 - z0), Vector3(outer, h / 2.0, (z0 + z1) / 2.0), m)


# --- the hazard ---------------------------------------------------------------------------

## Host only. `people` is [{id, pos, out, value}] for everyone alive; `t` is seconds since the
## doors opened. Returns hits: [{id, impulse, stun, drop, sound}] (+ "steal": the toddler).
func server_tick(dt: float, t: float, people: Array, nav_map: RID) -> Array:
	_t = t
	var hits := []
	for k in _cool.keys():
		_cool[k] -= dt
	_spook_t = maxf(_spook_t - dt, 0.0)
	var spooked := _spook_target(people)
	match kind:
		"office":
			var want := Vector3.ZERO
			if not spooked.is_empty():
				want = spooked.pos - Vector3(0, 0, -9.0)
				want.y = 0
			_conga_off = _conga_off.move_toward(want, dt * 4.0)
			_place_conga(t)
			for p in people:
				if not p.out or _cool.get(p.id, 0.0) > 0.0:
					continue
				for n in npcs:
					var d: Vector3 = p.pos - n.position
					d.y = 0
					if d.length() < 0.85:
						_cool[p.id] = 1.4
						var push := d.normalized() if d.length() > 0.05 else Vector3.RIGHT
						hits.append({"id": p.id, "impulse": push * 7.0 + Vector3.UP * 2.0, "stun": 0.5,
							"drop": 1 if _rng.randf() < 0.5 else 0, "sound": "shove"})
						break
		"fire":
			var s := clampi(int(floor((t - FIRE_START) / FIRE_EVERY)) + 1, 0, FIRE_ROWS.size()) if t >= FIRE_START else 0
			stage = s
			if _spook_new and not spooked.is_empty():
				_flare_t = Rules.SPOOK_TIME
				_flare.position = Vector3(spooked.pos.x, 0, minf(spooked.pos.z, -1.2))
			_flare_t = maxf(_flare_t - dt, 0.0)
			if _flare_t <= 0.0:
				_flare.position.y = -50.0
			for p in people:
				if p.out and burning(p.pos) and _cool.get(p.id, 0.0) <= 0.0:
					_cool[p.id] = 1.2
					hits.append({"id": p.id, "impulse": Vector3(0, 3.0, 8.0), "stun": 0.4, "drop": 1, "sound": "slam"})
		"zoo":
			hits = _gorilla_tick(dt, t, people, nav_map, spooked)
		"spa":
			_water.position.y = 0.02 + clampf((t - WATER_START) / WATER_RISE, 0.0, 1.0) * WATER_MAX
			if _spook_new and not spooked.is_empty():
				# a surge: the water throws them away from the cab
				hits.append({"id": spooked.id, "impulse": Vector3(_rng.randf_range(-2, 2), 3.0, -8.0), "stun": 0.8,
					"drop": 1, "sound": "slam"})
		"vault":
			hits = _fence_tick(dt, people, spooked)
		"daycare":
			hits = _kid_tick(dt, t, people, nav_map, spooked)
	_spook_new = false
	return hits


## A ghost sets this room's hazard on one person for a few seconds. Host only.
func spook(pid: int) -> void:
	_spook_id = pid
	_spook_t = Rules.SPOOK_TIME
	_spook_new = true


func _spook_target(people: Array) -> Dictionary:
	if _spook_t <= 0.0:
		return {}
	for p in people:
		if p.id == _spook_id and p.out:
			return p
	return {}


func burning(pos: Vector3) -> bool:
	if kind != "fire":
		return false
	for i in stage:
		if absf(pos.z - FIRE_ROWS[i]) < 1.55 and pos.z < -0.5:
			return true
	if _flare and _flare.position.y > -1.0 and pos.z < -0.5:
		if Vector2(pos.x - _flare.position.x, pos.z - _flare.position.z).length() < FLARE_RADIUS:
			return true
	return false


## Spa: how high the flood is (0 when this room has no water).
func water_level() -> float:
	return _water.position.y if _water else 0.0


## How much wading slows you here: the flood, or the ball pit. 1 = not at all.
func wade(pos: Vector3) -> float:
	if pos.z > FRONT:
		return 1.0
	match kind:
		"spa":
			var depth := clampf(water_level() - pos.y, 0.0, WATER_MAX)
			return 1.0 - depth * 0.6
		"daycare":
			return 0.7 if in_pit(pos) else 1.0
	return 1.0


func in_pit(pos: Vector3) -> bool:
	return kind == "daycare" and PIT.has_point(Vector2(pos.x, pos.z))


## Where the toddler drops what it took: somewhere in the pit. Host only.
func pit_spot() -> Vector3:
	return Vector3(_rng.randf_range(PIT.position.x + 0.6, PIT.end.x - 0.6), 0.0, _rng.randf_range(PIT.position.y + 0.6, PIT.end.y - 0.6))


func _fence_tick(dt: float, people: Array, spooked: Dictionary) -> Array:
	var hits := []
	var f := _fence
	var speed := FENCE_SPEED
	var gap_want := sin(_t * 0.7) * 5.5
	if not spooked.is_empty():
		# the sweep goes for them, and the gap runs to the far side
		_fence_dir = signf(spooked.pos.z - f.position.z) if absf(spooked.pos.z - f.position.z) > 0.2 else _fence_dir
		speed = 4.0
		gap_want = -signf(spooked.pos.x) * 6.0 if absf(spooked.pos.x) > 0.3 else 6.0
	f.position.z += _fence_dir * speed * dt
	if f.position.z > FENCE_NEAR:
		f.position.z = FENCE_NEAR
		_fence_dir = -1.0
	elif f.position.z < FENCE_FAR:
		f.position.z = FENCE_FAR
		_fence_dir = 1.0
	f.position.x = move_toward(f.position.x, gap_want, dt * (6.0 if not spooked.is_empty() else 2.5))
	for p in people:
		if not p.out or _cool.get(p.id, 0.0) > 0.0:
			continue
		if laser_hits(p.pos):
			_cool[p.id] = 1.2
			hits.append({"id": p.id, "impulse": Vector3(0, 2.0, _fence_dir * 5.0), "stun": 0.3, "drop": 1, "sound": "buzzer"})
	return hits


## Vault: is someone standing at `pos` in the beams right now?
func laser_hits(pos: Vector3) -> bool:
	if kind != "vault" or _fence == null or pos.z > -0.5:
		return false
	return absf(pos.z - _fence.position.z) < 0.3 and absf(pos.x - _fence.position.x) > FENCE_GAP - 0.3 and pos.y < 1.5


func _kid_tick(dt: float, t: float, people: Array, nav_map: RID, spooked: Dictionary) -> Array:
	var kid := npcs[0]
	if t < KID_RELEASE:
		Body.animate(kid, 0.0, 0.0)
		return []
	if _kid_rest > 0.0:
		_kid_rest -= dt
		Body.animate(kid, 0.0, t * 10.0)
		return []
	# chase whoever outside is carrying the most; a spooked person first
	var target := {}
	if not spooked.is_empty():
		target = spooked
	else:
		var best := 0
		for p in people:
			if p.out and p.value > best:
				best = p.value
				target = p
	var goal := Vector3(PIT.get_center().x, 0, PIT.get_center().y) if target.is_empty() else (target.pos as Vector3)
	goal.z = minf(goal.z, -0.8)
	var speed := KID_SPEED * (1.4 if not spooked.is_empty() else 1.0)
	_kid_repath -= dt
	if _kid_repath <= 0.0 and nav_map.is_valid():
		_kid_repath = 0.4
		_kid_path = NavigationServer3D.map_get_path(nav_map, kid.position, goal, true)
	var step := goal
	while _kid_path.size() > 0 and Vector2(_kid_path[0].x - kid.position.x, _kid_path[0].z - kid.position.z).length() < 0.3:
		_kid_path.remove_at(0)
	if _kid_path.size() > 0:
		step = _kid_path[0]
	var dir := step - kid.position
	dir.y = 0
	if dir.length() > 0.05:
		dir = dir.normalized()
		kid.position += dir * speed * dt
		kid.rotation.y = lerp_angle(kid.rotation.y, atan2(-dir.x, -dir.z), 0.25)
	kid.position.y = 0.0
	kid.position.z = minf(kid.position.z, -0.8)
	Body.animate(kid, speed * 1.5, t * 14.0)
	var hits := []
	for p in people:
		if not p.out or p.value <= 0 or _cool.get(p.id, 0.0) > 0.0:
			continue
		var d: Vector3 = p.pos - kid.position
		d.y = 0
		if d.length() < 0.9:
			_cool[p.id] = 2.0
			_kid_rest = 1.5
			hits.append({"id": p.id, "impulse": d.normalized() * 3.0 + Vector3.UP * 1.5, "stun": 0.4, "drop": 0,
				"steal": true, "sound": "pickup"})
			break
	return hits


func _place_conga(t: float) -> void:
	var perim := 0.0
	var lens := []
	for i in CONGA_LOOP.size():
		var l: float = CONGA_LOOP[i].distance_to(CONGA_LOOP[(i + 1) % CONGA_LOOP.size()])
		lens.append(l)
		perim += l
	for k in npcs.size():
		var s := fposmod(t * CONGA_SPEED + k * 1.1, perim)
		var i := 0
		while s > lens[i]:
			s -= lens[i]
			i += 1
		var a: Vector3 = CONGA_LOOP[i]
		var b: Vector3 = CONGA_LOOP[(i + 1) % CONGA_LOOP.size()]
		var pos := a.lerp(b, s / lens[i]) + _conga_off
		pos.x = clampf(pos.x, -HALF_W + 0.5, HALF_W - 0.5)
		pos.z = clampf(pos.z, BACK + 0.5, -1.0)
		npcs[k].position = pos
		npcs[k].rotation.y = atan2(-(b - a).x, -(b - a).z) + sin(t * 8.0 + k) * 0.25
		Body.animate(npcs[k], CONGA_SPEED, t * 9.0 + k)


func _gorilla_tick(dt: float, t: float, people: Array, nav_map: RID, spooked: Dictionary) -> Array:
	var g := npcs[0]
	if t < GORILLA_RELEASE:
		Body.animate(g, 0.0, 0.0)
		return []
	if _gorilla_rest > 0.0:
		_gorilla_rest -= dt
		var arms := [g.get_node("Bob/Arm0"), g.get_node("Bob/Arm2")]
		for a in arms:
			(a as Node3D).rotation.x = -1.2 + sin(t * 18.0) * 0.6
		return []
	for a in [g.get_node("Bob/Arm0"), g.get_node("Bob/Arm2")]:
		(a as Node3D).rotation.x = 0.0
	var target := Vector3.INF
	var best := INF
	for p in people:
		if not p.out:
			continue
		var d: float = g.position.distance_to(p.pos)
		if d < best:
			best = d
			target = p.pos
	if not spooked.is_empty():
		target = spooked.pos
	if target == Vector3.INF:
		target = Vector3(0, 0, -13.5)
	target.z = minf(target.z, -0.8)
	_gorilla_repath -= dt
	if _gorilla_repath <= 0.0 and nav_map.is_valid():
		_gorilla_repath = 0.4
		_gorilla_path = NavigationServer3D.map_get_path(nav_map, g.position, target, true)
	var step := target
	while _gorilla_path.size() > 0 and Vector2(_gorilla_path[0].x - g.position.x, _gorilla_path[0].z - g.position.z).length() < 0.3:
		_gorilla_path.remove_at(0)
	if _gorilla_path.size() > 0:
		step = _gorilla_path[0]
	var dir := step - g.position
	dir.y = 0
	if dir.length() > 0.05:
		dir = dir.normalized()
		g.position += dir * GORILLA_SPEED * (1.35 if not spooked.is_empty() else 1.0) * dt
		g.rotation.y = lerp_angle(g.rotation.y, atan2(-dir.x, -dir.z), 0.2)
	g.position.y = 0.0
	g.position.z = minf(g.position.z, -0.8)
	Body.animate(g, GORILLA_SPEED, t * 7.0)
	var hits := []
	for p in people:
		if not p.out or _cool.get(p.id, 0.0) > 0.0:
			continue
		var d: Vector3 = p.pos - g.position
		d.y = 0
		if d.length() < 1.3:
			_cool[p.id] = 2.0
			_gorilla_rest = 1.3
			hits.append({"id": p.id, "impulse": d.normalized() * 11.0 + Vector3.UP * 4.0, "stun": 0.9, "drop": 1, "sound": "slam"})
	return hits


## What the host sends about the hazard, and how everyone else applies it.
func npc_state() -> Array:
	var out := []
	for n in npcs:
		out.append([n.position, n.rotation.y])
	return out


func apply_npc_state(state: Array) -> void:
	for i in mini(state.size(), npcs.size()):
		var n := npcs[i]
		var target: Vector3 = state[i][0]
		var moved := n.position.distance_to(target)
		n.position = target
		n.rotation.y = state[i][1]
		_npc_vel[i] = Vector3.ONE * moved
		Body.animate(n, clampf(moved * 20.0, 0.0, 4.0), Time.get_ticks_msec() / 110.0 + i)


func _process(dt: float) -> void:
	if _disco:
		var s := Time.get_ticks_msec() / 1000.0
		_disco.position = Vector3(sin(s * 1.7) * 3.0, 3.0, -9.0 + cos(s * 1.3) * 3.0)
		_disco.light_color = Color.from_hsv(fposmod(s / 2.5, 1.0), 0.8, 1.0)
	for i in _fires.size():
		var f := _fires[i]
		f.visible = i < stage
		if f.visible:
			f.scale.y = 1.0 + sin(Time.get_ticks_msec() / 70.0 + i) * 0.12
