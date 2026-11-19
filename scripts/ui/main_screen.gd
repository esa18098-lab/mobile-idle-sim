extends Control
## The game screen: resource bar on top, planet or region view in the middle,
## queue and clock at the bottom. Pop-up sheets slide over it for choices.

const Look := preload("res://scripts/ui/look.gd")
const Icon := preload("res://scripts/ui/icon.gd")
const ResourceBar := preload("res://scripts/ui/resource_bar.gd")
const PlanetView := preload("res://scripts/ui/planet_view.gd")
const RegionView := preload("res://scripts/ui/region_view.gd")

const REFRESH_SECONDS := 0.2

var resource_bar: ResourceBar
var view: Control                 ## the planet or region view on screen
var _content: MarginContainer
var _queue_btn: Button
var _clock: Label
var _sheet_layer: Control
var _sheet_box: VBoxContainer
var _sheet_builder := Callable()  ## rebuilds the open sheet when the game changes
var _since_refresh := 0.0
var _demolish_armed := -1


func _ready() -> void:
	theme = Look.make_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Look.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 0)
	add_child(col)

	resource_bar = ResourceBar.new()
	col.add_child(resource_bar)

	_content = MarginContainer.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		_content.add_theme_constant_override("margin_" + side, 6)
	col.add_child(_content)

	col.add_child(_bottom_bar())
	_build_sheet_layer()

	Game.changed.connect(_on_changed)
	show_planet()
	_refresh_bottom()


func _process(delta: float) -> void:
	_since_refresh += delta
	if _since_refresh < REFRESH_SECONDS:
		return
	_since_refresh = 0.0
	resource_bar.refresh()
	_refresh_bottom()
	if _sheet_layer.visible and _sheet_builder.is_valid() and _sheet_builder.get_method() == &"_queue_sheet":
		_rebuild_sheet()


## Android back: close a sheet, then step out of a region, then leave the app.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		go_back()


func go_back() -> void:
	if _sheet_layer.visible:
		close_sheet()
	elif view is RegionView:
		show_planet()
	else:
		get_tree().quit()


# =============================================================================
# Views
# =============================================================================

func show_planet() -> void:
	_set_view(PlanetView.new())
	view.region_tapped.connect(show_region)


func show_region(idx: int) -> void:
	var rv := RegionView.new()
	rv.region_idx = idx
	_set_view(rv)
	rv.back_tapped.connect(show_planet)
	rv.empty_slot_tapped.connect(open_build_sheet)
	rv.building_tapped.connect(open_building_sheet)


func _set_view(v: Control) -> void:
	if view:
		view.queue_free()
	view = v
	_content.add_child(v)


func _on_changed() -> void:
	if view and view.has_method("rebuild"):
		view.rebuild()
	resource_bar.refresh()
	_refresh_bottom()
	if _sheet_layer.visible:
		_rebuild_sheet()


# =============================================================================
# Bottom bar
# =============================================================================

func _bottom_bar() -> Control:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", Look.flat_box(Look.PANEL, Look.LINE, 0, 4))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	bar.add_child(row)
	_queue_btn = Button.new()
	_queue_btn.name = "queue"
	_queue_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_queue_btn.custom_minimum_size = Vector2(0, 40)
	_queue_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_queue_btn.pressed.connect(func(): _open_sheet(_queue_sheet))
	row.add_child(_queue_btn)
	_clock = Look.label("", Look.FONT_SMALL, Look.DIM)
	_clock.custom_minimum_size = Vector2(62, 0)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_clock)
	if OS.is_debug_build():
		var dev := Button.new()
		dev.name = "dev"
		dev.text = "Dev"
		dev.custom_minimum_size = Vector2(44, 40)
		dev.pressed.connect(func(): _open_sheet(_dev_sheet))
		row.add_child(dev)
	return bar


func _refresh_bottom() -> void:
	var sim = Game.sim
	if sim.queue.is_empty():
		_queue_btn.text = "Queue empty"
	else:
		_queue_btn.text = "Queue %d · %s" % [sim.queue.size(), _waiting_for(sim.queue[0])]
	var secs := int(sim.hours * 3600.0)
	_clock.text = "%d:%02d:%02d\n×%s" % [secs / 3600, (secs / 60) % 60, secs % 60, Look.num(Game.speed)]


## "needs 120 metal" for the first thing the stockpile can't cover yet.
func _waiting_for(item: Dictionary) -> String:
	var c: Dictionary = Game.sim.cost_of(item)
	for k in c:
		var short: float = c[k] - Game.sim.res[k]
		if short > 0.0:
			return "needs %s %s" % [Look.num(short), k]
	return "paying"


# =============================================================================
# Sheets
# =============================================================================

func _build_sheet_layer() -> void:
	_sheet_layer = Control.new()
	_sheet_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sheet_layer.visible = false
	add_child(_sheet_layer)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.gui_input.connect(func(e):
		if (e is InputEventMouseButton or e is InputEventScreenTouch) and e.pressed:
			close_sheet())
	_sheet_layer.add_child(shade)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Look.flat_box(Look.PANEL, Look.ACCENT, 1, 8))
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE, Control.PRESET_MODE_MINSIZE)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_sheet_layer.add_child(panel)
	_sheet_box = VBoxContainer.new()
	_sheet_box.add_theme_constant_override("separation", 6)
	panel.add_child(_sheet_box)


func _open_sheet(builder: Callable) -> void:
	_sheet_builder = builder
	_demolish_armed = -1
	_sheet_layer.visible = true
	_rebuild_sheet()


func close_sheet() -> void:
	_sheet_layer.visible = false
	_sheet_builder = Callable()


func _rebuild_sheet() -> void:
	for c in _sheet_box.get_children():
		_sheet_box.remove_child(c)
		c.queue_free()
	if _sheet_builder.is_valid():
		_sheet_builder.call()


func _sheet_title(text: String) -> void:
	var row := HBoxContainer.new()
	var t := Look.label(text, Look.FONT_TITLE)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(t)
	var x := Button.new()
	x.text = "Close"
	x.pressed.connect(close_sheet)
	row.add_child(x)
	_sheet_box.add_child(row)


func _row_button(icon: Control, title: String, sub: String, right: String, on_tap: Callable, disabled := false) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 44)
	btn.disabled = disabled
	btn.pressed.connect(on_tap)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	btn.add_child(row)
	if icon:
		var c := CenterContainer.new()
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(icon)
		row.add_child(c)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 0)
	col.add_child(Look.label(title))
	if sub != "":
		col.add_child(Look.label(sub, Look.FONT_SMALL, Look.DIM))
	row.add_child(col)
	if right != "":
		var r := Look.label(right, Look.FONT_SMALL, Look.TEXT)
		r.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(r)
	return btn


# --- build -------------------------------------------------------------------

func open_build_sheet(region_idx: int) -> void:
	_open_sheet(_build_sheet.bind(region_idx))


func _build_sheet(region_idx: int) -> void:
	var sim = Game.sim
	var reg: Dictionary = sim.region(region_idx)
	_sheet_title("Build in %s" % reg.name)
	var free: bool = reg.kept_credits > 0
	var cost_text: String = ("Free · Lv %d" % reg.kept_level) if free else Look.cost(sim.new_building_cost())
	for type in sim.buildable_types():
		var preview: Dictionary = sim.building_output({"type": type, "region": region_idx, "level": 1}, reg.kept_level if free else 1)
		var sub := "%s %s" % [Look.rate(preview.amount), preview.resource]
		if preview.has("power"):
			sub += ", uses %s fuel" % Look.rate(preview.power)
		var btn := _row_button(Icon.for_building(type), Look.BUILDING_LOOK[type].label, sub, cost_text, func():
			Game.cmd_build(type, region_idx)
			close_sheet())
		btn.name = "build_" + type
		_sheet_box.add_child(btn)
	_sheet_box.add_child(Look.label("Paid from your stockpile in queue order.", Look.FONT_SMALL, Look.DIM))


# --- one building -------------------------------------------------------------

func open_building_sheet(building_id: int) -> void:
	_open_sheet(_building_sheet.bind(building_id))


func _building_sheet(building_id: int) -> void:
	var sim = Game.sim
	var bd: Dictionary = sim.building_by_id(building_id)
	if bd.is_empty():
		close_sheet()
		return
	var look: Dictionary = Look.BUILDING_LOOK[bd.type]
	_sheet_title("%s · Lv %d" % [look.label, bd.level])
	var now: Dictionary = sim.building_output(bd)
	var queued := 0
	for q in sim.queue:
		if q.kind == "upgrade" and q.id == building_id:
			queued += 1
	var next_level: int = bd.level + queued + 1
	var nxt: Dictionary = sim.building_output(bd, next_level)
	var info := Look.label("Makes %s %s in %s." % [Look.rate(now.amount), now.resource, sim.region(bd.region).name])
	info.name = "makes"
	_sheet_box.add_child(info)
	if now.has("power"):
		_sheet_box.add_child(Look.label("Draws %s fuel for power while it runs." % Look.rate(now.power), Look.FONT_SMALL, Look.DIM))
	var up := _row_button(Icon.make(Look.ACCENT, "+", 2), "Upgrade to Lv %d" % next_level,
		"%s %s" % [Look.rate(nxt.amount), nxt.resource] + (" · %d already queued" % queued if queued > 0 else ""),
		Look.cost(sim.upgrade_cost(next_level - 1)), func(): Game.cmd_upgrade(building_id))
	up.name = "upgrade"
	_sheet_box.add_child(up)
	var armed := _demolish_armed == building_id
	var demo := _row_button(null, "Tap again to demolish (no refund)" if armed else "Demolish",
		"Frees the slot for another building.", "", func():
			if _demolish_armed == building_id:
				Game.cmd_demolish(building_id)
				close_sheet()
			else:
				_demolish_armed = building_id
				_rebuild_sheet())
	demo.name = "demolish"
	if armed:
		demo.add_theme_color_override("font_color", Look.BAD)
	_sheet_box.add_child(demo)


# --- queue --------------------------------------------------------------------

func _queue_sheet() -> void:
	var sim = Game.sim
	_sheet_title("Queue")
	if sim.queue.is_empty():
		_sheet_box.add_child(Look.label("Nothing waiting. Tap an empty slot or a building to add work.", Look.FONT_SMALL, Look.DIM))
		return
	for i in mini(sim.queue.size(), 8):
		var q: Dictionary = sim.queue[i]
		var idx := i
		var title := _queue_title(q, i)
		var status := _waiting_for(q) if i == 0 else "waiting in line"
		var btn := _row_button(_queue_icon(q), title, status, Look.cost(sim.projected_cost(i)) + ("\ntap to cancel" if q.kind != "annex_gold" else ""),
			func(): Game.cmd_cancel_queued(idx), q.kind == "annex_gold")
		_sheet_box.add_child(btn)
	if sim.queue.size() > 8:
		_sheet_box.add_child(Look.label("and %d more" % (sim.queue.size() - 8), Look.FONT_SMALL, Look.DIM))


func _queue_title(q: Dictionary, index: int) -> String:
	var sim = Game.sim
	match q.kind:
		"build": return "Build %s in %s" % [Look.BUILDING_LOOK[q.type].label, sim.region(q.region).name]
		"upgrade":
			var bd: Dictionary = sim.building_by_id(q.id)
			var from: int = sim.projected_level(index)
			return "%s Lv %d > %d" % [Look.BUILDING_LOOK[bd.type].label, from, from + 1]
		"upgrade_lowest": return "Upgrade lowest building"
		"annex_gold": return "Annexation payment"
	return q.kind


func _queue_icon(q: Dictionary) -> Control:
	match q.kind:
		"build": return Icon.for_building(q.type, 2, true)
		"upgrade":
			return Icon.for_building(Game.sim.building_by_id(q.id).type, 2)
	return Icon.make(Look.ACCENT, "$", 2)


# --- dev ----------------------------------------------------------------------

func _dev_sheet() -> void:
	_sheet_title("Dev tools")
	var speeds := HBoxContainer.new()
	speeds.add_theme_constant_override("separation", 4)
	for s in [1.0, 10.0, 60.0, 600.0]:
		var b := Button.new()
		b.text = "×%s" % Look.num(s)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 40)
		if is_equal_approx(Game.speed, s):
			b.add_theme_color_override("font_color", Look.ACCENT)
		b.pressed.connect(func():
			Game.speed = s
			_rebuild_sheet())
		speeds.add_child(b)
	_sheet_box.add_child(Look.label("Game speed", Look.FONT_SMALL, Look.DIM))
	_sheet_box.add_child(speeds)
	_sheet_box.add_child(_row_button(null, "+5k of every resource", "", "", func(): Game.dev_add_resources(5000.0)))
	_sheet_box.add_child(_row_button(null, "Take the next enemy region", "Empty slots to build in, until conquest exists", "", func():
		var idx := Game.dev_take_next_region()
		close_sheet()
		if idx > 0:
			show_region(idx)))
	_sheet_box.add_child(_row_button(null, "New game", "Throws away this run", "", func():
		Game.new_game()
		close_sheet()
		show_planet()))
	_sheet_box.add_child(_row_button(null, "Build check screen", "The milestone 1–2 test screen", "", func():
		get_tree().change_scene_to_file("res://scenes/build_check.tscn")))
