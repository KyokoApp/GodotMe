## No `class_name` on purpose - see WorldArt.gd. Same pack, so `preload` is
## enough and the script also parses when the game is loaded from .pck files.
extends Node3D
## HD-2D camera rig: one oblique angle, one distance, a smooth glide after the
## player.
##
## Step 3A rewrote this file. What it used to do, and why every one of those
## things had to go:
##
##   1. Pinch, wheel, magnify-gesture and pan gestures all changed `_zoom`. On a
##      phone the joystick thumb and the action thumb are two touches, and
##      `_input` treated ANY two touches as a pinch - walking while pressing a
##      button quietly zoomed the camera. That was the "camera zooms by itself"
##      bug. There is now no input handler in this file at all.
##   2. `focus_pair()` multiplied the zoom by 0.86 when a conversation opened, so
##      every dialogue moved the lens.
##   3. `recentre()`/`clear_focus()` snapped the zoom back to `start_zoom`, so the
##      view jumped again when the conversation closed.
##   4. The zoom was snapped to a ladder, so the same gesture could stop on 12 or
##      12.5 - the frame never sat still.
##
## The lens is now read from ONE data file (`world/camera.json`) and never
## changes at run time except for scripted moments (battle transitions, a cutscene)
## which go through `set_lens()`. Tests (`CameraTest`) drive the player through a
## long route and record pitch, FOV and distance every frame: all three must hold
## still. What the player asked for - "smooth like Octopath, fixed distance, no
## zoom" - is exactly what that test enforces.
##
## Motion: a critically damped spring per axis, computed from `delta`, so the
## camera cannot overshoot and cannot move faster on a 120 Hz screen than on a
## 30 Hz one. The rig processes AFTER the character (process_priority), so the
## frame the knight moves in is the frame the camera answers, with no one-frame
## lag that reads as rubber-banding.

const CONFIG_PATH := "res://game/world/camera.json"

## Fallbacks, used when the pack has no camera.json (an older world pack, or a
## test that only wants a rig). Same numbers as the shipped file.
const DEFAULT_PITCH := 30.0
const DEFAULT_YAW := -22.0
const DEFAULT_FOV := 32.0
const DEFAULT_DISTANCE := 18.0
const DEFAULT_LOOK_AHEAD := 1.7
const DEFAULT_NEAR := 0.4
const DEFAULT_FAR := 420.0
const DEFAULT_DEADZONE := 0.32
const DEFAULT_SMOOTH := 0.20

## Runs after CharacterWorld (priority 0): the rig must answer a move that has
## already happened in this frame, not the one before it.
const PROCESS_PRIORITY := 200

## The camera never flies off the map. This is how much of the frame may hang
## over the edge before the clamp stops it.
const EDGE_SLACK := 0.45

var pitch_deg := DEFAULT_PITCH
var yaw_deg := DEFAULT_YAW
var fov_deg := DEFAULT_FOV
var distance_m := DEFAULT_DISTANCE
var look_ahead_m := DEFAULT_LOOK_AHEAD
var near_m := DEFAULT_NEAR
var far_m := DEFAULT_FAR
var deadzone_m := DEFAULT_DEADZONE
var smooth_time_s := DEFAULT_SMOOTH
## Filled by `load_config()`; tests read it to prove the screen matches the file.
var config := {}

## Aim point on the ground = where the rig itself stands.
var _target := Vector3.ZERO
## Spring velocity in metres per second, per axis.
var _vel := Vector3.ZERO
var _follow: Node3D = null
## Dialogue framing: a point between the speakers, or empty.
var _focus_pair: Array = []
## Height of the ground under the player. The rig has to ride it: at Pos Gunung
## (4 tiles above the valley = 7,2 m) a rig pinned to y = 0 with an 18 m lens sits
## 9 m up - which is IN the mountain, and the capture showed props from inside and
## no knight at all. The world feeds this every frame.
var _ground_y := 0.0
## Field lens numbers parked while a battle borrows the rig.
var _saved: Dictionary = {}
## Map rectangle the camera must stay over.
var _map := Rect2()
var _has_map := false
## Older packs set these through the diorama; kept so `bounds` never crashes.
@export var bounds := Vector2(15.0, 11.0)
@export var start_zoom := DEFAULT_DISTANCE
@onready var _cam: Camera3D = $Camera3D


func _ready() -> void:
	process_priority = PROCESS_PRIORITY
	load_config()
	_apply_lens()
	_apply()


## Read `world/camera.json`. Missing or broken file = the shipped defaults, and
## one warning in the log: a pack whose data is damaged must still boot.
func load_config() -> Dictionary:
	config = {}
	if FileAccess.file_exists(CONFIG_PATH):
		var text := FileAccess.get_file_as_string(CONFIG_PATH)
		if text.length() > 2:
			var parsed: Variant = JSON.parse_string(text)
			if typeof(parsed) == TYPE_DICTIONARY:
				config = parsed
	if config.is_empty():
		push_warning("[CAMERA] camera.json tidak terbaca, memakai nilai bawaan")
		_pick_fallbacks()
		return config
	var lens: Dictionary = _dict(config, "lens")
	var follow: Dictionary = _dict(config, "follow")
	pitch_deg = _num(lens, "pitch_deg", DEFAULT_PITCH)
	yaw_deg = _num(lens, "yaw_deg", DEFAULT_YAW)
	fov_deg = _num(lens, "fov_deg", DEFAULT_FOV)
	distance_m = _num(lens, "distance_m", DEFAULT_DISTANCE)
	look_ahead_m = _num(lens, "look_ahead_m", DEFAULT_LOOK_AHEAD)
	near_m = _num(lens, "near_m", DEFAULT_NEAR)
	far_m = _num(lens, "far_m", DEFAULT_FAR)
	deadzone_m = _num(follow, "deadzone_m", DEFAULT_DEADZONE)
	smooth_time_s = _num(follow, "smooth_time_s", DEFAULT_SMOOTH)
	# A file that asks for a top-down lens or a fisheye is a typo, not a design:
	# keep the rig inside what the rest of the game was built for.
	pitch_deg = clampf(pitch_deg, 12.0, 70.0)
	fov_deg = clampf(fov_deg, 18.0, 60.0)
	distance_m = clampf(distance_m, 8.0, 40.0)
	smooth_time_s = clampf(smooth_time_s, 0.05, 1.0)
	print("[CAMERA] lens pitch %.1f fov %.1f jarak %.1f (dari camera.json)" % [
		pitch_deg, fov_deg, distance_m])
	return config


func _pick_fallbacks() -> void:
	pitch_deg = DEFAULT_PITCH
	yaw_deg = DEFAULT_YAW
	fov_deg = DEFAULT_FOV
	distance_m = DEFAULT_DISTANCE
	look_ahead_m = DEFAULT_LOOK_AHEAD
	near_m = DEFAULT_NEAR
	far_m = DEFAULT_FAR
	deadzone_m = DEFAULT_DEADZONE
	smooth_time_s = DEFAULT_SMOOTH


func _dict(source: Dictionary, key: String) -> Dictionary:
	var raw: Variant = source.get(key, {})
	if typeof(raw) == TYPE_DICTIONARY:
		return raw
	return {}


func _num(source: Dictionary, key: String, fallback: float) -> float:
	var raw: Variant = source.get(key, fallback)
	if typeof(raw) == TYPE_FLOAT or typeof(raw) == TYPE_INT:
		return float(raw)
	return fallback


## Terrain height under the player, in metres. Called by the diorama each frame.
func set_ground_height(y: float) -> void:
	_ground_y = y


## Values the HUD post-process needs (tilt-shift), so the blur band follows the
## same file the angle does.
func tilt_shift() -> Dictionary:
	var ts: Dictionary = _dict(config, "tilt_shift")
	return {
		"focus_line": _num(ts, "focus_line", 0.54),
		"sharp_band": _num(ts, "sharp_band", 0.30),
		"blur_pixels": _num(ts, "blur_pixels", 2.1),
	}


func occlusion() -> Dictionary:
	var oc: Dictionary = _dict(config, "occlusion")
	return {
		"radius_m": _num(oc, "radius_m", 1.05),
		"reach_m": _num(oc, "reach_m", 2.5),
	}


# -------------------------------------------------------------------- lens ---
## Put the configured lens on the rig and on the `Camera3D`. Called once at
## boot and again only by `set_lens()` (scripted scenes and captures).
func _apply_lens() -> void:
	rotation_degrees = Vector3(-pitch_deg, yaw_deg, 0.0)
	if _cam == null:
		return
	_cam.fov = fov_deg
	_cam.near = near_m
	_cam.far = far_m
	_cam.position = Vector3(0.0, 0.0, distance_m)


## Scripted lens change - a cutscene, a battle transition, or the capture rig
## photographing the same scene at several angles. Never called from input.
func set_lens(pitch: float = NAN, fov: float = NAN, distance: float = NAN) -> void:
	if not is_nan(pitch):
		pitch_deg = clampf(pitch, 12.0, 70.0)
	if not is_nan(fov):
		fov_deg = clampf(fov, 18.0, 60.0)
	if not is_nan(distance):
		distance_m = clampf(distance, 8.0, 40.0)
	_apply_lens()
	_apply()


## Scripted battle framing: face the arena straight on, close in, and drop the
## walking look-ahead (which would push the aim past the enemies). The field's
## numbers are handed back by `battle_release()`.
##
## Like `set_lens()`, nothing in input can reach this: step 3A's rule is that the
## player never moves the lens. A battle is the same kind of moment as a cutscene.
func battle_frame(aim: Vector2, ground_y: float) -> void:
	_saved = {
		"pitch": pitch_deg, "yaw": yaw_deg, "fov": fov_deg,
		"distance": distance_m, "look_ahead": look_ahead_m,
	}
	# the knight keeps walking his own business during the fight; the lens must not
	# slide back to him, so the follow target is parked and handed back afterwards
	_saved["follow"] = _follow
	_follow = null
	# The numbers are the ones a sweep over this rig proved: five yaws from -22 to
	# +22 all rendered the arena (draw calls 97-106, mid-pixel green or brown, no
	# haze), at pitch 30, fov 34 and 16 m. -12 is the three-quarter view that puts
	# both lines in frame with the village behind them.
	look_ahead_m = 0.0
	yaw_deg = -12.0
	pitch_deg = 30.0
	fov_deg = 34.0
	distance_m = 16.0
	_apply_lens()
	_ground_y = ground_y
	_target = Vector3(aim.x, ground_y, aim.y)
	_vel = Vector3.ZERO
	_apply()
	print("[CAMERA] bingkai pertarungan: pitch 30 fov 34 jarak 16 yaw -12 di %s" % str(aim))


func battle_release() -> void:
	if _saved.is_empty():
		return
	pitch_deg = float(_saved.get("pitch", pitch_deg))
	yaw_deg = float(_saved.get("yaw", yaw_deg))
	fov_deg = float(_saved.get("fov", fov_deg))
	distance_m = float(_saved.get("distance", distance_m))
	look_ahead_m = float(_saved.get("look_ahead", look_ahead_m))
	var who: Variant = _saved.get("follow", null)
	if who is Node3D and is_instance_valid(who):
		_follow = who as Node3D
	_saved = {}
	_vel = Vector3.ZERO
	_apply_lens()
	_apply()


## Kept for the capture harness and older callers that think in "zoom": the
## distance along the view axis. No input anywhere reaches this.
func set_distance(value: float) -> void:
	set_lens(NAN, NAN, value)


func distance() -> float:
	return distance_m


func lens() -> Dictionary:
	return {
		"pitch_deg": pitch_deg,
		"yaw_deg": yaw_deg,
		"fov_deg": fov_deg,
		"distance_m": distance_m,
	}


func camera() -> Camera3D:
	return _cam


## Everything the recorder test looks at, in one place.
func lens_state() -> Dictionary:
	return {
		"pitch_deg": pitch_deg,
		"yaw_deg": yaw_deg,
		"fov_deg": fov_deg if _cam == null else _cam.fov,
		"distance_m": distance_m if _cam == null else absf(_cam.position.z),
		"near_m": near_m if _cam == null else _cam.near,
		"far_m": far_m if _cam == null else _cam.far,
	}


# ------------------------------------------------------------------- limits ---
## Give the rig the map it must not leave. The diorama calls this with
## `map.bounds()`; tests call it with a made-up rectangle.
func set_map_bounds(rect: Rect2) -> void:
	_map = rect
	_has_map = rect.size.x > 0.1 and rect.size.y > 0.1
	_clamp_target()
	_apply()


func map_bounds() -> Rect2:
	return _map


## What the lens can see on the ground: half width and half depth. Derived from
## the real camera (fov, pitch, distance) instead of a guessed constant, so a
## config change cannot leave the clamp out of step with the frame.
func view_extent(distance_value: float = -1.0) -> Vector2:
	var use_distance := distance_m if distance_value < 0.0 else distance_value
	var use_fov := fov_deg
	if _cam != null:
		use_fov = _cam.fov
	var vp := get_viewport()
	var aspect := 1.7778
	if vp != null:
		var size := vp.get_visible_rect().size
		if size.y > 1.0:
			aspect = size.x / size.y
	var half_h := use_distance * tan(deg_to_rad(use_fov * 0.5))
	var half_w := half_h * aspect
	# Looking down at `pitch` degrees, the same frame covers more ground in depth
	# than across; sin() is the honest factor.
	var half_d := half_h / maxf(0.2, sin(deg_to_rad(pitch_deg)))
	return Vector2(half_w, half_d)


## Limits currently in force, for tests: {min: Vector2, max: Vector2, zoom}.
func clamp_limits() -> Dictionary:
	if not _has_map:
		return {"min": Vector2(-bounds.x, -bounds.y), "max": bounds, "zoom": distance_m}
	var view := view_extent()
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
	return {"min": low, "max": high, "zoom": distance_m}


func _clamp_target() -> void:
	if not _has_map:
		return
	var limits := clamp_limits()
	var low: Vector2 = limits["min"]
	var high: Vector2 = limits["max"]
	_target.x = clampf(_target.x, low.x, high.x)
	_target.z = clampf(_target.z, low.y, high.y)


# ------------------------------------------------------------------- follow ---
## Let the rig drift toward an actor so the player is never walked off screen.
func set_follow_target(node: Node3D) -> void:
	_follow = node
	if node != null and is_instance_valid(node):
		_target = Vector3(node.position.x, _target.y, node.position.z)
		_clamp_target()
		_vel = Vector3.ZERO
		_apply()


## Frame a conversation: aim between the two speakers. The DISTANCE DOES NOT
## CHANGE - step 3A removed the old 0.86x pull-in, which moved the lens every
## time anybody spoke.
func focus_pair(a: Node3D, b: Node3D) -> void:
	_focus_pair = []
	if a != null and is_instance_valid(a):
		_focus_pair.append(a)
	if b != null and is_instance_valid(b):
		_focus_pair.append(b)


func clear_focus() -> void:
	_focus_pair = []


## Centre the lens on the player again (menu button / double tap). No jump: the
## spring takes it there like it takes it anywhere.
func recentre() -> void:
	_focus_pair = []
	if _follow == null or not is_instance_valid(_follow):
		_target = Vector3(_map.get_center().x, 0.0, _map.get_center().y) if _has_map else Vector3.ZERO
	else:
		_target = Vector3(_follow.position.x, 0.0, _follow.position.z)
	_clamp_target()
	_vel = Vector3.ZERO
	_apply()


func reset() -> void:
	recentre()


## Put the rig on a map point at once (boot, or after a scene change). No glide:
## the first frame of a session must not show the camera flying in from nowhere.
func place_at(point: Vector2) -> void:
	_target = Vector3(point.x, _ground_y, point.y)
	_clamp_target()
	_vel = Vector3.ZERO
	_apply()


## Place the rig exactly where it belongs right now: used once when a scene is
## assembled, and by captures so a screenshot is not a frame of drift.
func snap_to_target() -> void:
	var want := _desired_target()
	_target = want
	_clamp_target()
	_vel = Vector3.ZERO
	_apply()


func _process(delta: float) -> void:
	var want := _desired_target()
	_target = _smooth_damp(_target, want, delta)
	_apply()


## Where the rig would sit if it were allowed to jump. Dead zone first: the
## camera ignores the first few centimetres a knight walks, so standing still and
## starting to walk do not nudge the picture.
func _desired_target() -> Vector3:
	var point := _follow_point()
	var fwd := ground_forward()
	var aim := point + fwd * look_ahead_m
	var gap := Vector2(aim.x - _target.x, aim.z - _target.z)
	if gap.length() <= deadzone_m:
		aim = Vector3(_target.x, _ground_y, _target.z)
	else:
		# aim at the edge of the dead zone, not at the actor: the view glides
		# instead of pumping while the knight walks
		var dir := gap.normalized() * (gap.length() - deadzone_m)
		aim = Vector3(_target.x + dir.x, _ground_y, _target.z + dir.y)
	if _has_map:
		var limits := clamp_limits()
		var low: Vector2 = limits["min"]
		var high: Vector2 = limits["max"]
		aim.x = clampf(aim.x, low.x, high.x)
		aim.z = clampf(aim.z, low.y, high.y)
	return aim


## The point the lens is interested in: the player, or the middle of a
## conversation. Never the player's exact frame - a 30 Hz phone and a 120 Hz
## screen must agree.
func _follow_point() -> Vector3:
	if not _focus_pair.is_empty():
		var sum := Vector3.ZERO
		var count := 0
		for node in _focus_pair:
			if node != null and is_instance_valid(node):
				sum += Vector3(node.position.x, 0.0, node.position.z)
				count += 1
		if count > 0:
			return sum / float(count)
		_focus_pair = []
	if _follow != null and is_instance_valid(_follow):
		return Vector3(_follow.position.x, 0.0, _follow.position.z)
	return Vector3(_target.x, 0.0, _target.z)


## Ground direction the camera looks along, from the rig's own yaw. Used for the
## look-ahead so "forward" is always away from the viewer.
func ground_forward() -> Vector3:
	var bas := global_transform.basis
	var flat := Vector3(-bas.z.x, 0.0, -bas.z.z)
	if flat.length() < 0.001:
		return Vector3(0.0, 0.0, -1.0)
	return flat.normalized()


## Critically damped spring (the "SmoothDamp" of every camera in this genre),
## written with the exponential form so one call per frame is enough and the
## result does not depend on the frame rate.
func _smooth_damp(current: Vector3, goal: Vector3, delta: float) -> Vector3:
	var smooth := maxf(0.0001, smooth_time_s)
	var omega := 2.0 / smooth
	var x := omega * delta
	var expo := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := current - goal
	var temp := (_vel + change * omega) * delta
	_vel = (_vel - temp * omega) * expo
	var out := goal + (change + temp) * expo
	return out


## Spring state, for the motion test: it must not overshoot and must not depend
## on the frame rate.
func motion_state() -> Dictionary:
	return {"target": _target, "velocity": _vel}


func _apply() -> void:
	position = _target
