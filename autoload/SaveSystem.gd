extends Node
## JSON Save System supporting 3 manual/auto slots, automatic save on chunk transition,
## and schema version migration (v1 -> v2 -> v3).

const SAVE_DIR: String = "user://saves/"
const MAX_SLOTS: int = 3

var active_slot: int = 1

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	EventBus.chunk_entered.connect(_on_chunk_entered_autosave)

func get_slot_path(slot: int) -> String:
	var clamped_slot: int = clampi(slot, 1, MAX_SLOTS)
	return SAVE_DIR + "lanternfall_slot_%d.json" % clamped_slot

func save_game(slot: int = -1) -> bool:
	var target_slot: int = active_slot if slot < 1 else clampi(slot, 1, MAX_SLOTS)
	active_slot = target_slot

	var payload: Dictionary = {
		"save_version": GameState.CURRENT_SAVE_VERSION,
		"timestamp_unix": Time.get_unix_time_from_system(),
		"player_name": GameState.player_name,
		"current_chapter": GameState.current_chapter,
		"current_chunk_id": GameState.current_chunk_id,
		"level": GameState.level,
		"exp_points": GameState.exp_points,
		"exp_to_next": GameState.exp_to_next,
		"skill_points": GameState.skill_points,
		"max_hp": GameState.max_hp,
		"current_hp": GameState.current_hp,
		"max_lantern_oil": GameState.max_lantern_oil,
		"current_lantern_oil": GameState.current_lantern_oil,
		"equipped_weapon_id": GameState.equipped_weapon_id,
		"equipped_cloak_id": GameState.equipped_cloak_id,
		"equipped_lantern_id": GameState.equipped_lantern_id,
		"weapon_durability": GameState.weapon_durability,
		"koin_embun": GameState.koin_embun,
		"pecahan_kelip": GameState.pecahan_kelip,
		"faction_reputation": GameState.faction_reputation.duplicate(true),
		"unlocked_skills": GameState.unlocked_skills.duplicate(true),
		"lit_beacons": GameState.lit_beacons.duplicate(),
		"chunk_restoration": GameState.chunk_restoration.duplicate(true),
		"pondok_upgrades": GameState.pondok_upgrades.duplicate(true),
		"pondok_storage": GameState.pondok_storage.duplicate(true),
		"story_flags": GameState.story_flags.duplicate(true),
		"bestiary_kills": GameState.bestiary_kills.duplicate(true),
		"discovered_lore": GameState.discovered_lore.duplicate(),
		"inventory": InventorySystem.serialize_inventory(),
		"economy": EconomyManager.serialize_economy(),
		"settings": GameState.settings.duplicate(true)
	}

	var file: FileAccess = FileAccess.open(get_slot_path(target_slot), FileAccess.WRITE)
	if file == null:
		push_warning("SaveSystem: Gagal membuka slot %d untuk menulis." % target_slot)
		return false

	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	EventBus.toast_notification.emit("Lentera Ingatan tersimpan (Slot %d)" % target_slot, "save")
	return true

func load_game(slot: int) -> bool:
	var target_slot: int = clampi(slot, 1, MAX_SLOTS)
	var path: String = get_slot_path(target_slot)
	if not FileAccess.file_exists(path):
		return false

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var raw_text: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(raw_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SaveSystem: File save korup pada slot %d" % target_slot)
		return false

	var data: Dictionary = migrate_save_data(parsed as Dictionary)
	active_slot = target_slot
	_apply_loaded_dictionary(data)
	return true

func migrate_save_data(data: Dictionary) -> Dictionary:
	var ver: int = int(data.get("save_version", 1))
	# Migrate v1 -> v2: add pondok_upgrades and faction_reputation
	if ver < 2:
		if not data.has("pondok_upgrades"):
			data["pondok_upgrades"] = {"lentera_halaman": 1, "rak_gudang": 1, "tungku_masak": 1, "meja_tempa": 0}
		if not data.has("faction_reputation"):
			data["faction_reputation"] = {"tetua_rembang": 10, "serikat_layar_abu": 0, "perajin_jamur_senja": 0, "penjaga_menara": 10}
		ver = 2
	# Migrate v2 -> v3: add Part 2 moral choice flag & weapon durability
	if ver < 3:
		if not data.has("weapon_durability"):
			data["weapon_durability"] = 100.0
		var flags: Dictionary = data.get("story_flags", {})
		if not flags.has("part1_ending_moral_choice"):
			flags["part1_ending_moral_choice"] = ""
		data["story_flags"] = flags
		ver = 3
	data["save_version"] = ver
	return data

func _apply_loaded_dictionary(data: Dictionary) -> void:
	GameState.player_name = String(data.get("player_name", "Nara"))
	GameState.current_chapter = int(data.get("current_chapter", 0))
	GameState.current_chunk_id = String(data.get("current_chunk_id", "chunk_0_0_rembang"))
	GameState.level = int(data.get("level", 1))
	GameState.exp_points = int(data.get("exp_points", 0))
	GameState.exp_to_next = int(data.get("exp_to_next", 100))
	GameState.skill_points = int(data.get("skill_points", 0))
	GameState.max_hp = int(data.get("max_hp", 120))
	GameState.current_hp = int(data.get("current_hp", 120))
	GameState.max_lantern_oil = float(data.get("max_lantern_oil", 100.0))
	GameState.current_lantern_oil = float(data.get("current_lantern_oil", 85.0))
	GameState.equipped_weapon_id = String(data.get("equipped_weapon_id", "wpn_dayung_retak"))
	GameState.equipped_cloak_id = String(data.get("equipped_cloak_id", "clk_jubah_tenun_kabut"))
	GameState.equipped_lantern_id = String(data.get("equipped_lantern_id", "lnt_lentera_kuningan_tua"))
	GameState.weapon_durability = float(data.get("weapon_durability", 100.0))
	GameState.koin_embun = int(data.get("koin_embun", 65))
	GameState.pecahan_kelip = int(data.get("pecahan_kelip", 1))

	if data.has("faction_reputation"):
		GameState.faction_reputation = (data["faction_reputation"] as Dictionary).duplicate(true)
	if data.has("unlocked_skills"):
		GameState.unlocked_skills = (data["unlocked_skills"] as Dictionary).duplicate(true)
	if data.has("chunk_restoration"):
		GameState.chunk_restoration = (data["chunk_restoration"] as Dictionary).duplicate(true)
	if data.has("pondok_upgrades"):
		GameState.pondok_upgrades = (data["pondok_upgrades"] as Dictionary).duplicate(true)
	if data.has("story_flags"):
		GameState.story_flags = (data["story_flags"] as Dictionary).duplicate(true)
	if data.has("settings"):
		GameState.settings = (data["settings"] as Dictionary).duplicate(true)
		GameState.apply_runtime_settings()
	if data.has("inventory"):
		InventorySystem.deserialize_inventory(data["inventory"] as Dictionary)
	if data.has("economy"):
		EconomyManager.deserialize_economy(data["economy"] as Dictionary)

func _on_chunk_entered_autosave(_chunk_id: String, _region_name: String) -> void:
	save_game(active_slot)
