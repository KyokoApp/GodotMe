class_name QuestData
extends Resource
## Data-driven Resource schema for main branching quests, narrative side quests, and hidden secrets.

@export var quest_id: String = ""
@export var chapter_index: int = 0
@export var title_key: String = ""
@export var summary_key: String = ""
@export_enum("utama", "sampingan", "rahasia") var quest_type: String = "utama"
@export var steps: Array[String] = []
@export var branching_choices: Dictionary = {} # choice_id -> description_key
@export var reward_koin_embun: int = 50
@export var reward_pecahan_kelip: int = 0
@export var reward_exp: int = 80
@export var reward_items: Dictionary = {}
@export var reward_faction_id: String = "tetua_rembang"
@export var reward_reputation: int = 15
