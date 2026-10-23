extends Node
## Central runtime state singleton for LANTERNFALL Part 1.
## Holds player stats, currencies, unlocked beacons, story flags, and skill tree allocations.

const CURRENT_SAVE_VERSION: int = 3

var player_name: String = "Nara"
var current_chapter: int = 0 # 0=Prolog, 1=Pulau Embun, 2=Hutan Jamur Senja, 3=Pelabuhan Karam, 4=Finale Part 1
var current_chunk_id: String = "chunk_0_0_rembang"

# Core combat & lantern metrics
var level: int = 1
var exp_points: int = 0
var exp_to_next: int = 100
var skill_points: int = 1

var max_hp: int = 120
var current_hp: int = 120
var max_stamina: float = 100.0
var current_stamina: float = 100.0
var max_lantern_oil: float = 100.0
var current_lantern_oil: float = 85.0
var lantern_lit: bool = true

# Equipment tiers & durability
var equipped_weapon_id: String = "wpn_dayung_retak"
var equipped_cloak_id: String = "clk_jubah_tenun_kabut"
var equipped_lantern_id: String = "lnt_lentera_kuningan_tua"
var weapon_durability: float = 100.0

# Currencies (No IAP, No Ads)
var koin_embun: int = 65
var pecahan_kelip: int = 1
var faction_reputation: Dictionary = {
	"tetua_rembang": 15,
	"serikat_layar_abu": 0,
	"perajin_jamur_senja": 0,
	"penjaga_menara": 10
}

# 3-Branch Skill Tree: Penjaga (Guardian), Pelaut (Mariner), Perajin (Artisan)
var unlocked_skills: Dictionary = {
	"penjaga_1_sinar_fokus": true,
	"penjaga_2_perisai_senja": false,
	"penjaga_3_ledakan_lentera": false,
	"pelaut_1_langkah_angin": false,
	"pelaut_2_kemudi_kabut": false,
	"pelaut_3_tombak_arus": false,
	"perajin_1_minyak_hemat": false,
	"perajin_2_racikan_jamur": false,
	"perajin_3_tempaan_kelip": false
}

# World Restoration & Beacons
var lit_beacons: Array[String] = ["beacon_rembang_gate"]
var chunk_restoration: Dictionary = {
	"chunk_0_0_rembang": 0.45,
	"chunk_1_0_pulau_embun": 0.20,
	"chunk_0_1_hutan_jamur": 0.10,
	"chunk_1_1_pelabuhan_karam": 0.15,
	"chunk_2_1_menara_pemadam": 0.05
}

# Homestead ("Pondok Nara") customization & storage
var pondok_upgrades: Dictionary = {
	"lentera_halaman": 1,
	"rak_gudang": 1,
	"tungku_masak": 1,
	"meja_tempa": 0
}
var pondok_storage: Dictionary = {}

# Narrative & Part 2 carryover moral flags
var story_flags: Dictionary = {
	"prolog_lentera_pertama_nyala": false,
	"bab1_pilihan_pajak_dermaga": "",     # "bela_nelayan" or "kompromi_serikat"
	"bab2_pilihan_nasib_guru_soka": "",   # "bebaskan_ingatan" or "segel_ke_lentera"
	"bab3_pilihan_armada_karam": "",      # "bakar_kapal_gelap" or "selamatkan_awak"
	"part1_ending_moral_choice": ""       # "jaga_bara_terakhir" or "terima_kebenaran_pemadam"
}

# Bestiary & Lore Journal
var bestiary_kills: Dictionary = {}
var discovered_lore: Array[String] = ["lore_retakan_matahari"]

# User Settings
var settings: Dictionary = {
	"graphics_preset": 1, # 0=Low, 1=Medium, 2=High
	"battery_saver_30fps": false,
	"ui_scale": 1.0,
	"language": "id",
	"master_vol": 0.9,
	"bgm_vol": 0.75,
	"sfx_vol": 0.9,
	"colorblind_mode": 0,
	"joystick_offset_x": 140.0,
	"joystick_offset_y": -140.0,
	"action_buttons_offset_x": -180.0,
	"action_buttons_offset_y": -140.0
}

func add_koin_embun(amount: int) -> void:
	koin_embun = max(0, koin_embun + amount)
	EventBus.currency_changed.emit(koin_embun, pecahan_kelip)

func add_pecahan_kelip(amount: int) -> void:
	pecahan_kelip = max(0, pecahan_kelip + amount)
	EventBus.currency_changed.emit(koin_embun, pecahan_kelip)

func modify_reputation(faction_id: String, delta: int) -> void:
	var current: int = int(faction_reputation.get(faction_id, 0))
	faction_reputation[faction_id] = clampi(current + delta, -100, 100)
	EventBus.reputation_changed.emit(faction_id, int(faction_reputation[faction_id]))

func consume_lantern_oil(amount: float) -> void:
	var efficiency: float = 0.80 if unlocked_skills.get("perajin_1_minyak_hemat", false) else 1.0
	current_lantern_oil = clampf(current_lantern_oil - (amount * efficiency), 0.0, max_lantern_oil)
	if current_lantern_oil <= 0.0:
		lantern_lit = false
	EventBus.lantern_oil_changed.emit(current_lantern_oil, max_lantern_oil)

func refill_lantern_oil(amount: float) -> void:
	current_lantern_oil = clampf(current_lantern_oil + amount, 0.0, max_lantern_oil)
	if current_lantern_oil > 0.0:
		lantern_lit = true
	EventBus.lantern_oil_changed.emit(current_lantern_oil, max_lantern_oil)

func add_exp(amount: int) -> void:
	exp_points += amount
	while exp_points >= exp_to_next:
		exp_points -= exp_to_next
		level += 1
		skill_points += 1
		max_hp += 15
		current_hp = max_hp
		exp_to_next = int(float(exp_to_next) * 1.35)
		EventBus.player_level_changed.emit(level, skill_points)
		EventBus.player_hp_changed.emit(current_hp, max_hp)

func light_beacon(beacon_id: String, chunk_id: String) -> void:
	if not lit_beacons.has(beacon_id):
		lit_beacons.append(beacon_id)
	var current_ratio: float = float(chunk_restoration.get(chunk_id, 0.1))
	var updated_ratio: float = clampf(current_ratio + 0.45, 0.0, 1.0)
	chunk_restoration[chunk_id] = updated_ratio
	EventBus.beacon_lit.emit(beacon_id, chunk_id, updated_ratio)

func record_moral_choice(choice_key: String, option_id: String) -> void:
	story_flags[choice_key] = option_id
	EventBus.moral_choice_recorded.emit(choice_key, option_id)

func apply_runtime_settings() -> void:
	Engine.max_fps = 30 if bool(settings.get("battery_saver_30fps", false)) else 60
	TranslationServer.set_locale(String(settings.get("language", "id")))
	EventBus.graphics_preset_changed.emit(int(settings.get("graphics_preset", 1)))
	EventBus.colorblind_mode_changed.emit(int(settings.get("colorblind_mode", 0)))
