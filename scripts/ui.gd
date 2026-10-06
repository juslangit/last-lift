class_name UI
extends RefCounted

## The look of every screen: brass and elevator-LED orange on smoked glass,
## Bungee for the shouting and Chakra Petch for everything else. Sizes are large on purpose.

const LED := Color("ff7a3d")
const BRASS := Color("d6a948")
const INK := Color("f4ecdc")
const MUTED := Color("b9ad95")
const PANEL := Color(0.07, 0.055, 0.04, 0.82)
const DANGER := Color("ff4f3a")
const SAFE := Color("5fd38d")

static var display: Font = load("res://assets/fonts/Bungee-Regular.ttf")
static var bold: Font = load("res://assets/fonts/ChakraPetch-Bold.ttf")
static var semi: Font = load("res://assets/fonts/ChakraPetch-SemiBold.ttf")


static func theme() -> Theme:
	var t := Theme.new()
	t.default_font = semi
	t.default_font_size = 26
	var normal := _box(Color("2a2117"), BRASS, 2)
	var hover := _box(Color("3a2d1e"), LED, 2)
	var pressed := _box(Color("4a3420"), LED, 2)
	for k in ["normal", "focus"]:
		t.set_stylebox(k, "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", _box(Color("1d1812"), Color("4a4030"), 2))
	t.set_font("font", "Button", bold)
	t.set_font_size("font_size", "Button", 28)
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color("6d6250"))
	t.set_stylebox("normal", "LineEdit", _box(Color("140f0a"), Color("6d5a36"), 2))
	t.set_stylebox("focus", "LineEdit", _box(Color("140f0a"), LED, 2))
	t.set_font("font", "LineEdit", bold)
	t.set_font_size("font_size", "LineEdit", 30)
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_color", "Label", INK)
	t.set_stylebox("panel", "PanelContainer", _box(PANEL, Color(BRASS, 0.55), 2, 10))
	t.set_stylebox("slider", "HSlider", _box(Color("2a2117"), Color("6d5a36"), 1, 4, 6))
	t.set_stylebox("grabber_area", "HSlider", _box(BRASS, BRASS, 0, 4, 6))
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(LED, LED, 0, 4, 6))
	return t


static func _box(bg: Color, border: Color, width: int, radius := 8, pad := 14) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad + 6
	s.content_margin_right = pad + 6
	s.content_margin_top = pad * 0.6
	s.content_margin_bottom = pad * 0.6
	return s


static func label(text: String, size := 26, color := INK, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_override("font", font if font else semi)
	l.add_theme_constant_override("outline_size", 0)
	return l


static func shadowed(l: Label) -> Label:
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 3)
	return l


static func panel() -> PanelContainer:
	return PanelContainer.new()


static func button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func():
		Sound.play("click", -8.0)
		cb.call())
	return b
