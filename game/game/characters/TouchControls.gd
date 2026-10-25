extends CanvasLayer
## The joystick. Nothing else.
##
## Step 1 moved every button off the field HUD: the attack and shield buttons are
## gone (the game is turn-based and the battle system is not built yet), and the
## single contextual action lives in `FieldHud`. What is left on the left thumb
## is one virtual stick - the only control the world needs while walking.
##
## The stick is *floating* by default: it appears wherever the thumb lands in the
## left half and disappears on release, because a stick pinned to one spot makes
## the player look down and hunt for it. The player who prefers a fixed stick can
## choose it in Pengaturan; then it always sits in the corner and the same zone
## around it steers.
##
## Feel is data, not taste baked into code: DEAD_ZONE and CURVE are constants, and
## the player's "sensitivitas stik" multiplies the result. Both are per-device,
## never per-save.

signal stick_changed(vector: Vector2)

const FONT_TITLE := "res://game/assets/PixelifySans-SemiBold.woff2"
const BRASS := Color(0.74, 0.58, 0.31)

const STICK_SIZE := 196.0
const STICK_RADIUS := 78.0
## 12 % of the radius is ignored, so a resting thumb does not creep.
const DEAD_ZONE := 0.12
## Response curve: <1 is eager at the start, >1 is gentle. 0.85 keeps small
## pushes useful without making the walk twitchy.
const CURVE := 0.85
## The left share of the screen that belongs to the stick. Any single finger
## there steers and never touches the camera (the camera ignores one finger
## entirely now, so the two can never fight).
const STICK_ZONE_X := 0.55
const STICK_ZONE_Y := 0.15

var stick_vector := Vector2.ZERO
var fixed_mode := false:
	set(value):
		fixed_mode = value
		if _base != null:
			if value and visible:
				_place_fixed()
			elif not value:
				_reset()

var _base: Panel
var _knob: Panel
var _touch_index := -1
var _sensitivity := 1.0


func _ready() -> void:
	layer = 10
	_build()


func _build() -> void:
	_base = Panel.new()
	_base.add_theme_stylebox_override("panel", _stick_style())
	_base.size = Vector2(STICK_SIZE, STICK_SIZE)
	_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_base.visible = false
	add_child(_base)

	_knob = Panel.new()
	_knob.add_theme_stylebox_override("panel", _knob_style())
	_knob.size = Vector2(80.0, 80.0)
	_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_base.add_child(_knob)
	_knob.position = Vector2(STICK_SIZE, STICK_SIZE) * 0.5 - _knob.size * 0.5
	if fixed_mode:
		_place_fixed()


## Hide the whole pad while a conversation or the menu is open: a stray drag on a
## hidden stick must not walk the knight behind the parchment.
func show_controls(shown: bool) -> void:
	visible = shown
	_base.visible = false
	_knob.visible = false
	if not shown:
		stick_vector = Vector2.ZERO
		_touch_index = -1
	elif fixed_mode:
		_place_fixed()


func set_sensitivity(value: float) -> void:
	_sensitivity = clampf(value, 0.5, 1.6)


## Rect of the thumb area, in screen pixels.
func stick_zone() -> Rect2:
	var vp := get_viewport().get_visible_rect().size
	return Rect2(0.0, vp.y * STICK_ZONE_Y, vp.x * STICK_ZONE_X,
		vp.y * (1.0 - STICK_ZONE_Y))


## Screen rect the stick occupies, so other systems can avoid it.
func stick_rect() -> Rect2:
	if _base == null or not _base.visible:
		return Rect2()
	return _base.get_global_rect()


func _input(event: InputEvent) -> void:
	if _base == null or not visible:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and _touch_index == -1 and stick_zone().has_point(t.position):
			_touch_index = t.index
			if not fixed_mode:
				_place_stick(t.position)
			_base.visible = true
			_knob.visible = true
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
		if mb.pressed and _touch_index == -1 and stick_zone().has_point(mb.position):
			_touch_index = -2
			if not fixed_mode:
				_place_stick(mb.position)
			_base.visible = true
			_knob.visible = true
			_steer(mb.position)
			get_viewport().set_input_as_handled()
		elif not mb.pressed and _touch_index == -2:
			_touch_index = -1
			_reset()
	elif event is InputEventMouseMotion and _touch_index == -2:
		_steer((event as InputEventMouseMotion).position)


## Put the stick under the thumb, pushed inside the screen edges so it is never
## half off-screen near a corner.
func _place_stick(pos: Vector2) -> void:
	var vp := get_viewport().get_visible_rect().size
	var half := Vector2(STICK_SIZE, STICK_SIZE) * 0.5
	var centre := Vector2(
		clampf(pos.x, half.x + 16.0, vp.x - half.x - 16.0),
		clampf(pos.y, half.y + 16.0, vp.y - half.y - 16.0))
	_base.position = centre - half
	_knob.position = Vector2(STICK_SIZE, STICK_SIZE) * 0.5 - _knob.size * 0.5


## The resting place of a fixed stick: bottom left, a thumb's width from the edge.
func _place_fixed() -> void:
	var vp := get_viewport().get_visible_rect().size
	_base.position = Vector2(28.0, vp.y - STICK_SIZE - 34.0)
	_knob.position = Vector2(STICK_SIZE, STICK_SIZE) * 0.5 - _knob.size * 0.5
	_base.visible = true
	_knob.visible = true


func _steer(pos: Vector2) -> void:
	var centre := _base.position + Vector2(STICK_SIZE, STICK_SIZE) * 0.5
	var delta := pos - centre
	if delta.length() > STICK_RADIUS:
		delta = delta.normalized() * STICK_RADIUS
	var raw := delta / STICK_RADIUS
	stick_vector = _shape(raw)
	_knob.position = Vector2(STICK_SIZE, STICK_SIZE) * 0.5 + delta - _knob.size * 0.5
	stick_changed.emit(stick_vector)


## Dead zone, then response curve, then the player's sensitivity. Written as one
## function so "the stick feels wrong" is a single place to look.
func _shape(raw: Vector2) -> Vector2:
	var magnitude := raw.length()
	if magnitude <= DEAD_ZONE:
		return Vector2.ZERO
	var shaped := (magnitude - DEAD_ZONE) / (1.0 - DEAD_ZONE)
	shaped = pow(shaped, CURVE) * _sensitivity
	shaped = clampf(shaped, 0.0, 1.0)
	return raw.normalized() * shaped


func _reset() -> void:
	stick_vector = Vector2.ZERO
	if fixed_mode:
		_base.visible = true
		_knob.visible = true
		_knob.position = Vector2(STICK_SIZE, STICK_SIZE) * 0.5 - _knob.size * 0.5
		return
	_base.visible = false
	_knob.visible = false


func _stick_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.08, 0.06, 0.22)
	sb.border_color = Color(BRASS.r, BRASS.g, BRASS.b, 0.45)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(98)
	return sb


func _knob_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(BRASS.r, BRASS.g, BRASS.b, 0.36)
	sb.border_color = Color(0.98, 0.94, 0.86, 0.45)
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
