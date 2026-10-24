## No `class_name` on purpose - see WorldArt.gd. Same pack, so `preload` is
## enough and the script also parses when the game is loaded from .pck files.
extends Node3D
## HD-2D camera rig: a fixed oblique angle (like a miniature diorama). The rig
## FOLLOWS the player by itself; two fingers pan, pinch or wheel zooms. A single
## finger belongs to the on-screen stick, so a thumb that lands outside the
## stick's circle must not drag the view away from the character.
##
## The rig holds the angle; `Camera3D` sits on it and only its local Z changes
## with the zoom, so the view can never tilt, which is what keeps the diorama
## reading as a diorama.

const PITCH_DEG := -38.0
const YAW_DEG := -22.0
const ZOOM_MIN := 11.0
const ZOOM_MAX := 32.0
const ZOOM_STEP := 0.9
## The camera does not chase every millimetre the knight walks: it only moves
## once he leaves this radius, which keeps the picture still while he is close.
const FOLLOW_DEADZONE := 0.55
## How fast it catches up, in "fraction of the remaining distance per second".
const FOLLOW_RATE := 5.5

## Half extents of the area the camera may look at (metres).
@export var bounds := Vector2(15.0, 11.0)
@export var start_zoom := 19.0

## Screen rects where a touch must not pan the camera - the touch UI registers
## its stick and buttons here so steering does not also drag the view.
var touch_blockers: Array = []

var _yaw := YAW_DEG
var _zoom := 13.0
var _target := Vector3.ZERO
var _dragging := false
var _touch_index := -1
## Every finger currently down, for two-finger pan / pinch.
var _touches := {}
var _pinch_start := 0.0
var _follow: Node3D = null
var _follow_pause := 0.0
@onready var _cam: Camera3D = $Camera3D


func _ready() -> void:
	_zoom = start_zoom
	rotation_degrees = Vector3(PITCH_DEG, _yaw, 0.0)
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMagnifyGesture:
		_zoom_by(1.0 / maxf(0.2, (event as InputEventMagnifyGesture).factor))
		get_viewport().set_input_as_handled()
	elif event is InputEventPanGesture:
		var pan := (event as InputEventPanGesture).delta
		_pan_screen(pan * 12.0)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_by(1.0 / ZOOM_STEP)
			get_viewport().set_input_as_handled()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(ZOOM_STEP)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed and not (mb.pressed and _blocked(mb.position))
	elif event is InputEventMouseMotion and _dragging:
		_pan_screen((event as InputEventMouseMotion).relative)
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	# Touch gets its own handler: the camera needs the fingers that the stick and
	# the buttons are not using, and it must never steal the first one.
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_touches[t.index] = t.position
		else:
			_touches.erase(t.index)
			if _touches.size() < 2:
				_pinch_start = 0.0
				_touch_index = -1
		if _touches.size() >= 2:
			_touch_index = -1      # two fingers down: this is a camera gesture
			_pinch_start = _touch_span()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if not _touches.has(d.index):
			return
		_touches[d.index] = d.position
		if _touches.size() < 2:
			return
		var span := _touch_span()
		if _pinch_start > 1.0 and span > 1.0:
			_zoom_by(_pinch_start / span)
			_pinch_start = span
		_pan_screen(d.relative * 0.5)


func _touch_span() -> float:
	var pts: Array = _touches.values()
	if pts.size() < 2:
		return 0.0
	return (pts[0] as Vector2).distance_to(pts[1] as Vector2)


func _blocked(pos: Vector2) -> bool:
	for raw in touch_blockers:
		if typeof(raw) == TYPE_RECT2 and (raw as Rect2).has_point(pos):
			return true
	return false


## Let the rig drift toward an actor so the player is never walked off screen.
## A manual pan wins for a couple of seconds after it ends.
func set_follow_target(node: Node3D) -> void:
	_follow = node
	_follow_pause = 0.0
	if node != null and is_instance_valid(node):
		_target = Vector3(node.position.x, 0.0, node.position.z)
		_apply()


func _process(delta: float) -> void:
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
	_target.x = clampf(_target.x, -bounds.x, bounds.x)
	_target.z = clampf(_target.z, -bounds.y, bounds.y)
	_apply()


func _pan_screen(delta: Vector2) -> void:
	# A deliberate pan holds the camera still for a moment afterwards, then the
	# rig quietly takes over again - the player should never lose his knight.
	_follow_pause = 1.2
	# Screen pixels -> metres at the current zoom, in the rig's own plane.
	var per_px := _zoom * 0.0016
	var right := global_transform.basis.x
	var forward := global_transform.basis.z
	_target += (-right * delta.x + forward * -delta.y) * per_px
	_target.x = clampf(_target.x, -bounds.x, bounds.x)
	_target.z = clampf(_target.z, -bounds.y, bounds.y)
	_apply()


func _zoom_by(factor: float) -> void:
	_zoom = clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	_apply()


## Absolute zoom, clamped to the rig's limits (used by the visual test scenes).
func set_zoom(value: float) -> void:
	_zoom = clampf(value, ZOOM_MIN, ZOOM_MAX)
	_apply()


func reset() -> void:
	_target = Vector3.ZERO
	_zoom = start_zoom
	_apply()


func _apply() -> void:
	if _cam == null:
		return
	position = _target
	_cam.position = Vector3(0.0, 0.0, _zoom)
