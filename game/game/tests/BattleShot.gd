extends Node3D
## Screenshots for step 3C. One run per state, on a real (xvfb) display:
##
##   godot --path game --resolution 1280x720 res://game/tests/BattleShot.tscn -- \
##     --state=menu --capture=/abs/docs/screenshots --capture-name=51_battle_menu
##
## Every shot comes from the REAL battle scene standing on the REAL region, not
## from a mock. What is scripted is only the *input*: which button is pressed and
## which enemy is picked, exactly what a thumb would do. The states that cannot be
## reached by tapping quickly (a boss at half health, a party about to lose) are
## reached by setting the party's numbers and letting the engine play the rest -
## the animations and the interface are the same ones the player sees.

const HARNESS := preload("res://game/tests/TestHarness.gd")
const DIORAMA := "res://game/world/Diorama.tscn"
const BATTLE := "res://game/battle/BattleScene.gd"

var world: Node3D = null
var battle: Node3D = null


func _ready() -> void:
	await get_tree().process_frame
	if not HARNESS.has_arg("--capture="):
		print("[SHOT] butuh --capture=<dir>")
		get_tree().quit(2)
		return
	var state := HARNESS.arg("--state=", "awal")
	if not ResourceLoader.exists(DIORAMA):
		print("[SHOT] Diorama tidak ada")
		get_tree().quit(2)
		return
	world = load(DIORAMA).instantiate()
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame
	var region: Variant = world.call("region")
	var spot: Vector2 = world.call("start_position")
	var script: Script = load(BATTLE)
	battle = script.new()
	battle.name = "Battle"
	add_child(battle)
	battle.call("start", region, spot, "ujian_orc", {
		"level": 3, "exp": 320, "leaf": 240, "seed": 7,
		"observed": {"orc_prajurit": ["tombak"], "orc_pemimpin": ["tombak", "es"]},
	})
	await _reach(state)
	var shot := HARNESS.arg("--capture-name=", "51_pertarungan_%s" % state)
	# the transition shot must not wait: its whole point is a frame mid-flight
	await HARNESS.capture(self, shot, 0.0 if state == "transisi" else 0.35)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _logic() -> RefCounted:
	var l: RefCounted = battle.get("logic")
	return l


func _ui() -> Control:
	var c: Control = battle.get("ui")
	return c


func _foe(index: int) -> Dictionary:
	var foes: Array = _logic().get("foes")
	var out: Dictionary = foes[index]
	return out


func _ready_battle() -> void:
	# let the shatter finish so the arena is fully visible
	await _wait(1.6)


func _reach(state: String) -> void:
	match state:
		"transisi":
			# mid-shatter. The wipe tween is running, so the honest way to catch it
			# is to stand still and let it pass: 0.25 s into a 0.55 s shatter is a
			# real frame of the real transition, not a hand-set uniform fighting
			# the tween back on the next frame.
			await _wait(0.25)
			return
		"awal":
			await _ready_battle()
			return
		"menu":
			await _ready_battle()
			_ui().call("select_target", int(_foe(1)["uid"]))
			_ui().call("refresh")
			return
		"kelemahan":
			await _ready_battle()
			# two known weaknesses on the leader and one on a soldier: the "?" row
			var observed: Dictionary = _logic().get("observed")
			observed["orc_pemimpin"] = ["tombak", "es"]
			observed["orc_prajurit"] = ["tombak", "api"]
			_ui().call("select_target", int(_foe(3)["uid"]))
			_ui().call("refresh")
			return
		"boost":
			await _ready_battle()
			_logic().set("awaiting", (_logic().get("allies") as Array)[0])
			_ui().call("_cycle_boost")
			_ui().call("_cycle_boost")
			_ui().call("refresh")
			return
		"break":
			await _ready_battle()
			var foe := _foe(0)
			foe["shield"] = 1
			_trigger_attack(int(foe["uid"]))
			await _wait(0.75)
			return
		"damage":
			await _ready_battle()
			_trigger_attack(int(_foe(1)["uid"]))
			await _wait(0.42)
			return
		"fase2":
			await _ready_battle()
			var boss := _foe(3)
			boss["hp"] = int(float(boss["hp_max"]) * 0.5) + 4
			_trigger_attack(int(boss["uid"]))
			await _wait(1.5)
			return
		"hasil":
			await _ready_battle()
			for raw in (_logic().get("foes") as Array):
				var foe: Dictionary = raw
				foe["hp"] = 0
				foe["alive"] = false
			_logic().set("finished", true)
			_logic().set("result", "win")
			battle.call("_finish")
			await _wait(0.7)
			return
		"kalah":
			await _ready_battle()
			for raw in (_logic().get("allies") as Array):
				var ally: Dictionary = raw
				ally["hp"] = 0
				ally["alive"] = false
			_logic().set("finished", true)
			_logic().set("result", "lose")
			battle.call("_finish")
			await _wait(0.7)
			return
		_:
			await _ready_battle()
			return


## Act as if the player had tapped Serang (or the skill) on that enemy, without
## waiting for the tap: the events still play at their real speed.
func _trigger_attack(target_uid: int) -> void:
	var allies: Array = _logic().get("allies")
	var knight: Dictionary = allies[0]
	var foe: Dictionary = {}
	for raw in (_logic().get("foes") as Array):
		if int((raw as Dictionary)["uid"]) == target_uid:
			foe = raw
	var action := {"kind": "skill", "id": "tebas_naik", "target": target_uid, "boost": 0}
	if int(knight["sp"]) < 6:
		action = {"kind": "attack", "target": target_uid, "boost": 0}
	_logic().set("awaiting", knight)
	# `_apply` is the controller's own path: engine first, then the animation
	battle.call("_apply", action)
	await get_tree().process_frame
	_ui().call("refresh")
