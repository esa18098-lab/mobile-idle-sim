extends Control
## The planet as a pixel map: territories with terrain textures, your land
## bright and theirs shaded in their colours, borders, names and garrisons.
## Battles draw a marching arrow from your region into theirs; raids come the
## other way in red; captured regions flash. Tap a territory to open it.

const Look := preload("res://scripts/ui/look.gd")
const Sim := preload("res://scripts/sim/sim.gd")

signal region_tapped(region_idx: int)

const CELL := 6            ## screen pixels per map cell
const TILE := 24           ## terrain pattern size (tileable)
const SEA := Color("#14304a")
const SEA_LIGHT := Color("#22476a")
const FOAM := Color("#cfe3ea")
const LINE := Color("#0d1015")
const FLASH_SECONDS := 0.9

var _tex: ImageTexture
var _owner_key := ""
var _map_seed := -1
var _patterns := {}        ## "terrain|owner" -> Image
var _flash := {}           ## region -> seconds left
var _seen_events := 0
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(Sim.MapGen.W * CELL, Sim.MapGen.H * CELL)
	_seen_events = Game.sim.events.size()
	rebuild()


## Redraws the map image if the map or anyone's borders changed.
func rebuild() -> void:
	var sim = Game.sim
	var key := ",".join(sim.regions.map(func(r): return r.owner))
	if _tex != null and key == _owner_key and sim.map_seed == _map_seed:
		queue_redraw()
		return
	_owner_key = key
	_map_seed = sim.map_seed
	_tex = ImageTexture.create_from_image(_render(sim))
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	var sim = Game.sim
	if _seen_events > sim.events.size():
		_seen_events = 0
	while _seen_events < sim.events.size():
		var e: Dictionary = sim.events[_seen_events]
		_seen_events += 1
		if e.kind in ["captured", "annexed", "raid_lost"]:
			_flash[e.region] = FLASH_SECONDS
	for r in _flash.keys():
		_flash[r] -= delta
		if _flash[r] <= 0.0:
			_flash.erase(r)
	if not sim.battles.is_empty() or not sim.npc_raids.is_empty() or not _flash.is_empty() or not sim.annexes.is_empty():
		queue_redraw()


func refresh_live() -> void:
	rebuild()


# =============================================================================
# The map image
# =============================================================================

func _origin() -> Vector2:
	var map_px := Vector2(Sim.MapGen.W * CELL, Sim.MapGen.H * CELL)
	return ((size - map_px) * 0.5).floor()


func _render(sim) -> Image:
	var W: int = sim.map.w
	var H: int = sim.map.h
	var cells: PackedInt32Array = sim.map.cells
	var img := Image.create(W * CELL, H * CELL, false, Image.FORMAT_RGBA8)
	var sea := _pattern("sea", "")
	for y in H:
		for x in W:
			var r: int = cells[y * W + x]
			var src: Image = sea
			if r != 0:
				var reg: Dictionary = sim.region(r)
				src = _pattern(reg.terrain, reg.owner)
			img.blit_rect(src, Rect2i((x * CELL) % TILE, (y * CELL) % TILE, CELL, CELL), Vector2i(x * CELL, y * CELL))
	# Borders and shoreline, drawn on each cell's own side of the edge.
	for y in H:
		for x in W:
			var r: int = cells[y * W + x]
			if r == 0:
				continue
			var mine: Color = _owner_color(sim, r)
			var px := x * CELL
			var py := y * CELL
			for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				var other := 0 if nx < 0 or ny < 0 or nx >= W or ny >= H else cells[ny * W + nx]
				if other == r:
					continue
				var col: Color
				if other == 0:
					col = FOAM
				elif sim.region(other).owner != sim.region(r).owner:
					col = mine          # a frontier: each side shows its owner's colour
				elif d.x < 0 or d.y < 0:
					col = LINE          # same owner: one thin dark line between regions
				else:
					continue
				var rect: Rect2i
				match d:
					Vector2i(-1, 0): rect = Rect2i(px, py, 1, CELL)
					Vector2i(1, 0): rect = Rect2i(px + CELL - 1, py, 1, CELL)
					Vector2i(0, -1): rect = Rect2i(px, py, CELL, 1)
					_: rect = Rect2i(px, py + CELL - 1, CELL, 1)
				img.fill_rect(rect, col)
	return img


func _owner_color(sim, r: int) -> Color:
	return Look.OWNER_COLORS.get(sim.region(r).owner, Look.LINE)


## A tileable 24×24 texture for a terrain, tinted for who holds it.
func _pattern(terrain: String, owner: String) -> Image:
	var key := terrain + "|" + owner
	if _patterns.has(key):
		return _patterns[key]
	var img := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	var base: Color = SEA if terrain == "sea" else Look.TERRAIN_COLORS.get(terrain, Look.PANEL)
	for y in TILE:
		for x in TILE:
			var h := ((x * 73856093) ^ (y * 19349663) ^ (x * y * 83492791)) & 1023
			var c := base
			match terrain:
				"sea":
					if y % 6 == 2 and (x + y) % 12 < 3:
						c = SEA_LIGHT
				"Plains":
					if h % 17 == 0:
						c = base.lightened(0.25)
					elif h % 23 == 0:
						c = base.darkened(0.15)
				"Forest":
					var tx := (x + (y / 6) % 2 * 3) % 6
					var ty := y % 6
					if tx >= 1 and tx <= 3 and ty >= 1 and ty <= 3:
						c = base.darkened(0.3) if ty > 1 else base.lightened(0.15)
				"Hills":
					if y % 6 == 3 and (x + y / 6 * 4) % 8 < 4:
						c = base.lightened(0.22)
					elif y % 6 == 4 and (x + y / 6 * 4) % 8 < 4:
						c = base.darkened(0.2)
				"Mountains":
					var mx := (x + (y / 8) % 2 * 4) % 8
					var my := y % 8
					if my >= 2 and absi(mx - 4) <= my - 2:
						c = Color("#e8ecef") if my == 2 else (base.lightened(0.15) if mx < 4 else base.darkened(0.25))
				"Tundra":
					if h % 9 == 0:
						c = Color("#f2f6f8")
				"Coast":
					if h % 13 == 0:
						c = base.lightened(0.2)
			if terrain != "sea" and owner != "You":
				c = c.lerp(Look.OWNER_COLORS.get(owner, Look.DIM), 0.18).darkened(0.3)
			img.set_pixel(x, y, c)
	_patterns[key] = img
	return img


# =============================================================================
# Drawing: map, names, arrows
# =============================================================================

func _draw() -> void:
	var sim = Game.sim
	draw_rect(Rect2(Vector2.ZERO, size), SEA)
	var o := _origin()
	if _tex:
		draw_texture(_tex, o)
	# Captured regions flash.
	for r in _flash:
		var a := clampf(_flash[r] / FLASH_SECONDS, 0.0, 1.0) * 0.7
		var cells: PackedInt32Array = sim.map.cells
		for i in cells.size():
			if cells[i] == r:
				draw_rect(Rect2(o + Vector2(i % sim.map.w, i / sim.map.w) * CELL, Vector2(CELL, CELL)), Color(1, 1, 1, a))
	# Arrows under the labels.
	for battle in sim.battles:
		var from := _nearest_owned(sim, battle.region)
		if from > 0:
			_arrow(_anchor(sim, from), _anchor(sim, battle.region), Look.ACCENT)
	for raid in sim.npc_raids:
		_arrow(_anchor(sim, raid.from), _anchor(sim, raid.target), Look.BAD)
	for reg in sim.regions:
		_label(sim, reg)


func _anchor(sim, r: int) -> Vector2:
	var a: Vector2i = sim.map.anchors[r]
	return _origin() + (Vector2(a) + Vector2(0.5, 0.5)) * CELL


## Your region on its border closest to it: where the march starts.
func _nearest_owned(sim, target: int) -> int:
	var best := -1
	var best_d := INF
	for n in sim.neighbours(target):
		if sim.owns(n):
			var d := _anchor(sim, n).distance_squared_to(_anchor(sim, target))
			if d < best_d:
				best_d = d
				best = n
	return best


## A dotted arrow with dots marching toward the target.
func _arrow(a: Vector2, b: Vector2, col: Color) -> void:
	var dir := (b - a)
	var length := dir.length()
	if length < 1.0:
		return
	dir /= length
	var stop := length - 12.0          # leave room for the label
	var offset := fmod(_t * 18.0, 6.0)
	var d := 10.0 + offset
	while d < stop:
		var p := (a + dir * d).floor()
		draw_rect(Rect2(p - Vector2(1, 1), Vector2(3, 3)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), col)
		d += 6.0
	var tip := (a + dir * stop).floor()
	var side := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([tip + dir * 5.0, tip - dir * 3.0 + side * 4.0, tip - dir * 3.0 - side * 4.0]), col)


func _label(sim, reg: Dictionary) -> void:
	var font := get_theme_default_font()
	var p := _anchor(sim, reg.index)
	var mine: bool = reg.owner == Sim.PLAYER
	var lines: Array = []
	var words: PackedStringArray = reg.name.to_upper().split(" ")
	lines.append([" ".join(words) if reg.name.length() <= 10 else words[0], Look.TEXT])
	if reg.name.length() > 10 and words.size() > 1:
		lines.append([" ".join(words.slice(1)), Look.TEXT])
	var battle: Dictionary = sim.battle_at(reg.index)
	var raid := {}
	for r in sim.npc_raids:
		if r.target == reg.index:
			raid = r
	if not battle.is_empty():
		lines.append([_clock(battle.ends_at - sim.hours), Look.ACCENT])
	elif not raid.is_empty():
		var t: float = raid.warning_ends_at if raid.battle_ends_at < 0.0 else raid.battle_ends_at
		lines.append(["! " + _clock(t - sim.hours), Look.BAD])
	elif sim.annexing(reg.index):
		var talk: Dictionary = sim.annexes.filter(func(a): return a.region == reg.index)[0]
		lines.append(["TALKS " + _clock(talk.ends_at - sim.hours), Look.OWNER_COLORS["Veyra Compact"]])
	elif mine:
		lines.append(["%d/%d" % [reg.slots - sim.free_slots(reg.index), reg.slots], Look.ACCENT])
	else:
		var border: bool = sim.neighbours(reg.index).any(func(n): return sim.owns(n))
		lines.append(["%s %s" % ["x" if border else "", Look.num(reg.garrison)], Look.ACCENT if border else Look.DIM])
	var y := p.y - lines.size() * 4.0
	for l in lines:
		var w := font.get_string_size(l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, Look.FONT_SIZE).x
		var pos := Vector2(p.x - w * 0.5, y + 6).floor()
		draw_string(font, pos + Vector2(1, 1), l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, Look.FONT_SIZE, Color(0, 0, 0, 0.85))
		draw_string(font, pos, l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, Look.FONT_SIZE, l[1])
		y += 8.0


static func _clock(hours_left: float) -> String:
	var s := int(maxf(0.0, hours_left) * 3600.0)
	return "%d:%02d" % [s / 60, s % 60]


# =============================================================================
# Taps
# =============================================================================

func region_at(local: Vector2) -> int:
	var sim = Game.sim
	var c := ((local - _origin()) / CELL).floor()
	if c.x < 0 or c.y < 0 or c.x >= sim.map.w or c.y >= sim.map.h:
		return 0
	return sim.map.cells[int(c.y) * sim.map.w + int(c.x)]


func _gui_input(e: InputEvent) -> void:
	# Touches arrive as mouse events too (Godot emulates the mouse from touch),
	# so listening to the mouse alone covers phones, browsers and the editor.
	var tapped: bool = e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed
	if tapped:
		var r := region_at(e.position)
		if r > 0:
			region_tapped.emit(r)
			accept_event()
