extends Control
## Test instrument: a metre ruler and a foot-pivot cross drawn in screen space
## by projecting world points through the test camera. Lines and numbers only -
## it is a measuring tool, not game art.

var camera: Camera3D
var actors: Array = []
var ruler_x := -3.4
var ruler_z := 0.0
var top_metres := 2.0

const INK := Color(0.97, 0.92, 0.82, 0.92)
const PIVOT := Color(1.0, 0.82, 0.30, 0.95)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if camera == null or not is_instance_valid(camera):
		return
	var font := ThemeDB.fallback_font
	var base := camera.unproject_position(Vector3(ruler_x, 0.0, ruler_z))
	var top := camera.unproject_position(Vector3(ruler_x, top_metres, ruler_z))
	draw_line(base, top, Color(INK.r, INK.g, INK.b, 0.55), 2.0)
	var steps := int(top_metres * 10.0)
	for i in range(steps + 1):
		var h := float(i) * 0.1
		var p := camera.unproject_position(Vector3(ruler_x, h, ruler_z))
		var major := i % 5 == 0
		draw_line(p, p - Vector2(20.0 if major else 10.0, 0.0), INK, 2.0 if major else 1.0)
		if major:
			# right-aligned, ending just left of its tick: on the far left the
			# label was clipped by the screen edge, and on the right it sat on
			# top of the knight's sword
			draw_string(font, p + Vector2(-8.0, -2.0), "%.1f m" % h,
				HORIZONTAL_ALIGNMENT_RIGHT, 58.0, 13, INK)
	for actor in actors:
		if not is_instance_valid(actor):
			continue
		var feet: Vector3 = (actor as Node3D).global_position
		var p := camera.unproject_position(feet)
		draw_line(p - Vector2(10.0, 0.0), p + Vector2(10.0, 0.0), PIVOT, 2.0)
		draw_line(p - Vector2(0.0, 10.0), p + Vector2(0.0, 10.0), PIVOT, 2.0)
		draw_arc(p, 4.0, 0.0, TAU, 12, PIVOT, 1.5)
