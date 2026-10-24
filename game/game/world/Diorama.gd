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

const WORLD_DIR := "res://game/world/"
const TEX_DIR := WORLD_DIR + "textures/"

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
	["cottage", -3.0, -1.6, 1.0, false],
	["bush", -6.2, 0.4, 1.0, false],
	["bush", -0.6, 0.8, 0.85, true],
	["rock", -9.4, 1.2, 0.9, true],
	# tree line at the back
	["pine", -11.5, -8.5, 1.0, false],
	["pine", -8.6, -9.8, 0.88, true],
	["pine", -6.5, -8.9, 1.12, true],
	["pine", -4.0, -9.8, 0.92, false],
	["pine", -1.5, -8.6, 0.96, false],
	["pine", 1.0, -9.7, 1.04, true],
	["pine", 3.0, -8.8, 1.06, false],
	["pine", 5.6, -9.9, 0.9, false],
	["pine", 8.5, -8.2, 0.98, true],
	["pine", 10.8, -9.2, 1.06, false],
	["pine", 12.2, -6.2, 1.05, false],
	["oak", -8.0, -6.0, 1.0, false],
	["oak", 7.4, -5.2, 1.04, true],
	# side screens
	["pine", -12.5, -2.0, 1.1, true],
	["pine", -12.8, 3.6, 1.0, false],
	["pine", 12.6, -1.0, 1.05, false],
	["pine", 12.9, 4.2, 1.0, true],
	# middle ground
	["bush", 5.6, 0.2, 1.0, true],
	["rock", 6.8, 3.4, 0.95, false],
	["bush", 9.2, 2.4, 0.9, false],
	# foreground framing (low, so it never hides the middle)
	["bush", -8.4, 7.4, 1.2, false],
	["bush", 7.8, 7.8, 1.15, true],
	["rock", -3.2, 8.6, 1.2, false],
	["rock", 3.4, 8.9, 1.1, true],
	# scattered detail
	["tuft", -5.4, 3.2, 1.0, false],
	["tuft", -1.8, 4.4, 1.1, true],
	["tuft", 2.2, 2.8, 0.9, false],
	["tuft", 4.6, 5.2, 1.05, true],
	["tuft", -7.6, 2.0, 0.95, false],
	["tuft", 7.0, 1.2, 1.0, true],
	["tuft", 10.2, 3.8, 0.9, false],
	["tuft", 0.4, 6.2, 1.05, false],
	["tuft", -2.4, 6.8, 0.95, true],
	["tuft", 5.2, -2.4, 1.0, false],
	["rock", 10.4, -3.2, 0.8, false],
	["bush", 2.4, -6.6, 0.9, true],
]

## Winding dirt path towards the cottage door, in world XZ.
const PATH := [
	Vector2(5.2, 9.6), Vector2(3.0, 6.2), Vector2(0.8, 3.2),
	Vector2(-1.2, 1.0), Vector2(-2.6, -0.4),
]
const PATH_WIDTH := 1.9

const GROUND_SIZE := Vector2(26.0, 20.0)

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
	env.ambient_light_color = Color(0.50, 0.56, 0.72)
	env.ambient_light_energy = 0.48
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	# warm afternoon haze -> depth without a depth-of-field pass
	env.fog_enabled = true
	env.fog_light_color = Color(0.74, 0.68, 0.62)
	env.fog_light_energy = 0.55
	env.fog_density = 0.0045
	env.fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.30
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.12

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)

	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.rotation_degrees = Vector3(-46.0, 34.0, 0.0)
	# late afternoon, not noon: keeps the greens green instead of hay-yellow
	_sun.light_color = Color(1.0, 0.96, 0.90)
	_sun.light_energy = 1.1
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
		grass, GROUND_SIZE.x / 2.0, GROUND_SIZE.y / 2.0)
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
	var uvs2 := PackedVector2Array()
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
			# ground tiling (tile size matches _build_ground's 2.0 m)
			uvs2.append(Vector2(p.x / 2.0, p.y / 2.0))
		indices.append_array([base, base + 1, base + 2, base + 1, base + 3, base + 2])
		run += seg
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uvs2
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mi := MeshInstance3D.new()
	mi.name = "Path"
	mi.mesh = mesh
	var dirt := WorldArt.tex(TEX_DIR + "path_tile.png")
	var grass_tex := WorldArt.tex(TEX_DIR + "grass_tile.png")
	var mat := ShaderMaterial.new()
	if ResourceLoader.exists(WORLD_DIR + "path.gdshader"):
		mat.shader = load(WORLD_DIR + "path.gdshader")
	mat.set_shader_parameter("dirt_tex", dirt)
	mat.set_shader_parameter("grass_tex", grass_tex)
	mat.set_shader_parameter("dirt_scale", 1.6)
	mat.set_shader_parameter("feather", 0.26)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
		# only X/Z: node.position.y already lifts the quad so its bottom edge
		# sits on the ground. Overwriting y buried the lower half of every prop
		# (the first capture showed roofs growing out of the grass).
		node.position.x = x
		node.position.z = z
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
	_camera.bounds = Vector2(GROUND_SIZE.x * 0.5 - 4.0, GROUND_SIZE.y * 0.5 - 3.5)
	_camera.start_zoom = 19.0
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
