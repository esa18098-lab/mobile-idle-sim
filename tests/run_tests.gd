extends SceneTree
## Headless test runner. Exit code 0 = all passed.
##   godot --headless --path . --script res://tests/run_tests.gd
##
## Golden checks compare the sim against numbers copied from the balance sheet
## (tests/golden). Tolerance is 5% per the build plan; the formulas should
## actually match to well under 0.1%.

const BalanceData := preload("res://scripts/data/balance_data.gd")
const Combat := preload("res://scripts/sim/combat.gd")
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

	# Cumulative hours need the economy sim (milestone 2).
	_skip("timeline cumulative hours (5.106 h) — economy sim is milestone 2")
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
