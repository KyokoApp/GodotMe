class_name DioramaCamera
extends Node3D
## HD-2D camera rig: a fixed oblique angle (like a miniature diorama), player
## pan with one finger / left mouse, pinch or wheel to zoom.
##
## The rig holds the angle; `Camera3D` sits on it and only its local Z changes
## with the zoom, so the view can never tilt, which is what keeps the diorama
## reading as a diorama.

const PITCH_DEG := -38.0
const YAW_DEG := -22.0
const ZOOM_MIN := 14.0
const ZOOM_MAX := 42.0
const ZOOM_STEP := 0.9

## Half extents of the area the camera may look at (metres).
@export var bounds := Vector2(15.0, 11.0)
@export var start_zoom := 30.0

var _yaw := YAW_DEG
var _zoom := 13.0
var _target := Vector3.ZERO
var _dragging := false
var _touch_index := -1
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
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging:
		_pan_screen((event as InputEventMouseMotion).relative)
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	# Touch gets its own handler: on Android the drag must keep working even if a
	# button on the HUD is under the first finger.
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and _touch_index == -1:
			_touch_index = t.index
		elif not t.pressed and t.index == _touch_index:
			_touch_index = -1
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _touch_index:
			_pan_screen(d.relative)


func _pan_screen(delta: Vector2) -> void:
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


func reset() -> void:
	_target = Vector3.ZERO
	_zoom = start_zoom
	_apply()


func _apply() -> void:
	if _cam == null:
		return
	position = _target
	_cam.position = Vector3(0.0, 0.0, _zoom)
