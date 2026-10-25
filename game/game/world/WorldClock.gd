extends Node
## The world clock. One number walks a full day; everything the light does is
## read from it.
##
## Before this file the only "time" in the game was a boolean: `set_time_of_day(
## true/false)` flipped the sun and the fog to a fixed night, and nothing else.
## Phase 6 asks for pagi-siang-sore-malam, so the diorama now owns a real cycle
## and the old boolean simply jumps to a phase - the test hook that VisualTest
## has always used keeps working.
##
## No `class_name`: this script is loaded out of a .pck into the launcher's
## project, whose global class cache never saw it (see Actor.gd for the black
## screen that taught us this).

signal phase_changed(id: String)

## How long one full day takes in real seconds. Eight minutes: long enough that
## the light feels like weather instead of a strobe, short enough that a player
## who keeps the app open for a session sees the evening arrive.
const DAY_SECONDS := 480.0

## Written out rather than computed, because these are art decisions: the sun is
## warm and low in the morning, white and high at noon, gold and raking at dusk,
## and a weak blue moon at night. Fog is thickest at dawn (that is when a valley
## actually fogs up) and thinnest at noon.
const PHASES := [
	{
		"id": "pagi",
		"sun_color": Color(1.0, 0.92, 0.82),
		"sun_energy": 0.78,
		"sun_rot": Vector3(-16.0, 62.0, 0.0),
		"ambient": Color(0.56, 0.62, 0.76),
		"ambient_energy": 0.50,
		"fog": Color(0.80, 0.80, 0.80),
		"fog_density": 0.0090,
		"sky": Color(0.52, 0.50, 0.50),
		"lamp": 0.10,
	},
	{
		"id": "siang",
		"sun_color": Color(1.0, 0.97, 0.92),
		"sun_energy": 1.15,
		"sun_rot": Vector3(-52.0, 26.0, 0.0),
		"ambient": Color(0.52, 0.58, 0.72),
		"ambient_energy": 0.46,
		"fog": Color(0.74, 0.71, 0.67),
		"fog_density": 0.0034,
		"sky": Color(0.46, 0.40, 0.36),
		"lamp": 0.0,
	},
	{
		"id": "sore",
		"sun_color": Color(1.0, 0.82, 0.60),
		"sun_energy": 1.12,
		"sun_rot": Vector3(-40.0, 40.0, 0.0),
		"ambient": Color(0.60, 0.50, 0.56),
		"ambient_energy": 0.46,
		"fog": Color(0.80, 0.62, 0.48),
		"fog_density": 0.0055,
		"sky": Color(0.44, 0.36, 0.32),
		"lamp": 0.45,
	},
	{
		"id": "malam",
		"sun_color": Color(0.60, 0.70, 1.0),
		"sun_energy": 0.30,
		"sun_rot": Vector3(-30.0, 118.0, 0.0),
		"ambient": Color(0.20, 0.26, 0.44),
		"ambient_energy": 0.34,
		"fog": Color(0.24, 0.29, 0.42),
		"fog_density": 0.0048,
		"sky": Color(0.12, 0.15, 0.24),
		"lamp": 1.25,
	},
]

var sun: DirectionalLight3D
var env: Environment
var lamp: OmniLight3D
## 0..1 through the whole cycle. 0 = first instant of pagi.
var day := 0.0
var running := true

var _last_phase := ""


func setup(sun_node: DirectionalLight3D, env_ref: Environment,
		lamp_node: OmniLight3D = null) -> void:
	sun = sun_node
	env = env_ref
	lamp = lamp_node
	_apply()


func _process(delta: float) -> void:
	if not running:
		return
	advance(delta)


## Move the clock by real seconds. Exposed so a test can walk a whole day in one
## call instead of waiting eight minutes.
func advance(seconds: float) -> void:
	if seconds <= 0.0:
		return
	day = fposmod(day + seconds / DAY_SECONDS, 1.0)
	_apply()


## Jump to the settled middle of a phase ("pagi" / "siang" / "sore" / "malam").
## The middle, not the start: 0.0 of a phase is where the previous one is still
## blending out, and a capture taken there looks like a mistake.
func set_phase(id: String) -> void:
	var index := phase_index(id)
	if index < 0:
		push_warning("[WORLD] fase tidak dikenal: %s" % id)
		return
	day = (float(index) + 0.35) / float(PHASES.size())
	_apply()


func phase_index(id: String) -> int:
	for i in range(PHASES.size()):
		if String(PHASES[i]["id"]) == id:
			return i
	return -1


func phase_name() -> String:
	return String(PHASES[_segment()]["id"])


func phase_ids() -> Array:
	var out: Array = []
	for p in PHASES:
		out.append(String(p["id"]))
	return out


## The old boolean hook (VisualTest used it from phase 2): night is a phase now.
func set_time_of_day(night: bool) -> void:
	set_phase("malam" if night else "sore")


func _segment() -> int:
	return clampi(int(day * float(PHASES.size())), 0, PHASES.size() - 1)


## Blend factor towards the NEXT phase. Zero for most of a phase, then a smooth
## ramp over its last third, so the light sits still long enough to be read as a
## time of day instead of sliding continuously.
func _blend() -> float:
	var u := day * float(PHASES.size())
	var frac: float = u - floorf(u)
	return smoothstep(0.62, 1.0, frac)


func _apply() -> void:
	if sun == null or env == null:
		return
	var i := _segment()
	var a: Dictionary = PHASES[i]
	var b: Dictionary = PHASES[(i + 1) % PHASES.size()]
	var t := _blend()

	sun.light_color = (a["sun_color"] as Color).lerp(b["sun_color"] as Color, t)
	sun.light_energy = lerpf(float(a["sun_energy"]), float(b["sun_energy"]), t)
	sun.rotation_degrees = (a["sun_rot"] as Vector3).lerp(b["sun_rot"] as Vector3, t)

	env.ambient_light_color = (a["ambient"] as Color).lerp(b["ambient"] as Color, t)
	env.ambient_light_energy = lerpf(float(a["ambient_energy"]), float(b["ambient_energy"]), t)
	env.fog_light_color = (a["fog"] as Color).lerp(b["fog"] as Color, t)
	env.fog_density = lerpf(float(a["fog_density"]), float(b["fog_density"]), t)
	env.background_color = (a["sky"] as Color).lerp(b["sky"] as Color, t)

	if lamp != null:
		lamp.light_energy = lerpf(float(a["lamp"]), float(b["lamp"]), t)

	var id := phase_name()
	if id != _last_phase:
		_last_phase = id
		phase_changed.emit(id)
