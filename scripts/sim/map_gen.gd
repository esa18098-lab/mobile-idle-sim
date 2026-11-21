extends RefCounted
## Procedural home-planet map. Pure data and deterministic: the same seed always
## gives the same map, so a save only needs the seed.
##
## The map is a grid of cells (pixel-art friendly). A noisy island is cut from
## the sea, 12 seed points are spread across it, and territories grow outward
## from them over noisy ground, which makes the wobbly borders. The sheet's 12
## regions are then placed onto the territories so that:
##   - the capital sits at the south of the island,
##   - every region on the default path borders one taken before it
##     (region k touches some region < k), so the sheet's order always works,
##   - each civilization's land is one connected territory,
##   - regions are placed outward from the capital, so the later (stronger) a
##     region is, the further from home it sits; the last civilization never
##     borders the capital and the last region is as far away as any.
## Maps that can't meet that are thrown away and drawn again with the next seed.
##
## Geography: an elevation field (high in the middle, falling to the sea), a
## temperature gradient (cold north, hot south) and a moisture field give each
## cell a biome. Lakes sit in low basins and are water, so regions on opposite
## shores don't border. Rivers run downhill from the highlands to the sea or a
## lake. Growth is slower across rivers and ridges, so territories tend to end
## there and those become borders. A region's biome is the one most of its
## land has; it sets the region's terrain (defense, production).

const W := 58          ## cells across
const H := 72          ## cells down
const SEA := 0

## water[] values
const LAND := 0
const OCEAN := 1
const LAKE := 2

const BIOMES: PackedStringArray = ["Plains", "Forest", "Hills", "Mountains", "Tundra", "Coast", "Desert"]

## regions: [{index, civ}] from the balance data, capital = index 1.
static func generate(seed: int, regions: Array) -> Dictionary:
	for attempt in 50:
		var m := _try(seed + attempt * 7919, regions)
		if not m.is_empty():
			m.seed = seed
			m.attempts = attempt + 1
			return m
	push_error("Map generator failed for seed %d" % seed)
	return {}


static func _try(s: int, regions: Array) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	var f := _fields(s)
	var land := _island(s)
	var lake := _lakes(rng, land, f.elev)
	var river := _rivers(rng, land, lake, f.elev)
	var land_cells: Array = []
	for i in land.size():
		if land[i]:
			land_cells.append(i)
	var n := regions.size()
	if land_cells.size() < n * 110:
		return {}

	var seeds := _spread_seeds(rng, land_cells, n)
	var owner := _grow(s, land, seeds, [], river, f.elev)
	var adj := _adjacency(owner, n)
	if not _shapes_ok(owner, adj, n):
		return {}

	# Which territory holds which sheet region.
	var order := _assign(rng, adj, seeds, regions)
	if order.is_empty():
		return {}

	# Regrow with bigger regions claiming more ground (by slot count), and keep
	# it if the rules still hold.
	var weights: Array = []
	for t in n:
		weights.append(sqrt(float(regions[order.find(t)].slots) / 5.5))
	var owner2 := _grow(s, land, seeds, weights, river, f.elev)
	var adj2 := _adjacency(owner2, n)
	if _shapes_ok(owner2, adj2, n) and _rules_hold(adj2, order, regions) and _far_enough(order, _hops(adj2, order[0]), regions):
		owner = owner2
		adj = adj2

	# Relabel cells with sheet region indexes (1..n); 0 is water.
	var cells := PackedInt32Array()
	cells.resize(W * H)
	var water := PackedByteArray()
	water.resize(W * H)
	var rivers := PackedByteArray()
	rivers.resize(W * H)
	for i in W * H:
		cells[i] = SEA if owner[i] < 0 else regions[order.find(owner[i])].index
		water[i] = LAKE if lake[i] else (OCEAN if owner[i] < 0 else LAND)
		rivers[i] = 1 if river[i] and owner[i] >= 0 else 0
	var by_region := {}
	for t in n:
		var idx: int = regions[order.find(t)].index
		by_region[idx] = []
		for other in adj[t]:
			by_region[idx].append(regions[order.find(other)].index)
		by_region[idx].sort()
	var biome := _region_biomes(cells, water, f, regions)
	if not _biomes_ok(biome):
		return {}
	return {"w": W, "h": H, "cells": cells, "water": water, "river": rivers,
		"trees": _trees(cells, water, rivers, f, biome),
		"adjacency": by_region, "anchors": _anchors(cells, regions),
		"biome": biome, "river_share": _river_shares(cells, rivers),
		"lakes": _count_lakes(water), "rivers": _count_rivers(rivers)}


# --- fields -------------------------------------------------------------------

## Elevation (0..1, highest inland), temperature (0 north .. 1 south) and moisture.
static func _fields(s: int) -> Dictionary:
	var en := FastNoiseLite.new()
	en.seed = s + 11
	en.frequency = 0.05
	en.fractal_octaves = 4
	var tn := FastNoiseLite.new()
	tn.seed = s + 12
	tn.frequency = 0.04
	var mn := FastNoiseLite.new()
	mn.seed = s + 13
	mn.frequency = 0.045
	mn.fractal_octaves = 3
	var elev := PackedFloat32Array()
	var temp := PackedFloat32Array()
	var moist := PackedFloat32Array()
	elev.resize(W * H)
	temp.resize(W * H)
	moist.resize(W * H)
	for y in H:
		for x in W:
			var dx := (x - W * 0.5) / (W * 0.5)
			var dy := (y - H * 0.5) / (H * 0.5)
			var inland := 1.0 - clampf(sqrt(dx * dx + dy * dy), 0.0, 1.0)
			var i := y * W + x
			elev[i] = clampf(inland * 0.75 + (en.get_noise_2d(x, y) + 1.0) * 0.35 - 0.1, 0.0, 1.0)
			temp[i] = clampf(float(y) / H * 0.9 + tn.get_noise_2d(x, y) * 0.35 + 0.05, 0.0, 1.0)
			moist[i] = clampf((mn.get_noise_2d(x, y) + 1.0) * 0.5, 0.0, 1.0)
	return {"elev": elev, "temp": temp, "moist": moist}


# --- island ------------------------------------------------------------------

static func _island(s: int) -> Array:
	var noise := FastNoiseLite.new()
	noise.seed = s
	noise.frequency = 0.06
	noise.fractal_octaves = 3
	var land: Array = []
	land.resize(W * H)
	for y in H:
		for x in W:
			var dx := (x - W * 0.5) / (W * 0.47)
			var dy := (y - H * 0.5) / (H * 0.47)
			var d := dx * dx + dy * dy
			land[y * W + x] = d + noise.get_noise_2d(x, y) * 0.55 < 0.82
	# Keep only the biggest piece of land: no stray islets.
	var comp := _largest_component(land)
	for i in land.size():
		land[i] = land[i] and comp[i]
	return land


static func _largest_component(land: Array) -> Array:
	var seen: Array = []
	seen.resize(W * H)
	seen.fill(false)
	var best: Array = []
	for start in W * H:
		if not land[start] or seen[start]:
			continue
		var comp: Array = [start]
		seen[start] = true
		var head := 0
		while head < comp.size():
			var c: int = comp[head]
			head += 1
			for nb in _neighbours4(c):
				if land[nb] and not seen[nb]:
					seen[nb] = true
					comp.append(nb)
		if comp.size() > best.size():
			best = comp
	var keep: Array = []
	keep.resize(W * H)
	keep.fill(false)
	for c in best:
		keep[c] = true
	return keep


# --- lakes and rivers -------------------------------------------------------------

## One to three lakes in low inland basins. A lake that would cut the land in two
## is dropped. Lake cells stop being land.
static func _lakes(rng: RandomNumberGenerator, land: Array, elev: PackedFloat32Array) -> Array:
	var lake: Array = []
	lake.resize(W * H)
	lake.fill(false)
	var want := rng.randi_range(1, 3)
	var made := 0
	for attempt in 40:
		if made >= want:
			break
		var c := rng.randi_range(0, W * H - 1)
		if not land[c] or _near_sea(land, c, 5) or elev[c] > 0.62:
			continue
		var size := rng.randi_range(14, 34)
		var blob: Array = [c]
		var in_blob := {c: true}
		while blob.size() < size:
			var from: int = blob[rng.randi_range(0, blob.size() - 1)]
			var nbs := _neighbours4(from)
			var nb: int = nbs[rng.randi_range(0, nbs.size() - 1)]
			if land[nb] and not in_blob.has(nb) and not _near_sea(land, nb, 3):
				blob.append(nb)
				in_blob[nb] = true
			elif rng.randf() < 0.05:
				break
		if blob.size() < 10:
			continue
		for b in blob:
			land[b] = false
		if _connected(land):
			for b in blob:
				lake[b] = true
			made += 1
		else:
			for b in blob:
				land[b] = true
	return lake


## Rivers start high and run downhill to the sea or a lake.
static func _rivers(rng: RandomNumberGenerator, land: Array, lake: Array, elev: PackedFloat32Array) -> Array:
	var river: Array = []
	river.resize(W * H)
	river.fill(false)
	var want := rng.randi_range(2, 4)
	var made := 0
	for attempt in 60:
		if made >= want:
			break
		var c := rng.randi_range(0, W * H - 1)
		if not land[c] or river[c] or elev[c] < 0.62 or _near_river(river, c, 6):
			continue
		var path: Array = [c]
		var seen := {c: true}
		var reached := false
		while path.size() < 90:
			var cur: int = path[-1]
			var best := -1
			var best_e := INF
			for nb in _neighbours4(cur):
				if seen.has(nb):
					continue
				var e := elev[nb] + rng.randf() * 0.04
				if e < best_e:
					best_e = e
					best = nb
			if best < 0:
				break
			if not land[best] or river[best]:
				reached = true   # sea, lake, or joined another river
				break
			path.append(best)
			seen[best] = true
		if reached and path.size() >= 9:
			for p in path:
				river[p] = true
			made += 1
	return river


static func _near_sea(land: Array, c: int, r: int) -> bool:
	var cx := c % W
	var cy := c / W
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			if x < 0 or y < 0 or x >= W or y >= H or not land[y * W + x]:
				return true
	return false


static func _near_river(river: Array, c: int, r: int) -> bool:
	var cx := c % W
	var cy := c / W
	for y in range(maxi(0, cy - r), mini(H, cy + r + 1)):
		for x in range(maxi(0, cx - r), mini(W, cx + r + 1)):
			if river[y * W + x]:
				return true
	return false


static func _connected(land: Array) -> bool:
	var total := 0
	var start := -1
	for i in land.size():
		if land[i]:
			total += 1
			start = i
	if start < 0:
		return false
	var seen := {start: true}
	var q: Array = [start]
	var head := 0
	while head < q.size():
		var c: int = q[head]
		head += 1
		for nb in _neighbours4(c):
			if land[nb] and not seen.has(nb):
				seen[nb] = true
				q.append(nb)
	return seen.size() == total


# --- biomes ---------------------------------------------------------------------

static func cell_biome(elev: float, temp: float, moist: float) -> String:
	if elev > 0.80:
		return "Mountains"
	if elev > 0.66:
		return "Hills"
	if temp < 0.22:
		return "Tundra"
	if temp > 0.56 and moist < 0.46:
		return "Desert"
	if moist > 0.53:
		return "Forest"
	return "Plains"


## A region's biome is the one most of its land has. Low land along a long
## shore is Coast. The capital is always Plains: your homeland is farmland.
static func _region_biomes(cells: PackedInt32Array, water: PackedByteArray, f: Dictionary, regions: Array) -> Dictionary:
	var votes := {}
	var shore := {}
	var area := {}
	for i in W * H:
		var r: int = cells[i]
		if r == SEA:
			continue
		var b := cell_biome(f.elev[i], f.temp[i], f.moist[i])
		if not votes.has(r):
			votes[r] = {}
			shore[r] = 0
			area[r] = 0
		votes[r][b] = votes[r].get(b, 0) + 1
		area[r] += 1
		for nb in _neighbours4(i):
			if water[nb] == OCEAN:
				shore[r] += 1
				break
	var out := {}
	for r in votes:
		var best := ""
		for b in votes[r]:
			if best == "" or votes[r][b] > votes[r][best]:
				best = b
		if best in ["Plains", "Forest", "Desert"] and float(shore[r]) / area[r] > 0.17:
			best = "Coast"
		out[r] = best
	out[regions[0].index] = "Plains"
	return out


## Variety without extremes: at least four biomes, at most three mountain regions.
static func _biomes_ok(biome: Dictionary) -> bool:
	var kinds := {}
	var mountains := 0
	for r in biome:
		kinds[biome[r]] = true
		if biome[r] == "Mountains":
			mountains += 1
	return kinds.size() >= 4 and mountains <= 3


## Decoration: tree cells in wet places (forest regions are thick with them).
static func _trees(cells: PackedInt32Array, water: PackedByteArray, rivers: PackedByteArray, f: Dictionary, biome: Dictionary) -> PackedByteArray:
	var t := PackedByteArray()
	t.resize(W * H)
	for i in W * H:
		if cells[i] == SEA or rivers[i] == 1:
			continue
		var b: String = biome[cells[i]]
		var m: float = f.moist[i]
		if b == "Forest" and m > 0.45:
			t[i] = 1
		elif b in ["Plains", "Hills", "Coast"] and m > 0.62:
			t[i] = 1
	return t


## For each pair of bordering regions, the share of their border that runs
## along a river ("a,b" with a < b).
static func _river_shares(cells: PackedInt32Array, rivers: PackedByteArray) -> Dictionary:
	var total := {}
	var wet := {}
	for i in W * H:
		var a: int = cells[i]
		if a == SEA:
			continue
		for nb in _neighbours4(i):
			var bb: int = cells[nb]
			if bb == SEA or bb <= a:
				continue
			var key := "%d,%d" % [a, bb]
			total[key] = total.get(key, 0) + 1
			if rivers[i] == 1 or rivers[nb] == 1:
				wet[key] = wet.get(key, 0) + 1
	var out := {}
	for k in total:
		out[k] = float(wet.get(k, 0)) / total[k]
	return out


static func _count_lakes(water: PackedByteArray) -> int:
	var seen := {}
	var n := 0
	for i in W * H:
		if water[i] != LAKE or seen.has(i):
			continue
		n += 1
		var q: Array = [i]
		seen[i] = true
		while not q.is_empty():
			var c: int = q.pop_back()
			for nb in _neighbours4(c):
				if water[nb] == LAKE and not seen.has(nb):
					seen[nb] = true
					q.append(nb)
	return n


static func _count_rivers(rivers: PackedByteArray) -> int:
	var n := 0
	for v in rivers:
		n += v
	return n


# --- territories -----------------------------------------------------------------

## Best-candidate sampling: each new seed is the one of a handful of random
## land cells that sits furthest from the seeds already placed.
static func _spread_seeds(rng: RandomNumberGenerator, land_cells: Array, n: int) -> Array:
	var seeds: Array = [land_cells[rng.randi_range(0, land_cells.size() - 1)]]
	while seeds.size() < n:
		var best := -1
		var best_d := -1.0
		for k in 24:
			var c: int = land_cells[rng.randi_range(0, land_cells.size() - 1)]
			var d := INF
			for sd in seeds:
				d = minf(d, _dist2(c, sd))
			if d > best_d:
				best_d = d
				best = c
		seeds.append(best)
	return seeds


## Multi-source growth over noisy ground (Dijkstra). weights > 1 grow faster.
## Crossing a river or climbing a ridge is slow, so borders tend to form there.
static func _grow(s: int, land: Array, seeds: Array, weights: Array, river: Array, elev: PackedFloat32Array) -> Array:
	var rough := FastNoiseLite.new()
	rough.seed = s + 1
	rough.frequency = 0.18
	var owner: Array = []
	owner.resize(W * H)
	owner.fill(-1)
	var cost: Array = []
	cost.resize(W * H)
	cost.fill(INF)
	var heap := _Heap.new()
	for t in seeds.size():
		cost[seeds[t]] = 0.0
		owner[seeds[t]] = t
		heap.push(0.0, seeds[t])
	while not heap.empty():
		var top := heap.pop()
		var c: int = top[1]
		if top[0] > cost[c]:
			continue
		var t: int = owner[c]
		var speed: float = weights[t] if not weights.is_empty() else 1.0
		for nb in _neighbours4(c):
			if not land[nb]:
				continue
			var step := (1.0 + 1.4 * (rough.get_noise_2d(nb % W, nb / W) + 1.0)) / speed
			if river[nb] != river[c]:
				step += 9.0
			step += maxf(0.0, elev[nb] - elev[c]) * 40.0
			var nc: float = cost[c] + step
			if nc < cost[nb]:
				cost[nb] = nc
				owner[nb] = t
				heap.push(nc, nb)
	return owner


static func _adjacency(owner: Array, n: int) -> Array:
	var adj: Array = []
	for t in n:
		adj.append([])
	for c in W * H:
		var a: int = owner[c]
		if a < 0:
			continue
		for nb in _neighbours4(c):
			var bb: int = owner[nb]
			if bb >= 0 and bb != a and not (bb in adj[a]):
				adj[a].append(bb)
	return adj


## No slivers, no giants, every territory touches another, and each is one piece.
static func _shapes_ok(owner: Array, adj: Array, n: int) -> bool:
	var area: Array = []
	area.resize(n)
	area.fill(0)
	for c in owner:
		if c >= 0:
			area[c] += 1
	var mean := 0.0
	for a in area:
		mean += a
	mean /= n
	for t in n:
		if area[t] < mean * 0.4 or area[t] > mean * 2.4 or adj[t].is_empty():
			return false
	return true


# --- placing the sheet's regions ---------------------------------------------

## Returns order[i] = territory for regions[i], or [] if the rules can't be met.
static func _assign(rng: RandomNumberGenerator, adj: Array, seeds: Array, regions: Array) -> Array:
	var n := regions.size()
	# The capital is the territory furthest south.
	var capital := 0
	for t in n:
		if seeds[t] / W > seeds[capital] / W:
			capital = t
	var dist := _hops(adj, capital)
	for tries in 80:
		var order: Array = []
		order.resize(n)
		order.fill(-1)
		var used := {capital: true}
		order[0] = capital
		var ok := true
		for i in range(1, n):
			var civ: String = regions[i].civ
			var cand: Array = []
			for t in n:
				if used.has(t):
					continue
				var touches_earlier := false
				var touches_own_civ := false
				var own_civ_started := false
				for j in i:
					if regions[j].civ == civ:
						own_civ_started = true
					if order[j] in adj[t]:
						touches_earlier = true
						if regions[j].civ == civ:
							touches_own_civ = true
				if touches_earlier and (touches_own_civ or not own_civ_started):
					cand.append(t)
			if cand.is_empty():
				ok = false
				break
			# Outward from the capital: take the nearest candidates first.
			var nearest := 999
			for t in cand:
				nearest = mini(nearest, dist[t])
			cand = cand.filter(func(t): return dist[t] == nearest)
			var pick: int = cand[rng.randi_range(0, cand.size() - 1)]
			order[i] = pick
			used[pick] = true
		if ok and _far_enough(order, dist, regions):
			return order
	return []


## The last civilization stays off the capital's border, and the last region
## is as far from home as any.
static func _far_enough(order: Array, dist: Array, regions: Array) -> bool:
	var last_civ: String = regions[-1].civ
	var furthest := 0
	for t in order:
		furthest = maxi(furthest, dist[t])
	if dist[order[-1]] < furthest:
		return false
	for i in regions.size():
		if regions[i].civ == last_civ and dist[order[i]] < 2:
			return false
	return true


## Steps from the capital's territory to every other, across borders.
static func _hops(adj: Array, start: int) -> Array:
	var dist: Array = []
	dist.resize(adj.size())
	dist.fill(999)
	dist[start] = 0
	var q: Array = [start]
	var head := 0
	while head < q.size():
		var t: int = q[head]
		head += 1
		for nb in adj[t]:
			if dist[nb] > dist[t] + 1:
				dist[nb] = dist[t] + 1
				q.append(nb)
	return dist


static func _rules_hold(adj: Array, order: Array, regions: Array) -> bool:
	for i in range(1, regions.size()):
		var t: int = order[i]
		var touches_earlier := false
		var touches_own_civ := false
		var own_civ_started := false
		for j in i:
			if regions[j].civ == regions[i].civ:
				own_civ_started = true
			if order[j] in adj[t]:
				touches_earlier = true
				if regions[j].civ == regions[i].civ:
					touches_own_civ = true
		if not touches_earlier or (own_civ_started and not touches_own_civ):
			return false
	return true


## For each region, the cell deepest inside it: where its label and arrows go.
static func _anchors(cells: PackedInt32Array, regions: Array) -> Dictionary:
	var dist: Array = []
	dist.resize(W * H)
	dist.fill(-1)
	var queue: Array = []
	for c in W * H:
		if cells[c] == SEA:
			continue
		var edge := false
		var x := c % W
		var y := c / W
		if x == 0 or y == 0 or x == W - 1 or y == H - 1:
			edge = true
		else:
			for nb in _neighbours4(c):
				if cells[nb] != cells[c]:
					edge = true
		if edge:
			dist[c] = 0
			queue.append(c)
	var head := 0
	while head < queue.size():
		var c: int = queue[head]
		head += 1
		for nb in _neighbours4(c):
			if cells[nb] == cells[c] and dist[nb] < 0:
				dist[nb] = dist[c] + 1
				queue.append(nb)
	var best := {}
	for c in W * H:
		var r: int = cells[c]
		if r == SEA:
			continue
		if not best.has(r) or dist[c] > dist[best[r]]:
			best[r] = c
	var out := {}
	for r in best:
		out[r] = Vector2i(best[r] % W, best[r] / W)
	return out


# --- helpers -------------------------------------------------------------------

static func _neighbours4(c: int) -> Array:
	var x := c % W
	var y := c / W
	var out: Array = []
	if x > 0: out.append(c - 1)
	if x < W - 1: out.append(c + 1)
	if y > 0: out.append(c - W)
	if y < H - 1: out.append(c + W)
	return out


static func _dist2(a: int, b: int) -> float:
	var dx := float(a % W - b % W)
	var dy := float(a / W - b / W)
	return dx * dx + dy * dy


## A small binary min-heap of [priority, item].
class _Heap:
	var pri: Array = []
	var item: Array = []

	func empty() -> bool:
		return pri.is_empty()

	func push(p: float, v: int) -> void:
		pri.append(p)
		item.append(v)
		var i := pri.size() - 1
		while i > 0:
			var parent := (i - 1) / 2
			if pri[parent] <= pri[i]:
				break
			_swap(i, parent)
			i = parent

	func pop() -> Array:
		var top := [pri[0], item[0]]
		var last := pri.size() - 1
		_swap(0, last)
		pri.pop_back()
		item.pop_back()
		var i := 0
		while true:
			var l := 2 * i + 1
			var r := l + 1
			var m := i
			if l < pri.size() and pri[l] < pri[m]: m = l
			if r < pri.size() and pri[r] < pri[m]: m = r
			if m == i:
				break
			_swap(i, m)
			i = m
		return top

	func _swap(a: int, b: int) -> void:
		var tp = pri[a]; pri[a] = pri[b]; pri[b] = tp
		var ti = item[a]; item[a] = item[b]; item[b] = ti
