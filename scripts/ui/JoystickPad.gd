class_name JoystickPad
extends Control
## Visual virtual joystick untuk LANTERNFALL (kiri bawah layar).
## Digambar prosedural (tanpa tekstur) supaya ringan & bebas resolusi:
## lingkaran dasar transparan + knob yang mengikuti arah sentuhan.
## Digunakan oleh TouchHUDController melalui set_state()/release().

const BASE_ALPHA: float = 0.42
const RING_ALPHA: float = 0.55
const KNOB_ALPHA: float = 0.85
const PAD_PADDING: float = 40.0
const KNOB_RADIUS: float = 34.0

var _radius: float = 72.0
var _vec: Vector2 = Vector2.ZERO
var _active: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## Dipanggil setiap ada sentuhan/drag joystick.
## `screen_pos` = titik awal sentuhan, `vec` = vektor arah ter-normalisasi (-1..1).
func set_state(screen_pos: Vector2, vec: Vector2, radius: float) -> void:
	_radius = radius
	_vec = vec
	_active = true
	var pad_size: float = radius * 2.0 + PAD_PADDING
	size = Vector2(pad_size, pad_size)
	position = screen_pos - Vector2(pad_size, pad_size) * 0.5
	visible = true
	queue_redraw()


func release() -> void:
	_active = false
	_vec = Vector2.ZERO
	visible = false
	queue_redraw()


func _draw() -> void:
	if not _active:
		return
	var center: Vector2 = size * 0.5
	var base_radius: float = _radius + 14.0
	draw_circle(center, base_radius, Color(0.09, 0.08, 0.13, BASE_ALPHA))
	draw_arc(center, base_radius, 0.0, TAU, 48, Color(0.78, 0.72, 0.92, RING_ALPHA), 3.0, true)
	var knob: Vector2 = center + _vec * _radius
	draw_circle(knob, KNOB_RADIUS, Color(0.85, 0.78, 0.96, KNOB_ALPHA))
