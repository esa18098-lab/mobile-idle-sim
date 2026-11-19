extends VBoxContainer
## Planet zoom: the 12 regions as territories. Tap one to open its slots.

const Look := preload("res://scripts/ui/look.gd")
const Sim := preload("res://scripts/sim/sim.gd")

signal region_tapped(region_idx: int)
signal market_tapped
signal diplomacy_tapped

const COLUMNS := 3

var _battle_labels := {}   ## region -> Label


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	rebuild()


func rebuild() -> void:
	for c in get_children():
		remove_child(c)   # detach now: the new nodes reuse the old names
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
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 4)
	for pair in [["Market", market_tapped], ["Diplomacy", diplomacy_tapped]]:
		var bt := Button.new()
		bt.name = pair[0].to_lower()
		bt.text = pair[0]
		bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bt.custom_minimum_size = Vector2(0, 32)
		var sig: Signal = pair[1]
		bt.pressed.connect(func(): sig.emit())
		nav.add_child(bt)
	add_child(nav)

	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(grid)
	_battle_labels.clear()
	var by_pos := {}
	for reg in sim.regions:
		by_pos[sim.map_pos[reg.index]] = reg
	var rows := 0
	for p in by_pos:
		rows = maxi(rows, p.y + 1)
	for y in rows:
		for x in COLUMNS:
			var p := Vector2i(x, y)
			if by_pos.has(p):
				grid.add_child(_region_tile(by_pos[p]))
			else:
				grid.add_child(Control.new())
	refresh_live()


func refresh_live() -> void:
	var sim = Game.sim
	for idx in _battle_labels:
		var battle: Dictionary = sim.battle_at(idx)
		var l: Label = _battle_labels[idx]
		if not is_instance_valid(l):
			continue
		var raid: Dictionary = {}
		for r in sim.npc_raids:
			if r.target == idx:
				raid = r
		if not raid.is_empty():
			var t: float = raid.warning_ends_at if raid.battle_ends_at < 0.0 else raid.battle_ends_at
			var left2 := int(maxf(0.0, t - sim.hours) * 3600.0)
			l.text = "Under attack %d:%02d" % [left2 / 60, left2 % 60]
			l.add_theme_color_override("font_color", Look.BAD)
		elif battle.is_empty():
			l.text = ""
		else:
			var left := int(maxf(0.0, battle.ends_at - sim.hours) * 3600.0)
			l.text = "Battle %d:%02d" % [left / 60, left % 60]
			l.add_theme_color_override("font_color", Look.ACCENT)
		l.visible = l.text != ""


func _region_tile(reg: Dictionary) -> Button:
	var sim = Game.sim
	var mine: bool = reg.owner == Sim.PLAYER
	var fill: Color = Look.TERRAIN_COLORS.get(reg.terrain, Look.PANEL)
	var reachable: bool = not mine and sim.neighbours(reg.index).any(func(n): return sim.owns(n))
	if not mine:
		fill = fill.darkened(0.45 if reachable else 0.65)
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
	var battle_l := Look.label("", Look.FONT_SIZE, Look.ACCENT)
	battle_l.add_theme_stylebox_override("normal", Look.flat_box(Color(0.05, 0.06, 0.08, 0.85), Color(0, 0, 0, 0), 0, 1))
	battle_l.visible = false
	box.add_child(battle_l)
	_battle_labels[reg.index] = battle_l
	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(grow)
	if mine:
		var used: int = reg.slots - sim.free_slots(reg.index)
		box.add_child(Look.label("%d/%d slots" % [used, reg.slots], Look.FONT_SMALL))
	else:
		box.add_child(Look.label(("Border · " if reachable else "") + "Garrison %s" % Look.num(reg.garrison), Look.FONT_SMALL, Look.TEXT if reachable else Look.DIM))
	return tile
