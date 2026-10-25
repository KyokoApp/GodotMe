extends Control
## The field HUD: as close to empty as the game can honestly get.
##
## What is on screen while walking, and nothing else:
##   * minimap, top left, with the hour of the day tucked under it (no text box);
##   * one menu button, top right;
##   * one contextual action button, bottom right, which fades away when there is
##     nothing to act on;
##   * a place banner for three seconds when you arrive somewhere;
##   * a quest marker at the screen edge when the destination is off screen.
##
## Everything the old HUD carried - the objective box, the hearts, the narrative
## paragraph, the FPS line - is gone from here on purpose. Hearts and progress
## live in the menu now (Jurnal), the FPS counter only appears when debug is on,
## and the joystick + dialogue belong to the cast.
##
## This control never decides anything about the world: Main (and the cast) push
## state in, signals go out.

signal menu_pressed
signal action_pressed

const KIT := preload("res://game/ui/UiKit.gd")
const MINIMAP_SCRIPT := "res://game/ui/Minimap.gd"
const FULLMAP_SCRIPT := "res://game/ui/FullMap.gd"

const LEATHER := Color(0.20, 0.15, 0.11)
const LEATHER_SOFT := Color(0.28, 0.21, 0.15)
const BRASS := Color(0.70, 0.55, 0.28)
const CREAM := Color(0.98, 0.94, 0.86)
const GOLD := Color(0.93, 0.78, 0.42)
const INK := Color(0.17, 0.12, 0.09)

## The minimap takes a fifth of the screen height, as asked: big enough to read
## the path, small enough that the valley still owns the frame.
const MINIMAP_SHARE := 0.20
const BANNER_SEC := 3.0
## A destination closer than this is "here": no arrow needed.
const MARKER_MIN_M := 1.2

var _minimap: Control
var _fullmap: Control
var _menu_btn: Button
var _action_btn: Button
var _action_icon: TextureRect
var _action_label: Label
var _banner: PanelContainer
var _banner_title: Label
var _banner_sub: Label
var _phase_icon: TextureRect
var _phase_label: Label
var _fps_label: Label
var _action_shown := false
var _action_kind := ""
var _banner_tween: Tween
var _quest := Vector2.ZERO
var _has_quest := false
var _player := Vector2.ZERO
var _insets := Vector2.ZERO
var _scale_factor := 1.0
var _fps_timer := 0.0
var _marker_dirty := true


func _ready() -> void:
	# Anchors are written out instead of `set_anchors_preset`: this control lives
	# directly inside a CanvasLayer, with no Control parent, and `preset` alone
	# left it as a fixed 1280x720 rect at (0,0). On a 4:3 window (or with "ukuran
	# UI" above 1,0, which scales the whole layer around the screen centre) the
	# Menu button and the map then slid off the right edge. Four numbers cost
	# nothing and cannot drift.
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_minimap()
	_build_menu_button()
	_build_action_button()
	_build_banner()
	_build_fullmap()
	# The window can change under us (rotation, 16:9 vs 20:9 vs 4:3 windows, the
	# phone's own resize): every corner has to be re-anchored, not just once at
	# boot, or the minimap ends up half off screen on a wider screen.
	resized.connect(func() -> void: apply_safe_area(_insets))


# ------------------------------------------------------------------- layout ---
## Notch/rounded-corner guard, in design pixels. `Main` used to carry a private
## copy of this; the HUD needs it more (it owns the corners now).
##
## `insets` is the left/top inset; the same amount is reserved on the right and
## bottom. On a phone in landscape the notch sits on one short edge and the
## rounded corner on the other, and both are within a few pixels of each other,
## so reserving the same margin on all four sides is both simpler and safer than
## four separate numbers that could disagree.
func apply_safe_area(insets: Vector2) -> void:
	_insets = insets
	var vp := size
	if vp.x <= 1.0:
		vp = Vector2(1280, 720)
	if _minimap != null:
		var side := clampf(vp.y * MINIMAP_SHARE, 108.0, 196.0)
		_minimap.size = Vector2(side, side)
		_minimap.position = Vector2(20.0 + insets.x, 18.0 + insets.y)
	_place_phase()
	if _menu_btn != null:
		_menu_btn.size = Vector2(196.0, KIT.TOUCH_MIN)
		_menu_btn.position = Vector2(vp.x - 196.0 - 22.0 - insets.x, 18.0 + insets.y)
	if _action_btn != null:
		_action_btn.size = Vector2(KIT.TOUCH_BIG, KIT.TOUCH_BIG)
		_action_btn.position = Vector2(vp.x - KIT.TOUCH_BIG - 26.0 - insets.x,
			vp.y - KIT.TOUCH_BIG - 26.0 - insets.y)
	if _banner != null:
		_banner.position = Vector2(vp.x * 0.5 - 260.0, 16.0 + insets.y)
		_banner.size = Vector2(520.0, 0.0)
	_marker_dirty = true
	queue_redraw()


func apply_ui_scale(factor: float) -> void:
	_scale_factor = factor
	KIT.apply_layer_scale(_layer_of(self), factor, _viewport_size())
	apply_safe_area(_insets)


func _viewport_size() -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return Vector2(1280, 720)
	return vp.get_visible_rect().size


func _layer_of(node: Node) -> CanvasLayer:
	if node is CanvasLayer:
		return node as CanvasLayer
	var parent := node.get_parent()
	return null if parent == null else _layer_of(parent)


# ---------------------------------------------------------------- minimap -----
func _build_minimap() -> void:
	_minimap = (load(MINIMAP_SCRIPT) as Script).new()
	_minimap.name = "Minimap"
	add_child(_minimap)
	_minimap.set("mouse_filter", Control.MOUSE_FILTER_STOP)
	_minimap.connect("map_requested", Callable(self, "open_map"))

	_phase_icon = KIT.icon_rect("sun", 26.0)
	_phase_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_phase_icon)
	_phase_label = KIT.label("Sore", 15, CREAM)
	_phase_label.add_theme_color_override("font_shadow_color", Color(0.05, 0.03, 0.02, 0.9))
	_phase_label.add_theme_constant_override("shadow_outline_size", 4)
	_phase_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_phase_label)


func _place_phase() -> void:
	if _minimap == null or _phase_icon == null:
		return
	var at := _minimap.position + Vector2(0.0, _minimap.size.y + 8.0)
	_phase_icon.position = at
	_phase_label.position = at + Vector2(32.0, 3.0)


func minimap() -> Control:
	return _minimap


func set_map(map: RefCounted) -> void:
	if _minimap != null:
		_minimap.call("set_map", map)
	if _fullmap != null:
		_fullmap.set("_map", map)


## Hour of the day, as an icon and one word. No panel: the brief asks for the
## icon to sit on the world, not in another box.
func set_phase(icon_name: String, label_text: String) -> void:
	if _phase_icon == null:
		return
	_phase_icon.texture = KIT.icon(icon_name)
	_phase_label.text = label_text.capitalize()


# ------------------------------------------------------------------- menu -----
func _build_menu_button() -> void:
	_menu_btn = Button.new()
	_menu_btn.name = "MenuButton"
	_menu_btn.text = "  Menu"
	_menu_btn.icon = KIT.icon("gear")
	_menu_btn.expand_icon = true
	_menu_btn.add_theme_font_override("font", KIT.font(KIT.FONT_TITLE, 2))
	_menu_btn.add_theme_font_size_override("font_size", 20)
	_menu_btn.add_theme_color_override("font_color", CREAM)
	_menu_btn.add_theme_color_override("font_hover_color", CREAM)
	_menu_btn.add_theme_color_override("font_pressed_color", GOLD)
	for state in ["normal", "hover", "pressed", "focus"]:
		_menu_btn.add_theme_stylebox_override(state, _chip_style())
	_menu_btn.pressed.connect(func() -> void: menu_pressed.emit())
	add_child(_menu_btn)


func menu_button() -> Button:
	return _menu_btn


## Round leather chip with a brass rim: the one small button shape in the field,
## so the menu and the action button read as the same family.
func _chip_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(LEATHER.r, LEATHER.g, LEATHER.b, 0.88)
	sb.border_color = Color(BRASS.r, BRASS.g, BRASS.b, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


# ----------------------------------------------------------------- action -----
func _build_action_button() -> void:
	_action_btn = Button.new()
	_action_btn.name = "ActionButton"
	_action_btn.custom_minimum_size = Vector2(KIT.TOUCH_BIG, KIT.TOUCH_BIG)
	_action_btn.size = _action_btn.custom_minimum_size
	_action_btn.focus_mode = Control.FOCUS_NONE
	var pad := _chip_style()
	pad.set_corner_radius_all(66)
	pad.bg_color = Color(LEATHER.r, LEATHER.g, LEATHER.b, 0.92)
	pad.set_border_width_all(3)
	var down := pad.duplicate() as StyleBoxFlat
	down.bg_color = Color(LEATHER_SOFT.r, LEATHER_SOFT.g, LEATHER_SOFT.b, 0.95)
	for state in ["normal", "hover", "focus"]:
		_action_btn.add_theme_stylebox_override(state, pad)
	_action_btn.add_theme_stylebox_override("pressed", down)
	_action_btn.pressed.connect(func() -> void: action_pressed.emit())
	add_child(_action_btn)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_action_btn.add_child(column)

	_action_icon = KIT.icon_rect("talk", 52.0)
	_action_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_action_icon)

	_action_label = KIT.label("Bicara", 18, CREAM, true)
	_action_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_action_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_action_label)
	_action_btn.modulate.a = 0.0
	_action_btn.visible = false


func _flat() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()


## The single contextual button. `kind` is one of talk / door / inspect / take;
## anything else hides it. Hidden means faded out and untouchable, never a grey
## lump sitting there.
func set_action(kind: String, label_text: String) -> void:
	if _action_btn == null:
		return
	if kind == "":
		hide_action()
		return
	if kind == _action_kind and _action_shown:
		_action_label.text = label_text
		return
	_action_kind = kind
	_action_icon.texture = KIT.icon(kind if KIT.ICONS.has(kind) else "inspect")
	_action_label.text = label_text
	if not _action_shown:
		_action_shown = true
		_action_btn.visible = true
		_action_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		var tw := create_tween()
		tw.tween_property(_action_btn, "modulate:a", 1.0, 0.16)
	else:
		_action_btn.modulate.a = 1.0


func hide_action() -> void:
	if _action_btn == null or not _action_shown:
		return
	_action_shown = false
	_action_kind = ""
	_action_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween()
	tw.tween_property(_action_btn, "modulate:a", 0.0, 0.18)
	tw.tween_callback(func() -> void: _action_btn.visible = false)


func action_visible() -> bool:
	return _action_btn != null and _action_shown


func action_kind() -> String:
	return _action_kind


func action_rect() -> Rect2:
	if _action_btn == null:
		return Rect2()
	return _action_btn.get_global_rect()


# ----------------------------------------------------------------- banner -----
func _build_banner() -> void:
	_banner = PanelContainer.new()
	_banner.add_theme_stylebox_override("panel", KIT.parchment(20, 26, 14))
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.modulate.a = 0.0
	_banner.visible = false
	add_child(_banner)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	_banner.add_child(box)

	_banner_title = KIT.label("Lembah Senja", 30, INK, true)
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_banner_title)

	_banner_sub = KIT.label("Yaros, awal perjalanan", 16, KIT.INK_SOFT)
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_banner_sub)


## Show the place name for three seconds: slide in from above, wait, fade out.
## It is the only big parchment on the field, and it is gone before the player
## starts walking.
func show_banner(title: String, subtitle: String) -> void:
	if _banner == null:
		return
	_banner_title.text = title
	_banner_sub.text = subtitle
	_banner.visible = true
	_banner.modulate.a = 0.0
	var vp := _viewport_size()
	var home := Vector2(vp.x * 0.5 - _banner.size.x * 0.5, 16.0 + _insets.y)
	_banner.position = home - Vector2(0.0, 18.0)
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_banner_tween.set_parallel(true)
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.35)
	_banner_tween.tween_property(_banner, "position", home, 0.40).set_trans(Tween.TRANS_SINE)
	_banner_tween.set_parallel(false)
	# settle the size first: the parchment must be centred on the text it holds
	_banner_tween.tween_callback(Callable(self, "_centre_banner"))
	_banner_tween.tween_interval(BANNER_SEC)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.5)
	_banner_tween.tween_callback(func() -> void: _banner.visible = false)


## Take the place banner away at once. Used by the capture harness (a shot of
## "walking" should show the empty field, not three seconds of title card).
func dismiss_banner() -> void:
	if _banner == null:
		return
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner.visible = false
	_banner.modulate.a = 0.0


func _centre_banner() -> void:
	if _banner == null:
		return
	var vp := _viewport_size()
	_banner.size.x = maxf(_banner.size.x, _banner.get_combined_minimum_size().x)
	_banner.position.x = vp.x * 0.5 - _banner.size.x * 0.5


func banner_visible() -> bool:
	return _banner != null and _banner.visible and _banner.modulate.a > 0.05


# ------------------------------------------------------------------- quest ----
## Told where the current objective is, in world XZ. The HUD decides how to show
## it: a small mark on the spot when it is on screen, a brass arrow on the rim
## when it is not.
func set_quest_target(pos: Vector2, has_target: bool = true) -> void:
	_quest = pos
	_has_quest = has_target
	_marker_dirty = true


## Feed the map and the edge marker: player position, facing, and the markers
## other systems want drawn.
func update_field(player: Vector2, heading: Vector2, markers: Array) -> void:
	_player = player
	if _minimap != null:
		_minimap.call("update_state", player, heading, markers)
	# the camera slides every frame, so the edge arrow has to follow it; a
	# handful of draw calls, and only while walking
	if _has_quest or _marker_dirty:
		_marker_dirty = false
		queue_redraw()


func _camera() -> Camera3D:
	var vp := get_viewport()
	return vp.get_camera_3d() if vp != null else null


func _draw() -> void:
	if not _has_quest or size.x < 200.0 or size.y < 200.0:
		return
	var cam := _camera()
	if cam == null:
		return
	var world := Vector3(_quest.x, 0.9, _quest.y)
	var behind := cam.is_position_behind(world)
	var at := cam.unproject_position(world)
	var box := Rect2(Vector2.ZERO, size)
	var margin := 74.0
	if not behind and box.grow(-margin).has_point(at):
		# on screen: a small gold diamond hanging over the spot
		var d := PackedVector2Array([at + Vector2(0, -38), at + Vector2(9, -28),
			at + Vector2(0, -18), at + Vector2(-9, -28)])
		draw_colored_polygon(d, GOLD)
		draw_polyline(PackedVector2Array([d[0], d[1], d[2], d[3], d[0]]),
			Color(0.30, 0.20, 0.08), 1.5)
		draw_line(at + Vector2(0, -16), at + Vector2(0, -2),
			Color(0.30, 0.20, 0.08, 0.65), 1.5)
		return
	# off screen: park an arrow on the rim, pointing the way
	var centre := size * 0.5
	var dir := at - centre
	if behind:
		dir = -dir
	if dir.length() < 1.0:
		dir = Vector2(0.0, 1.0)
	dir = dir.normalized()
	var half := centre - Vector2(margin, margin)
	var scale_x := half.x / maxf(0.001, absf(dir.x))
	var scale_y := half.y / maxf(0.001, absf(dir.y))
	var reach := minf(scale_x, scale_y)
	var tip := centre + dir * reach
	var side := Vector2(-dir.y, dir.x)
	var tri := PackedVector2Array([tip + dir * 16.0, tip - dir * 8.0 + side * 13.0,
		tip - dir * 8.0 - side * 13.0])
	draw_colored_polygon(tri, GOLD)
	draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]),
		Color(0.22, 0.15, 0.08), 2.0)
	var metres := _player.distance_to(_quest)
	if metres >= MARKER_MIN_M:
		var font := KIT.font(KIT.FONT_BODY, 1)
		var text := "%d m" % int(round(metres))
		var text_at := tip - dir * 26.0 - Vector2(16.0, 10.0)
		draw_string_outline(font, text_at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4,
			Color(0.06, 0.04, 0.03, 0.9))
		draw_string(font, text_at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, CREAM)


# --------------------------------------------------------------------- fps ----
## Debug only: the field stays clean unless the owner turns debug on inside
## Pengaturan. `show_fps` alone is not enough any more.
func set_fps_visible(on: bool) -> void:
	if on and _fps_label == null:
		_fps_label = KIT.label("", 15, CREAM)
		_fps_label.add_theme_color_override("font_shadow_color", Color(0.05, 0.03, 0.02, 0.9))
		_fps_label.add_theme_constant_override("shadow_outline_size", 4)
		_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fps_label.position = Vector2(size.x - 260.0, 118.0 + _insets.y)
		add_child(_fps_label)
	elif not on and _fps_label != null:
		_fps_label.queue_free()
		_fps_label = null


func fps_label() -> Label:
	return _fps_label


func tick(delta: float, quality_label: String = "") -> void:
	if _fps_label == null:
		return
	_fps_timer += delta
	if _fps_timer < 0.4:
		return
	_fps_timer = 0.0
	_fps_label.text = "%d FPS · %s" % [Engine.get_frames_per_second(), quality_label]
	_fps_label.position = Vector2(size.x - 260.0, 118.0 + _insets.y)


# ------------------------------------------------------------------ fullmap ---
func _build_fullmap() -> void:
	if not ResourceLoader.exists(FULLMAP_SCRIPT):
		return
	_fullmap = (load(FULLMAP_SCRIPT) as Script).new()
	_fullmap.name = "FullMap"
	add_child(_fullmap)


func open_map() -> void:
	if _fullmap == null:
		return
	var map: Variant = _minimap.call("map") if _minimap != null else null
	if map == null:
		return
	_fullmap.call("open_panel", map, _player, _minimap.call("markers"))


func full_map() -> Control:
	return _fullmap


func full_map_open() -> bool:
	return _fullmap != null and bool(_fullmap.get("is_open"))
