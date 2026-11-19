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

	# NPC raids on the default path, over 20 random seeds.
	print("\nraids on the default path (20 seeds)")
	for mode in [AutoPlayer.Mode.STRICT, AutoPlayer.Mode.EAGER]:
		var times: Array = []
		var counts := {"raid_warning": 0, "raid_repelled": 0, "raid_lost": 0}
		for seed in range(1, 21):
			var sim = Sim.new_home_planet(b)
			sim.rng.seed = seed
			sim._schedule_next_npc_attack()
			times.append(AutoPlayer.new(sim, mode, AutoPlayer.Placement.FIRST_FREE, true).play())
			for e in sim.events:
				if counts.has(e.kind):
					counts[e.kind] += 1
		times.sort()
		var mean: float = times.reduce(func(a, x): return a + x, 0.0) / times.size()
		print("  %-9s mean %.2fh  range %.2f-%.2fh  per run: %.1f attacks, %.1f repelled, %.1f lost" % [
			AutoPlayer.Mode.keys()[mode].to_lower(), mean, times[0], times[-1],
			counts.raid_warning / 20.0, counts.raid_repelled / 20.0, counts.raid_lost / 20.0])
	quit()
