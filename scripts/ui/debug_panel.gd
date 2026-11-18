extends Control
## Milestone 1 screen: proves the CSV -> game pipeline on a real device.
## Shows a few live balance values and a sample battle. "Reload" re-reads the CSVs.

const Combat := preload("res://scripts/sim/combat.gd")

var _out: Label


func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	var title := Label.new()
	title.text = "Mobile Idle Sim — build check"
	box.add_child(title)

	_out = Label.new()
	_out.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_out.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_out)

	var reload := Button.new()
	reload.text = "Reload balance CSVs"
	reload.custom_minimum_size = Vector2(0, 48)
	reload.pressed.connect(func(): Balance.reload())
	box.add_child(reload)

	Balance.reloaded.connect(_refresh)
	_refresh()


func _refresh() -> void:
	var b = Balance.data
	var lines: PackedStringArray = []
	if not b.errors.is_empty():
		lines.append("BALANCE ERRORS:")
		lines.append_array(b.errors)
		_out.text = "\n".join(lines)
		return

	lines.append("Loaded %d inputs, %d buildings from %s" % [b.inputs.size(), b.buildings.size(), b.source_dir])
	lines.append("Defender advantage: %s" % b.text("def_advantage"))
	lines.append("Farm output (L1): %d food/hr" % b.building_output("farm"))

	var g := Combat.region_garrison(2, b)
	var need := Combat.soldiers_needed(g, 1.0, b)
	var first := Combat.resolve(need, g, 1.0, b)
	lines.append("")
	lines.append("First battle (Rustfield): %d soldiers vs %.0f defenders, %.2f min" % [need, g, first.minutes])

	var demo := Combat.resolve(500, 200, 1.15, b)
	lines.append("Sample: 500 vs 200 in forest -> %s, %d survivors, %.1f min" % [
		"attacker wins" if demo.attacker_wins else "defender holds",
		roundi(demo.survivors), demo.minutes])
	_out.text = "\n".join(lines)
