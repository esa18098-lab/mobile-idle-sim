extends PanelContainer
## Top bar: every resource with its stock and hourly rate, straight from the sim.

const Look := preload("res://scripts/ui/look.gd")
const Icon := preload("res://scripts/ui/icon.gd")

const ORDER: PackedStringArray = ["citizens", "food", "metal", "fuel", "gold", "rations", "equipment", "soldiers"]

const LETTERS := {"citizens": "C", "food": "F", "metal": "M", "fuel": "U", "gold": "G", "rations": "R", "equipment": "E", "soldiers": "S"}

var _value := {}   ## resource -> Label
var _rate := {}    ## resource -> Label


func _ready() -> void:
	add_theme_stylebox_override("panel", Look.flat_box(Look.PANEL, Look.LINE, 0, 3))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	add_child(grid)
	for r in ORDER:
		var cell := HBoxContainer.new()
		cell.custom_minimum_size = Vector2(86, 22)
		cell.add_theme_constant_override("separation", 3)
		cell.add_child(Icon.make(Look.RESOURCE_COLORS[r], LETTERS[r], 1))
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		var v := Look.label("0", Look.FONT_SIZE)
		v.name = "value_" + r
		var rt := Look.label("", Look.FONT_SMALL, Look.DIM)
		rt.name = "rate_" + r
		col.add_child(v)
		col.add_child(rt)
		cell.add_child(col)
		grid.add_child(cell)
		_value[r] = v
		_rate[r] = rt
	refresh()


func refresh() -> void:
	var sim = Game.sim
	var rates: Dictionary = sim.display_rates()
	for r in ORDER:
		var amount: float = sim.soldiers if r == "soldiers" else sim.res[r]
		_value[r].text = Look.num(amount)
		_rate[r].text = Look.rate(rates[r])


## The text shown for a resource's rate (tests compare it with the sim).
func rate_text(r: String) -> String:
	return _rate[r].text
