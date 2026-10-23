class_name PlayerController
extends CharacterBody3D
## Playable protagonist (Nara) controller in 2.5D Low-Poly + Pixel Billboard world.
## Features smooth acceleration/deceleration, 4/8-dir billboard state machine, 3-hit combo with anticipation/follow-through,
## i-frame roll/dodge, Lantern Oil light aura, touch auto-aim assist, and companion moth Kelip orbit.

const ACCELERATION: float = 26.0
const DECELERATION: float = 32.0
const BASE_MOVE_SPEED: float = 5.4
const SPRINT_MULTIPLIER: float = 1.35
const DODGE_SPEED: float = 10.8
const DODGE_DURATION: float = 0.28
const DODGE_IFRAME_DURATION: float = 0.22
const COMBO_RESET_TIME: float = 0.75

enum State { IDLE, MOVE, DODGE, ATTACK, SKILL, HURT, INTERACT }

var current_state: State = State.IDLE
var move_input: Vector2 = Vector2.ZERO
var facing_dir: Vector3 = Vector3.FORWARD

# Combat & Combo tracking
var combo_step: int = 0
var combo_timer: float = 0.0
var state_timer: float = 0.0
var iframe_timer: float = 0.0
var skill_1_cooldown: float = 0.0
var skill_2_cooldown: float = 0.0
var lock_on_target: Node3D = null

# Node references created dynamically or attached in scene
@onready var sprite_billboard: Sprite3D = $Sprite3D
@onready var lantern_light: OmniLight3D = $LanternLight3D
@onready var kelip_companion: Node3D = $KelipCompanion
@onready var attack_area: Area3D = $AttackHitbox
@onready var interact_area: Area3D = $InteractArea

var _anim_time: float = 0.0
var _step_dust_timer: float = 0.0

func _ready() -> void:
	add_to_group("player")
	EventBus.hit_stop_requested.connect(_on_hit_stop_requested)
	_update_lantern_visuals(0.0)

func _physics_process(delta: float) -> void:
	_anim_time += delta
	_update_timers(delta)
	_update_kelip_orbit(delta)
	_update_lantern_visuals(delta)

	match current_state:
		State.IDLE, State.MOVE:
			_process_movement(delta)
		State.DODGE:
			_process_dodge(delta)
		State.ATTACK, State.SKILL, State.HURT, State.INTERACT:
			_process_locked_state(delta)

	move_and_slide()
	_animate_billboard_squash_stretch(delta)
	_broadcast_lantern_shader_globals()

func set_touch_move_vector(vec: Vector2) -> void:
	move_input = vec.limit_length(1.0)

func trigger_attack() -> void:
	if current_state in [State.DODGE, State.HURT]:
		return
	if GameState.current_stamina < 10.0:
		EventBus.toast_notification.emit("Napas Nara tersengal (Stamina rendah)", "combat")
		return

	GameState.current_stamina = maxf(0.0, GameState.current_stamina - 10.0)
	EventBus.player_stamina_changed.emit(GameState.current_stamina, GameState.max_stamina)

	# Auto-aim assist toward nearest enemy within 4.5m for comfortable mobile touch combat
	_apply_auto_aim_assist(4.5)

	combo_step = (combo_step % 3) + 1
	combo_timer = COMBO_RESET_TIME
	current_state = State.ATTACK
	# Anticipation + Strike + Follow-through duration per combo step
	state_timer = 0.24 if combo_step < 3 else 0.36
	velocity = facing_dir * (2.6 if combo_step < 3 else 4.2)

	AudioBus.play_sfx("swing", 0.90 + float(combo_step) * 0.06, 1.02 + float(combo_step) * 0.06)
	_execute_melee_hitbox(combo_step)

func trigger_dodge() -> void:
	if current_state == State.DODGE or GameState.current_stamina < 18.0:
		return
	GameState.current_stamina = maxf(0.0, GameState.current_stamina - 18.0)
	EventBus.player_stamina_changed.emit(GameState.current_stamina, GameState.max_stamina)

	current_state = State.DODGE
	state_timer = DODGE_DURATION
	iframe_timer = DODGE_IFRAME_DURATION
	var dodge_dir: Vector3 = Vector3(move_input.x, 0.0, move_input.y).normalized()
	if dodge_dir.length_squared() < 0.01:
		dodge_dir = -facing_dir
	facing_dir = dodge_dir
	velocity = dodge_dir * DODGE_SPEED
	AudioBus.play_sfx("step", 1.15, 1.30)

func trigger_skill_1_sinar_fokus() -> void:
	# Skill 1: Sinar Fokus (Focused Lantern Flare - breaks Senyap shadow armor & stuns nearby enemies)
	if skill_1_cooldown > 0.0 or GameState.current_lantern_oil < 12.0:
		EventBus.toast_notification.emit("Minyak Cahaya atau jeda Skill 1 belum siap", "skill")
		return
	GameState.consume_lantern_oil(12.0)
	skill_1_cooldown = 5.0
	current_state = State.SKILL
	state_timer = 0.35
	AudioBus.play_sfx("lantern_ignite", 0.95, 1.05)
	EventBus.screen_shake_requested.emit(0.18, 0.20)
	_execute_lantern_skill_aoe(5.5, 28, true)

func trigger_skill_2_perisai_senja() -> void:
	# Skill 2: Gelombang Kelip (Restores slight HP/Stamina and pushes enemies back with warm pastel pulse)
	if skill_2_cooldown > 0.0 or GameState.current_lantern_oil < 18.0:
		EventBus.toast_notification.emit("Minyak Cahaya atau jeda Skill 2 belum siap", "skill")
		return
	GameState.consume_lantern_oil(18.0)
	skill_2_cooldown = 8.5
	current_state = State.SKILL
	state_timer = 0.40
	GameState.current_hp = mini(GameState.max_hp, GameState.current_hp + 22)
	EventBus.player_hp_changed.emit(GameState.current_hp, GameState.max_hp)
	AudioBus.play_sfx("lantern_ignite", 1.10, 1.22)
	_execute_lantern_skill_aoe(4.2, 18, true)

func trigger_contextual_interact() -> void:
	if interact_area == null:
		return
	var bodies: Array[Node3D] = interact_area.get_overlapping_bodies()
	var areas: Array[Area3D] = interact_area.get_overlapping_areas()
	for a in areas:
		if a.has_method("interact_with_player"):
			a.call("interact_with_player", self)
			return
	for b in bodies:
		if b.has_method("interact_with_player"):
			b.call("interact_with_player", self)
			return

func toggle_lock_on() -> void:
	if lock_on_target != null and is_instance_valid(lock_on_target):
		lock_on_target = null
		EventBus.lock_on_target_changed.emit(null)
		return
	lock_on_target = _find_nearest_enemy(9.0)
	EventBus.lock_on_target_changed.emit(lock_on_target)

func receive_damage(raw_damage: int, attacker_pos: Vector3) -> void:
	if iframe_timer > 0.0 or current_state == State.DODGE:
		return
	var mitigation: int = 3 if GameState.unlocked_skills.get("penjaga_2_perisai_senja", false) else 0
	var final_dmg: int = maxi(1, raw_damage - mitigation)
	GameState.current_hp = maxi(0, GameState.current_hp - final_dmg)
	EventBus.player_hp_changed.emit(GameState.current_hp, GameState.max_hp)
	EventBus.player_damaged.emit(final_dmg, attacker_pos)
	EventBus.screen_shake_requested.emit(0.25, 0.18)

	# Directional knockback
	var kb_dir: Vector3 = (global_position - attacker_pos)
	kb_dir.y = 0.0
	velocity = kb_dir.normalized() * 6.5
	current_state = State.HURT
	state_timer = 0.22
	iframe_timer = 0.45

	if GameState.current_hp <= 0:
		EventBus.player_died.emit()
		# Respawn at last lit lantern with 60% HP & Oil
		GameState.current_hp = int(float(GameState.max_hp) * 0.6)
		GameState.refill_lantern_oil(50.0)
		EventBus.player_hp_changed.emit(GameState.current_hp, GameState.max_hp)

func _process_movement(delta: float) -> void:
	var target_dir: Vector3 = Vector3(move_input.x, 0.0, move_input.y)
	var speed_bonus: float = 1.12 if GameState.unlocked_skills.get("pelaut_1_langkah_angin", false) else 1.0
	var target_vel: Vector3 = target_dir * BASE_MOVE_SPEED * speed_bonus

	if target_dir.length_squared() > 0.02:
		current_state = State.MOVE
		facing_dir = target_dir.normalized()
		velocity.x = move_toward(velocity.x, target_vel.x, ACCELERATION * delta)
		velocity.z = move_toward(velocity.z, target_vel.z, ACCELERATION * delta)
		_step_dust_timer -= delta
		if _step_dust_timer <= 0.0:
			_step_dust_timer = 0.34
			AudioBus.play_sfx("step", 0.92, 1.08)
	else:
		current_state = State.IDLE
		velocity.x = move_toward(velocity.x, 0.0, DECELERATION * delta)
		velocity.z = move_toward(velocity.z, 0.0, DECELERATION * delta)

	if not is_on_floor():
		velocity.y -= 18.0 * delta
	else:
		velocity.y = 0.0

func _process_dodge(delta: float) -> void:
	state_timer -= delta
	if state_timer <= 0.0:
		current_state = State.IDLE

func _process_locked_state(delta: float) -> void:
	state_timer -= delta
	velocity.x = move_toward(velocity.x, 0.0, DECELERATION * 0.8 * delta)
	velocity.z = move_toward(velocity.z, 0.0, DECELERATION * 0.8 * delta)
	if state_timer <= 0.0:
		current_state = State.IDLE

func _update_timers(delta: float) -> void:
	if iframe_timer > 0.0:
		iframe_timer -= delta
	if skill_1_cooldown > 0.0:
		skill_1_cooldown -= delta
	if skill_2_cooldown > 0.0:
		skill_2_cooldown -= delta
	if combo_timer > 0.0:
		combo_timer -= delta
		if combo_timer <= 0.0:
			combo_step = 0

	# Passive Stamina regeneration when not dodging/attacking
	if current_state in [State.IDLE, State.MOVE] and GameState.current_stamina < GameState.max_stamina:
		GameState.current_stamina = minf(GameState.max_stamina, GameState.current_stamina + 22.0 * delta)
		EventBus.player_stamina_changed.emit(GameState.current_stamina, GameState.max_stamina)

	# Slow passive Lantern Oil consumption while exploring dark zones
	if GameState.lantern_lit and GameState.current_lantern_oil > 0.0:
		GameState.consume_lantern_oil(0.32 * delta)

func _execute_melee_hitbox(step: int) -> void:
	var base_dmg: int = 16 + (GameState.level * 3) + (step * 5)
	var is_crit: bool = (step == 3)
	for node in get_tree().get_nodes_in_group("enemies"):
		if not (node is Node3D):
			continue
		var enemy_3d: Node3D = node as Node3D
		var dist: float = global_position.distance_to(enemy_3d.global_position)
		if dist <= 2.4:
			var to_enemy: Vector3 = (enemy_3d.global_position - global_position).normalized()
			if facing_dir.dot(to_enemy) > -0.15 or dist < 1.2:
				if enemy_3d.has_method("take_combat_damage"):
					enemy_3d.call("take_combat_damage", base_dmg, global_position, GameState.lantern_lit, is_crit)
					EventBus.hit_stop_requested.emit(3 if step == 3 else 2)
					EventBus.screen_shake_requested.emit(0.16 if step == 3 else 0.08, 0.12)
					AudioBus.play_sfx("hit", 0.90, 1.10)
					# Slight weapon durability wear
					GameState.weapon_durability = maxf(10.0, GameState.weapon_durability - 0.15)

func _execute_lantern_skill_aoe(radius: float, dmg: int, is_light_burst: bool) -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		if not (node is Node3D):
			continue
		var enemy_3d: Node3D = node as Node3D
		if global_position.distance_to(enemy_3d.global_position) <= radius:
			if enemy_3d.has_method("take_combat_damage"):
				enemy_3d.call("take_combat_damage", dmg, global_position, is_light_burst, true)

func _apply_auto_aim_assist(max_dist: float) -> void:
	if lock_on_target != null and is_instance_valid(lock_on_target):
		var dir: Vector3 = (lock_on_target.global_position - global_position)
		dir.y = 0.0
		if dir.length_squared() > 0.01:
			facing_dir = dir.normalized()
		return
	var nearest: Node3D = _find_nearest_enemy(max_dist)
	if nearest != null:
		var dir: Vector3 = (nearest.global_position - global_position)
		dir.y = 0.0
		if dir.length_squared() > 0.01:
			facing_dir = dir.normalized()

func _find_nearest_enemy(max_dist: float) -> Node3D:
	var best: Node3D = null
	var best_d: float = max_dist
	for node in get_tree().get_nodes_in_group("enemies"):
		if node is Node3D:
			var n3d: Node3D = node as Node3D
			var d: float = global_position.distance_to(n3d.global_position)
			if d < best_d:
				best_d = d
				best = n3d
	return best

func _animate_billboard_squash_stretch(_delta: float) -> void:
	if sprite_billboard == null:
		return
	# Flip horizontally only for left/right symmetry
	if absf(facing_dir.x) > 0.15:
		sprite_billboard.flip_h = (facing_dir.x < 0.0)

	# Squash & stretch + breathing animation principles
	var scale_y: float = 1.0
	var scale_x: float = 1.0
	match current_state:
		State.IDLE:
			scale_y = 1.0 + sin(_anim_time * 3.2) * 0.035
			scale_x = 1.0 - sin(_anim_time * 3.2) * 0.02
		State.MOVE:
			scale_y = 1.0 + absf(sin(_anim_time * 10.5)) * 0.08
			scale_x = 1.0 - absf(sin(_anim_time * 10.5)) * 0.05
		State.ATTACK:
			# Anticipation squash into follow-through stretch
			scale_x = 1.18
			scale_y = 0.88
		State.DODGE:
			scale_x = 1.24
			scale_y = 0.76
		State.HURT:
			scale_x = 0.85
			scale_y = 1.15
	sprite_billboard.scale = Vector3(scale_x, scale_y, 1.0)

func _update_kelip_orbit(_delta: float) -> void:
	if kelip_companion == null:
		return
	var orbit_angle: float = _anim_time * 2.1
	var offset: Vector3 = Vector3(cos(orbit_angle) * 0.85, 1.35 + sin(_anim_time * 4.2) * 0.15, sin(orbit_angle) * 0.85)
	kelip_companion.position = offset

func _update_lantern_visuals(_delta: float) -> void:
	if lantern_light == null:
		return
	var oil_ratio: float = clampf(GameState.current_lantern_oil / maxf(1.0, GameState.max_lantern_oil), 0.0, 1.0)
	var flicker: float = sin(_anim_time * 7.5) * 0.05 + cos(_anim_time * 13.0) * 0.03
	lantern_light.omni_range = lerpf(2.2, 10.5, oil_ratio) + flicker
	lantern_light.light_energy = lerpf(0.25, 2.1, oil_ratio) + flicker

func _broadcast_lantern_shader_globals() -> void:
	# Notify active materials in current chunk of player lantern position & radius
	var radius: float = lantern_light.omni_range if lantern_light != null else 8.0
	get_tree().call_group("lantern_reactive_materials", "update_player_lantern_state", global_position, radius)

func _on_hit_stop_requested(frames: int) -> void:
	# Subtle 2-4 frame hit-stop for tactile impact without breaking mobile flow
	Engine.time_scale = 0.08
	var duration_sec: float = float(clampi(frames, 1, 5)) / 60.0
	await get_tree().create_timer(duration_sec, true, false, true).timeout
	Engine.time_scale = 1.0
