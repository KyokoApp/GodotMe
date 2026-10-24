extends CanvasLayer
## On-screen controls for a phone held in landscape: a large thumb stick on the
## left (small push walks, full push runs) and three thumb buttons on the right
## (attack, hold to block, talk).
##
## Every target is at least 96 px so it can be hit with a thumb without looking.
## The stick is hit-tested by hand instead of relying on Control drag routing,
## because a drag that leaves the stick must keep steering.

signal attack_pressed
signal interact_pressed

const FONT_TITLE := "res://game/assets/PixelifySans-SemiBold.woff2"
const PARCH := "res://game/assets/parchment.png"
const INK := Color(0.17, 0.12, 0.09)
const BRASS := Color(0.74, 0.58, 0.31)

var stick_vector := Vector2.ZERO
var block_held := false
var attack_enabled := true:
	set(value):
		attack_enabled = value
		if _attack_btn != null:
			_attack_btn.disabled = not value
var interact_enabled := true:
	set(value):
		interact_enabled = value
		if _interact_btn != null:
			_interact_btn.disabled = not value

var _base: Panel
var _knob: Panel
var _attack_btn: Button
var _block_btn: Button
var _interact_btn: Button
var _touch_index := -1
var _radius := 78.0


func _ready() -> void:
	layer = 10
	_build()


func _build() -> void:
	var font := _font(FONT_TITLE)

	_base = Panel.new()
	_base.add_theme_stylebox_override("panel", _stick_style())
	_base.anchor_left = 0.0
	_base.anchor_top = 1.0
	_base.anchor_right = 0.0
	_base.anchor_bottom = 1.0
	_base.offset_left = 34.0
	_base.offset_right = 34.0 + 196.0
	_base.offset_top = -230.0
	_base.offset_bottom = -34.0
	_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_base)

	_knob = Panel.new()
	_knob.add_theme_stylebox_override("panel", _knob_style())
	_knob.size = Vector2(80.0, 80.0)
	_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_base.add_child(_knob)
	_knob.position = Vector2(58.0, 58.0)

	_attack_btn = _button("Serang", font, Vector2(140.0, 140.0))
	_attack_btn.anchor_left = 1.0
	_attack_btn.anchor_right = 1.0
	_attack_btn.anchor_top = 1.0
	_attack_btn.anchor_bottom = 1.0
	_attack_btn.offset_left = -186.0
	_attack_btn.offset_right = -46.0
	_attack_btn.offset_top = -186.0
	_attack_btn.offset_bottom = -46.0
	_attack_btn.pressed.connect(func() -> void: attack_pressed.emit())

	_block_btn = _button("Tahan", font, Vector2(120.0, 120.0))
	_block_btn.anchor_left = 1.0
	_block_btn.anchor_right = 1.0
	_block_btn.anchor_top = 1.0
	_block_btn.anchor_bottom = 1.0
	_block_btn.offset_left = -330.0
	_block_btn.offset_right = -210.0
	_block_btn.offset_top = -166.0
	_block_btn.offset_bottom = -46.0
	_block_btn.button_down.connect(_on_block_down)
	_block_btn.button_up.connect(_on_block_up)

	_interact_btn = _button("Bicara", font, Vector2(120.0, 120.0))
	_interact_btn.anchor_left = 1.0
	_interact_btn.anchor_right = 1.0
	_interact_btn.anchor_top = 1.0
	_interact_btn.anchor_bottom = 1.0
	_interact_btn.offset_left = -300.0
	_interact_btn.offset_right = -180.0
	_interact_btn.offset_top = -300.0
	_interact_btn.offset_bottom = -180.0
	_interact_btn.pressed.connect(func() -> void: interact_pressed.emit())


func _button(text: String, font: Font, size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_disabled_color", Color(0.35, 0.30, 0.24, 0.75))
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, _nine(PARCH, 20, 14, 10))
	b.custom_minimum_size = size
	b.size = size
	add_child(b)
	return b


## Screen rects the camera must not treat as a pan gesture.
func block_rects() -> Array:
	var out: Array = []
	for c in [_base, _attack_btn, _block_btn, _interact_btn]:
		if c != null:
			out.append(c.get_global_rect().grow(8.0))
	return out


func _on_block_down() -> void:
	block_held = true


func _on_block_up() -> void:
	block_held = false


func _input(event: InputEvent) -> void:
	if _base == null:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and _touch_index == -1 and _base.get_global_rect().grow(24.0).has_point(t.position):
			_touch_index = t.index
			_steer(t.position)
			get_viewport().set_input_as_handled()
		elif not t.pressed and t.index == _touch_index:
			_touch_index = -1
			_reset()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _touch_index:
			_steer(d.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed and _base.get_global_rect().grow(24.0).has_point(mb.position):
			_touch_index = -2
			_steer(mb.position)
			get_viewport().set_input_as_handled()
		elif not mb.pressed and _touch_index == -2:
			_touch_index = -1
			_reset()
	elif event is InputEventMouseMotion and _touch_index == -2:
		_steer((event as InputEventMouseMotion).position)


func _steer(pos: Vector2) -> void:
	var rect := _base.get_global_rect()
	var centre := rect.position + rect.size * 0.5
	var delta := pos - centre
	if delta.length() > _radius:
		delta = delta.normalized() * _radius
	stick_vector = delta / _radius
	_knob.position = rect.size * 0.5 + delta - _knob.size * 0.5


func _reset() -> void:
	stick_vector = Vector2.ZERO
	if _knob != null and _base != null:
		_knob.position = _base.size * 0.5 - _knob.size * 0.5


func _stick_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.08, 0.06, 0.30)
	sb.border_color = Color(BRASS.r, BRASS.g, BRASS.b, 0.55)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(98)
	return sb


func _knob_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(BRASS.r, BRASS.g, BRASS.b, 0.42)
	sb.border_color = Color(0.98, 0.94, 0.86, 0.55)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(40)
	return sb


func _font(path: String) -> Font:
	var f := FontFile.new()
	if f.load_dynamic_font(path) != OK:
		return ThemeDB.fallback_font
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.hinting = TextServer.HINTING_NONE
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return f


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
