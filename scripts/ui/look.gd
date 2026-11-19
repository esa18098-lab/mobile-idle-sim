extends RefCounted
## Placeholder look: colours, short labels, number formatting and the theme.
## Nothing here is balance; it is presentation only and will change with real art.

const BG := Color("#14171f")
const PANEL := Color("#1f2430")
const PANEL_HI := Color("#2a3141")
const LINE := Color("#3b4457")
const TEXT := Color("#ece8dc")
const DIM := Color("#9097a6")
const ACCENT := Color("#e3b341")
const BAD := Color("#d0603f")

## Silkscreen is drawn on an 8 px grid: only multiples of 8 stay crisp.
const FONT_SIZE := 8
const FONT_SMALL := 8
const FONT_TITLE := 16

const OWNER_COLORS := {
	"You": Color("#e3b341"),
	"Kharn Clans": Color("#c8553d"),
	"Veyra Compact": Color("#3fa7a3"),
	"Ostrel Dominion": Color("#9a6ad6"),
}

const TERRAIN_COLORS := {
	"Plains": Color("#6f8f3f"),
	"Forest": Color("#3e6b3a"),
	"Hills": Color("#8a6f45"),
	"Mountains": Color("#6c6f76"),
	"Tundra": Color("#9fb9c4"),
	"Coast": Color("#4f86a6"),
}

const RESOURCE_COLORS := {
	"citizens": Color("#d9a05b"),
	"food": Color("#7fb24a"),
	"metal": Color("#a3a9b2"),
	"fuel": Color("#e07b39"),
	"gold": Color("#e3b341"),
	"rations": Color("#c9a227"),
	"equipment": Color("#5b8fd0"),
	"soldiers": Color("#c8553d"),
}

const BUILDING_LOOK := {
	"home": {"label": "Home", "letter": "H", "color": Color("#d9a05b")},
	"farm": {"label": "Farm", "letter": "F", "color": Color("#7fb24a")},
	"mine": {"label": "Mine", "letter": "M", "color": Color("#8d939c")},
	"fuel_extractor": {"label": "Fuel", "letter": "U", "color": Color("#e07b39")},
	"factory_rations": {"label": "Rations", "letter": "R", "color": Color("#c9a227")},
	"factory_equipment": {"label": "Equip.", "letter": "E", "color": Color("#5b8fd0")},
	"barracks": {"label": "Barracks", "letter": "B", "color": Color("#b2553b")},
	"station": {"label": "Station", "letter": "S", "color": Color("#e3b341")},
}


static func num(v: float) -> String:
	var a := absf(v)
	var sgn := "-" if v < 0.0 else ""
	if a >= 1_000_000.0:
		return "%s%.1fM" % [sgn, a / 1_000_000.0]
	if a >= 10_000.0:
		return "%s%dk" % [sgn, roundi(a / 1000.0)]
	if a >= 1000.0:
		return "%s%.1fk" % [sgn, a / 1000.0]
	if a >= 10.0 or a == 0.0:
		return "%s%d" % [sgn, roundi(a)]
	return "%s%.1f" % [sgn, a]


static func rate(v: float) -> String:
	return ("+" if v >= 0.0 else "") + num(v) + "/h"


## "100 metal · 10 fuel", or "Free" for an empty cost.
static func cost(c: Dictionary) -> String:
	if c.is_empty():
		return "Free"
	var parts: PackedStringArray = []
	for k in ["metal", "fuel", "gold"]:
		if c.has(k) and c[k] > 0.0:
			parts.append("%s %s" % [num(c[k]), k])
	return " · ".join(parts)


static func flat_box(fill: Color, border: Color = Color(0, 0, 0, 0), width: int = 0, pad: int = 4) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_content_margin_all(pad)
	sb.anti_aliasing = false
	return sb


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = FONT_SIZE
	var font: FontFile = load("res://assets/fonts/Silkscreen-Regular.ttf")
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.hinting = TextServer.HINTING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	t.default_font = font
	t.set_color("font_color", "Label", TEXT)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var fill := PANEL_HI if state != "pressed" else LINE
		if state == "disabled":
			fill = PANEL
		var box := flat_box(fill, LINE, 1, 6)
		if state == "focus":
			box = flat_box(Color(0, 0, 0, 0), ACCENT, 1, 6)
		t.set_stylebox(state, "Button", box)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_disabled_color", "Button", DIM)
	t.set_stylebox("panel", "PanelContainer", flat_box(PANEL, LINE, 1, 6))
	t.set_stylebox("panel", "Panel", flat_box(PANEL, LINE, 1, 0))
	return t


static func label(text: String, size: int = FONT_SIZE, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
