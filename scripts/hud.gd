class_name Hud
extends CanvasLayer

## Everything drawn over the 3D view: the floor display, the door clock, the cab's load,
## your three hands' worth of loot, and the lobby, results and pause panels.

signal start_pressed
signal bots_changed(delta: int)
signal leave_pressed

var game: Game
var paused := false

var _root: Control
var _floor: Label
var _room: Label
var _hazard: Label
var _doors: Label
var _riding: Label
var _haul: Label
var _round: Label
var _load_label: Label
var _load_fill: ColorRect
var _slots: Array[Label] = []
var _slot_boxes: Array[PanelContainer] = []
var _prompt: Label
var _cross: Control
var _feed: VBoxContainer
var _big: VBoxContainer
var _big_title: Label
var _big_sub: Label
var _big_t := 0.0
var _flash: ColorRect
var _lobby: PanelContainer
var _lobby_list: GridContainer
var _lobby_host: VBoxContainer
var _lobby_wait: Label
var _room_title: Label
var _room_sub: Label
var _invite: Button
var _lobby_count: Label
var _results_count: Label
var _results: PanelContainer
var _results_grid: GridContainer
var _results_title: Label
var _next_btn: Button
var _pause: PanelContainer
var _spectate: Label
var _last_tick := -1
var _hands: VBoxContainer
var _ghost: PanelContainer
var _ghost_who: Label
var _ghost_powers: Array[Label] = []
var _ghost_msg: Label
var _ghost_msg_t := 0.0
var _ghost_pts: Label


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UI.theme()
	add_child(_root)
	_build_top()
	_build_bottom()
	_build_center()
	_build_lobby()
	_build_results()
	_build_pause()
	_build_ghost()


func _place(c: Control, preset: Control.LayoutPreset, offset := Vector2.ZERO) -> Control:
	_root.add_child(c)
	c.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, 28)
	c.position += offset
	return c


## Anchor a control to a preset and size it with offsets (position alone ignores anchors).
func _anchor(c: Control, preset: Control.LayoutPreset, left: float, top: float, right: float, bottom: float) -> void:
	if c.get_parent() == null:
		_root.add_child(c)
	c.set_anchors_preset(preset)
	c.offset_left = left
	c.offset_top = top
	c.offset_right = right
	c.offset_bottom = bottom


func _build_top() -> void:
	var tl := UI.panel()
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -4)
	tl.add_child(v)
	v.add_child(UI.label("FLOOR", 22, UI.BRASS, UI.bold))
	_floor = UI.label("40", 96, UI.LED, UI.bold)
	v.add_child(_floor)
	_room = UI.label("", 28, UI.INK, UI.bold)
	v.add_child(_room)
	_hazard = UI.label("", 22, UI.MUTED)
	v.add_child(_hazard)
	_place(tl, Control.PRESET_TOP_LEFT)

	_doors = UI.shadowed(UI.label("", 50, UI.INK, UI.bold))  # Bungee's 7 reads as "?"
	_doors.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor(_doors, Control.PRESET_CENTER_TOP, -600, 30, 600, 90)
	_spectate = UI.shadowed(UI.label("CAM 01   ● REC", 30, UI.DANGER, UI.bold))
	_spectate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor(_spectate, Control.PRESET_CENTER_TOP, -600, 96, 600, 136)
	_spectate.visible = false

	var tr := VBoxContainer.new()
	tr.alignment = BoxContainer.ALIGNMENT_BEGIN
	_riding = UI.shadowed(UI.label("", 34, UI.INK, UI.bold))
	_haul = UI.shadowed(UI.label("", 34, UI.BRASS, UI.bold))
	_round = UI.shadowed(UI.label("", 24, UI.MUTED, UI.semi))
	for l in [_riding, _haul, _round]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		tr.add_child(l)
	tr.custom_minimum_size = Vector2(420, 0)
	_place(tr, Control.PRESET_TOP_RIGHT)

	_feed = VBoxContainer.new()
	_feed.alignment = BoxContainer.ALIGNMENT_END
	_feed.custom_minimum_size = Vector2(620, 300)
	_anchor(_feed, Control.PRESET_CENTER_RIGHT, -650, -160, -30, 140)


func _build_bottom() -> void:
	var bl := VBoxContainer.new()
	_load_label = UI.shadowed(UI.label("CAB LOAD", 26, UI.INK, UI.bold))
	bl.add_child(_load_label)
	var bar := ColorRect.new()
	bar.color = Color(0, 0, 0, 0.55)
	bar.custom_minimum_size = Vector2(380, 18)
	_load_fill = ColorRect.new()
	_load_fill.color = UI.BRASS
	_load_fill.size = Vector2(0, 18)
	bar.add_child(_load_fill)
	bl.add_child(bar)
	_place(bl, Control.PRESET_BOTTOM_LEFT)

	var br := VBoxContainer.new()
	_hands = br
	br.alignment = BoxContainer.ALIGNMENT_END
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_END
	for i in Rules.SLOTS:
		var box := UI.panel()
		box.custom_minimum_size = Vector2(170, 104)
		var l := UI.label("", 20, UI.INK, UI.bold)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(l)
		row.add_child(box)
		_slots.append(l)
		_slot_boxes.append(box)
	br.add_child(row)
	var keys := UI.shadowed(UI.label("WASD move · Shift run · Space jump · E grab · Q drop · Click shove · Esc menu", 20, UI.MUTED))
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	br.add_child(keys)
	_place(br, Control.PRESET_BOTTOM_RIGHT)


func _build_center() -> void:
	_cross = Control.new()
	var dot := ColorRect.new()
	dot.color = Color(1, 1, 1, 0.75)
	dot.size = Vector2(6, 6)
	dot.position = Vector2(-3, -3)
	_cross.add_child(dot)
	_anchor(_cross, Control.PRESET_CENTER, 0, 0, 0, 0)

	_prompt = UI.shadowed(UI.label("", 32, UI.INK, UI.bold))
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor(_prompt, Control.PRESET_CENTER_BOTTOM, -700, -240, 700, -190)

	_big = VBoxContainer.new()
	_big.alignment = BoxContainer.ALIGNMENT_CENTER
	_big_title = UI.shadowed(UI.label("", 104, UI.LED, UI.display))
	_big_sub = UI.shadowed(UI.label("", 32, UI.INK, UI.bold))
	for l in [_big_title, _big_sub]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_big.add_child(l)
	_anchor(_big, Control.PRESET_CENTER, -800, -300, 800, 0)
	_big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_big.modulate.a = 0.0

	_flash = ColorRect.new()
	_flash.color = Color(1, 0.95, 0.85, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_flash)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)


func _build_lobby() -> void:
	_lobby = UI.panel()
	_lobby.custom_minimum_size = Vector2(620, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_lobby.add_child(v)
	_room_title = UI.label("THE LOBBY", 50, UI.LED, UI.bold)  # room codes must read clearly
	v.add_child(_room_title)
	_room_sub = UI.label("Everyone in the cab. Floor 40.", 24, UI.MUTED)
	_room_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_room_sub)
	_invite = UI.button("Invite Steam friends", func():
		var said := Lobby.invite_friends()
		if said != "":
			feed(said))
	v.add_child(_invite)
	_lobby_count = UI.label("", 30, UI.INK, UI.bold)
	v.add_child(_lobby_count)
	_lobby_list = GridContainer.new()
	_lobby_list.columns = 2
	_lobby_list.add_theme_constant_override("h_separation", 24)
	_lobby_list.add_theme_constant_override("v_separation", 2)
	v.add_child(_lobby_list)
	_lobby_host = VBoxContainer.new()
	_lobby_host.add_theme_constant_override("separation", 10)
	v.add_child(_lobby_host)
	var bots := HBoxContainer.new()
	bots.add_theme_constant_override("separation", 10)
	bots.add_child(UI.label("Bots", 28, UI.INK, UI.bold))
	bots.add_child(UI.button("  −  ", func(): bots_changed.emit(-1)))
	bots.add_child(UI.button("  +  ", func(): bots_changed.emit(1)))
	_lobby_host.add_child(bots)
	_lobby_host.add_child(UI.button("Start now  (Enter)", func(): start_pressed.emit()))
	var addr := UI.label("", 22, UI.MUTED)
	addr.name = "Addr"
	addr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lobby_host.add_child(addr)
	_lobby_wait = UI.label("Waiting for the host to start the round.", 26, UI.MUTED)
	v.add_child(_lobby_wait)
	_root.add_child(_lobby)
	_lobby.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_lobby.position = Vector2(28, 290)  # under the floor display
	_lobby.size = Vector2(620, 0)
	_lobby.resized.connect(func(): _lobby.size.y = _lobby.get_combined_minimum_size().y)


func _build_results() -> void:
	_results = UI.panel()
	_results.custom_minimum_size = Vector2(900, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	_results.add_child(v)
	_results_title = UI.label("LOBBY!", 68, UI.LED, UI.bold)
	_results_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_results_title)
	_results_grid = GridContainer.new()
	_results_grid.columns = 4
	_results_grid.add_theme_constant_override("h_separation", 40)
	_results_grid.add_theme_constant_override("v_separation", 4)
	v.add_child(_results_grid)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	_results_count = UI.label("", 26, UI.MUTED, UI.bold)
	_results_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_results_count)
	_next_btn = UI.button("Next round  (Enter)", func(): start_pressed.emit())
	row.add_child(_next_btn)
	row.add_child(UI.button("Leave", func(): leave_pressed.emit()))
	v.add_child(row)
	_place(_results, Control.PRESET_CENTER)
	_results.visible = false


func _build_ghost() -> void:
	_ghost = UI.panel()
	_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_ghost.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 24)
	top.add_child(UI.label("GHOST", 40, Color("bfe3ff"), UI.display))
	_ghost_who = UI.label("", 32, UI.INK, UI.bold)
	_ghost_who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_ghost_who)
	v.add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	for i in 3:
		var box := UI.panel()
		box.custom_minimum_size = Vector2(300, 0)
		var l := UI.label("", 24, UI.INK, UI.bold)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(l)
		row.add_child(box)
		_ghost_powers.append(l)
	v.add_child(row)
	_ghost_msg = UI.label("", 24, UI.LED, UI.bold)
	_ghost_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_ghost_msg)
	_ghost_pts = UI.label("", 26, UI.BRASS, UI.bold)
	v.add_child(_ghost_pts)
	v.add_child(UI.label("Click or Tab: next person  ·  Right-click: back  ·  Mouse: look around", 20, UI.MUTED))
	_anchor(_ghost, Control.PRESET_CENTER_BOTTOM, -490, -300, 490, -28)
	_ghost.visible = false


## A ghost power was refused: say why, briefly, in the ghost panel.
func ghost_says(text: String) -> void:
	_ghost_msg.text = text
	_ghost_msg_t = 2.5


func _update_ghost(g: Game) -> bool:
	var lp := g.local_player()
	var on := lp != null and not lp.alive and g.haunts.has(g.me) \
		and g.phase != "lobby" and g.phase != "results"
	_ghost.visible = on
	if not on:
		return false
	var t := g.my_haunt()
	var who: String = g.info[t].name if g.info.has(t) else "nobody"
	_ghost_who.text = "Haunting  %s" % who.to_upper()
	var target_in := t != 0 and Rules.inside_cab(g.players[t].position)
	var states := []
	var cd: float = g.ghost_cd.get("lights", 0.0)
	states.append(["[1]  LIGHTS OUT", "dark now" if g.cab.blackout > 0.0 else ("%d s" % ceili(cd) if cd > 0.0 else "ready")])
	var b := "ready  −%d s" % int(Rules.BUTTON_CUT)
	if g.phase != "open":
		b = "doors shut"
	elif g.ghost_used_floor == g.floor_now:
		b = "used this floor"
	elif g.presses >= Rules.BUTTON_PER_FLOOR:
		b = "panel jammed"
	elif g.time_left <= Rules.BUTTON_MIN_LEFT + 0.5:
		b = "too late"
	states.append(["[2]  PRESS A BUTTON", b])
	cd = g.ghost_cd.get("spook", 0.0)
	var sp := "ready"
	if cd > 0.0:
		sp = "%d s" % ceili(cd)
	elif g.phase != "open":
		sp = "doors shut"
	elif target_in:
		sp = "%s is in the cab" % who
	states.append(["[3]  SPOOK THE ROOM", sp])
	for i in 3:
		_ghost_powers[i].text = "%s\n%s" % states[i]
		var ready: bool = states[i][1].begins_with("ready")
		_ghost_powers[i].add_theme_color_override("font_color", UI.SAFE if ready else UI.MUTED)
	_ghost_pts.text = "Haunt points  %d   ·   +%d if %s is left behind" % [g.ghost_pts.get(g.me, 0), Rules.HAUNT_POINTS, who]
	return true


func _build_pause() -> void:
	_pause = UI.panel()
	_pause.custom_minimum_size = Vector2(620, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	_pause.add_child(v)
	v.add_child(UI.label("MENU", 52, UI.LED, UI.display))
	v.add_child(UI.label("The lift keeps falling while you're here.", 24, UI.MUTED))
	v.add_child(UI.button("Back to the lift", func(): toggle_pause()))
	v.add_child(UI.label("Mouse sensitivity", 24, UI.INK, UI.bold))
	var sens := HSlider.new()
	sens.min_value = 0.0008
	sens.max_value = 0.006
	sens.step = 0.0001
	sens.value = 0.0025
	sens.custom_minimum_size = Vector2(0, 30)
	sens.value_changed.connect(func(x):
		var lp := game.local_player()
		if lp:
			lp.sensitivity = x)
	v.add_child(sens)
	v.add_child(UI.label("Volume", 24, UI.INK, UI.bold))
	var vol := HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.05
	vol.value = Sound.volume
	vol.custom_minimum_size = Vector2(0, 30)
	vol.value_changed.connect(func(x): Sound.volume = x)
	v.add_child(vol)
	v.add_child(UI.button("Leave the game", func(): leave_pressed.emit()))
	_place(_pause, Control.PRESET_CENTER)
	_pause.visible = false


# --- called by the game ------------------------------------------------------------------

func refresh_players() -> void:
	if _lobby_list == null:
		return
	for c in _lobby_list.get_children():
		c.queue_free()
	var ids := game.info.keys()
	ids.sort()
	for id in ids:
		var d: Dictionary = game.info[id]
		var row := HBoxContainer.new()
		var sw := ColorRect.new()
		sw.color = Rules.PLAYER_COLORS[d.color]
		sw.custom_minimum_size = Vector2(18, 18)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(sw)
		var tag := "  (bot)" if d.bot else ("  (host)" if id == 1 else "")
		var you := "  ← you" if id == game.me else ""
		row.add_child(UI.label("  " + d.name + tag + you, 22, UI.INK if not d.bot else UI.MUTED, UI.bold))
		_lobby_list.add_child(row)


func on_phase() -> void:
	if game == null:
		return
	var lobby := game.phase == "lobby"
	_lobby.visible = lobby
	_lobby_host.visible = lobby and game.multiplayer.is_server()
	_lobby_wait.visible = lobby and not game.multiplayer.is_server()
	var steam_room := Lobby.lobby_id != 0
	_invite.visible = lobby and steam_room
	_invite.text = "Copy invite link" if Lobby.web else "Invite Steam friends"
	match Lobby.mode:
		"code":
			_room_title.text = "ROOM  %s" % Lobby.code
			_room_sub.text = ("Friends type %s under Play with friends, or send them %s" % [Lobby.code, Lobby.invite_link()]) if Lobby.web \
				else "Friends type %s under Play with friends, or you can invite them on Steam." % Lobby.code
		"quick":
			_room_title.text = "QUICKPLAY"
			_room_sub.text = "Other players are joining. Bots keep the seats warm until they do."
		_:
			_room_title.text = "THE LOBBY"
			_room_sub.text = "Everyone in the cab. Floor 40."
	var addr := _lobby_host.get_node("Addr") as Label
	addr.visible = not steam_room
	if lobby and game.multiplayer.is_server() and not steam_room:
		var a: Array[String] = Net.local_addresses()
		addr.text = "Friends on your Wi-Fi join with:  %s" % (", ".join(a) if not a.is_empty() else "this computer's IP address")
	if game.phase != "results":
		_results.visible = false


func banner(title: String, sub: String) -> void:
	big(title.to_upper(), sub)


func big(title: String, sub: String) -> void:
	_big_title.text = title
	_big_sub.text = sub
	_big_t = 3.2


func flash() -> void:
	_flash.color.a = 0.95


func feed(text: String) -> void:
	if _feed == null:
		return
	var l := UI.shadowed(UI.label(text, 24, UI.INK, UI.bold))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(620, 0)
	_feed.add_child(l)
	while _feed.get_child_count() > 6:
		_feed.get_child(0).free()
	var tw := l.create_tween()
	tw.tween_interval(5.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.0)
	tw.tween_callback(l.queue_free)


func show_results(rows: Array) -> void:
	for c in _results_grid.get_children():
		c.queue_free()
	for h in ["", "THIS ROUND", "TOTAL", ""]:
		_results_grid.add_child(UI.label(h, 22, UI.BRASS, UI.bold))
	for r in rows:
		var you: bool = r[0] == game.me
		_results_grid.add_child(UI.label(r[1] + ("  ← you" if you else ""), 30, UI.LED if you else UI.INK, UI.bold))
		_results_grid.add_child(UI.label(str(r[2]), 30, UI.INK, UI.bold))
		_results_grid.add_child(UI.label(str(r[3]), 30, UI.INK, UI.bold))
		var status := "made it" if r[4] else "left behind"
		if r.size() > 5 and r[5] > 0:
			status += "  ·  haunted +%d" % r[5]
		_results_grid.add_child(UI.label(status, 26, UI.SAFE if r[4] else UI.DANGER, UI.semi))
	_results_title.text = "ROUND %d · LOBBY!" % game.round_no
	_next_btn.visible = game.multiplayer.is_server()
	_results.visible = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func hide_results() -> void:
	_results.visible = false
	if DisplayServer.get_name() != "headless" and not paused and not OS.has_feature("web"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func set_spectating(on: bool) -> void:
	_spectate.visible = on
	_cross.visible = not on


func toggle_pause() -> void:
	paused = not paused
	_pause.visible = paused
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED


func update_hud(dt: float) -> void:
	if game == null:
		return
	var g := game
	var lp0 := g.local_player()
	var dark := g.cab.blackout > 0.0 and lp0 != null and lp0.alive
	_floor.text = "--" if dark else g.cab.led_in.text
	var showing_room := g.phase == "open" or g.phase == "closing"
	_room.text = Rules.ROOM_NAMES.get(g.room_kind, "") if showing_room else ("The lobby" if g.phase == "results" else "In the shaft")
	_hazard.text = Rules.ROOM_HAZARDS.get(g.room_kind, "") if showing_room else ""
	match g.phase:
		"lobby":
			_doors.text = "DOORS SEALED"
			_doors.add_theme_color_override("font_color", UI.INK)
		"descent":
			if g.snap_active():
				_doors.text = "CABLE SNAPPED!  HOLD A RAIL  %.1f" % g.snap_t
				_doors.add_theme_color_override("font_color", UI.DANGER)
			else:
				_doors.text = "FALLING"
				_doors.add_theme_color_override("font_color", UI.INK)
		"open":
			if dark:
				_doors.text = "LIGHTS OUT  ·  CLOCK DEAD"
				_doors.add_theme_color_override("font_color", UI.DANGER)
			elif g.waiting_weight:
				_doors.text = "TOO HEAVY! THROW SOMETHING OUT"
				_doors.add_theme_color_override("font_color", UI.DANGER)
			else:
				var s := int(ceil(g.time_left))
				_doors.text = "DOORS CLOSE IN %d" % s
				_doors.add_theme_color_override("font_color", UI.DANGER if s <= 5 else UI.INK)
				if s <= 5 and s != _last_tick and s > 0:
					Sound.play("tick", -4.0)
				_last_tick = s
		"closing":
			_doors.text = "DOORS CLOSING"
			_doors.add_theme_color_override("font_color", UI.DANGER)
		"crash":
			_doors.text = "BRACE!"
			_doors.add_theme_color_override("font_color", UI.DANGER)
		_:
			_doors.text = ""
	_riding.text = "%d / %d riding" % [g.alive_count(), g.players.size()]
	_haul.text = "Your haul  %d" % g.my_haul()
	_round.text = "Round %d" % g.round_no if g.round_no > 0 else "Waiting to start"
	var people := 0
	for d in g.info.values():
		if not d.bot:
			people += 1
	if g.countdown >= 0.0:
		_lobby_count.text = "Starting in %d" % int(ceil(g.countdown))
		_results_count.text = "Next round in %d" % int(ceil(g.countdown))
	else:
		_lobby_count.text = ("Waiting for one more person… (%d here)" % people) if Lobby.mode == "quick" else ""
		_results_count.text = ""
	var limit := Rules.CAB_LIMIT_KG
	_load_label.text = "CAB LOAD  %d / %d kg" % [int(g.cab_kg), int(limit)]
	_load_fill.size.x = 380.0 * clampf(g.cab_kg / limit, 0.0, 1.0)
	_load_fill.color = UI.DANGER if g.overweight else (UI.LED if g.cab_kg > limit * 0.85 else UI.BRASS)
	var lp := g.local_player()
	for i in Rules.SLOTS:
		if lp and i < lp.carried_kinds.size():
			var k := lp.carried_kinds[i]
			_slots[i].text = "%s\n%d pts · %s" % [Rules.loot_name(k), Rules.loot_value(k), g.kg_text(lp.carried[i])]
			_slot_boxes[i].modulate = Color.WHITE
		else:
			_slots[i].text = "empty"
			_slot_boxes[i].modulate = Color(1, 1, 1, 0.5)
	var it := g.interact_target()
	_prompt.text = ("[E]  " + it.text) if it.type == "loot" or it.type == "hold" else it.get("text", "")
	if Lobby.web and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not paused and g.phase != "results":
		_prompt.text = "Click the game to grab the mouse"
	var ghosting := _update_ghost(g)
	_hands.visible = not ghosting
	_spectate.visible = lp != null and not lp.alive and not ghosting and g.phase != "lobby" and g.phase != "results"
	_ghost_msg_t -= dt
	if _ghost_msg_t <= 0.0:
		_ghost_msg.text = ""
	_big_t -= dt
	_big.modulate.a = clampf(_big_t / 0.6, 0.0, 1.0)
	_flash.color.a = maxf(_flash.color.a - dt * 1.2, 0.0)
