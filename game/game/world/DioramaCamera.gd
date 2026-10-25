## No `class_name` on purpose - see WorldArt.gd. Same pack, so `preload` is
## enough and the script also parses when the game is loaded from .pck files.
extends Node3D
## HD-2D camera rig: a fixed oblique angle (like a miniature diorama), gliding
## after the player.
##
## Step 1 rules, in order of importance:
##   1. One finger belongs to the joystick. The rig never pans on a single touch;
##      the old pan made the view slide away from the knight whenever a thumb
##      landed just outside the stick.
##   2. The camera follows with a small dead zone and a soft catch-up, so walking
##      does not make the picture breathe.
##   3. It stays inside the map. The clamp is derived from the map rectangle and
##      from what the lens can actually see at the current zoom, so a bigger map
##      (step 2) needs no new numbers here.
##   4. Zoom is pinch-only and snaps to a fixed ladder, so a sprite is never
##      drawn at 1.13x and never shimmers while the fingers are moving.
##
## The rig holds the angle; `Camera3D` sits on it and only its local Z changes
## with the zoom, so the view can never tilt, which is what keeps the diorama
## reading as a diorama.

const PITCH_DEG := -38.0
const YAW_DEG := -22.0
const ZOOM_MIN := 11.0
## Absolute ceiling. A small map pulls the real ceiling in (see _rebuild_limits):
## on a 26x20 valley, zooming out to 32 would show more ground than exists.
const ZOOM_MAX := 32.0
## The ladder the pinch snaps to: whole and half metres, no in-between values.
const ZOOM_LADDER := [11.0, 12.0, 12.5, 14.0, 16.0, 18.0, 20.0, 22.5, 25.0, 28.0, 32.0]
## The camera does not chase every millimetre the knight walks: it only moves
## once he leaves this radius, which keeps the picture still while he is close.
const FOLLOW_DEADZONE := 0.55
## How fast it catches up, in "fraction of the remaining distance per second".
const FOLLOW_RATE := 4.5
## A conversation pulls the lens this much closer and aims between the two
## people, then lets go.
const DIALOG_ZOOM_FACTOR := 0.86
## How much of the frame the camera may lose off the map's edge before the clamp
## stops it. 0.45 keeps the centre well inside on small maps and effectively
## disappears on large ones.
const EDGE_SLACK := 0.45

## Half extents of the area the camera may look at (metres). Kept for older
## packs; `set_map_bounds` is what the diorama calls now.
@export var bounds := Vector2(15.0, 11.0)
@export var start_zoom := 19.0

var _yaw := YAW_DEG
var _zoom := 13.0
var _target := Vector3.ZERO
var _touches := {}
var _pinch_start := 0.0
var _pinch_snap := 0.0
var _follow: Node3D = null
var _follow_pause := 0.0
## Map rectangle the camera must stay over, and the margins it keeps from its
## edges at the current zoom.
var _map := Rect2()
var _has_map := false
var _max_zoom := ZOOM_MAX
## Dialogue framing: a point between the speakers, or null when nobody talks.
var _focus_pair: Array = []
@onready var _cam: Camera3D = $Camera3D


func _ready() -> void:
	_zoom = start_zoom
	rotation_degrees = Vector3(PITCH_DEG, _yaw, 0.0)
	_rebuild_limits()
	_apply()


# ------------------------------------------------------------------- limits ---
## Give the rig the map it must not leave. The diorama calls this with
## `map.bounds()`; tests call it with a made-up rectangle.
func set_map_bounds(rect: Rect2) -> void:
	_map = rect
	_has_map = rect.size.x > 0.1 and rect.size.y > 0.1
	_rebuild_limits()
	_clamp_target()
	_apply()


func map_bounds() -> Rect2:
	return _map


## What the lens can see on the ground at a given zoom: half width and half
## depth. Used for the clamp and for the maximum zoom-out, so both always agree
## with the real camera instead of with a guessed constant.
func view_extent(zoom_value: float) -> Vector2:
	var fov := 30.0
	if _cam != null:
		fov = _cam.fov
	var vp := get_viewport()
	var aspect := 1.7778
	if vp != null:
		var size := vp.get_visible_rect().size
		if size.y > 1.0:
			aspect = size.x / size.y
	var half_h := zoom_value * tan(deg_to_rad(fov * 0.5))
	var half_w := half_h * aspect
	# The rig looks down at PITCH_DEG, so the same frame covers more ground in
	# depth than across. sin() is the honest factor; using the raw half height
	# would let the top of the screen show the void.
	var half_d := half_h / maxf(0.2, sin(deg_to_rad(absf(PITCH_DEG))))
	return Vector2(half_w, half_d)


func _rebuild_limits() -> void:
	_max_zoom = ZOOM_MAX
	if not _has_map:
		return
	# Zoom out only as far as the depth of the frame still fits the map. On the
	# starting valley that pulls the ceiling down to ~21; on a map eight times
	# larger it stays at the absolute maximum.
	var limit := _map.size.y * 0.5
	if limit <= 0.1:
		return
	var half_h_ratio := tan(deg_to_rad(15.0)) / maxf(0.2, sin(deg_to_rad(absf(PITCH_DEG))))
	_max_zoom = clampf(limit / half_h_ratio, ZOOM_MIN, ZOOM_MAX)


func max_zoom() -> float:
	return _max_zoom


func _clamp_target() -> void:
	if not _has_map:
		return
	var view := view_extent(_zoom)
	var slack_x := minf(view.x * 0.9, _map.size.x * 0.5 * EDGE_SLACK)
	var slack_z := minf(view.y * 0.9, _map.size.y * 0.5 * EDGE_SLACK)
	var low_x := _map.position.x + slack_x
	var high_x := _map.position.x + _map.size.x - slack_x
	var low_z := _map.position.y + slack_z
	var high_z := _map.position.y + _map.size.y - slack_z
	# None of the four may cross, or a big zoom on a small map would clamp the
	# camera to the wrong side of its own limits.
	if low_x > high_x:
		low_x = _map.get_center().x
		high_x = low_x
	if low_z > high_z:
		low_z = _map.get_center().y
		high_z = low_z
	_target.x = clampf(_target.x, low_x, high_x)
	_target.z = clampf(_target.z, low_z, high_z)


## Limits currently in force, for tests: {min: Vector2, max: Vector2, zoom}.
func clamp_limits() -> Dictionary:
	if not _has_map:
		return {"min": Vector2(-bounds.x, -bounds.y), "max": bounds, "zoom": _zoom}
	var view := view_extent(_zoom)
	var sx := minf(view.x * 0.9, _map.size.x * 0.5 * EDGE_SLACK)
	var sz := minf(view.y * 0.9, _map.size.y * 0.5 * EDGE_SLACK)
	var low := Vector2(_map.position.x + sx, _map.position.y + sz)
	var high := Vector2(_map.position.x + _map.size.x - sx,
		_map.position.y + _map.size.y - sz)
	if low.x > high.x:
		low.x = _map.get_center().x
		high.x = low.x
	if low.y > high.y:
		low.y = _map.get_center().y
		high.y = low.y
	return {"min": low, "max": high, "zoom": _zoom}


# -------------------------------------------------------------------- input ---
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMagnifyGesture:
		_zoom_by(1.0 / maxf(0.2, (event as InputEventMagnifyGesture).factor))
		get_viewport().set_input_as_handled()
	elif event is InputEventPanGesture:
		_pan_screen((event as InputEventPanGesture).delta * 12.0)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_by(1.0 / 1.12)
			get_viewport().set_input_as_handled()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(1.12)
			get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	# Touch gets its own handler: the camera needs the fingers the stick and the
	# buttons are not using. ONE finger is never a camera gesture.
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_touches[t.index] = t.position
		else:
			_touches.erase(t.index)
		if _touches.size() < 2:
			_pinch_start = 0.0
			_pinch_snap = _zoom
		elif _pinch_start <= 0.0:
			_pinch_start = _touch_span()
			_pinch_snap = _zoom
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if not _touches.has(d.index):
			return
		_touches[d.index] = d.position
		if _touches.size() < 2:
			return
		var span := _touch_span()
		if _pinch_start > 1.0 and span > 1.0:
			# Zoom against the span the pinch STARTED at, then snap once, so the
			# lens does not ratchet on every event.
			var want := _pinch_snap * (_pinch_start / span)
			_set_zoom_snapped(want)
		_pan_screen(d.relative * 0.5)


func _touch_span() -> float:
	var pts: Array = _touches.values()
	if pts.size() < 2:
		return 0.0
	return (pts[0] as Vector2).distance_to(pts[1] as Vector2)


# ------------------------------------------------------------------- follow ---
## Let the rig drift toward an actor so the player is never walked off screen.
func set_follow_target(node: Node3D) -> void:
	_follow = node
	_follow_pause = 0.0
	if node != null and is_instance_valid(node):
		_target = Vector3(node.position.x, 0.0, node.position.z)
		_clamp_target()
		_apply()


## Frame a conversation: aim between the knight and the speaker and come a
## little closer. `clear_focus` puts the lens back on the player.
func focus_pair(a: Node3D, b: Node3D) -> void:
	_focus_pair = []
	if a != null and is_instance_valid(a):
		_focus_pair.append(a)
	if b != null and is_instance_valid(b):
		_focus_pair.append(b)
	_rebuild_limits()
	_set_zoom_snapped(_zoom * DIALOG_ZOOM_FACTOR)


func clear_focus() -> void:
	if _focus_pair.is_empty():
		return
	_focus_pair = []
	_set_zoom_snapped(start_zoom)


## Centre the lens on the player again (menu button / double tap).
func recentre() -> void:
	_follow_pause = 0.0
	_focus_pair = []
	_set_zoom_snapped(start_zoom)
	if _follow == null or not is_instance_valid(_follow):
		_target = Vector3(_map.get_center().x, 0.0, _map.get_center().y) if _has_map else Vector3.ZERO
	else:
		_target = Vector3(_follow.position.x, 0.0, _follow.position.z)
	_clamp_target()
	_apply()


func _process(delta: float) -> void:
	if not _focus_pair.is_empty():
		_follow_box(delta)
		return
	if _follow_pause > 0.0:
		_follow_pause = maxf(0.0, _follow_pause - delta)
		return
	if _follow == null or not is_instance_valid(_follow):
		return
	var want := Vector3(_follow.position.x, 0.0, _follow.position.z)
	var gap := Vector2(want.x - _target.x, want.z - _target.z)
	if gap.length() <= FOLLOW_DEADZONE:
		return
	# Aim at the edge of the deadzone, not at the actor: the view then glides
	# instead of pumping back and forth while the knight walks.
	var aim := want - Vector3(gap.normalized().x, 0.0, gap.normalized().y) * FOLLOW_DEADZONE
	_target = _target.lerp(aim, clampf(delta * FOLLOW_RATE, 0.0, 1.0))
	_clamp_target()
	_apply()


## During a conversation the lens sits on the midpoint of the two speakers.
func _follow_box(delta: float) -> void:
	var sum := Vector3.ZERO
	var count := 0
	for node in _focus_pair:
		if node != null and is_instance_valid(node):
			sum += Vector3(node.position.x, 0.0, node.position.z)
			count += 1
	if count == 0:
		_focus_pair = []
		return
	var want := sum / float(count)
	_target = _target.lerp(want, clampf(delta * FOLLOW_RATE * 1.4, 0.0, 1.0))
	_clamp_target()
	_apply()


func _pan_screen(delta: Vector2) -> void:
	# Two fingers may still look around; a deliberate pan holds the camera still
	# for a moment afterwards, then the rig quietly takes over again.
	_follow_pause = 1.2
	var per_px := _zoom * 0.0016
	var right := global_transform.basis.x
	var forward := global_transform.basis.z
	_target += (-right * delta.x + forward * -delta.y) * per_px
	_clamp_target()
	_apply()


func _zoom_by(factor: float) -> void:
	_set_zoom_snapped(_zoom * factor)


## Snap to the ladder: the value a finger lets go on is always a whole or half
## metre, never 17,43, which is what keeps sprites from shimmering at 1,03x.
func _set_zoom_snapped(value: float) -> void:
	var high := minf(ZOOM_MAX, _max_zoom)
	var pick := clampf(value, ZOOM_MIN, high)
	var best := pick
	var best_gap := INF
	for step_variant in ZOOM_LADDER:
		var step_value := float(step_variant)
		if step_value < ZOOM_MIN - 0.01 or step_value > high + 0.01:
			continue
		var gap := absf(step_value - pick)
		if gap < best_gap:
			best_gap = gap
			best = step_value
	_zoom = best
	_clamp_target()
	_apply()


## Absolute zoom, clamped to the current limits (used by the visual tests).
func set_zoom(value: float) -> void:
	_set_zoom_snapped(value)


func zoom() -> float:
	return _zoom


func reset() -> void:
	recentre()


## Backwards-compatible alias: older tests and the world call `reset_view`.
func _apply() -> void:
	if _cam == null:
		return
	position = _target
	_cam.position = Vector3(0.0, 0.0, _zoom)
