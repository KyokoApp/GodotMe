extends Node3D
## The controller: one battle, start to finish, with the transition at both ends.
##
## It owns the engine (`BattleLogic`), the body (`BattleView`) and the interface
## (`BattleUI`), and it is the only place that knows about TIME - how long a hit
## takes to read, how long the player gets to see the "?" disappear, what 2x
## means. The engine is instant; this file stretches it out so it can be watched.
##
## Order of a turn:
##   1. `logic.next_actor()` says whose turn it is;
##   2. an ally waits for a tap (or `suggest_action()` when Auto is on), an enemy
##      is played by the engine after a short beat;
##   3. the events the engine produced are played one at a time - swing, hit,
##      stop, float a number, break, die - and only then is the interface
##      refreshed, so nothing shows a result before its animation.
##
## Speed multiplies those waits, never the engine's numbers: at 3x a battle is
## the same battle, just read faster.

signal battle_finished(summary: Dictionary)

const DATA_SCRIPT := "res://game/battle/BattleData.gd"
const LOGIC_SCRIPT := "res://game/battle/BattleLogic.gd"
const VIEW_SCRIPT := "res://game/battle/BattleView.gd"
const UI_SCRIPT := "res://game/battle/BattleUI.gd"
const WIPE_SHADER := "res://game/battle/battle_wipe.gdshader"

## Seconds, at 1x. A hit has to be readable but a four-hit Boosted action has to
## stay under two seconds or the battle feels like a slideshow.
const T_SWING := 0.22
const T_HIT := 0.20
const T_BREAK := 0.55
const T_MESSAGE := 0.45
const T_TURN := 0.18
const T_END := 0.9

var logic: RefCounted = null
var view: Node3D = null
var ui: Control = null
var data: RefCounted = null

var encounter_id := ""
var centre := Vector2.ZERO
var progress: Dictionary = {}
var speed := 1
var auto := false
var summary: Dictionary = {}
var _busy := false
var _finished := false
var _wipe: ColorRect = null
var _wipe_layer: CanvasLayer = null
var _wipe_mat: ShaderMaterial = null
var _ui_layer: CanvasLayer = null
var _waiting_for_tap := false
var _pending_action: Dictionary = {}


## `party_progress` is the save's battle blob (or {} for a new game): level, exp,
## leaf, hp, sp, items and the weaknesses already learned.
func start(region: RefCounted, at: Vector2, encounter: String, party_progress: Dictionary) -> void:
	centre = at
	encounter_id = encounter
	progress = _default_progress().merged(party_progress.duplicate(true), true)
	var data_script: Script = load(DATA_SCRIPT)
	data = data_script.new()
	if not bool(data.call("ok")):
		push_error("[BATTLE] data rusak: %s" % str(data.get("problems")))
	var enc: Dictionary = data.call("encounter", encounter)
	var line: Array = enc.get("enemies", [])
	var logic_script: Script = load(LOGIC_SCRIPT)
	logic = logic_script.new()
	logic.call("setup", data, ["knight"], line, int(progress.get("seed", 0)))
	logic.set("level", int(progress.get("level", 1)))
	var observed: Dictionary = progress.get("observed", {})
	logic.set("observed", observed.duplicate(true))
	var inventory: Dictionary = progress.get("items", {})
	logic.set("inventory", inventory.duplicate(true))
	if bool(enc.get("ambush", false)):
		logic.call("apply_ambush")
	# the HP/SP the party walked in with, not a fresh bar every battle
	var allies: Array = logic.get("allies")
	for i in range(allies.size()):
		var unit: Dictionary = allies[i]
		if int(progress.get("hp", 0)) > 0:
			unit["hp"] = mini(int(unit["hp_max"]), int(progress.get("hp", unit["hp"])))
		if int(progress.get("sp", 0)) > 0:
			unit["sp"] = mini(int(unit["sp_max"]), int(progress.get("sp", unit["sp"])))
	logic.call("drain")
	_build_body(region)
	_build_ui()
	_play_wipe_in()


func _default_progress() -> Dictionary:
	return {
		"level": 1, "exp": 0, "leaf": 60, "hp": 0, "sp": 0,
		"battles_won": 0, "battles_lost": 0,
		"observed": {}, "items": {"ramuan": 2, "elixir": 1, "granat_api": 1, "botol_es": 1},
		"seed": 0,
	}


func _build_body(region: RefCounted) -> void:
	var view_script: Script = load(VIEW_SCRIPT)
	view = view_script.new()
	view.name = "Arena"
	add_child(view)
	view.set("region", region)
	view.set("centre", centre)
	view.call("build", logic)


func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "BattleUI"
	_ui_layer.layer = 30
	add_child(_ui_layer)
	var ui_script: Script = load(UI_SCRIPT)
	ui = ui_script.new()
	ui.name = "Hud"
	_ui_layer.add_child(ui)
	ui.call("setup", logic, view)
	ui.connect("action_chosen", Callable(self, "_on_action"))
	ui.connect("speed_changed", Callable(self, "_on_speed"))
	ui.connect("auto_toggled", Callable(self, "_on_auto"))
	ui.connect("result_closed", Callable(self, "_on_result_closed"))
	_build_wipe()


# --------------------------------------------------------------- transition ---
func _build_wipe() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Wipe"
	layer.layer = 60
	# Parked from the start: nothing to draw until a tween moves it.
	layer.visible = false
	_wipe_layer = layer
	add_child(layer)
	_wipe = ColorRect.new()
	_wipe.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wipe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# nothing to draw until the tween moves it (see `_set_wipe`)
	_wipe.visible = false
	_wipe_mat = ShaderMaterial.new()
	if ResourceLoader.exists(WIPE_SHADER):
		_wipe_mat.shader = load(WIPE_SHADER)
	_wipe.material = _wipe_mat
	layer.add_child(_wipe)
	# the shader samples the screen behind it, so the frame has to be copied
	var copy := BackBufferCopy.new()
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	layer.add_child(copy)


func _play_wipe_in() -> void:
	await _wipe_to(1.0, 0.55)
	await get_tree().process_frame
	_refresh_all()
	await _wipe_to(0.0, 0.4)
	# belt and braces: whatever the last tween frame rounded to, the transition is
	# over and the arena has to be seen without anything over it
	if _wipe_layer != null:
		_wipe_layer.visible = false
	_run()


func _wipe_to(value: float, seconds: float) -> void:
	if _wipe_mat == null:
		await get_tree().create_timer(seconds).timeout
		return
	var from := 0.0
	if _wipe_mat.get_shader_parameter("t") != null:
		from = float(_wipe_mat.get_shader_parameter("t"))
	var tween := create_tween()
	tween.tween_method(_set_wipe, from, value, seconds)
	await tween.finished


func _set_wipe(value: float) -> void:
	if _wipe_mat != null:
		_wipe_mat.set_shader_parameter("t", value)
	# The overlay is a full-screen copy of the frame behind it, and a copy is only
	# wanted WHILE the picture is breaking. Park the whole layer at both ends: at
	# 0 there is nothing to cover, and at 1 the controller is about to swap the
	# scene. Leaving it up (an earlier draft only hid the rect, and before that
	# nothing at all) cost a full-screen pass over the arena for the whole fight -
	# and on the GL Compatibility renderer the "copy" it drew was the 2D canvas
	# rather than the 3D frame, so the parked overlay painted a flat brown wash
	# and a grid of shard seams over every battle screenshot.
	if _wipe_layer != null:
		_wipe_layer.visible = value > 0.0005 and value < 0.9995
	if _wipe != null:
		_wipe.visible = _wipe_layer == null or _wipe_layer.visible


# -------------------------------------------------------------------- turns ---
func _run() -> void:
	while not bool(logic.get("finished")) and is_inside_tree():
		var unit: Dictionary = logic.call("next_actor")
		logic.call("drain")
		if unit.is_empty():
			break
		_refresh_all()
		if String(unit["side"]) == "foe":
			await _sleep(T_TURN)
			if is_inside_tree() and not _finished:
				logic.call("play_enemy_turn")
				var events: Array = logic.call("drain")
				await _play_events(events)
			continue
		# an ally: a tap, or Auto
		await _wait_for_action(unit)
		if _finished or not is_inside_tree():
			break
	await _finish()


func _wait_for_action(unit: Dictionary) -> void:
	if auto:
		await _sleep(T_TURN)
		await _apply(logic.call("suggest_action"))
		return
	_waiting_for_tap = true
	ui.set("awaiting_ready", true)
	while _waiting_for_tap and not _finished:
		await get_tree().process_frame
	ui.set("awaiting_ready", false)
	if _finished or _pending_action.is_empty():
		return
	# The tap only records WHAT was chosen; the animation is played here, in the
	# turn's own coroutine. Playing it from the signal handler instead let `_run`
	# move on to the next actor while the first action was still swinging.
	var action: Dictionary = _pending_action
	_pending_action = {}
	await _apply(action)


func _on_action(action: Dictionary) -> void:
	if not _waiting_for_tap or _busy:
		return
	_pending_action = action
	_waiting_for_tap = false


func _apply(action: Dictionary) -> void:
	_busy = true
	var events: Array = logic.call("submit", action)
	await _play_events(events)
	_busy = false
	if not _finished:
		_refresh_all()


func _on_speed(value: int) -> void:
	speed = clampi(value, 1, 3)


func _on_auto(on: bool) -> void:
	auto = on


func _sleep(seconds: float) -> void:
	var wait := maxf(0.01, seconds / float(maxi(1, speed)))
	await get_tree().create_timer(wait).timeout


# ------------------------------------------------------------------- events ---
func _play_events(events: Array) -> void:
	for raw in events:
		if _finished or not is_inside_tree():
			return
		await _play_event(raw as Dictionary)
		if not is_inside_tree():
			return


func _play_event(event: Dictionary) -> void:
	match String(event.get("kind", "")):
		"hit":
			await _play_hit(event)
		"miss":
			ui.call("note", "Serangan meleset.")
			await _sleep(T_HIT)
		"resist":
			await _sleep(0.05)
		"shield":
			_refresh_all()
			await _sleep(0.05)
		"break":
			var unit: Dictionary = event["unit"]
			view.call("break_unit", int(unit["uid"]))
			ui.call("note", "BREAK! %s kehilangan giliran." % unit["name"])
			ui.call("float_text", view.call("unit_screen", int(unit["uid"])),
				"BREAK!", Color(0.98, 0.86, 0.42), true)
			_refresh_all()
			await _sleep(T_BREAK)
		"recover":
			var unit: Dictionary = event["unit"]
			view.call("recover_unit", int(unit["uid"]))
			await _sleep(T_HIT)
		"down":
			var unit: Dictionary = event["unit"]
			view.call("die", int(unit["uid"]))
			_refresh_all()
			await _sleep(0.35)
		"heal":
			var unit: Dictionary = event["unit"]
			ui.call("float_text", view.call("unit_screen", int(unit["uid"])),
				"+%d" % int(event.get("amount", 0)), Color(0.55, 0.85, 0.45))
			_refresh_all()
			await _sleep(T_HIT)
		"buff":
			ui.call("note", "%s memperkuat pertahanan." % String((event["unit"] as Dictionary)["name"]))
			_refresh_all()
			await _sleep(T_HIT)
		"charge":
			var unit: Dictionary = event["unit"]
			ui.call("float_text", view.call("unit_screen", int(unit["uid"])),
				"!!", Color(0.92, 0.42, 0.24), true)
			await _sleep(T_BREAK * 0.6)
		"phase":
			ui.call("note", String(event.get("text", "")))
			_refresh_all()
			await _sleep(T_BREAK)
		"flee":
			if bool(event.get("ok", false)):
				ui.call("note", "Kabur berhasil.")
				await _sleep(T_MESSAGE)
		"message":
			ui.call("note", String(event.get("text", "")))
			await _sleep(T_MESSAGE * 0.6)
		"round":
			await _sleep(0.05)
		"end":
			await _sleep(T_END)
		"skill", "item", "guard", "turn":
			await _sleep(0.05)
		_:
			await _sleep(0.05)


func _play_hit(event: Dictionary) -> void:
	var src: Dictionary = event.get("src", {})
	var unit: Dictionary = event.get("unit", {})
	var damage := int(event.get("damage", 0))
	var uid := int(unit.get("uid", -1))
	if not src.is_empty() and String(src.get("side", "")) == "ally":
		view.call("swing", int(src["uid"]))
	await _sleep(T_SWING * 0.5)
	view.call("hit", uid, bool(event.get("crit", false)) or int(damage) > 40)
	var colour := Color(0.98, 0.94, 0.86)
	if bool(event.get("crit", false)):
		colour = Color(1.0, 0.86, 0.30)
	elif bool(event.get("weak", false)):
		colour = Color(1.0, 0.62, 0.28)
	if bool(event.get("guard", false)):
		colour = Color(0.70, 0.78, 0.92)
	ui.call("float_text", view.call("unit_screen", uid), str(damage), colour,
		bool(event.get("crit", false)))
	_refresh_all()
	await _sleep(T_HIT)


# -------------------------------------------------------------------- finish ---
func _finish() -> void:
	if _finished:
		return
	_finished = true
	var won := String(logic.get("result")) == "win"
	var lost := String(logic.get("result")) == "lose"
	var fled := String(logic.get("result")) == "flee"
	summary = {"win": won, "lost": lost, "fled": fled, "encounter": encounter_id}
	var victim := 0
	if lost:
		victim = 1
	# level, EXP and Leaf
	if won:
		var rewards: Dictionary = logic.call("rewards")
		summary["exp"] = int(rewards.get("exp", 0))
		summary["leaf"] = int(rewards.get("leaf", 0))
		summary["drops"] = rewards.get("drops", [])
		progress["exp"] = int(progress.get("exp", 0)) + int(summary["exp"])
		progress["leaf"] = int(progress.get("leaf", 0)) + int(summary["leaf"])
		progress["battles_won"] = int(progress.get("battles_won", 0)) + 1
		_apply_level_ups()
	elif lost:
		# losing is survivable and cheap, but not free: a light Leaf penalty and
		# back to the last save, which is what the save file is for
		var penalty: int = mini(40, int(float(progress.get("leaf", 0)) * 0.15))
		summary["penalty"] = penalty
		progress["leaf"] = maxi(0, int(progress.get("leaf", 0)) - penalty)
		progress["battles_lost"] = int(progress.get("battles_lost", 0)) + 1
	# what the party learned and what it still has
	progress["observed"] = (logic.get("observed") as Dictionary).duplicate(true)
	progress["items"] = (logic.get("inventory") as Dictionary).duplicate(true)
	for raw in logic.get("allies"):
		var unit: Dictionary = raw
		summary["hp"] = int(unit["hp"])
		summary["sp"] = int(unit["sp"])
		progress["hp"] = int(unit["hp"])
		progress["sp"] = int(unit["sp"])
	summary["level"] = int(progress.get("level", 1))
	summary["progress"] = progress.duplicate(true)
	summary["victim"] = victim
	ui.call("show_result", summary)
	ui.call("note", "…")
	logic.call("drain")


func _apply_level_ups() -> void:
	var curve: Array = (data.call("balance").get("level_curve", []) as Array)
	var level := int(progress.get("level", 1))
	while level < curve.size() and int(progress.get("exp", 0)) >= int(curve[level]):
		level += 1
	if level > int(progress.get("level", 1)):
		progress["level"] = level
		summary["level_up"] = true
		# a level-up has to be felt: more HP, more ATK, and a full heal
		var max_hp := 370 + int(data.call("balance_int", "level_hp", 24)) * (level - 1)
		progress["hp"] = max_hp
		summary["hp"] = max_hp


func _on_result_closed() -> void:
	await _wipe_to(1.0, 0.5)
	battle_finished.emit(summary)
	queue_free()


func _refresh_all() -> void:
	if ui != null:
		ui.call("refresh")


func _process(_delta: float) -> void:
	if view != null:
		view.call("tick", _delta)
	if ui != null:
		ui.call("tick_display")


func is_running() -> bool:
	return not _finished
