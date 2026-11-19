extends SceneTree
## Compares the paths through the home planet, cautious and attentive.
##   godot --headless --path . --script res://tools/paths.gd

const BalanceData := preload("res://scripts/data/balance_data.gd")
const Sim := preload("res://scripts/sim/sim.gd")
const AutoPlayer := preload("res://scripts/sim/autoplayer.gd")


func _initialize() -> void:
	var b := BalanceData.new()
	b.load_dir()
	var paths := {
		"default (conquer Kharn+Ostrel, annex Veyra)": func(_s): pass,
		"conquer everyone": func(s):
			for n in s.civs: s.civs[n].method = "Conquer",
		"conquer everyone, raze Kharn": func(s):
			for n in s.civs: s.civs[n].method = "Conquer"
			s.civs["Kharn Clans"].captured = "Raze",
		"annex Veyra, raze Kharn": func(s): s.civs["Kharn Clans"].captured = "Raze",
		"conquer everyone, raze all": func(s):
			for n in s.civs:
				s.civs[n].method = "Conquer"
				s.civs[n].captured = "Raze",
	}
	print("%-46s %9s %9s" % ["path", "cautious", "attentive"])
	for name in paths:
		var out := []
		for mode in [AutoPlayer.Mode.STRICT, AutoPlayer.Mode.EAGER]:
			var sim = Sim.new_home_planet(b)
			paths[name].call(sim)
			out.append(AutoPlayer.new(sim, mode).play())
		print("%-46s %8.2fh %8.2fh" % [name, out[0], out[1]])
	quit()
