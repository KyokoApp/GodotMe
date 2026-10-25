extends CanvasLayer
## Parchment dialogue: portrait, speaker name, typewriter text, and a real branch
## (answers that set story flags and end the conversation differently).
##
## Step 1 made it smaller and quieter, as asked: one low, compact strip at the
## bottom of the screen instead of a tall box, a small framed portrait cropped
## from the speaker's own sprite strip (no new art, and no drawn code portrait),
## and "tap anywhere to continue" instead of a Lanjut button - the strip is
## already the biggest thing on screen, so a separate button adds nothing.
##
## A page is either a plain string (one speaker for the whole conversation) or
## `{speaker, text}` when the knight answers inside the same paragraph flow.

signal closed
signal choice_made(index: int)

const FONT_BODY := "res://game/assets/PixelifySans.woff2"
const FONT_TITLE := "res://game/assets/PixelifySans-SemiBold.woff2"
const PARCH := "res://game/assets/parchment.png"
const INK := Color(0.17, 0.12, 0.09)
const INK_SOFT := Color(0.33, 0.25, 0.18)
const BRASS := Color(0.72, 0.55, 0.28)

const CHARS_PER_SEC := 46.0
## Portrait frame, in design pixels. The sprite frame is square-ish, the frame is
## portrait-shaped, so the texture is kept at aspect and centred.
const PORTRAIT := Vector2(76.0, 96.0)

var is_open := false

var _root: Control
var _panel: PanelContainer
var _portrait_frame: PanelContainer
var _portrait: TextureRect
var _name_label: Label
var _text: Label
var _advance: Label
var _choices: VBoxContainer
var _pages: Array = []
var _options: Array = []
var _index := 0
var _typing := false
var _tween: Tween
var _font_body: Font
var _font_title: Font
var _open_speaker := "?"
var _blink := 0.0
## True while the strip is a name plate ("who is this, and can I talk to him")
## rather than a conversation. See set_line().
var _line_only := false


func _ready() -> void:
	layer = 12
	_font_body = _font(FONT_BODY)
	_font_title = _font(FONT_TITLE, 1)
	_build()
	visible = false


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	# The strip owns the whole screen while it is open: a tap is "continue", and
	# nothing behind the parchment (grass, orc, knight) may react to it.
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(_on_root_input)
	add_child(_root)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", _nine(PARCH, 22, 26, 18))
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -470.0
	_panel.offset_right = 470.0
	# height is measured from content in _fit_panel, then pushed up off the edge
	_panel.offset_top = -190.0
	_panel.offset_bottom = -22.0
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_panel.add_child(row)

	_portrait_frame = PanelContainer.new()
	_portrait_frame.custom_minimum_size = PORTRAIT + Vector2(12, 12)
	_portrait_frame.add_theme_stylebox_override("panel", _portrait_style())
	_portrait_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_portrait_frame)
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = PORTRAIT
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait_frame.add_child(_portrait)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(box)

	_name_label = Label.new()
	_name_label.add_theme_font_override("font", _font_title)
	_name_label.add_theme_font_size_override("font_size", 21)
	_name_label.add_theme_color_override("font_color", BRASS.darkened(0.35))
	box.add_child(_name_label)

	_text = Label.new()
	_text.add_theme_font_override("font", _font_body)
	_text.add_theme_font_size_override("font_size", 20)
	_text.add_theme_color_override("font_color", INK)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(760, 64)
	_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	box.add_child(_text)

	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 6)
	_choices.visible = false
	box.add_child(_choices)

	_advance = Label.new()
	_advance.text = "ketuk untuk lanjut ▸"
	_advance.add_theme_font_override("font", _font_body)
	_advance.add_theme_font_size_override("font_size", 15)
	_advance.add_theme_color_override("font_color", INK_SOFT)
	_advance.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_advance)


func _portrait_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.30, 0.22, 0.15, 0.18)
	sb.border_color = Color(BRASS.r, BRASS.g, BRASS.b, 0.85)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


## Portrait for the speaker, cropped from the character's own strip by
## `CharacterAssets.portrait`. `null` hides the frame instead of showing an
## empty box with a broken border.
func set_portrait(tex: Texture2D) -> void:
	if _portrait == null:
		return
	_portrait.texture = tex
	_portrait_frame.visible = tex != null


## A name plate, not a conversation: the speaker's name, one short greeting and
## his portrait, shown while the knight stands within talking range with nobody
## talking yet. Why it exists: without it the guard's own sprite stands exactly
## where a floating hint would sit, and drawing his name over his head was the
## only thing that made the field HUD look busy. It is also the honest place for
## it - it disappears the moment he is out of reach or a conversation starts.
func set_line(speaker: String, text: String, portrait: Texture2D = null) -> void:
	if is_open:
		return
	if text == "":
		_line_only = false
		_advance.text = ""
		visible = false
		return
	_line_only = true
	visible = true
	_typing = false
	_choices.visible = false
	_clear_choices()
	_name_label.text = speaker
	_text.text = text
	_text.visible_ratio = 1.0
	_advance.text = ""
	set_portrait(portrait)
	_fit_panel()
	_fit_panel_later()


func is_line_only() -> bool:
	return _line_only


func open(speaker: String, pages: Array, options: Array = [], portrait: Texture2D = null) -> void:
	_line_only = false
	_pages = pages.duplicate()
	_options = options.duplicate()
	_index = 0
	is_open = true
	visible = true
	_name_label.text = speaker
	_open_speaker = speaker
	_choices.visible = false
	_clear_choices()
	set_portrait(portrait)
	_type_page()
	_fit_panel()
	_fit_panel_later()


## Size the parchment from what is actually inside it, then slide it up so its
## bottom edge stays 22 px above the screen edge. Called again one frame later,
## because autowrapped text only reports its real height after sorting once.
func _fit_panel() -> void:
	var need: float = _panel.get_combined_minimum_size().y
	if need <= 0.0:
		return
	_panel.offset_top = -(need + 22.0)
	_panel.offset_bottom = -22.0


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
	_advance.text = "ketuk untuk melewati ▸"
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	var secs := maxf(0.3, float(body.length()) / CHARS_PER_SEC)
	_tween.tween_property(_text, "visible_ratio", 1.0, secs)
	_tween.finished.connect(_on_typed)


func _on_typed() -> void:
	_typing = false
	_refresh_footer()


func _refresh_footer() -> void:
	if _typing:
		_advance.text = "ketuk untuk melewati ▸"
		_choices.visible = false
		return
	var last := _index >= _pages.size() - 1
	if last and not _options.is_empty():
		_advance.text = ""
		_show_choices()
		return
	_advance.text = "ketuk untuk menutup ▸" if last else "ketuk untuk lanjut ▸"
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
			b.add_theme_stylebox_override(state, _nine(PARCH, 20, 22, 10))
		# 48 dp: a full-width row, tall enough for a thumb and for the label
		b.custom_minimum_size = Vector2(760, 58)
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
	_pages = [String(opt.get("reply", ""))]
	_options = []
	_index = 0
	_type_page()
	_fit_panel_later()


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
		_fit_panel_later()
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
	_line_only = false
	visible = false
	closed.emit()


## Anywhere on the screen advances - except a tap on an answer row, which the
## button eats before it gets here.
func _on_root_input(event: InputEvent) -> void:
	if not is_open or _line_only:
		return
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		_on_advance()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_on_advance()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event is InputEventKey and (event as InputEventKey).pressed \
			and (event as InputEventKey).keycode in [KEY_SPACE, KEY_ENTER]:
		_on_advance()
		get_viewport().set_input_as_handled()


## The little arrow beside "ketuk untuk lanjut" breathes once it has finished
## typing, so a player who is reading still sees there is more.
func _process(delta: float) -> void:
	if not is_open or _typing or _advance == null:
		return
	_blink += delta
	_advance.modulate.a = 0.65 + 0.35 * absf(sin(_blink * 2.6))


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
