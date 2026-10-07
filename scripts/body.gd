class_name Body
extends RefCounted

## Low-poly people: a bean body, a round head, two eyes. Facing is -Z.

const SKINS := [Color("f1c7a5"), Color("d9a27c"), Color("a8714f"), Color("6e4630"), Color("f4d9c4")]


static func person(color: Color, skin: Color, hat := Color(0, 0, 0, 0)) -> Node3D:
	var root := Node3D.new()
	var bob := Node3D.new()
	bob.name = "Bob"
	root.add_child(bob)
	var cloth := Build.mat(color, 0.7)
	var torso := CapsuleMesh.new()
	torso.radius = 0.32
	torso.height = 1.05
	torso.radial_segments = 12
	torso.rings = 4
	Build.mesh(bob, torso, Vector3(0, 0.62, 0), cloth).name = "Torso"
	var head := Build.mesh(bob, Build.sphere_mesh(0.24), Vector3(0, 1.38, 0), Build.mat(skin, 0.75))
	head.name = "Head"
	var eye := Build.mat(Color("15130f"), 0.4)
	Build.mesh(head, Build.sphere_mesh(0.045), Vector3(-0.08, 0.04, -0.21), eye)
	Build.mesh(head, Build.sphere_mesh(0.045), Vector3(0.08, 0.04, -0.21), eye)
	Build.mesh(bob, Build.box_mesh(Vector3(0.5, 0.1, 0.06)), Vector3(0, 0.95, -0.29), Build.mat(color.darkened(0.25), 0.7))
	for side in [-1, 1]:
		Build.mesh(bob, Build.box_mesh(Vector3(0.16, 0.1, 0.26)), Vector3(0.13 * side, 0.05, -0.03), Build.mat(Color("2a2522"), 0.8))
	if hat.a > 0.0:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.14
		cone.height = 0.34
		cone.radial_segments = 10
		Build.mesh(head, cone, Vector3(0.04, 0.3, 0), Build.mat(hat, 0.6), Vector3(0, 0, -0.25))
	return root


static func gorilla() -> Node3D:
	var root := Node3D.new()
	var bob := Node3D.new()
	bob.name = "Bob"
	root.add_child(bob)
	var fur := Build.mat(Color("2b2622"), 0.95)
	var face := Build.mat(Color("5a4a40"), 0.8)
	Build.mesh(bob, Build.box_mesh(Vector3(1.2, 1.1, 0.8)), Vector3(0, 1.2, 0.1), fur)
	Build.mesh(bob, Build.box_mesh(Vector3(0.9, 0.6, 0.6)), Vector3(0, 0.5, 0.15), fur)
	var head := Build.mesh(bob, Build.box_mesh(Vector3(0.6, 0.55, 0.55)), Vector3(0, 1.9, -0.2), fur)
	head.name = "Head"
	Build.mesh(head, Build.box_mesh(Vector3(0.42, 0.3, 0.1)), Vector3(0, -0.06, -0.28), face)
	var eye := Build.mat(Color("f0e6cc"), 0.3, 0.0, 0.4)
	Build.mesh(head, Build.sphere_mesh(0.05), Vector3(-0.12, 0.1, -0.29), eye)
	Build.mesh(head, Build.sphere_mesh(0.05), Vector3(0.12, 0.1, -0.29), eye)
	for side in [-1, 1]:
		var arm := Build.mesh(bob, Build.box_mesh(Vector3(0.32, 1.4, 0.32)), Vector3(0.78 * side, 0.85, -0.1), fur)
		arm.name = "Arm%d" % (side + 1)
	return root


## A ghost: a pale sheet with a round top, two dark eyes and a ragged hem, tinted with the
## colour its player wore. Unshaded and see-through so it reads in any light.
static func ghost(tint: Color) -> Node3D:
	var root := Node3D.new()
	root.scale = Vector3.ONE * 0.75
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.92, 1.0, 0.42).lerp(Color(tint, 0.42), 0.35)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = m.albedo_color
	m.emission_energy_multiplier = 0.6
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	root.set_meta("mat", m)
	var sheet := CylinderMesh.new()
	sheet.top_radius = 0.3
	sheet.bottom_radius = 0.42
	sheet.height = 0.8
	sheet.radial_segments = 12
	Build.mesh(root, sheet, Vector3(0, 0.4, 0), m)
	Build.mesh(root, Build.sphere_mesh(0.3), Vector3(0, 0.8, 0), m)
	for i in 6:  # the ragged hem
		var a := i * TAU / 6.0
		var cone := CylinderMesh.new()
		cone.top_radius = 0.1
		cone.bottom_radius = 0.0
		cone.height = 0.22
		cone.radial_segments = 5
		Build.mesh(root, cone, Vector3(cos(a) * 0.32, -0.1, sin(a) * 0.32), m)
	var eye := Build.mat(Color("101418"), 0.5)
	for x in [-0.1, 0.1]:
		Build.mesh(root, Build.sphere_mesh(0.06, 0.1), Vector3(x, 0.86, -0.26), eye)
	return root


static func ghost_glow(g: Node3D, energy: float) -> void:
	var m := g.get_meta("mat") as StandardMaterial3D
	if m:
		m.emission_energy_multiplier = lerpf(m.emission_energy_multiplier, energy, 0.1)


## Walk cycle on a body made above: bob and waddle by distance travelled.
static func animate(body: Node3D, speed: float, phase: float) -> void:
	var bob := body.get_node_or_null("Bob") as Node3D
	if bob == null:
		return
	var amt := clampf(speed / 5.0, 0.0, 1.2)
	bob.position.y = absf(sin(phase)) * 0.09 * amt
	bob.rotation.z = sin(phase) * 0.09 * amt
	bob.rotation.x = -0.12 * amt
