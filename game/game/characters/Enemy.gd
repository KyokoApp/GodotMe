extends "res://game/characters/Actor.gd"
## Patrol enemy (the orcs). Walks its route, notices the player inside
## `detect_radius`, closes in slowly and swings once it is close enough.
##
## Contact does not start a battle yet - it raises `battle_triggered`, which the
## world turns into a notice. That is deliberate: there is no battle system in
## this stage, so nothing pretends there is one.

var patrol: Array = []
var patrol_index := 0
var detect_radius := 4.5
var contact_radius := 1.0
var player: Node3D = null

var _wait := 0.0
var _cooldown := 0.0
var _engaged := false
var _leash := 12.0

## Two solid hits and the orc goes down. Not a battle system - just enough for
## the hurt and death animations to actually be used.
var hp := 2


func _ready() -> void:
	died.connect(_on_died)


func _on_died(_actor: Node3D) -> void:
	# hold the last death frame for a moment, then fade out
	await get_tree().create_timer(0.9).timeout
	if is_instance_valid(self):
		fade_out(0.9)


func tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if player == null or not is_instance_valid(player):
		_patrol_step(delta)
		return

	var to := Vector2(player.position.x - position.x, player.position.z - position.z)
	var dist := to.length()

	if dist <= contact_radius:
		if not _engaged:
			_engaged = true
			battle_triggered.emit(self)
			_swing()
		stop_locomotion()
		return

	if dist <= detect_radius:
		drive(to.normalized(), false, delta)
		if dist < 2.4 and _cooldown <= 0.0:
			_cooldown = 1.8
			_swing()
		return

	if dist > _leash:
		_engaged = false
	_patrol_step(delta)


## Orc: one of the two swings at random, not a 1-2-3 combo (the pack has no
## third attack and the animation is not faked from it).
func _swing() -> void:
	if state == STATE_ATTACK or state == STATE_HURT or is_dead():
		return
	var options: Array = []
	if def.call("has_anim", "attack_1"):
		options.append("attack_1")
	if def.call("has_anim", "attack_2"):
		options.append("attack_2")
	if options.is_empty():
		return
	_enter_state(STATE_ATTACK)
	_play(String(options[randi() % options.size()]), 1.0, true)
	_squash = 0.18
	_squash_kind = 1.0
	attacked.emit(self)
	_swing_landed()


func _patrol_step(delta: float) -> void:
	if patrol.size() < 2:
		stop_locomotion()
		return
	if _wait > 0.0:
		_wait = maxf(0.0, _wait - delta)
		stop_locomotion()
		return
	var target: Vector2 = patrol[patrol_index]
	var to := target - Vector2(position.x, position.z)
	if to.length() < 0.3:
		patrol_index = (patrol_index + 1) % patrol.size()
		_wait = 1.6
		stop_locomotion()
		return
	drive(to.normalized(), false, delta)


## The club comes down about a third of a second into the swing; that is when a
## player standing in reach should flinch.
func _swing_landed() -> void:
	await get_tree().create_timer(0.33).timeout
	if not is_instance_valid(self) or player == null or not is_instance_valid(player):
		return
	if bool(player.call("is_dead")):
		return
	var d := Vector2(player.position.x - position.x, player.position.z - position.z)
	if d.length() <= 1.7:
		player.call("take_hit")
