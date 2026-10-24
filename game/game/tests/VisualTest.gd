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
var _elapsed := 0.0
var _walk_seconds := 6.0
## "" = the walking shot, "page" = a dialogue page, "choices" = the branch fork.
var _dialog_mode := ""
var _dialog_done := false


func _ready() -> void:
	_night = HARNESS.arg("--time=", "day") == "night"
	_dialog_mode = HARNESS.arg("--dialog=", "")
	_build()
	await _run()


func _run() -> void:
	var default_name := "11_visual_malam" if _night else "10_visual_siang"
	var delay := 3.4
	if _dialog_mode == "choices":
		default_name = "13_pilihan"
		delay = 3.2
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
		_cast.call("set_time_of_day", _night)

	_cam_rig = _diorama.get_node_or_null("CameraRig") as Node3D
	if _cam_rig != null:
		_cam_rig.call("set_zoom", 16.0)
		# keep the follow lens on the actors, not the far trees
		_cam_rig.set("bounds", Vector2(7.5, 5.5))
	print("[TEST] VisualTest waktu=%s cast=%s" % [
		"malam" if _night else "siang", str(_cast != null)])


func _process(delta: float) -> void:
	_elapsed += delta
	if _cast == null:
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


## Walk the knight up to the guard and press Bicara for him. Everything here is
## the same path a thumb takes - it just has no thumb.
func _open_dialogue() -> void:
	_cast.call("teleport_player", Vector2(3.6, 3.2))
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
