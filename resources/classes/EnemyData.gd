class_name EnemyData
extends Resource
## Data-driven Resource schema for all 8 regular enemies + 2 multi-phase Bosses.

@export var enemy_id: String = ""
@export var display_name_key: String = ""
@export var lore_summary_key: String = ""
@export var is_boss: bool = false
@export var max_hp: int = 80
@export var move_speed: float = 3.2
@export var attack_damage: int = 14
@export var attack_range: float = 1.6
@export var detection_range: float = 8.5
@export var telegraph_duration: float = 0.55
@export_enum("patrol_chase", "flee_from_light", "ambush_in_dark", "ranged_spore", "heavy_shield", "boss_phases") var behavior_archetype: String = "patrol_chase"
@export var light_weakness_multiplier: float = 1.35
@export var senyap_shield_requires_lantern: bool = true
@export var exp_reward: int = 25
@export var koin_embun_min: int = 8
@export var koin_embun_max: int = 16
@export var drop_table: Dictionary = {} # item_id: probability (0.0 - 1.0)
@export var sprite_sheet_path: String = "res://assets/sprites/enemies/enemy_atlas.png"
