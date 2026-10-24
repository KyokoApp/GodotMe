extends Control
## Sample pack entry point.
##
## Demonstrates the two rules a real Re - Traveller build must also follow:
##   1. report a healthy boot to the launcher (user://retraveller/boot_ok.json)
##   2. never assume res:// texture imports exist - assets are loaded from the
##      pack at runtime so the demo can be built with a plain PCKPacker.

const TEXT_VERSION := "0.1.0"
const CREST := "res://game/assets/crest.png"
const BG := "res://game/assets/bg.png"
const PARCH := "res://game/assets/parchment.png"
const DIVIDER := "res://game/assets/divider.png"
# Blackletter reads as a smear at phone size (and at 60 px on a 1280x720
# canvas it is unreadable), so the sample screen uses the same pixel face as the
# launcher, bigger and with extra tracking.
const FONT_DISPLAY := "res://game/assets/PixelifySans-SemiBold.woff2"
const FONT_BODY := "res://game/assets/PixelifySans.woff2"

var _font_display: Font
var _font_body: Font
var _status: Label


func _ready() -> void:
	if FileAccess.file_exists("res://game/FAIL_BOOT"):
		printerr("[SAMPLE] Penanda kerusakan ditemukan, sengaja gagal boot.")
		OS.crash("Simulasi paket rusak (FAIL_BOOT)")

	_report_healthy_boot()
	_build_ui()
	_maybe_quit_for_tests()


func _report_healthy_boot() -> void:
	var version := TEXT_VERSION
	var active := "user://retraveller/active.json"
	if FileAccess.file_exists(active):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(active))
		if typeof(parsed) == TYPE_DICTIONARY:
			version = String((parsed as Dictionary).get("version", TEXT_VERSION))
	DirAccess.make_dir_recursive_absolute("user://retraveller")
	var f := FileAccess.open("user://retraveller/boot_ok.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({
			"version": version,
			"schema": 1,
			"scene": "res://game/Main.tscn",
			"at": Time.get_datetime_string_from_system(true),
		}, "  "))
		f.flush()
		f = null
	print("[SAMPLE] boot_ok ditulis untuk versi %s" % version)


func _build_ui() -> void:
	var bg := _tex(BG)
	var bg_rect := TextureRect.new()
	bg_rect.texture = bg
	bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_rect.modulate = Color(0.72, 0.66, 0.62)
	add_child(bg_rect)

	_font_display = _font(FONT_DISPLAY, 3)
	_font_body = _font(FONT_BODY, 1)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _nine(PARCH, 20, 30, 26))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(820, 0)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -410
	panel.offset_right = 410
	panel.offset_top = -250
	panel.offset_bottom = 250
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var crest := TextureRect.new()
	crest.texture = _tex(CREST)
	crest.custom_minimum_size = Vector2(112, 112)
	crest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	crest.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(crest)

	var title := Label.new()
	title.text = "DUNIA CONTOH"
	title.add_theme_font_override("font", _font_display)
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(0.165, 0.11, 0.086))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var sub := Label.new()
	sub.text = "Dunia ini dimuat dari paket .pck, bukan dari APK."
	sub.add_theme_font_override("font", _font_body)
	sub.add_theme_font_size_override("font_size", 20)
	sub.add_theme_color_override("font_color", Color(0.35, 0.27, 0.19))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)

	var divider := TextureRect.new()
	divider.texture = _tex(DIVIDER)
	divider.custom_minimum_size = Vector2(0, 14)
	divider.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	divider.stretch_mode = TextureRect.STRETCH_SCALE
	box.add_child(divider)

	_status = Label.new()
	_status.text = "Dimuat dari 6 paket: core · characters · enemies · world · ui · audio"
	_status.add_theme_font_override("font", _font_body)
	_status.add_theme_font_size_override("font_size", 17)
	_status.add_theme_color_override("font_color", Color(0.42, 0.33, 0.24))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)

	var end_note := Label.new()
	end_note.text = "Ini batas Fase 1: pipa unduh → verifikasi → muat paket sudah utuh.\nDunia sesungguhnya (kamera HD-2D, karakter, pertempuran) dibangun di Fase 2."
	end_note.add_theme_font_override("font", _font_body)
	end_note.add_theme_font_size_override("font_size", 16)
	end_note.add_theme_color_override("font_color", Color(0.44, 0.35, 0.26))
	end_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(end_note)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)

	var back := Button.new()
	back.text = "  Kembali ke Peluncur"
	back.custom_minimum_size = Vector2(280, 54)
	back.add_theme_font_override("font", _font_body)
	back.add_theme_font_size_override("font_size", 21)
	back.add_theme_color_override("font_color", Color(0.98, 0.94, 0.84))
	back.add_theme_stylebox_override("normal", _nine(DIVIDER, 4, 20, 10) if false else _flat(Color(0.36, 0.235, 0.149)))
	back.add_theme_stylebox_override("hover", _flat(Color(0.45, 0.30, 0.19)))
	back.add_theme_stylebox_override("pressed", _flat(Color(0.28, 0.18, 0.11)))
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/Launcher.tscn"))
	row.add_child(back)


func _maybe_quit_for_tests() -> void:
	for arg in OS.get_cmdline_user_args():
		var a := String(arg)
		if a.begins_with("--test-quit-after="):
			var secs := float(a.substr("--test-quit-after=".length()))
			await get_tree().create_timer(secs).timeout
			print("[SAMPLE] keluar otomatis untuk pengujian.")
			get_tree().quit(0)
			return
		if a.begins_with("--capture="):
			# "godot --path game -- --capture=<dir> [--capture-name=x]": save the
			# scene once and exit, so CI can check this screen visually.
			var dir := a.substr("--capture=".length())
			var shot_name := "07_dunia"
			for arg2 in OS.get_cmdline_user_args():
				var b := String(arg2)
				if b.begins_with("--capture-name="):
					shot_name = b.substr("--capture-name=".length())
			await get_tree().create_timer(1.2).timeout
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute(dir)
			var img := get_viewport().get_texture().get_image()
			var path := dir.path_join(shot_name + ".png")
			var err := img.save_png(path)
			print("[SAMPLE] capture %s -> %s (err %d, %dx%d)" % [
				shot_name, path, err, img.get_width(), img.get_height()])
			get_tree().quit(0)
			return


# --------------------------------------------------------------- helpers -----
func _tex(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var data := FileAccess.get_file_as_bytes(path)
	var img := Image.new()
	if img.load_png_from_buffer(data) != OK:
		return null
	return ImageTexture.create_from_image(img)


## Pixelify packs its glyphs tight; a FontVariation adds tracking without
## touching the letterforms (same trick as the launcher's small print).
func _font(path: String, tracking: int = 0) -> Font:
	var f := FontFile.new()
	if f.load_dynamic_font(path) != OK:
		return null
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.hinting = TextServer.HINTING_NONE
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	if tracking == 0:
		return f
	var v := FontVariation.new()
	v.base_font = f
	v.spacing_glyph = tracking
	v.spacing_space = tracking * 2
	return v


func _nine(path: String, margin: int, mx: int, my: int) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = _tex(path)
	sb.set_texture_margin_all(margin)
	sb.content_margin_left = mx
	sb.content_margin_right = mx
	sb.content_margin_top = my
	sb.content_margin_bottom = my
	return sb


func _flat(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb
