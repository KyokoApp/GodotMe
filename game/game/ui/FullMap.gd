extends Control
## The full map: the same tile data as the minimap, drawn larger, on parchment,
## and draggable. Deliberately simple - step 2 grows the world, and this panel
## grows with it because it asks the map for a whole-image render instead of
## knowing the valley's size.
##
## Opened from a tap on the minimap or from the menu's Peta tab. Closed with the
## brass cross, the same way the menu closes.

signal closed

const KIT := preload("res://game/ui/UiKit.gd")

const LEATHER := Color(0.20, 0.15, 0.11)
const BRASS := Color(0.70, 0.55, 0.28)
const CREAM := Color(0.98, 0.94, 0.86)
const GOLD := Color(0.93, 0.78, 0.42)
const FRIEND := Color(0.98, 0.90, 0.66)
const ENEMY := Color(0.72, 0.24, 0.18)

var is_open := false

var _dim: ColorRect
var _sheet: PanelContainer
var _title: Label
var _viewport: Control
var _chart: TextureRect
var _close_btn: Button
var _hint: Label
var _dragging := false
var _drag_from := Vector2.ZERO
var _chart_home := Vector2.ZERO
var _factor := 1.0
var _image: Image
var _player := Vector2.ZERO
var _markers: Array = []
var _map: RefCounted = null


func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	_dim = ColorRect.new()
	_dim.color = Color(0.06, 0.04, 0.03, 0.72)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	_sheet = PanelContainer.new()
	_sheet.add_theme_stylebox_override("panel", KIT.parchment(20, 18, 16))
	_sheet.set_anchors_preset(Control.PRESET_CENTER)
	_sheet.custom_minimum_size = Vector2(880, 600)
	_sheet.size = Vector2(880, 600)
	# centred by hand: PRESET_CENTER anchors the top-left corner to the middle
	_sheet.anchor_left = 0.5
	_sheet.anchor_right = 0.5
	_sheet.anchor_top = 0.5
	_sheet.anchor_bottom = 0.5
	_sheet.offset_left = -440
	_sheet.offset_right = 440
	_sheet.offset_top = -300
	_sheet.offset_bottom = 300
	add_child(_sheet)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_sheet.add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	box.add_child(head)
	_title = KIT.label("Peta", 26, KIT.INK, true)
	head.add_child(_title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	_close_btn = Button.new()
	_close_btn.icon = KIT.icon("close")
	_close_btn.expand_icon = true
	_close_btn.custom_minimum_size = Vector2(KIT.TOUCH_MIN, KIT.TOUCH_MIN)
	_close_btn.add_theme_stylebox_override("normal", _button_style())
	_close_btn.add_theme_stylebox_override("hover", _button_style())
	_close_btn.add_theme_stylebox_override("pressed", _button_style())
	_close_btn.pressed.connect(close_panel)
	head.add_child(_close_btn)

	_viewport = Control.new()
	_viewport.clip_contents = true
	_viewport.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_viewport.custom_minimum_size = Vector2(840, 470)
	_viewport.mouse_filter = Control.MOUSE_FILTER_STOP
	var vp_style := StyleBoxFlat.new()
	vp_style.bg_color = LEATHER
	vp_style.border_color = BRASS
	vp_style.set_border_width_all(3)
	vp_style.set_corner_radius_all(8)
	_viewport.add_theme_stylebox_override("panel", vp_style)
	box.add_child(_viewport)

	_chart = TextureRect.new()
	_chart.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_chart.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_chart.stretch_mode = TextureRect.STRETCH_SCALE
	_chart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport.add_child(_chart)

	_hint = KIT.label("Geser untuk menjelajah peta. Ketuk ✕ untuk menutup.", 15, KIT.INK_SOFT)
	box.add_child(_hint)


func _button_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.86, 0.78, 0.62)
	sb.border_color = BRASS
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


## Build the chart from the map. One image render, once per opening: this is the
## only place in the UI that pays for a whole-map texture.
func open_panel(map: RefCounted, player: Vector2, markers: Array = []) -> void:
	_map = map
	_player = player
	_markers = markers
	if map == null or not bool(map.call("is_ready")):
		return
	var scale: int = map.call("texture_scale", 300)
	_image = map.call("render_image", scale)
	_chart.texture = ImageTexture.create_from_image(_image)
	_title.text = String(map.get("label")) if String(map.get("label")) != "" else "Peta"
	var vsize := Vector2(840, 470)
	var factor := minf(vsize.x / float(_image.get_width()), vsize.y / float(_image.get_height()))
	_factor = maxf(1.0, factor)
	_chart.size = Vector2(_image.get_width(), _image.get_height()) * _factor
	_chart_home = (vsize - _chart.size) * 0.5
	_chart.position = _chart_home
	visible = true
	is_open = true
	queue_redraw()
	print("[UI] peta penuh %dx%d px, faktor %.2f, jelajah %.0f%%" % [
		_image.get_width(), _image.get_height(), _factor,
		float(map.call("explored_ratio")) * 100.0])


func close_panel() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	closed.emit()


func _gui_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		_dragging = t.pressed
		_drag_from = t.position
		accept_event()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if _dragging:
			_move_chart((d.position - _drag_from))
			_drag_from = d.position
			accept_event()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		_dragging = mb.pressed
		_drag_from = mb.position
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_move_chart(mm.relative)


func _move_chart(delta: Vector2) -> void:
	var want := _chart.position + delta
	var room := _chart.size - Vector2(840, 470)
	# clamped so the chart can never be dragged out of its case
	want.x = clampf(want.x, minf(0.0, room.x), maxf(0.0, room.x))
	want.y = clampf(want.y, minf(0.0, room.y), maxf(0.0, room.y))
	_chart.position = want
	queue_redraw()


func _draw() -> void:
	if not is_open or _image == null or _map == null:
		return
	var origin := _viewport.get_global_rect().position - get_global_rect().position
	var cell := float(_map.get("cell"))
	var tiles := Vector2(float(_map.get("width")), float(_map.get("height"))) * cell
	var map_origin: Vector2 = _map.call("bounds").position
	var span := _chart.size / maxf(1.0, tiles.x)
	for raw in _markers:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var m: Dictionary = raw
		var pos: Vector2 = m.get("pos", Vector2.ZERO)
		var local := (pos - map_origin) * span + _chart.position + origin
		if not Rect2(origin, Vector2(840, 470)).has_point(local):
			continue
		match String(m.get("kind", "")):
			"enemy":
				draw_circle(local, 4.0, ENEMY)
			"quest":
				draw_circle(local, 4.5, GOLD)
			"door":
				draw_rect(Rect2(local - Vector2(3, 3), Vector2(6, 6)), Color(0.55, 0.36, 0.22))
			_:
				draw_circle(local, 3.5, FRIEND)
	var mine := (_player - map_origin) * span + _chart.position + origin
	draw_circle(mine, 4.5, CREAM)
	draw_arc(mine, 8.0, 0.0, TAU, 20, Color(0.22, 0.15, 0.09), 1.5)
