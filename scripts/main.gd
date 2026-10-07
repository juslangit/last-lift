extends Node

## The front door: the menu, then a Game once you are hosting or connected.
## Two ways in: Quickplay (Steam finds a lobby with other people, or opens one) and
## Play with friends (a 4-digit room code or a Steam invite; same-Wi-Fi by IP as a fallback).
## Command line (after --):  --host  --join=IP  --name=X  --bots=N  --autostart[=humans]
##                           --autopilot  --rounds=N  --quit  --rooms=office,fire,zoo  --log  --nosteam
##                           --snap=always|never
##                           --quickplay  --room  --code=1234   (press that menu button on start)

var game: Game
var menu: Control
var _status: Label
var _name: LineEdit
var _bots_label: Label
var _backdrop: Node3D
var _page: VBoxContainer
var _busy := false


func _ready() -> void:
	name = "Main"
	add_to_group("main")
	_inputs()
	Net.joined.connect(_start_game)
	Net.failed.connect(_on_failed)
	Lobby.hosting.connect(_start_game)
	Lobby.failed.connect(_on_failed)
	Lobby.status.connect(func(t): _say(t, UI.INK))
	if Net.opts.has("shots"):
		add_child(load("res://dev/looks/shots.gd").new())
	if Net.opts.has("probe"):  # a check that drives a real game: dev/checks/<name>.gd
		add_child(load("res://dev/checks/%s.gd" % Net.opts["probe"]).new())
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
		# test hooks: --quickplay, --room, --code=1234 press the matching menu button
		if Net.flag("quickplay"):
			_on_quickplay.call_deferred()
		elif Net.flag("room"):
			_on_create_room.call_deferred()
		elif Net.opts.has("code"):
			_on_join_code.call_deferred(str(Net.opts["code"]))


func _inputs() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"run": [KEY_SHIFT], "jump": [KEY_SPACE], "interact": [KEY_E], "drop": [KEY_Q],
		"pause": [KEY_ESCAPE], "start": [KEY_ENTER, KEY_KP_ENTER],
		"ghost_lights": [KEY_1], "ghost_button": [KEY_2], "ghost_spook": [KEY_3], "haunt_next": [KEY_TAB],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	for pair in [["shove", MOUSE_BUTTON_LEFT], ["haunt_prev", MOUSE_BUTTON_RIGHT]]:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0])
			var mb := InputEventMouseButton.new()
			mb.button_index = pair[1]
			InputMap.action_add_event(pair[0], mb)


func _start_game() -> void:
	_busy = false
	_clear_menu()
	game = Game.new()
	game.left_game.connect(_on_left)
	add_child(game)


func _on_left(reason: String) -> void:
	_show_menu(reason)


func _on_failed(reason: String) -> void:
	_busy = false
	if Net.flag("quit"):
		print("[peer] %s" % reason)
		get_tree().quit()
		return
	if game:
		_show_menu(reason)
	else:
		_say(reason, UI.LED)


## A Steam invite was accepted mid-match: drop this match quietly so the new one can start.
func leave_for_invite() -> void:
	if game:
		game.left_game.disconnect(_on_left)
		game._leave("")
		game.queue_free()
		game = null
		_show_menu("Joining your friend's room…")


# --- the menu ----------------------------------------------------------------------------

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
	_busy = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_backdrop()
	menu = Control.new()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.theme = UI.theme()
	add_child(menu)
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.02, 0.01, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(shade)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	menu.add_child(col)
	col.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	col.offset_left = 120
	col.offset_right = 900
	col.offset_top = -470
	col.offset_bottom = 470
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(UI.shadowed(UI.label("LAST", 140, UI.INK, UI.display)))
	var lift := UI.shadowed(UI.label("LIFT", 140, UI.BRASS, UI.display))
	col.add_child(lift)
	col.add_child(UI.shadowed(UI.label("The building is falling. The doors open for fourteen seconds.", 28, UI.INK, UI.bold)))
	_name = LineEdit.new()
	_name.placeholder_text = "Your name"
	var default_name := Net.my_name if Net.my_name != "Player" else Lobby.user_name
	_name.text = default_name
	_name.max_length = 16
	_name.custom_minimum_size = Vector2(0, 58)
	col.add_child(_name)
	_page = VBoxContainer.new()
	_page.add_theme_constant_override("separation", 14)
	col.add_child(_page)
	_status = UI.shadowed(UI.label("", 26, UI.LED, UI.bold))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(780, 0)
	col.add_child(_status)
	_home_page()
	if message != "":
		_say(message, UI.LED)
	elif not Lobby.ok:
		_say("Steam: %s Quickplay and room codes need it." % Lobby.why_not, UI.MUTED)
	else:
		_say("Signed in to Steam as %s." % Lobby.user_name, UI.MUTED)


func _build_backdrop() -> void:
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


func _clear_page() -> void:
	for c in _page.get_children():
		c.queue_free()


func _big_button(title: String, sub: String, cb: Callable, accent := false) -> Button:
	var b := UI.button("", cb)
	b.custom_minimum_size = Vector2(780, 104)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 0)
	v.offset_left = 26
	v.offset_top = 12
	v.add_theme_constant_override("separation", 0)
	var t := UI.label(title, 40, UI.LED if accent else UI.INK, UI.display)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := UI.label(sub, 22, UI.MUTED, UI.semi)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	v.add_child(s)
	b.add_child(v)
	return b


func _home_page() -> void:
	_clear_page()
	var quick := _big_button("QUICKPLAY", "Jump into a lobby with other players", _on_quickplay, true)
	quick.name = "Quickplay"
	_page.add_child(quick)
	_page.add_child(_big_button("PLAY WITH FRIENDS", "Make a room with a 4-digit code, or invite Steam friends", _friends_page))
	var quit := UI.button("Quit", func(): get_tree().quit())
	quit.custom_minimum_size = Vector2(780, 0)
	_page.add_child(quit)


func _friends_page() -> void:
	_clear_page()
	_page.add_child(UI.shadowed(UI.label("PLAY WITH FRIENDS", 44, UI.LED, UI.display)))
	var make := HBoxContainer.new()
	make.add_theme_constant_override("separation", 12)
	var create := UI.button("Make a room", _on_create_room)
	create.custom_minimum_size = Vector2(320, 64)
	make.add_child(create)
	make.add_child(UI.button(" − ", func(): _set_bots(Net.bots - 1)))
	_bots_label = UI.label("", 26, UI.INK, UI.bold)
	_bots_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	make.add_child(_bots_label)
	make.add_child(UI.button(" + ", func(): _set_bots(Net.bots + 1)))
	_page.add_child(make)
	_set_bots(Net.bots)
	_page.add_child(UI.label("You get a 4-digit code to give your friends, and can invite Steam friends from the lobby.", 22, UI.MUTED))
	var join := HBoxContainer.new()
	join.add_theme_constant_override("separation", 12)
	var code := LineEdit.new()
	code.name = "Code"
	code.placeholder_text = "Room code"
	code.max_length = 4
	code.custom_minimum_size = Vector2(320, 64)
	code.add_theme_font_size_override("font_size", 38)
	code.text_submitted.connect(func(t): _on_join_code(t))
	join.add_child(code)
	var jb := UI.button("Join room", func(): _on_join_code(code.text))
	jb.custom_minimum_size = Vector2(220, 64)
	join.add_child(jb)
	_page.add_child(join)
	_page.add_child(UI.label("Got a Steam invite? Accept it in Steam and you'll join automatically.", 22, UI.MUTED))
	# same Wi-Fi without Steam
	var lan := HBoxContainer.new()
	lan.add_theme_constant_override("separation", 10)
	lan.add_child(UI.label("No Steam, same Wi-Fi:", 22, UI.MUTED))
	lan.add_child(UI.button("Host", _on_host_lan))
	var ip := LineEdit.new()
	ip.placeholder_text = "Host's IP"
	ip.custom_minimum_size = Vector2(230, 0)
	lan.add_child(ip)
	lan.add_child(UI.button("Join", func(): _on_join_lan(ip.text)))
	_page.add_child(lan)
	var back := UI.button("Back", _home_page)
	back.custom_minimum_size = Vector2(200, 0)
	_page.add_child(back)


func _set_bots(n: int) -> void:
	Net.bots = clampi(n, 0, Rules.MAX_PLAYERS - 1)
	if _bots_label:
		_bots_label.text = "%d bots" % Net.bots


func _say(text: String, color: Color) -> void:
	if _status:
		_status.text = text
		_status.add_theme_color_override("font_color", color)


func _take_name() -> void:
	var n := _name.text.strip_edges()
	Net.my_name = n if n != "" else (Lobby.user_name if Lobby.user_name != "" else "Player")


func _guard() -> bool:
	if _busy:
		return false
	_take_name()
	_busy = true
	return true


func _on_quickplay() -> void:
	if not _guard():
		return
	Net.bots = Rules.FULL_CAB - 1  # bots keep the cab full; people take their places as they arrive
	Lobby.quickplay()


func _on_create_room() -> void:
	if not _guard():
		return
	Lobby.create_room()


func _on_join_code(c: String) -> void:
	if not _guard():
		return
	Lobby.join_code(c)


func _on_host_lan() -> void:
	if not _guard():
		return
	var err := Net.host()
	if err != "":
		_on_failed(err)
		return
	_start_game()


func _on_join_lan(ip: String) -> void:
	if ip.strip_edges() == "":
		_say("Type the host's IP address first. The host sees it in their lobby.", UI.LED)
		return
	if not _guard():
		return
	var err := Net.join(ip)
	if err != "":
		_on_failed(err)
		return
	_say("Connecting to %s…" % ip.strip_edges(), UI.INK)
