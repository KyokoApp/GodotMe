extends Node3D
## The battle's body: sprites, ground, camera, and the little bits of juice.
##
## The arena IS the field. Rather than building a separate stage (which would
## have to re-create the terrain materials, the light and the surrounding props
## and would sooner or later disagree with the world), the battle stands the
## fighters on the ground where the fight started, keeps the diorama's own light
## and scenery around them, and brings its own camera in for a closer, more
## side-on framing. "Arena sesuai permukaan + latar sekitar" then is not a
## promise, it is the same ground.
##
## What this class does NOT do: decide anything. It is told to play a hit, a
## break, a death; it reports where a unit stands so the UI can float a number
## over its head. All numbers live in BattleLogic.

const ASSETS := "res://game/characters/CharacterAssets.gd"

## Where the two lines stand, relative to the middle of the arena, in metres.
## z+ is towards the camera. Five enemy slots so the boss fight fits.
const PARTY_SLOTS := [Vector2(-2.4, 3.4), Vector2(-4.6, 2.4), Vector2(-1.2, 4.6), Vector2(-3.4, 4.8)]
const FOE_SLOTS := [
	Vector2(-4.3, -1.0), Vector2(-1.5, -2.1), Vector2(1.3, -2.1), Vector2(4.1, -1.0),
	Vector2(-0.1, -3.5),
]

var region: RefCounted = null
var centre := Vector2.ZERO
var camera: Camera3D = null

var _sprites: Dictionary = {}      ## uid -> AnimatedSprite3D
var _roots: Dictionary = {}        ## uid -> Node3D (the thing that moves)
var _defs: Dictionary = {}         ## uid -> CharacterDef
var _frames_cache: Dictionary = {}
var _shake := 0.0
var _shake_time := 0.0
var _flash: Dictionary = {}        ## uid -> seconds left
var _camera_base := Vector3.ZERO
var _camera_look := Vector3.ZERO
var _frozen := false


func build(logic: RefCounted) -> void:
	# the controller hands us the region the fight started on. Only a bare
	# BattleView dropped into a scene (a test) has to go looking for one - and
	# looking up the tree found nothing when the battle stands next to the
	# diorama instead of inside it, which put every fighter at y = 0.
	if region == null:
		region = _find_region()
	var assets: Script = load(ASSETS)
	var party_index := 0
	var foe_index := 0
	for raw in logic.get("units"):
		var unit: Dictionary = raw
		var def: Resource = _load_def(String(unit["def_path"]))
		if def == null:
			continue
		_defs[int(unit["uid"])] = def
		var slot: Vector2
		if String(unit["side"]) == "ally":
			slot = PARTY_SLOTS[party_index % PARTY_SLOTS.size()]
			party_index += 1
		else:
			slot = FOE_SLOTS[foe_index % FOE_SLOTS.size()]
			foe_index += 1
		_spawn(int(unit["uid"]), def, centre + slot, unit, assets)
	_frame_camera()
	play_idle_all()


func _find_region() -> RefCounted:
	var node: Node = get_parent()
	while node != null:
		if node.has_method("region"):
			return node.call("region")
		node = node.get_parent()
	return null


func _load_def(path: String) -> Resource:
	if not ResourceLoader.exists(path):
		return null
	return load(path)


func _spawn(uid: int, def: Resource, at: Vector2, unit: Dictionary, assets: Script) -> void:
	var root := Node3D.new()
	root.name = "Unit%d" % uid
	var y := 0.0
	if region != null:
		y = float(region.call("height_at", at))
	root.position = Vector3(at.x, y, at.y)
	add_child(root)
	var sprite := AnimatedSprite3D.new()
	sprite.name = "Sprite"
	var key := String(def.get("id"))
	if not _frames_cache.has(key):
		_frames_cache[key] = assets.call("build_frames", def)
	sprite.sprite_frames = _frames_cache[key]
	sprite.centered = true
	# the same billboard rule as the field: yaw towards the camera, never tilt
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.alpha_scissor_threshold = 0.45
	sprite.shaded = true
	sprite.double_sided = true
	sprite.pixel_size = float(def.call("pixel_world"))
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# feet on the ground: the pivot maths Actor.gd uses, so a battle sprite and a
	# field sprite of the same character stand at exactly the same height
	var fs: Vector2i = def.get("frame_size")
	var pivot: Vector2 = def.get("pivot")
	var dx := (float(fs.x) * 0.5 - pivot.x) * float(def.call("pixel_world"))
	var dy := (pivot.y - float(fs.y) * 0.5) * float(def.call("pixel_world"))
	sprite.position = Vector3(dx, dy, 0.0)
	root.add_child(sprite)
	# facing: the party looks right (+x), the enemies look left (-x), like two
	# lines meeting - not both facing the camera, which reads as a lineup
	var face := 1.0 if String(unit["side"]) == "ally" else -1.0
	sprite.flip_h = face < 0.0
	_sprites[uid] = sprite
	_roots[uid] = root


func _frame_camera() -> void:
	camera = Camera3D.new()
	camera.name = "BattleCamera"
	camera.fov = 33.0
	camera.near = 0.2
	camera.far = 400.0
	var ground := 0.0
	if region != null:
		ground = float(region.call("height_at", centre))
	_camera_base = Vector3(centre.x + 1.2, ground + 8.4, centre.y + 12.6)
	_camera_look = Vector3(centre.x, ground + 1.5, centre.y - 0.6)
	camera.position = _camera_base
	add_child(camera)
	camera.look_at(_camera_look, Vector3.UP)
	camera.make_current()


## Screen position of a unit, for floating damage numbers. Returns Vector2.ZERO
## when there is no camera yet (headless test runs).
func unit_screen(uid: int) -> Vector2:
	if camera == null or not _sprites.has(uid):
		return Vector2.ZERO
	var sprite: AnimatedSprite3D = _sprites[uid]
	var at: Vector3 = sprite.global_position + Vector3(0.0, 1.9, 0.0)
	if camera.is_position_behind(at):
		return Vector2.ZERO
	return camera.unproject_position(at)


func unit_world_top(uid: int) -> Vector3:
	if not _roots.has(uid):
		return Vector3.ZERO
	return (_roots[uid] as Node3D).global_position + Vector3(0.0, 1.9, 0.0)


func play(uid: int, anim: String, speed: float = 1.0) -> void:
	var sprite: AnimatedSprite3D = _sprites.get(uid, null)
	if sprite == null or sprite.sprite_frames == null:
		return
	if not sprite.sprite_frames.has_animation(anim):
		anim = "idle"
	if not sprite.sprite_frames.has_animation(anim):
		return
	sprite.speed_scale = speed
	sprite.play(anim)


func play_idle_all() -> void:
	for uid in _sprites.keys():
		var sprite: AnimatedSprite3D = _sprites[uid]
		if sprite.sprite_frames != null and sprite.sprite_frames.has_animation("idle"):
			sprite.speed_scale = 1.0
			sprite.play("idle")


## The hit itself: 2-3 frames of frozen animation, a white flash, and a shake.
## "Hit-stop" in the brief. Freezing the ANIMATION instead of the engine keeps
## the UI and the audio clock honest - only the sprite stops.
func hit(uid: int, strong: bool = false) -> void:
	var sprite: AnimatedSprite3D = _sprites.get(uid, null)
	if sprite == null:
		return
	play(uid, "hurt")
	_flash[uid] = 0.12
	if strong:
		_shake = 0.9
	else:
		_shake = 0.45
	_shake_time = 0.22
	await _freeze(sprite, 3 if strong else 2)


func _freeze(sprite: AnimatedSprite3D, frames: int) -> void:
	if sprite == null or not is_instance_valid(sprite):
		return
	var keep := sprite.speed_scale
	sprite.speed_scale = 0.0
	for i in range(maxi(1, frames)):
		await get_tree().process_frame
	if is_instance_valid(sprite):
		sprite.speed_scale = keep


func swing(uid: int) -> void:
	# the knight's combo is three strikes; pick them in order so a Boosted action
	# that lands four hits cycles through all three instead of repeating one
	var sprite: AnimatedSprite3D = _sprites.get(uid, null)
	if sprite == null or sprite.sprite_frames == null:
		return
	var options: Array = []
	for name in ["attack_1", "attack_2", "attack_3"]:
		if sprite.sprite_frames.has_animation(name):
			options.append(name)
	if options.is_empty():
		return
	play(uid, String(options[randi() % options.size()]))


func block(uid: int) -> void:
	play(uid, "block")


func break_unit(uid: int) -> void:
	play(uid, "hurt")
	_flash[uid] = 0.2
	var sprite: AnimatedSprite3D = _sprites.get(uid, null)
	if sprite != null:
		sprite.modulate = Color(0.72, 0.66, 0.86)


func recover_unit(uid: int) -> void:
	var sprite: AnimatedSprite3D = _sprites.get(uid, null)
	if sprite != null:
		sprite.modulate = Color.WHITE
	play(uid, "idle")


func die(uid: int) -> void:
	play(uid, "death")
	var sprite: AnimatedSprite3D = _sprites.get(uid, null)
	if sprite == null:
		return
	# fade out, but keep the node: the results screen still asks where it stood
	var tween := create_tween()
	tween.tween_property(sprite, "modulate:a", 0.0, 0.55)
	tween.tween_callback(func() -> void:
		if is_instance_valid(sprite):
			sprite.visible = false)


func cheer(uid: int) -> void:
	play(uid, "attack_1", 0.6)


## Called every frame by the controller.
func tick(delta: float) -> void:
	for uid in _flash.keys():
		var left := float(_flash[uid]) - delta
		var sprite: AnimatedSprite3D = _sprites.get(uid, null)
		if left <= 0.0:
			_flash.erase(uid)
			if sprite != null:
				sprite.self_modulate = Color.WHITE
		else:
			_flash[uid] = left
			if sprite != null:
				# a bright tint for a tenth of a second: the flash the brief asks
				# for, done with the sprite's own colour so it needs no shader
				sprite.self_modulate = Color(2.4, 2.2, 2.0)
	if camera == null:
		return
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 5.0)
		_shake_time = maxf(0.0, _shake_time - delta)
		var t := Time.get_ticks_msec() * 0.001
		var amp := _shake * 0.16
		camera.position = _camera_base + Vector3(sin(t * 61.0) * amp, sin(t * 43.0) * amp * 0.5, 0.0)
	else:
		camera.position = _camera_base
	camera.look_at(_camera_look, Vector3.UP)


func clear() -> void:
	for uid in _sprites.keys():
		var sprite: AnimatedSprite3D = _sprites[uid]
		if is_instance_valid(sprite):
			sprite.queue_free()
	_sprites.clear()
	_roots.clear()
	_defs.clear()
	if camera != null and is_instance_valid(camera):
		camera.queue_free()
	camera = null
