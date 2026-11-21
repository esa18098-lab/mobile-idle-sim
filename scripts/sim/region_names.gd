extends RefCounted
## Names for generated regions, chosen to fit their biome ("Ashen Dunes" in a
## desert, "Frostmarch" in the tundra). Content, not balance.

const FIRST := {
	"Plains": ["Amber", "Wheat", "Golden", "Wind", "Long", "Barley", "Green", "Hearth"],
	"Forest": ["Iron", "Elder", "Moss", "Thorn", "Deep", "Shade", "Oak", "Briar"],
	"Hills": ["High", "Rolling", "Copper", "Stone", "Red", "Crag", "Barrow", "Tor"],
	"Mountains": ["Spire", "Storm", "Grey", "Thunder", "Ash", "Eagle", "Ridge", "Granite"],
	"Tundra": ["Frost", "White", "Cold", "Rime", "Snow", "Pale", "Ice", "North"],
	"Coast": ["Salt", "Gull", "Tide", "Shell", "Brine", "Pearl", "Surf", "Harbor"],
	"Desert": ["Ashen", "Sun", "Dust", "Ember", "Glass", "Bone", "Scorch", "Ochre"],
}

const SECOND := {
	"Plains": ["field", "reach", "vale", "meadow", "downs", "acre"],
	"Forest": ["wood", "ridge", "grove", "hollow", "weald", "glen"],
	"Hills": ["moor", "gate", "fell", "knolls", "heights", "brae"],
	"Mountains": ["peaks", "crown", "teeth", "spire", "pass", "summit"],
	"Tundra": ["march", "water", "waste", "hold", "fen", "drift"],
	"Coast": ["flats", "strand", "bay", "shore", "cove", "point"],
	"Desert": [" Dunes", "sands", " Wastes", "basin", " Flats", "scar"],
}


## A name for the biome that hasn't been used on this map yet.
static func make(rng: RandomNumberGenerator, biome: String, used: Dictionary) -> String:
	var a: Array = FIRST.get(biome, FIRST["Plains"])
	var b: Array = SECOND.get(biome, SECOND["Plains"])
	for i in 40:
		var first: String = a[rng.randi_range(0, a.size() - 1)]
		var second: String = b[rng.randi_range(0, b.size() - 1)]
		var name := first + second
		if not used.has(name) and not used.has("first:" + first):
			used[name] = true
			used["first:" + first] = true
			return name
	return "%s %d" % [biome, used.size()]
