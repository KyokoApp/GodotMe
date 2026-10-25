extends Node3D
## Scene `VisualTest`: the cast dropped into the real diorama, walking, in
## daylight and at night. This is the check that the sprites belong to the
## world - sharpness, blob shadows, relative height against the cottage door -
## not a turntable in a void.
##
##   godot --path game res://game/tests/VisualTest.tscn -- --time=night \
##     --capture=<dir> --capture-name=11_visual_malam

const HARNESS := preload("res://game/tests/TestHarness.gd")

var _diorama: Node3D
var _cast: Node3D
var _cam_rig: Node3D
var _night := false
## Which phase this run opens in. "day" is noon, "dusk" the warm afternoon the
## game normally starts in; both are real clock phases now, not a boolean.
var _phase := "sore"
var _elapsed := 0.0
var _walk_seconds := 6.0
## "" = the walking shot, "page" = a dialogue page, "choices" = the branch fork.
var _dialog_mode := ""
var _dialog_done := false
var _down_done := false
var _down_reported := false


func _ready() -> void:
	var time_arg := HARNESS.arg("--time=", "day")
	match time_arg:
		"dawn":
			_phase = "pagi"
		"night":
			_phase = "malam"
		"dusk":
			_phase = "sore"
		_:
			_phase = "siang"
	_night = _phase == "malam"
	_dialog_mode = HARNESS.arg("--dialog=", "")
	_build()
	await _run()


func _run() -> void:
	var default_name := "11_visual_malam" if _night else "10_visual_siang"
	var delay := 3.4
	if _dialog_mode == "choices":
		default_name = "13_pilihan"
		delay = 3.2
	elif _dialog_mode == "down":
		# hearts empty: the knight on the ground, HUD at 0/3 and the toast telling
		# the player he will get up - the stakes, captured instead of described
		default_name = "16_terjatuh"
		delay = 4.2
	elif _dialog_mode == "after":
		# the same guard, after the player cleared the valley: a different story
		default_name = "15_dialog_setelah"
		delay = 4.6
	elif _dialog_mode != "":
		default_name = "12_dialog"
		# the typewriter runs at 42 characters a second; one page needs ~2.5 s
		delay = 4.6
	await HARNESS.capture(self, default_name, delay)
	await HARNESS.quit_after(self, 45.0)


func _build() -> void:
	var path := "res://game/world/Diorama.tscn"
	if not ResourceLoader.exists(path):
		push_error("[TEST] Diorama.tscn tidak ada; paket dunia belum dipasang")
		return
	_diorama = load(path).instantiate() as Node3D
	add_child(_diorama)

	var cast_script: Script = load("res://game/characters/CharacterWorld.gd")
	if cast_script != null:
		_cast = cast_script.new()
		_cast.name = "Characters"
		_diorama.add_child(_cast)
		# The diorama owns the cycle; older world packs only know the boolean.
		if _diorama.has_method("set_phase"):
			_diorama.call("set_phase", _phase)
		else:
			_cast.call("set_time_of_day", _night)

	_cam_rig = _diorama.get_node_or_null("CameraRig") as Node3D
	if _cam_rig != null:
		_cam_rig.call("set_zoom", 16.0)
		# keep the follow lens on the actors, not the far trees
		_cam_rig.set("bounds", Vector2(7.5, 5.5))
	print("[TEST] VisualTest fase=%s cast=%s atmosfer=%s" % [
		_phase, str(_cast != null),
		str(_diorama.has_method("atmosphere") and _diorama.call("atmosphere") != null)])


func _process(delta: float) -> void:
	_elapsed += delta
	if _cast == null:
		return
	if _dialog_mode == "down":
		_cast.call("set_virtual_stick", Vector2.ZERO)
		if not _down_done and _elapsed > 1.0:
			_down_done = true
			_fall_down()
		if not _down_reported and _elapsed > 4.0:
			_down_reported = true
			_report_down()
		return
	if _dialog_mode != "":
		_cast.call("set_virtual_stick", Vector2.ZERO)
		if not _dialog_done and _elapsed > 1.0:
			_dialog_done = true
			_open_dialogue()
		return
	if _elapsed < _walk_seconds:
		# pushed up-left: the knight walks the path towards the cottage, which
		# puts the guard in frame and moves the feet across the grass
		_cast.call("set_virtual_stick", Vector2(-0.45, -0.62))
	else:
		_cast.call("set_virtual_stick", Vector2.ZERO)
	if _cam_rig != null:
		# slow zoom so a single capture proves the sprite stays crisp and the
		# billboard keeps facing the camera at a non-default distance
		_cam_rig.call("set_zoom", 15.0 + 2.5 * sin(_elapsed * 0.55))


## Three orc hits' worth of damage, spaced out so the knight's own
## invulnerability window does not swallow them, ending with him on the ground.
func _fall_down() -> void:
	var knight: Node3D = _cast.call("player")
	for _i in 3:
		if knight == null or not is_instance_valid(knight):
			return
		knight.call("take_hit")
		await get_tree().create_timer(0.95).timeout


## One log line at the moment the camera looks at him: if a future run ever
## captures a standing knight again, this says why instead of leaving a mystery.
func _report_down() -> void:
	var knight: Node3D = _cast.call("player")
	var st: Dictionary = _cast.call("hud_state")
	print("[TEST] terjatuh? nyawa=%d/%d henti=%s state=%s mati=%s anim=%s t=%.2f" % [
		int(st.get("hearts", -1)), int(st.get("max_hearts", -1)), str(st.get("down")),
		String(knight.get("state")), str(knight.call("is_dead")),
		String(knight.call("anim_name")), _elapsed])


## Walk the knight up to the guard and press Bicara for him. Everything here is
## the same path a thumb takes - it just has no thumb.
## The guard's own marker, moved a step to the side: the scene under test is the
## real region, so nothing here may assume a hand-placed coordinate.
func _guard_spot() -> Vector2:
	if _diorama != null and _diorama.has_method("region"):
		var region: RefCounted = _diorama.call("region")
		if region != null:
			var m: Dictionary = region.call("marker", "Penjaga Bram")
			if not m.is_empty():
				return (region.call("marker_pos", m) as Vector2) + Vector2(-1.0, 0.4)
	return Vector2(3.4, 5.8)


func _open_dialogue() -> void:
	_cast.call("teleport_player", _guard_spot())
	if _dialog_mode == "after":
		# pretend three orcs are down and the first meeting already happened:
		# this is the branch a returning player must see, proved by a capture
		_cast.call("set_progress", 3, ["bram_kenal"])
	_cast.call("press_interact")
	var dlg: Node = _cast.call("dialogue")
	if dlg == null:
		push_error("[TEST] kotak dialog tidak ada")
		return
	var open := bool(dlg.get("is_open"))
	if not open:
		push_error("[TEST] dialog tidak terbuka - penjaga di luar jangkauan?")
		return
	if _dialog_mode == "choices":
		dlg.call("jump_to_choices")
	var opts: Array = dlg.get("_options")
	print("[TEST] dialog terbuka=%s teks=%d aksara pilihan=%d" % [
		open, String(dlg.call("current_text")).length(), opts.size()])
