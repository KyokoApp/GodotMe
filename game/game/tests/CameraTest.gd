extends Node
## Headless gate for step 3A: the camera.
##
##   godot --headless --path game res://game/tests/CameraTest.tscn
##
## What this covers, and why each one exists:
##
##   * the lens (pitch, FOV, distance) comes from `world/camera.json` and nothing
##     else - not from a setting, not from an input event;
##   * a long route - walk, stop, turn, stand by the guard, open the dialogue,
##     open the menu, walk into the map's edge - records the lens EVERY frame and
##     fails if any of the three numbers moves;
##   * the follow is smooth: no per-frame jump, no pumping, and it stays close;
##   * the spring is frame-rate independent: 30 fps and 60 fps land in the same
##     place, and a long walk does not overshoot;
##   * the occlusion corridor (which prop fades, and how much) is a pure function
##     and is checked on the real prop layout of Yaros.

const CAMERA_SCRIPT := preload("res://game/world/DioramaCamera.gd")
const SETTINGS_SCRIPT := preload("res://game/ui/Settings.gd")
const MAIN_SCENE := "res://game/Main.tscn"
const CONFIG_PATH := "res://game/world/camera.json"

## A lens that moves by more than half a centimetre is a bug: the whole point of
## step 3A is that these three numbers hold still.
const EPS_LENS := 0.005

var failures := 0
var checks := 0
var _main: Control
var _cast: Node3D
var _rig: Node3D

## Per-frame records while a route runs: lens + positions.
var _recording := false
var _frames: Array = []


func _ready() -> void:
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute("user://cameratest")
	OS.set_environment("RT_SETTINGS_DIR", "user://cameratest")
	OS.set_environment("RT_SAVE_DIR", "user://cameratest")
	_test_config()
	await _test_no_input_moves_the_lens()
	_test_spring()
	await _test_route_holds_the_lens()
	await _test_follow_is_smooth()
	_test_occlusion_plan()
	print("[CAMERA] %d pemeriksaan, %d gagal" % [checks, failures])
	OS.set_environment("RT_SETTINGS_DIR", "")
	OS.set_environment("RT_SAVE_DIR", "")
	get_tree().quit(0 if failures == 0 else 1)


func _check(cond: bool, label: String, extra: String = "") -> void:
	checks += 1
	if cond:
		print("[CAMERA] PASS %s" % label)
	else:
		failures += 1
		print("[CAMERA] FAIL %s %s" % [label, extra])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


# ---------------------------------------------------------------- config -----
## The file is the single source. If the numbers in the game and the numbers in
## the file ever differ, this is the test that says so.
func _test_config() -> void:
	var text := FileAccess.get_file_as_string(CONFIG_PATH)
	var parsed: Variant = JSON.parse_string(text)
	_check(typeof(parsed) == TYPE_DICTIONARY, "camera.json terbaca sebagai JSON")
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var cfg: Dictionary = parsed
	var lens: Dictionary = cfg.get("lens", {})
	_check(lens.has("pitch_deg") and lens.has("fov_deg") and lens.has("distance_m"),
		"camera.json memuat pitch, fov, dan jarak")

	var rig := _make_rig()
	var state: Dictionary = rig.call("lens_state")
	_check(is_equal_approx(float(state["pitch_deg"]), float(lens.get("pitch_deg", 0.0))),
		"pitch kamera = camera.json", "%.2f vs %.2f" % [
			float(state["pitch_deg"]), float(lens.get("pitch_deg", 0.0))])
	_check(is_equal_approx(float(state["fov_deg"]), float(lens.get("fov_deg", 0.0))),
		"FOV kamera = camera.json", "%.2f vs %.2f" % [
			float(state["fov_deg"]), float(lens.get("fov_deg", 0.0))])
	_check(is_equal_approx(float(state["distance_m"]), float(lens.get("distance_m", 0.0))),
		"jarak kamera = camera.json", "%.2f vs %.2f" % [
			float(state["distance_m"]), float(lens.get("distance_m", 0.0))])

	# Perspective, not orthographic: an orthographic lens cannot show a wall and a
	# roof at once, which is the whole point of the HD-2D angle.
	var cam: Camera3D = rig.get_node_or_null("Camera3D") as Camera3D
	_check(cam != null and cam.projection == Camera3D.PROJECTION_PERSPECTIVE,
		"kamera perspektif, bukan ortografis")

	# Pitch is measured as degrees BELOW the horizon. Prove the number means what
	# the brief says it means: the forward axis must point down by that much.
	if cam != null:
		var fwd := -cam.global_transform.basis.z.normalized()
		var below := rad_to_deg(asin(clampf(-fwd.y, -1.0, 1.0)))
		_check(absf(below - float(state["pitch_deg"])) < 0.5,
			"pitch %.0f derajat benar-benar menunduk segitu" % float(state["pitch_deg"]),
			"terukur %.2f" % below)

	# No setting anywhere may offer a zoom. The player cannot change the lens.
	var settings_script: Script = SETTINGS_SCRIPT
	var consts: Dictionary = settings_script.get_script_constant_map()
	var defaults: Dictionary = consts.get("DEFAULTS", {})
	var zoom_key := false
	for key in defaults.keys():
		if String(key).to_lower().contains("zoom"):
			zoom_key = true
	_check(not zoom_key, "tidak ada setelan zoom di Pengaturan", str(defaults.keys()))

	# And no input handler on the rig at all: the bug was in `_input`.
	_check(not rig.has_method("_input") and not rig.has_method("_unhandled_input"),
		"rig kamera tidak punya penangan input sama sekali")

	rig.queue_free()


func _make_rig() -> Node3D:
	var rig: Node3D = CAMERA_SCRIPT.new()
	rig.name = "CameraRigTest"
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.current = true
	rig.add_child(cam)
	add_child(rig)
	return rig


# ----------------------------------------------------------------- input -----
## Throw every gesture that used to move the lens at the rig. Nothing may happen.
func _test_no_input_moves_the_lens() -> void:
	var rig := _make_rig()
	var before: Dictionary = rig.call("lens_state")

	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	Input.parse_input_event(wheel)
	var wheel_down := InputEventMouseButton.new()
	wheel_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel_down.pressed = true
	Input.parse_input_event(wheel_down)

	var magnify := InputEventMagnifyGesture.new()
	magnify.factor = 1.8
	Input.parse_input_event(magnify)

	var pan := InputEventPanGesture.new()
	pan.delta = Vector2(90.0, -40.0)
	Input.parse_input_event(pan)

	# the phone's own failure: joystick thumb plus action thumb read as a pinch
	var t0 := InputEventScreenTouch.new()
	t0.index = 0
	t0.position = Vector2(200.0, 500.0)
	t0.pressed = true
	Input.parse_input_event(t0)
	var t1 := InputEventScreenTouch.new()
	t1.index = 1
	t1.position = Vector2(300.0, 300.0)
	t1.pressed = true
	Input.parse_input_event(t1)
	for i in range(6):
		var drag := InputEventScreenDrag.new()
		drag.index = 1
		drag.position = Vector2(300.0 + float(i) * 40.0, 300.0 - float(i) * 30.0)
		drag.relative = Vector2(40.0, -30.0)
		Input.parse_input_event(drag)
		await get_tree().process_frame
	for ev in [t0, t1]:
		var up := (ev as InputEventScreenTouch).duplicate() as InputEventScreenTouch
		up.pressed = false
		Input.parse_input_event(up)
	await get_tree().process_frame
	await get_tree().process_frame

	var after: Dictionary = rig.call("lens_state")
	var drift := 0.0
	for key in before.keys():
		drift = maxf(drift, absf(float(after[key]) - float(before[key])))
	_check(drift < EPS_LENS, "roda, pinch, dan geser dua jari tidak mengubah lensa",
		"selisih %.5f" % drift)
	rig.queue_free()


# ---------------------------------------------------------------- spring -----
## The follow spring: no overshoot, and the same answer at 30 fps as at 60 fps.
func _test_spring() -> void:
	var fast: Dictionary = _simulate_follow(1.0 / 60.0)
	var slow: Dictionary = _simulate_follow(1.0 / 30.0)
	var gap: float = (fast["pos"] as Vector3).distance_to(slow["pos"] as Vector3)
	print("[CAMERA] spring 60fps %s vs 30fps %s (selisih %.3f m)" % [
		str(fast["pos"]), str(slow["pos"]), gap])
	_check(gap < 0.12, "follow sama pada 60 fps dan 30 fps", "selisih %.3f m" % gap)
	_check(not bool(fast["overshoot"]), "follow tidak melewati target (tanpa overshoot)",
		"kelebihan %.3f m" % float(fast["overshoot_by"]))
	_check(float(fast["settle_error"]) < 0.02,
		"follow berhenti tepat di target setelah pemain diam",
		"sisa %.4f m" % float(fast["settle_error"]))


## Run the rig's own `_process` by hand with a walker that steps along +x, so the
## frame rate is under the test's control instead of the machine's.
func _simulate_follow(delta: float) -> Dictionary:
	var rig: Node3D = CAMERA_SCRIPT.new()
	rig.name = "SpringTest"
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	rig.add_child(cam)
	add_child(rig)
	rig.set_process(false)
	var walker := Node3D.new()
	add_child(walker)
	walker.position = Vector3.ZERO
	rig.call("set_map_bounds", Rect2(-400.0, -400.0, 800.0, 800.0))
	rig.call("set_follow_target", walker)

	var speed := 4.0
	var t := 0.0
	var overshoot := false
	var overshoot_by := 0.0
	var steps := int(round(2.0 / delta))
	for i in range(steps):
		t += delta
		walker.position = Vector3(speed * t, 0.0, 0.0)
		rig.call("_process", delta)
		var pos := rig.position
		# the camera may trail the walker, never lead it
		if pos.x > walker.position.x + 0.001:
			overshoot = true
			overshoot_by = maxf(overshoot_by, pos.x - walker.position.x)
	# then let it settle with the walker standing still
	for i in range(int(round(1.5 / delta))):
		rig.call("_process", delta)
	var end_pos := rig.position
	var err := Vector2(end_pos.x - walker.position.x, end_pos.z - walker.position.z).length()
	var out := {"pos": end_pos, "overshoot": overshoot, "overshoot_by": overshoot_by,
		"settle_error": err}
	walker.queue_free()
	rig.queue_free()
	return out


# ----------------------------------------------------------------- route -----
## The long route. Every frame records the lens; any drift fails the build.
func _test_route_holds_the_lens() -> void:
	if not await _boot_main():
		return
	if _cast.has_method("set_shake_scale"):
		_cast.call("set_shake_scale", 0.0)
	var want: Dictionary = _rig.call("lens_state")
	_frames = []
	_recording = true

	# 1 walk
	_cast.call("set_virtual_stick", Vector2(0.25, -0.95))
	await _wait(1.2)
	# 2 stop, so the spring settles and starts again
	_cast.call("set_virtual_stick", Vector2.ZERO)
	await _wait(0.6)
	# 3 turn the other way and run
	_cast.call("set_virtual_stick", Vector2(-0.85, 0.5))
	await _wait(1.0)
	_cast.call("set_virtual_stick", Vector2.ZERO)
	await _wait(0.3)
	# 4 stand by the guard, then hold a conversation
	var npc_spot: Variant = _npc_spot()
	if npc_spot != null:
		_cast.call("teleport_player", npc_spot)
		await _wait(0.6)
		_cast.call("press_interact")
		await _wait(0.7)
		var dlg: Variant = _cast.call("dialogue")
		var guard := 0
		while dlg != null and bool(dlg.get("is_open")) and guard < 20:
			guard += 1
			dlg.call("advance")
			await get_tree().process_frame
		await _wait(0.4)
	# 5 the menu: parchment over the world
	_main.call("_open_menu", "lanjut")
	await _wait(0.6)
	_main.call("_on_resume_pressed")
	await _wait(0.4)
	# 6 the edge of the map: the clamp is where a camera used to jump
	var edge: Variant = _edge_spot()
	if edge != null:
		_cast.call("teleport_player", edge)
		await _wait(0.5)
		_cast.call("set_virtual_stick", Vector2(-1.0, -1.0))
		await _wait(1.6)
		_cast.call("set_virtual_stick", Vector2.ZERO)
		await _wait(0.4)
	_recording = false

	var pitch_drift := 0.0
	var fov_drift := 0.0
	var dist_drift := 0.0
	for raw in _frames:
		var f: Dictionary = raw
		pitch_drift = maxf(pitch_drift, absf(float(f["pitch"]) - float(want["pitch_deg"])))
		fov_drift = maxf(fov_drift, absf(float(f["fov"]) - float(want["fov_deg"])))
		dist_drift = maxf(dist_drift, absf(float(f["dist"]) - float(want["distance_m"])))
	print("[CAMERA] rute %d frame, geser pitch %.5f fov %.5f jarak %.5f" % [
		_frames.size(), pitch_drift, fov_drift, dist_drift])
	_check(_frames.size() > 120, "rute merekam ratusan frame", str(_frames.size()))
	_check(pitch_drift < EPS_LENS, "pitch tetap sepanjang rute", "%.5f" % pitch_drift)
	_check(fov_drift < EPS_LENS, "FOV tetap sepanjang rute", "%.5f" % fov_drift)
	_check(dist_drift < EPS_LENS, "jarak kamera tetap sepanjang rute", "%.5f" % dist_drift)

	# the lens on the screen, not only the number in the script
	var cam: Camera3D = _rig.call("camera")
	if cam != null:
		var real := cam.global_position.distance_to(_rig.global_position)
		_check(absf(real - float(want["distance_m"])) < 0.02,
			"kamera benar-benar sejauh itu dari titik bidik", "%.3f m" % real)


func _process(delta: float) -> void:
	if not _recording or _rig == null:
		return
	var state: Dictionary = _rig.call("lens_state")
	var cam: Camera3D = _rig.call("camera")
	var cam_pos := Vector3.ZERO
	if cam != null:
		cam_pos = cam.global_position
	var player := Vector3.ZERO
	if _cast != null and _cast.has_method("player"):
		var p: Node3D = _cast.call("player")
		if p != null and is_instance_valid(p):
			player = p.global_position
	_frames.append({
		"pitch": float(state["pitch_deg"]),
		"fov": float(state["fov_deg"]),
		"dist": float(state["distance_m"]),
		"rig": _rig.global_position,
		"cam": cam_pos,
		"player": player,
	})


# ---------------------------------------------------------------- smooth -----
## A camera that jitters, snaps or pumps shows up here. One clean segment: walk in
## a straight line for two and a half seconds and record what the rig does.
func _test_follow_is_smooth() -> void:
	if _cast == null or _rig == null:
		_check(false, "pemain dan rig ada untuk uji kehalusan")
		return
	# a straight run of open ground: the map corner the previous test ended on
	# would have the knight walking into the fence
	var start: Variant = _start_spot()
	if start != null:
		_cast.call("teleport_player", start)
		await _wait(0.5)
	_frames = []
	_recording = true
	_cast.call("set_virtual_stick", Vector2(0.18, -0.98))
	await _wait(2.5)
	_cast.call("set_virtual_stick", Vector2.ZERO)
	await _wait(0.5)
	_recording = false

	if _frames.size() < 40:
		_check(false, "ada cukup frame untuk menilai kehalusan", str(_frames.size()))
		return
	# skip the first third of a second: that is the start-up glide, not the walk
	var start := mini(20, _frames.size() / 4)
	var worst_step := 0.0
	var max_off := 0.0
	var min_x := 1.0e9
	var max_x := -1.0e9
	var min_z := 1.0e9
	var max_z := -1.0e9
	var prev: Dictionary = {}
	for i in range(_frames.size()):
		var f: Dictionary = _frames[i]
		if not prev.is_empty() and i > start:
			var d_cam: float = (f["rig"] as Vector3).distance_to(prev["rig"] as Vector3)
			worst_step = maxf(worst_step, d_cam)
		if i > start:
			var off: Vector3 = (f["rig"] as Vector3) - (f["player"] as Vector3)
			max_off = maxf(max_off, Vector2(off.x, off.z).length())
			min_x = minf(min_x, off.x)
			max_x = maxf(max_x, off.x)
			min_z = minf(min_z, off.z)
			max_z = maxf(max_z, off.z)
		prev = f
	var swing := maxf(max_x - min_x, max_z - min_z)
	print("[CAMERA] jalan 2,5 s: langkah terbesar %.3f m/frame, offset %.2f m, ayunan %.3f m" % [
		worst_step, max_off, swing])
	_check(worst_step < 0.6, "tidak ada lompatan posisi kamera", "%.3f m" % worst_step)
	_check(max_off < 8.0, "kamera tetap dekat pemain saat berjalan", "%.2f m" % max_off)
	_check(swing < 0.9, "offset kamera tidak berayun (pumping)", "%.3f m" % swing)


# -------------------------------------------------------------- occlusion ----
## Which prop fades is a pure function of the prop layout; check it against the
## real layout instead of a made-up one.
func _test_occlusion_plan() -> void:
	var view: Node3D = null
	var diorama: Node3D = null
	if _main != null:
		diorama = _main.get("_diorama") as Node3D
	if diorama != null and diorama.has_method("view"):
		view = diorama.call("view") as Node3D
	if view == null:
		_check(false, "RegionView tersedia untuk uji occlusion")
		return
	var layout: Array = view.call("prop_layout")
	_check(layout.size() > 100, "layout prop terbaca", str(layout.size()))
	var target: Array = []
	for raw in layout:
		var row: Array = raw
		if row.size() >= 5 and float(row[4]) > 1.6:
			target = row
			break
	_check(not target.is_empty(), "ada prop tinggi untuk diuji")
	if target.is_empty():
		return
	var x := float(target[1])
	var z := float(target[2])
	# camera 8 m behind the prop, knight 2 m past it: the prop is on the line
	var plan: Dictionary = view.call("occluders_for", Vector2(x, z + 2.0),
		Vector2(x, z - 8.0), 1.05, 2.5)
	_check(not plan.is_empty(), "prop di garis kamera-pemain memudar", str(plan.size()))
	var lowest := 1.0
	for key in plan.keys():
		lowest = minf(lowest, float(plan[key]))
	_check(lowest < 1.0, "pemudaran dither benar-benar terjadi", "%.2f" % lowest)
	_check(lowest >= 0.24, "prop yang memudar tidak hilang total", "%.2f" % lowest)
	# a knight far to the side: the corridor must not sweep the whole forest
	var aside: Dictionary = view.call("occluders_for", Vector2(x + 40.0, z),
		Vector2(x + 20.0, z - 8.0), 1.05, 2.5)
	_check(aside.size() <= 4, "corridor occlusion tidak menyapu seluruh hutan",
		"%d prop" % aside.size())


# ----------------------------------------------------------------- boot ------
func _boot_main() -> bool:
	if _main != null:
		return true
	if not ResourceLoader.exists(MAIN_SCENE):
		_check(false, "Main.tscn ada")
		return false
	_main = load(MAIN_SCENE).instantiate() as Control
	_main.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_main)
	for _i in 12:
		await get_tree().process_frame
	_cast = _main.get("_cast") as Node3D
	var diorama: Node3D = _main.get("_diorama") as Node3D
	if diorama != null:
		_rig = diorama.call("camera_rig") as Node3D
	_check(_cast != null and _rig != null, "Main, cast, dan rig kamera termuat")
	return _cast != null and _rig != null


func _start_spot() -> Variant:
	var diorama: Node3D = _main.get("_diorama") as Node3D
	if diorama == null:
		return null
	var region: RefCounted = diorama.call("region")
	if region == null:
		return null
	return region.call("start_position")


func _npc_spot() -> Variant:
	var diorama: Node3D = _main.get("_diorama") as Node3D
	if diorama == null:
		return null
	var region: RefCounted = diorama.call("region")
	if region == null:
		return null
	var m: Dictionary = region.call("marker", "Penjaga Bram")
	if m.is_empty():
		return null
	return (region.call("marker_pos", m) as Vector2) + Vector2(-1.0, 0.5)


## A walkable tile hard against the map's corner: the clamp has to ease the
## camera to a stop there without stepping.
func _edge_spot() -> Variant:
	var diorama: Node3D = _main.get("_diorama") as Node3D
	if diorama == null:
		return null
	var region: RefCounted = diorama.call("region")
	if region == null:
		return null
	var bounds: Rect2 = region.call("bounds")
	var tile: Vector2i = region.call("world_to_tile",
		bounds.position + Vector2(3.0, 3.0))
	var near: Vector2i = region.call("nearest_walkable", tile, 24)
	return region.call("tile_centre", near.x, near.y)
