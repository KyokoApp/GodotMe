extends Node
## Detailed & Balanced Dynamic Archipelago Economy (Part 1).
## Formula:
##   FinalBuyPrice  = round(BasePrice * IslandSupplyMod * WeatherEventMod * FactionRepDiscount * MarginBuy)
##   FinalSellPrice = round(BasePrice * IslandSupplyMod * DiminishingReturnMod * MarginSell)
## Includes diminishing returns when overselling identical items, periodic restock, and harbor taxes.

const BUY_MARGIN: float = 1.15
const SELL_MARGIN: float = 0.65

# Island regional supply-demand modifiers per item category/id
var island_modifiers: Dictionary = {
	"pulau_embun": {
		"mat_ikan_kabut": 0.80,       # Abundant in fishing village -> cheaper
		"mat_minyak_biji_terang": 0.90,
		"mat_spora_jamur_senja": 1.30,# Imported from Mushroom Forest -> pricier
		"mat_besi_karam": 1.25
	},
	"hutan_jamur": {
		"mat_ikan_kabut": 1.25,
		"mat_spora_jamur_senja": 0.75,# Local harvest -> cheaper
		"mat_kayu_embun": 0.85,
		"mat_besi_karam": 1.35
	},
	"pelabuhan_karam": {
		"mat_ikan_kabut": 0.95,
		"mat_spora_jamur_senja": 1.15,
		"mat_besi_karam": 0.78,       # Salvaged from shipwrecks -> cheaper
		"mat_minyak_biji_terang": 1.20
	}
}

# Tracks recent player sales per item_id to apply anti-exploit diminishing returns (recovers over time)
var recent_sales_volume: Dictionary = {}
var merchant_stock: Dictionary = {
	"pulau_embun": {"mat_minyak_biji_terang": 8, "mat_ikan_kabut": 12, "mat_kayu_embun": 10, "cns_teh_hangat_rembang": 5},
	"hutan_jamur": {"mat_spora_jamur_senja": 14, "mat_minyak_biji_terang": 6, "cns_sup_jamur_kelip": 4},
	"pelabuhan_karam": {"mat_besi_karam": 10, "mat_minyak_biji_terang": 10, "mat_kain_layar_tua": 8}
}

var _restock_clock: float = 0.0

func _process(delta: float) -> void:
	_restock_clock += delta
	if _restock_clock >= 120.0:
		_restock_clock = 0.0
		_decay_oversold_items_and_restock()

func calculate_buy_price(base_price: int, item_id: String, island_id: String, faction_id: String) -> int:
	var island_table: Dictionary = island_modifiers.get(island_id, {})
	var supply_mod: float = float(island_table.get(item_id, 1.0))
	var rep: int = int(GameState.faction_reputation.get(faction_id, 0))
	# Up to 20% discount at 100 reputation, or 15% surcharge if hostile
	var rep_mod: float = clampf(1.0 - (float(rep) * 0.002), 0.80, 1.15)
	# Quest decision impact (e.g., defending fishermen in Ch.1 lowers harbor tax)
	var event_mod: float = 0.92 if String(GameState.story_flags.get("bab1_pilihan_pajak_dermaga", "")) == "bela_nelayan" else 1.0
	return maxi(1, int(round(float(base_price) * supply_mod * rep_mod * event_mod * BUY_MARGIN)))

func calculate_sell_price(base_price: int, item_id: String, island_id: String) -> int:
	var island_table: Dictionary = island_modifiers.get(island_id, {})
	var demand_mod: float = float(island_table.get(item_id, 1.0))
	var sold_qty: int = int(recent_sales_volume.get(item_id, 0))
	# Diminishing return: each unit sold reduces price by 3.5% down to 40% floor
	var diminishing_mod: float = maxf(0.40, 1.0 - float(sold_qty) * 0.035)
	return maxi(1, int(round(float(base_price) * demand_mod * diminishing_mod * SELL_MARGIN)))

func buy_from_merchant(island_id: String, faction_id: String, item_id: String, base_price: int, qty: int = 1) -> bool:
	var stock_table: Dictionary = merchant_stock.get(island_id, {})
	var available: int = int(stock_table.get(item_id, 0))
	if available < qty:
		EventBus.toast_notification.emit("Stok pedagang habis, tunggu kiriman perahu berikutnya.", "economy")
		return false

	var unit_price: int = calculate_buy_price(base_price, item_id, island_id, faction_id)
	var total_cost: int = unit_price * qty
	if GameState.koin_embun < total_cost:
		EventBus.toast_notification.emit("Koin Embun tidak cukup!", "economy")
		return false

	if not InventorySystem.can_fit_item(item_id, qty):
		EventBus.toast_notification.emit("Tas Nara penuh atau melebihi batas beban!", "economy")
		return false

	GameState.add_koin_embun(-total_cost)
	stock_table[item_id] = available - qty
	merchant_stock[island_id] = stock_table
	InventorySystem.add_item(item_id, qty)
	AudioBus.play_sfx("ui_tap", 1.0, 1.1)
	return true

func sell_to_merchant(island_id: String, item_id: String, base_price: int, qty: int = 1) -> bool:
	if not InventorySystem.has_item(item_id, qty):
		return false
	var unit_sell: int = calculate_sell_price(base_price, item_id, island_id)
	InventorySystem.remove_item(item_id, qty)
	GameState.add_koin_embun(unit_sell * qty)
	recent_sales_volume[item_id] = int(recent_sales_volume.get(item_id, 0)) + qty
	AudioBus.play_sfx("ui_tap", 0.9, 1.0)
	return true

func _decay_oversold_items_and_restock() -> void:
	for k in recent_sales_volume.keys():
		recent_sales_volume[k] = maxi(0, int(recent_sales_volume[k]) - 3)
	for isl in merchant_stock.keys():
		var st: Dictionary = merchant_stock[isl]
		for item_k in st.keys():
			st[item_k] = mini(15, int(st[item_k]) + 2)

func serialize_economy() -> Dictionary:
	return {
		"recent_sales_volume": recent_sales_volume.duplicate(true),
		"merchant_stock": merchant_stock.duplicate(true)
	}

func deserialize_economy(data: Dictionary) -> void:
	if data.has("recent_sales_volume"):
		recent_sales_volume = (data["recent_sales_volume"] as Dictionary).duplicate(true)
	if data.has("merchant_stock"):
		merchant_stock = (data["merchant_stock"] as Dictionary).duplicate(true)
