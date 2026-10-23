class_name RecipeData
extends Resource
## Data-driven Resource schema for Crafting & Cooking stations.

@export var recipe_id: String = ""
@export var result_item_id: String = ""
@export var result_count: int = 1
@export_enum("meja_perajin", "tungku_masak", "tempa_lentera") var station_type: String = "meja_perajin"
@export var ingredients: Dictionary = {} # item_id: count
@export var craft_cost_embun: int = 0
@export var required_reputation_faction: String = ""
@export var required_reputation_min: int = 0
