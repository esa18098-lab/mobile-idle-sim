extends Node
## Autoload "Balance": the game's single copy of the balance data.
## The sim core never reaches for this directly; it is handed a BalanceData.

const BalanceData := preload("res://scripts/data/balance_data.gd")

signal reloaded

var data: BalanceData = BalanceData.new()


func _ready() -> void:
	reload()


func reload(dir: String = BalanceData.DEFAULT_DIR) -> bool:
	var ok := data.load_dir(dir)
	reloaded.emit()
	return ok
