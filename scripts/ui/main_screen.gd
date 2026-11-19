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
var _sheet_scroll: ScrollContainer
const SHEET_MAX_HEIGHT := 540.0
var _sheet_builder := Callable()  ## rebuilds the open sheet when the game changes
var _since_refresh := 0.0
var _demolish_armed := -1
var _army_btn: Button
var _toast_box: VBoxContainer
var _seen_events := 0
var _attack_count := 0
var _attack_mode := "Occupy"


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
	_toast_box = VBoxContainer.new()
	_toast_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE, 6)
	_toast_box.position.y = 56
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast_box)
	_seen_events = Game.sim.events.size()

	Game.changed.connect(_on_changed)
	Game.away.connect(func(summary): _open_sheet(_away_sheet.bind(summary)))
	show_planet()
	_refresh_bottom()


func _process(delta: float) -> void:
	_since_refresh += delta
	if _since_refresh < REFRESH_SECONDS:
		return
	_since_refresh = 0.0
	resource_bar.refresh()
	_refresh_bottom()
	_show_new_events()
	if view and view.has_method("refresh_live"):
		view.refresh_live()
	if _sheet_layer.visible and _sheet_builder.is_valid() and _sheet_builder.get_method() in [&"_queue_sheet", &"_army_sheet", &"_diplomacy_sheet", &"_market_sheet"]:
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
	view.market_tapped.connect(func(): _open_sheet(_market_sheet))
	view.diplomacy_tapped.connect(func(): _open_sheet(_diplomacy_sheet))


func show_region(idx: int) -> void:
	var rv := RegionView.new()
	rv.region_idx = idx
	_set_view(rv)
	rv.back_tapped.connect(show_planet)
	rv.empty_slot_tapped.connect(open_build_sheet)
	rv.building_tapped.connect(open_building_sheet)
	rv.attack_tapped.connect(open_attack_sheet)
	rv.annex_tapped.connect(func(_idx): _open_sheet(_diplomacy_sheet))


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
	_army_btn = Button.new()
	_army_btn.name = "army"
	_army_btn.custom_minimum_size = Vector2(76, 40)
	_army_btn.pressed.connect(func(): _open_sheet(_army_sheet))
	row.add_child(_army_btn)
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
		_queue_btn.text = "Queue %d\n%s" % [sim.queue.size(), _waiting_for(sim.queue[0])]
	var away := 0.0
	for battle in sim.battles:
		away += battle.soldiers
	_army_btn.text = "Army %s" % Look.num(sim.soldiers) + ("\n%s fighting" % Look.num(away) if away > 0.0 else ("\ntrain to %s" % Look.num(sim.train_target) if sim.train_target > sim.soldiers + 0.5 else ""))
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
	_sheet_scroll = ScrollContainer.new()
	_sheet_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(_sheet_scroll)
	_sheet_box = VBoxContainer.new()
	_sheet_box.add_theme_constant_override("separation", 6)
	_sheet_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sheet_scroll.add_child(_sheet_box)


func _open_sheet(builder: Callable) -> void:
	_sheet_builder = builder
	_demolish_armed = -1
	_sheet_layer.visible = true
	_rebuild_sheet()


func _show_new_events() -> void:
	var events: Array = Game.sim.events
	if _seen_events > events.size():   # new game
		_seen_events = 0
	while _seen_events < events.size():
		var e: Dictionary = events[_seen_events]
		_seen_events += 1
		if e.kind in ["captured", "battle_lost", "annexed"]:
			toast(e.text, Look.BAD if e.kind == "battle_lost" else Look.ACCENT)


func toast(text: String, color: Color = Look.ACCENT) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Look.flat_box(Look.PANEL, color, 1, 6))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Look.label(text, Look.FONT_SIZE, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(l)
	_toast_box.add_child(panel)
	get_tree().create_timer(5.0).timeout.connect(func():
		if is_instance_valid(panel):
			panel.queue_free())


func close_sheet() -> void:
	_sheet_layer.visible = false
	_sheet_builder = Callable()


func _rebuild_sheet() -> void:
	for c in _sheet_box.get_children():
		_sheet_box.remove_child(c)
		c.queue_free()
	if _sheet_builder.is_valid():
		_sheet_builder.call()
	_fit_sheet.call_deferred()


## Sheets grow with their content up to SHEET_MAX_HEIGHT, then scroll.
func _fit_sheet() -> void:
	var h := minf(_sheet_box.get_combined_minimum_size().y, SHEET_MAX_HEIGHT)
	_sheet_scroll.custom_minimum_size = Vector2(0, h)


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


# --- attack -------------------------------------------------------------------

func open_attack_sheet(region_idx: int) -> void:
	var sim = Game.sim
	var need: int = sim.preview_attack(region_idx, 1).needed
	_attack_count = mini(need, floori(sim.soldiers + 1e-6)) if sim.soldiers >= 1.0 else need
	_attack_mode = "Occupy"
	_open_sheet(_attack_sheet.bind(region_idx))


func _attack_sheet(region_idx: int) -> void:
	var sim = Game.sim
	var reg: Dictionary = sim.region(region_idx)
	_sheet_title("Attack %s" % reg.name)
	var home := floori(sim.soldiers + 1e-6)
	_attack_count = clampi(_attack_count, 0, maxi(home, _attack_count))
	var p: Dictionary = sim.preview_attack(region_idx, maxi(1, _attack_count))

	var steps := HBoxContainer.new()
	steps.add_theme_constant_override("separation", 4)
	for d in [-10, -1, 1, 10]:
		var bt := Button.new()
		bt.text = "%+d" % d
		bt.custom_minimum_size = Vector2(44, 40)
		bt.pressed.connect(func():
			_attack_count = maxi(0, _attack_count + d)
			_rebuild_sheet())
		steps.add_child(bt)
	var count_l := Look.label("  %d" % _attack_count, Look.FONT_TITLE)
	count_l.name = "count"
	count_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	steps.add_child(count_l)
	_sheet_box.add_child(steps)

	var quick := HBoxContainer.new()
	quick.add_theme_constant_override("separation", 4)
	for pair in [["Needed %d" % p.needed, p.needed], ["All %d" % home, home]]:
		var qb := Button.new()
		qb.text = pair[0]
		qb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		qb.custom_minimum_size = Vector2(0, 36)
		var n: int = pair[1]
		qb.pressed.connect(func():
			_attack_count = n
			_rebuild_sheet())
		quick.add_child(qb)
	_sheet_box.add_child(quick)

	var outcome := "WIN" if p.attacker_wins else "LOSS"
	var lines: PackedStringArray = [
		"Attack %s vs defense %s (×%.2f)" % [Look.num(p.attack), Look.num(p.defense), p.ratio],
		"%s · battle %.1f min" % [outcome, p.minutes],
	]
	if p.attacker_wins:
		lines.append("%s survive, %s stay as garrison" % [Look.num(p.survivors), Look.num(p.stay)])
	else:
		lines.append("All attackers lost; %s defenders left" % Look.num(p.survivors))
	var pv := Look.label("\n".join(lines), Look.FONT_SIZE, Look.ACCENT if p.attacker_wins else Look.BAD)
	pv.name = "preview"
	_sheet_box.add_child(pv)

	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 4)
	for m in ["Occupy", "Raze"]:
		var mb := Button.new()
		mb.name = "mode_" + m.to_lower()
		mb.text = m
		mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mb.custom_minimum_size = Vector2(0, 36)
		if _attack_mode == m:
			mb.add_theme_color_override("font_color", Look.ACCENT)
			mb.add_theme_stylebox_override("normal", Look.flat_box(Look.PANEL_HI, Look.ACCENT, 1, 6))
		mb.pressed.connect(func():
			_attack_mode = m
			_rebuild_sheet())
		modes.add_child(mb)
	_sheet_box.add_child(modes)
	var why := ""
	if _attack_mode == "Occupy":
		why = "Keep %d of %d buildings free. The rest are torn down for your plan." % [p.kept, reg.slots]
	else:
		why = "Salvage %s. Citizens and gold -%d%% until your next capture. Annexing gets %d%% slower." % [
			Look.cost(p.salvage), roundi(sim.b.num("raze_output_penalty") * 100), roundi(sim.b.num("raze_relations_damage") * 100)]
	var wl := Look.label(why, Look.FONT_SMALL, Look.DIM)
	wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sheet_box.add_child(wl)

	var blocker: String = sim.attack_blocker(region_idx, _attack_count)
	var go := Button.new()
	go.name = "go"
	go.custom_minimum_size = Vector2(0, 44)
	go.text = blocker if blocker != "" else "Send %d soldiers" % _attack_count
	go.disabled = blocker != ""
	go.pressed.connect(func():
		if Game.cmd_attack(region_idx, _attack_count, _attack_mode):
			close_sheet())
	_sheet_box.add_child(go)


# --- army ---------------------------------------------------------------------

func _army_sheet() -> void:
	var sim = Game.sim
	_sheet_title("Army")
	var away := 0.0
	for battle in sim.battles:
		away += battle.soldiers
	_sheet_box.add_child(Look.label("%s at home · %s in battle" % [Look.num(sim.soldiers), Look.num(away)]))
	var r: Dictionary = sim.rates()
	var limit := "nothing"
	for k in ["citizens", "equipment", "rations"]:
		if sim.res[k] < 1.0:
			limit = k
			break
	var info := Look.label("Barracks train up to %s. Each soldier takes 1 citizen, 1 equipment, 1 ration. Short on: %s." % [Look.rate(r.barracks_cap), limit], Look.FONT_SMALL, Look.DIM)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sheet_box.add_child(info)

	_sheet_box.add_child(Look.label("Keep this many soldiers at home:", Look.FONT_SIZE))
	var steps := HBoxContainer.new()
	steps.add_theme_constant_override("separation", 4)
	for d in [-50, -10, 10, 50]:
		var bt := Button.new()
		bt.text = "%+d" % d
		bt.custom_minimum_size = Vector2(44, 40)
		bt.pressed.connect(func(): Game.cmd_train_target(int(sim.train_target) + d))
		steps.add_child(bt)
	var t := Look.label("  %d" % int(sim.train_target), Look.FONT_TITLE)
	t.name = "target"
	steps.add_child(t)
	_sheet_box.add_child(steps)

	for reg in sim.regions:
		if sim.owns(reg.index) or sim.attack_blocker(reg.index, 1) == "Not on your border" or sim.battle_at(reg.index).size() > 0:
			continue
		var need: int = sim.preview_attack(reg.index, 1).needed
		var btn := _row_button(null, "Train for %s" % reg.name, "Garrison %s" % Look.num(reg.garrison), "%d needed" % need,
			func(): Game.cmd_train_target(need))
		btn.name = "train_for_%d" % reg.index
		_sheet_box.add_child(btn)


# --- while you were away ------------------------------------------------------

func _away_sheet(summary: Dictionary) -> void:
	var secs := int(summary.seconds)
	_sheet_title("While you were away")
	_sheet_box.add_child(Look.label("%dh %02dm passed." % [secs / 3600, (secs / 60) % 60], Look.FONT_SIZE, Look.DIM))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	for k in ["citizens", "food", "metal", "fuel", "gold", "rations", "equipment", "soldiers"]:
		var v: float = summary.gained.get(k, 0.0)
		if absf(v) < 0.5:
			continue
		grid.add_child(Look.label(k.capitalize(), Look.FONT_SIZE, Look.RESOURCE_COLORS.get(k, Look.TEXT)))
		grid.add_child(Look.label(("+" if v > 0.0 else "") + Look.num(v)))
	_sheet_box.add_child(grid)
	for e in summary.events:
		if e.kind == "info":
			continue
		var l := Look.label(e.text, Look.FONT_SMALL, Look.BAD if e.kind == "battle_lost" else Look.ACCENT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_sheet_box.add_child(l)
	_seen_events = Game.sim.events.size()   # already shown here, no toasts


# --- diplomacy ----------------------------------------------------------------

func _diplomacy_sheet() -> void:
	var sim = Game.sim
	_sheet_title("Diplomacy")
	var any := false
	for civ_name in sim.civs:
		if sim.civ_absorbed(civ_name):
			continue
		any = true
		var civ: Dictionary = sim.civs[civ_name]
		var color: Color = Look.OWNER_COLORS.get(civ_name, Look.TEXT)
		var left := 0
		for i in range(civ.first, civ.last + 1):
			if not sim.owns(i):
				left += 1
		_sheet_box.add_child(Look.label("%s · %d regions left · size %s" % [civ_name, left, Look.num(sim.civ_size(civ_name))], Look.FONT_SIZE, color))
		if civ.trade:
			_sheet_box.add_child(Look.label("Trade partner: market fee -%d%%, talks %d%% faster" % [
				roundi(sim.b.num("trade_fee_cut_per_partner") * 100), roundi(sim.b.num("trade_relations_cut") * 100)], Look.FONT_SMALL, Look.ACCENT))
		else:
			var tb := _row_button(null, "Sign trade rights", "Market fee -%d%% · annexation talks %d%% faster" % [
				roundi(sim.b.num("trade_fee_cut_per_partner") * 100), roundi(sim.b.num("trade_relations_cut") * 100)],
				Look.cost({"gold": sim.b.num("trade_signing_fee")}), func(): Game.cmd_sign_trade(civ_name))
			tb.name = "trade_" + civ_name.split(" ")[0].to_lower()
			_sheet_box.add_child(tb)
		for i in range(civ.first, civ.last + 1):
			if sim.owns(i):
				continue
			var reg: Dictionary = sim.region(i)
			var talk: Dictionary = {}
			for a in sim.annexes:
				if a.region == i:
					talk = a
			var sub := ""
			if talk.is_empty():
				sub = "Talks %d min · then %s gold" % [roundi(sim.relations_hours(i) * 60.0), Look.num(sim.annex_gold(i))]
			else:
				var mins := maxf(0.0, talk.ends_at - sim.hours) * 60.0
				sub = ("Talks %d min left" % ceili(mins) if mins > 0.0 else "Talks done") + (" · gold paid" if talk.paid else " · waiting for gold")
			var blocker: String = sim.annex_blocker(i)
			var idx: int = i
			var ab := _row_button(null, "Annex %s" % reg.name, sub, "" if blocker == "" else blocker,
				func(): Game.cmd_annex(idx), blocker != "")
			ab.name = "annex_%d" % i
			_sheet_box.add_child(ab)
	if not any:
		_sheet_box.add_child(Look.label("Every civilization on the planet is yours.", Look.FONT_SMALL, Look.DIM))


# --- market -------------------------------------------------------------------

const TRADE_LOT := 100.0
const TRADED := ["food", "metal", "fuel", "rations", "equipment"]


func _market_sheet() -> void:
	var sim = Game.sim
	_sheet_title("Market")
	var info := Look.label("You keep %d%% of every sale after the fee. Big trades move the price; it recovers %d%% an hour. %d%% of spare food sells by itself." % [
		roundi(sim.sale_keep() * 100), roundi(sim.b.num("market_recovery_per_hr") * 100), roundi(sim.b.num("food_sell_share") * 100)], Look.FONT_SMALL, Look.DIM)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sheet_box.add_child(info)
	for r in TRADED:
		var m: Dictionary = sim.market[r]
		var flow: float = sim._food_flow() if r == "food" else 0.0
		var price: float = sim.market_price(r, flow)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row.add_child(Icon.make(Look.RESOURCE_COLORS[r], r.left(1).to_upper(), 1))
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 0)
		col.add_child(Look.label("%s %.2f g (%+d%%)" % [r.capitalize(), price, roundi((price / m.base - 1.0) * 100)]))
		col.add_child(Look.label("have %s" % Look.num(sim.res[r]), Look.FONT_SMALL, Look.DIM))
		row.add_child(col)
		var sell_g: float = sim.quote_sell(r, TRADE_LOT)
		var buy_g: float = sim.quote_buy(r, TRADE_LOT)
		var sb := Button.new()
		sb.name = "sell_" + r
		sb.text = "Sell 100\n+%s g" % Look.num(sell_g)
		sb.custom_minimum_size = Vector2(76, 36)
		sb.disabled = sim.res[r] < TRADE_LOT
		sb.pressed.connect(func(): Game.cmd_sell(r, TRADE_LOT))
		row.add_child(sb)
		var bb := Button.new()
		bb.name = "buy_" + r
		bb.text = "Buy 100\n-%s g" % Look.num(buy_g)
		bb.custom_minimum_size = Vector2(76, 36)
		bb.disabled = sim.res.gold < buy_g
		bb.pressed.connect(func(): Game.cmd_buy(r, TRADE_LOT))
		row.add_child(bb)
		_sheet_box.add_child(row)


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
