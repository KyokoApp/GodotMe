extends Node
## Touch-friendly Grid Inventory with stack limits, categories, weight limit, and upgradable bag tiers.

var max_slots: int = 16
var max_weight_kg: float = 25.0
var bag_tier: int = 1

# Array of Dictionaries: {"item_id": String, "qty": int, "weight": float}
var slots: Array[Dictionary] = []

var _item_catalog: Dictionary = {
	"mat_minyak_biji_terang": {"name": "Minyak Biji Terang", "cat": "consumable", "weight": 0.4, "stack": 20, "price": 14, "oil": 35.0, "hp": 0},
	"mat_ikan_kabut": {"name": "Ikan Kabut Asap", "cat": "material", "weight": 0.5, "stack": 20, "price": 12, "oil": 0.0, "hp": 15},
	"mat_kayu_embun": {"name": "Kayu Embun Liat", "cat": "material", "weight": 0.8, "stack": 20, "price": 10, "oil": 0.0, "hp": 0},
	"mat_spora_jamur_senja": {"name": "Spora Jamur Senja", "cat": "material", "weight": 0.3, "stack": 30, "price": 18, "oil": 15.0, "hp": 0},
	"mat_besi_karam": {"name": "Besi Kapal Karam", "cat": "material", "weight": 1.2, "stack": 15, "price": 24, "oil": 0.0, "hp": 0},
	"mat_kain_layar_tua": {"name": "Kain Layar Tua", "cat": "material", "weight": 0.6, "stack": 15, "price": 16, "oil": 0.0, "hp": 0},
	"cns_teh_hangat_rembang": {"name": "Teh Hangat Rembang", "cat": "consumable", "weight": 0.4, "stack": 10, "price": 22, "oil": 10.0, "hp": 45},
	"cns_sup_jamur_kelip": {"name": "Sup Jamur Kelip", "cat": "consumable", "weight": 0.5, "stack": 10, "price": 34, "oil": 25.0, "hp": 65},
	"wpn_dayung_retak": {"name": "Dayung Penjaga Retak", "cat": "weapon", "weight": 2.0, "stack": 1, "price": 45, "oil": 0.0, "hp": 0},
	"wpn_tombak_suar_kuningan": {"name": "Tombak Suar Kuningan", "cat": "weapon", "weight": 2.4, "stack": 1, "price": 140, "oil": 0.0, "hp": 0},
	"clk_jubah_tenun_kabut": {"name": "Jubah Tenun Kabut", "cat": "cloak", "weight": 1.5, "stack": 1, "price": 110, "oil": 0.0, "hp": 0},
	"lnt_lentera_kuningan_tua": {"name": "Lentera Kuningan Rembang", "cat": "lantern", "weight": 1.2, "stack": 1, "price": 90, "oil": 0.0, "hp": 0},
	"key_lensa_guru_soka": {"name": "Lensa Retak Guru Soka", "cat": "key_item", "weight": 0.2, "stack": 1, "price": 0, "oil": 0.0, "hp": 0}
}

func _ready() -> void:
	# Starter survival kit for Prologue
	add_item("mat_minyak_biji_terang", 3)
	add_item("cns_teh_hangat_rembang", 2)
	add_item("mat_kayu_embun", 2)

func get_current_weight() -> float:
	var total: float = 0.0
	for s in slots:
		var meta: Dictionary = _item_catalog.get(String(s["item_id"]), {"weight": 0.5})
		total += float(meta["weight"]) * float(int(s["qty"]))
	return total

func can_fit_item(item_id: String, qty: int) -> bool:
	var meta: Dictionary = _item_catalog.get(item_id, {"weight": 0.5, "stack": 20})
	if get_current_weight() + float(meta["weight"]) * float(qty) > max_weight_kg:
		return false
	for s in slots:
		if String(s["item_id"]) == item_id and int(s["qty"]) + qty <= int(meta["stack"]):
			return true
	return slots.size() < max_slots

func add_item(item_id: String, qty: int = 1) -> bool:
	if not can_fit_item(item_id, qty):
		return false
	var meta: Dictionary = _item_catalog.get(item_id, {"weight": 0.5, "stack": 20})
	var max_st: int = int(meta["stack"])
	for s in slots:
		if String(s["item_id"]) == item_id and int(s["qty"]) < max_st:
			var space: int = max_st - int(s["qty"])
			var add_now: int = mini(space, qty)
			s["qty"] = int(s["qty"]) + add_now
			qty -= add_now
			if qty <= 0:
				EventBus.item_acquired.emit(item_id, add_now)
				EventBus.inventory_updated.emit()
				return true
	if qty > 0 and slots.size() < max_slots:
		slots.append({"item_id": item_id, "qty": qty})
		EventBus.item_acquired.emit(item_id, qty)
		EventBus.inventory_updated.emit()
		return true
	return false

func has_item(item_id: String, min_qty: int = 1) -> bool:
	var total: int = 0
	for s in slots:
		if String(s["item_id"]) == item_id:
			total += int(s["qty"])
	return total >= min_qty

func remove_item(item_id: String, qty: int = 1) -> bool:
	if not has_item(item_id, qty):
		return false
	var remaining: int = qty
	for i in range(slots.size() - 1, -1, -1):
		if String(slots[i]["item_id"]) == item_id:
			var cur: int = int(slots[i]["qty"])
			if cur <= remaining:
				remaining -= cur
				slots.remove_at(i)
			else:
				slots[i]["qty"] = cur - remaining
				remaining = 0
			if remaining <= 0:
				break
	EventBus.inventory_updated.emit()
	return true

func use_consumable(item_id: String) -> bool:
	if not has_item(item_id, 1):
		return false
	var meta: Dictionary = _item_catalog.get(item_id, {})
	var oil_gain: float = float(meta.get("oil", 0.0))
	var hp_gain: int = int(meta.get("hp", 0))
	if oil_gain <= 0.0 and hp_gain <= 0:
		return false
	remove_item(item_id, 1)
	if oil_gain > 0.0:
		GameState.refill_lantern_oil(oil_gain)
	if hp_gain > 0:
		GameState.current_hp = mini(GameState.max_hp, GameState.current_hp + hp_gain)
		EventBus.player_hp_changed.emit(GameState.current_hp, GameState.max_hp)
	AudioBus.play_sfx("lantern_ignite", 1.05, 1.15)
	return true

func upgrade_bag_capacity() -> bool:
	var cost: int = bag_tier * 85
	if bag_tier >= 3 or GameState.koin_embun < cost or not has_item("mat_kain_layar_tua", 2):
		return false
	GameState.add_koin_embun(-cost)
	remove_item("mat_kain_layar_tua", 2)
	bag_tier += 1
	max_slots += 6
	max_weight_kg += 10.0
	EventBus.inventory_updated.emit()
	return true

func serialize_inventory() -> Dictionary:
	return {
		"bag_tier": bag_tier,
		"max_slots": max_slots,
		"max_weight_kg": max_weight_kg,
		"slots": slots.duplicate(true)
	}

func deserialize_inventory(data: Dictionary) -> void:
	bag_tier = int(data.get("bag_tier", 1))
	max_slots = int(data.get("max_slots", 16))
	max_weight_kg = float(data.get("max_weight_kg", 25.0))
	slots.clear()
	var raw_slots: Array = data.get("slots", [])
	for entry in raw_slots:
		if typeof(entry) == TYPE_DICTIONARY:
			slots.append((entry as Dictionary).duplicate())
	EventBus.inventory_updated.emit()
