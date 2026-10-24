extends Node3D
## Shared body for every character: a billboarded pixel sprite, a soft blob
## shadow, distance-driven locomotion and the animation state machine.
##
## Subclasses (`Enemy.gd`, `Npc.gd`) only implement `tick()`; the player is
## driven directly by CharacterWorld from the touch stick.
##
## Placement rules that matter for the HD-2D look:
##   * the node origin is the FEET, measured from the IDLE bounding box, so a
##     character stands on the ground instead of hovering by its canvas centre;
##   * the sprite quad is offset by that same pivot, and the offset mirrors with
##     `flip_h`, so turning around does not slide the feet sideways;
##   * the sprite is alpha-scissored and shaded, so the world sun lights it and
##     it sorts correctly against trees instead of being an unshaded sticker;
##   * no baked shadow is used - one uniform blob from `blob_shadow.gdshader`.

signal attacked(actor: Node3D)
signal hurt(actor: Node3D)
signal died(actor: Node3D)
signal battle_triggered(actor: Node3D)

const CharacterAssets := preload("res://game/characters/CharacterAssets.gd")
const BLOB_SHADER := "res://game/characters/blob_shadow.gdshader"
const DUST_SHADER := "res://game/characters/dust_puff.gdshader"

const STATE_IDLE := "idle"
const STATE_WALK := "walk"
const STATE_RUN := "run"
const STATE_ATTACK := "attack"
const STATE_BLOCK := "block"
const STATE_HURT := "hurt"
const STATE_DEATH := "death"

## ~3 frames at 60 fps: enough to feel a hit, not enough to feel laggy.
const HITSTOP_SEC := 0.05
## Position grid, as a fraction of one source pixel. A whole pixel is ~3.5
## screen pixels at the default zoom and makes walking look like it stutters;
## a quarter removes the edge crawl while keeping motion smooth.
const SNAP_FRACTION := 0.25
const FLASH_SEC := 0.09

var def: Resource
var world_pixel := 0.05
var body_radius := 0.3

var sprite: AnimatedSprite3D
var visual: Node3D
var blob: MeshInstance3D
var dust: CPUParticles3D

var state := STATE_IDLE
var facing := 1.0
## Footprint circles ({x, z, r}) and the walkable rectangle, both in world XZ.
var blockers: Array = []
var bounds := Rect2(-12.0, -9.0, 24.0, 18.0)

var _anim := ""
var _hitstop := 0.0
var _flash := 0.0
var _squash := 0.0
var _squash_kind := 0.0
var _dead := false
var _fading := false
var _combo: Array = []
var _combo_index := 0
var _combo_queued := false
var _step_acc := 0.0
## Speed the running animation should play at. Hit-stop zeroes `speed_scale`,
## and without this the animation stays frozen *after* the hit-stop ends: that
## is what locked the knight in `hurt` (no walking, no attack) on the device.
var _anim_speed := 1.0
## Seconds since the current one-shot state started; a watchdog hands control
## back even if an `animation_finished` is ever missed.
var _state_time := 0.0


func setup(character_def: Resource) -> void:
	def = character_def
	world_pixel = float(def.call("pixel_world"))
	body_radius = float(def.get("body_radius_m"))
	_build_visual()
	_build_blob()
	_build_dust()
	_collect_combo()
	sprite.animation_finished.connect(_on_anim_finished)
	_play("idle", 1.0)


# ----------------------------------------------------------------- build ----
func _build_visual() -> void:
	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)

	sprite = AnimatedSprite3D.new()
	sprite.name = "Sprite"
	sprite.sprite_frames = CharacterAssets.build_frames(def)
	sprite.centered = true
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.alpha_scissor_threshold = 0.45
	sprite.shaded = true
	sprite.double_sided = true
	sprite.pixel_size = world_pixel
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.add_child(sprite)
	_place_sprite()


## Put the feet pivot on the node origin. `centered` keeps the quad centred on
## the sprite node, so the node itself is the thing that moves; the x part is
## mirrored with the facing because flip_h mirrors the pivot with the texture.
func _place_sprite() -> void:
	var fs: Vector2i = def.get("frame_size")
	var pivot: Vector2 = def.get("pivot")
	var dx := (float(fs.x) * 0.5 - pivot.x) * world_pixel
	var dy := (pivot.y - float(fs.y) * 0.5) * world_pixel
	sprite.position = Vector3(dx * facing, dy, 0.0)


func _build_blob() -> void:
	var quad := QuadMesh.new()
	quad.size = def.call("blob_size")
	blob = MeshInstance3D.new()
	blob.name = "Blob"
	blob.mesh = quad
	var mat := ShaderMaterial.new()
	if ResourceLoader.exists(BLOB_SHADER):
		mat.shader = load(BLOB_SHADER)
	blob.material_override = mat
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blob.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	# above the path decals (0.015 / 0.02) so the shadow is never clipped by them
	blob.position = Vector3(0.0, 0.035, 0.0)
	add_child(blob)


func _build_dust() -> void:
	dust = CPUParticles3D.new()
	dust.name = "Dust"
	dust.emitting = false
	dust.one_shot = true
	dust.amount = 5
	dust.lifetime = 0.5
	dust.explosiveness = 0.9
	dust.direction = Vector3(0.0, 1.0, 0.0)
	dust.spread = 60.0
	dust.initial_velocity_min = 0.2
	dust.initial_velocity_max = 0.55
	dust.gravity = Vector3(0.0, -0.5, 0.0)
	dust.scale_amount_min = 0.5
	dust.scale_amount_max = 1.3
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.16)
	var mat := ShaderMaterial.new()
	if ResourceLoader.exists(DUST_SHADER):
		mat.shader = load(DUST_SHADER)
	quad.material = mat
	dust.mesh = quad
	dust.position = Vector3(0.0, 0.06, 0.0)
	add_child(dust)


func _collect_combo() -> void:
	_combo.clear()
	for name in ["attack_1", "attack_2", "attack_3"]:
		if def.call("has_anim", name):
			_combo.append(name)


# ------------------------------------------------------------- animation ----
func _play(anim: String, anim_speed: float, restart: bool = false) -> void:
	if not def.call("has_anim", anim):
		return
	if _anim != anim or restart:
		_anim = anim
		sprite.play(anim)
	_anim_speed = maxf(0.05, anim_speed)
	sprite.speed_scale = _anim_speed


## How long one pass of a one-shot animation lasts, in seconds.
func _anim_seconds(anim: String) -> float:
	var entry: Dictionary = def.call("anim_entry", anim)
	if entry.is_empty():
		return 0.0
	var frames := float(entry.get("frames", 1))
	var fps := maxf(1.0, float(entry.get("fps", 10.0)))
	return frames / fps


func _enter_state(new_state: String) -> void:
	state = new_state
	_state_time = 0.0


func _on_anim_finished() -> void:
	match state:
		STATE_ATTACK:
			if _combo_queued and _combo_index + 1 < _combo.size():
				_start_attack(_combo_index + 1)
			else:
				_enter_state(STATE_IDLE)
				_play(STATE_IDLE, 1.0)
		STATE_HURT:
			if not _dead:
				_enter_state(STATE_IDLE)
				_play(STATE_IDLE, 1.0)
		_:
			# death and block hold their last frame on purpose
			pass


# -------------------------------------------------------------- movement ----
func drive(dir: Vector2, run_hint: bool, delta: float) -> void:
	if def == null or _dead:
		return
	if state == STATE_ATTACK or state == STATE_HURT or state == STATE_BLOCK:
		return
	var mag := clampf(dir.length(), 0.0, 1.0)
	if mag < 0.06:
		stop_locomotion()
		return

	var nd := dir.normalized()
	var walk_speed := float(def.call("locomotion_speed", "walk"))
	var run_speed := float(def.call("locomotion_speed", "run"))
	var can_run := run_speed > 0.01 and run_hint and mag > 0.55
	var anim := STATE_RUN if can_run else STATE_WALK
	var nominal := run_speed if can_run else walk_speed
	if nominal <= 0.01:
		return

	# Speed and cadence come from the same stride number, and `speed_scale` is
	# the ratio between them, so a half-pushed stick walks half as fast with
	# half the cadence: the feet keep their grip on the ground.
	var speed := 0.0
	if can_run:
		speed = lerpf(walk_speed, run_speed, clampf((mag - 0.55) / 0.45, 0.0, 1.0))
	else:
		speed = walk_speed * clampf(mag / 0.55, 0.25, 1.0)

	if state != anim:
		_enter_state(anim)
	_apply_facing(nd.x)
	_play(anim, speed / nominal)
	_move(Vector3(nd.x, 0.0, nd.y) * speed * delta)

	var stride := float(def.get("run_stride_m")) if can_run else float(def.get("walk_stride_m"))
	_step_acc += speed * delta
	if stride > 0.01 and _step_acc >= stride * 0.5:
		_step_acc = 0.0
		_puff()


func stop_locomotion() -> void:
	if state == STATE_WALK or state == STATE_RUN:
		_enter_state(STATE_IDLE)
		_play(STATE_IDLE, 1.0)
	_step_acc = 0.0


func _move(step: Vector3) -> void:
	var p := Vector2(position.x + step.x, position.z + step.z)
	p = resolve_position(p)
	var grid := world_pixel * SNAP_FRACTION
	if grid > 0.0:
		p.x = roundf(p.x / grid) * grid
		p.y = roundf(p.y / grid) * grid
	position = Vector3(p.x, position.y, p.y)


## Circle-vs-circle push-out against the prop footprints, plus the meadow edge.
## Cheap and deterministic: no physics body, no tunnelling, and the props stay
## pure billboards in the world pack.
func resolve_position(p: Vector2) -> Vector2:
	var r := body_radius
	p.x = clampf(p.x, bounds.position.x + r, bounds.position.x + bounds.size.x - r)
	p.y = clampf(p.y, bounds.position.y + r, bounds.position.y + bounds.size.y - r)
	for _pass in range(2):
		for raw in blockers:
			if typeof(raw) != TYPE_DICTIONARY:
				continue
			var blk: Dictionary = raw
			var c := Vector2(float(blk.get("x", 0.0)), float(blk.get("z", 0.0)))
			var rad := float(blk.get("r", 0.0)) + r
			var d := p - c
			if d.length() < rad:
				if d.length() < 0.001:
					d = Vector2(0.0, 1.0)
				p = c + d.normalized() * rad
	return p


func _apply_facing(x: float) -> void:
	if absf(x) < 0.01:
		return
	var f := 1.0 if x > 0.0 else -1.0
	if is_equal_approx(f, facing):
		return
	facing = f
	sprite.flip_h = facing < 0.0
	_place_sprite()


func _puff() -> void:
	if dust != null:
		dust.restart()


# ---------------------------------------------------------------- combat ----
func try_attack() -> void:
	if def == null or _dead or state == STATE_HURT or state == STATE_DEATH:
		return
	if state == STATE_BLOCK:
		return
	if state == STATE_ATTACK:
		if _combo_index + 1 < _combo.size():
			_combo_queued = true
		return
	if _combo.is_empty():
		return
	_start_attack(0)


func _start_attack(index: int) -> void:
	if index >= _combo.size():
		return
	_combo_index = index
	_combo_queued = false
	_enter_state(STATE_ATTACK)
	_play(String(_combo[index]), 1.0, true)
	_squash = 0.18
	_squash_kind = 1.0
	attacked.emit(self)


func set_block(on: bool) -> void:
	if def == null or _dead:
		return
	if not on:
		if state == STATE_BLOCK:
			_enter_state(STATE_IDLE)
			_play(STATE_IDLE, 1.0)
		return
	if state == STATE_BLOCK:
		return
	if state == STATE_ATTACK or state == STATE_HURT or state == STATE_DEATH:
		return
	if not def.call("has_anim", "block"):
		return
	_enter_state(STATE_BLOCK)
	_play("block", 1.0, true)


func take_hit() -> void:
	if def == null or _dead:
		return
	# Two orcs swinging together used to chain-stun the player: he could not
	# move at all. One flinch per 0.2 s is enough to feel the hit.
	if state == STATE_HURT and _state_time < 0.2:
		return
	_hitstop = HITSTOP_SEC
	_flash = FLASH_SEC
	_squash = 0.18
	_squash_kind = -1.0
	hurt.emit(self)
	if def.call("has_anim", "hurt"):
		_enter_state(STATE_HURT)
		# `restart` matters: the second flinch arrives while `hurt` is still the
		# current animation name, so without it the strip would never rewind -
		# and because it had already finished, no `animation_finished` follows.
		_play("hurt", 1.0, true)


func die() -> void:
	if _dead:
		return
	_dead = true
	_enter_state(STATE_DEATH)
	if def.call("has_anim", "death"):
		_play("death", 1.0, true)
	died.emit(self)


func fade_out(seconds: float) -> void:
	_dead = true
	_fading = true
	sprite.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var tw := create_tween()
	tw.tween_property(sprite, "modulate:a", 0.0, seconds)
	await tw.finished
	hide()


func is_dead() -> bool:
	return _dead


func anim_name() -> String:
	return _anim


func combo_size() -> int:
	return _combo.size()


# ------------------------------------------------------------------ frame ---
func tick(_delta: float) -> void:
	pass


func _process(delta: float) -> void:
	if def == null or sprite == null:
		return
	_update_flash(delta)
	_update_squash(delta)
	if _hitstop > 0.0:
		_hitstop = maxf(0.0, _hitstop - delta)
		sprite.speed_scale = 0.0
		if _hitstop <= 0.0:
			sprite.speed_scale = _anim_speed   # resume where the hit stopped it
		return
	_state_time += delta
	_watch_one_shot()
	tick(delta)


## Hand control back if a one-shot animation never reported that it ended.
## Belt and braces on top of `animation_finished`: a dropped signal (device
## hiccup, a paused tree) must never leave a character permanently frozen.
func _watch_one_shot() -> void:
	if _dead:
		return
	if state != STATE_HURT and state != STATE_ATTACK:
		return
	var limit := _anim_seconds(state) / maxf(_anim_speed, 0.05) + 0.35
	if _state_time < limit:
		return
	if state == STATE_ATTACK and _combo_queued and _combo_index + 1 < _combo.size():
		return   # the next swing is about to start
	push_warning("[ACTOR] %s keluar dari state %s lewat pengawas waktu" % [name, state])
	_enter_state(STATE_IDLE)
	_play(STATE_IDLE, 1.0)


func _update_flash(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		var k := 1.0 + 1.3 * (_flash / FLASH_SEC)
		sprite.modulate = Color(k, k, k, sprite.modulate.a if _fading else 1.0)
	elif not _fading:
		sprite.modulate = Color.WHITE


func _update_squash(delta: float) -> void:
	if _squash <= 0.0:
		return
	_squash = maxf(0.0, _squash - delta)
	var a := _squash / 0.18
	var k := a * _squash_kind
	visual.scale = Vector3(1.0 - 0.09 * k, 1.0 + 0.11 * k, 1.0)
