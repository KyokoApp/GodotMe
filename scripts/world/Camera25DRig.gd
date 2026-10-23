class_name Camera25DRig
extends Camera3D
## 2.5D Low-FOV (~38 deg tilted angle) Camera Controller with smooth follow damping and screen shake.

@export var target_group: String = "player"
@export var camera_offset: Vector3 = Vector3(0.0, 8.8, 9.6)
@export var follow_damping: float = 6.5

var _shake_intensity: float = 0.0
var _shake_timer: float = 0.0

func _ready() -> void:
	fov = 32.0 # Low FOV for classic 2.5D diorama perspective
	rotation_degrees = Vector3(-40.0, 0.0, 0.0)
	EventBus.screen_shake_requested.connect(_on_screen_shake_requested)

func _physics_process(delta: float) -> void:
	var targets: Array[Node] = get_tree().get_nodes_in_group(target_group)
	if targets.size() == 0 or not (targets[0] is Node3D):
		return
	var target: Node3D = targets[0] as Node3D
	var desired_pos: Vector3 = target.global_position + camera_offset
	global_position = global_position.lerp(desired_pos, clampf(follow_damping * delta, 0.0, 1.0))

	if _shake_timer > 0.0:
		_shake_timer -= delta
		h_offset = randf_range(-_shake_intensity, _shake_intensity)
		v_offset = randf_range(-_shake_intensity, _shake_intensity)
	else:
		h_offset = 0.0
		v_offset = 0.0

func _on_screen_shake_requested(intensity: float, duration: float) -> void:
	_shake_intensity = intensity
	_shake_timer = maxf(_shake_timer, duration)
