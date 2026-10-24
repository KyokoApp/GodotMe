extends "res://game/characters/Actor.gd"
## Townsfolk / guard (the soldier). Stands his post, turns to face the player
## when they come close, and offers the story line. All the talking is done by
## CharacterWorld's dialogue box; this script only decides where to look.

var player: Node3D = null
var talk_radius := 2.2
## Where he is standing; he drifts back to it after a conversation.
var post := Vector2.ZERO


func tick(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var to := Vector2(player.position.x - position.x, player.position.z - position.z)
	if to.length() <= talk_radius + 1.2:
		_apply_facing(to.x)
	if state == STATE_IDLE or state == STATE_WALK:
		# A guard shifts his weight instead of freezing: a tiny idle sway is
		# already in the strip, this only keeps him from sliding off his post.
		var home := post - Vector2(position.x, position.z)
		if home.length() > 0.35:
			drive(home.normalized() * 0.4, false, delta)
		else:
			stop_locomotion()


func can_talk_to(other: Node3D) -> bool:
	if other == null:
		return false
	var to := Vector2(other.position.x - position.x, other.position.z - position.z)
	return to.length() <= talk_radius
