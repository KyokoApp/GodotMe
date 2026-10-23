class_name ItemData
extends Resource
## Data-driven Resource schema for all items, weapons, cloaks, lanterns, materials, and cooked meals.

@export var item_id: String = ""
@export var display_name_key: String = ""
@export var description_key: String = ""
@export_enum("material", "consumable", "weapon", "cloak", "lantern", "key_item") var category: String = "material"
@export_enum("umum", "jarang", "langka", "warisan") var rarity: String = "umum"
@export var max_stack: int = 20
@export var unit_weight: float = 0.5
@export var base_price_embun: int = 10
@export var icon_path: String = "res://assets/sprites/ui/icon_lantern.png"

# Combat / Restoration / Buff parameters
@export var attack_bonus: int = 0
@export var defense_bonus: int = 0
@export var lantern_radius_bonus: float = 0.0
@export var heal_hp: int = 0
@export var restore_oil: float = 0.0
@export var stamina_regen_buff: float = 0.0
@export var buff_duration_sec: float = 0.0
