extends RefCounted
## Loads the balance CSVs exported from the balance sheet.
##
## Rule: no balance number is typed into game code. Code asks for a value by
## key (the "Key (used by code)" column on the sheet), and this class answers
## from the CSVs in res://balance. Change a CSV, the game changes.

const DEFAULT_DIR := "res://balance"
const KEY_COLUMN := "Key (used by code)"

## Every CSV the game reads. File name = sheet tab, lower_snake_case.
const TABLES: PackedStringArray = [
	"inputs", "buildings", "terrain", "planet_types", "regions",
	"civilizations", "build_plan", "ships", "market", "market_settings",
]

## Tables of keyed parameters (Value + Key columns). All land in `inputs`.
const PARAMETER_TABLES: PackedStringArray = ["inputs", "market_settings"]

## Keys the code relies on. Loading fails loudly if the sheet drops one.
const REQUIRED_INPUT_KEYS: PackedStringArray = [
	"def_advantage", "attack_margin", "garrison_first", "garrison_growth",
	"starting_soldiers", "level_output_growth", "new_building_metal",
	"new_building_fuel", "upgrade_metal", "upgrade_fuel", "upgrade_gold",
	"upgrade_cost_growth", "food_per_citizen", "food_per_ration",
	"metal_per_equipment", "fuel_per_equipment", "factory_fuel_draw",
	"food_sell_share", "battle_k", "battle_p", "annex_gold_per_defender",
	"relations_hours_ref", "food_shortage_penalty", "fort_bonus_per_level",
	"warning_minutes_per_region", "warning_fleet_exponent",
	"stealth_warning_cut", "sensor_stealth_undo", "max_combat_modifiers",
	"garrison_left_share", "annexed_garrison_join", "market_fee",
	"trade_fee_cut_per_partner", "trade_signing_fee", "trade_relations_cut",
	"relations_ref_size", "relations_size_exp", "occupy_rebuild_share",
	"raze_metal_per_slot", "raze_fuel_per_slot", "raze_output_penalty",
	"raze_relations_damage", "docked_upkeep_share", "cmd_cap_base",
	"cmd_cap_per_level", "overcap_rule", "capture_base",
	"capture_per_survival", "soldier_boarding_eff", "marine_ground_eff",
	"marine_equipment", "marine_gold", "orbit_cut_per_battleship",
	"orbit_cut_max", "build_cut_per_station_level", "orbital_garrison_share",
	"repair_metal_share", "repair_hours", "marine_landing_eff",
	"soldier_landing_eff", "routing_exp", "routing_floor", "cmd_cap_hard",
	"station_upgrade_metal", "station_upgrade_fuel", "station_upgrade_growth",
	"station_upgrade_hours", "system_slots", "system_population",
	"system_npc_garrison", "system_bonus_points", "rival_growth_per_hr",
	"level_gain_per_region", "system_target_days",
	"market_price_floor", "market_price_ceiling", "market_recovery_per_hr",
]

const REQUIRED_BUILDING_KEYS: PackedStringArray = [
	"home", "farm", "mine", "fuel_extractor", "factory_rations",
	"factory_equipment", "barracks", "station",
]

var source_dir: String = DEFAULT_DIR
var inputs: Dictionary = {}     ## key -> raw string from the Value column
var buildings: Dictionary = {}  ## key -> row Dictionary
var tables: Dictionary = {}     ## table name -> Array of row Dictionaries
var errors: PackedStringArray = []


## Loads every table from `dir`. Returns true when nothing is missing.
func load_dir(dir: String = DEFAULT_DIR) -> bool:
	source_dir = dir
	inputs.clear()
	buildings.clear()
	tables.clear()
	errors.clear()

	for table_name in TABLES:
		var path := dir.path_join(table_name + ".csv")
		if not FileAccess.file_exists(path):
			errors.append("Missing balance file: %s" % path)
			tables[table_name] = []
			continue
		tables[table_name] = read_csv(path)

	for table_name in PARAMETER_TABLES:
		for row in tables[table_name]:
			var key: String = row.get(KEY_COLUMN, "").strip_edges()
			if key.is_empty():
				continue
			if inputs.has(key):
				errors.append("Duplicate parameter key: %s" % key)
			inputs[key] = row.get("Value", "")

	for row in tables["buildings"]:
		var key: String = row.get(KEY_COLUMN, "").strip_edges()
		if not key.is_empty():
			buildings[key] = row

	for key in REQUIRED_INPUT_KEYS:
		if not inputs.has(key):
			errors.append("Balance is missing parameter key: %s" % key)
	for key in REQUIRED_BUILDING_KEYS:
		if not buildings.has(key):
			errors.append("Buildings tab is missing key: %s" % key)

	for e in errors:
		push_error(e)
	return errors.is_empty()


func has(key: String) -> bool:
	return inputs.has(key)


## A numeric input. "40%" comes back as 0.4. Unknown keys are an error.
func num(key: String) -> float:
	if not inputs.has(key):
		push_error("Balance key not found: %s" % key)
		return NAN
	return parse_number(inputs[key])


## An input as written on the sheet ("Not allowed", "7–10", ...).
func text(key: String) -> String:
	if not inputs.has(key):
		push_error("Balance key not found: %s" % key)
		return ""
	return inputs[key]


## Level-1 hourly output of a building, by key.
func building_output(key: String) -> float:
	if not buildings.has(key):
		push_error("Building key not found: %s" % key)
		return NAN
	return parse_number(buildings[key].get("Output at level 1 (per hr)", ""))


## All rows of a table, each a Dictionary of column header -> raw string.
func rows(table_name: String) -> Array:
	return tables.get(table_name, [])


## First row whose `column` equals `value`, or an empty Dictionary.
func find_row(table_name: String, column: String, value: String) -> Dictionary:
	for row in rows(table_name):
		if str(row.get(column, "")) == value:
			return row
	return {}


static func parse_number(raw: String) -> float:
	var s := raw.strip_edges().replace(",", "")
	var is_percent := s.ends_with("%")
	if is_percent:
		s = s.left(-1).strip_edges()
	if not s.is_valid_float():
		return NAN
	var v := s.to_float()
	return v / 100.0 if is_percent else v


static func read_csv(path: String) -> Array:
	var out: Array = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Cannot open %s (error %d)" % [path, FileAccess.get_open_error()])
		return out
	var header := f.get_csv_line()
	while not f.eof_reached():
		var line := f.get_csv_line()
		if line.size() == 1 and line[0].strip_edges().is_empty():
			continue
		var row := {}
		for i in header.size():
			row[header[i]] = line[i] if i < line.size() else ""
		out.append(row)
	return out
