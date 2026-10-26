extends Node
## Step 3C rules: the battle tables, the turn engine, and 1000 simulated battles.
##
## Headless on purpose. A screenshot can show a menu with the right words on it;
## it cannot show that a shield actually runs out, that BP is spent exactly once,
## that a broken enemy really loses its turn, that a boss's second phase opens a
## new weakness, or that a battle which uses Break + Boost finishes in 5-8 turns
## while one that ignores them does not.
##
## The 1000 battles run against the SAME policy the Auto button uses
## (`BattleLogic.suggest_action`), so the numbers below are the numbers a player
## who taps Auto really gets.

const DATA := "res://game/battle/battle_data.json"
const DATA_SCRIPT := "res://game/battle/BattleData.gd"
const LOGIC_SCRIPT := "res://game/battle/BattleLogic.gd"
const SAVE_SCRIPT := "res://game/save/SaveGame.gd"
const ATLAS_JSON := "res://game/assets/ui/atlas_ui.json"

const BATTLES := 1000
const ENCOUNTER := "ujian_orc"

var checks := 0
var failures := 0
var _data: RefCounted
var _logic_script: Script


func _ready() -> void:
	await get_tree().process_frame
	if not _load():
		print("[BATTLE] tidak bisa memuat data, %d gagal" % failures)
		get_tree().quit(1)
		return
	_test_tables()
	_test_formula()
	_test_shield_and_break()
	_test_boost()
	_test_weakness_learning()
	_test_boss_phase()
	_test_ambush()
	_test_flee()
	_test_items_and_skills()
	await _test_simulation()
	_test_save()
	print("[BATTLE] %d pemeriksaan, %d gagal" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _check(cond: bool, label: String, extra: String = "") -> void:
	checks += 1
	if cond:
		print("[BATTLE] PASS %s" % label)
	else:
		failures += 1
		print("[BATTLE] FAIL %s %s" % [label, extra])


func _load() -> bool:
	if not FileAccess.file_exists(DATA):
		_check(false, "battle_data.json ada", DATA)
		return false
	var script: Script = load(DATA_SCRIPT)
	if script == null:
		_check(false, "BattleData.gd termuat")
		return false
	_data = script.new()
	_check(bool(_data.call("ok")), "battle_data.json lolos validasi",
		str(_data.get("problems")))
	var logic_script: Script = load(LOGIC_SCRIPT)
	if logic_script == null:
		_check(false, "BattleLogic.gd termuat")
		return false
	_logic_script = logic_script
	return true


func _battle(seed_value: int, enemy_line: Array = [], party: Array = ["knight"]) -> RefCounted:
	var line := enemy_line
	if line.is_empty():
		line = _data.call("encounter", ENCOUNTER).get("enemies", [])
	var b: RefCounted = _logic_script.new()
	b.call("setup", _data, party, line, seed_value)
	b.call("drain")
	return b


## Hand the engine turns until it is an ally's turn (or the battle ends), and
## return that ally. Every test needs this, because between one ally action and
## the next the four enemies get theirs.
func _ally_turn(b: RefCounted) -> Dictionary:
	var guard := 0
	while guard < 200:
		guard += 1
		if bool(b.get("finished")):
			return {}
		var unit: Dictionary = b.call("next_actor")
		if unit.is_empty():
			return {}
		if String(unit["side"]) == "foe":
			b.call("play_enemy_turn")
			b.call("drain")
			continue
		return unit
	return {}


# ------------------------------------------------------------------ tables ---
func _test_tables() -> void:
	_check((_data.get("weapons") as Array).size() == 6, "enam senjata didefinisikan")
	_check((_data.get("elements") as Array).size() == 6, "enam elemen didefinisikan")
	_check((_data.call("party_defs") as Array).size() >= 1, "party punya minimal satu karakter")
	_check((_data.call("enemies") as Array).size() >= 3, "tiga jenis musuh orc ada")
	var knight: Dictionary = _data.call("party_def", "knight")
	_check(String(knight.get("name", "")) == "Knight", "Knight ada di tabel party")
	var weapons: Array = knight.get("weapons", [])
	_check(weapons.has("pedang") and weapons.has("tombak"), "Knight memakai pedang dan tombak", str(weapons))
	var skills: Array = []
	for raw in (knight.get("skills", []) as Array):
		skills.append(String(raw))
	_check(skills.size() == 3, "Knight punya tiga skill", str(skills))
	for want in ["tebas_naik", "hentak_perisai", "sumpah_penjaga"]:
		_check(skills.has(want), "skill %s ada" % want)
	# the weakness icons must exist as real PNGs or the "?" row is blank
	var names: Array = []
	var sizes: Dictionary = {}
	if FileAccess.file_exists(ATLAS_JSON):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ATLAS_JSON))
		if typeof(parsed) == TYPE_DICTIONARY:
			var entries: Dictionary = (parsed as Dictionary).get("entries", {})
			names = entries.keys()
			sizes = entries
	_check(names.size() >= 27, "atlas UI memuat ikon tempur baru", str(names.size()))
	var missing: Array = []
	for w in (_data.get("weapons") as Array):
		if not names.has("w_" + String(w)):
			missing.append("w_" + String(w))
	for e in (_data.get("elements") as Array):
		if not names.has("e_" + String(e)):
			missing.append("e_" + String(e))
	_check(missing.is_empty(), "setiap senjata dan elemen punya ikon", str(missing))
	# 6 weapons x 6 elements is the "?" wall the UI draws
	_check((_data.get("weapons") as Array).size() * (_data.get("elements") as Array).size() == 36,
		"papan kelemahan berukuran 6 x 6")
	print("[BATTLE] data: %d musuh, %d skill, %d item, %d encounter" % [
		(_data.call("enemies") as Array).size(), (_data.call("skills") as Array).size(),
		(_data.call("items") as Array).size(), (_data.call("encounters") as Array).size()])


# ----------------------------------------------------------------- formula ---
func _test_formula() -> void:
	var text := String(_data.call("formula_text"))
	_check(text.contains("ATK") and text.contains("DEF") and text.contains("Boost")
		and text.contains("Break"), "rumus damage terdokumentasi di berkas data", text.substr(0, 40))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var attacker := {"atk": 60, "matk": 40, "crit": 0}
	var soft := {"def": 10, "mdef": 10, "weak": []}
	var hard := {"def": 80, "mdef": 80, "weak": []}
	var a: Dictionary = _data.call("resolve_hit", attacker, soft, "tombak", 100.0, 0, false, 0.0, false, rng)
	var b: Dictionary = _data.call("resolve_hit", attacker, hard, "tombak", 100.0, 0, false, 0.0, false, rng)
	_check(int(a["damage"]) > int(b["damage"]), "DEF tinggi mengurangi damage",
		"%d vs %d" % [int(a["damage"]), int(b["damage"])])
	var plain: Dictionary = _data.call("resolve_hit", attacker, soft, "tombak", 100.0, 0, false, 0.0, false, rng)
	var broken: Dictionary = _data.call("resolve_hit", attacker, soft, "tombak", 100.0, 0, true, 0.0, false, rng)
	var ratio := float(broken["damage"]) / maxf(1.0, float(plain["damage"]))
	_check(ratio > 1.3 and ratio < 1.75, "BREAK menaikkan damage sekitar 1,5x", "%.2f" % ratio)
	var guarded: Dictionary = _data.call("resolve_hit", attacker, soft, "tombak", 100.0, 0, false, 0.0, true, rng)
	var guard_ratio := float(guarded["damage"]) / maxf(1.0, float(plain["damage"]))
	_check(guard_ratio < 0.6, "Bertahan memotong damage setengah", "%.2f" % guard_ratio)
	var strong: Dictionary = _data.call("resolve_hit", attacker, soft, "tombak", 130.0, 0, false, 0.0, false, rng)
	_check(int(strong["damage"]) > int(plain["damage"]), "power 130 lebih kuat dari power 100")
	var boosted: Dictionary = _data.call("resolve_hit", attacker, soft, "tombak", 100.0, 3, false, 0.0, false, rng)
	_check(int(boosted["damage"]) > int(plain["damage"]), "Boost menaikkan damage per pukulan")
	# six weapons x six elements: damage uses atk for weapons and matk for elements
	rng.seed = 11
	var phys: Dictionary = _data.call("resolve_hit", attacker, soft, "pedang", 100.0, 0, false, 0.0, false, rng)
	var magic: Dictionary = _data.call("resolve_hit", attacker, soft, "api", 100.0, 0, false, 0.0, false, rng)
	_check(int(phys["damage"]) > int(magic["damage"]), "senjata memakai ATK, elemen memakai MATK")
	# never zero, never negative: a level 1 hero must still be able to hurt a boss
	var tiny := {"atk": 1, "matk": 1, "crit": 0}
	var wall := {"def": 999, "mdef": 999, "weak": []}
	var chip: Dictionary = _data.call("resolve_hit", tiny, wall, "pedang", 100.0, 0, false, 0.0, false, rng)
	_check(int(chip["damage"]) >= 1, "damage tidak pernah nol atau negatif", str(chip["damage"]))
	var jitter_min := 2.0
	var jitter_max := 0.0
	var base := 0.0
	for i in range(200):
		var hit: Dictionary = _data.call("resolve_hit", attacker, soft, "tombak", 100.0, 0, false, 0.0, false, rng)
		var d := float(hit["damage"])
		if base == 0.0:
			base = d
		jitter_min = minf(jitter_min, d / base)
		jitter_max = maxf(jitter_max, d / base)
	_check(jitter_min > 0.85 and jitter_max < 1.15, "sebaran damage 0,95..1,05",
		"%.2f..%.2f" % [jitter_min, jitter_max])


# ----------------------------------------------------------- shield & break ---
func _test_shield_and_break() -> void:
	var b := _battle(5, ["orc_prajurit"])
	var foe: Dictionary = b.get("foes")[0]
	_check(int(foe["shield"]) == 3, "Orc Prajurit mulai dengan Shield 3", str(foe["shield"]))
	var hits := 0
	var guard := 0
	while int(foe["shield"]) > 0 and not bool(foe["broken"]) and int(foe["hp"]) > 0 and guard < 10:
		guard += 1
		if _ally_turn(b).is_empty():
			break
		var ev: Array = b.call("submit", {"kind": "skill", "id": "tebas_naik",
			"target": int(foe["uid"]), "boost": 0})
		b.call("drain")
		for raw in ev:
			var e: Dictionary = raw
			if String(e["kind"]) == "hit" and bool(e.get("weak", false)):
				hits += 1
	_check(bool(foe["broken"]) or int(foe["hp"]) <= 0,
		"tiga pukulan kelemahan mematahkan Shield 3", str(foe["shield"]))
	_check(hits <= 3, "BREAK terjadi setelah maksimal 3 pukulan lemah", str(hits))
	_check(not bool(foe["broken"]) or int(foe["shield"]) == 0, "Shield nol saat BREAK")
	# a broken enemy loses its next turn, and then comes back with a full shield
	var b2 := _battle(9, ["orc_prajurit"])
	var f2: Dictionary = b2.get("foes")[0]
	f2["shield"] = 1
	var ally: Dictionary = _ally_turn(b2)
	_check(not ally.is_empty(), "giliran pertama milik party (Speed)")
	# a plain sword swing is NOT a weakness of an Orc Prajurit (tombak/api/angin
	# are), so the shield only comes off with the spear skill
	b2.call("submit", {"kind": "skill", "id": "tebas_naik", "target": int(f2["uid"]), "boost": 0})
	b2.call("drain")
	_check(bool(f2["broken"]), "Shield habis = BREAK")
	# A broken unit never comes back from `next_actor()` while it is still broken -
	# it is skipped inside the engine - so the skip has to be read from the log it
	# leaves behind, not from a unit that is handed to us.
	var skipped := false
	var recovered := false
	for i in range(12):
		if bool(b2.get("finished")):
			break
		var unit: Dictionary = b2.call("next_actor")
		var ev: Array = b2.call("drain")
		for raw in ev:
			var e: Dictionary = raw
			if String(e.get("kind", "")) == "message" \
					and String(e.get("text", "")).contains("kehilangan giliran"):
				skipped = true
		if unit.is_empty():
			break
		if int(unit["uid"]) == int(f2["uid"]) and not bool(f2["broken"]) \
				and int(f2["shield"]) == int(f2["shield_max"]):
			recovered = true
			break
		if String(unit["side"]) == "foe":
			b2.call("play_enemy_turn")
		else:
			b2.call("submit", {"kind": "guard"})
		b2.call("drain")
	_check(skipped, "musuh yang BREAK kehilangan giliran")
	_check(recovered, "setelah pulih, Shield kembali penuh", str(f2["shield"]))
	# and the defence really is halved while broken
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var atk := {"atk": 50, "matk": 50, "crit": 0}
	var target := {"def": 100, "mdef": 100, "weak": []}
	var normal: Dictionary = _data.call("resolve_hit", atk, target, "pedang", 100.0, 0, false, 0.0, false, rng)
	var cracked: Dictionary = _data.call("resolve_hit", atk, target, "pedang", 100.0, 0, true, 0.0, false, rng)
	var ratio := float(cracked["damage"]) / maxf(1.0, float(normal["damage"]))
	_check(ratio > 1.8, "DEF musuh yang BREAK terpotong setengah", "%.2f" % ratio)


# ------------------------------------------------------------------- boost ---
func _test_boost() -> void:
	var b := _battle(21, ["orc_pemimpin"])
	var knight: Dictionary = b.get("allies")[0]
	_check(int(knight["bp"]) >= int(_data.call("balance_int", "bp_start", 1)),
		"BP mulai dari angka di data", str(knight["bp"]))
	# a fresh Knight holds 1 BP and gets 1 more at the start of its turn, so the
	# 4-hit case has to be staged with enough BP in hand - otherwise the engine
	# (correctly) pays for only what the unit has
	knight["bp"] = 3
	var before := int(knight["bp"])
	var ev: Array = b.call("submit", {"kind": "attack",
		"target": int(b.get("foes")[0]["uid"]), "boost": 3})
	b.call("drain")
	var hits := 0
	for raw in ev:
		if String((raw as Dictionary)["kind"]) == "hit":
			hits += 1
	_check(hits == 4, "3 BP = 4 pukulan", str(hits))
	_check(before - int(knight["bp"]) <= int(_data.call("balance_int", "bp_spend_max", 3)),
		"BP yang dipakai tidak melebihi batas", "%d -> %d" % [before, int(knight["bp"])])
	# BP is capped, and grows by one per own turn
	var b2 := _battle(22, ["orc_prajurit"])
	var a2: Dictionary = b2.get("allies")[0]
	a2["bp"] = int(_data.call("balance_int", "bp_max", 5))
	for i in range(12):
		var unit: Dictionary = b2.call("next_actor")
		if unit.is_empty():
			break
		if String(unit["side"]) == "ally":
			break
		b2.call("play_enemy_turn")
		b2.call("drain")
	_check(int(a2["bp"]) <= int(_data.call("balance_int", "bp_max", 5)),
		"BP tidak melewati maksimum", str(a2["bp"]))
	_check(int(_data.call("balance_int", "bp_spend_max", 3)) == 3, "paling banyak 3 BP sekali pakai")


# -------------------------------------------------------------- weaknesses ---
func _test_weakness_learning() -> void:
	var b := _battle(31, ["orc_pemimpin"])
	var boss: Dictionary = b.get("foes")[0]
	var observed: Dictionary = b.get("observed")
	_check((observed.get("orc_pemimpin", []) as Array).is_empty(),
		"kelemahan musuh belum diketahui di awal (masih \"?\")")
	b.call("submit", {"kind": "skill", "id": "tebas_naik", "target": int(boss["uid"]), "boost": 0})
	b.call("drain")
	_check(bool(_data.call("shown_weak", observed, "orc_pemimpin", "tombak")),
		"kelemahan yang dipukul jadi diketahui")
	# elements are learned too, and only when they really are a weakness
	var b2 := _battle(32, ["orc_prajurit"])
	var foe: Dictionary = b2.get("foes")[0]
	var obs2: Dictionary = b2.get("observed")
	b2.call("submit", {"kind": "item", "id": "granat_api", "target": int(foe["uid"])})
	b2.call("drain")
	_check(bool(_data.call("shown_weak", obs2, "orc_prajurit", "api")),
		"kelemahan elemen ikut terungkap")
	var b3 := _battle(33, ["orc_prajurit"])
	var foe3: Dictionary = b3.get("foes")[0]
	var obs3: Dictionary = b3.get("observed")
	b3.call("submit", {"kind": "item", "id": "botol_es", "target": int(foe3["uid"])})
	b3.call("drain")
	_check(not bool(_data.call("shown_weak", obs3, "orc_prajurit", "es")),
		"pukulan yang bukan kelemahan tidak membuka apa pun")
	var weak: Array = (foe3["weak"] as Array).duplicate()
	weak.sort()
	_check(weak.size() == 3, "setiap orc punya tepat tiga kelemahan", str(weak))


# -------------------------------------------------------------- boss phases ---
func _test_boss_phase() -> void:
	var b := _battle(41, ["orc_pemimpin"])
	var boss: Dictionary = b.get("foes")[0]
	_check(int(boss["phase"]) == 1, "pemimpin mulai di fase 1")
	boss["hp"] = int(float(boss["hp_max"]) * 0.5) + 1
	b.call("submit", {"kind": "skill", "id": "tebas_naik", "target": int(boss["uid"]), "boost": 0})
	var ev: Array = b.call("drain")
	var phased := false
	for raw in ev:
		if String((raw as Dictionary)["kind"]) == "phase":
			phased = true
	_check(phased, "pemimpin berganti fase di 50% HP")
	_check(int(boss["phase"]) == 2, "fase 2 tercatat", str(boss["phase"]))
	_check((boss["weak"] as Array).has("petir"), "fase 2 membuka kelemahan baru (petir)", str(boss["weak"]))
	_check(int(boss["shield"]) == int(boss["shield_max"]), "fase 2 mengembalikan Shield penuh")
	var b2 := _battle(42, ["orc_pemimpin"])
	var boss2: Dictionary = b2.get("foes")[0]
	_check(int(boss2["shield"]) == 6, "Pemimpin mulai dengan Shield 6", str(boss2["shield"]))


# ------------------------------------------------------------------ ambush ---
func _test_ambush() -> void:
	var b := _battle(51, ["orc_prajurit", "orc_prajurit"])
	var knight: Dictionary = b.get("allies")[0]
	var foe: Dictionary = b.get("foes")[0]
	var bp_before := int(knight["bp"])
	var shield_before := int(foe["shield"])
	b.call("apply_ambush")
	_check(int(knight["bp"]) == bp_before + 1, "kejutan memberi +1 BP", str(int(knight["bp"])))
	_check(int(foe["shield"]) == shield_before - 1, "kejutan memotong 1 Shield musuh",
		str(int(foe["shield"])))
	var enc: Dictionary = _data.call("encounter", "pos_gunung")
	_check(bool(enc.get("ambush", false)), "encounter lapangan ditandai sebagai kejutan")


# -------------------------------------------------------------------- flee ---
func _test_flee() -> void:
	var b := _battle(61, ["orc_pemimpin"])
	_ally_turn(b)
	b.call("submit", {"kind": "flee"})
	var ev: Array = b.call("drain")
	var blocked := false
	for raw in ev:
		var e: Dictionary = raw
		if String(e["kind"]) == "flee" and not bool(e.get("ok", false)):
			blocked = true
	_check(blocked, "tidak bisa kabur dari pertarungan bos")
	_check(not bool(b.get("finished")), "kabur yang gagal tidak mengakhiri pertarungan")
	var b2 := _battle(62, ["orc_prajurit"])
	var fled := false
	var tried := 0
	while tried < 30 and not fled:
		tried += 1
		if _ally_turn(b2).is_empty():
			break
		b2.call("submit", {"kind": "flee"})
		b2.call("drain")
		if bool(b2.get("finished")):
			fled = String(b2.get("result")) == "flee"
			break
	_check(fled, "kabur dari orc biasa bisa berhasil", "percobaan %d" % tried)


# ------------------------------------------------------- items and skills ---
func _test_items_and_skills() -> void:
	var b := _battle(71, ["orc_prajurit"])
	var knight: Dictionary = b.get("allies")[0]
	var before_sp := int(knight["sp"])
	b.call("submit", {"kind": "skill", "id": "tebas_naik", "target": int(b.get("foes")[0]["uid"]), "boost": 0})
	b.call("drain")
	_check(int(knight["sp"]) == before_sp - 6, "skill memakai SP dari data",
		"%d -> %d" % [before_sp, int(knight["sp"])])
	knight["hp"] = 40
	var inv_before := int((b.get("inventory") as Dictionary).get("ramuan", 0))
	b.call("submit", {"kind": "item", "id": "ramuan", "target": int(knight["uid"])})
	b.call("drain")
	_check(int(knight["hp"]) > 40, "Ramuan memulihkan HP", str(knight["hp"]))
	_check(int((b.get("inventory") as Dictionary).get("ramuan", 0)) == inv_before - 1,
		"item berkurang satu")
	var b2 := _battle(72, ["orc_prajurit"])
	var k2: Dictionary = b2.get("allies")[0]
	var def_before := float(k2["def_up"])
	b2.call("submit", {"kind": "skill", "id": "sumpah_penjaga", "boost": 0})
	b2.call("drain")
	_check(float(k2["def_up"]) > def_before, "Sumpah Penjaga menaikkan DEF", str(k2["def_up"]))
	_check(int(k2["def_up_turns"]) == 3, "buff bertahan tiga giliran", str(k2["def_up_turns"]))


# ------------------------------------------------------------- simulation ---
func _test_simulation() -> void:
	var t0 := Time.get_ticks_msec()
	var rounds: Array = []
	var wins := 0
	var boost_used := 0
	var breaks := 0
	for seed_value in range(BATTLES):
		var b := _battle(seed_value)
		var guard := 0
		while not bool(b.get("finished")) and guard < 400:
			guard += 1
			var unit: Dictionary = b.call("next_actor")
			if unit.is_empty():
				break
			if String(unit["side"]) == "foe":
				b.call("play_enemy_turn")
			else:
				var action: Dictionary = b.call("suggest_action")
				boost_used += int(action.get("boost", 0))
				var ev: Array = b.call("submit", action)
				for raw in ev:
					if String((raw as Dictionary)["kind"]) == "break":
						breaks += 1
			b.call("drain")
			if guard >= 399:
				break
		rounds.append(int(b.get("round")))
		if String(b.get("result")) == "win":
			wins += 1
	var ms := Time.get_ticks_msec() - t0
	var total := 0.0
	var worst := 0
	for r in rounds:
		total += float(r)
		worst = maxi(worst, int(r))
	var mean := total / maxf(1.0, float(rounds.size()))
	var sorted := rounds.duplicate()
	sorted.sort()
	var median: int = int(sorted[sorted.size() / 2])
	print("[BATTLE] simulasi: %d pertarungan, %.0f ms, menang %d (%.1f%%), giliran rata-rata %.2f, median %d, terburuk %d, Boost dipakai %d, BREAK %d" % [
		BATTLES, float(ms), wins, 100.0 * float(wins) / float(BATTLES), mean, median, worst,
		boost_used, breaks])
	_check(wins >= int(float(BATTLES) * 0.95), "Auto (Break + Boost) menang hampir selalu",
		"%d dari %d" % [wins, BATTLES])
	_check(mean >= 4.5 and mean <= 9.0, "panjang pertarungan 5-8 giliran", "rata-rata %.2f" % mean)
	_check(median >= 5 and median <= 8, "median pertarungan 5-8 giliran", str(median))
	_check(worst <= 30, "tidak ada pertarungan yang menggantung", str(worst))
	_check(breaks > BATTLES, "BREAK benar-benar terjadi di hampir setiap pertarungan", str(breaks))
	_check(boost_used > BATTLES, "Boost benar-benar dipakai", str(boost_used))

	# the other half of the design: ignoring Break and Boost has to be worse
	var dumb_wins := 0
	var dumb_rounds := 0.0
	for seed_value in range(200):
		var b := _battle(10000 + seed_value)
		var guard := 0
		while not bool(b.get("finished")) and guard < 400:
			guard += 1
			var unit: Dictionary = b.call("next_actor")
			if unit.is_empty():
				break
			if String(unit["side"]) == "foe":
				b.call("play_enemy_turn")
			else:
				b.call("submit", {"kind": "attack", "boost": 0})
			b.call("drain")
		if String(b.get("result")) == "win":
			dumb_wins += 1
		dumb_rounds += float(b.get("round"))
	print("[BATTLE] tanpa Break/Boost: menang %d dari 200, giliran rata-rata %.1f" % [
		dumb_wins, dumb_rounds / 200.0])
	_check(dumb_wins < 120, "tanpa Break + Boost, kalah jauh lebih sering",
		"%d dari 200" % dumb_wins)


# -------------------------------------------------------------------- save ---
func _test_save() -> void:
	var script: Script = load(SAVE_SCRIPT)
	if script == null:
		_check(false, "SaveGame.gd termuat")
		return
	var dir := "user://t_battle_save"
	var save: RefCounted = script.new(dir)
	save.call("erase")
	save.call("load_game")
	_check(int(save.get("schema")) >= 3, "save sudah punya skema untuk hasil pertarungan",
		str(save.get("schema")))
	var blob := {
		"battles_won": 4,
		"battles_lost": 1,
		"leaf": 240,
		"exp": 620,
		"level": 3,
		"hp": 300,
		"sp": 22,
		"observed": {"orc_prajurit": ["tombak", "api"], "orc_pemimpin": ["es"]},
		"items": {"ramuan": 1, "elixir": 2},
	}
	save.call("set_battle", blob)
	var error := String(save.call("save_now"))
	_check(error == "", "hasil pertarungan tersimpan", error)
	var again: RefCounted = script.new(dir)
	var note := String(again.call("load_game"))
	var read: Dictionary = again.call("battle")
	_check(note == "save_dibaca", "save terbaca lagi", note)
	_check(int(read.get("battles_won", 0)) == 4, "jumlah kemenangan tersimpan",
		str(read.get("battles_won")))
	_check(int(read.get("leaf", 0)) == 240, "Leaf tersimpan", str(read.get("leaf")))
	var obs: Dictionary = read.get("observed", {})
	_check((obs.get("orc_prajurit", []) as Array).size() == 2,
		"kelemahan yang sudah terungkap ikut tersimpan", str(obs))
	# an older save without the battle blob must still load
	var old := script.new(dir + "_old")
	old.call("erase")
	old.call("load_game")
	old.call("set_counter", "orcs_defeated", 2)
	old.call("save_now")
	var upgraded: RefCounted = script.new(dir + "_old")
	var note2 := String(upgraded.call("load_game"))
	_check(note2 == "save_dibaca", "save lama tetap terbaca", note2)
	_check((upgraded.call("battle") as Dictionary).is_empty(),
		"save lama mulai tanpa hasil pertarungan")
	_check(int(upgraded.call("get_counter", "orcs_defeated")) == 2, "progres lama tidak hilang")
	for d in [dir, dir + "_old"]:
		var cleanup: RefCounted = script.new(d)
		cleanup.call("erase")
