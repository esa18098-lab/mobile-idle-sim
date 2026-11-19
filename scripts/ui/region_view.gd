extends VBoxContainer
## Region zoom: one region's slots. Tap an empty slot to build, a building to
## upgrade or demolish it.

const Look := preload("res://scripts/ui/look.gd")
const Icon := preload("res://scripts/ui/icon.gd")
const Sim := preload("res://scripts/sim/sim.gd")

signal back_tapped
signal empty_slot_tapped(region_idx: int)
signal building_tapped(building_id: int)

const COLUMNS := 4

var region_idx := 1


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	rebuild()


func rebuild() -> void:
	for c in get_children():
		c.queue_free()
	var sim = Game.sim
	var reg: Dictionary = sim.region(region_idx)
	var mine: bool = reg.owner == Sim.PLAYER

	var head := HBoxContainer.new()
	var back := Button.new()
	back.name = "back"
	back.text = "< Planet"
	back.pressed.connect(func(): back_tapped.emit())
	head.add_child(back)
	var title := Look.label("  " + reg.name, Look.FONT_TITLE)
	head.add_child(title)
	add_child(head)

	var owner_color: Color = Look.OWNER_COLORS.get(reg.owner, Look.DIM)
	add_child(Look.label("%s · %s" % ["Yours" if mine else reg.owner, reg.terrain], Look.FONT_SIZE, owner_color))
	add_child(Look.label(_terrain_line(reg), Look.FONT_SMALL, Look.DIM))

	var grid := GridContainer.new()
	grid.name = "slots"
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	add_child(grid)

	if not mine:
		for i in reg.slots:
			grid.add_child(_slot_tile(Icon.make(Look.DIM, "?", 2, true), "Held", reg.owner.split(" ")[0], "", true, Callable()))
		var info := Look.label("Garrison %s, defense ×%.2f. Taking regions arrives in milestone 4; the Dev menu can hand you one to build in." % [Look.num(reg.garrison), reg.defense_mod], Look.FONT_SMALL, Look.DIM)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(info)
		return

	for bd in sim.buildings_in(region_idx):
		var out: Dictionary = sim.building_output(bd)
		var id: int = bd.id
		var queued := _queued_upgrades(id)
		var lvl := "Lv %d" % bd.level + (" +%d" % queued if queued > 0 else "")
		var tile := _slot_tile(Icon.for_building(bd.type), Look.BUILDING_LOOK[bd.type].label, lvl,
			"%s %s" % [Look.rate(out.amount), _short(out.resource)], false, func(): building_tapped.emit(id))
		tile.name = "building_%d" % id
		grid.add_child(tile)
	for q in sim.queue:
		if q.kind == "build" and q.region == region_idx:
			grid.add_child(_slot_tile(Icon.for_building(q.type, 2, true), Look.BUILDING_LOOK[q.type].label, "queued", "", true, Callable()))
	for i in sim.open_slots(region_idx):
		var t := _slot_tile(Icon.make(Look.DIM, "+", 2, true), "Empty", "tap to build", "", false, func(): empty_slot_tapped.emit(region_idx))
		t.name = "empty_%d" % i
		grid.add_child(t)

	if reg.kept_credits > 0:
		var kept := Look.label("%d captured buildings fit your plan: placing them here is free, at level %d." % [reg.kept_credits, reg.kept_level], Look.FONT_SMALL, Look.ACCENT)
		kept.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(kept)
	var summary := Look.label(_summary(), Look.FONT_SMALL, Look.DIM)
	summary.name = "summary"
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(summary)


func _slot_tile(icon: Control, line1: String, line2: String, line3: String, disabled: bool, on_tap: Callable) -> Button:
	var tile := Button.new()
	tile.custom_minimum_size = Vector2(84, 92)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.disabled = disabled
	if on_tap.is_valid():
		tile.pressed.connect(on_tap)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 1)
	tile.add_child(box)
	var icon_row := CenterContainer.new()
	icon_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_row.add_child(icon)
	box.add_child(icon_row)
	for t in [[line1, Look.FONT_SIZE, Look.TEXT], [line2, Look.FONT_SMALL, Look.DIM], [line3, Look.FONT_SMALL, Look.TEXT]]:
		if t[0] == "":
			continue
		var l := Look.label(t[0], t[1], t[2])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(l)
	return tile


func _queued_upgrades(id: int) -> int:
	var n := 0
	for q in Game.sim.queue:
		if q.kind == "upgrade" and q.id == id:
			n += 1
	return n


func _terrain_line(reg: Dictionary) -> String:
	var parts: PackedStringArray = ["defense ×%.2f" % reg.defense_mod]
	for k in ["food", "metal", "fuel"]:
		if not is_equal_approx(reg.mult[k], 1.0):
			parts.append("%s ×%.2f" % [k, reg.mult[k]])
	return ", ".join(parts)


func _summary() -> String:
	var totals := {}
	for bd in Game.sim.buildings_in(region_idx):
		var o: Dictionary = Game.sim.building_output(bd)
		totals[o.resource] = totals.get(o.resource, 0.0) + o.amount
	if totals.is_empty():
		return "Nothing built here yet."
	var parts: PackedStringArray = []
	for k in totals:
		parts.append("%s %s" % [Look.rate(totals[k]), k])
	return "This region: " + ", ".join(parts)


static func _short(res: String) -> String:
	return {"citizens": "cit.", "equipment": "equip.", "soldiers": "sold."}.get(res, res)
