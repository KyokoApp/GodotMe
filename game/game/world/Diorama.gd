class_name Diorama
extends Node3D
## The first HD-2D diorama: a small glade on the edge of the vale.
##
## Everything here is placed, not painted: sprites come from PNG files in
## res://game/world/textures and are attached to billboarded quads, so one 2D
## sprite gets a real 3D sun, real shadows and real depth sorting - the trick
## that makes HD-2D read as a diorama instead of a flat side-scroller.
##
## No character logic lives here (Phase 2 stage 1 is the engine, not an actor).

const TEX_DIR := "res://game/world/textures/"

const AREA_NAME := "Lembah Senja"
const AREA_SUBTITLE := "Yaros, awal perjalanan"

## Sprite size in metres (w, h) at scale 1.
const PROP_SIZE := {
	"pine": Vector2(3.2, 5.4),
	"oak": Vector2(5.4, 4.0),
	"cottage": Vector2(5.6, 4.2),
	"bush": Vector2(1.5, 1.2),
	"rock": Vector2(1.9, 1.3),
	"tuft": Vector2(0.9, 0.7),
}

const PROP_TEXTURE := {
	"pine": "tree_pine.png",
	"oak": "tree_oak.png",
	"cottage": "cottage.png",
	"bush": "bush.png",
	"rock": "rock.png",
	"tuft": "bush.png",
}

## Hand-placed layout: kind, x, z, scale, flip.
const LAYOUT := [
	# the cottage and its doorstep
	["cottage", -4.2, -3.0, 1.0, false],
	["bush", -7.4, -1.2, 1.0, false],
	["bush", -1.4, -1.0, 0.85, true],
	["rock", -6.6, 1.4, 0.9, true],
	# tree line at the back, denser on the left
	["pine", -13.0, -11.0, 1.0, false],
	["pine", -9.0, -13.2, 1.12, true],
	["pine", -4.4, -12.0, 0.94, false],
	["pine", 0.6, -13.4, 1.06, false],
	["pine", 5.2, -11.6, 0.9, true],
	["pine", 9.6, -13.0, 1.08, false],
	["pine", 13.6, -10.2, 0.96, true],
	["oak", -11.4, -4.6, 1.0, false],
	["oak", 8.2, -5.2, 1.04, true],
	["oak", 13.4, 0.4, 0.92, false],
	# side screens
	["pine", -15.4, -2.0, 1.16, true],
	["pine", -14.2, 5.6, 1.02, false],
	["pine", 15.8, -4.4, 1.12, false],
	["pine", 16.4, 6.2, 1.0, true],
	# foreground framing (kept low so it never hides the middle)
	["bush", -10.8, 8.6, 1.1, false],
	["bush", 6.4, 9.4, 1.0, true],
	["rock", -8.2, 11.0, 1.15, false],
	["rock", 10.2, 10.6, 1.0, true],
	["bush", 1.8, 11.4, 0.95, false],
	# scattered detail
	["tuft", -6.0, 4.2, 1.0, false],
	["tuft", -2.6, 5.6, 1.1, true],
	["tuft", 3.4, 3.8, 0.9, false],
	["tuft", 5.0, 6.4, 1.05, true],
	["tuft", -9.6, 2.6, 0.95, false],
	["tuft", 8.8, 2.2, 1.0, true],
	["tuft", 11.4, 4.6, 0.9, false],
	["tuft", 0.2, 7.4, 1.05, false],
	["rock", 12.2, -1.6, 0.8, false],
	["bush", 2.6, -8.4, 0.9, true],
]

## Winding dirt path towards the cottage door, in world XZ.
const PATH := [
	Vector2(-15.0, 13.0), Vector2(-11.0, 10.2), Vector2(-8.0, 7.0),
	Vector2(-6.2, 3.4), Vector2(-4.6, 0.2), Vector2(-4.2, -1.2),
]
const PATH_WIDTH := 1.9

const GROUND_SIZE := Vector2(46.0, 36.0)

var _sun: DirectionalLight3D
var _camera: DioramaCamera


func _ready() -> void:
	_build_environment()
	_build_ground()
	_build_path()
	_build_props()
	_build_camera()


# --------------------------------------------------------------- lighting ----
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.42, 0.35, 0.30)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.68)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.92
	env.tonemap_white = 6.0
	# warm afternoon haze -> depth without a depth-of-field pass
	env.fog_enabled = true
	env.fog_light_color = Color(0.86, 0.68, 0.48)
	env.fog_light_energy = 0.9
	env.fog_density = 0.011
	env.fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.04

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)

	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.rotation_degrees = Vector3(-46.0, 34.0, 0.0)
	# late afternoon, not noon: keeps the greens green instead of hay-yellow
	_sun.light_color = Color(1.0, 0.94, 0.84)
	_sun.light_energy = 0.95
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.directional_shadow_max_distance = 60.0
	_sun.shadow_bias = 0.04
	_sun.shadow_normal_bias = 1.2
	_sun.shadow_blur = 1.4
	add_child(_sun)


# ----------------------------------------------------------------- ground ----
func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = GROUND_SIZE
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = plane
	var grass := WorldArt.tex(TEX_DIR + "grass_tile.png")
	mi.material_override = WorldArt.ground_material(
		grass, GROUND_SIZE.x / 2.3, GROUND_SIZE.y / 2.3)
	add_child(mi)

	# A darker skirt around the meadow so the world does not end in mid-air.
	var skirt := PlaneMesh.new()
	skirt.size = GROUND_SIZE + Vector2(40.0, 40.0)
	var base := MeshInstance3D.new()
	base.name = "Skirt"
	base.mesh = skirt
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.16, 0.20, 0.14)
	m.roughness = 1.0
	base.material_override = m
	base.position.y = -0.35
	add_child(base)


func _build_path() -> void:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var norms := PackedVector3Array()
	var indices := PackedInt32Array()
	var run := 0.0
	for i in range(PATH.size() - 1):
		var a: Vector2 = PATH[i]
		var b: Vector2 = PATH[i + 1]
		var dir: Vector2 = (b - a).normalized()
		var side: Vector2 = Vector2(-dir.y, dir.x) * (PATH_WIDTH * 0.5)
		var seg: float = a.distance_to(b)
		var base := verts.size()
		for corner in [[a - side, 0.0], [a + side, 1.0], [b - side, 0.0], [b + side, 1.0]]:
			var p: Vector2 = corner[0]
			var across: float = corner[1]
			verts.append(Vector3(p.x, 0.02, p.y))
			norms.append(Vector3.UP)
			uvs.append(Vector2(across, run / 2.2))
		indices.append_array([base, base + 1, base + 2, base + 1, base + 3, base + 2])
		run += seg
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mi := MeshInstance3D.new()
	mi.name = "Path"
	mi.mesh = mesh
	var dirt := WorldArt.tex(TEX_DIR + "path_tile.png")
	mi.material_override = WorldArt.ground_material(dirt, 1.0, 1.0)
	add_child(mi)


# ------------------------------------------------------------------ props ----
func _build_props() -> void:
	var root := Node3D.new()
	root.name = "Props"
	add_child(root)
	for entry in LAYOUT:
		var kind := String(entry[0])
		var x: float = entry[1]
		var z: float = entry[2]
		var s: float = entry[3]
		var flip: bool = entry[4]
		var node := _make_prop(kind, s, flip)
		if node == null:
			continue
		node.position = Vector3(x, 0.0, z)
		root.add_child(node)
	# painter's order for the shadow caster list; billboards still face the camera
	root.sort_children = true


func _make_prop(kind: String, s: float, flip: bool) -> Node3D:
	var size: Vector2 = PROP_SIZE[kind]
	var texture := WorldArt.tex(TEX_DIR + String(PROP_TEXTURE[kind]))
	if texture == null:
		return null
	var quad := QuadMesh.new()
	quad.size = size
	var mi := MeshInstance3D.new()
	mi.name = kind
	mi.mesh = quad
	var tint := Color.WHITE
	if kind == "tuft":
		tint = Color(0.92, 0.98, 0.88)
	mi.material_override = WorldArt.sprite_material(texture, tint)
	# stand the sprite on the ground: the quad is centred on its origin
	mi.position.y = size.y * 0.5
	mi.scale = Vector3(s * (-1.0 if flip else 1.0), s, s)
	mi.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if kind == "tuft"
		else GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	return mi


# ----------------------------------------------------------------- camera ----
func _build_camera() -> void:
	_camera = DioramaCamera.new()
	_camera.name = "CameraRig"
	_camera.bounds = Vector2(GROUND_SIZE.x * 0.5 - 6.0, GROUND_SIZE.y * 0.5 - 6.0)
	_camera.start_zoom = 30.0
	add_child(_camera)
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.fov = 30.0
	cam.near = 0.5
	cam.far = 120.0
	cam.position = Vector3(0.0, 0.0, _camera.start_zoom)
	cam.current = true
	_camera.add_child(cam)


func reset_view() -> void:
	if _camera != null:
		_camera.reset()
