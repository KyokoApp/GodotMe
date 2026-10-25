extends Control
## The minimap: a small warm-framed map drawn from the world's tile DATA.
##
## Why data and not a second camera: a second viewport is a second full render
## pass on a phone, and the map is a grid of a few hundred tiles. `WorldMap.gd`
## keeps that grid; this control asks it for a bounded window (see
## `render_window`) and adds the markers on top.
##
## Cost control, in order:
##   * the texture is rebuilt only when the player enters a new tile or a fog
##     tile opens - not every frame;
##   * the window is a fixed number of tiles, so a map ten times larger costs the
##     same here (the full map panel is a separate, deliberate build);
##   * markers are a few dozen draw calls at most.
##
## Input, per the brief: one tap opens the full map, a double tap switches
## between the close and wide minimap zoom.

signal map_requested
## Emitted when the zoom level changes, so a test can prove a double tap works.
signal zoom_changed(level: int)

const KIT := preload("res://game/ui/UiKit.gd")

const MAP_SCRIPT := "res://game/world/WorldMap.gd"
## Window widths, in tiles. Close view = 14 m across, wide = 34 m, which is the
## whole starting valley. Both are bounded on purpose.
const TILES_NEAR := 14
const TILES_WIDE := 34
## Pixels per tile in the texture. Chunky is fine - it is a map, not a photo.
const TILE_PX := 4
## Enemies are the only thing that appears and disappears on the map, so they get
## their own shorter range: a minimap that shows every orc in the valley would
## turn exploration into a radar sweep.
const ENEMY_RANGE_M := 7.0

const LEATHER := Color(0.20, 0.15, 0.11)
const BRASS := Color(0.70, 0.55, 0.28)
const CREAM := Color(0.98, 0.94, 0.86)
const GOLD := Color(0.93, 0.78, 0.42)
const ENEMY := Color(0.72, 0.24, 0.18)
const FRIEND := Color(0.98, 0.90, 0.66)
const DOOR := Color(0.66, 0.44, 0.28)

var zoom_level := 1

var _map: RefCounted = null
var _texture: ImageTexture = null
var _image: Image = null
var _revision := -1
var _last_tile := Vector2i(-9999, -9999)
var _player := Vector2.ZERO
var _heading := Vector2(0.0, -1.0)
var _markers: Array = []
var _tap_ms := 0
var _back: Panel


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false
	_back = Panel.new()
	_back.show_behind_parent = true
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back.set_anchors_preset(Control.PRESET_FULL_RECT)
	_back.add_theme_stylebox_override("panel", _frame_style())
	add_child(_back)


func _frame_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = LEATHER
	sb.border_color = BRASS
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(16)
	sb.shadow_color = Color(0.05, 0.03, 0.02, 0.35)
	sb.shadow_size = 4
	return sb


func set_map(map: RefCounted) -> void:
	_map = map
	_revision = -1
	queue_redraw()


func map() -> RefCounted:
	return _map


## Everything the map needs to know about the world right now, once per frame at
## most. Only a change of tile or of the fog rebuilds the texture.
func update_state(player: Vector2, heading: Vector2, markers: Array) -> void:
	_player = player
	if heading.length() > 0.01:
		_heading = heading.normalized()
	_markers = markers
	if _map == null:
		return
	_map.call("reveal", player)
	_map.call("set_sight", player)
	var tile: Vector2i = _map.call("world_to_tile", player)
	if tile != _last_tile or int(_map.get("fog_revision")) != _revision:
		_last_tile = tile
		_rebuild(tile)
	queue_redraw()


## Test hook: force the next draw to rebuild (used after a scripted teleport).
func refresh_now() -> void:
	_revision = -1
	if _map != null:
		var tile: Vector2i = _map.call("world_to_tile", _player)
		_last_tile = tile
		_rebuild(tile)
	queue_redraw()


func _rebuild(tile: Vector2i) -> void:
	var tiles := TILES_NEAR if zoom_level <= 1 else TILES_WIDE
	if _map == null:
		return
	_image = _map.call("render_window", tile, tiles, TILE_PX)
	_revision = int(_map.get("fog_revision"))
	if _texture == null:
		_texture = ImageTexture.create_from_image(_image)
	else:
		_texture.set_image(_image)


func window_tiles() -> int:
	return TILES_NEAR if zoom_level <= 1 else TILES_WIDE


func texture() -> Texture2D:
	return _texture


## The markers currently drawn, for the full map panel (it shows the same cast).
func markers() -> Array:
	return _markers


## Double tap switches the zoom; a single tap opens the full map. The delay is
## short enough that opening the map does not feel laggy and long enough that a
## double tap is not eaten by the full map.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_on_tap()
			accept_event()
	elif event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_on_tap()
			accept_event()


func _on_tap() -> void:
	var now := Time.get_ticks_msec()
	if now - _tap_ms <= 320:
		_tap_ms = 0
		zoom_level = 2 if zoom_level == 1 else 1
		if _map != null:
			_rebuild(_map.call("world_to_tile", _player))
		queue_redraw()
		zoom_changed.emit(zoom_level)
		return
	_tap_ms = now
	# give the double tap a chance before opening the heavy panel
	await get_tree().create_timer(0.33).timeout
	if _tap_ms != now or not is_inside_tree():
		return
	_tap_ms = 0
	map_requested.emit()


# -------------------------------------------------------------------- draw ---
func _draw() -> void:
	var box := _box()
	if _texture == null:
		return
	var tiles := window_tiles()
	var size := Vector2(box.size, box.size)
	# the map image is drawn 1:1 on the box: the window is square, the box is
	# square, so there is no stretching and no half-pixel sampling
	draw_texture_rect(_texture, Rect2(box.position, size), false)
	# a 1 px brass line inside the frame, so the map reads as a chart in a case
	draw_rect(Rect2(box.position - Vector2.ONE, size + Vector2.ONE * 2.0),
		Color(BRASS.r, BRASS.g, BRASS.b, 0.55), false, 1.0)
	_draw_markers(box, tiles)
	_draw_player(box, tiles)


## The square the map occupies inside the frame (the frame is `size`).
func _box() -> Rect2:
	var inset := 8.0
	return Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0)


## World metres -> minimap pixels, relative to the player-centred window.
func _to_box(world: Vector2, box: Rect2, tiles: int) -> Vector2:
	var span_m := float(tiles) * _cell()
	var half := span_m * 0.5
	var rel := world - _player
	return box.position + box.size * 0.5 + Vector2(rel.x, rel.y) / span_m * box.size.y


func _cell() -> float:
	if _map == null:
		return 1.0
	return float(_map.get("cell"))


func _draw_player(box: Rect2, _tiles: int) -> void:
	var at := box.position + box.size * 0.5
	var fwd := _heading
	var side := Vector2(-fwd.y, fwd.x)
	var tip := at + fwd * 7.0
	var back_l := at - fwd * 4.0 + side * 4.0
	var back_r := at - fwd * 4.0 - side * 4.0
	draw_colored_polygon(PackedVector2Array([tip, back_l, back_r]), CREAM)
	draw_polyline(PackedVector2Array([tip + fwd * 1.5, back_l, back_r, tip + fwd * 1.5]),
		Color(0.22, 0.15, 0.09), 1.4)


func _draw_markers(box: Rect2, tiles: int) -> void:
	for raw in _markers:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var m: Dictionary = raw
		var kind := String(m.get("kind", "npc"))
		var world: Variant = m.get("pos", null)
		if world == null:
			continue
		var pos: Vector2 = world
		if kind == "enemy" and pos.distance_to(_player) > ENEMY_RANGE_M:
			continue
		if kind == "quest":
			# the destination lives off the minimap as often as on it; the edge
			# arrow in FieldHud covers that case
			if pos.distance_to(_player) > float(tiles) * _cell() * 0.48:
				continue
		var p := _to_box(pos, box, tiles)
		if not box.grow(2.0).has_point(p):
			continue
		match kind:
			"enemy":
				draw_circle(p, 2.8, ENEMY)
				draw_circle(p, 1.2, Color(0.35, 0.10, 0.06))
			"quest":
				var d := PackedVector2Array([p + Vector2(0, -5), p + Vector2(5, 0),
					p + Vector2(0, 5), p + Vector2(-5, 0)])
				draw_colored_polygon(d, GOLD)
				draw_polyline(_closed(d), Color(0.30, 0.20, 0.08), 1.2)
			"door":
				draw_rect(Rect2(p - Vector2(2.5, 2.5), Vector2(5, 5)), DOOR)
			_:
				draw_circle(p, 2.6, FRIEND)
				draw_circle(p, 1.1, Color(0.30, 0.22, 0.12))


func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var out := points.duplicate()
	if out.size() > 0:
		out.append(out[0])
	return out
