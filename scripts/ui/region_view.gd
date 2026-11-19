extends VBoxContainer
## Region zoom: one region's slots. Tap an empty slot to build, a building to
## upgrade or demolish it.

const Look := preload("res://scripts/ui/look.gd")
const Icon := preload("res://scripts/ui/icon.gd")
const Sim := preload("res://scripts/sim/sim.gd")

signal back_tapped
signal empty_slot_tapped(region_idx: int)
signal building_tapped(building_id: int)
signal attack_tapped(region_idx: int)

const COLUMNS := 4

var region_idx := 1
var _battle_label: Label
var _battle_bar: ColorRect
var _battle_track: Control


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	rebuild()


func rebuild() -> void:
	for c in get_children():
		remove_child(c)   # detach now: the new nodes reuse the old names
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
		add_child(Look.label("Garrison %s · defense ×%.2f with home advantage ×%.2f" % [Look.num(reg.garrison), reg.defense_mod, sim.b.num("def_advantage")], Look.FONT_SIZE))
		if sim.battle_at(region_idx).size() > 0:
			_add_battle_bar()
		else:
			var blocker: String = sim.attack_blocker(region_idx, 1)
			var plan := Button.new()
			plan.name = "plan_attack"
			plan.custom_minimum_size = Vector2(0, 44)
			plan.text = "Plan attack" if blocker in ["", "Send at least one soldier"] or blocker.begins_with("Only") else blocker
			plan.disabled = blocker == "Not on your border"
			plan.pressed.connect(func(): attack_tapped.emit(region_idx))
			add_child(plan)
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


func _add_battle_bar() -> void:
	_battle_label = Look.label("", Look.FONT_SIZE, Look.ACCENT)
	_battle_label.name = "battle"
	add_child(_battle_label)
	_battle_track = ColorRect.new()
	_battle_track.color = Look.PANEL_HI
	_battle_track.custom_minimum_size = Vector2(0, 8)
	add_child(_battle_track)
	_battle_bar = ColorRect.new()
	_battle_bar.color = Look.ACCENT
	_battle_track.add_child(_battle_bar)
	refresh_live()


## Called a few times a second: moves the battle bar without a full rebuild.
func refresh_live() -> void:
	if _battle_label == null or not is_instance_valid(_battle_label):
		return
	var sim = Game.sim
	var battle: Dictionary = sim.battle_at(region_idx)
	if battle.is_empty():
		return
	var total: float = battle.ends_at - battle.started_at
	var done := clampf((sim.hours - battle.started_at) / total, 0.0, 1.0) if total > 0.0 else 1.0
	var left := int(maxf(0.0, battle.ends_at - sim.hours) * 3600.0)
	_battle_label.text = "Battle: %d attacking · %s left · then %s" % [battle.soldiers, _clock(left), battle.on_capture.to_lower()]
	_battle_bar.size = Vector2(_battle_track.size.x * done, 8)


static func _clock(secs: int) -> String:
	return "%d:%02d" % [secs / 60, secs % 60] if secs < 3600 else "%d:%02d:%02d" % [secs / 3600, (secs / 60) % 60, secs % 60]


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
