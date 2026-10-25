extends Node
## Headless gate for phase 7: the UI kit, the settings file and the menu.
##
##   godot --headless --path game res://game/tests/UiTest.tscn
##
## What a screenshot cannot prove: that the settings actually survive a restart,
## that a corrupt settings file does not take the boot down, that every icon is
## really 24x24 and came out of the pack, and that the pause sheet's buttons are
## wired to something. All of that is asserted here.

const KIT := preload("res://game/ui/UiKit.gd")
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
	for _i in 8:
		await get_tree().process_frame

	var sheet: Control = _main.get("_pause_root")
	_check(sheet != null and not sheet.visible, "lembar jeda ada dan tersembunyi")
	var inset: Vector2 = _main.call("_safe_insets")
	_check(inset.x >= 0.0 and inset.y >= 0.0, "safe area tidak pernah negatif", str(inset))
	var icons: Array = _main.get("_hearts_icons")
	_check(icons.size() == 3, "HUD punya tiga ikon hati", str(icons.size()))

	_main.call("_on_pause_pressed")
	await get_tree().process_frame
	_check(sheet.visible and get_tree().paused, "jeda membuka lembar dan menghentikan dunia")
	# and it must actually be on screen: a sheet at alpha 0 freezes the world and
	# shows the player nothing (that was the first version of this menu)
	await get_tree().create_timer(0.4).timeout
	_check(sheet.modulate.a > 0.95, "lembar jeda benar-benar tampak", str(sheet.modulate.a))

	var page_jeda: Control = _main.get("_page_jeda")
	var page_set: Control = _main.get("_page_set")
	_check(page_jeda != null and page_jeda.get_child_count() == 4,
		"halaman jeda punya empat tombol", str(page_jeda.get_child_count() if page_jeda else -1))
	_check(page_set != null and page_set.get_child_count() == 4,
		"halaman pengaturan punya empat tombol", str(page_set.get_child_count() if page_set else -1))

	_main.call("_show_settings")
	await get_tree().process_frame
	_check(page_set.visible and not page_jeda.visible, "pindah ke halaman pengaturan")

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

	var blur := float((_main.get("_tilt_mat") as ShaderMaterial).get_shader_parameter("blur_pixels"))
	_check(blur >= 0.0, "tilt-shift mendapat nilai blur", str(blur))
	var status := String(_main.call("_status_text"))
	_check(status.contains("Orc") and status.contains("Nyawa"), "status di menu terbaca", status)

	_main.call("_on_resume_pressed")
	await get_tree().create_timer(0.25).timeout
	_check(not get_tree().paused, "lanjutkan melepas jeda")
	_main.queue_free()
	await get_tree().process_frame
