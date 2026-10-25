extends Node
## Headless gate for the UI kit, the settings file and the one menu.
##
##   godot --headless --path game res://game/tests/UiTest.tscn
##
## What a screenshot cannot prove: that the settings actually survive a restart,
## that a corrupt settings file does not take the boot down, that every icon is
## really 24x24 and came out of the pack, and that the pause sheet's buttons are
## wired to something. All of that is asserted here.

const KIT := preload("res://game/ui/UiKit.gd")
const ATLAS_JSON := "res://game/assets/ui/atlas_ui.json"
const SETTINGS := preload("res://game/ui/Settings.gd")
const MAIN_SCENE := "res://game/Main.tscn"

const SCRATCH := "user://uitest"

var failures := 0
var checks := 0
var _main: Control


func _ready() -> void:
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(SCRATCH)
	OS.set_environment("RT_SETTINGS_DIR", SCRATCH)
	_clean()
	_test_icons()
	_test_kit_assets()
	_test_settings()
	await _test_menu()
	print("[UI] %d pemeriksaan, %d gagal" % [checks, failures])
	OS.set_environment("RT_SETTINGS_DIR", "")
	_clean()
	get_tree().quit(0 if failures == 0 else 1)


func _check(cond: bool, label: String, extra: String = "") -> void:
	checks += 1
	if cond:
		print("[UI] PASS %s" % label)
	else:
		failures += 1
		print("[UI] FAIL %s %s" % [label, extra])


func _clean() -> void:
	for name in ["settings.json"]:
		var f := SCRATCH.path_join(name)
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)


# ------------------------------------------------------------------ icons ----
func _test_icons() -> void:
	var missing: Array = []
	var wrong_size: Array = []
	var empty: Array = []
	for name in KIT.ICONS:
		var path := KIT.ICON_DIR + String(name) + ".png"
		if not FileAccess.file_exists(path):
			missing.append(name)
			continue
		var tex := KIT.icon(String(name))
		if tex == null:
			missing.append(name)
			continue
		if tex.get_width() != 24 or tex.get_height() != 24:
			wrong_size.append("%s=%dx%d" % [name, tex.get_width(), tex.get_height()])
		var img := tex.get_image()
		if img == null or img.is_empty():
			empty.append(name)
	_check(missing.is_empty(), "semua ikon ada di paket ui", str(missing))
	_check(wrong_size.is_empty(), "semua ikon 24x24", str(wrong_size))
	_check(empty.is_empty(), "tidak ada ikon kosong", str(empty))

	# the packed game only ships the atlas, so every icon the code names must be
	# in it - a missing entry would be an invisible button on the phone
	var entries := {}
	if FileAccess.file_exists(ATLAS_JSON):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ATLAS_JSON))
		if typeof(parsed) == TYPE_DICTIONARY:
			entries = (parsed as Dictionary).get("entries", {})
	var not_in_atlas: Array = []
	for name in KIT.ICONS:
		if not entries.has(String(name)):
			not_in_atlas.append(name)
	_check(entries.size() == KIT.ICONS.size(),
		"atlas memuat semua ikon (%d)" % KIT.ICONS.size(), str(entries.size()))
	_check(not_in_atlas.is_empty(), "tidak ada ikon yang lupa masuk atlas", str(not_in_atlas))
	var tex_icon := KIT.icon("heart_full")
	_check(tex_icon is AtlasTexture and tex_icon.get_width() == 24,
		"ikon dibaca dari atlas, bukan tujuh tekstur terpisah", str(tex_icon))


func _test_kit_assets() -> void:
	var parch := KIT.tex(KIT.PARCHMENT)
	var crest := KIT.tex(KIT.CREST)
	_check(parch != null and crest != null, "perkamen dan crest termuat dari paket")
	var f := KIT.font(KIT.FONT_BODY)
	_check(f != null, "font badan termuat")
	var nine := KIT.parchment()
	_check(nine.texture != null and nine.content_margin_left > 0.0,
		"nine-patch perkamen punya tekstur dan margin")
	var btn := KIT.button("Uji", Vector2(120, 40))
	_check(btn.custom_minimum_size == Vector2(120, 40) and btn.text == "Uji",
		"tombol kit memakai ukuran yang diminta")


# --------------------------------------------------------------- settings ----
func _test_settings() -> void:
	var st: RefCounted = SETTINGS.new(SCRATCH)
	var note := String(st.call("load_settings"))
	_check(bool(st.call("get_value", "tilt_shift")) and bool(st.call("get_value", "shake"))
		and String(st.call("quality")) == "sedang", "bawaan: tilt-shift nyala, getar nyala, sedang", note)

	_check(bool(st.call("set_value", "quality", "tinggi")), "kualitas tinggi diterima")
	_check(not bool(st.call("set_value", "quality", "ultra")), "kualitas asing ditolak")
	var err := String(st.call("save"))
	_check(err == "", "settings bisa ditulis", err)

	var again: RefCounted = SETTINGS.new(SCRATCH)
	again.call("load_settings")
	_check(String(again.call("quality")) == "tinggi", "kualitas tersimpan setelah dibaca ulang",
		String(again.call("quality")))

	# a corrupt file must not break the boot
	var f := FileAccess.open(SCRATCH.path_join("settings.json"), FileAccess.WRITE)
	f.store_string("{ not json")
	f.flush()
	f = null
	var broken: RefCounted = SETTINGS.new(SCRATCH)
	var broken_note := String(broken.call("load_settings"))
	_check(String(broken.call("quality")) == "sedang" and broken_note.contains("rusak"),
		"settings rusak kembali ke bawaan", broken_note)

	# a file from a newer build is left alone
	var raw := JSON.stringify({"schema": 99, "quality": "tinggi"})
	var f2 := FileAccess.open(SCRATCH.path_join("settings.json"), FileAccess.WRITE)
	f2.store_string(raw)
	f2.flush()
	f2 = null
	var newer: RefCounted = SETTINGS.new(SCRATCH)
	var newer_note := String(newer.call("load_settings"))
	var after := FileAccess.get_file_as_string(SCRATCH.path_join("settings.json"))
	_check(newer_note.contains("lebih baru") and after == raw,
		"settings versi lebih baru tidak ditimpa", newer_note)

	# presets feed the renderer
	var preset: RefCounted = SETTINGS.new(SCRATCH)
	preset.call("load_settings")
	preset.call("set_value", "quality", "rendah")
	var low_blur := float(preset.call("tilt_blur"))
	var low_scale := float(preset.call("atmosphere_scale"))
	_check(not bool(preset.call("shadows_enabled")) and low_blur < 2.0 and low_scale < 0.5,
		"preset rendah mematikan bayangan dan menipiskan atmosfer",
		"blur %.1f skala %.2f" % [low_blur, low_scale])
	preset.call("set_value", "tilt_shift", false)
	_check(is_zero_approx(float(preset.call("tilt_blur"))), "tilt-shift mati = blur 0")

	# frame budget and 3D resolution are part of the same preset
	# step 1 added one UI size knob and two joystick preferences
	_check(bool(preset.call("set_value", "ui_scale", "besar"))
		and is_equal_approx(float(preset.call("ui_scale")), 1.14),
		"ukuran UI besar = skala 1,14", "%.2f" % float(preset.call("ui_scale")))
	_check(not bool(preset.call("set_value", "ui_scale", "raksasa")),
		"ukuran UI asing ditolak")
	_check(bool(preset.call("set_value", "stick_mode", "tetap"))
		and bool(preset.call("stick_fixed")), "stik bisa dipilih tetap")
	preset.call("set_value", "stick_sensitivity", 9.0)
	_check(is_equal_approx(float(preset.call("stick_sensitivity")), 1.6),
		"sensitivitas stik dijepit ke batas atas",
		"%.2f" % float(preset.call("stick_sensitivity")))
	preset.call("set_value", "stick_sensitivity", 1.0)

	var low_fps := int(preset.call("fps_cap"))
	var low_render := float(preset.call("render_scale"))
	preset.call("set_value", "quality", "tinggi")
	var high_fps := int(preset.call("fps_cap"))
	var high_render := float(preset.call("render_scale"))
	_check(low_fps <= 30 and high_fps >= 60, "preset rendah membatasi 30 fps, tinggi 60",
		"%d vs %d" % [low_fps, high_fps])
	_check(low_render < 0.85 and is_equal_approx(high_render, 1.0),
		"preset rendah menurunkan resolusi 3D", "%.2f vs %.2f" % [low_render, high_render])


# ------------------------------------------------------------------- menu ----
func _test_menu() -> void:
	if not ResourceLoader.exists(MAIN_SCENE):
		_check(false, "Main.tscn ada")
		return
	var st: RefCounted = SETTINGS.new(SCRATCH)
	st.call("load_settings")
	st.call("save")

	_main = load(MAIN_SCENE).instantiate() as Control
	_main.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_main)
	for _i in 10:
		await get_tree().process_frame

	var menu: Control = _main.get("_menu")
	var hud: Control = _main.get("_hud")
	_check(menu != null and not menu.visible, "menu ada dan tersembunyi saat bermain")
	_check(hud != null, "HUD lapangan terbangun")
	var inset: Vector2 = _main.call("_safe_insets")
	_check(inset.x >= 0.0 and inset.y >= 0.0, "safe area tidak pernah negatif", str(inset))

	# --- the field is almost empty: no objective box, no hearts, no FPS text
	var permanent: Array = [hud.call("minimap"), hud.call("menu_button")]
	_check(permanent[0] != null and permanent[1] != null,
		"HUD hanya punya minimap dan satu tombol menu")
	# In the valley of step 1 the spawn point was empty, so "no button at boot"
	# was true for free. In Yaros the region's start marker sits a few metres from
	# the fast-travel post, and standing next to a post IS something to act on -
	# so the rule is checked from open meadow instead of from the doorstep.
	var cast: Node = _main.get("_cast")
	var diorama: Node = _main.get("_diorama")
	if cast != null and diorama != null and diorama.has_method("region"):
		var region: RefCounted = diorama.call("region")
		var start: Vector2 = region.call("start_position")
		cast.call("teleport_player", start + Vector2(-11.0, -9.0))
		await get_tree().process_frame
		await get_tree().process_frame
		_main.call("_refresh_field")
	_check(not bool(hud.call("action_visible")), "tombol aksi tidak menetap di layar")
	_check(hud.call("fps_label") == null, "tidak ada teks FPS tanpa mode debug")
	_check(int(menu.call("current_page")) >= 0, "menu punya halaman awal")

	# --- one button opens every panel
	var page_ids: Array = []
	for id in ["lanjut", "jurnal", "peta", "inventori", "pengaturan", "simpan", "peluncur"]:
		if menu.call("page_node", id) != null:
			page_ids.append(id)
	_check(page_ids.size() == 7, "menu punya tujuh tab", str(page_ids))

	_main.call("_on_menu_pressed")
	await get_tree().process_frame
	_check(menu.visible and get_tree().paused, "tombol menu membuka panel dan menghentikan dunia")
	await get_tree().create_timer(0.35).timeout
	_check(menu.modulate.a > 0.95, "panel menu benar-benar tampak", str(menu.modulate.a))

	menu.call("show_page", "jurnal")
	await get_tree().process_frame
	_check(String(menu.call("current_page")) == "jurnal", "pindah ke tab Jurnal")
	var objective: Label = menu.get("_journal_objective")
	_check(objective != null and objective.text != "" and objective.text != "—",
		"Jurnal memuat tujuan aktif", objective.text if objective != null else "")

	menu.call("show_page", "pengaturan")
	await get_tree().process_frame
	var settings: RefCounted = _main.get("_settings")
	var before := bool(settings.call("get_value", "shake"))
	_main.call("_on_toggle", "shake")
	await get_tree().process_frame
	var after := bool(settings.call("get_value", "shake"))
	_check(before != after, "tombol pengaturan mengubah nilai", "%s -> %s" % [before, after])
	var disk := FileAccess.file_exists(SCRATCH.path_join("settings.json"))
	_check(disk, "setiap perubahan pengaturan langsung ditulis")

	_main.call("_on_toggle", "quality")
	await get_tree().process_frame
	var sun: DirectionalLight3D = _main.get("_diorama").get_node_or_null("Sun") as DirectionalLight3D
	var q := String(settings.call("quality"))
	_check(sun != null and sun.shadow_enabled == (q != "rendah"),
		"kualitas yang dipilih benar-benar diterapkan ke matahari", q)

	# the frame cap must reach the engine, not just the settings file
	var cap := Engine.max_fps
	_check(cap == int(settings.call("fps_cap")), "batas fps diterapkan ke engine", str(cap))
	var vp := _main.get_viewport()
	_check(vp != null and is_equal_approx(vp.scaling_3d_scale, float(settings.call("render_scale"))),
		"skala resolusi 3D diterapkan ke viewport",
		str(vp.scaling_3d_scale if vp != null else -1.0))

	# one knob for the whole interface, applied to the HUD's canvas layer
	var before_scale := float(menu.get("_settings").call("ui_scale"))
	_main.call("_on_toggle", "ui_scale")
	await get_tree().process_frame
	var after_scale := float(settings.call("ui_scale"))
	var layer: CanvasLayer = _main.get("_hud_layer")
	_check(not is_equal_approx(before_scale, after_scale)
		and is_equal_approx(layer.transform.get_scale().x, after_scale),
		"ukuran UI mengubah skala seluruh layer HUD",
		"%.2f -> %.2f (layer %.2f)" % [before_scale, after_scale,
			layer.transform.get_scale().x])
	_main.call("_on_toggle", "ui_scale")
	_main.call("_on_toggle", "ui_scale")
	await get_tree().process_frame

	# FPS is a debug readout: it needs both switches
	_main.call("_on_toggle", "debug")
	await get_tree().process_frame
	_check(bool(settings.call("debug_enabled")), "mode debug bisa dinyalakan")
	_main.call("_on_toggle", "show_fps")
	await get_tree().process_frame
	_check(hud.call("fps_label") != null, "penghitung FPS muncul saat debug + FPS nyala")
	_main.call("_on_toggle", "show_fps")
	_main.call("_on_toggle", "debug")
	await get_tree().process_frame
	_check(hud.call("fps_label") == null, "penghitung FPS hilang lagi")

	var blur := float((_main.get("_tilt_mat") as ShaderMaterial).get_shader_parameter("blur_pixels"))
	_check(blur >= 0.0, "tilt-shift mendapat nilai blur", str(blur))
	var status := String(_main.call("_status_text"))
	_check(status.contains("Orc") and status.contains("Nyawa"), "status di menu terbaca", status)

	# --- the launcher door needs a second tap
	menu.call("show_page", "peluncur")
	await get_tree().process_frame
	menu.call("_on_launcher_pressed")
	await get_tree().process_frame
	_check(menu.get("_launcher_armed"), "tombol peluncur minta konfirmasi dulu")
	# arm it again by hand rather than pressing twice: the second press really
	# would close the world, and this test is not here to leave the scene
	menu.set("_launcher_armed", false)
	_main.call("_on_resume_pressed")
	await get_tree().create_timer(0.25).timeout
	_check(not get_tree().paused and not menu.visible, "lanjutkan melepas jeda dan menutup panel")

	# --- full map panel opens from the minimap data, and closes again
	hud.call("open_map")
	await get_tree().process_frame
	var full: Control = hud.call("full_map")
	var opened := full != null and bool(full.get("is_open"))
	_check(opened, "peta penuh bisa dibuka")
	if full != null:
		# step 2 replaced the valley with the region: the title comes from the
		# map's own label (Yaros), not from a constant in the diorama
		var map_label := "Yaros"
		if diorama != null and diorama.has_method("region"):
			var reg: RefCounted = diorama.call("region")
			map_label = String(reg.get("label"))
		_check(String(full.get("_title").text) == map_label,
			"peta penuh memakai nama area", String(full.get("_title").text))
		full.call("close_panel")
		await get_tree().process_frame
		_check(not bool(full.get("is_open")), "peta penuh bisa ditutup")

	_main.queue_free()
	await get_tree().process_frame
