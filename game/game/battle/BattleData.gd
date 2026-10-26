extends RefCounted
## Re - Traveller : battle tables, loaded from `battle_data.json`.
##
## Everything the battle screen needs to know about weapons, elements, skills,
## items, party stats, enemies and encounters lives in that one versioned JSON.
## This class does three jobs and no more:
##
##   1. read the file and answer "is it sane?" (`problems()`), so a typo in a
##      weakness or a skill that names an item that does not exist fails CI
##      instead of showing up as a monster that can never be broken;
##   2. hand out the tables to the engine and the UI;
##   3. own the damage formula, in ONE place, because the UI's floating numbers
##      and the tests' 1000 simulated battles must agree with the engine.
##
## The formula, and why each factor is where it is:
##
##   dmg = ATK x (power / 100) x (100 / (100 + DEF)) x Boost x Break x crit x jitter
##
##   ATK/DEF    physical hits use atk/def, magic and elements use matk/mdef. A
##              weapon hit is physical; an element hit is magic. That is the only
##              split, so a skill never has to say which it is.
##   power/100  100 = "one normal hit". A 130 skill is 30% stronger, not 130%.
##   100/(100+DEF)   diminishing returns, and DEF can never make a hit zero or
##              negative: 100 DEF halves damage, it does not stop it. This is
##              also why halving DEF on Break is a real gain without exploding.
##   Boost     1 + 0.25 x BP spent, on top of the extra hits. Spending 3 BP is
##              1,75x per hit across four hits.
##   Break     1,5x while the target is broken (on top of its halved DEF).
##   jitter    0,95..1,05, seeded, so a battle is reproducible in a test.
##
## The file is read with `FileAccess` and `JSON.parse_string`, not `load()`: the
## game ships inside plain PCKPacker archives with no `.import` files, and a
## `.json` that is not imported does not exist as a Resource at all.

const DATA_PATH := "res://game/battle/battle_data.json"
const SCHEMA := 1

var data: Dictionary = {}
var problems: Array = []
var source := ""
## Element ids in file order, so the weakness row is always in the same order.
var elements: Array = []
var weapons: Array = []


func _init(path: String = "") -> void:
	var want := path if path != "" else DATA_PATH
	source = want
	if not FileAccess.file_exists(want):
		problems.append("battle_data.json tidak ada: %s" % want)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(want))
	if typeof(parsed) != TYPE_DICTIONARY:
		problems.append("battle_data.json bukan objek JSON")
		return
	data = parsed
	elements = _string_list(data.get("elements", []))
	weapons = _string_list(data.get("weapons", []))
	_validate()


# ------------------------------------------------------------------ tables ---
func balance() -> Dictionary:
	var b: Variant = data.get("balance", {})
	return b if typeof(b) == TYPE_DICTIONARY else {}


func balance_int(key: String, fallback: int) -> int:
	return int(balance().get(key, fallback))


func balance_float(key: String, fallback: float) -> float:
	return float(balance().get(key, fallback))


func formula_text() -> String:
	return String(data.get("formula", ""))


func items() -> Array:
	return _dict_list(data.get("items", []))


func item(id: String) -> Dictionary:
	return _find(items(), id)


func skills() -> Array:
	return _dict_list(data.get("skills", []))


func skill(id: String) -> Dictionary:
	return _find(skills(), id)


func party_defs() -> Array:
	return _dict_list(data.get("party", []))


func party_def(id: String) -> Dictionary:
	return _find(party_defs(), id)


func enemies() -> Array:
	return _dict_list(data.get("enemies", []))


func enemy(id: String) -> Dictionary:
	return _find(enemies(), id)


func encounters() -> Array:
	return _dict_list(data.get("encounters", []))


func encounter(id: String) -> Dictionary:
	return _find(encounters(), id)


func surfaces() -> Array:
	return _dict_list(data.get("surfaces", []))


func surface_for_tile(tile: String) -> Dictionary:
	for row in surfaces():
		if String(row.get("tile", "")) == tile:
			return row
	return surfaces()[0] if not surfaces().is_empty() else {}


## Weapon ids an enemy is weak to, as a Dictionary for O(1) lookups in the loop.
func weak_set(enemy_id: String) -> Dictionary:
	var out := {}
	for w in _string_list(enemy(enemy_id).get("weak", [])):
		out[w] = true
	return out


# ----------------------------------------------------------------- formula ---
## One hit. `tag` is a weapon id (physical) or an element id (magic).
## Returns {damage, crit, weak, tag, power}.
func resolve_hit(attacker: Dictionary, defender: Dictionary, tag: String, power: float,
		boost: int, broken: bool, def_up: float, guard: bool,
		rng: RandomNumberGenerator) -> Dictionary:
	var magic := elements.has(tag)
	var atk := float(attacker.get("matk" if magic else "atk", 10))
	var defense := float(defender.get("mdef" if magic else "def", 10))
	if def_up > 0.0:
		# a buff belongs to the defender, so it raises its DEF, not the attacker's
		defense *= 1.0 + def_up
	if broken:
		defense *= balance_float("break_defense_factor", 0.5)
	var dmg := atk * (power / 100.0) * (100.0 / (100.0 + maxf(0.0, defense)))
	var boost_mult := 1.0 + 0.25 * float(boost)
	var break_mult := balance_float("break_multiplier", 1.5) if broken else 1.0
	var crit := false
	var crit_chance := float(attacker.get("crit", 0)) / 100.0
	if rng.randf() < crit_chance:
		crit = true
	var jitter := rng.randf_range(balance_float("variance_low", 0.95),
		balance_float("variance_high", 1.05))
	dmg *= boost_mult * break_mult * (balance_float("crit_multiplier", 1.6) if crit else 1.0)
	dmg *= jitter
	if guard:
		dmg *= balance_float("guard_multiplier", 0.5)
	var weak := _is_weak(defender, tag)
	return {
		"damage": maxi(1, int(round(dmg))),
		"crit": crit,
		"weak": weak,
		"tag": tag,
		"power": power,
		"magic": magic,
	}


## Does a hit with this tag count against the shield? Only a weakness does, and
## a weakness is either one of the enemy's elements or one of its weapons.
func _is_weak(defender: Dictionary, tag: String) -> bool:
	var weak: Array = defender.get("weak", [])
	for raw in weak:
		if String(raw) == tag:
			return true
	return false


func is_weak(defender: Dictionary, tag: String) -> bool:
	return _is_weak(defender, tag)


## The "?" wall: the UI shows a weakness icon only when the party has learned it.
## Kept here so the rule is one line and both the UI and the tests read it.
func shown_weak(observed: Dictionary, enemy_id: String, tag: String) -> bool:
	var known: Variant = observed.get(enemy_id, [])
	if typeof(known) != TYPE_ARRAY:
		return false
	return (known as Array).has(tag)


func mark_weak(observed: Dictionary, enemy_id: String, tag: String) -> bool:
	if shown_weak(observed, enemy_id, tag):
		return false
	var known: Variant = observed.get(enemy_id, [])
	var list: Array = known if typeof(known) == TYPE_ARRAY else []
	list.append(tag)
	observed[enemy_id] = list
	return true


# ------------------------------------------------------------------ checks ---
func _validate() -> void:
	if int(data.get("schema", 0)) != SCHEMA:
		problems.append("schema %s, harusnya %d" % [str(data.get("schema")), SCHEMA])
	if elements.size() != 6:
		problems.append("enam elemen harus ada, ada %d" % elements.size())
	if weapons.size() != 6:
		problems.append("enam senjata harus ada, ada %d" % weapons.size())
	if balance().is_empty():
		problems.append("bagian balance kosong")
	var b := balance()
	for key in ["bp_start", "bp_per_turn", "bp_max", "bp_spend_max", "shield_max",
			"shield_min", "break_turns", "turn_bar_entries"]:
		if not b.has(key):
			problems.append("balance.%s tidak ada" % key)
	if int(b.get("bp_spend_max", 0)) > int(b.get("bp_max", 0)):
		problems.append("BP boleh dipakai melebihi BP maksimum")
	if int(b.get("bp_spend_max", 0)) > 3:
		problems.append("spesifikasi: paling banyak 3 BP sekali pakai")
	if int(b.get("shield_min", 0)) < 2 or int(b.get("shield_max", 0)) > 8:
		problems.append("Shield harus 2..8")
	if formula_text().length() < 40:
		problems.append("rumus damage tidak didokumentasikan di berkas data")

	var item_ids: Array = []
	for it in items():
		var id := String(it.get("id", ""))
		item_ids.append(id)
		if id == "":
			problems.append("ada item tanpa id")
		if String(it.get("kind", "")) not in ["heal", "damage", "buff"]:
			problems.append("item %s punya kind asing" % id)
		if String(it.get("kind", "")) == "damage" and not elements.has(String(it.get("element", ""))):
			problems.append("item %s: elemen %s tidak dikenal" % [id, str(it.get("element"))])
		if String(it.get("target", "ally")) not in ["ally", "enemy", "self"]:
			problems.append("item %s: target asing" % id)

	var skill_ids: Array = []
	for sk in skills():
		var id := String(sk.get("id", ""))
		skill_ids.append(id)
		var kind := String(sk.get("kind", "attack"))
		if kind == "attack" and not weapons.has(String(sk.get("weapon", ""))):
			problems.append("skill %s: senjata %s tidak dikenal" % [id, str(sk.get("weapon"))])
		if kind not in ["attack", "buff", "heal"]:
			problems.append("skill %s: kind asing" % id)
		if float(sk.get("sp", 0)) < 0.0:
			problems.append("skill %s: SP negatif" % id)

	if party_defs().is_empty():
		problems.append("party kosong")
	for p in party_defs():
		var id := String(p.get("id", ""))
		for w in _string_list(p.get("weapons", [])):
			if not weapons.has(w):
				problems.append("party %s: senjata %s tidak dikenal" % [id, w])
		for s in _string_list(p.get("skills", [])):
			if not skill_ids.has(s):
				problems.append("party %s: skill %s tidak ada" % [id, s])
		for i in _string_list(p.get("items", [])):
			if not item_ids.has(i):
				problems.append("party %s: item %s tidak ada" % [id, i])
		if String(p.get("def_path", "")) == "":
			problems.append("party %s: def_path kosong" % id)

	if enemies().is_empty():
		problems.append("daftar musuh kosong")
	for e in enemies():
		var id := String(e.get("id", ""))
		var shield := int(e.get("shield", 0))
		if shield < int(b.get("shield_min", 2)) or shield > int(b.get("shield_max", 8)):
			problems.append("musuh %s: shield %d di luar 2..8" % [id, shield])
		var weak := _string_list(e.get("weak", []))
		if weak.is_empty():
			problems.append("musuh %s tidak punya kelemahan: tidak akan pernah BREAK" % id)
		for w in weak:
			if not weapons.has(w) and not elements.has(w):
				problems.append("musuh %s: kelemahan %s bukan senjata atau elemen" % [id, w])
		if String(e.get("def_path", "")) == "":
			problems.append("musuh %s: def_path kosong" % id)
		var rng_list: Array = _string_list(e.get("ai", []))
		for step in rng_list:
			if step not in ["attack", "charge"]:
				problems.append("musuh %s: langkah AI asing (%s)" % [id, step])
		var reward: Dictionary = e.get("reward", {}) if typeof(e.get("reward", {})) == TYPE_DICTIONARY else {}
		if float(reward.get("exp", 0)) <= 0.0:
			problems.append("musuh %s tidak memberi EXP" % id)
		for phase in _dict_list(e.get("phases", [])):
			for w in _string_list(phase.get("add_weak", [])):
				if not weapons.has(w) and not elements.has(w):
					problems.append("musuh %s: kelemahan fase %s tidak dikenal" % [id, w])

	for enc in encounters():
		var id := String(enc.get("id", ""))
		var list := _string_list(enc.get("enemies", []))
		if list.is_empty() or list.size() > 5:
			problems.append("encounter %s: 1..5 musuh, ada %d" % [id, list.size()])
		for e in list:
			if enemy(e).is_empty():
				problems.append("encounter %s: musuh %s tidak ada" % [id, e])


func ok() -> bool:
	return problems.is_empty()


# ------------------------------------------------------------------- utils ---
func _dict_list(raw: Variant) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for item in (raw as Array):
		if typeof(item) == TYPE_DICTIONARY:
			out.append(item)
	return out


func _string_list(raw: Variant) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for item in (raw as Array):
		out.append(String(item))
	return out


func _find(rows: Array, id: String) -> Dictionary:
	for row in rows:
		if String((row as Dictionary).get("id", "")) == id:
			return row
	return {}
