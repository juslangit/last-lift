extends Node

## The front door: the menu, then a Game once you are hosting or connected.
## Command line (after --):  --host  --join=IP  --name=X  --bots=N  --autostart[=humans]
##                           --autopilot  --rounds=N  --quit  --rooms=office,fire,zoo  --log

var game: Game
var menu: Control
var _status: Label
var _name: LineEdit
var _ip: LineEdit
var _bots_label: Label
var _backdrop: Node3D


func _ready() -> void:
	name = "Main"
	_inputs()
	Net.joined.connect(_start_game)
	Net.failed.connect(_on_failed)
	if Net.opts.has("shots"):
		add_child(load("res://dev/looks/shots.gd").new())
	if Net.flag("host"):
		var err := Net.host()
		if err != "":
			push_error(err)
			get_tree().quit(1)
			return
		_start_game()
	elif Net.flag("join"):
		var err := Net.join(str(Net.opts["join"]))
		if err != "":
			push_error(err)
			get_tree().quit(1)
	else:
		_show_menu("")


func _inputs() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"run": [KEY_SHIFT], "jump": [KEY_SPACE], "interact": [KEY_E], "drop": [KEY_Q],
		"pause": [KEY_ESCAPE], "start": [KEY_ENTER, KEY_KP_ENTER],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	if not InputMap.has_action("shove"):
		InputMap.add_action("shove")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("shove", mb)


func _start_game() -> void:
	_clear_menu()
	game = Game.new()
	game.left_game.connect(_on_left)
	add_child(game)


func _on_left(reason: String) -> void:
	_show_menu(reason)


func _on_failed(reason: String) -> void:
	if Net.flag("quit"):
		print("[peer] %s" % reason)
		get_tree().quit()
		return
	_show_menu(reason)


func _clear_menu() -> void:
	if menu:
		menu.queue_free()
		menu = null
	if _backdrop:
		_backdrop.queue_free()
		_backdrop = null


func _show_menu(message: String) -> void:
	if game:
		game.queue_free()
		game = null
	_clear_menu()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# behind the menu: the cab at floor 40, doors shut, lights flickering
	_backdrop = Node3D.new()
	add_child(_backdrop)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("0a0806")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("ffe0b8")
	env.environment.ambient_light_energy = 0.3
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment.glow_enabled = true
	_backdrop.add_child(env)
	var cab := Cab.new()
	_backdrop.add_child(cab)
	cab.flicker = 0.15
	var cam := Camera3D.new()
	cam.fov = 62
	_backdrop.add_child(cam)
	cam.position = Vector3(-1.2, 1.55, 3.7)
	cam.look_at(Vector3(0.35, 1.35, 0.0))
	cam.current = true

	menu = Control.new()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.theme = UI.theme()
	add_child(menu)
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.02, 0.01, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(shade)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	menu.add_child(col)
	col.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT, Control.PRESET_MODE_MINSIZE, 120)
	col.custom_minimum_size = Vector2(700, 0)
	col.position.y -= 330
	col.add_child(UI.shadowed(UI.label("LAST", 150, UI.INK, UI.display)))
	var lift := UI.shadowed(UI.label("LIFT", 150, UI.BRASS, UI.display))
	lift.add_theme_constant_override("line_spacing", -40)
	col.add_child(lift)
	col.add_child(UI.shadowed(UI.label("The building is falling. The doors open for fourteen seconds.", 28, UI.INK, UI.bold)))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	col.add_child(spacer)
	_name = LineEdit.new()
	_name.placeholder_text = "Your name"
	_name.text = Net.my_name if Net.my_name != "Player" else ""
	_name.max_length = 16
	col.add_child(_name)
	var host_row := HBoxContainer.new()
	host_row.add_theme_constant_override("separation", 12)
	host_row.add_child(UI.button("Host a game", _on_host))
	host_row.add_child(UI.button(" − ", func(): _set_bots(Net.bots - 1)))
	_bots_label = UI.label("", 26, UI.INK, UI.bold)
	_bots_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	host_row.add_child(_bots_label)
	host_row.add_child(UI.button(" + ", func(): _set_bots(Net.bots + 1)))
	col.add_child(host_row)
	_set_bots(Net.bots)
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 12)
	_ip = LineEdit.new()
	_ip.placeholder_text = "Host's IP address, e.g. 192.168.1.20"
	_ip.custom_minimum_size = Vector2(520, 0)
	join_row.add_child(_ip)
	join_row.add_child(UI.button("Join", _on_join))
	col.add_child(join_row)
	col.add_child(UI.button("Quit", func(): get_tree().quit()))
	_status = UI.shadowed(UI.label(message, 26, UI.LED, UI.bold))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status)


func _set_bots(n: int) -> void:
	Net.bots = clampi(n, 0, Rules.MAX_PLAYERS - 1)
	_bots_label.text = "%d bots" % Net.bots


func _take_name() -> void:
	var n := _name.text.strip_edges()
	Net.my_name = n if n != "" else "Player"


func _on_host() -> void:
	_take_name()
	var err := Net.host()
	if err != "":
		_status.text = err
		return
	_start_game()


func _on_join() -> void:
	_take_name()
	if _ip.text.strip_edges() == "":
		_status.text = "Type the host's IP address first. The host sees it in their lobby."
		return
	var err := Net.join(_ip.text)
	if err != "":
		_status.text = err
		return
	_status.text = "Connecting to %s…" % _ip.text.strip_edges()
