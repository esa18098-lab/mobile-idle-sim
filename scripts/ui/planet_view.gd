extends VBoxContainer
## Planet zoom: the 12 regions as territories. Tap one to open its slots.

const Look := preload("res://scripts/ui/look.gd")
const Sim := preload("res://scripts/sim/sim.gd")

signal region_tapped(region_idx: int)

const COLUMNS := 3


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	rebuild()


func rebuild() -> void:
	for c in get_children():
		c.queue_free()
	var sim = Game.sim
	var owned := 0
	for reg in sim.regions:
		if reg.owner == Sim.PLAYER:
			owned += 1
	var head := HBoxContainer.new()
	head.add_child(Look.label("Home planet", Look.FONT_TITLE))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	head.add_child(Look.label("%d of %d regions" % [owned, sim.regions.size()], Look.FONT_SIZE, Look.DIM))
	add_child(head)

	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(grid)
	for reg in sim.regions:
		grid.add_child(_region_tile(reg))


func _region_tile(reg: Dictionary) -> Button:
	var sim = Game.sim
	var mine: bool = reg.owner == Sim.PLAYER
	var fill: Color = Look.TERRAIN_COLORS.get(reg.terrain, Look.PANEL)
	if not mine:
		fill = fill.darkened(0.45)
	var border: Color = Look.OWNER_COLORS.get(reg.owner, Look.LINE)
	var tile := Button.new()
	tile.name = "region_%d" % reg.index
	tile.custom_minimum_size = Vector2(114, 118)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for state in ["normal", "hover", "focus", "disabled"]:
		tile.add_theme_stylebox_override(state, Look.flat_box(fill, border, 2, 5))
	tile.add_theme_stylebox_override("pressed", Look.flat_box(fill.lightened(0.15), Look.ACCENT, 2, 5))
	tile.pressed.connect(func(): region_tapped.emit(reg.index))

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 5)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 0)
	tile.add_child(box)
	var name_l := Look.label(reg.name, Look.FONT_SIZE)
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(name_l)
	box.add_child(Look.label("You" if mine else reg.owner.split(" ")[0], Look.FONT_SMALL, border))
	box.add_child(Look.label(reg.terrain, Look.FONT_SMALL, Look.TEXT if mine else Look.DIM))
	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(grow)
	if mine:
		var used: int = reg.slots - sim.free_slots(reg.index)
		box.add_child(Look.label("%d/%d slots" % [used, reg.slots], Look.FONT_SMALL))
	else:
		box.add_child(Look.label("Garrison %s" % Look.num(reg.garrison), Look.FONT_SMALL, Look.DIM))
	return tile
