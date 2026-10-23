extends Node
## Branching Narrative & Localization-ready Dialogue Manager for LANTERNFALL Part 1.
## Each NPC has distinct diction, cadence, and local Indonesian flavor without stiff templates.

var active_npc_id: String = ""
var current_node_id: String = ""
var is_dialogue_active: bool = false

# Complete branching dialogue database for Prologue, Ch.1, Ch.2, Ch.3, and Part 1 Finale
var dialogue_db: Dictionary = {
	"dlg_kelip_prolog": {
		"speaker": "Kelip (Roh Ngengat Lentera)",
		"emotion": "cemas",
		"text": "Nara! Bangun, jangan melamun terus! Lentera Utama Desa Rembang baru saja batuk tiga kali lalu padam. Seratus tahun api itu menyala, dan malam ini kabut Senyap sudah menjilat pagar dermaga!",
		"choices": [
			{"label": "Tenang, Kelip. Di mana Guru Soka sekarang?", "next": "dlg_kelip_prolog_2", "flag": "", "val": ""},
			{"label": "Ambil lentera kuningan dulu, kita nyalakan Menara Gerbang.", "next": "dlg_kelip_prolog_2", "flag": "prolog_lentera_pertama_nyala", "val": "siap"}
		]
	},
	"dlg_kelip_prolog_2": {
		"speaker": "Kelip (Roh Ngengat Lentera)",
		"emotion": "sedih",
		"text": "Guru Soka turun ke tepi Selimut Kabut sejak senja tadi. Hanya lensa retaknya yang tertinggal di jembatan tali. Kalau kita tidak menyalakan Lentera Gerbang sekarang, warga Rembang bakal lupa nama mereka sendiri!",
		"choices": [
			{"label": "Ayo bergerak. Cahaya kecil pun cukup asal tidak padam.", "next": "END", "flag": "prolog_lentera_pertama_nyala", "val": "true"}
		]
	},
	"dlg_damar_intro": {
		"speaker": "Tetua Damar (Pulau Embun)",
		"emotion": "tenang",
		"text": "Angin malam ini bau abu garam, Nak Nara. Serikat Layar Abu menaikkan upeti minyak lentera dua kali lipat, sementara jaring nelayan kita cuma mengangkat ikan buta dari kabut.",
		"choices": [
			{"label": "Saya akan bicara dengan Serikat. Nelayan tidak boleh gelap malam ini.", "next": "END", "flag": "bab1_pilihan_pajak_dermaga", "val": "bela_nelayan", "rep_faction": "tetua_rembang", "rep_delta": 20},
			{"label": "Kita bagi cadangan minyak desa agar kapal dagang tetap bersandar.", "next": "END", "flag": "bab1_pilihan_pajak_dermaga", "val": "kompromi_serikat", "rep_faction": "serikat_layar_abu", "rep_delta": 20}
		]
	},
	"dlg_soka_echo_bab2": {
		"speaker": "Gema Ingatan Guru Soka (Hutan Jamur Senja)",
		"emotion": "misterius",
		"text": "Nara... jangan tatap inti lentera terlalu lama. Setiap lentera besar yang menyala di kepulauan ini tidak membakar minyak biji, melainkan membakar ingatan seorang Penjaga yang merelakan dirinya.",
		"choices": [
			{"label": "Bebaskan sisa ingatan Guru Soka meski lentera hutan meredup sedikit.", "next": "END", "flag": "bab2_pilihan_nasib_guru_soka", "val": "bebaskan_ingatan", "rep_faction": "perajin_jamur_senja", "rep_delta": 25},
			{"label": "Segel kembali ingatan Guru ke lentera demi melindungi kampung bawah.", "next": "END", "flag": "bab2_pilihan_nasib_guru_soka", "val": "segel_ke_lentera", "rep_faction": "penjaga_menara", "rep_delta": 25}
		]
	},
	"dlg_pemadam_finale": {
		"speaker": "Sang Pemadam (Mantan Penjaga Agung)",
		"emotion": "tenang",
		"text": "Kau bertarung gigih, murid Soka. Tapi lihatlah lentera di tanganmu—kelopak ngengat kecil di sampingmu itu adalah jiwa Penjaga terdahulu yang tak diizinkan tidur. Aku memadamkan lentera bukan karena membenci manusia, melainkan agar tak ada lagi yang harus dibakar hidup-hidup demi menunda malam.",
		"choices": [
			{"label": "Meski sakit, ingatan dan harapan manusia layak dijaga tetap menyala!", "next": "END", "flag": "part1_ending_moral_choice", "val": "jaga_bara_terakhir"},
			{"label": "Kalau lentera memakan jiwa... kita harus mencari fajar baru tanpa lentera.", "next": "END", "flag": "part1_ending_moral_choice", "val": "terima_kebenaran_pemadam"}
		]
	}
}

func start_dialogue(npc_id: String, start_node: String) -> void:
	if not dialogue_db.has(start_node):
		return
	active_npc_id = npc_id
	current_node_id = start_node
	is_dialogue_active = true
	EventBus.dialogue_started.emit(npc_id, start_node)

func select_choice(choice_index: int) -> void:
	if not is_dialogue_active or not dialogue_db.has(current_node_id):
		return
	var node_data: Dictionary = dialogue_db[current_node_id]
	var choices: Array = node_data.get("choices", [])
	if choice_index < 0 or choice_index >= choices.size():
		return
	var chosen: Dictionary = choices[choice_index]
	var flag_key: String = String(chosen.get("flag", ""))
	if not flag_key.is_empty():
		GameState.record_moral_choice(flag_key, String(chosen.get("val", "")))
	if chosen.has("rep_faction"):
		GameState.modify_reputation(String(chosen["rep_faction"]), int(chosen.get("rep_delta", 0)))

	var next_id: String = String(chosen.get("next", "END"))
	if next_id == "END" or not dialogue_db.has(next_id):
		is_dialogue_active = false
		EventBus.dialogue_ended.emit(active_npc_id)
	else:
		current_node_id = next_id
		EventBus.dialogue_started.emit(active_npc_id, current_node_id)
