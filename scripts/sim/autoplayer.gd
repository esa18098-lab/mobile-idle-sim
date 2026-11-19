extends RefCounted
## Plays the home planet on the default path, using only the sim's commands.
## Used by tests and balance checks; never by the shipped game.
##
## STRICT plays the way the Timeline tab assumes: one step at a time. It
## builds the step's plan, trains, then attacks, and waits for the battle
## before starting the next step.
## EAGER plays like an attentive player: it trains for the next region while
## the current battle runs, and attacks as soon as the soldiers are ready.
## Construction can still be catching up when it attacks.
##
## Placement FIRST_FREE puts new buildings in the first free slot (the sheet
## averages terrain over all slots). BEST_TERRAIN puts each building where its
## terrain bonus is highest.

const Combat := preload("res://scripts/sim/combat.gd")

enum Mode { STRICT, EAGER }
enum Placement { FIRST_FREE, BEST_TERRAIN }

const STEP_HOURS := 10.0 / 3600.0  ## the autoplayer checks the game every 10 seconds
const MAX_HOURS := 48.0

var sim
var mode: Mode
var placement: Placement
var steps: Array = []            ## per region: {region, name, method, started, ready, ended, bottleneck_note}


func _init(p_sim, p_mode: Mode = Mode.STRICT, p_placement: Placement = Placement.FIRST_FREE, raids := false) -> void:
	sim = p_sim
	sim.npc_attacks_enabled = raids   # the sheet has no raids; turn them on to see their cost
	mode = p_mode
	placement = p_placement


## Plays regions 2..last in order. Returns the hour the last region became yours.
func play() -> float:
	var last_region: int = sim.regions.size()
	for civ_name in sim.civs:
		if sim.civs[civ_name].plan_trade:
			sim.sign_trade(civ_name)
	var idx := 2
	while idx <= last_region:
		# Retake anything an NPC raid took back before moving on.
		for back in range(2, idx):
			if not sim.owns(back):
				idx = back
				break
		var step := {"region": idx, "name": sim.region(idx).name, "started": sim.hours}
		_plan_economy(idx)
		var method: String = sim.civs[sim.region(idx).civ].method
		step.method = method
		if method == "Annex" and sim.region(idx).owner == sim.region(idx).civ:
			sim.start_annex(idx)
			_wait(func(): return sim.owns(idx) and (mode == Mode.EAGER or sim.queue.is_empty()))
			step.ready = sim.hours
		else:
			step.method = "Conquer"
			var need := _need(idx)
			sim.set_train_target(need)
			_wait(func(): return sim.soldiers + 1e-6 >= _need(idx) and (mode == Mode.EAGER or sim.queue.is_empty()))
			step.ready = sim.hours
			sim.attack(idx, _need(idx), sim.civs[sim.region(idx).civ].captured)
			if mode == Mode.STRICT:
				sim.set_train_target(0)   # the sheet trains nothing during a battle
			if mode == Mode.EAGER and idx < last_region:
				_prepare_next_during_battle(idx + 1)
			_wait(func(): return sim.owns(idx) or sim.battle_at(idx).is_empty())
		step.ended = sim.hours
		if sim.owns(idx):
			steps.append(step)
			idx += 1
		if sim.hours >= MAX_HOURS:
			push_error("Autoplayer gave up at %.1f h" % sim.hours)
			break
	return sim.hours


func _need(idx: int) -> int:
	return Combat.soldiers_needed(sim.region(idx).garrison, sim.region(idx).defense_mod, sim.b)


## Eager only: start training for the next conquest (or talks for the next
## annexation) while this battle runs.
func _prepare_next_during_battle(next_idx: int) -> void:
	var nxt: Dictionary = sim.region(next_idx)
	if sim.civs[nxt.civ].method == "Annex":
		sim.start_annex(next_idx)   # relations can warm up while the battle runs
		return
	sim.set_train_target(Combat.soldiers_needed(nxt.garrison, nxt.defense_mod, sim.b))


## Queue buildings and upgrades so the economy matches the build-plan row.
func _plan_economy(region_idx: int) -> void:
	var plan: Dictionary = sim.plan_for_region(region_idx)
	var queued_levels := 0
	for type in plan.counts:
		var deficit: int = plan.counts[type] - sim.count_type(type) - _queued_count(type)
		for i in deficit:
			var where := _choose_region(type)
			if where < 0:
				break
			sim.queue_build(type, where)
			queued_levels += sim.region(where).kept_level if sim.region(where).kept_credits > _queued_in(where) - 1 else 1
	# Upgrades: lift the total level count to the plan's average.
	var total_levels := 0
	for bd in sim.buildings:
		total_levels += bd.level
	total_levels += queued_levels + _queued_upgrades()
	var target := roundi(plan.avg_level * plan.total)
	for i in maxi(0, target - total_levels):
		sim.queue_upgrade_lowest()


func _choose_region(type: String) -> int:
	# Regions holding free captured buildings come first: they cost nothing.
	var candidates: Array = []
	for reg in sim.regions:
		if reg.owner == sim.PLAYER and reg.kept_credits > _queued_in(reg.index) and sim.free_slots(reg.index) > _queued_in(reg.index):
			candidates.append(reg)
	if candidates.is_empty():
		for reg in sim.regions:
			if reg.owner == sim.PLAYER and sim.free_slots(reg.index) > _queued_in(reg.index):
				candidates.append(reg)
	if candidates.is_empty():
		return -1
	if placement == Placement.FIRST_FREE:
		return candidates[0].index
	var best: Dictionary = candidates[0]
	for reg in candidates:
		if _terrain_mult(type, reg) > _terrain_mult(type, best):
			best = reg
	return best.index


func _terrain_mult(type: String, reg: Dictionary) -> float:
	match type:
		"farm": return reg.mult.food
		"mine": return reg.mult.metal
		"fuel_extractor": return reg.mult.fuel
	return 1.0


func _queued_in(region_idx: int) -> int:
	var n := 0
	for q in sim.queue:
		if q.kind == "build" and q.region == region_idx:
			n += 1
	return n


func _queued_count(type: String) -> int:
	var n := 0
	for q in sim.queue:
		if q.kind == "build" and q.type == type:
			n += 1
	return n


func _queued_upgrades() -> int:
	var n := 0
	for q in sim.queue:
		if q.kind == "upgrade_lowest":
			n += 1
	return n


func _wait(done: Callable) -> void:
	while not done.call():
		sim.advance(STEP_HOURS)
		if sim.hours >= MAX_HOURS:
			return
