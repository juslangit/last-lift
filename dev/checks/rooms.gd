extends SceneTree

## Every room, many seeds: built the same way twice, enough loot spots, and every loot spot
## reachable on foot from inside the cab (the navmesh path really ends next to it).
##   Godot --headless --path . -s dev/checks/rooms.gd

var passes := 0
var failures := 0


func check(label: String, ok: bool) -> void:
	if ok:
		passes += 1
	else:
		failures += 1
		print("  FAIL  " + label)


func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 30:
		check("floor plan %d has 3 to 7 stops, all falling" % i, _plan_ok(Rules.floor_plan(rng)))
	check("inside: middle of the cab", Rules.inside_cab(Vector3(0, 0, 2)))
	check("outside: on the landing", not Rules.inside_cab(Vector3(0, 0, -0.5)))
	check("outside: standing in the door line", not Rules.inside_cab(Vector3(0, 0, 0.1)))
	check("heavy loot slows you, never below 45%", Rules.speed_factor(45.0) < 0.5 and Rules.speed_factor(500.0) >= 0.45)
	check("snap drops half, rounded up", Rules.snap_drops(0) == 0 and Rules.snap_drops(1) == 1
		and Rules.snap_drops(2) == 1 and Rules.snap_drops(3) == 2)
	check("no rail in the middle of the cab", not Rules.can_hold_rail(Vector3(0, 0, 2)))
	check("rail reachable against the left wall", Rules.can_hold_rail(Vector3(-1.6, 0, 2)))
	check("rail reachable against the back wall", Rules.can_hold_rail(Vector3(0.3, 0, 3.6)))
	check("no rail outside the cab", not Rules.can_hold_rail(Vector3(-1.6, 0, -0.5)))
	for i in 40:
		var spot := Vector3(rng.randf_range(-1.6, 1.6), 0, rng.randf_range(0.4, 3.6))
		check("rail spot from %s can be held" % spot, Rules.can_hold_rail(Rules.rail_spot(spot)))
	for room in Rules.ROOMS:
		check("%s has a name and a hazard line" % room, Rules.ROOM_NAMES.has(room) and Rules.ROOM_HAZARDS.has(room))
		for k in Rules.ROOM_LOOT[room]:
			check("%s loot %s is in the catalogue" % [room, k], Rules.LOOT.has(k))
	_rooms.call_deferred()


func _plan_ok(stops: Array[int]) -> bool:
	if stops.size() < 3 or stops.size() > 7:
		return false
	var last := Rules.START_FLOOR
	for s in stops:
		if s >= last or s <= 0:
			return false
		last = s
	return true


func _rooms() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var cab := Cab.new()
	world.add_child(cab)
	var region := NavigationRegion3D.new()
	world.add_child(region)
	var map := world.get_world_3d().navigation_map
	for i in 10:  # let the new world's navigation map come up
		await physics_frame
	for kind in Rules.ROOMS:
		for s in [1, 2, 3, 42, 99, 1234]:
			var a := Room.create(kind, s)
			var b := Room.create(kind, s)
			check("%s seed %d builds identically" % [kind, s], a.loot_points == b.loot_points)
			check("%s seed %d has at least 10 loot spots" % [kind, s], a.loot_points.size() >= 10)
			b.free()
			world.add_child(a)
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
			var before := NavigationServer3D.map_get_iteration_id(map)
			region.navigation_mesh = nm
			for f in 30:
				await physics_frame
				if NavigationServer3D.map_get_iteration_id(map) != before and f > 3:
					break
			for pt in a.loot_points:
				var path := NavigationServer3D.map_get_path(map, Vector3(0, 0, 2.5), Vector3(pt.x, 0, pt.z), true)
				var end := path[path.size() - 1] if path.size() > 0 else Vector3.INF
				var reach := Vector2(end.x - pt.x, end.z - pt.z).length() if end != Vector3.INF else INF
				check("%s seed %d: loot at %s reachable from the cab (gap %.2f m)" % [kind, s, pt, reach],
					reach < Rules.PICKUP_RANGE - 0.4)
			world.remove_child(a)
			a.free()
	print("%d passed, %d failed" % [passes, failures])
	quit(1 if failures > 0 else 0)
