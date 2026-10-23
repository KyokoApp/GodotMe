class_name BoatController
extends CharacterBody3D
## Controllable small sailboat ("Perahu Layar Kabut") for inter-island traversal across the Sea of Fog.
## Influenced by wind direction, sea weather waves, and Pelaut skill branch upgrades.

@export var base_sail_speed: float = 8.5
var is_occupied: bool = false
var _wave_clock: float = 0.0

func _physics_process(delta: float) -> void:
	_wave_clock += delta
	# Gentle rocking on the fog sea
	rotation.z = sin(_wave_clock * 1.8) * 0.04
	rotation.x = cos(_wave_clock * 1.4) * 0.03

	if not is_occupied:
		return

	var input_vec: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var helm_bonus: float = 1.25 if GameState.unlocked_skills.get("pelaut_2_kemudi_kabut", false) else 1.0
	var target_vel: Vector3 = Vector3(input_vec.x, 0.0, input_vec.y) * base_sail_speed * helm_bonus
	velocity = velocity.move_toward(target_vel, 12.0 * delta)
	move_and_slide()

func interact_with_player(player: Node3D) -> void:
	is_occupied = not is_occupied
	EventBus.boat_boarding_toggled.emit(is_occupied)
	if is_occupied:
		EventBus.toast_notification.emit("Berlayar di atas Selimut Kabut", "boat")
	else:
		player.global_position = global_position + Vector3(1.8, 0.5, 0.0)
