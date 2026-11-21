extends VBoxContainer
## Planet zoom: the generated map of the 12 regions. Tap one to open its slots.

const Look := preload("res://scripts/ui/look.gd")
const Sim := preload("res://scripts/sim/sim.gd")
const MapView := preload("res://scripts/ui/map_view.gd")

signal region_tapped(region_idx: int)
signal market_tapped
signal diplomacy_tapped
signal automate_tapped

var map_view: MapView
var _count: Label


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	var sim = Game.sim
	var head := HBoxContainer.new()
	head.add_child(Look.label("Home planet", Look.FONT_TITLE))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	_count = Look.label("", Look.FONT_SIZE, Look.DIM)
	head.add_child(_count)
	add_child(head)
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 4)
	for pair in [["Market", market_tapped], ["Diplomacy", diplomacy_tapped], ["Automate", automate_tapped]]:
		var bt := Button.new()
		bt.name = pair[0].to_lower()
		bt.text = pair[0]
		bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bt.custom_minimum_size = Vector2(0, 32)
		var sig: Signal = pair[1]
		bt.pressed.connect(func(): sig.emit())
		nav.add_child(bt)
	add_child(nav)
	map_view = MapView.new()
	map_view.name = "map"
	map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_view.region_tapped.connect(func(r): region_tapped.emit(r))
	add_child(map_view)
	rebuild()


func rebuild() -> void:
	var sim = Game.sim
	var owned: int = sim.regions.filter(func(r): return r.owner == Sim.PLAYER).size()
	_count.text = "%d of %d regions" % [owned, sim.regions.size()]
	if map_view:
		map_view.rebuild()


func refresh_live() -> void:
	if map_view:
		map_view.refresh_live()
