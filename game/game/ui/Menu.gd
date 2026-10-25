extends Control
## The one menu: every panel the player needs lives behind a single parchment
## sheet with tabs, opened from the single button in the top right corner.
##
## Tabs, in the order of the brief: Lanjut, Jurnal, Peta, Inventori, Pengaturan,
## Simpan, Peluncur. Two of them used to be their own buttons on the field
## (Jeda, Peluncur) and one used to be a permanent HUD box (Tujuan) - here they
## are, without costing the valley a single pixel of screen.
##
## The menu does not touch the world. It emits what the player asked for and
## `Main.gd` decides; that is why the same sheet works while the tree is paused.

signal resume_requested
signal save_requested
signal launcher_confirmed
signal map_requested
signal setting_changed(key: String)

const KIT := preload("res://game/ui/UiKit.gd")

const TABS := [
	{"id": "lanjut", "label": "Lanjut", "icon": "arrow_left"},
	{"id": "jurnal", "label": "Jurnal", "icon": "map"},
	{"id": "peta", "label": "Peta", "icon": "map"},
	{"id": "inventori", "label": "Inventori", "icon": "take"},
	{"id": "pengaturan", "label": "Pengaturan", "icon": "gear"},
	{"id": "simpan", "label": "Simpan", "icon": "save"},
	{"id": "peluncur", "label": "Peluncur", "icon": "door"},
]

const SHEET := Vector2(1080.0, 604.0)
const CONTENT := Vector2(1016.0, 372.0)

var _dim: ColorRect
var _sheet: PanelContainer
var _title: Label
var _tab_buttons := {}
var _pages := {}
var _page := ""
var _settings: RefCounted
var _state := {}
var _save_note: Label
var _status: Label
var _journal_objective: Label
var _journal_note: Label
var _journal_hearts: Label
var _journal_progress: Label
var _map_preview: TextureRect
var _map_note: Label
var _value_labels := {}
var _launcher_armed := false
var _launcher_btn: Button
var _launcher_warn: Label
var _map: RefCounted = null
var _tabs_row: HBoxContainer
var _frame: PanelContainer
var _stack: Control


func _ready() -> void:
	visible = false
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_layout()
	resized.connect(_layout)


func _build() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0.06, 0.04, 0.03, 0.66)
	_dim.anchor_right = 1.0
	_dim.anchor_bottom = 1.0
	add_child(_dim)

	_sheet = PanelContainer.new()
	_sheet.name = "Sheet"
	_sheet.add_theme_stylebox_override("panel", KIT.parchment(20, 24, 18))
	# centred in _layout(): the sheet is designed on 1280x720 and a 4:3 phone
	# window is 960x720, where a fixed 1080-wide sheet hangs off both edges
	_sheet.anchor_left = 0.5
	_sheet.anchor_right = 0.5
	_sheet.anchor_top = 0.5
	_sheet.anchor_bottom = 0.5
	add_child(_sheet)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_sheet.add_child(column)

	# --- header: title + close
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	column.add_child(head)
	_title = KIT.label("Jeda", 28, KIT.INK, true)
	head.add_child(_title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	_status = KIT.label("", 15, KIT.INK_SOFT)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(_status)
	var close_btn := Button.new()
	close_btn.name = "Close"
	close_btn.icon = KIT.icon("close")
	close_btn.expand_icon = true
	close_btn.custom_minimum_size = Vector2(KIT.TOUCH_MIN, KIT.TOUCH_MIN)
	for state in ["normal", "hover", "pressed", "focus"]:
		close_btn.add_theme_stylebox_override(state, _tab_style(false))
	close_btn.pressed.connect(func() -> void: resume_requested.emit())
	head.add_child(close_btn)

	# --- tab row
	var tabs := HBoxContainer.new()
	tabs.name = "Tabs"
	_tabs_row = tabs
	tabs.add_theme_constant_override("separation", 6)
	column.add_child(tabs)
	for entry in TABS:
		var id := String(entry["id"])
		var b := Button.new()
		b.name = "Tab_" + id
		b.text = String(entry["label"])
		b.icon = KIT.icon(String(entry["icon"]))
		b.expand_icon = true
		b.add_theme_font_override("font", KIT.font(KIT.FONT_TITLE, 1))
		b.add_theme_font_size_override("font_size", 17)
		b.add_theme_color_override("font_color", KIT.INK)
		b.custom_minimum_size = Vector2(138.0, KIT.TOUCH_MIN)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.toggle_mode = true
		for state in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(state, _tab_style(false))
		b.add_theme_stylebox_override("pressed", _tab_style(true))
		var chosen := id
		b.pressed.connect(func() -> void: show_page(chosen))
		tabs.add_child(b)
		_tab_buttons[id] = b

	# --- content
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _well_style())
	frame.custom_minimum_size = CONTENT
	_frame = frame
	column.add_child(frame)
	var stack := Control.new()
	stack.custom_minimum_size = CONTENT - Vector2(32, 32)
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stack = stack
	frame.add_child(stack)

	_build_page_lanjut(stack)
	_build_page_jurnal(stack)
	_build_page_peta(stack)
	_build_page_inventori(stack)
	_build_page_pengaturan(stack)
	_build_page_simpan(stack)
	_build_page_peluncur(stack)
	show_page("lanjut")


## Fit the parchment to the window: never wider or taller than the screen, and
## never wider than 1120 design px (a sheet that spans a 20:9 phone edge to edge
## stops reading as a sheet). Re-run on every resize.
func _layout() -> void:
	if _sheet == null:
		return
	var vp := size
	if vp.x < 2.0 or vp.y < 2.0:
		var host := get_viewport()
		vp = host.get_visible_rect().size if host != null else Vector2(1280, 720)
		# the first frame can run before the control has been laid out
		size = vp
	var w := minf(SHEET.x, vp.x - 48.0)
	var h := minf(SHEET.y, vp.y - 56.0)
	_sheet.offset_left = -w * 0.5
	_sheet.offset_right = w * 0.5
	_sheet.offset_top = -h * 0.5
	_sheet.offset_bottom = h * 0.5
	_sheet.custom_minimum_size = Vector2.ZERO
	# The seven tabs and the content well were designed on 1280x720. On a 4:3
	# window (960x720) they would be wider than the sheet, so their minimums
	# shrink with it instead of pushing the parchment past the screen edge.
	var inner := w - 76.0
	if _tabs_row != null:
		var each := clampf((inner - 6.0 * float(_tabs_row.get_child_count() - 1))
			/ float(maxi(1, _tabs_row.get_child_count())), 88.0, 138.0)
		for child in _tabs_row.get_children():
			(child as Control).custom_minimum_size = Vector2(each, KIT.TOUCH_MIN)
	if _frame != null:
		_frame.custom_minimum_size = Vector2(maxf(420.0, inner),
			maxf(240.0, h - 210.0))
	if _stack != null:
		_stack.custom_minimum_size = Vector2(maxf(388.0, inner - 32.0),
			maxf(208.0, h - 242.0))


func _tab_style(active: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.62, 0.49, 0.32) if active else Color(0.82, 0.73, 0.56)
	sb.border_color = Color(0.54, 0.40, 0.20)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


func _well_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.77, 0.68, 0.52, 0.55)
	sb.border_color = Color(0.54, 0.40, 0.20, 0.7)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	return sb


## One page: a stack of rows, shown alone. Pages are children of the same
## container, so switching is a visibility flip - no rebuild, no flicker.
func _make_page(parent: Control, id: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "Page_" + id
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 10)
	box.visible = false
	parent.add_child(box)
	_pages[id] = box
	return box


func _build_page_lanjut(parent: Control) -> void:
	var box := _make_page(parent, "lanjut")
	var blurb := KIT.label(
		"Dunia berhenti selagi panel ini terbuka.\n" +
		"Progres tersimpan sendiri setiap beberapa detik, dan sekali lagi saat kau menutup panel ini.",
		17, KIT.INK_SOFT)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(blurb)
	var go := KIT.button("Lanjutkan", Vector2(360.0, KIT.TOUCH_MIN), 20)
	go.pressed.connect(func() -> void: resume_requested.emit())
	box.add_child(go)


func _build_page_jurnal(parent: Control) -> void:
	var box := _make_page(parent, "jurnal")
	var head := KIT.label("TUJUAN AKTIF", 15, KIT.INK_SOFT, true)
	box.add_child(head)
	_journal_objective = KIT.label("—", 22, KIT.INK)
	_journal_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_journal_objective)
	_journal_progress = KIT.label("", 16, KIT.INK_SOFT)
	box.add_child(_journal_progress)
	_journal_hearts = KIT.label("", 16, KIT.INK_SOFT)
	box.add_child(_journal_hearts)
	var rule := ColorRect.new()
	rule.color = Color(0.54, 0.40, 0.20, 0.45)
	rule.custom_minimum_size = Vector2(0, 2)
	box.add_child(rule)
	var note_head := KIT.label("CATATAN PETA", 15, KIT.INK_SOFT, true)
	box.add_child(note_head)
	# The paragraph that used to sit in a box on the field lives here now: it is
	# worth reading once, not worth a third of the screen forever.
	_journal_note = KIT.label("", 17, KIT.INK)
	_journal_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_journal_note)


func _build_page_peta(parent: Control) -> void:
	var box := _make_page(parent, "peta")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(row)
	var well := PanelContainer.new()
	well.add_theme_stylebox_override("panel", _map_well())
	well.custom_minimum_size = Vector2(420, 260)
	row.add_child(well)
	_map_preview = TextureRect.new()
	_map_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_map_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_map_preview.custom_minimum_size = Vector2(400, 240)
	well.add_child(_map_preview)

	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 10)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(side)
	_map_note = KIT.label("", 16, KIT.INK_SOFT)
	_map_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_map_note)
	var open := KIT.button("Peta besar", Vector2(280.0, KIT.TOUCH_MIN), 19)
	open.pressed.connect(func() -> void: map_requested.emit())
	side.add_child(open)


func _map_well() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.10, 0.08)
	sb.border_color = Color(0.54, 0.40, 0.20)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


func _build_page_inventori(parent: Control) -> void:
	var box := _make_page(parent, "inventori")
	var text := KIT.label(
		"Belum ada isi.\nBarang pertama akan muncul di sini, dan tiap kotak memuat satu benda.",
		17, KIT.INK_SOFT)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(text)
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	for i in range(16):
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(96, 96)
		slot.add_theme_stylebox_override("panel", _slot_style())
		var mark := KIT.label("—", 14, Color(0.54, 0.40, 0.20, 0.55))
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slot.add_child(mark)
		grid.add_child(slot)


func _slot_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.72, 0.63, 0.47, 0.45)
	sb.border_color = Color(0.54, 0.40, 0.20, 0.6)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	return sb


func _build_page_pengaturan(parent: Control) -> void:
	var box := _make_page(parent, "pengaturan")
	var grid := VBoxContainer.new()
	grid.add_theme_constant_override("separation", 6)
	box.add_child(grid)
	for row in [
		["quality", "Grafis", "Sedang"],
		["ui_scale", "Ukuran UI", "Sedang"],
		["stick_sensitivity", "Sensitivitas stik", "1,0"],
		["stick_mode", "Stik", "Mengambang"],
		["debug", "Mode debug", "Mati"],
		["show_fps", "Tampilkan FPS", "Mati"],
		["tilt_shift", "Tilt-shift", "Nyala"],
		["shake", "Getar kamera", "Nyala"],
	]:
		grid.add_child(_setting_row(String(row[0]), String(row[1])))
	# The FPS row only appears in debug: a number on screen is a measuring tool,
	# not part of the painting. refresh_values() decides, so the row is not
	# secretly special-cased twice.
	refresh_values()


func _setting_row(key: String, label_text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var name_label := KIT.label(label_text, 17, KIT.INK)
	name_label.custom_minimum_size = Vector2(300, 0)
	row.add_child(name_label)
	var value := KIT.button("—", Vector2(220.0, 56.0), 17)
	value.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	value.pressed.connect(func() -> void: setting_changed.emit(key))
	row.add_child(value)
	_value_labels[key] = value
	return row


func _build_page_simpan(parent: Control) -> void:
	var box := _make_page(parent, "simpan")
	var text := KIT.label(
		"Simpan manual menulis berkas yang sama dengan simpan otomatis, " +
		"lengkap dengan cadangan .bak.",
		17, KIT.INK_SOFT)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(text)
	var save_btn := KIT.button("Simpan sekarang", Vector2(320.0, KIT.TOUCH_MIN), 19)
	save_btn.pressed.connect(func() -> void: save_requested.emit())
	box.add_child(save_btn)
	_save_note = KIT.label("", 17, KIT.INK)
	box.add_child(_save_note)


func _build_page_peluncur(parent: Control) -> void:
	var box := _make_page(parent, "peluncur")
	var text := KIT.label(
		"Kembali ke peluncur akan menutup dunia ini. Progres sudah tersimpan di perangkat.",
		17, KIT.INK_SOFT)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(text)
	_launcher_warn = KIT.label("Butuh dua ketukan: yang pertama meminta konfirmasi.", 15, KIT.INK_SOFT)
	box.add_child(_launcher_warn)
	_launcher_btn = KIT.button("Kembali ke peluncur", Vector2(360.0, KIT.TOUCH_MIN), 19)
	_launcher_btn.pressed.connect(_on_launcher_pressed)
	box.add_child(_launcher_btn)


func _on_launcher_pressed() -> void:
	if not _launcher_armed:
		_launcher_armed = true
		_launcher_btn.text = "Yakin? Ketuk lagi"
		_launcher_warn.text = "Progres disimpan dulu, lalu peluncur dibuka."
		return
	_launcher_armed = false
	_launcher_btn.text = "Kembali ke peluncur"
	_launcher_warn.text = "Butuh dua ketukan: yang pertama meminta konfirmasi."
	launcher_confirmed.emit()


# ------------------------------------------------------------------ public ---
func open(page: String = "lanjut") -> void:
	_layout()
	visible = true
	modulate.a = 0.0
	show_page(page)
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(self, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_SINE)


func close() -> void:
	_launcher_armed = false
	if _launcher_btn != null:
		_launcher_btn.text = "Kembali ke peluncur"
	visible = false


func show_page(id: String) -> void:
	if not _pages.has(id):
		return
	_page = id
	for key in _pages.keys():
		(_pages[key] as Control).visible = key == id
	for key in _tab_buttons.keys():
		var b: Button = _tab_buttons[key]
		b.set_pressed_no_signal(key == id)
	_title.text = "Jeda" if id == "lanjut" else "Jeda · " + String(id).capitalize()
	_refresh_page(id)


func current_page() -> String:
	return _page


func page_node(id: String) -> Control:
	return _pages.get(id)


func set_settings(settings: RefCounted) -> void:
	_settings = settings
	refresh_values()


func set_map(map: RefCounted) -> void:
	_map = map


## Everything the menu prints comes from here; the menu never reaches into the
## world itself.
func set_state(state: Dictionary) -> void:
	_state = state
	_status.text = String(state.get("status", ""))
	_journal_objective.text = String(state.get("objective", "—"))
	_journal_progress.text = "Orc %d / %d · Nyawa %d / %d · %s" % [
		int(state.get("orcs_defeated", 0)), int(state.get("orcs_total", 3)),
		int(state.get("hearts", 3)), int(state.get("max_hearts", 3)),
		String(state.get("phase", ""))]
	_journal_hearts.text = "Waktu bermain %d menit." % int(float(state.get("play_time", 0.0)) / 60.0)
	_journal_note.text = String(state.get("area_note", ""))
	if _page == "peta":
		_refresh_page("peta")


func set_save_note(text: String) -> void:
	if _save_note != null:
		_save_note.text = text


func refresh_values() -> void:
	if _settings == null:
		return
	_set_label("quality", String(_settings.call("quality")).capitalize())
	_set_label("ui_scale", String(_settings.call("get_value", "ui_scale")).capitalize())
	_set_label("stick_sensitivity", "%.1f" % float(_settings.call("stick_sensitivity")))
	_set_label("stick_mode", String(_settings.call("get_value", "stick_mode")).capitalize())
	_set_label("debug", _on_off(bool(_settings.call("debug_enabled"))))
	_set_label("show_fps", _on_off(bool(_settings.call("get_value", "show_fps"))))
	_set_label("tilt_shift", _on_off(bool(_settings.call("get_value", "tilt_shift"))))
	_set_label("shake", _on_off(bool(_settings.call("get_value", "shake"))))
	var fps_button: Button = _value_labels.get("show_fps")
	if fps_button != null:
		var row := fps_button.get_parent()
		if row != null:
			(row as Control).visible = bool(_settings.call("debug_enabled"))


func _on_off(on: bool) -> String:
	return "Nyala" if on else "Mati"


func _set_label(key: String, text: String) -> void:
	var node: Button = _value_labels.get(key)
	if node != null:
		node.text = text


func _refresh_page(id: String) -> void:
	if id == "peta":
		_refresh_map()
	elif id == "pengaturan":
		refresh_values()


func _refresh_map() -> void:
	if _map == null or _map_preview == null:
		return
	if not bool(_map.call("is_ready")):
		return
	var scale: int = _map.call("texture_scale", 260)
	var img: Image = _map.call("render_image", scale)
	_map_preview.texture = ImageTexture.create_from_image(img)
	var explored := float(_map.call("explored_ratio")) * 100.0
	_map_note.text = "Sudah dijelajahi %.0f%%. Area gelap belum pernah kau datangi.\n" % explored
	_map_note.text += "Peta penuh bisa digeser dengan satu jari."


func node_of(name: String) -> Node:
	return find_child(name, true, false)
