class_name NPCController
extends CharacterBody3D
## Living NPC controller: features daily routine schedules (Morning/Dusk/Night waypoints),
## head-turning toward player, reactions to rain/night, and branching dialogue interaction.

@export var npc_id: String = "npc_tetua_damar"
@export var display_name_key: String = "NPC_DAMAR_NAME"
@export var default_dialog_id: String = "dlg_damar_intro"
@export var morning_pos: Vector3 = Vector3(2.0, 0.0, 2.0)
@export var dusk_pos: Vector3 = Vector3(0.0, 0.0, -1.5)
@export var night_shelter_pos: Vector3 = Vector3(-3.0, 0.0, -2.5)
@export var is_merchant: bool = false
@export var merchant_island_id: String = "pulau_embun"

var _target_waypoint: Vector3 = Vector3.ZERO
var _anim_clock: float = 0.0
var _current_weather: String = "cerah_redup"

@onready var sprite_billboard: Sprite3D = $Sprite3D

func _ready() -> void:
	_target_waypoint = morning_pos
	EventBus.time_of_day_changed.connect(_on_time_of_day_changed)
	EventBus.weather_changed.connect(_on_weather_changed)

func _physics_process(delta: float) -> void:
	_anim_clock += delta
	var to_target: Vector3 = _target_waypoint - global_position
	to_target.y = 0.0
	if to_target.length() > 0.35:
		velocity = to_target.normalized() * 1.85
		move_and_slide()
	else:
		velocity = Vector3.ZERO

	_face_nearby_player()
	if sprite_billboard != null:
		var idle_bob: float = sin(_anim_clock * 2.8) * 0.03
		sprite_billboard.scale = Vector3(1.0, 1.0 + idle_bob, 1.0)

func interact_with_player(_player: Node3D) -> void:
	AudioBus.play_sfx("ui_tap", 0.95, 1.05)
	DialogueManager.start_dialogue(npc_id, default_dialog_id)

func _face_nearby_player() -> void:
	if sprite_billboard == null:
		return
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.size() > 0 and players[0] is Node3D:
		var p: Node3D = players[0] as Node3D
		if global_position.distance_to(p.global_position) < 4.5:
			sprite_billboard.flip_h = (p.global_position.x < global_position.x)

func _on_time_of_day_changed(_hour: float, phase_name: String) -> void:
	if _current_weather == "hujan_abu":
		_target_waypoint = night_shelter_pos
		return
	match phase_name:
		"Pagi Redup":
			_target_waypoint = morning_pos
		"Senja Lembayung":
			_target_waypoint = dusk_pos
		"Malam Senyap":
			_target_waypoint = night_shelter_pos

func _on_weather_changed(weather_id: String, _intensity: float) -> void:
	_current_weather = weather_id
	if weather_id in ["hujan_abu", "badai_kabut"]:
		_target_waypoint = night_shelter_pos
