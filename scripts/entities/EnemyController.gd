class_name EnemyController
extends CharacterBody3D
## Data-driven Enemy & Multi-Phase Boss AI for LANTERNFALL Part 1.
## Supports 8 distinct enemy behaviors (patrol, chase, flee from light, dark ambush, spore ranged, heavy shield)
## and 2 Multi-Phase Bosses (Penjaga Kabut & Nakhoda Abu) with clear attack telegraphs and Lantern vulnerability.

@export var enemy_data: EnemyData

enum AIState { PATROL, CHASE, FLEE_LIGHT, AMBUSH_WAIT, TELEGRAPH, ATTACK, STUNNED, DEAD }

var ai_state: AIState = AIState.PATROL
var current_hp: int = 80
var boss_phase: int = 1
var spawn_origin: Vector3 = Vector3.ZERO
var patrol_target: Vector3 = Vector3.ZERO
var state_timer: float = 0.0
var senyap_armor_active: bool = true

@onready var sprite_billboard: Sprite3D = $Sprite3D
@onready var telegraph_ring: MeshInstance3D = $TelegraphRing

var _anim_clock: float = 0.0

func _ready() -> void:
	add_to_group("enemies")
	spawn_origin = global_position
	_pick_new_patrol_point()
	if enemy_data != null:
		current_hp = enemy_data.max_hp
		senyap_armor_active = enemy_data.senyap_shield_requires_lantern

func configure_from_data(data: EnemyData) -> void:
	enemy_data = data
	current_hp = data.max_hp
	senyap_armor_active = data.senyap_shield_requires_lantern

func _physics_process(delta: float) -> void:
	if ai_state == AIState.DEAD or enemy_data == null:
		return
	_anim_clock += delta
	var player: Node3D = _get_player()
	if player == null:
		return

	var dist_to_player: float = global_position.distance_to(player.global_position)
	var player_has_strong_light: bool = GameState.lantern_lit and GameState.current_lantern_oil > 15.0 and dist_to_player <= 6.5

	# Light interaction: strips Senyap shadow armor and triggers flee on light-phobic creatures
	if player_has_strong_light:
		senyap_armor_active = false
		if enemy_data.behavior_archetype == "flee_from_light" and ai_state not in [AIState.STUNNED, AIState.TELEGRAPH]:
			ai_state = AIState.FLEE_LIGHT

	match ai_state:
		AIState.PATROL:
			_update_patrol(delta, player, dist_to_player)
		AIState.AMBUSH_WAIT:
			_update_ambush(delta, player, dist_to_player)
		AIState.FLEE_LIGHT:
			_update_flee_light(delta, player, dist_to_player)
		AIState.CHASE:
			_update_chase(delta, player, dist_to_player)
		AIState.TELEGRAPH:
			_update_telegraph(delta, player)
		AIState.ATTACK:
			_update_attack(delta, player, dist_to_player)
		AIState.STUNNED:
			state_timer -= delta
			velocity = velocity.move_toward(Vector3.ZERO, 18.0 * delta)
			if state_timer <= 0.0:
				ai_state = AIState.CHASE

	move_and_slide()
	_update_visual_feedback()

func take_combat_damage(raw_amount: int, source_pos: Vector3, exposed_to_lantern: bool, is_crit: bool) -> void:
	if ai_state == AIState.DEAD or enemy_data == null:
		return

	var multiplier: float = 1.0
	if exposed_to_lantern:
		senyap_armor_active = false
		multiplier = enemy_data.light_weakness_multiplier
	elif senyap_armor_active:
		multiplier = 0.45 # Shadow armor dampens physical strikes until illuminated

	var final_dmg: int = maxi(1, int(round(float(raw_amount) * multiplier * (1.35 if is_crit else 1.0))))
	current_hp = maxi(0, current_hp - final_dmg)

	EventBus.floating_damage_spawned.emit(global_position + Vector3(0, 1.4, 0), final_dmg, is_crit, exposed_to_lantern)

	# Knockback & brief stun
	var kb: Vector3 = (global_position - source_pos)
	kb.y = 0.0
	velocity = kb.normalized() * (3.2 if enemy_data.is_boss else 5.8)

	# Boss Phase Transition at 50% HP
	if enemy_data.is_boss and boss_phase == 1 and current_hp <= int(float(enemy_data.max_hp) * 0.5):
		boss_phase = 2
		EventBus.screen_shake_requested.emit(0.35, 0.4)
		EventBus.toast_notification.emit("%s memasuki Fase 2: Kabut Pekat!" % enemy_data.display_name_key, "boss")

	if current_hp <= 0:
		_handle_death()
	elif not enemy_data.is_boss:
		ai_state = AIState.STUNNED
		state_timer = 0.16

func _update_patrol(delta: float, _player: Node3D, dist_to_player: float) -> void:
	if enemy_data.behavior_archetype == "ambush_in_dark" and dist_to_player > 4.2:
		ai_state = AIState.AMBUSH_WAIT
		return
	if dist_to_player <= enemy_data.detection_range:
		ai_state = AIState.CHASE
		return

	var dir: Vector3 = (patrol_target - global_position)
	dir.y = 0.0
	if dir.length() < 0.6:
		_pick_new_patrol_point()
	else:
		velocity = dir.normalized() * (enemy_data.move_speed * 0.55)

func _update_ambush(_delta: float, _player: Node3D, dist_to_player: float) -> void:
	velocity = Vector3.ZERO
	if sprite_billboard != null:
		sprite_billboard.modulate.a = 0.25 # Semi-camouflaged in shadow
	if dist_to_player <= 3.8:
		if sprite_billboard != null:
			sprite_billboard.modulate.a = 1.0
		ai_state = AIState.TELEGRAPH
		state_timer = enemy_data.telegraph_duration * 0.7

func _update_flee_light(_delta: float, player: Node3D, dist_to_player: float) -> void:
	if dist_to_player > 7.5 or not GameState.lantern_lit:
		ai_state = AIState.PATROL
		return
	var away: Vector3 = (global_position - player.global_position)
	away.y = 0.0
	velocity = away.normalized() * (enemy_data.move_speed * 1.15)

func _update_chase(_delta: float, player: Node3D, dist_to_player: float) -> void:
	if dist_to_player > enemy_data.detection_range * 1.5 and not enemy_data.is_boss:
		ai_state = AIState.PATROL
		return
	if dist_to_player <= enemy_data.attack_range:
		ai_state = AIState.TELEGRAPH
		var phase_speedup: float = 0.75 if (enemy_data.is_boss and boss_phase == 2) else 1.0
		state_timer = enemy_data.telegraph_duration * phase_speedup
		velocity = Vector3.ZERO
		return

	var dir: Vector3 = (player.global_position - global_position)
	dir.y = 0.0
	velocity = dir.normalized() * enemy_data.move_speed

func _update_telegraph(delta: float, _player: Node3D) -> void:
	state_timer -= delta
	if telegraph_ring != null:
		telegraph_ring.visible = true
	if state_timer <= 0.0:
		if telegraph_ring != null:
			telegraph_ring.visible = false
		ai_state = AIState.ATTACK
		state_timer = 0.25

func _update_attack(delta: float, player: Node3D, dist_to_player: float) -> void:
	state_timer -= delta
	if state_timer <= 0.0:
		if dist_to_player <= enemy_data.attack_range + 0.55 and player.has_method("receive_damage"):
			var dmg: int = enemy_data.attack_damage + (6 if boss_phase == 2 else 0)
			player.call("receive_damage", dmg, global_position)
		ai_state = AIState.CHASE

func _handle_death() -> void:
	ai_state = AIState.DEAD
	GameState.add_exp(enemy_data.exp_reward)
	var koin_drop: int = randi_range(enemy_data.koin_embun_min, enemy_data.koin_embun_max)
	GameState.add_koin_embun(koin_drop)

	# Roll item drops
	for item_id in enemy_data.drop_table.keys():
		var chance: float = float(enemy_data.drop_table[item_id])
		if randf() <= chance:
			InventorySystem.add_item(String(item_id), 1)

	# Update Bestiary count
	var prev_kills: int = int(GameState.bestiary_kills.get(enemy_data.enemy_id, 0))
	GameState.bestiary_kills[enemy_data.enemy_id] = prev_kills + 1
	EventBus.bestiary_unlocked.emit(enemy_data.enemy_id, prev_kills + 1)

	if enemy_data.is_boss:
		GameState.add_pecahan_kelip(2)
		EventBus.toast_notification.emit("Boss Dikalahkan! +2 Pecahan Kelip", "boss")

	queue_free()

func _pick_new_patrol_point() -> void:
	var angle: float = randf() * TAU
	var radius: float = randf_range(2.0, 5.5)
	patrol_target = spawn_origin + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)

func _update_visual_feedback() -> void:
	if sprite_billboard == null:
		return
	if absf(velocity.x) > 0.1:
		sprite_billboard.flip_h = (velocity.x < 0.0)
	if ai_state == AIState.TELEGRAPH:
		# Anticipation crouch + warm warning flash before strike
		sprite_billboard.scale = Vector3(1.18, 0.82, 1.0)
		sprite_billboard.modulate = Color(1.0, 0.68, 0.52, 1.0)
	else:
		var breath: float = sin(_anim_clock * 4.0) * 0.04
		sprite_billboard.scale = Vector3(1.0 - breath, 1.0 + breath, 1.0)
		sprite_billboard.modulate = Color(0.55, 0.52, 0.68, 1.0) if senyap_armor_active else Color.WHITE

func _get_player() -> Node3D:
	var list: Array[Node] = get_tree().get_nodes_in_group("player")
	if list.size() > 0 and list[0] is Node3D:
		return list[0] as Node3D
	return null
