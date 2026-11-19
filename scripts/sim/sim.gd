extends RefCounted
## The home-planet sim core. Pure GDScript: no scenes, no wall clock.
##
## The caller drives time with advance(hours). Players (the UI, or an
## autoplayer in tests) act only through the command methods. Every rule
## number comes from BalanceData.
##
## State is plain Dictionaries and Arrays so it can be saved as JSON later.

const BalanceData := preload("res://scripts/data/balance_data.gd")
const Combat := preload("res://scripts/sim/combat.gd")

const PLAYER := "You"
const RESOURCES: PackedStringArray = ["citizens", "food", "metal", "fuel", "gold", "rations", "equipment"]
const TICK_HOURS := 1.0 / 3600.0  ## one-second ticks

var b: BalanceData

# --- state -------------------------------------------------------------------
var hours := 0.0
var res := {}                 ## resource -> amount
var soldiers := 0.0           ## soldiers at home, ready to send
var train_target := 0.0       ## barracks and factories work until soldiers reach this
var buildings: Array = []     ## {type, level, region}
var regions: Array = []       ## see _load_regions
var civs := {}                ## name -> {method, trade, first, last, captured}
var queue: Array = []         ## construction and payments, paid in order
var battles: Array = []       ## {region, soldiers, ends_at}
var annexes: Array = []       ## {region, ends_at, paid}
var events: Array = []        ## log of what happened: {hours, text}
var next_id := 1              ## buildings get stable ids: indexes shift on demolish
var razed_count := 0          ## regions razed so far (slows every later annexation)
var raze_penalty := false     ## citizens and gold down until your next capture
var map_pos := {}             ## region -> Vector2i on the map grid; borders come from it
var market := {}              ## resource -> {base, supply, demand, sens, recent}
## `recent` is the player's recent net sales (units/hr equivalent): selling
## pushes prices down, buying pushes them up, and it fades by
## market_recovery_per_hr each hour.

const MAP_PATH := "res://data/maps/home_planet.csv"

# --- derived, cached ---------------------------------------------------------
var _rates_dirty := true
var _rates := {}
var _type_by_name := {}       ## "Factory: rations" -> "factory_rations"


static func new_home_planet(data: BalanceData) -> RefCounted:
	var sim = load("res://scripts/sim/sim.gd").new()
	sim._setup(data)
	return sim


func _setup(data: BalanceData) -> void:
	b = data
	for r in RESOURCES:
		res[r] = 0.0
	for key in b.buildings:
		_type_by_name[b.buildings[key]["Building"]] = key
	_load_civs()
	_load_regions()
	_load_map()
	_load_market()
	soldiers = b.num("starting_soldiers")
	# The capital starts built out with the first build-plan row, all at level 1.
	var first_plan := plan_for_region(2)
	for type in first_plan.counts:
		for i in first_plan.counts[type]:
			_add_building(type, 1, 1)
	_log("Start: %d buildings in %s, %d soldiers" % [buildings.size(), regions[0].name, soldiers])


func _load_civs() -> void:
	for row in b.rows("civilizations"):
		civs[row["Civilization"]] = {
			"method": row["Method"],
			"trade": false,   ## the player signs trade rights in game
			"plan_trade": row["Trade rights"].to_upper() == "TRUE",   ## the sheet path's choice
			"first": int(row["First region"]),
			"last": int(row["Last region"]),
			"captured": row["Captured regions"],
		}


func _load_regions() -> void:
	for row in b.rows("regions"):
		var idx := int(row["Region"])
		var terrain: Dictionary = b.find_row("terrain", "Terrain", row["Terrain"])
		var owner: String = row["Owner"]
		regions.append({
			"index": idx,
			"name": row["Name"],
			"civ": owner,
			"owner": owner,
			"slots": int(row["Slots"]),
			"terrain": row["Terrain"],
			"defense_mod": BalanceData.parse_number(terrain["Defense mod"]),
			"mult": {
				"metal": BalanceData.parse_number(terrain["Metal"]),
				"fuel": BalanceData.parse_number(terrain["Fuel"]),
				"food": BalanceData.parse_number(terrain["Food"]),
			},
			"garrison": 0.0 if owner == PLAYER else Combat.region_garrison(idx, b),
			"kept_credits": 0,    ## captured buildings that fit your plan: free to place here
			"kept_level": 1,
		})


func _load_market() -> void:
	for row in b.rows("market"):
		market[row["Resource"].to_lower()] = {
			"base": BalanceData.parse_number(row["Base price"]),
			"supply": BalanceData.parse_number(row["NPC supply/hr"]),
			"demand": BalanceData.parse_number(row["NPC demand/hr"]),
			"sens": BalanceData.parse_number(row["Sensitivity"]),
			"recent": 0.0,
		}


func _load_map() -> void:
	for row in BalanceData.read_csv(MAP_PATH):
		map_pos[int(row["Region"])] = Vector2i(int(row["Column"]), int(row["Row"]))


# =============================================================================
# Queries
# =============================================================================

## Regions share a border when they sit side by side on the map grid.
func borders(a: int, b_idx: int) -> bool:
	var d: Vector2i = map_pos[a] - map_pos[b_idx]
	return absi(d.x) + absi(d.y) == 1


func neighbours(idx: int) -> Array:
	var out: Array = []
	for other in map_pos:
		if other != idx and borders(idx, other):
			out.append(other)
	return out


## Why the player can't attack a region right now, or "" if they can.
func attack_blocker(region_idx: int, count: int) -> String:
	if owns(region_idx):
		return "Already yours"
	if battle_at(region_idx).size() > 0:
		return "Battle under way"
	if not neighbours(region_idx).any(func(n): return owns(n)):
		return "Not on your border"
	if count <= 0:
		return "Send at least one soldier"
	if count > soldiers + 1e-6:
		return "Only %d soldiers at home" % floori(soldiers + 1e-6)
	return ""


func annexing(region_idx: int) -> bool:
	return annexes.any(func(a): return a.region == region_idx)


func battle_at(region_idx: int) -> Dictionary:
	for battle in battles:
		if battle.region == region_idx:
			return battle
	return {}


## The outcome a battle would have if it started now (for the attack screen).
func preview_attack(region_idx: int, count: int) -> Dictionary:
	var reg := region(region_idx)
	var r := Combat.resolve(count, reg.garrison, reg.defense_mod, b)
	r.needed = Combat.soldiers_needed(reg.garrison, reg.defense_mod, b)
	r.salvage = {"metal": reg.slots * b.num("raze_metal_per_slot"), "fuel": reg.slots * b.num("raze_fuel_per_slot")}
	r.kept = floori(reg.slots * (1.0 - b.num("occupy_rebuild_share")))
	r.stay = r.survivors * b.num("garrison_left_share") if r.attacker_wins else 0.0
	return r

func region(idx: int) -> Dictionary:
	return regions[idx - 1]


func owns(idx: int) -> bool:
	return region(idx).owner == PLAYER


func free_slots(idx: int) -> int:
	if not owns(idx):
		return 0
	var used := 0
	for bd in buildings:
		if bd.region == idx:
			used += 1
	return region(idx).slots - used


func building_by_id(id: int) -> Dictionary:
	for bd in buildings:
		if bd.id == id:
			return bd
	return {}


func buildings_in(region_idx: int) -> Array:
	return buildings.filter(func(bd): return bd.region == region_idx)


## Types a player can place in a slot (the station is not built in a slot).
func buildable_types() -> PackedStringArray:
	var out: PackedStringArray = []
	for row in b.rows("buildings"):
		var key: String = row[BalanceData.KEY_COLUMN]
		if key != "station":
			out.append(key)
	return out


## Free slots minus builds already queued there.
func open_slots(region_idx: int) -> int:
	var queued := 0
	for q in queue:
		if q.kind == "build" and q.region == region_idx:
			queued += 1
	return free_slots(region_idx) - queued


## What one building makes per hour: {resource, amount}. Factories and barracks
## report capacity; factories also draw fuel for power.
func building_output(bd: Dictionary, level: int = -1) -> Dictionary:
	var lvl: int = bd.level if level < 0 else level
	var reg := region(bd.region)
	var out := b.building_output(bd.type) * level_mult(lvl)
	match bd.type:
		"home": return {"resource": "citizens", "amount": out}
		"farm": return {"resource": "food", "amount": out * reg.mult.food}
		"mine": return {"resource": "metal", "amount": out * reg.mult.metal}
		"fuel_extractor": return {"resource": "fuel", "amount": out * reg.mult.fuel}
		"factory_rations": return {"resource": "rations", "amount": out, "power": b.num("factory_fuel_draw") * level_mult(lvl)}
		"factory_equipment": return {"resource": "equipment", "amount": out, "power": b.num("factory_fuel_draw") * level_mult(lvl)}
		"barracks": return {"resource": "soldiers", "amount": out}
	return {"resource": "", "amount": 0.0}


func count_type(type: String) -> int:
	var n := 0
	for bd in buildings:
		if bd.type == type:
			n += 1
	return n


func avg_level() -> float:
	if buildings.is_empty():
		return 1.0
	var total := 0
	for bd in buildings:
		total += bd.level
	return float(total) / buildings.size()


func level_mult(level: int) -> float:
	return pow(b.num("level_output_growth"), level - 1)


## Hourly capacity of every building type at current levels and terrain.
## The sum of building_output() over all buildings, so the UI and sim agree.
func rates() -> Dictionary:
	if not _rates_dirty:
		return _rates
	var r := {"citizens": 0.0, "food": 0.0, "metal": 0.0, "fuel": 0.0,
		"rations_cap": 0.0, "equipment_cap": 0.0, "barracks_cap": 0.0,
		"rations_power": 0.0, "equipment_power": 0.0}
	for bd in buildings:
		var o := building_output(bd)
		match o.resource:
			"citizens", "food", "metal", "fuel": r[o.resource] += o.amount
			"rations":
				r.rations_cap += o.amount
				r.rations_power += o.power
			"equipment":
				r.equipment_cap += o.amount
				r.equipment_power += o.power
			"soldiers": r.barracks_cap += o.amount
	_rates = r
	_rates_dirty = false
	return r


## Citizens and gold after a razing: down until your next capture.
func raze_output_mult() -> float:
	return 1.0 - b.num("raze_output_penalty") if raze_penalty else 1.0


## Per-hour rates for the resource bar. Raw resources are what flows into the
## stockpile; rations, equipment and soldiers are capacity (they need inputs).
func display_rates() -> Dictionary:
	var r := rates()
	var penalty := raze_output_mult()
	var citizens: float = r.citizens * penalty
	var food_net: float = r.food - citizens * b.num("food_per_citizen")
	var sold := maxf(0.0, food_net) * b.num("food_sell_share")
	return {
		"citizens": citizens,
		"food": food_net - sold if food_net > 0.0 else food_net,
		"metal": r.metal,
		"fuel": r.fuel,
		"gold": sold * food_price(sold) * sale_keep() * penalty,
		"rations": r.rations_cap,
		"equipment": r.equipment_cap,
		"soldiers": r.barracks_cap,
	}


## Market price of a resource. `flow` is the player's ongoing sales per hour
## (food is sold continuously); `recent` adds the after-effect of manual trades.
func market_price(res_name: String, flow: float = 0.0, extra: float = 0.0) -> float:
	var m: Dictionary = market[res_name]
	var denom := maxf(1.0, m.supply + flow + m.recent + extra)
	var p: float = m.base * pow(m.demand / denom, m.sens)
	return clampf(p, m.base * b.num("market_price_floor"), m.base * b.num("market_price_ceiling"))


## Settled food price at the player's selling rate (per hour).
func food_price(sell_per_hr: float) -> float:
	return market_price("food", sell_per_hr)


## What the player keeps of a sale after the market fee (trade partners cut it).
func sale_keep() -> float:
	return 1.0 - b.num("market_fee") + b.num("trade_fee_cut_per_partner") * active_trade_partners()


## Gold for selling `qty` now: the lot moves the price, so it sells at the
## average of the price before and after.
func quote_sell(res_name: String, qty: float) -> float:
	var flow := _food_flow() if res_name == "food" else 0.0
	var p0 := market_price(res_name, flow)
	var p1 := market_price(res_name, flow, qty)
	return qty * (p0 + p1) * 0.5 * sale_keep()


## Gold needed to buy `qty` now. The fee applies on purchases too.
func quote_buy(res_name: String, qty: float) -> float:
	var flow := _food_flow() if res_name == "food" else 0.0
	var p0 := market_price(res_name, flow)
	var p1 := market_price(res_name, flow, -qty)
	return qty * (p0 + p1) * 0.5 * (2.0 - sale_keep())


func _food_flow() -> float:
	var r := rates()
	var net: float = r.food - r.citizens * raze_output_mult() * b.num("food_per_citizen")
	return maxf(0.0, net) * b.num("food_sell_share")


func active_trade_partners() -> int:
	var n := 0
	for name in civs:
		var c: Dictionary = civs[name]
		if c.trade and not civ_absorbed(name):
			n += 1
	return n


func civ_absorbed(civ_name: String) -> bool:
	var c: Dictionary = civs[civ_name]
	for i in range(c.first, c.last + 1):
		if not owns(i):
			return false
	return true


## Total garrison still standing in a civilization (its "size" for relations).
func civ_size(civ_name: String) -> float:
	var c: Dictionary = civs[civ_name]
	var total := 0.0
	for i in range(c.first, c.last + 1):
		total += Combat.region_garrison(i, b)
	return total


func relations_hours(region_idx: int) -> float:
	var civ_name: String = region(region_idx).civ
	var c: Dictionary = civs[civ_name]
	var t := b.num("relations_hours_ref") * pow(civ_size(civ_name) / b.num("relations_ref_size"), b.num("relations_size_exp"))
	if c.trade:
		t *= 1.0 - b.num("trade_relations_cut")
	return t * (1.0 + b.num("raze_relations_damage") * razed_count)


func annex_gold(region_idx: int) -> float:
	return region(region_idx).garrison * b.num("annex_gold_per_defender")


## Build-plan row for the step that attacks `region_idx`: {counts, avg_level, total}.
func plan_for_region(region_idx: int) -> Dictionary:
	var row := b.find_row("build_plan", "Attacking region", str(region_idx))
	var counts := {}
	var total := 0
	for col in row:
		if _type_by_name.has(col):
			counts[_type_by_name[col]] = int(row[col])
			total += int(row[col])
	return {"counts": counts, "avg_level": BalanceData.parse_number(row["Avg building level"]), "total": total}


func cost_of(item: Dictionary) -> Dictionary:
	match item.kind:
		"build":
			if region(item.region).kept_credits > 0:
				return {}
			return new_building_cost()
		"upgrade_lowest":
			return upgrade_cost(buildings[_lowest_building()].level)
		"upgrade":
			var bd := building_by_id(item.id)
			if bd.is_empty():
				return {}
			return upgrade_cost(bd.level)
		"annex_gold":
			return {"gold": annex_gold(item.region)}
	return {}


## What a queued item will cost when its turn comes: upgrades queued twice on
## one building are priced at the level they will start from.
func projected_cost(index: int) -> Dictionary:
	var item: Dictionary = queue[index]
	if item.kind != "upgrade":
		return cost_of(item)
	return upgrade_cost(projected_level(index))


## The level a queued upgrade will start from (current level + earlier upgrades in line).
func projected_level(index: int) -> int:
	var item: Dictionary = queue[index]
	var lvl: int = building_by_id(item.id).get("level", 1)
	for i in index:
		if queue[i].kind == "upgrade" and queue[i].id == item.id:
			lvl += 1
	return lvl


func upgrade_cost(level: int) -> Dictionary:
	var g := pow(b.num("upgrade_cost_growth"), level - 1)
	return {"metal": b.num("upgrade_metal") * g, "fuel": b.num("upgrade_fuel") * g, "gold": b.num("upgrade_gold") * g}


func new_building_cost() -> Dictionary:
	return {"metal": b.num("new_building_metal"), "fuel": b.num("new_building_fuel")}


# =============================================================================
# Commands (the only way players change the sim)
# =============================================================================

## Queue a new building in a region you own. Free if the region has kept buildings.
func queue_build(type: String, region_idx: int) -> bool:
	if not owns(region_idx) or not (type in buildable_types()) or open_slots(region_idx) <= 0:
		return false
	queue.append({"kind": "build", "type": type, "region": region_idx})
	return true


## Queue one level on a specific building.
func queue_upgrade(building_id: int) -> bool:
	if building_by_id(building_id).is_empty():
		return false
	queue.append({"kind": "upgrade", "id": building_id})
	return true


## Queue one level on whichever building is lowest when it gets paid for.
func queue_upgrade_lowest() -> void:
	queue.append({"kind": "upgrade_lowest"})


## Remove a queued item. Nothing has been paid for it yet, so nothing is refunded.
## Annexation payments can't be cancelled here.
func cancel_queued(index: int) -> bool:
	if index < 0 or index >= queue.size() or queue[index].kind == "annex_gold":
		return false
	queue.remove_at(index)
	return true


## Tear a building down. No refund. Its queued upgrades are dropped.
func demolish(building_id: int) -> bool:
	var bd := building_by_id(building_id)
	if bd.is_empty():
		return false
	buildings.erase(bd)
	queue = queue.filter(func(q): return not (q.kind == "upgrade" and q.id == building_id))
	_rates_dirty = true
	_log("Demolished %s in %s" % [bd.type, region(bd.region).name])
	return true


## Sign free trade rights with a civilization: a smaller market fee while they
## last, and annexation talks with them go faster.
func sign_trade(civ_name: String) -> bool:
	if not civs.has(civ_name) or civs[civ_name].trade or civ_absorbed(civ_name):
		return false
	if res.gold < b.num("trade_signing_fee"):
		return false
	res.gold -= b.num("trade_signing_fee")
	civs[civ_name].trade = true
	_log("Signed trade rights with %s" % civ_name, "diplomacy")
	return true


func sell(res_name: String, qty: float) -> bool:
	if not market.has(res_name) or qty <= 0.0 or res[res_name] < qty:
		return false
	res.gold += quote_sell(res_name, qty)
	res[res_name] -= qty
	market[res_name].recent += qty
	return true


func buy(res_name: String, qty: float) -> bool:
	if not market.has(res_name) or qty <= 0.0:
		return false
	var cost := quote_buy(res_name, qty)
	if res.gold < cost:
		return false
	res.gold -= cost
	res[res_name] += qty
	market[res_name].recent -= qty
	return true


func set_train_target(n: float) -> void:
	train_target = n


## Send soldiers at an enemy region on your border. `on_capture` is "Occupy" or
## "Raze", chosen up front so a battle that ends while you're away still resolves.
func attack(region_idx: int, count: int, on_capture: String = "Occupy") -> bool:
	if attack_blocker(region_idx, count) != "" or not (on_capture in ["Occupy", "Raze"]):
		return false
	var reg := region(region_idx)
	var dfn := Combat.defense_power(reg.garrison, reg.defense_mod, b)
	var minutes := Combat.battle_minutes(count, reg.garrison, count, dfn, b)
	soldiers -= count
	battles.append({"region": region_idx, "soldiers": float(count), "started_at": hours,
		"ends_at": hours + minutes / 60.0, "on_capture": on_capture})
	_log("Attack %s with %d (battle %.2f min)" % [reg.name, count, minutes])
	return true


## Why a region can't be annexed right now, or "" if it can.
func annex_blocker(region_idx: int) -> String:
	if owns(region_idx):
		return "Already yours"
	if battle_at(region_idx).size() > 0:
		return "Battle under way"
	if annexing(region_idx):
		return "Talks under way"
	var civ_name: String = region(region_idx).civ
	if annexes.any(func(a): return region(a.region).civ == civ_name):
		return "One talk at a time per civ"
	return ""


func start_annex(region_idx: int) -> bool:
	if annex_blocker(region_idx) != "":
		return false
	annexes.append({"region": region_idx, "ends_at": hours + relations_hours(region_idx), "paid": false})
	queue.push_front({"kind": "annex_gold", "region": region_idx})
	_log("Start annexing %s (relations %.1f min, %.1f gold)" % [region(region_idx).name, relations_hours(region_idx) * 60.0, annex_gold(region_idx)])
	return true


# =============================================================================
# Time
# =============================================================================

func advance(dt_hours: float) -> void:
	var left := dt_hours
	while left > 1e-12:
		var step := minf(TICK_HOURS, left)
		_tick(step)
		left -= step


func _tick(dt: float) -> void:
	var r := rates()

	# Raw production. Citizens eat as they are produced.
	var penalty := raze_output_mult()
	var citizens_made: float = r.citizens * penalty * dt
	res.citizens += citizens_made
	var food_net: float = r.food * dt - citizens_made * b.num("food_per_citizen")
	if food_net > 0.0:
		var sold := food_net * b.num("food_sell_share")
		res.gold += sold * food_price(sold / dt) * sale_keep() * penalty
		res.food += food_net - sold
	else:
		res.food = maxf(0.0, res.food + food_net)
	res.metal += r.metal * dt
	res.fuel += r.fuel * dt

	var fade := pow(1.0 - b.num("market_recovery_per_hr"), dt)
	for k in market:
		market[k].recent *= fade

	_pay_queue()
	_run_factories(dt, r)
	_run_barracks(dt, r)

	hours += dt
	_resolve_events()


## Pays queued items in order. The head blocks the rest (no skipping ahead).
func _pay_queue() -> void:
	while not queue.is_empty():
		var item: Dictionary = queue[0]
		var cost := cost_of(item)
		for k in cost:
			if res[k] < cost[k]:
				return
		for k in cost:
			res[k] -= cost[k]
		queue.pop_front()
		_apply(item)


func _apply(item: Dictionary) -> void:
	match item.kind:
		"build":
			var reg := region(item.region)
			if free_slots(item.region) <= 0:
				push_error("No free slot in %s" % reg.name)
				return
			var level := 1
			if reg.kept_credits > 0:
				reg.kept_credits -= 1
				level = reg.kept_level
			_add_building(item.type, level, item.region)
		"upgrade_lowest":
			buildings[_lowest_building()].level += 1
		"upgrade":
			var bd := building_by_id(item.id)
			if bd.is_empty():
				return
			bd.level += 1
		"annex_gold":
			for a in annexes:
				if a.region == item.region:
					a.paid = true
	_rates_dirty = true


func _lowest_building() -> int:
	var best := 0
	for i in buildings.size():
		if buildings[i].level < buildings[best].level:
			best = i
	return best


## Factories work only toward the training target. They share the stockpile
## with construction: whatever is in stock can be spent by either.
func _run_factories(dt: float, r: Dictionary) -> void:
	var to_train := maxf(0.0, train_target - soldiers - _soldiers_in_battle_returning())
	if to_train <= 0.0:
		return
	var spare_metal: float = res.metal
	var spare_fuel: float = res.fuel

	if r.equipment_cap > 0.0:
		var cap: float = r.equipment_cap * dt
		var power_per_unit: float = r.equipment_power / r.equipment_cap
		var need := maxf(0.0, to_train - res.equipment)
		var make := minf(minf(cap, need), spare_metal / b.num("metal_per_equipment"))
		make = minf(make, spare_fuel / (b.num("fuel_per_equipment") + power_per_unit))
		make = maxf(0.0, make)
		res.equipment += make
		res.metal -= make * b.num("metal_per_equipment")
		res.fuel -= make * (b.num("fuel_per_equipment") + power_per_unit)
		spare_fuel -= make * (b.num("fuel_per_equipment") + power_per_unit)

	if r.rations_cap > 0.0:
		var cap: float = r.rations_cap * dt
		var power_per_unit: float = r.rations_power / r.rations_cap
		var need := maxf(0.0, to_train - res.rations)
		var make := minf(minf(cap, need), res.food / b.num("food_per_ration"))
		if power_per_unit > 0.0:
			make = minf(make, spare_fuel / power_per_unit)
		make = maxf(0.0, make)
		res.rations += make
		res.food -= make * b.num("food_per_ration")
		res.fuel -= make * power_per_unit


func _run_barracks(dt: float, r: Dictionary) -> void:
	var to_train := maxf(0.0, train_target - soldiers - _soldiers_in_battle_returning())
	var n: float = minf(r.barracks_cap * dt, to_train)
	n = minf(n, minf(res.citizens, minf(res.equipment, res.rations)))
	if n <= 0.0:
		return
	res.citizens -= n
	res.equipment -= n
	res.rations -= n
	soldiers += n


## Soldiers away in battle don't count toward the target. (Kept as a hook:
## survivors are unknown until the battle ends, so this is 0 for now.)
func _soldiers_in_battle_returning() -> float:
	return 0.0


func _resolve_events() -> void:
	for battle in battles.duplicate():
		if hours + 1e-9 >= battle.ends_at:
			battles.erase(battle)
			_finish_battle(battle)
	for a in annexes.duplicate():
		if a.paid and hours + 1e-9 >= a.ends_at:
			annexes.erase(a)
			_finish_annex(a.region)


func _finish_battle(battle: Dictionary) -> void:
	var reg := region(battle.region)
	var result := Combat.resolve(battle.soldiers, reg.garrison, reg.defense_mod, b)
	if not result.attacker_wins:
		reg.garrison = reg.garrison * result.survivor_share
		_log("Lost at %s: all %d attackers fell, %.0f defenders left" % [reg.name, battle.soldiers, reg.garrison], "battle_lost", battle.region)
		return
	var survivors: float = result.survivors
	var left := survivors * b.num("garrison_left_share")
	soldiers += survivors - left
	reg.owner = PLAYER
	reg.garrison = left
	reg.kept_level = maxi(1, floori(avg_level()))
	raze_penalty = false
	if battle.get("on_capture", "Occupy") == "Raze":
		res.metal += reg.slots * b.num("raze_metal_per_slot")
		res.fuel += reg.slots * b.num("raze_fuel_per_slot")
		reg.kept_credits = 0
		razed_count += 1
		raze_penalty = true
		_log("Razed %s: %.0f survivors (%.0f stay), salvaged %.0f metal and %.0f fuel" % [reg.name, survivors, left,
			reg.slots * b.num("raze_metal_per_slot"), reg.slots * b.num("raze_fuel_per_slot")], "captured", battle.region)
	else:
		reg.kept_credits = floori(reg.slots * (1.0 - b.num("occupy_rebuild_share")))
		_log("Captured %s: %.0f survivors, %.0f stay as garrison" % [reg.name, survivors, left], "captured", battle.region)
	_rates_dirty = true


func _finish_annex(region_idx: int) -> void:
	var reg := region(region_idx)
	soldiers += reg.garrison * b.num("annexed_garrison_join")
	reg.owner = PLAYER
	reg.garrison = 0.0
	reg.kept_credits = reg.slots
	reg.kept_level = maxi(1, floori(avg_level()))
	raze_penalty = false
	_rates_dirty = true
	_log("Annexed %s" % reg.name, "annexed", region_idx)


func _add_building(type: String, level: int, region_idx: int) -> void:
	buildings.append({"id": next_id, "type": type, "level": level, "region": region_idx})
	next_id += 1


func _log(text: String, kind: String = "info", region_idx: int = 0) -> void:
	events.append({"hours": hours, "text": text, "kind": kind, "region": region_idx})
