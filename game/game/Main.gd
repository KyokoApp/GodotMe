extends Control
## Re - Traveller : boot shell (Project B).
##
## Until Phase 2 adds actors, this is the game's front door: it boots the first
## HD-2D diorama, applies the tilt-shift pass and shows the themed HUD. It also
## keeps the two obligations of the pack contract:
##   1. report a healthy boot to the launcher (user://retraveller/boot_ok.json)
##   2. load every texture off the pack at runtime (no .import files exist)
##
## The sample screen's honesty note stays: this is still engine work, not a world
## with people in it.

const DIORAMA := "res://game/world/Diorama.tscn"
const TILT_SHIFT := "res://game/world/tiltshift.gdshader"

const FONT_BODY := "res://game/assets/PixelifySans.woff2"
const FONT_TITLE := "res://game/assets/PixelifySans-SemiBold.woff2"
const PARCH := "res://game/assets/parchment.png"
const CREST := "res://game/assets/crest.png"

const INK := Color(0.17, 0.12, 0.09)
const INK_SOFT := Color(0.36, 0.28, 0.20)
const BRASS := Color(0.78, 0.62, 0.33)
const CREAM := Color(0.98, 0.94, 0.86)

var _font_body: Font
var _font_title: Font
var _hud: CanvasLayer
var _hint: Label
var _diorama: Node3D


func _ready() -> void:
	if FileAccess.file_exists("res://game/FAIL_BOOT"):
		printerr("[GAME] Penanda kerusakan ditemukan, sengaja gagal boot.")
		OS.crash("Simulasi paket rusak (FAIL_BOOT)")

	_report_healthy_boot()
	_font_body = _font(FONT_BODY, 1)
	_font_title = _font(FONT_TITLE, 3)
	_build_world()
	_build_hud()
	_fade_in()
	_maybe_capture_or_quit()


# ------------------------------------------------------------------ world ----
func _build_world() -> void:
	if ResourceLoader.exists(DIORAMA):
		_diorama = load(DIORAMA).instantiate() as Node3D
		add_child(_diorama)
		_add_cast()
	else:
		# A missing world pack must not look like a crash: say it plainly.
		_diorama = null

	var layer := CanvasLayer.new()
	layer.name = "Post"
	layer.layer = 1
	add_child(layer)

	var rect := ColorRect.new()
	rect.name = "TiltShift"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	if ResourceLoader.exists(TILT_SHIFT):
		mat.shader = load(TILT_SHIFT)
	rect.material = mat
	layer.add_child(rect)


## The cast lives in the characters pack and is added *inside* the diorama, so
## it can ask the world for its prop footprints and inherit its light. A missing
## characters pack leaves the diorama standing instead of taking the boot down.
func _add_cast() -> void:
	var path := "res://game/characters/CharacterWorld.gd"
	if _diorama == null or not ResourceLoader.exists(path):
		print("[GAME] paket karakter tidak ada, diorama tetap tampil tanpa penghuni")
		return
	var script: Script = load(path)
	if script == null:
		print("[GAME] skrip karakter gagal dimuat")
		return
	var cast: Node3D = script.new()
	cast.name = "Characters"
	_diorama.add_child(cast)
	print("[GAME] penghuni dimuat dari paket karakter")


## Read a constant off the diorama's own script, at runtime.
##
## `Diorama.AREA_NAME` (a global class name) parses only inside the game's own
## project. The shipped game is loaded from .pck inside the launcher's project,
## where that name does not exist - it made this whole script fail to parse.
func _area_constant(key: String, fallback: String) -> String:
	if _diorama == null or _diorama.get_script() == null:
		return fallback
	var consts: Dictionary = (_diorama.get_script() as Script).get_script_constant_map()
	return String(consts.get(key, fallback))


# -------------------------------------------------------------------- hud ----
func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "HUD"
	_hud.layer = 2
	add_child(_hud)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(root)

	# --- area plaque, top left
	var plaque := PanelContainer.new()
	plaque.theme = _theme()
	plaque.add_theme_stylebox_override("panel", _nine(PARCH, 20, 26, 18))
	plaque.anchor_left = 0.0
	plaque.anchor_top = 0.0
	plaque.offset_left = 26.0
	plaque.offset_top = 24.0
	plaque.offset_right = 366.0
	plaque.offset_bottom = 24.0
	plaque.grow_vertical = Control.GROW_DIRECTION_END
	root.add_child(plaque)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	plaque.add_child(box)

	var name_label := Label.new()
	name_label.text = _area_constant("AREA_NAME", "Dunia tidak termuat")
	name_label.add_theme_font_override("font", _font_title)
	name_label.add_theme_font_size_override("font_size", 30)
	name_label.add_theme_color_override("font_color", INK)
	box.add_child(name_label)

	var sub_label := Label.new()
	sub_label.text = (_area_constant("AREA_SUBTITLE", "") if _diorama != null
		else "Paket dunia tidak ditemukan — kembali dan periksa pembaruan.")
	sub_label.add_theme_font_override("font", _font_body)
	sub_label.add_theme_font_size_override("font_size", 16)
	sub_label.add_theme_color_override("font_color", INK_SOFT)
	sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(sub_label)

	# --- crest + engine note, bottom left
	var note := PanelContainer.new()
	note.theme = _theme()
	note.add_theme_stylebox_override("panel", _nine(PARCH, 20, 22, 16))
	note.anchor_left = 0.0
	note.anchor_right = 0.0
	note.anchor_top = 1.0
	note.anchor_bottom = 1.0
	note.offset_left = 26.0
	note.offset_right = 452.0
	note.offset_top = -26.0
	note.offset_bottom = -26.0
	note.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(note)

	var note_box := HBoxContainer.new()
	note_box.add_theme_constant_override("separation", 14)
	note.add_child(note_box)

	var crest := TextureRect.new()
	crest.texture = _tex(CREST)
	crest.custom_minimum_size = Vector2(56, 56)
	crest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	crest.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	note_box.add_child(crest)

	var note_label := Label.new()
	note_label.text = "Fase 2 · tahap 2: penghuni lembah.\nKsatria bisa digerakkan, penjaga punya cerita, orc berpatroli di tepi hutan."
	note_label.add_theme_font_override("font", _font_body)
	note_label.add_theme_font_size_override("font_size", 15)
	note_label.add_theme_color_override("font_color", INK_SOFT)
	note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_label.custom_minimum_size = Vector2(330, 0)
	note_box.add_child(note_label)

	# --- back to the launcher, top right
	var back := Button.new()
	back.text = "  Peluncur"
	back.theme = _theme()
	back.add_theme_stylebox_override("normal", _nine(PARCH, 20, 22, 12))
	back.add_theme_stylebox_override("hover", _nine(PARCH, 20, 22, 12))
	back.add_theme_stylebox_override("pressed", _nine(PARCH, 20, 22, 12))
	back.add_theme_font_override("font", _font_title)
	back.add_theme_font_size_override("font_size", 18)
	back.add_theme_color_override("font_color", INK)
	back.custom_minimum_size = Vector2(150, 46)
	back.anchor_left = 1.0
	back.anchor_right = 1.0
	back.anchor_top = 0.0
	back.anchor_bottom = 0.0
	back.offset_left = -176.0
	back.offset_right = -26.0
	back.offset_top = 24.0
	back.offset_bottom = 70.0
	back.pressed.connect(_on_back_pressed)
	root.add_child(back)

	# --- one-time control hint near the bottom centre
	_hint = Label.new()
	_hint.text = "Stik kiri: jalan (dorong penuh untuk lari) · Serang · Tahan · Bicara\nGeser layar untuk melihat sekeliling · cubit untuk memperbesar"
	_hint.add_theme_font_override("font", _font_body)
	_hint.add_theme_font_size_override("font_size", 16)
	_hint.add_theme_color_override("font_color", CREAM)
	_hint.add_theme_color_override("font_shadow_color", Color(0.05, 0.03, 0.02, 0.9))
	_hint.add_theme_constant_override("shadow_offset_y", 2)
	_hint.add_theme_constant_override("shadow_outline_size", 4)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.anchor_left = 0.0
	_hint.anchor_right = 1.0
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_left = 470.0
	_hint.offset_right = -26.0
	_hint.offset_top = -44.0
	_hint.offset_bottom = -16.0
	root.add_child(_hint)
	var tw := create_tween()
	tw.tween_interval(5.0)
	tw.tween_property(_hint, "modulate:a", 0.0, 1.2)


func _on_back_pressed() -> void:
	var tree := get_tree()
	await _fade_out()
	tree.change_scene_to_file("res://scenes/Launcher.tscn")


# ---------------------------------------------------------------- curtain ----
func _fade_in() -> void:
	var curtain := _make_curtain()
	add_child(curtain)
	var tw := create_tween()
	tw.tween_property(curtain, "modulate:a", 0.0, 0.7).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(curtain.queue_free)


func _fade_out() -> void:
	var curtain := _make_curtain()
	curtain.modulate.a = 0.0
	add_child(curtain)
	var tw := create_tween()
	tw.tween_property(curtain, "modulate:a", 1.0, 0.35).set_trans(Tween.TRANS_SINE)
	await tw.finished


func _make_curtain() -> ColorRect:
	var rect := ColorRect.new()
	rect.color = Color(0.07, 0.05, 0.04, 1.0)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


# --------------------------------------------------------------- contract ----
func _report_healthy_boot() -> void:
	var version := "0.1.0"
	var active := "user://retraveller/active.json"
	if FileAccess.file_exists(active):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(active))
		if typeof(parsed) == TYPE_DICTIONARY:
			version = String((parsed as Dictionary).get("version", version))
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
	print("[GAME] boot_ok ditulis untuk versi %s" % version)


func _maybe_capture_or_quit() -> void:
	for arg in OS.get_cmdline_user_args():
		var a := String(arg)
		if a.begins_with("--test-quit-after="):
			var secs := float(a.substr("--test-quit-after=".length()))
			await get_tree().create_timer(secs).timeout
			print("[GAME] keluar otomatis untuk pengujian.")
			get_tree().quit(0)
			return
		if a.begins_with("--capture="):
			var dir: String = a.substr("--capture=".length())
			var shot_name := "08_diorama"
			for arg2 in OS.get_cmdline_user_args():
				var b := String(arg2)
				if b.begins_with("--capture-name="):
					shot_name = b.substr("--capture-name=".length())
			# let the curtain finish and one bloom frame settle
			await get_tree().create_timer(1.8).timeout
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute(dir)
			var img := get_viewport().get_texture().get_image()
			var path := dir.path_join(shot_name + ".png")
			var err := img.save_png(path)
			print("[GAME] capture %s -> %s (err %d, %dx%d)" % [
				shot_name, path, err, img.get_width(), img.get_height()])
			get_tree().quit(0)
			return


# ---------------------------------------------------------------- helpers ----
func _theme() -> Theme:
	var t := Theme.new()
	t.default_font = _font_body
	t.default_font_size = 18
	return t


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
		return ThemeDB.fallback_font
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
