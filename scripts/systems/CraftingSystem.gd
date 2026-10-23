extends Node
## Crafting, Equipment Upgrade & Cooking Buff System for LANTERNFALL Part 1.

var recipes: Dictionary = {
	"rcp_minyak_suling": {
		"result": "mat_minyak_biji_terang",
		"qty": 2,
		"station": "meja_perajin",
		"ingredients": {"mat_spora_jamur_senja": 2, "mat_kayu_embun": 1},
		"cost": 5
	},
	"rcp_sup_jamur_kelip": {
		"result": "cns_sup_jamur_kelip",
		"qty": 1,
		"station": "tungku_masak",
		"ingredients": {"mat_spora_jamur_senja": 2, "mat_ikan_kabut": 1},
		"cost": 4
	},
	"rcp_tombak_suar": {
		"result": "wpn_tombak_suar_kuningan",
		"qty": 1,
		"station": "tempa_lentera",
		"ingredients": {"mat_besi_karam": 3, "mat_kayu_embun": 2, "mat_spora_jamur_senja": 2},
		"cost": 45
	},
	"rcp_jubah_kabut_tebal": {
		"result": "clk_jubah_tenun_kabut",
		"qty": 1,
		"station": "meja_perajin",
		"ingredients": {"mat_kain_layar_tua": 3, "mat_spora_jamur_senja": 2},
		"cost": 35
	}
}

func can_craft(recipe_id: String) -> bool:
	if not recipes.has(recipe_id):
		return false
	var r: Dictionary = recipes[recipe_id]
	if GameState.koin_embun < int(r["cost"]):
		return false
	var ing: Dictionary = r["ingredients"]
	for item_id in ing.keys():
		if not InventorySystem.has_item(String(item_id), int(ing[item_id])):
			return false
	return InventorySystem.can_fit_item(String(r["result"]), int(r["qty"]))

func craft_recipe(recipe_id: String) -> bool:
	if not can_craft(recipe_id):
		EventBus.toast_notification.emit("Bahan atau Koin Embun belum cukup.", "craft")
		return false
	var r: Dictionary = recipes[recipe_id]
	var ing: Dictionary = r["ingredients"]
	for item_id in ing.keys():
		InventorySystem.remove_item(String(item_id), int(ing[item_id]))
	GameState.add_koin_embun(-int(r["cost"]))
	var res_item: String = String(r["result"])
	var res_qty: int = int(r["qty"])
	# Perajin skill bonus: 25% chance to yield +1 extra consumable
	if GameState.unlocked_skills.get("perajin_2_racikan_jamur", false) and res_item.begins_with("cns_"):
		if randf() < 0.25:
			res_qty += 1
	InventorySystem.add_item(res_item, res_qty)
	AudioBus.play_sfx("quest_chime", 0.98, 1.06)
	EventBus.item_crafted.emit(recipe_id, res_item)
	return true
