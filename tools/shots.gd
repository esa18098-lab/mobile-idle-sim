extends SceneTree
## Renders the game screens to PNGs for a visual check (needs a display; use xvfb-run).
##   xvfb-run -a -s "-screen 0 720x1280x24" godot --path . --rendering-driver opengl3 --script res://tools/shots.gd -- /tmp/shots

var _main: Node
var Game: Node
var _frame := 0
var _dir := "/tmp/shots"
var _steps: Array = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_dir = args[0]
	DirAccess.make_dir_recursive_absolute(_dir)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_steps = [
		["planet", func(): pass],
		["capital", func(): _main.show_region(1)],
		["building", func(): _main.open_building_sheet(Game.sim.buildings_in(1)[2].id)],
		["dev_region", func():
			_main.close_sheet()
			Game.dev_take_next_region()
			_main.show_region(2)],
		["build_menu", func(): _main.open_build_sheet(2)],
		["queue", func():
			_main.close_sheet()
			Game.cmd_build("farm", 2)
			Game.cmd_build("mine", 2)
			Game.cmd_upgrade(Game.sim.buildings[0].id)
			Game.cmd_upgrade(Game.sim.buildings[0].id)
			_main._open_sheet(_main._queue_sheet)],
		["npc_region", func():
			_main.close_sheet()
			_main.show_region(9)],
		["planet_later", func():
			Game.advance_seconds(600)
			_main.show_planet()],
		["army", func():
			Game.new_game()
			_main.show_planet()
			_main._open_sheet(_main._army_sheet)],
		["attack", func():
			_main.close_sheet()
			_main.show_region(2)
			_main.open_attack_sheet(2)],
		["attack_raze", func():
			_main._attack_mode = "Raze"
			_main._attack_count = 15
			_main._rebuild_sheet()],
		["battle", func():
			_main._attack_mode = "Occupy"
			_main._attack_count = 20
			_main._rebuild_sheet()
			_main._sheet_box.get_node("go").pressed.emit()
			Game.advance_seconds(70)],
		["planet_battle", func(): _main.show_planet()],
		["captured", func():
			Game.advance_seconds(120)
			_main._process(1.0)],
		["diplomacy", func():
			Game.cmd_sign_trade("Veyra Compact")
			Game.cmd_annex(5)
			Game.advance_seconds(300)
			_main.show_planet()
			_main._open_sheet(_main._diplomacy_sheet)],
		["market", func():
			Game.dev_add_resources(2000.0)
			Game.cmd_sell("metal", 1000.0)
			_main._open_sheet(_main._market_sheet)],
		["away", func():
			_main.close_sheet()
			Game.sim.set_train_target(80)
			Game.sim.soldiers = 40.0
			Game.cmd_attack(4, 35, "Occupy")
			var SaveSystem = load("res://scripts/game/save_system.gd")
			Game.save_path = "user://shots_save.json"
			SaveSystem.write(Game.sim.to_dict(), Game.now_unix() - 3.0 * 3600.0, Game.save_path)
			Game.load_game()
			DirAccess.remove_absolute(Game.save_path)],
		["raid_banner", func():
			_main.close_sheet()
			Game.new_game()
			for idx in [2, 4]:
				Game.sim.region(idx).owner = "You"
				Game.sim.region(idx).garrison = 3.0
			Game.sim.soldiers = 12.0
			Game.sim._rates_dirty = true
			Game.sim.next_npc_attack_at = Game.sim.hours
			Game.advance_seconds(1)
			_main.show_planet()
			_main._process(1.0)],
		["raid_region", func():
			_main.show_region(Game.sim.npc_raids[0].target)
			_main._process(1.0)],
	]


func _process(_d: float) -> bool:
	if Game == null:
		Game = root.get_node_or_null("Game")
		Game.persist = false
		Game.new_game()
	_frame += 1
	var i := _frame / 6
	if _frame % 6 == 1 and i < _steps.size():
		_steps[i][1].call()
	elif _frame % 6 == 5 and i < _steps.size():
		var path := "%s/%02d_%s.png" % [_dir, i, _steps[i][0]]
		root.get_texture().get_image().save_png(path)
	elif i >= _steps.size():
		print("shots in ", _dir)
		quit()
	return false
