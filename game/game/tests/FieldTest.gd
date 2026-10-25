extends Node
## Headless gate for step 1: the map data, the minimap, the camera leash and the
## contextual action button.
##
##   godot --headless --path game res://game/tests/FieldTest.tscn
##
## A screenshot proves the field looks empty. These checks prove the things a
## screenshot cannot: that the camera can never leave the map, that the minimap
## works on a map ten times bigger, that fog survives a save, that the action
## button follows distance, and that nothing sits on top of a conversation.

const MAP_SCRIPT := preload("res://game/world/WorldMap.gd")
const CAMERA_SCRIPT := preload("res://game/world/DioramaCamera.gd")
const MINIMAP_SCRIPT := preload("res://game/ui/Minimap.gd")
const MAIN_SCENE := "res://game/Main.tscn"
const SAVE_SCRIPT := preload("res://game/save/SaveGame.gd")

const SCRATCH := "user://fieldtest"

var failures := 0
var checks := 0
var _main: Control
var _cast: Node3D


func _ready() -> void:
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(SCRATCH)
	OS.set_environment("RT_SETTINGS_DIR", SCRATCH)
	OS.set_environment("RT_SAVE_DIR", SCRATCH)
	_clean()
	_test_map_data()
	_test_fog()
	_test_fog_payload()
	_test_window_sizes()
	await _test_camera_limits()
	await _test_zoom_ladder()
	await _test_minimap_sizes()
	await _test_action_button()
	await _test_dialogue_clear_of_hud()
	print("[FIELD] %d pemeriksaan, %d gagal" % [checks, failures])
	OS.set_environment("RT_SETTINGS_DIR", "")
	OS.set_environment("RT_SAVE_DIR", "")
	_clean()
	get_tree().quit(0 if failures == 0 else 1)


func _check(cond: bool, label: String, extra: String = "") -> void:
	checks += 1
	if cond:
		print("[FIELD] PASS %s" % label)
	else:
		failures += 1
		print("[FIELD] FAIL %s %s" % [label, extra])


func _clean() -> void:
	var dir := DirAccess.open(SCRATCH)
	if dir == null:
		return
	for name in dir.get_files():
		DirAccess.remove_absolute(SCRATCH.path_join(name))


# ------------------------------------------------------------------ map ------
func _test_map_data() -> void:
	var map: RefCounted = MAP_SCRIPT.new()
	map.call("setup", 26, 20, 1.0, Vector2.ZERO)
	_check(int(map.get("width")) == 26 and int(map.get("height")) == 20,
		"peta 26x20 ubin terbentuk", "%dx%d" % [int(map.get("width")), int(map.get("height"))])
	var rect: Rect2 = map.call("bounds")
	_check(is_equal_approx(rect.size.x, 26.0) and is_equal_approx(rect.size.y, 20.0)
		and rect.position.distance_to(Vector2(-13.0, -10.0)) < 0.01,
		"batas peta 26x20 m di sekitar titik nol", str(rect))

	var tile: Vector2i = map.call("world_to_tile", Vector2(2.4, -3.6))
	var back: Vector2 = map.call("tile_centre", tile.x, tile.y)
	_check(back.distance_to(Vector2(2.4, -3.6)) < 0.75,
		"ubin dan titik tengahnya saling konsisten", "%s -> %s" % [str(tile), str(back)])

	# the outside of the map is not walkable, inside grass is
	_check(not bool(map.call("walkable_at", Vector2(400.0, 0.0))), "di luar peta tidak bisa dijalankan")
	_check(bool(map.call("walkable_at", Vector2.ZERO)), "rumput bisa dijalankan")
	var kinds: Dictionary = MAP_SCRIPT.get_script_constant_map()
	var dirt := int(kinds.get("KIND_DIRT", 1))
	map.call("paint_disc", Vector2.ZERO, 1.0, dirt)
	_check(int(map.call("tile_at", 13, 10)) == dirt, "ubin bisa dicat jadi tanah")
	_check(not bool(map.call("walkable_at", Vector2(40.0, 0.0))), "peta tetap tertutup di luar")


func _test_fog() -> void:
	var map: RefCounted = MAP_SCRIPT.new()
	map.call("setup", 26, 20, 1.0, Vector2.ZERO)
	_check(int(map.call("explored_count")) == 0, "peta mulai dalam gelap")
	var before := int(map.get("fog_revision"))
	var opened := bool(map.call("reveal", Vector2.ZERO, 5.0))
	_check(opened and int(map.call("explored_count")) > 0, "fog terbuka di sekitar pemain",
		str(map.call("explored_count")))
	_check(int(map.get("fog_revision")) > before, "revisi fog naik (memicu gambar ulang)")
	var again := bool(map.call("reveal", Vector2.ZERO, 5.0))
	_check(not again, "fog yang sama tidak dibuka dua kali")
	map.call("reveal_all")
	_check(is_equal_approx(float(map.call("explored_ratio")), 1.0), "reveal_all membuka semuanya",
		str(map.call("explored_ratio")))


func _test_fog_payload() -> void:
	var map: RefCounted = MAP_SCRIPT.new()
	map.call("setup", 26, 20, 1.0, Vector2.ZERO)
	map.call("reveal", Vector2(2.0, 3.0), 4.0)
	var explored := int(map.call("explored_count"))
	var payload: Dictionary = map.call("fog_payload")
	_check(String(payload.get("bits", "")).length() == 26 * 20, "fog disimpan sebagai 520 bit",
		str(String(payload.get("bits", "")).length()))

	var other: RefCounted = MAP_SCRIPT.new()
	other.call("setup", 26, 20, 1.0, Vector2.ZERO)
	var note := String(other.call("load_fog", payload))
	_check(note == "" and int(other.call("explored_count")) == explored,
		"fog yang sama dipulihkan utuh", "%s / %d vs %d" % [note, int(other.call("explored_count")), explored])

	# a save written on a bigger map must not be smeared onto this one
	var big: RefCounted = MAP_SCRIPT.new()
	big.call("setup", 120, 90, 1.0, Vector2.ZERO)
	var mismatch := String(other.call("load_fog", big.call("fog_payload")))
	_check(mismatch != "" and int(other.call("explored_count")) == explored,
		"fog dari peta lain ditolak tanpa merusak", mismatch)

	# a fog blob from a newer build is refused, not guessed at
	var future := {"schema": 99, "w": 26, "h": 20, "bits": "0".repeat(520)}
	var future_note := String(other.call("load_fog", future))
	_check(future_note.contains("lebih baru"), "fog versi lebih baru ditolak", future_note)

	# and the save carries it: schema bump, old saves get an empty fog
	var save: RefCounted = SAVE_SCRIPT.new(SCRATCH)
	save.call("load_game")
	save.call("set_fog", payload)
	_check(String(save.call("save_now")) == "", "save dengan fog bisa ditulis")
	var reloaded: RefCounted = SAVE_SCRIPT.new(SCRATCH)
	reloaded.call("load_game")
	var kept: Dictionary = reloaded.call("fog")
	_check(String(kept.get("bits", "")) == String(payload.get("bits", "")),
		"fog terbawa lewat simpan dan muat", str(kept.get("w", -1)))
	_clean()


func _test_window_sizes() -> void:
	var sizes := [[26, 20], [120, 90], [3, 3]]
	var widths: Array = []
	for pair in sizes:
		var map: RefCounted = MAP_SCRIPT.new()
		map.call("setup", int(pair[0]), int(pair[1]), 1.0, Vector2.ZERO)
		map.call("reveal_all")
		map.call("set_sight", Vector2.ZERO, 6.0)
		var img: Image = map.call("render_window", Vector2i(1, 1), 14, 4)
		widths.append(img.get_width())
		_check(img.get_width() == 14 * 4 and img.get_height() == 14 * 4,
			"jendela minimap %dx%d tetap 56x56 px" % [int(pair[0]), int(pair[1])],
			"%dx%d" % [img.get_width(), img.get_height()])
		var full: Image = map.call("render_image", int(map.call("texture_scale", 300)))
		_check(full.get_width() > 0 and full.get_height() > 0,
			"peta penuh %dx%d bisa digambar" % [int(pair[0]), int(pair[1])])
	_check(widths.size() == 3 and int(widths[0]) == int(widths[2]),
		"biaya jendela minimap tidak bergantung ukuran peta", str(widths))


# --------------------------------------------------------------- camera ------
func _test_camera_limits() -> void:
	for pair in [[26.0, 20.0], [208.0, 160.0]]:
		var rig: Node3D = CAMERA_SCRIPT.new()
		rig.name = "RigTest"
		var cam := Camera3D.new()
		cam.name = "Camera3D"
		cam.current = true
		rig.add_child(cam)
		add_child(rig)
		await get_tree().process_frame
		var rect := Rect2(-pair[0] * 0.5, -pair[1] * 0.5, pair[0], pair[1])
		rig.call("set_map_bounds", rect)
		var limits: Dictionary = rig.call("clamp_limits")
		var low: Vector2 = limits["min"]
		var high: Vector2 = limits["max"]
		_check(low.x <= high.x and low.y <= high.y,
			"batas kamera %.0fx%.0f m tidak terbalik" % [pair[0], pair[1]],
			"%s .. %s" % [str(low), str(high)])

		var walker := Node3D.new()
		add_child(walker)
		rig.call("set_follow_target", walker)
		# walk far past every edge, in all four directions
		for target in [Vector2(999.0, 999.0), Vector2(-999.0, 400.0), Vector2(80.0, -999.0)]:
			walker.position = Vector3(target.x, 0.0, target.y)
			for _i in 40:
				await get_tree().process_frame
			var pos := rig.position
			var inside := pos.x >= low.x - 0.001 and pos.x <= high.x + 0.001 \
				and pos.z >= low.y - 0.001 and pos.z <= high.y + 0.001
			_check(inside, "kamera %.0fx%.0f m tetap di dalam peta" % [pair[0], pair[1]],
				"target %s -> kamera %s (batas %s..%s)" % [str(target), str(pos), str(low), str(high)])
		walker.queue_free()
		rig.queue_free()
		await get_tree().process_frame


func _test_zoom_ladder() -> void:
	var rig: Node3D = CAMERA_SCRIPT.new()
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.current = true
	rig.add_child(cam)
	add_child(rig)
	await get_tree().process_frame
	rig.call("set_map_bounds", Rect2(-13.0, -10.0, 26.0, 20.0))
	var ladder: Array = CAMERA_SCRIPT.get_script_constant_map()["ZOOM_LADDER"]
	rig.call("set_zoom", 17.43)
	var snapped := float(rig.call("zoom"))
	var on_ladder := false
	for step_variant in ladder:
		if is_equal_approx(float(step_variant), snapped):
			on_ladder = true
	_check(on_ladder, "zoom menempel ke tangga (tidak 17,43)", "%.2f" % snapped)
	rig.call("set_zoom", 999.0)
	_check(float(rig.call("zoom")) <= float(rig.call("max_zoom")) + 0.001,
		"zoom maksimum mengikuti ukuran peta",
		"%.2f <= %.2f" % [float(rig.call("zoom")), float(rig.call("max_zoom"))])
	rig.call("set_zoom", 0.1)
	_check(float(rig.call("zoom")) >= 11.0 - 0.001, "zoom minimum dijaga",
		"%.2f" % float(rig.call("zoom")))
	rig.queue_free()
	await get_tree().process_frame


# --------------------------------------------------------------- minimap -----
func _test_minimap_sizes() -> void:
	for pair in [[26, 20], [160, 120]]:
		var map: RefCounted = MAP_SCRIPT.new()
		map.call("setup", int(pair[0]), int(pair[1]), 1.0, Vector2.ZERO)
		var mini: Control = MINIMAP_SCRIPT.new()
		add_child(mini)
		await get_tree().process_frame
		mini.call("set_map", map)
		mini.call("update_state", Vector2(2.0, 2.0), Vector2(0.0, -1.0), [])
		var tex: Texture2D = mini.call("texture")
		var tiles := int(mini.call("window_tiles"))
		_check(tex != null and tex.get_width() == tiles * 4,
			"minimap %dx%d menggambar jendela %d ubin" % [int(pair[0]), int(pair[1]), tiles],
			str(tex.get_width() if tex != null else -1))
		_check(int(map.call("explored_count")) > 0, "minimap ikut membuka fog saat dipakai")
		var before := int(mini.get("zoom_level"))
		mini.call("_on_tap")
		mini.call("_on_tap")
		_check(int(mini.get("zoom_level")) != before, "ketuk dua kali mengubah zoom minimap",
			"%d -> %d" % [before, int(mini.get("zoom_level"))])
		mini.queue_free()
		await get_tree().process_frame


# ------------------------------------------------------------ field HUD ------
func _boot_main() -> bool:
	if _main != null:
		return true
	if not ResourceLoader.exists(MAIN_SCENE):
		_check(false, "Main.tscn ada")
		return false
	_main = load(MAIN_SCENE).instantiate() as Control
	_main.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_main)
	for _i in 10:
		await get_tree().process_frame
	_cast = _main.get("_cast")
	_check(_cast != null, "cast termuat di dalam diorama")
	return _cast != null


func _hud() -> Control:
	return _main.get("_hud") as Control


func _wait_seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _test_action_button() -> void:
	if not await _boot_main():
		return
	var hud := _hud()
	_check(hud != null, "FieldHud terbangun di atas dunia")
	# a long way from everyone: no button at all
	_cast.call("teleport_player", Vector2(-9.0, 8.0))
	await _wait_seconds(0.35)
	_check(not bool(hud.call("action_visible")), "tombol aksi tersembunyi saat jauh dari target",
		String(hud.call("action_kind")))
	# standing next to the guard: the button offers Bicara
	_cast.call("teleport_player", Vector2(3.4, 5.2))
	await _wait_seconds(0.4)
	_check(bool(hud.call("action_visible")) and String(hud.call("action_kind")) == "talk",
		"tombol aksi muncul sebagai Bicara di dekat penjaga",
		String(hud.call("action_kind")))
	# and it goes away again when he walks off
	_cast.call("teleport_player", Vector2(-8.0, 6.5))
	await _wait_seconds(0.45)
	_check(not bool(hud.call("action_visible")), "tombol aksi memudar lagi setelah menjauh",
		String(hud.call("action_kind")))
	var action_rect: Rect2 = hud.call("action_rect")
	_check(action_rect.size.x >= 132.0,
		"tombol aksi minimal 132 px desain (≈72 dp)", str(action_rect.size))


func _test_dialogue_clear_of_hud() -> void:
	if not await _boot_main():
		return
	var hud := _hud()
	_cast.call("teleport_player", Vector2(3.4, 5.8))
	await _wait_seconds(0.3)
	_cast.call("press_interact")
	await _wait_seconds(0.4)
	var dlg: Variant = _cast.call("dialogue")
	var open := dlg != null and bool(dlg.get("is_open"))
	_check(open, "dialog terbuka untuk pemeriksaan tata letak")
	if not open:
		return
	var panel: Control = dlg.get("_panel")
	var drect := panel.get_global_rect()
	_check(not bool(hud.call("action_visible")), "tombol aksi disembunyikan saat dialog")
	var mini_rect: Rect2 = (hud.call("minimap") as Control).get_global_rect()
	var menu_rect: Rect2 = (hud.call("menu_button") as Control).get_global_rect()
	_check(not drect.intersects(mini_rect), "dialog tidak menimpa minimap",
		"%s vs %s" % [str(drect), str(mini_rect)])
	_check(not drect.intersects(menu_rect), "dialog tidak menimpa tombol menu",
		"%s vs %s" % [str(drect), str(menu_rect)])
	var vp := _main.get_viewport().get_visible_rect()
	_check(drect.position.y > vp.size.y * 0.45 and drect.end.y <= vp.size.y + 1.0,
		"dialog ringkas di bagian bawah layar", str(drect))
	dlg.call("advance")
	await _wait_seconds(0.15)
	print("[FIELD] dialog tertutup=%s" % str(not bool(dlg.get("is_open"))))
