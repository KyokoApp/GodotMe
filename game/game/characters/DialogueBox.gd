extends CanvasLayer
## Parchment dialogue for townsfolk: speaker name, typewriter text, and a real
## branch (answers that set story flags and end the conversation differently).
##
## A page is either a plain string (one speaker for the whole conversation) or
## `{speaker, text}` when the knight answers inside the same paragraph flow - the
## name line follows the page, which is what makes a two-person exchange read
## like a conversation instead of a monologue.
##
## Sized for a phone in landscape: the panel sits low and wide, the advance tap
## covers a large button, and the branch choices are full-width rows.

signal closed
signal choice_made(index: int)

const FONT_BODY := "res://game/assets/PixelifySans.woff2"
const FONT_TITLE := "res://game/assets/PixelifySans-SemiBold.woff2"
const PARCH := "res://game/assets/parchment.png"
const INK := Color(0.17, 0.12, 0.09)
const INK_SOFT := Color(0.33, 0.25, 0.18)
const BRASS := Color(0.72, 0.55, 0.28)

const CHARS_PER_SEC := 42.0

var is_open := false

var _root: Control
var _panel: PanelContainer
var _name_label: Label
var _text: Label
var _advance: Button
var _choices: VBoxContainer
var _pages: Array = []
var _options: Array = []
var _index := 0
var _typing := false
var _tween: Tween
var _font_body: Font
var _font_title: Font
var _open_speaker := "?"


func _ready() -> void:
	layer = 12
	_font_body = _font(FONT_BODY)
	_font_title = _font(FONT_TITLE, 1)
	_build()
	visible = false


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", _nine(PARCH, 22, 30, 22))
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -450.0
	_panel.offset_right = 450.0
	# A fixed height cut the second answer off the screen, and `grow_vertical`
	# alone still let the container overflow downwards. So the height is measured
	# from the content and the top offset is pushed up by exactly that much
	# (`_fit_panel`), which always keeps the panel inside the screen.
	_panel.offset_top = -236.0
	_panel.offset_bottom = -26.0
	_root.add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)

	_name_label = Label.new()
	_name_label.add_theme_font_override("font", _font_title)
	_name_label.add_theme_font_size_override("font_size", 22)
	_name_label.add_theme_color_override("font_color", BRASS.darkened(0.35))
	box.add_child(_name_label)

	_text = Label.new()
	_text.add_theme_font_override("font", _font_body)
	_text.add_theme_font_size_override("font_size", 21)
	_text.add_theme_color_override("font_color", INK)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(860, 92)
	_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	box.add_child(_text)

	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 6)
	_choices.visible = false
	box.add_child(_choices)

	_advance = Button.new()
	_advance.text = "Lanjut"
	_advance.add_theme_font_override("font", _font_title)
	_advance.add_theme_font_size_override("font_size", 18)
	_advance.add_theme_color_override("font_color", INK)
	for state in ["normal", "hover", "pressed", "focus"]:
		_advance.add_theme_stylebox_override(state, _nine(PARCH, 20, 18, 8))
	_advance.custom_minimum_size = Vector2(160, 44)
	_advance.size_flags_horizontal = Control.SIZE_SHRINK_END
	_advance.pressed.connect(_on_advance)
	box.add_child(_advance)


func open(speaker: String, pages: Array, options: Array = []) -> void:
	_pages = pages.duplicate()
	_options = options.duplicate()
	_index = 0
	is_open = true
	visible = true
	_name_label.text = speaker
	_open_speaker = speaker
	_choices.visible = false
	_clear_choices()
	_type_page()
	_fit_panel()


## Size the parchment from what is actually inside it, then slide it up so its
## bottom edge stays 26 px above the screen edge. Called again one frame later,
## because autowrapped text and freshly added buttons only report their real
## height after the container has sorted them once.
func _fit_panel() -> void:
	var need: float = _panel.get_combined_minimum_size().y
	if need <= 0.0:
		return
	_panel.offset_top = -(need + 26.0)
	_panel.offset_bottom = -26.0


func _fit_panel_later() -> void:
	call_deferred("_fit_panel")


func _type_page() -> void:
	if _index >= _pages.size():
		_close()
		return
	var page: Variant = _pages[_index]
	var body := ""
	if typeof(page) == TYPE_DICTIONARY:
		body = String((page as Dictionary).get("text", ""))
		_name_label.text = String((page as Dictionary).get("speaker", _name_label.text))
	else:
		body = String(page)
		if _open_speaker != "":
			_name_label.text = _open_speaker
	_text.text = body
	_text.visible_ratio = 0.0
	_typing = true
	_advance.text = "Lewati"
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	var secs := maxf(0.35, float(body.length()) / CHARS_PER_SEC)
	_tween.tween_property(_text, "visible_ratio", 1.0, secs)
	_tween.finished.connect(_on_typed)


func _on_typed() -> void:
	_typing = false
	_refresh_footer()


func _refresh_footer() -> void:
	if _typing:
		_advance.text = "Lewati"
		_choices.visible = false
		return
	var last := _index >= _pages.size() - 1
	if last and not _options.is_empty():
		_advance.visible = false
		_show_choices()
		return
	_advance.visible = true
	_advance.text = "Selesai" if last else "Lanjut"
	_fit_panel_later()


func _show_choices() -> void:
	_clear_choices()
	_choices.visible = true
	for i in range(_options.size()):
		var opt: Dictionary = _options[i]
		var b := Button.new()
		b.text = String(opt.get("label", "…"))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_override("font", _font_body)
		b.add_theme_font_size_override("font_size", 19)
		b.add_theme_color_override("font_color", INK_SOFT)
		for state in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(state, _nine(PARCH, 20, 22, 8))
		b.custom_minimum_size = Vector2(860, 40)
		var idx := i
		b.pressed.connect(func() -> void: _on_choice(idx))
		_choices.add_child(b)
	_fit_panel()
	_fit_panel_later()


func _clear_choices() -> void:
	for child in _choices.get_children():
		child.queue_free()


func _on_choice(index: int) -> void:
	var opt: Dictionary = _options[index]
	choice_made.emit(index)
	_choices.visible = false
	_advance.visible = true
	_pages = [String(opt.get("reply", ""))]
	_options = []
	_index = 0
	_type_page()


func _on_advance() -> void:
	if _typing:
		if _tween != null and _tween.is_valid():
			_tween.kill()
		_text.visible_ratio = 1.0
		_typing = false
		_refresh_footer()
		return
	if _index + 1 < _pages.size():
		_index += 1
		_type_page()
		return
	_close()


## Public advance, so a test (or a future keyboard binding) steps the page the
## same way a tap on the parchment does.
func advance() -> void:
	_on_advance()


## Jump to the end of the conversation where the branches are offered, so a
## single screenshot can prove the fork exists without scripting taps.
func jump_to_choices() -> void:
	if _pages.is_empty() or _options.is_empty():
		return
	_index = _pages.size() - 1
	_type_page()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_text.visible_ratio = 1.0
	_typing = false
	_refresh_footer()


## What the player currently reads, for tests and for the capture log.
func current_text() -> String:
	return _text.text if _text != null else ""


func _close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		var t := event as InputEventScreenTouch
		# a tap anywhere above the panel advances; the panel itself is handled
		# by its own buttons so a finger on a choice does not skip the text
		if t.position.y < _panel.get_global_rect().position.y:
			_on_advance()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and (event as InputEventKey).pressed \
			and (event as InputEventKey).keycode in [KEY_SPACE, KEY_ENTER]:
		_on_advance()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- helpers ----
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
	return v


func _nine(path: String, margin: int, mx: int, my: int) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	if FileAccess.file_exists(path):
		var img := Image.new()
		if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK:
			sb.texture = ImageTexture.create_from_image(img)
	sb.set_texture_margin_all(margin)
	sb.content_margin_left = mx
	sb.content_margin_right = mx
	sb.content_margin_top = my
	sb.content_margin_bottom = my
	return sb
