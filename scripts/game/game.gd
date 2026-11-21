extends Node
## Autoload "Game": owns the running sim and feeds it real time.
##
## The sim never reads the clock; this node is the only place that does.
## The UI calls the cmd_* methods. It never edits sim state itself.

const Sim := preload("res://scripts/sim/sim.gd")
const SaveSystem := preload("res://scripts/game/save_system.gd")
const Server := preload("res://scripts/game/server.gd")
const Notifier := preload("res://scripts/game/notifier.gd")

signal ticked    ## time moved; refresh numbers
signal changed   ## something structural changed; rebuild views
signal away(summary: Dictionary)   ## offline time was caught up

const AUTOSAVE_SECONDS := 30.0
const AWAY_SUMMARY_MIN_SECONDS := 60.0

const MAX_TICKS_PER_FRAME := 600

var sim
var speed := 1.0          ## game seconds per real second (dev menu can raise it)
var paused := false
var _acc := 0.0
var _signature := ""
var persist := true       ## tests and tools turn this off so they never touch the save
var save_path := SaveSystem.PATH
var _since_save := 0.0
var _paused_at_unix := -1.0
var last_away: Dictionary = {}


func _ready() -> void:
	Server.ping_install()
	if not load_game():
		new_game()


func new_game(map_seed: int = -1) -> void:
	if map_seed < 0:
		map_seed = int(now_unix()) % 1000000   # a fresh map each new game
	sim = Sim.new_home_planet(Balance.data, map_seed)
	_acc = 0.0
	_emit_changed()


## Loads the save and catches up the time since it was written.
func load_game() -> bool:
	var got := SaveSystem.read(save_path)
	if not got.ok:
		return false
	sim = Sim.new_home_planet(Balance.data)
	sim.apply_dict(got.state)
	_acc = 0.0
	_catch_up_since(got.saved_unix)
	_emit_changed()
	return true


func save_game() -> bool:
	if not persist or sim == null:
		return false
	_since_save = 0.0
	return SaveSystem.write(sim.to_dict(), now_unix(), save_path)


## The one place the game reads the wall clock.
func now_unix() -> float:
	return Time.get_unix_time_from_system()


## Runs the sim over time spent away, then reports what changed.
func catch_up_seconds(seconds: float) -> Dictionary:
	var before: Dictionary = sim.res.duplicate()
	var soldiers_before: float = sim.soldiers
	var first_event: int = sim.events.size()
	sim.catch_up(seconds / 3600.0)
	_stamp_events()
	var gained := {}
	for k in sim.res:
		gained[k] = sim.res[k] - before[k]
	gained["soldiers"] = sim.soldiers - soldiers_before
	last_away = {"seconds": seconds, "gained": gained, "events": sim.events.slice(first_event)}
	_emit_changed()
	if seconds >= AWAY_SUMMARY_MIN_SECONDS:
		away.emit(last_away)
	return last_away


## Turns upcoming game events into wall-clock notifications for while the app is closed.
func schedule_notifications() -> void:
	var now := now_unix()
	var items: Array = []
	for n in sim.upcoming_notifications():
		items.append({"at_unix": now + (n.at - sim.hours) * 3600.0, "text": n.text})
	Notifier.schedule(items)


func _catch_up_since(saved_unix: float) -> void:
	var now := now_unix()
	var secs := Server.confirm_elapsed(saved_unix, now, now - saved_unix)
	if secs > 0.0:
		catch_up_seconds(secs)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			_paused_at_unix = now_unix()
			save_game()
			schedule_notifications()
		NOTIFICATION_APPLICATION_RESUMED:
			Notifier.cancel_all()
			if _paused_at_unix > 0.0:
				_catch_up_since(_paused_at_unix)
				_paused_at_unix = -1.0
		NOTIFICATION_WM_CLOSE_REQUEST:
			save_game()


func _process(delta: float) -> void:
	if paused or sim == null:
		return
	advance_seconds(delta * speed)
	_since_save += delta
	if _since_save >= AUTOSAVE_SECONDS:
		save_game()


## Moves game time forward in whole one-second ticks, carrying the remainder.
func advance_seconds(seconds: float) -> void:
	_acc += seconds
	var ticks := mini(int(_acc), MAX_TICKS_PER_FRAME)
	if ticks <= 0:
		return
	_acc -= ticks
	sim.advance(ticks * Sim.TICK_HOURS)
	_stamp_events()
	ticked.emit()
	if _structure() != _signature:
		_emit_changed()


# --- commands ----------------------------------------------------------------

func cmd_build(type: String, region_idx: int) -> bool:
	return _after(sim.queue_build(type, region_idx))


func cmd_upgrade(building_id: int) -> bool:
	return _after(sim.queue_upgrade(building_id))


func cmd_demolish(building_id: int) -> bool:
	return _after(sim.demolish(building_id))


func cmd_cancel_queued(index: int) -> bool:
	return _after(sim.cancel_queued(index))


func cmd_attack(region_idx: int, count: int, on_capture: String) -> bool:
	return _after(sim.attack(region_idx, count, on_capture))


func cmd_sign_trade(civ_name: String) -> bool:
	return _after(sim.sign_trade(civ_name))


func cmd_annex(region_idx: int) -> bool:
	return _after(sim.start_annex(region_idx))


func cmd_sell(res_name: String, qty: float) -> bool:
	var ok: bool = sim.sell(res_name, qty)
	if ok:
		ticked.emit()
	return ok


func cmd_buy(res_name: String, qty: float) -> bool:
	var ok: bool = sim.buy(res_name, qty)
	if ok:
		sim._pay_queue()
		ticked.emit()
	return ok


func cmd_reinforce(region_idx: int, n: int) -> bool:
	return _after(sim.reinforce(region_idx, n))


func cmd_withdraw(region_idx: int, n: int) -> bool:
	return _after(sim.withdraw(region_idx, n))


func cmd_automation(key: String, value) -> void:
	sim.automation[key] = value
	sim._automation_due = sim.hours   # act on it right away
	_emit_changed()


func cmd_auto_reinforce(on: bool) -> void:
	sim.auto_reinforce = on
	_emit_changed()


func cmd_train_target(n: int) -> void:
	sim.set_train_target(maxi(0, n))
	_emit_changed()


# --- dev only ----------------------------------------------------------------

func dev_add_resources(amount: float) -> void:
	for k in sim.res:
		sim.res[k] += amount
	ticked.emit()


## Hands you the next enemy region with empty slots, so building can be tested
## before conquest exists (milestone 4).
func dev_take_next_region() -> int:
	for reg in sim.regions:
		if reg.owner != Sim.PLAYER:
			reg.owner = Sim.PLAYER
			reg.garrison = 0.0
			sim._rates_dirty = true
			_emit_changed()
			return reg.index
	return -1


# --- internals ---------------------------------------------------------------

## Wall-clock stamps on new events, for the playtest log.
func _stamp_events() -> void:
	var now := now_unix()
	for i in range(sim.events.size() - 1, -1, -1):
		if sim.events[i].has("unix"):
			break
		sim.events[i]["unix"] = now


func _garrisons() -> int:
	var t := 0.0
	for reg in sim.regions:
		if reg.owner == Sim.PLAYER:
			t += reg.garrison
	return roundi(t)

func _after(ok: bool) -> bool:
	if ok:
		# Paying can happen right away if the stockpile already covers it.
		sim._pay_queue()
		_emit_changed()
	return ok


func _emit_changed() -> void:
	_signature = _structure()
	changed.emit()


## A cheap fingerprint of what the views draw: buildings, levels, owners, queue.
func _structure() -> String:
	var levels := 0
	for bd in sim.buildings:
		levels += bd.level * 31 + bd.id
	var owned := 0
	for reg in sim.regions:
		if reg.owner == Sim.PLAYER:
			owned += 1 << reg.index
	return "%d|%d|%d|%d|%d|%d" % [sim.buildings.size(), levels, owned, sim.queue.size(), sim.battles.size(), int(sim.train_target)] + "|%d|%d|%d|%d" % [sim.npc_raids.size(), int(sim.auto_reinforce), roundi(sim.soldiers), _garrisons()] + str(sim.automation) + "|%d" % (sim.annexes.size() + sim.civs.values().filter(func(c): return c.trade).size() * 100)
