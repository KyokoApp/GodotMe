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

const KIT := preload("res://game/ui/UiKit.gd")
const SETTINGS := preload("res://game/ui/Settings.gd")

const INK := Color(0.17, 0.12, 0.09)
const INK_SOFT := Color(0.36, 0.28, 0.20)
const BRASS := Color(0.78, 0.62, 0.33)
const CREAM := Color(0.98, 0.94, 0.86)

var _font_body: Font
var _font_title: Font
var _hud: CanvasLayer
var _hint: Label
var _diorama: Node3D
var _cast: Node3D
var _objective_label: Label
var _hearts_label: Label
var _pause_root: Control
var _save_note: Label
var _hud_timer := 0.0
var _settings: RefCounted
var _tilt_mat: ShaderMaterial
var _page_jeda: Control
var _page_set: Control
var _sheet_title: Label
var _status_label: Label
var _hearts_icons: Array = []
var _phase_icon: TextureRect
var _phase_label: Label
var _toggles := {}


func _ready() -> void:
	if FileAccess.file_exists("res://game/FAIL_BOOT"):
		printerr("[GAME] Penanda kerusakan ditemukan, sengaja gagal boot.")
		OS.crash("Simulasi paket rusak (FAIL_BOOT)")

	_report_healthy_boot()
	_settings = SETTINGS.new()
	_settings.call("load_settings")
	_font_body = _font(FONT_BODY, 1)
	_font_title = _font(FONT_TITLE, 3)
	_build_world()
	_build_hud()
	_apply_settings()
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
	_tilt_mat = mat
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
	_cast = cast
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
## Notch and rounded-corner guard. On a phone the display's safe area can be a
## few dozen pixels smaller than the screen; without this the area plaque and the
## Jeda button sit under the notch or the rounded corner. On desktop the insets
## are zero, so this costs nothing there. Values are scaled from screen pixels to
## the 1280x720 design canvas.
func _safe_insets() -> Vector2:
	var screen := DisplayServer.screen_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if screen.x <= 0 or screen.y <= 0 or safe.size.x <= 0:
		return Vector2.ZERO
	var vp := get_viewport()
	var width := float(vp.get_visible_rect().size.x) if vp != null else 1280.0
	if width <= 0.0:
		width = 1280.0
	var k := width / float(screen.x)
	var left := maxf(0.0, float(safe.position.x)) * k
	var top := maxf(0.0, float(safe.position.y)) * k
	return Vector2(left, top)



func _build_hud() -> void:
	var safe := _safe_insets()
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
	plaque.offset_left = 26.0 + safe.x
	plaque.offset_top = 24.0 + safe.y
	plaque.offset_right = 366.0 + safe.x
	plaque.offset_bottom = 24.0 + safe.y
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

	# --- objective + hearts, under the area plaque
	var quest := PanelContainer.new()
	quest.theme = _theme()
	quest.add_theme_stylebox_override("panel", _nine(PARCH, 20, 24, 16))
	quest.anchor_left = 0.0
	quest.anchor_top = 0.0
	quest.offset_left = 26.0 + safe.x
	quest.offset_top = 124.0 + safe.y
	quest.offset_right = 426.0 + safe.x
	quest.offset_bottom = 124.0 + safe.y
	quest.grow_vertical = Control.GROW_DIRECTION_END
	root.add_child(quest)

	var quest_box := VBoxContainer.new()
	quest_box.add_theme_constant_override("separation", 4)
	quest.add_child(quest_box)

	var quest_head := Label.new()
	quest_head.text = "TUJUAN"
	quest_head.add_theme_font_override("font", _font_title)
	quest_head.add_theme_font_size_override("font_size", 14)
	quest_head.add_theme_color_override("font_color", INK_SOFT)
	quest_box.add_child(quest_head)

	_objective_label = Label.new()
	_objective_label.text = "Menyiapkan lembah…"
	_objective_label.add_theme_font_override("font", _font_body)
	_objective_label.add_theme_font_size_override("font_size", 19)
	_objective_label.add_theme_color_override("font_color", INK)
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective_label.custom_minimum_size = Vector2(352, 0)
	quest_box.add_child(_objective_label)

	# hearts are drawn, not spelled out: three icons say "you have three lives"
	# faster than any sentence, and they are the only HUD element that changes
	# colour when the player is in trouble
	var hearts_row := HBoxContainer.new()
	hearts_row.add_theme_constant_override("separation", 4)
	quest_box.add_child(hearts_row)
	for i in range(3):
		var heart := KIT.icon_rect("heart_full", 24.0)
		heart.name = "Heart%d" % i
		hearts_row.add_child(heart)
		_hearts_icons.append(heart)
	_hearts_label = KIT.label("Nyawa 3 / 3", 16, INK_SOFT)
	hearts_row.add_child(_hearts_label)

	# which hour of the day the valley is in, with the matching icon
	var phase_row := HBoxContainer.new()
	phase_row.add_theme_constant_override("separation", 6)
	quest_box.add_child(phase_row)
	_phase_icon = KIT.icon_rect("sun", 20.0)
	phase_row.add_child(_phase_icon)
	_phase_label = KIT.label("Sore", 16, INK_SOFT)
	phase_row.add_child(_phase_label)

	# --- crest + engine note, bottom left
	var note := PanelContainer.new()
	note.theme = _theme()
	note.add_theme_stylebox_override("panel", _nine(PARCH, 20, 22, 16))
	note.anchor_left = 0.0
	note.anchor_right = 0.0
	note.anchor_top = 1.0
	note.anchor_bottom = 1.0
	note.offset_left = 26.0 + safe.x
	note.offset_right = 452.0 + safe.x
	note.offset_top = -26.0 - safe.y
	note.offset_bottom = -26.0 - safe.y
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
	note_label.text = "Lembah Pertama.\nJalan tua menuju pegunungan. Penjaga Bram berdiri di tikungan; tiga orc berkeliaran di tepi hutan."
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
	back.offset_left = -176.0 - safe.x
	back.offset_right = -26.0 - safe.x
	back.offset_top = 24.0 + safe.y
	back.offset_bottom = 70.0 + safe.y
	back.pressed.connect(_on_back_pressed)
	root.add_child(back)

	# --- pause sheet, top right (left of the launcher button)
	var pause_btn := Button.new()
	pause_btn.text = "  Jeda"
	pause_btn.theme = _theme()
	pause_btn.add_theme_stylebox_override("normal", _nine(PARCH, 20, 22, 12))
	pause_btn.add_theme_stylebox_override("hover", _nine(PARCH, 20, 22, 12))
	pause_btn.add_theme_stylebox_override("pressed", _nine(PARCH, 20, 22, 12))
	pause_btn.add_theme_font_override("font", _font_title)
	pause_btn.add_theme_font_size_override("font_size", 18)
	pause_btn.add_theme_color_override("font_color", INK)
	pause_btn.custom_minimum_size = Vector2(130, 46)
	pause_btn.anchor_left = 1.0
	pause_btn.anchor_right = 1.0
	pause_btn.offset_left = -326.0 - safe.x
	pause_btn.offset_right = -196.0 - safe.x
	pause_btn.offset_top = 24.0 + safe.y
	pause_btn.offset_bottom = 70.0 + safe.y
	pause_btn.pressed.connect(_on_pause_pressed)
	root.add_child(pause_btn)

	_build_pause_sheet(root)

	# --- one-time control hint near the bottom centre
	_hint = Label.new()
	_hint.text = "Sentuh kiri untuk stik jalan (dorong penuh = lari) · Serang · Tahan perisai · Bicara\nDua jari menggeser pandangan · cubit memperbesar · Jeda untuk menyimpan dan keluar"
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
	_hint.offset_left = 470.0 + safe.x
	_hint.offset_right = -26.0 - safe.x
	_hint.offset_top = -44.0 - safe.y
	_hint.offset_bottom = -16.0 - safe.y
	root.add_child(_hint)
	var tw := create_tween()
	tw.tween_interval(5.0)
	tw.tween_property(_hint, "modulate:a", 0.0, 1.2)


## Themed pause sheet: two pages (jeda and pengaturan) inside one parchared
## frame. Buttons keep working while the tree is paused because the whole sheet
## is PROCESS_MODE_WHEN_PAUSED - the world freezes, the menu does not.
func _build_pause_sheet(parent: Control) -> void:
	_pause_root = Control.new()
	_pause_root.name = "PauseSheet"
	_pause_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_root.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_pause_root.visible = false
	parent.add_child(_pause_root)

	var dim := ColorRect.new()
	dim.color = Color(0.07, 0.05, 0.04, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_root.add_child(dim)

	var sheet := PanelContainer.new()
	sheet.name = "Sheet"
	sheet.theme = _theme()
	sheet.add_theme_stylebox_override("panel", _nine(PARCH, 20, 34, 26))
	sheet.anchor_left = 0.5
	sheet.anchor_right = 0.5
	sheet.anchor_top = 0.5
	sheet.anchor_bottom = 0.5
	sheet.offset_left = -216.0
	sheet.offset_right = 216.0
	sheet.offset_top = -196.0
	sheet.offset_bottom = 196.0
	_pause_root.add_child(sheet)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	sheet.add_child(box)

	_sheet_title = KIT.label("Jeda", 30, INK, true)
	_sheet_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_sheet_title)

	_status_label = KIT.label("", 15, INK_SOFT)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(352, 0)
	box.add_child(_status_label)

	# --- page 1: pause
	_page_jeda = VBoxContainer.new()
	_page_jeda.name = "PageJeda"
	_page_jeda.add_theme_constant_override("separation", 10)
	box.add_child(_page_jeda)
	_page_jeda.add_child(KIT.button("Lanjutkan", Vector2(352, 50)))
	_page_jeda.get_child(0).connect("pressed", Callable(self, "_on_resume_pressed"))
	_page_jeda.add_child(KIT.button("Simpan sekarang", Vector2(352, 50)))
	_page_jeda.get_child(1).connect("pressed", Callable(self, "_on_save_pressed"))
	_page_jeda.add_child(KIT.button("Pengaturan", Vector2(352, 50)))
	_page_jeda.get_child(2).connect("pressed", Callable(self, "_show_settings"))
	_page_jeda.add_child(KIT.button("Peluncur", Vector2(352, 50)))
	_page_jeda.get_child(3).connect("pressed", Callable(self, "_on_pause_back_pressed"))

	# --- page 2: settings
	_page_set = VBoxContainer.new()
	_page_set.name = "PagePengaturan"
	_page_set.add_theme_constant_override("separation", 10)
	_page_set.visible = false
	box.add_child(_page_set)
	_set_button("tilt_shift", "Tilt-shift: Nyala")
	_set_button("shake", "Getar kamera: Nyala")
	_set_button("quality", "Kualitas: Sedang")
	_page_set.add_child(KIT.button("Kembali", Vector2(352, 50)))
	_page_set.get_child(3).connect("pressed", Callable(self, "_show_pause"))

	_save_note = KIT.label("", 15, INK_SOFT)
	_save_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_save_note.custom_minimum_size = Vector2(352, 20)
	box.add_child(_save_note)


func _set_button(key: String, text: String) -> void:
	var btn := KIT.button(text, Vector2(352, 50))
	btn.name = "Set_" + key
	btn.pressed.connect(Callable(self, "_on_toggle").bind(key))
	_page_set.add_child(btn)
	_toggles[key] = btn


## Fade between the two pages instead of snapping: the parchment stays put and
## only its contents change, which reads as one sheet being turned over.
func _show_page(page: Control, title: String) -> void:
	if _pause_root == null or page == null:
		return
	var other: Control = _page_set if page == _page_jeda else _page_jeda
	_sheet_title.text = title
	other.visible = false
	page.visible = true
	page.modulate.a = 0.0
	var tw := create_tween()
	# The tree is paused while this sheet is open, and a tween bound to a paused
	# tree simply never runs - the first version of this menu showed nothing at
	# all and only froze the world (caught by the 20_menu capture, not by a test
	# that only looked at `visible`).
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(page, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_SINE)


func _show_pause() -> void:
	_show_page(_page_jeda, "Jeda")
	_save_note.text = ""


func _show_settings() -> void:
	_refresh_toggles()
	_show_page(_page_set, "Pengaturan")
	_save_note.text = "Perubahan langsung tersimpan."


func _refresh_toggles() -> void:
	if _settings == null:
		return
	var tilt := "Nyala" if bool(_settings.call("get_value", "tilt_shift")) else "Mati"
	var shake := "Nyala" if bool(_settings.call("get_value", "shake")) else "Mati"
	var q := String(_settings.call("quality"))
	for key in _toggles.keys():
		var btn: Button = _toggles[key]
		match key:
			"tilt_shift":
				btn.text = "Tilt-shift: " + tilt
			"shake":
				btn.text = "Getar kamera: " + shake
			"quality":
				btn.text = "Kualitas: " + q.capitalize()


## One button per setting; every press is written to disk immediately, because a
## player who changes the blur and then kills the app expects it to stay changed.
func _on_toggle(key: String) -> void:
	if _settings == null:
		return
	if key == "quality":
		_settings.call("cycle_quality")
	else:
		_settings.call("set_value", key, not bool(_settings.call("get_value", key)))
	var err := String(_settings.call("save"))
	_apply_settings()
	_refresh_toggles()
	_save_note.text = "Pengaturan tersimpan." if err == "" else "Gagal menyimpan: " + err


## Push the current settings into the running world. Everything here is optional
## on purpose: if a pack is missing, the toggle simply has nothing to act on.
func _apply_settings() -> void:
	if _settings == null:
		return
	if _tilt_mat != null:
		_tilt_mat.set_shader_parameter("blur_pixels", float(_settings.call("tilt_blur")))
		var vignette := 0.0 if String(_settings.call("quality")) == "rendah" else 0.34
		_tilt_mat.set_shader_parameter("vignette", vignette)
	if _cast != null and is_instance_valid(_cast) and _cast.has_method("set_shake_scale"):
		var scale := 1.0 if bool(_settings.call("get_value", "shake")) else 0.0
		_cast.call("set_shake_scale", scale)
	if _diorama != null:
		if _diorama.has_method("set_shadows_enabled"):
			_diorama.call("set_shadows_enabled", bool(_settings.call("shadows_enabled")))
		if _diorama.has_method("set_atmosphere_scale"):
			_diorama.call("set_atmosphere_scale", float(_settings.call("atmosphere_scale")))


func _process(delta: float) -> void:
	_hud_timer += delta
	if _hud_timer < 0.2:
		return
	_hud_timer = 0.0
	_refresh_hud()


## The world owns the numbers; the HUD only reads them.
func _refresh_hud() -> void:
	if _cast == null or not is_instance_valid(_cast) or not _cast.has_method("hud_state"):
		return
	var st: Dictionary = _cast.call("hud_state")
	if _objective_label != null:
		_objective_label.text = String(st.get("objective", ""))
	var hearts := int(st.get("hearts", 0))
	var most := int(st.get("max_hearts", 3))
	for i in range(_hearts_icons.size()):
		var icon: TextureRect = _hearts_icons[i]
		icon.texture = KIT.icon("heart_full" if i < hearts else "heart_empty")
	if _hearts_label != null:
		_hearts_label.text = "Nyawa %d / %d" % [hearts, most]
		_hearts_label.add_theme_color_override("font_color",
			KIT.DANGER if hearts <= 1 else INK_SOFT)
	_refresh_phase()


func _refresh_phase() -> void:
	if _diorama == null or not _diorama.has_method("phase_name"):
		return
	var phase := String(_diorama.call("phase_name"))
	if phase == "" or _phase_label == null:
		return
	var night := phase == "malam"
	_phase_icon.texture = KIT.icon("moon" if night else "sun")
	_phase_label.text = phase.capitalize()


func _on_pause_pressed() -> void:
	if _pause_root == null:
		return
	_refresh_hud()
	_refresh_toggles()
	_show_page(_page_jeda, "Jeda")
	_save_note.text = ""
	_status_label.text = _status_text()
	_pause_root.visible = true
	_pause_root.modulate.a = 0.0
	var sheet := _pause_root.get_node_or_null("Sheet") as Control
	if sheet != null:
		sheet.scale = Vector2(0.96, 0.96)
		sheet.pivot_offset = sheet.size * 0.5
		var st := create_tween()
		st.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		st.set_parallel(true)
		st.tween_property(sheet, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK)
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(_pause_root, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_SINE)
	get_tree().paused = true


## One line of state in the menu, so a player who paused to think can see where
## the run stands without closing the sheet.
func _status_text() -> String:
	if _cast == null or not is_instance_valid(_cast) or not _cast.has_method("hud_state"):
		return ""
	var st: Dictionary = _cast.call("hud_state")
	var phase := ""
	if _diorama != null and _diorama.has_method("phase_name"):
		phase = String(_diorama.call("phase_name")).capitalize()
	return "Orc %d / %d · Nyawa %d / %d · %s" % [
		int(st.get("orcs_defeated", 0)), int(st.get("orcs_total", 3)),
		int(st.get("hearts", 0)), int(st.get("max_hearts", 3)), phase]


func _on_resume_pressed() -> void:
	get_tree().paused = false
	if _pause_root != null:
		var tw := create_tween()
		tw.tween_property(_pause_root, "modulate:a", 0.0, 0.14).set_trans(Tween.TRANS_SINE)
		tw.tween_callback(Callable(_pause_root, "hide"))


## Manual save: same code path as the autosave, so what the button writes is
## exactly what the next boot reads.
func _on_save_pressed() -> void:
	var note := "save tidak tersedia"
	if _cast != null and _cast.has_method("save_now"):
		note = String(_cast.call("save_now"))
	_save_note.text = "Progres tersimpan." if note == "" else "Gagal menyimpan: " + note


func _on_pause_back_pressed() -> void:
	get_tree().paused = false
	if _pause_root != null:
		_pause_root.visible = false
	_on_back_pressed()


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
	# The launcher exports these before changing scene (PackLoader.boot_version).
	# On a phone the fallbacks below are the real paths; they exist so the scene
	# still runs when it is opened directly from the editor or a test.
	var root := OS.get_environment("RT_DATA_ROOT")
	if root == "":
		root = "user://retraveller"
	var version := OS.get_environment("RT_ACTIVE_VERSION")
	if version == "":
		var active := root.path_join("active.json")
		if FileAccess.file_exists(active):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(active))
			if typeof(parsed) == TYPE_DICTIONARY:
				version = String((parsed as Dictionary).get("version", ""))
	if version == "":
		version = "belum ada"
	DirAccess.make_dir_recursive_absolute(root)
	var f := FileAccess.open(root.path_join("boot_ok.json"), FileAccess.WRITE)
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
		if a.begins_with("--menu="):
			var page := String(a.substr("--menu=".length()))
			await get_tree().create_timer(1.6).timeout
			_on_pause_pressed()
			if page == "pengaturan":
				_show_settings()
			await get_tree().create_timer(0.6).timeout
			continue
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
