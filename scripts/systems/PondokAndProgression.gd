class_name PondokAndProgression
extends Node
## Manages Player Homestead ("Pondok Nara" customization, storage, personal lantern)
## and the 3-Branch Skill Tree (Penjaga, Pelaut, Perajin).

const UPGRADE_COSTS: Dictionary = {
	"lentera_halaman": {"koin": 90, "item": "mat_minyak_biji_terang", "qty": 4},
	"rak_gudang": {"koin": 80, "item": "mat_kayu_embun", "qty": 5},
	"tungku_masak": {"koin": 110, "item": "mat_besi_karam", "qty": 3},
	"meja_tempa": {"koin": 150, "item": "mat_besi_karam", "qty": 5}
}

func upgrade_pondok_facility(facility_id: String) -> bool:
	if not UPGRADE_COSTS.has(facility_id):
		return false
	var req: Dictionary = UPGRADE_COSTS[facility_id]
	var cur_tier: int = int(GameState.pondok_upgrades.get(facility_id, 0))
	if cur_tier >= 3:
		return false
	var koin_needed: int = int(req["koin"]) * (cur_tier + 1)
	var item_id: String = String(req["item"])
	var item_qty: int = int(req["qty"])
	if GameState.koin_embun < koin_needed or not InventorySystem.has_item(item_id, item_qty):
		return false
	GameState.add_koin_embun(-koin_needed)
	InventorySystem.remove_item(item_id, item_qty)
	GameState.pondok_upgrades[facility_id] = cur_tier + 1
	EventBus.homestead_upgraded.emit(facility_id, cur_tier + 1)
	return true

func unlock_skill_node(skill_id: String) -> bool:
	if not GameState.unlocked_skills.has(skill_id):
		return false
	if bool(GameState.unlocked_skills[skill_id]) or GameState.skill_points <= 0:
		return false
	GameState.skill_points -= 1
	GameState.unlocked_skills[skill_id] = true
	EventBus.player_level_changed.emit(GameState.level, GameState.skill_points)
	return true
