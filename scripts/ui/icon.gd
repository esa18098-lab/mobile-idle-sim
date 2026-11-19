extends Control
## Placeholder 16×16 pixel icon, drawn at an integer scale: a coloured square
## with a darker rim and a letter. Real sprites replace this after milestone 4.

const Look := preload("res://scripts/ui/look.gd")

var color := Color.WHITE
var letter := ""
var scale_px := 2
var ghost := false     ## drawn hollow, for queued or empty things


static func make(p_color: Color, p_letter: String, p_scale: int = 2, p_ghost: bool = false) -> Control:
	var i = load("res://scripts/ui/icon.gd").new()
	i.color = p_color
	i.letter = p_letter
	i.scale_px = p_scale
	i.ghost = p_ghost
	i.custom_minimum_size = Vector2(16, 16) * p_scale
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return i


static func for_building(type: String, p_scale: int = 2, p_ghost: bool = false) -> Control:
	var look: Dictionary = Look.BUILDING_LOOK.get(type, {"letter": "?", "color": Color.MAGENTA})
	return make(look.color, look.letter, p_scale, p_ghost)


static func for_resource(res: String, p_scale: int = 1) -> Control:
	return make(Look.RESOURCE_COLORS.get(res, Color.MAGENTA), "", p_scale)


func _draw() -> void:
	var s := float(scale_px)
	var r := Rect2(Vector2.ZERO, Vector2(16, 16) * s)
	if ghost:
		draw_rect(r.grow(-s * 0.5), color.darkened(0.2), false, s)
	else:
		draw_rect(r, color.darkened(0.45))
		draw_rect(r.grow(-s), color)
		draw_rect(Rect2(r.position + Vector2(s, s), Vector2(14 * s, s)), color.lightened(0.25))
	if letter != "":
		var font := get_theme_default_font()
		var fs := int(8 * s)
		var ts := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var pos := Vector2((r.size.x - ts.x) * 0.5, (r.size.y + fs * 0.7) * 0.5)
		draw_string(font, pos.round(), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#14171f") if not ghost else color)
