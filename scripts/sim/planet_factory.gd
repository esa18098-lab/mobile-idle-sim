extends RefCounted
## Makes a new home planet for a new game: a generated map with real geography,
## checked for balance before you get it.
##
## Like the solar-system generator, every map is played through once by the
## cautious autoplayer (the sheet's way of playing, no raids) in fast-forward.
## If it takes longer or shorter than the window on the sheet allows, the map
## is thrown away and the next seed is tried.

const BalanceData := preload("res://scripts/data/balance_data.gd")
const Sim := preload("res://scripts/sim/sim.gd")
const AutoPlayer := preload("res://scripts/sim/autoplayer.gd")

const CHECK_TICK_HOURS := 60.0 / 3600.0   ## coarse ticks: accurate to about 1% over a playthrough
const MAX_TRIES := 30


## The playthrough time of a map, played cautiously in fast-forward.
static func cautious_hours(data: BalanceData, seed: int) -> float:
	var probe = Sim.new_home_planet(data, seed, true)
	probe.tick_hours = CHECK_TICK_HOURS
	var ap = AutoPlayer.new(probe, AutoPlayer.Mode.STRICT)
	ap.step_hours = CHECK_TICK_HOURS
	return ap.play()


## A balanced map near `seed`: {sim, seed, hours, tries}.
static func new_game(data: BalanceData, seed: int) -> Dictionary:
	var lo := data.num("map_cautious_hours_min")
	var hi := data.num("map_cautious_hours_max")
	var best_seed := seed
	var best_gap := INF
	var best_hours := 0.0
	for i in MAX_TRIES:
		var s := seed + i * 1009
		var hrs := cautious_hours(data, s)
		if hrs >= lo and hrs <= hi:
			return {"sim": Sim.new_home_planet(data, s, true), "seed": s, "hours": hrs, "tries": i + 1}
		var gap := minf(absf(hrs - lo), absf(hrs - hi))
		if gap < best_gap:
			best_gap = gap
			best_seed = s
			best_hours = hrs
	push_warning("No map in the balance window after %d tries; using the closest (%.2f h)" % [MAX_TRIES, best_hours])
	return {"sim": Sim.new_home_planet(data, best_seed, true), "seed": best_seed, "hours": best_hours, "tries": MAX_TRIES}
