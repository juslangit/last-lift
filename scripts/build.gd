class_name Build
extends RefCounted

## Small helpers for putting low-poly geometry together in code.
## Collision layers: 1 world, 2 players, 3 (value 4) doors, 4 (value 8) NPCs.

const WORLD := 1
const PLAYERS := 2
const DOORS := 4
const NPCS := 8
const NAV_ONLY := 16   # invisible blockers only the navmesh bake sees (stops desk tops being "floor")

static var _mats := {}


static func mat(color: Color, rough := 0.8, metal := 0.0, glow := 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f|%.2f" % [color.to_html(), rough, metal, glow]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	_mats[key] = m
	return m


static func mesh(parent: Node, m: Mesh, pos: Vector3, material: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func box_mesh(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func cyl_mesh(radius: float, height: float, sides := 12) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = sides
	c.rings = 1
	return c


static func sphere_mesh(radius: float, height := -1.0) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0 if height < 0 else height
	s.radial_segments = 12
	s.rings = 6
	return s


## A visible box. With solid = true it also gets a static collider on `layer`.
static func box(parent: Node, size: Vector3, pos: Vector3, material: Material, solid := true, layer := WORLD) -> Node3D:
	if not solid:
		return mesh(parent, box_mesh(size), pos, material)
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = layer
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	mesh(body, box_mesh(size), Vector3.ZERO, material)
	parent.add_child(body)
	return body


## Tell the navmesh a block is solid to the ceiling, without stopping anyone jumping on it.
static func nav_block(parent: Node, size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos + Vector3(0, 1.5, 0)
	body.collision_layer = NAV_ONLY
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(size.x, size.y + 3.0, size.z)
	shape.shape = bs
	body.add_child(shape)
	parent.add_child(body)


static func cyl(parent: Node, radius: float, height: float, pos: Vector3, material: Material, solid := true) -> Node3D:
	if not solid:
		return mesh(parent, cyl_mesh(radius, height), pos, material)
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = WORLD
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var cs := CylinderShape3D.new()
	cs.radius = radius
	cs.height = height
	shape.shape = cs
	body.add_child(shape)
	mesh(body, cyl_mesh(radius, height), Vector3.ZERO, material)
	parent.add_child(body)
	return body


static func label(parent: Node, text: String, pos: Vector3, size := 64, color := Color.WHITE, font: Font = null) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.font_size = size
	l.modulate = color
	l.outline_size = 0
	l.pixel_size = 0.005
	if font:
		l.font = font
	parent.add_child(l)
	return l


static func light(parent: Node, pos: Vector3, color: Color, energy: float, range_m: float, shadow := false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = range_m
	l.shadow_enabled = shadow
	parent.add_child(l)
	return l


## A wall along x or z with a rectangular doorway cut out of it, as up to three boxes.
static func wall_with_hole(parent: Node, from_x: float, to_x: float, z: float, height: float,
		hole_half: float, hole_h: float, thick: float, material: Material) -> void:
	var left := -hole_half - from_x
	if left > 0.01:
		box(parent, Vector3(left, height, thick), Vector3(from_x + left / 2.0, height / 2.0, z), material)
	var right := to_x - hole_half
	if right > 0.01:
		box(parent, Vector3(right, height, thick), Vector3(hole_half + right / 2.0, height / 2.0, z), material)
	if height > hole_h:
		box(parent, Vector3(hole_half * 2.0, height - hole_h, thick),
			Vector3(0, hole_h + (height - hole_h) / 2.0, z), material)


static func loot_mesh(kind: String) -> Mesh:
	var d: Array = Rules.LOOT[kind]
	var size: Vector3 = d[5]
	match d[3]:
		"cyl":
			return cyl_mesh(size.x / 2.0, size.y)
		"sphere":
			return sphere_mesh(size.x / 2.0, size.y)
		_:
			return box_mesh(size)
