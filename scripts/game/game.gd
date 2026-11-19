extends Node
## Autoload "Game": owns the running sim and feeds it real time.
##
## The sim never reads the clock; this node is the only place that does.
## The UI calls the cmd_* methods. It never edits sim state itself.

const Sim := preload("res://scripts/sim/sim.gd")

signal ticked    ## time moved; refresh numbers
signal changed   ## something structural changed; rebuild views

const MAX_TICKS_PER_FRAME := 600

var sim
var speed := 1.0          ## game seconds per real second (dev menu can raise it)
var paused := false
var _acc := 0.0
var _signature := ""


func _ready() -> void:
	new_game()


func new_game() -> void:
	sim = Sim.new_home_planet(Balance.data)
	_acc = 0.0
	_emit_changed()


func _process(delta: float) -> void:
	if paused or sim == null:
		return
	advance_seconds(delta * speed)


## Moves game time forward in whole one-second ticks, carrying the remainder.
func advance_seconds(seconds: float) -> void:
	_acc += seconds
	var ticks := mini(int(_acc), MAX_TICKS_PER_FRAME)
	if ticks <= 0:
		return
	_acc -= ticks
	sim.advance(ticks * Sim.TICK_HOURS)
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
	return "%d|%d|%d|%d" % [sim.buildings.size(), levels, owned, sim.queue.size()]
