extends RefCounted
## Ground combat. Pure functions, no scene access.
## Mirrors the Combat and Timeline tabs of the balance sheet.
##
## Power: attackers count 1 each; defenders count def_advantage × terrain mod.
## Winner: higher power. Survivors (Lanchester square law):
##     winner keeps sqrt(1 - (weak/strong)^2) of its troops.
## Time: battle_k × (attackers + defenders)^battle_p, shortened by routing:
##     × max(routing_floor, (weak/strong)^routing_exp).

const BalanceData := preload("res://scripts/data/balance_data.gd")


static func attack_power(attackers: float, attacker_mod: float = 1.0) -> float:
	return attackers * attacker_mod


static func defense_power(defenders: float, terrain_mod: float, b: BalanceData) -> float:
	return defenders * b.num("def_advantage") * terrain_mod


## Soldiers the timeline sends: enough to beat the defense by attack_margin.
static func soldiers_needed(garrison: float, terrain_mod: float, b: BalanceData) -> int:
	var target := defense_power(garrison, terrain_mod, b) * b.num("attack_margin")
	return ceili(target - 1e-9)


## Share of the winner's troops still standing.
static func survivor_share(attack: float, defense: float) -> float:
	var strong := maxf(attack, defense)
	if strong <= 0.0:
		return 0.0
	var weak := minf(attack, defense)
	return sqrt(maxf(0.0, 1.0 - pow(weak / strong, 2.0)))


static func attacker_wins(attack: float, defense: float) -> bool:
	return attack > defense


static func battle_minutes(attackers: float, defenders: float, attack: float, defense: float, b: BalanceData) -> float:
	var strong := maxf(attack, defense)
	if strong <= 0.0:
		return 0.0
	var weak := minf(attack, defense)
	var routing := maxf(b.num("routing_floor"), pow(weak / strong, b.num("routing_exp")))
	return b.num("battle_k") * pow(attackers + defenders, b.num("battle_p")) * routing


## Garrison of the n-th enemy region on the home planet (region 2 is the first).
static func region_garrison(region_index: int, b: BalanceData) -> float:
	return b.num("garrison_first") * pow(b.num("garrison_growth"), region_index - 2)


## One full ground battle, returned as a plain Dictionary for the UI and tests.
static func resolve(attackers: float, defenders: float, terrain_mod: float, b: BalanceData) -> Dictionary:
	var atk := attack_power(attackers)
	var dfn := defense_power(defenders, terrain_mod, b)
	var wins := attacker_wins(atk, dfn)
	var share := survivor_share(atk, dfn)
	return {
		"attack": atk,
		"defense": dfn,
		"ratio": atk / dfn if dfn > 0.0 else INF,
		"attacker_wins": wins,
		"survivor_share": share,
		"survivors": (attackers if wins else defenders) * share,
		"minutes": battle_minutes(attackers, defenders, atk, dfn, b),
	}
