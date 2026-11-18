extends SceneTree
## Headless test runner. Exit code 0 = all passed.
##   godot --headless --path . --script res://tests/run_tests.gd
##
## Golden checks compare the sim against numbers copied from the balance sheet
## (tests/golden). Tolerance is 5% per the build plan; the formulas should
## actually match to well under 0.1%.

const BalanceData := preload("res://scripts/data/balance_data.gd")
const Combat := preload("res://scripts/sim/combat.gd")
const Sim := preload("res://scripts/sim/sim.gd")
const AutoPlayer := preload("res://scripts/sim/autoplayer.gd")
const GOLDEN_TOLERANCE := 0.05

var _passed := 0
var _failed := 0
var _skipped := 0


func _initialize() -> void:
	var b := BalanceData.new()
	_check("balance loads with every required key", b.load_dir(), "; ".join(b.errors))

	# A test that hits a script error stops early and returns null, not true.
	# Godot keeps running after script errors, so this is what catches them.
	_finished("test_parse_number", test_parse_number())
	_finished("test_combat_tab", test_combat_tab(b))
	_finished("test_timeline_golden", test_timeline_golden(b))
	_finished("test_csv_change_changes_game", test_csv_change_changes_game())
	_finished("test_economy_rates", test_economy_rates(b))
	_finished("test_strict_playthrough_matches_sheet", test_strict_playthrough_matches_sheet(b))
	_finished("test_eager_playthrough", test_eager_playthrough(b))

	print("\n%d passed, %d failed, %d skipped" % [_passed, _failed, _skipped])
	quit(1 if _failed > 0 else 0)


func test_parse_number() -> bool:
	_check_close("parse 40%", BalanceData.parse_number("40%"), 0.4)
	_check_close("parse 0.20%", BalanceData.parse_number("0.20%"), 0.002)
	_check_close("parse 40000", BalanceData.parse_number("40000"), 40000.0)
	_check("parse text -> NAN", is_nan(BalanceData.parse_number("Not allowed")))
	return true


## Combat tab defaults: 500 attackers vs 200 defenders, terrain 1.15.
func test_combat_tab(b) -> bool:
	var r := Combat.resolve(500, 200, 1.15, b)
	_check_close("combat: defense power", r.defense, 345.0)
	_check_close("combat: ratio", r.ratio, 1.449, 0.001)
	_check("combat: attacker wins", r.attacker_wins)
	_check_close("combat: survivor share", r.survivor_share, 0.72, 0.01)
	_check("combat: 362 survivors", roundi(r.survivors) == 362, "got %f" % r.survivors)
	_check_close("combat: battle minutes", r.minutes, 34.3, 0.01)
	return true


## Timeline tab, default path: garrisons, soldiers sent, battle minutes.
func test_timeline_golden(b) -> bool:
	var golden := BalanceData.read_csv("res://tests/golden/timeline_default.csv")
	_check("golden timeline has 11 regions", golden.size() == 11)
	for g in golden:
		var idx := int(g["region"])
		var region: Dictionary = b.find_row("regions", "Region", str(idx))
		var terrain: Dictionary = b.find_row("terrain", "Terrain", region.get("Terrain", ""))
		var mod := BalanceData.parse_number(terrain.get("Defense mod", ""))
		var garrison := Combat.region_garrison(idx, b)
		var label := "region %d %s" % [idx, g["name"]]

		_check_close(label + " defense mod", mod, float(g["defense_mod"]), 0.001)
		_check_close(label + " garrison", garrison, float(g["garrison"]), GOLDEN_TOLERANCE)
		if g["method"] == "Annex":
			continue
		var need := Combat.soldiers_needed(garrison, mod, b)
		_check(label + " soldiers needed", need == int(g["soldiers_needed"]), "got %d" % need)
		var r := Combat.resolve(need, garrison, mod, b)
		_check_close(label + " battle minutes", r.minutes, float(g["battle_min"]), GOLDEN_TOLERANCE)

	return true


## Milestone 1 "done when": a CSV change changes the game, with no code change.
func test_csv_change_changes_game() -> bool:
	var dir := "user://balance_csv_test"
	DirAccess.make_dir_recursive_absolute(dir)
	for t in BalanceData.TABLES:
		var src := FileAccess.get_file_as_string("res://balance/%s.csv" % t)
		if t == "inputs":
			src = src.replace("Defender advantage (multiplier),1.5,", "Defender advantage (multiplier),2,")
		var f := FileAccess.open(dir.path_join(t + ".csv"), FileAccess.WRITE)
		f.store_string(src)
		f.close()
	var b := BalanceData.new()
	b.load_dir(dir)
	_check_close("csv edit: def_advantage now 2", b.num("def_advantage"), 2.0)
	var need := Combat.soldiers_needed(Combat.region_garrison(2, b), 1.0, b)
	_check("csv edit: Rustfield now needs 30 soldiers (was 23)", need == 30, "got %d" % need)
	return true


## Production at the first build-plan row (all level 1) against the Timeline's row 12.
func test_economy_rates(b) -> bool:
	var sim = Sim.new_home_planet(b)
	var r: Dictionary = sim.rates()
	_check_close("rates: citizens/hr", r.citizens, 80.0)
	_check_close("rates: food after upkeep/hr", r.food - r.citizens * b.num("food_per_citizen"), 360.0)
	_check_close("rates: metal/hr", r.metal, 1120.0)
	_check_close("rates: fuel after factory power/hr", r.fuel - r.rations_power - r.equipment_power, 192.0)
	_check_close("rates: barracks cap/hr", r.barracks_cap, 120.0)
	# Market tab: food sells at 0.4014 when the player sells 1000/hr.
	_check_close("market: food price at 1000/hr", sim.food_price(1000.0), 0.40144021647363637, 1e-6)
	# Level 2 buildings make output_growth times more.
	for bd in sim.buildings:
		bd.level = 2
	sim._rates_dirty = true
	_check_close("rates: metal at level 2", sim.rates().metal, 1120.0 * b.num("level_output_growth"))
	return true


## Played the way the Timeline assumes (one step at a time, nothing trained
## during battles), the sim must land within 5% of the sheet at every step.
func test_strict_playthrough_matches_sheet(b) -> bool:
	var golden := {}
	for g in BalanceData.read_csv("res://tests/golden/timeline_default.csv"):
		golden[int(g["region"])] = float(g["cumulative_hrs"])
	var sim = Sim.new_home_planet(b)
	var ap = AutoPlayer.new(sim, AutoPlayer.Mode.STRICT)
	var total: float = ap.play()
	_check("strict: all 11 regions taken", ap.steps.size() == 11 and sim.owns(12))
	for s in ap.steps:
		_check_close("strict: region %d done by sheet time" % s.region, s.ended, golden[s.region], GOLDEN_TOLERANCE)
	_check_close("strict: home planet total vs sheet 5.106 h", total, golden[12], GOLDEN_TOLERANCE)
	_check_no_negative(sim, "strict")
	var again = Sim.new_home_planet(b)
	_check("strict: deterministic (same result twice)", is_equal_approx(AutoPlayer.new(again, AutoPlayer.Mode.STRICT).play(), total))
	return true


## An attentive player trains during battles. Pinned so balance changes show up.
func test_eager_playthrough(b) -> bool:
	var pin := float(BalanceData.read_csv("res://tests/golden/sim_playthrough.csv")[0]["total_hrs"])
	var sim = Sim.new_home_planet(b)
	var total: float = AutoPlayer.new(sim, AutoPlayer.Mode.EAGER).play()
	_check_close("eager: total matches pinned %.3f h" % pin, total, pin, 0.01)
	_check("eager: under the 6 h home-planet cap", total <= 6.0, "got %.2f" % total)
	_check_no_negative(sim, "eager")
	return true


func _check_no_negative(sim, label: String) -> void:
	var worst := 0.0
	for k in sim.res:
		worst = minf(worst, sim.res[k])
	_check(label + ": no resource below zero", worst > -1e-6, "min %f" % worst)


# --- tiny assert helpers -------------------------------------------------------

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    ", name)
	else:
		_failed += 1
		print("  FAIL  ", name, ("  (" + detail + ")") if detail else "")


func _check_close(name: String, got: float, want: float, rel_tol: float = 1e-6) -> void:
	var ok := absf(got - want) <= absf(want) * rel_tol + 1e-9
	_check(name, ok, "got %f, want %f" % [got, want])


func _finished(test_name: String, result) -> void:
	_check(test_name + " ran to the end", result == true, "script error — see output above")


func _skip(name: String) -> void:
	_skipped += 1
	print("  skip  ", name)
