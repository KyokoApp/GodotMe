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
