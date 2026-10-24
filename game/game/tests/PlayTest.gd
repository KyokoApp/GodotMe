extends Node3D
## Headless gate for the two things a player notices immediately and a static
## check cannot see:
##
##   1. a flinch must always hand control back. The device reported the knight
##      freezing (stuck in `hurt`, drawn white) after an orc hit him twice;
##   2. every prop must stand ON the ground. The device reported trees and rocks
##      floating after a few of them were scaled below 1.0.
##
##   godot --headless --path game res://game/tests/PlayTest.tscn
##
## Exit code 1 when either rule is broken, so CI fails instead of shipping it.

const KNIGHT_DEF := "res://game/characters/data/knight.tres"
const ORC_DEF := "res://game/characters/data/orc.tres"
const ACTOR := "res://game/characters/Actor.gd"
const ENEMY := "res://game/characters/Enemy.gd"
const DIORAMA := "res://game/world/Diorama.tscn"

var failures := 0
var checks := 0


func _ready() -> void:
	await get_tree().process_frame
	await _test_flinch_recovers()
	await _test_flinch_restarts()
	await _test_movement_after_hit()
	await _test_death_holds()
	await _test_orc_swing_does_not_lock_player()
	await _test_props_stand_on_ground()
	await _test_billboards_stay_upright()
	await _test_camera_follows_player()
	await _test_dynamic_stick()

	print("[PLAY] %d pemeriksaan, %d gagal" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)


func _check(cond: bool, label: String, extra: String = "") -> void:
	checks += 1
	if cond:
		print("[PLAY] PASS %s" % label)
	else:
		failures += 1
		print("[PLAY] FAIL %s %s" % [label, extra])


func _actor(def_path: String, script_path: String = ACTOR) -> Node3D:
	var def: Resource = load(def_path)
	var node: Node3D = (load(script_path) as Script).new()
	node.call("setup", def)
	add_child(node)
	return node


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## One hit, one recovery. This is the baseline that already worked.
func _test_flinch_recovers() -> void:
	var knight := _actor(KNIGHT_DEF)
	await get_tree().process_frame
	knight.call("take_hit")
	_check(String(knight.get("state")) == "hurt", "satu pukulan masuk ke state hurt",
		String(knight.get("state")))
	await _wait(1.2)
	_check(String(knight.get("state")) == "idle", "pulih ke idle setelah flinch",
		String(knight.get("state")))
	knight.queue_free()


## The real bug: the same animation cannot be replayed, so a second flinch that
## arrives while `hurt` is already the "current" animation never restarts the
## anim - and because the anim had already finished, `animation_finished` never
## fires again. State stays HURT forever: no walking, no attack, no block.
func _test_flinch_restarts() -> void:
	var knight := _actor(KNIGHT_DEF)
	await get_tree().process_frame
	knight.call("take_hit")
	await _wait(1.2)   # let the first flinch end; `_anim` is still "hurt"
	_check(String(knight.get("state")) == "idle", "flinch pertama sudah selesai",
		String(knight.get("state")))
	knight.call("take_hit")
	await get_tree().process_frame
	var sprite: AnimatedSprite3D = knight.get("sprite")
	_check(sprite.frame < 2, "flinch kedua mengulang dari frame awal",
		"frame %d" % sprite.frame)
	await _wait(1.4)
	_check(String(knight.get("state")) == "idle", "pulih ke idle setelah flinch kedua",
		String(knight.get("state")))
	knight.queue_free()


## A hit must never take the stick away for good.
func _test_movement_after_hit() -> void:
	var knight := _actor(KNIGHT_DEF)
	await get_tree().process_frame
	knight.call("take_hit")
	await _wait(1.2)
	var before: Vector3 = knight.position
	for _i in 30:
		knight.call("drive", Vector2(1.0, 0.0), false, 0.033)
		await get_tree().process_frame
	_check(knight.position.x > before.x + 0.05, "bisa berjalan setelah dipukul",
		"x %.2f -> %.2f" % [before.x, knight.position.x])
	knight.queue_free()


func _test_death_holds() -> void:
	var orc := _actor(ORC_DEF, ENEMY)
	await get_tree().process_frame
	orc.call("die")
	await _wait(0.6)
	_check(String(orc.get("state")) == "death", "mati menahan frame terakhir",
		String(orc.get("state")))
	var sprite: AnimatedSprite3D = orc.get("sprite")
	_check(sprite.frame == sprite.sprite_frames.get_frame_count("death") - 1,
		"frame mati berhenti di frame terakhir", "frame %d" % sprite.frame)
	orc.queue_free()


## The exact device situation: an orc stands next to the knight and swings on
## its own timer. Whatever happens, the knight must be steerable afterwards.
func _test_orc_swing_does_not_lock_player() -> void:
	var knight := _actor(KNIGHT_DEF)
	var orc := _actor(ORC_DEF, ENEMY)
	await get_tree().process_frame
	orc.position = Vector3(0.9, 0.0, 0.0)
	orc.set("player", knight)
	var before: Vector3 = knight.position
	for _i in 260:   # ~8.6 s of frames, several ore swings
		await get_tree().process_frame
	var moved_after := false
	for _i in 30:
		knight.call("drive", Vector2(1.0, 0.0), false, 0.033)
		await get_tree().process_frame
	moved_after = knight.position.x > before.x + 0.05
	_check(moved_after, "ksatria tetap bisa dikendalikan setelah orc memukul",
		"x %.2f -> %.2f state=%s" % [before.x, knight.position.x,
			String(knight.get("state"))])
	knight.queue_free()
	orc.queue_free()


## Props float when they are scaled below 1.0 and the lift is not scaled with
## them: the quad is centred, so `y = height/2` only touches the ground at
## scale 1. This walks the real diorama and measures every prop's bottom edge.
func _test_props_stand_on_ground() -> void:
	if not ResourceLoader.exists(DIORAMA):
		_check(false, "Diorama.tscn ada", DIORAMA)
		return
	var world: Node3D = load(DIORAMA).instantiate()
	add_child(world)
	await get_tree().process_frame
	var props := world.get_node_or_null("Props")
	_check(props != null, "node Props ada")
	if props == null:
		return
	var worst := 0.0
	var worst_name := ""
	var count := 0
	for child in props.get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var quad := mi.mesh as QuadMesh
		if quad == null:
			continue
		count += 1
		var height: float = quad.size.y * absf(mi.scale.y)
		var bottom: float = mi.position.y - height * 0.5
		if absf(bottom) > absf(worst):
			worst = bottom
			worst_name = mi.name
	_check(count > 10, "prop terbaca dari diorama", str(count))
	# 2 cm is a fifth of one source pixel at the world pixel size: invisible.
	_check(absf(worst) <= 0.02, "semua prop menapak di tanah",
		"%s melayang %.3f m" % [worst_name, worst])
	world.queue_free()


## A camera-facing billboard is tilted back by the camera pitch, and that tilt
## happens around the quad centre - which sits above the feet. Result on the
## device: characters and props floated. Yaw-only billboards keep them upright.
func _test_billboards_stay_upright() -> void:
	var knight := _actor(KNIGHT_DEF)
	await get_tree().process_frame
	var sprite: AnimatedSprite3D = knight.get("sprite")
	_check(sprite.billboard == BaseMaterial3D.BILLBOARD_FIXED_Y,
		"sprite karakter hanya berputar pada sumbu Y (tidak miring)",
		"mode %d" % sprite.billboard)
	knight.queue_free()

	if not ResourceLoader.exists(DIORAMA):
		return
	var world: Node3D = load(DIORAMA).instantiate()
	add_child(world)
	await get_tree().process_frame
	var props := world.get_node_or_null("Props")
	if props == null:
		_check(false, "node Props ada untuk uji billboard")
		return
	var bad := 0
	var total := 0
	for child in props.get_children():
		var mi := child as MeshInstance3D
		if mi == null:
			continue
		var mat := mi.material_override as StandardMaterial3D
		if mat == null:
			continue
		total += 1
		if mat.billboard_mode != BaseMaterial3D.BILLBOARD_FIXED_Y:
			bad += 1
	_check(total > 10 and bad == 0, "semua prop memakai billboard sumbu Y",
		"%d dari %d masih miring" % [bad, total])
	world.queue_free()


## The owner's report: "the camera does not follow where the character walks".
func _test_camera_follows_player() -> void:
	if not ResourceLoader.exists(DIORAMA):
		return
	var world: Node3D = load(DIORAMA).instantiate()
	add_child(world)
	await get_tree().process_frame
	var rig := world.get_node_or_null("CameraRig") as Node3D
	_check(rig != null, "CameraRig ada di diorama")
	if rig == null:
		return
	var walker := _actor(KNIGHT_DEF)
	walker.position = Vector3(0.0, 0.0, 0.0)
	rig.call("set_follow_target", walker)
	await get_tree().process_frame
	var start := rig.position
	walker.position = Vector3(3.5, 0.0, 2.0)
	for _i in 90:
		await get_tree().process_frame
	var moved: float = Vector2(rig.position.x - start.x, rig.position.z - start.z).length()
	_check(moved > 2.5, "kamera mengikuti karakter yang berjalan",
		"pindah %.2f m dari %.2f" % [moved, start.length()])
	var err: float = Vector2(rig.position.x - 3.5, rig.position.z - 2.0).length()
	_check(err < 1.2, "kamera berhenti dekat karakter (bukan jauh tertinggal)",
		"selisih %.2f m" % err)
	walker.queue_free()
	world.queue_free()


## The owner's request: the stick should appear where the thumb lands, and only
## in the left half of the screen.
func _test_dynamic_stick() -> void:
	var pad: Node = (load("res://game/characters/TouchControls.gd") as Script).new()
	add_child(pad)
	await get_tree().process_frame
	var base: Panel = pad.get("_base")
	_check(base != null and not base.visible, "stik tersembunyi sebelum disentuh")

	var vp := get_viewport().get_visible_rect().size
	var spot := Vector2(vp.x * 0.22, vp.y * 0.78)
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.pressed = true
	down.position = spot
	pad.call("_input", down)
	await get_tree().process_frame
	_check(base.visible, "stik muncul saat layar kiri disentuh")
	var centre: Vector2 = base.position + Vector2(96.0, 96.0)
	_check(centre.distance_to(spot) < 40.0, "stik muncul di titik sentuhan",
		"pusat %s vs sentuh %s" % [centre, spot])

	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = spot + Vector2(70.0, 0.0)
	pad.call("_input", drag)
	await get_tree().process_frame
	var v: Vector2 = pad.get("stick_vector")
	_check(v.x > 0.6 and absf(v.y) < 0.2, "dorongan ke kanan menghasilkan jalan ke kanan",
		str(v))

	var up := InputEventScreenTouch.new()
	up.index = 0
	up.pressed = false
	up.position = drag.position
	pad.call("_input", up)
	await get_tree().process_frame
	_check(not base.visible, "stik hilang setelah jari diangkat")
	_check((pad.get("stick_vector") as Vector2).length() < 0.01, "dorongan kembali nol")

	# the right half belongs to the buttons: touching it must not spawn a stick
	var right := InputEventScreenTouch.new()
	right.index = 1
	right.pressed = true
	right.position = Vector2(vp.x * 0.85, vp.y * 0.6)
	pad.call("_input", right)
	await get_tree().process_frame
	_check(not base.visible, "layar kanan tidak memunculkan stik")
	pad.queue_free()
