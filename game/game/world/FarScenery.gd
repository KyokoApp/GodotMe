## No `class_name` on purpose - see WorldArt.gd.
extends Node3D
## Everything the camera sees when it looks past the edge of the map: a gradient
## sky, two rings of distant ridges, and the haze plain the map sits on.
##
## Why this exists: with the step-2 lens (pitch 38, aimed straight down at a
## miniature) the top of the frame was always ground, so the world could end in
## void and nobody noticed. Step 3A tilts the camera to ~30 degrees and the
## horizon becomes part of every shot - the void turned into a black band, and
## the old flat background colour became a grey wall behind the hills.
##
## The design follows what HD-2D actually does: the sky is a gradient that
## follows the day phase, the far hills are faint blue-grey silhouettes that never
## come closer, and the ground beyond the map dissolves into the same haze as the
## horizon so there is no visible edge anywhere.
##
## Cost: three static meshes, no shadows, no lights, one material each. The rings
## are rebuilt once at boot (a few hundred triangles) and then only tinted.

const RIDGE_SHADER := "res://game/world/far_ridge.gdshader"

## Radii are chosen so the rings never sit inside the 192 m region: the map's
## half-diagonal is 136 m, so even standing in a corner the near ring is outside
## the world. They follow the camera, so they never get closer.
const NEAR_RADIUS := 175.0
const FAR_RADIUS := 320.0
const SEGMENTS := 96

var _sky: ProceduralSkyMaterial
var _near: MeshInstance3D
var _far: MeshInstance3D
var _plain: MeshInstance3D
var _sky_top := Color(0.40, 0.42, 0.60)
var _haze := Color(0.76, 0.70, 0.64)
var _ridge_colour := Color(0.34, 0.33, 0.44)
var _sky_res: Sky


## Builds the sky and the hills and hands the sky to the world environment.
## Called by the diorama right after it builds its `Environment`.
func setup(env: Environment) -> void:
	_sky = ProceduralSkyMaterial.new()
	_sky.sky_top_color = _sky_top
	_sky.sky_horizon_color = _haze
	_sky.sky_curve = 0.12
	_sky.sky_energy_multiplier = 1.0
	# below the horizon: the same haze, so a look past the map's edge reads as a
	# misty lowland instead of a hole
	_sky.ground_bottom_color = _haze
	_sky.ground_horizon_color = _haze
	_sky.ground_curve = 0.04
	_sky.sun_angle_max = 0.0
	_sky.sun_curve = 1.0

	_sky_res = Sky.new()
	_sky_res.sky_material = _sky
	if env != null:
		env.background_mode = Environment.BG_SKY
		env.sky = _sky_res
		# a little of the sky is fogged, or the horizon line is a hard seam
		env.fog_sky_affect = 0.35

	_near = _make_ring("RidgeNear", NEAR_RADIUS, 9.0, 26.0, 3.1)
	_far = _make_ring("RidgeFar", FAR_RADIUS, 22.0, 62.0, 7.7)
	_plain = _make_plain()
	_apply_colours()
	print("[WORLD] horizon siap: langit bergradien, 2 lapis pegunungan, hamparan kabut")


func sky() -> Sky:
	return _sky_res


## Day phase: the sky top, the haze (which is also the fog colour, so the ground
## and the horizon cannot disagree), and the ridge tint.
func set_phase(sky_top: Color, haze: Color, ridge: Color) -> void:
	_sky_top = sky_top
	_haze = haze
	_ridge_colour = ridge
	_apply_colours()


func _apply_colours() -> void:
	if _sky != null:
		_sky.sky_top_color = _sky_top
		_sky.sky_horizon_color = _haze
		_sky.ground_bottom_color = _haze
		_sky.ground_horizon_color = _haze
	for ring in [_near, _far]:
		var mi := ring as MeshInstance3D
		if mi == null:
			continue
		var mat := mi.material_override as ShaderMaterial
		if mat == null:
			continue
		mat.set_shader_parameter("base_color", _haze)
		mat.set_shader_parameter("crest_color", _ridge_colour)
	if _plain != null:
		var pmat := _plain.material_override as StandardMaterial3D
		if pmat != null:
			pmat.albedo_color = _haze


## Keep the rings centred on the camera so they never get closer and never run
## out. Called every frame by the diorama.
func follow(center: Vector2) -> void:
	for ring in [_near, _far]:
		var mi := ring as MeshInstance3D
		if mi != null:
			mi.position = Vector3(center.x, 0.0, center.y)


func _make_ring(node_name: String, radius: float, low: float, high: float,
		seed_phase: float) -> MeshInstance3D:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in range(SEGMENTS + 1):
		var a := TAU * float(i) / float(SEGMENTS)
		# three sines of different frequency: a ridge line with peaks and saddles
		# that never repeats visibly, and the same every boot
		var wave := 0.55 + 0.28 * sin(a * 3.0 + seed_phase) \
			+ 0.18 * sin(a * 7.0 + seed_phase * 1.7) \
			+ 0.10 * sin(a * 13.0 + seed_phase * 0.6)
		var crest := low + (high - low) * clampf(wave, 0.0, 1.0)
		verts.append(Vector3(cos(a) * radius, -1.0, sin(a) * radius))
		uvs.append(Vector2(float(i) / float(SEGMENTS), 0.0))
		verts.append(Vector3(cos(a) * radius, crest, sin(a) * radius))
		uvs.append(Vector2(float(i) / float(SEGMENTS), 1.0))
	for i in range(SEGMENTS):
		var b0 := i * 2
		var t0 := i * 2 + 1
		var b1 := (i + 1) * 2
		var t1 := (i + 1) * 2 + 1
		idx.append_array([b0, t0, t1, b0, t1, b1])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 1.0
	var mat := ShaderMaterial.new()
	if ResourceLoader.exists(RIDGE_SHADER):
		mat.shader = load(RIDGE_SHADER)
	mi.material_override = mat
	add_child(mi)
	return mi


## The map sits on a haze plain, so walking to the last row of tiles shows misted
## lowland instead of the void. Below the lowest walkable tile (0,12 m) and below
## the water surface (-0,14 m).
func _make_plain() -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2(2400.0, 2400.0)
	var mi := MeshInstance3D.new()
	mi.name = "HazePlain"
	mi.mesh = plane
	mi.position = Vector3(0.0, -0.6, 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = _haze
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	add_child(mi)
	return mi
