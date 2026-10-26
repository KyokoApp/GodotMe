extends RefCounted
## Re - Traveller : the turn engine. No nodes, no timers, no drawing.
##
## Everything that decides a battle happens here, which is the only reason the
## 1000-battle simulator in `BattleTest` can run in a few seconds: it feeds this
## class actions and reads the event list, never a scene tree.
##
## Rules, in the order they matter:
##
##   * Turn order is Speed, highest first, rebuilt every round. A broken unit
##     loses its next turn and then recovers - it does not simply act later.
##   * BP (Boost Points) start at `bp_start`, +1 at the beginning of each of the
##     actor's own turns, capped at `bp_max`. Up to `bp_spend_max` may go into one
##     action; each point spent adds a hit and 25% per hit.
##   * Shield: every hit of a type the target is WEAK to removes one layer (some
##     skills remove two). At zero the target BREAKS: it loses its next turn, its
##     DEF is halved, incoming damage is x1.5, and its shield comes back full when
##     it recovers. A charging enemy that breaks loses its charge.
##   * Weaknesses are learned, not printed: `observed` remembers what the party
##     has actually hit with, per enemy id, and the UI shows "?" for the rest.
##   * A boss has phases: at `at_hp` it gains a new weakness and new numbers.
##
## The event list is the UI's only input. Every event is a small Dictionary with
## a "kind"; `BattleUI` turns them into animation and floating numbers, and the
## simulator only counts them.

const ROLE_ALLY := "ally"
const ROLE_FOE := "foe"

var data = null                      ## BattleData, untyped so calls stay dynamic
var rng := RandomNumberGenerator.new()

var units: Array = []                ## every unit, allies first
var allies: Array = []
var foes: Array = []
var observed: Dictionary = {}        ## enemy id -> Array of learned tags
var inventory: Dictionary = {}       ## item id -> count (party-wide)
var events: Array = []
var messages: Array = []

var round := 1
var finished := false
var result := ""                     ## "win" / "lose" / "flee"
var awaiting := {}                   ## the ally unit whose turn it is ({} = none)
var order: Array = []                ## unit uids still to act this round
var turn_count := 0                  ## how many units have acted (the "giliran")
var ambush := false
## Display-only: the party's level (BattleScene keeps it in step with the save)
## and every weakness type the party has ever TRIED, so the knowledge board can
## grey out a wrong guess instead of leaving it as a "?" forever.
var level := 1
var tried: Dictionary = {}


# ------------------------------------------------------------------- setup ---
## `party` is the list of party ids (only "knight" today), `enemy_ids` the line
## in `battle_data.json`'s encounter. `seed` makes the whole battle repeatable.
func setup(battle_data, party_ids: Array, enemy_ids: Array, seed_value: int = 0) -> void:
	data = battle_data
	rng.seed = seed_value
	units.clear()
	allies.clear()
	foes.clear()
	events.clear()
	messages.clear()
	observed.clear()
	inventory.clear()
	tried.clear()
	ambush = false
	finished = false
	result = ""
	round = 1
	turn_count = 0
	awaiting = {}
	var bp_start: int = int(data.call("balance_int", "bp_start", 1))
	for raw in party_ids:
		var p: Dictionary = data.call("party_def", String(raw))
		if p.is_empty():
			continue
		var unit := _unit_from(p, ROLE_ALLY)
		unit["bp"] = bp_start
		unit["skills"] = p.get("skills", [])
		for item_id in (p.get("items", []) as Array):
			inventory[String(item_id)] = int(inventory.get(String(item_id), 0)) + 2
		allies.append(unit)
	for raw in enemy_ids:
		var e: Dictionary = data.call("enemy", String(raw))
		if e.is_empty():
			continue
		var unit := _unit_from(e, ROLE_FOE)
		unit["shield"] = int(e.get("shield", 3))
		unit["shield_max"] = int(unit["shield"])
		# duplicated: a boss's second phase ADDS a weakness, and appending to the
		# table's own array would leak that weakness into every later battle in the
		# same process (the 1000-battle simulator runs them all in one)
		unit["weak"] = (e.get("weak", []) as Array).duplicate()
		unit["boss"] = bool(e.get("boss", false))
		unit["ai"] = e.get("ai", ["attack"])
		unit["charge"] = e.get("charge", {})
		unit["phases"] = e.get("phases", [])
		unit["reward"] = e.get("reward", {})
		unit["ai_step"] = 0
		foes.append(unit)
	for u in allies:
		units.append(u)
	for u in foes:
		units.append(u)
	for i in range(units.size()):
		(units[i] as Dictionary)["uid"] = i
	begin_round()


func _unit_from(row: Dictionary, side: String) -> Dictionary:
	var hp := int(row.get("hp", 100))
	return {
		"uid": -1,
		"side": side,
		"id": String(row.get("id", "")),
		"name": String(row.get("name", row.get("id", "?"))),
		"def_path": String(row.get("def_path", "")),
		"hp": hp,
		"hp_max": hp,
		"sp": int(row.get("sp", 0)),
		"sp_max": int(row.get("sp", 0)),
		"atk": int(row.get("atk", 10)),
		"def": int(row.get("def", 10)),
		"matk": int(row.get("matk", 10)),
		"mdef": int(row.get("mdef", 10)),
		"spd": int(row.get("spd", 10)),
		"crit": int(row.get("crit", 0)),
		"eva": int(row.get("eva", 0)),
		"shield": int(row.get("shield", 0)),
		"shield_max": int(row.get("shield", 0)),
		"weak": row.get("weak", []),
		"bp": 0,
		"boost": 0,
		"broken": false,
		"break_turns": 0,
		"guard": false,
		"def_up": 0.0,
		"def_up_turns": 0,
		"charging": false,
		"phase": 1,
		"alive": hp > 0,
		"weapons": row.get("weapons", []),
		"skills": [],
		"ai": [],
		"ai_step": 0,
		"boss": false,
		"phases": [],
		"charge": {},
		"reward": {},
	}


## Ambush: the party arrives first (+1 BP each) and the enemies' shields are one
## layer thinner, which is what "kejutan" buys.
func apply_ambush() -> void:
	ambush = true
	for a in allies:
		(a as Dictionary)["bp"] = mini(int(data.call("balance_int", "bp_max", 5)),
			int((a as Dictionary)["bp"]) + 1)
	if not foes.is_empty():
		var f: Dictionary = foes[0]
		f["shield"] = maxi(int(data.call("balance_int", "shield_min", 2)),
			int(f["shield"]) - 1)
		f["shield_max"] = int(f["shield"])
	_push({"kind": "message", "text": "Kejutan! Party menyerang lebih dulu."})


# ------------------------------------------------------------------ rounds ---
func begin_round() -> void:
	order.clear()
	# speed first; a tie is broken by uid so a seeded battle is reproducible
	var living: Array = []
	for u in units:
		if bool((u as Dictionary)["alive"]):
			living.append(u)
	living.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["spd"]) == int(b["spd"]):
			return int(a["uid"]) < int(b["uid"])
		return int(a["spd"]) > int(b["spd"]))
	for u in living:
		order.append(int((u as Dictionary)["uid"]))
	_push({"kind": "round", "round": round})


## The next eight actors, for the turn bar. Read-only: it does not consume the
## queue, so the UI can draw it every frame.
func turn_preview(count: int = 0) -> Array:
	var want := count if count > 0 else int(data.call("balance_int", "turn_bar_entries", 8))
	var out: Array = []
	for uid in order:
		if out.size() >= want:
			break
		out.append(units[int(uid)])
	# a short round is padded from the next one, so the bar never looks empty
	if out.size() < want:
		for u in units:
			if out.size() >= want:
				break
			if bool((u as Dictionary)["alive"]):
				out.append(u)
	return out


## Pop the queue until a unit that can actually act is found. That unit is now
## `awaiting`: an ally waits for `submit()`, an enemy is played by
## `play_enemy_turn()`. A broken unit loses the turn here, and recovers after.
func next_actor() -> Dictionary:
	var guard := 0
	while not finished and guard < 64:
		guard += 1
		if order.is_empty():
			round += 1
			begin_round()
			if order.is_empty():
				return {}
		var uid := int(order.pop_front())
		var unit: Dictionary = units[uid]
		if not bool(unit["alive"]):
			continue
		turn_count += 1
		_tick_start_of_turn(unit)
		if bool(unit["broken"]):
			# a broken unit does not act: it loses this turn, and recovers after
			unit["break_turns"] = int(unit["break_turns"]) - 1
			_push({"kind": "message", "text": "%s kehilangan giliran." % unit["name"]})
			if int(unit["break_turns"]) <= 0:
				_recover(unit)
			continue
		awaiting = unit
		_push({"kind": "turn", "unit": unit})
		return unit
	return {}


# --------------------------------------------------------------- actions ----
## One ally action, from a tap or from Auto. Returns the events this action
## produced - the same list `drain()` would hand out - so the controller can
## animate exactly this action and nothing else.
##
## `submit()` is forgiving on purpose. A tap that lands one frame before the turn
## is announced, or right after the enemy's, is ordinary on a phone; it settles
## the queue instead of losing the input or, worse, playing the enemy's turn.
func submit(action: Dictionary) -> Array:
	var start := events.size()
	if finished:
		return []
	if awaiting.is_empty():
		var first: Dictionary = next_actor()
		if first.is_empty() or String(first["side"]) != ROLE_ALLY:
			return events.slice(start)
	var unit: Dictionary = awaiting
	if String(unit.get("side", "")) != ROLE_ALLY:
		return events.slice(start)
	var kind := String(action.get("kind", "attack"))
	var boost := 0
	# Boost is paid, capped by the rules (3) AND by what the unit actually holds.
	# The UI already clamps, but the engine is what the tests and Auto call.
	if kind == "attack" or kind == "skill":
		boost = clampi(int(action.get("boost", 0)), 0,
			mini(int(data.call("balance_int", "bp_spend_max", 3)), int(unit["bp"])))
		if boost > 0:
			unit["bp"] = int(unit["bp"]) - boost
			_push({"kind": "boost", "unit": unit, "bp": boost})
	if kind == "guard":
		unit["guard"] = true
		_push({"kind": "guard", "unit": unit})
		_push({"kind": "message", "text": "%s bertahan." % unit["name"]})
	elif kind == "flee":
		_try_flee(unit)
	elif kind == "item":
		var item_id := String(action.get("id", ""))
		var item: Dictionary = data.call("item", item_id)
		var item_target := _pick_target(action, unit, String(item.get("target", "ally")))
		if not item_target.is_empty():
			_use_item(unit, item_id, item_target)
	elif kind == "skill":
		var skill_id := String(action.get("id", ""))
		var sk: Dictionary = data.call("skill", skill_id)
		var skill_target := _pick_target(action, unit, String(sk.get("target", "enemy")))
		if not skill_target.is_empty():
			_use_skill(unit, skill_id, skill_target, boost)
	else:
		var hit_target := _pick_target(action, unit, "enemy")
		if not hit_target.is_empty():
			_attack(unit, hit_target, boost, _primary_weapon(unit))
	awaiting = {}
	_check_end()
	return events.slice(start)


## One enemy action. Also returns its own events; the controller plays them at
## the same speed it plays the party's.
func play_enemy_turn() -> Array:
	var start := events.size()
	if finished:
		return []
	if awaiting.is_empty():
		var first: Dictionary = next_actor()
		if first.is_empty() or String(first["side"]) != ROLE_FOE:
			return events.slice(start)
	var unit: Dictionary = awaiting
	if String(unit.get("side", "")) != ROLE_FOE:
		return events.slice(start)
	_enemy_act(unit)
	awaiting = {}
	_check_end()
	return events.slice(start)


func _tick_start_of_turn(unit: Dictionary) -> void:
	unit["guard"] = false
	if int(unit["def_up_turns"]) > 0:
		unit["def_up_turns"] = int(unit["def_up_turns"]) - 1
		if int(unit["def_up_turns"]) <= 0:
			unit["def_up"] = 0.0
	if String(unit["side"]) == ROLE_ALLY:
		unit["bp"] = mini(int(data.call("balance_int", "bp_max", 5)),
			int(unit["bp"]) + int(data.call("balance_int", "bp_per_turn", 1)))


func boss_busy() -> bool:
	for f in foes:
		if bool((f as Dictionary)["alive"]) and bool((f as Dictionary)["boss"]):
			return true
	return false


# ------------------------------------------------------------------- hits ---
func _primary_weapon(unit: Dictionary) -> String:
	var list: Array = unit.get("weapons", [])
	if list.is_empty():
		return "pedang"
	return String(list[0])


## What an action points at. A heal wants an ally, a hit wants an enemy, and a
## buff wants the caster - so a stray tap on the wrong side of the screen falls
## back to something sensible instead of healing a monster.
func _pick_target(action: Dictionary, unit: Dictionary, want: String) -> Dictionary:
	if want == "self":
		return unit
	var uid := int(action.get("target", -1))
	if uid >= 0 and uid < units.size():
		var picked: Dictionary = units[uid]
		if bool(picked["alive"]):
			if want == "enemy" and String(picked["side"]) == ROLE_FOE:
				return picked
			if want == "ally" and String(picked["side"]) == ROLE_ALLY:
				return picked
	if want == "ally":
		return unit
	return _first_living(ROLE_FOE)


func _first_living(side: String) -> Dictionary:
	for u in units:
		var unit: Dictionary = u
		if String(unit["side"]) == side and bool(unit["alive"]):
			return unit
	return {}


func _living(side: String) -> Array:
	var out: Array = []
	for u in units:
		var unit: Dictionary = u
		if String(unit["side"]) == side and bool(unit["alive"]):
			out.append(unit)
	return out


## A weapon hit: `hits` swings at `power` each. `extra_shield` is what a skill
## like Hentak Perisai adds on top of the one layer a weakness already removes.
func _attack(attacker: Dictionary, target: Dictionary, boost: int, tag: String,
		power: float = 100.0, extra_shield: int = 0) -> void:
	if target.is_empty():
		return
	var hits := 1 + boost
	for i in range(hits):
		if not bool(target["alive"]) or finished:
			break
		_strike(attacker, target, tag, power, boost, extra_shield)


func _strike(attacker: Dictionary, target: Dictionary, tag: String, power: float,
		boost: int, extra_shield: int = 0) -> void:
	if _evaded(target):
		_push({"kind": "miss", "unit": target, "tag": tag})
		return
	var broken := bool(target["broken"])
	var hit: Dictionary = data.call("resolve_hit", attacker, target, tag, power, boost,
		broken, float(target["def_up"]), bool(target["guard"]), rng)
	var dmg := int(hit["damage"])
	target["hp"] = maxi(0, int(target["hp"]) - dmg)
	_push({
		"kind": "hit",
		"src": attacker,
		"unit": target,
		"damage": dmg,
		"crit": bool(hit["crit"]),
		"weak": bool(hit["weak"]),
		"guard": bool(target["guard"]),
		"tag": tag,
		"broken": broken,
		"hp_after": int(target["hp"]),
	})
	# "tried" is display only; the real table is `observed`
	tried[tag] = true
	# learning: only a real weakness teaches the party what it is
	if bool(hit["weak"]):
		data.call("mark_weak", observed, String(target["id"]), tag)
		var lost := 1 + extra_shield
		if int(target["shield"]) > 0:
			target["shield"] = maxi(0, int(target["shield"]) - lost)
			_push({"kind": "shield", "unit": target, "shield": int(target["shield"])})
			if int(target["shield"]) <= 0:
				_break(target)
	else:
		# hitting a non-weakness still names the MISS: the UI greys that icon in
		_push({"kind": "resist", "unit": target, "tag": tag})
	_check_phase(target)
	if int(target["hp"]) <= 0:
		_down(target)


func _evaded(target: Dictionary) -> bool:
	var chance := float(int(target.get("eva", 0))) / 100.0
	return chance > 0.0 and rng.randf() < chance


func _break(unit: Dictionary) -> void:
	unit["broken"] = true
	unit["break_turns"] = int(data.call("balance_int", "break_turns", 1))
	if bool(unit["charging"]):
		unit["charging"] = false
		_push({"kind": "message", "text": "Tenaga %s buyar!" % unit["name"]})
	_push({"kind": "break", "unit": unit})


func _recover(unit: Dictionary) -> void:
	unit["broken"] = false
	unit["shield"] = int(unit["shield_max"])
	_push({"kind": "recover", "unit": unit})
	_push({"kind": "message", "text": "%s pulih, Shield penuh lagi." % unit["name"]})


func _down(unit: Dictionary) -> void:
	if not bool(unit["alive"]):
		return
	unit["alive"] = false
	unit["hp"] = 0
	unit["broken"] = false
	_push({"kind": "down", "unit": unit})


func _check_phase(unit: Dictionary) -> void:
	if not bool(unit.get("boss", false)) or int(unit["hp"]) <= 0:
		return
	var phases: Array = unit.get("phases", [])
	var ratio := float(unit["hp"]) / maxf(1.0, float(unit["hp_max"]))
	var index := int(unit["phase"]) - 1        # 0 = the first phase still to come
	while index < phases.size():
		var phase: Dictionary = phases[index]
		if ratio > float(phase.get("at_hp", 0.5)):
			return
		unit["phase"] = index + 2
		unit["atk"] = int(phase.get("atk", unit["atk"]))
		unit["spd"] = int(phase.get("spd", unit["spd"]))
		var weak: Array = unit["weak"]
		for w in (phase.get("add_weak", []) as Array):
			if not weak.has(String(w)):
				weak.append(String(w))
		# a new phase comes back with a full shield: it is a new problem to solve
		unit["shield"] = int(unit["shield_max"])
		_push({"kind": "phase", "unit": unit, "text": String(phase.get("text", ""))})
		_push({"kind": "message", "text": String(phase.get("text", ""))})
		index += 1


# ------------------------------------------------------------------ skills ---
func _use_skill(unit: Dictionary, skill_id: String, target: Dictionary, boost: int) -> void:
	var sk: Dictionary = data.call("skill", skill_id)
	if sk.is_empty():
		_attack(unit, target, boost, _primary_weapon(unit))
		return
	var cost := int(sk.get("sp", 0))
	if int(unit["sp"]) < cost:
		_push({"kind": "message", "text": "SP %s tidak cukup." % unit["name"]})
		return
	unit["sp"] = int(unit["sp"]) - cost
	_push({"kind": "skill", "unit": unit, "id": skill_id, "name": String(sk.get("name", ""))})
	_push({"kind": "message", "text": "%s memakai %s." % [unit["name"], String(sk.get("name", ""))]})
	var kind := String(sk.get("kind", "attack"))
	if kind == "buff":
		unit["def_up"] = float(sk.get("def_up", 0.0))
		unit["def_up_turns"] = int(sk.get("turns", 2))
		_push({"kind": "buff", "unit": unit, "def_up": float(unit["def_up"])})
		return
	if kind == "heal":
		var healed := mini(int(unit["hp_max"]), int(unit["hp"]) + int(sk.get("power", 0)))
		_push({"kind": "heal", "unit": unit, "amount": healed - int(unit["hp"])})
		unit["hp"] = healed
		return
	_attack(unit, target, boost, String(sk.get("weapon", _primary_weapon(unit))),
		float(sk.get("power", 100)), int(sk.get("shield_break", 0)))


func _use_item(unit: Dictionary, item_id: String, target: Dictionary) -> void:
	var count := int(inventory.get(item_id, 0))
	if count <= 0:
		_push({"kind": "message", "text": "%s habis." % item_id})
		return
	inventory[item_id] = count - 1
	var item: Dictionary = data.call("item", item_id)
	if item.is_empty():
		return
	_push({"kind": "item", "unit": unit, "id": item_id, "name": String(item.get("name", ""))})
	var kind := String(item.get("kind", "heal"))
	if kind == "heal":
		var healed := mini(int(target["hp_max"]),
			int(target["hp"]) + int(item.get("power", 0)))
		_push({"kind": "heal", "unit": target, "amount": healed - int(target["hp"])})
		target["hp"] = healed
		return
	if kind == "damage":
		_strike(unit, target, String(item.get("element", "api")),
			float(item.get("power", 100)), 0, 0)


func _try_flee(unit: Dictionary) -> void:
	var can_flee_boss := float(data.call("balance_float", "boss_flee", 0.0)) > 0.0
	if not can_flee_boss and boss_busy():
		_push({"kind": "message", "text": "Tidak bisa kabur dari pertarungan ini."})
		_push({"kind": "flee", "ok": false})
		return
	var chance := float(data.call("balance_float", "flee_base", 0.55))
	chance += (float(unit["spd"]) - _average_foe_speed()) * 0.02
	chance = clampf(chance, 0.05, 0.95)
	if rng.randf() < chance:
		finished = true
		result = "flee"
		_push({"kind": "flee", "ok": true})
		_push({"kind": "message", "text": "Berhasil kabur."})
		return
	_push({"kind": "flee", "ok": false})
	_push({"kind": "message", "text": "Gagal kabur."})


func _average_foe_speed() -> float:
	var living := _living(ROLE_FOE)
	if living.is_empty():
		return 0.0
	var total := 0.0
	for f in living:
		total += float((f as Dictionary)["spd"])
	return total / float(living.size())


## The Auto button's brain, and the simulator's policy, in one place - because a
## test that plays a different game from the player proves nothing.
##
## The policy is deliberately plain: heal below 35%, hit the foe that is charging
## its big attack, spend BP to finish a shield that is nearly gone, and otherwise
## put BP into damage while the target is broken. It knows only what the party has
## LEARNED (the `observed` table), never the enemy's hidden weakness list.
func suggest_action() -> Dictionary:
	if awaiting.is_empty():
		return {}
	var unit: Dictionary = awaiting
	var alive_foes := _living(ROLE_FOE)
	if alive_foes.is_empty():
		return {"kind": "guard"}
	# 1. survive first: a potion below a third saves more damage than one more hit
	if float(unit["hp"]) / maxf(1.0, float(unit["hp_max"])) < 0.35 \
			and int(inventory.get("ramuan", 0)) > 0:
		return {"kind": "item", "id": "ramuan", "target": int(unit["uid"])}
	# 2. the foe that is winding up is the one that will hurt most next turn
	var target: Dictionary = alive_foes[0]
	for raw in alive_foes:
		var f: Dictionary = raw
		if bool(f["charging"]):
			target = f
			break
		if int(f["hp"]) < int(target["hp"]) and not bool(target["charging"]):
			target = f
	var known: Variant = observed.get(String(target["id"]), [])
	var known_list: Array = known if typeof(known) == TYPE_ARRAY else []
	var skill_id := ""
	for raw in (unit.get("skills", []) as Array):
		var sk: Dictionary = data.call("skill", String(raw))
		if sk.is_empty():
			continue
		if String(sk.get("kind", "attack")) != "attack":
			continue
		if int(unit["sp"]) >= int(sk.get("sp", 0)):
			skill_id = String(sk.get("id", ""))
			break
	var bp := int(unit["bp"])
	var spend_max: int = int(data.call("balance_int", "bp_spend_max", 3))
	var spend := 0
	if int(target["shield"]) > 0:
		if int(target["shield"]) <= 2 and bp >= 1 and skill_id != "":
			spend = mini(bp, mini(spend_max, maxi(1, int(target["shield"]) - 1)))
		elif bp >= 2 and skill_id != "":
			spend = mini(bp, spend_max)
	elif skill_id != "":
		spend = mini(bp, mini(spend_max, 2))
	# 3. probe with a known weakness when the first choice is not one
	if not known_list.is_empty() and not known_list.has("tombak"):
		if known_list.has("pedang"):
			return {"kind": "attack", "target": int(target["uid"]), "boost": spend}
		if known_list.has("es") and int(inventory.get("botol_es", 0)) > 0:
			return {"kind": "item", "id": "botol_es", "target": int(target["uid"])}
		if known_list.has("api") and int(inventory.get("granat_api", 0)) > 0:
			return {"kind": "item", "id": "granat_api", "target": int(target["uid"])}
	if skill_id != "":
		return {"kind": "skill", "id": skill_id, "target": int(target["uid"]), "boost": spend}
	return {"kind": "attack", "target": int(target["uid"]), "boost": spend}


# --------------------------------------------------------------------- AI ---
func _enemy_act(unit: Dictionary) -> void:
	var target := _pick_ally_target()
	if target.is_empty():
		return
	if bool(unit["charging"]):
		var payload: Dictionary = unit.get("charge", {})
		unit["charging"] = false
		_push({"kind": "message", "text": "%s melepaskan tenaganya!" % unit["name"]})
		_attack(unit, target, 0, String(_primary_weapon(unit)),
			float(payload.get("power", 180)))
		return
	var steps: Array = unit.get("ai", ["attack"])
	var step := String(steps[int(unit["ai_step"]) % steps.size()])
	unit["ai_step"] = int(unit["ai_step"]) + 1
	if step == "charge" and not (unit.get("charge", {}) as Dictionary).is_empty():
		unit["charging"] = true
		_push({"kind": "charge", "unit": unit})
		_push({"kind": "message",
			"text": String((unit.get("charge", {}) as Dictionary).get("text", ""))})
		return
	_attack(unit, target, 0, String(_primary_weapon(unit)))


func _pick_ally_target() -> Dictionary:
	var living := _living(ROLE_ALLY)
	if living.is_empty():
		return {}
	# hit whoever is closest to falling: an enemy that spreads damage evenly is an
	# enemy that never wins, and a battle that can never be lost teaches nothing
	var best: Dictionary = living[0]
	for u in living:
		var unit: Dictionary = u
		if int(unit["hp"]) < int(best["hp"]):
			best = unit
	return best


# ------------------------------------------------------------------- state ---
func _check_end() -> void:
	if finished:
		return
	if _living(ROLE_FOE).is_empty():
		finished = true
		result = "win"
		_push({"kind": "end", "result": "win"})
		return
	if _living(ROLE_ALLY).is_empty():
		finished = true
		result = "lose"
		_push({"kind": "end", "result": "lose"})


## EXP, Leaf and drops for a won battle. Called once, after `result == "win"`.
func rewards() -> Dictionary:
	var exp := 0
	var leaf := 0
	var drops: Array = []
	for u in foes:
		var unit: Dictionary = u
		var row: Dictionary = unit.get("reward", {})
		exp += int(row.get("exp", 0))
		leaf += int(row.get("leaf", 0))
		if String(row.get("drop", "")) != "" and rng.randf() < float(row.get("drop_chance", 0.0)):
			drops.append(String(row["drop"]))
	return {"exp": exp, "leaf": leaf, "drops": drops}


func drain() -> Array:
	var out := events.duplicate()
	events.clear()
	return out


func push_note(text: String) -> void:
	_push({"kind": "message", "text": text})


func _push(event: Dictionary) -> void:
	events.append(event)
	if String(event.get("kind", "")) == "message":
		messages.append(String(event.get("text", "")))


# ------------------------------------------------------------ for the tests --
## Everything the HUD and the tests need to describe a unit in one line.
func snapshot() -> Array:
	var out: Array = []
	for u in units:
		var unit: Dictionary = u
		out.append({
			"uid": int(unit["uid"]),
			"name": String(unit["name"]),
			"side": String(unit["side"]),
			"hp": int(unit["hp"]),
			"hp_max": int(unit["hp_max"]),
			"sp": int(unit["sp"]),
			"bp": int(unit["bp"]),
			"shield": int(unit["shield"]),
			"shield_max": int(unit["shield_max"]),
			"broken": bool(unit["broken"]),
			"alive": bool(unit["alive"]),
			"phase": int(unit["phase"]),
		})
	return out
