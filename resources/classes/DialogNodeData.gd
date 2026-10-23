class_name DialogNodeData
extends Resource
## Data-driven Resource schema for multi-branch NPC dialogue with portrait emotion and moral flag triggers.

@export var dialog_id: String = ""
@export var speaker_name_key: String = ""
@export_enum("tenang", "cemas", "marah", "sedih", "hangat", "misterius") var portrait_emotion: String = "tenang"
@export var text_key: String = ""
@export var choices: Array[Dictionary] = []
# Each choice dict: {"label_key": String, "next_id": String, "set_flag": String, "flag_val": String, "rep_faction": String, "rep_delta": int, "start_quest": String}
