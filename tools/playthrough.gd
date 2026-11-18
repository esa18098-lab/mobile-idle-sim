extends SceneTree
## Prints a region-by-region playthrough of the home planet next to the sheet.
##   godot --headless --path . --script res://tools/playthrough.gd
## Optional: -- strict|eager first_free|best_terrain

const BalanceData := preload("res://scripts/data/balance_data.gd")
const Sim := preload("res://scripts/sim/sim.gd")
const AutoPlayer := preload("res://scripts/sim/autoplayer.gd")


func _initialize() -> void:
	var b := BalanceData.new()
	b.load_dir()
	var golden := {}
	for g in BalanceData.read_csv("res://tests/golden/timeline_default.csv"):
		golden[int(g["region"])] = float(g["cumulative_hrs"])
	# Placement makes no difference on the default path: each step's plan exactly
	# fills the region just won, so there is never a choice of where to build.
	var combos := [[AutoPlayer.Mode.STRICT, AutoPlayer.Placement.FIRST_FREE],
		[AutoPlayer.Mode.EAGER, AutoPlayer.Placement.FIRST_FREE]]
	for c in combos:
		var t0 := Time.get_ticks_msec()
		var sim = Sim.new_home_planet(b)
		var ap = AutoPlayer.new(sim, c[0], c[1])
		var total: float = ap.play()
		print("\n== %s / %s: %.3f h (sheet %.3f h, %+.1f%%)  [%d ms]" % [
			AutoPlayer.Mode.keys()[c[0]], AutoPlayer.Placement.keys()[c[1]], total, golden[12],
			(total / golden[12] - 1.0) * 100.0, Time.get_ticks_msec() - t0])
		print("  region              method   ready(h) done(h)  sheet(h)")
		for s in ap.steps:
			print("  %2d %-16s %-8s %7.3f %7.3f  %7.3f" % [s.region, s.name, s.method, s.ready, s.ended, golden[s.region]])
	quit()
