extends Node3D
## Streams REGION "Yaros" into the scene, one 32x32 chunk at a time.
##
## What lives here and what does not: this node owns geometry only - meshes,
## materials, prop instances, and the loading/unloading of chunks around the
## player. Where the player may stand, how high a tile is and where the roads go
## is RegionData's business; light, weather and the camera are the diorama's.
##
## Why streaming at all: the region is 192x192 tiles = 36 864 tiles. Built at
## once that is ~150 000 vertices and a mesh the size of a small town in memory,
## which a mid-range phone will not hold next to the character atlas. The camera
## never sees more than ~50 m, so only the chunks around the player exist as
## nodes. Everything else is bytes in the JSON.
##
## Threading: chunk arrays are pure maths (RegionMesh.build reads the byte grids
## and returns PackedArrays), so they are built on the WorkerThreadPool while the
## frame keeps drawing, then uploaded on the main thread - an ArrayMesh upload
## is a memcpy of a few hundred kilobytes, not a stall. `force_build()` exists
## for the two moments where waiting is honest: the first frame and a teleport,
## both of which happen behind a fade.

const DATA_SCRIPT := "res://game/world/RegionData.gd"
const MESH_SCRIPT := "res://game/world/RegionMesh.gd"
const TEX_DIR := "res://game/world/textures/"
const ATLAS := TEX_DIR + "terrain_atlas.png"
const WATER_TEX := TEX_DIR + "water_tile.png"
const PROP_ATLAS := TEX_DIR + "prop_atlas.png"
const PROP_META := "res://game/world/prop_atlas.json"
const PROP_SHADER := "res://game/world/prop.gdshader"
const BUILD_SCRIPT := "res://game/world/BuildingKit.gd"
const BUILD_SHADER := "res://game/world/building.gdshader"
const BUILD_ATLAS := TEX_DIR + "building_atlas.png"
const WATER_SHADER := "res://game/world/water.gdshader"
const TERRAIN_SHADER := "res://game/world/terrain.gdshader"
const CLIFF_SHADER := "res://game/world/cliff.gdshader"
const WOOD_SHADER := "res://game/world/wood.gdshader"
## Surfaces inside one chunk mesh, in the order they are built.
const SURFACES := ["terrain", "cliff", "wood", "water"]

## Decor kinds that step 3B draws as low-poly MESHES assembled from the building
## kit, instead of as a camera-facing sprite. Everything else in decor (pine,
## oak, bush, rock, reeds, flowers, stump) stays a billboard on purpose: the
## forest was painted as sprites and a mesh pine would lose that look.
const BUILDING_KINDS := ["cottage", "tower", "gate", "well", "dock", "sign", "torch"]

## How many chunks around the player's own chunk stay visible. 1 => 3x3 chunks
## = 96x96 m, which is wider than the camera can see at any zoom on the ladder.
const RADIUS_MAX := 2

var data: RefCounted
var view_radius := 1
## Chunks are built one ring further out than they are shown, so the next chunk
## is ready before the player walks into it.
var prefetch := true
## Bake chunks on WorkerThreadPool tasks. Off on a headless run: building the
## arrays needs no GPU, so nothing is gained by threads there, the tests get the
## worst case (one thread) as their measurement, and the process can exit without
## a baker task alive underneath it - which is what the intermittent
## "all checks green, exit 134" crash at teardown turned out to be.
var threaded := true

var _terrain_mat: ShaderMaterial
var _cliff_mat: ShaderMaterial
var _wood_mat: ShaderMaterial
var _water_mat: ShaderMaterial
var _prop_mats: Dictionary = {}     # kind -> ShaderMaterial with its atlas cell
var _prop_mms: Dictionary = {}      # kind -> MultiMeshInstance3D
var _tall: Array = []               # [kind, index, x, z, height] of occluders
var _layout: Array = []             # [kind, x, z, w, h, ground] every placed prop
var _tex_cache: Dictionary = {}     # path -> ImageTexture
var _faded: Dictionary = {}         # "kind/index" -> 0.0 while dissolved
var _quad: ArrayMesh
var _chunks: Dictionary = {}        # Vector2i -> Node3D
var _prop_size: Dictionary = {}     # kind -> Vector2 metres
var _kit: RefCounted                # BuildingKit instance, loaded at runtime
var _kit_meta: Dictionary = {}      # building_kit.json
var _build_mat: ShaderMaterial
var _build_mms: Dictionary = {}     # "kind|variant" -> MultiMeshInstance3D
var _build_layout: Array = []       # [kind, variant, x, z, y, yaw, top, block]
var _build_tall: Array = []         # [mmkey, index, x, z, height] occluders
var _build_faded: Dictionary = {}   # "b:mmkey/index" -> fade
var _centres: Array = []            # centre chunk as Vector2i
var _pending: Dictionary = {}       # Vector2i -> task id
var _task_chunk: Dictionary = {}    # task id -> Vector2i
var _queue: Array = []
var _pending_arrays: Dictionary = {}
var _stats := {
	"chunks": 0, "vertices": 0, "props": 0, "draws": 0,
	"build_ms_total": 0.0, "build_ms_worst": 0.0, "built": 0, "unloaded": 0,
}


func setup(region: RefCounted, radius: int = 1) -> void:
	data = region
	view_radius = clampi(radius, 0, RADIUS_MAX)
	# DisplayServer, not OS.has_feature("headless"): the feature tag is only set on
	# a headless export template, so `godot --headless` in CI kept threading on and
	# the process could abort at teardown with a baker task in flight.
	if DisplayServer.get_name() == "headless":
		threaded = false
	_stats["build_ms_total"] = 0.0
	_build_materials()
	_build_quad()
	_build_props()
	_build_buildings()
	set_process(true)


# ------------------------------------------------------------------ setup ----
func _build_materials() -> void:
	var atlas := _tex(ATLAS)
	_terrain_mat = _shader_material(TERRAIN_SHADER, {
		"atlas": atlas,
		"tile_scale": 2.0,
		"cell_grass": Vector2(0.0, 0.0),
		"cell_dirt": Vector2(0.25, 0.0),
		"cell_sand": Vector2(0.5, 0.0),
		"cell_cliff": Vector2(0.75, 0.0),
		"cell_snow": Vector2(0.0, 0.5),
	})
	_cliff_mat = _shader_material(CLIFF_SHADER, {
		"atlas": atlas,
		"cell_cliff": Vector2(0.75, 0.0),
		"tile_scale": 2.0,
		"window_radius": 2.6,
	})
	_wood_mat = _shader_material(WOOD_SHADER, {
		"atlas": atlas,
		"cell_wood": Vector2(0.5, 0.5),
		"tile_scale": 1.0,
	})
	_water_mat = _shader_material(WATER_SHADER, {
		"water_tex": _tex(WATER_TEX),
		# the tile is raw sRGB bytes, so these are sRGB values too (see _tex)
		"shallow_tint": Color(0.42, 0.56, 0.56),
		"deep_tint": Color(0.20, 0.31, 0.38),
		"foam_tint": Color(0.92, 0.95, 0.90),
	})
	# props get one material each, built in _build_props(): the atlas cell and the
	# sprite size differ per kind, and a kind per material keeps the shader free of
	# per-instance branching


## A ShaderMaterial with its uniforms already set; null shader means the material
## still exists (grey) instead of the whole world failing to draw.
func _shader_material(path: String, params: Dictionary) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	if ResourceLoader.exists(path):
		mat.shader = load(path)
	for key in params.keys():
		if params[key] != null:
			mat.set_shader_parameter(String(key), params[key])
	return mat


func _prop_meta() -> Dictionary:
	if not FileAccess.file_exists(PROP_META):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROP_META))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


## World textures are read as PNG BYTES, exactly as WorldArt.tex() has done since
## step 1. This is not a style choice: a PNG imported by the editor is flagged
## sRGB, so the GPU linearises every sample before the shader sees it, and the
## grass tile - which is a dark forest green in sRGB - arrives almost black. That
## single difference turned the valley's lawn into the brown smear the first
## region captures showed. Raw ImageTexture samples keep the tile's own colours,
## which is the look the valley was approved with.
func _tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	if not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		push_error("[REGION] PNG rusak: %s" % path)
		return null
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[path] = tex
	return tex


## A single quad, -0.5..0.5 in x and y. The prop shader rebuilds the billboard
## from the instance transform, so one quad serves every sprite in the atlas.
func _build_quad() -> void:
	var verts := PackedVector3Array([
		Vector3(-0.5, -0.5, 0.0), Vector3(0.5, -0.5, 0.0),
		Vector3(-0.5, 0.5, 0.0), Vector3(0.5, 0.5, 0.0)])
	var uvs := PackedVector2Array([
		Vector2(0.0, 1.0), Vector2(1.0, 1.0),
		Vector2(0.0, 0.0), Vector2(1.0, 0.0)])
	var idx := PackedInt32Array([0, 1, 2, 2, 1, 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_quad = mesh


## Read the atlas manifest once: which cell holds which prop, how big that prop
## is in metres, and place every decoration in the world. One file, so the art
## tool and the mesher cannot drift apart.
func _build_props() -> void:
	var meta := _prop_meta()
	if meta.is_empty():
		push_warning("[REGION] prop_atlas.json tidak ada, prop dunia dilewati")
		return
	var decor: Dictionary = data.get("decor") if data != null else {}
	if typeof(decor) != TYPE_DICTIONARY:
		return
	for raw in meta.get("cells", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var cell: Dictionary = raw
		var kind := String(cell.get("kind", ""))
		var uv: Array = cell.get("uv", [])
		var sz: Array = cell.get("size_m", [1.0, 1.0])
		if kind == "" or uv.size() < 4 or sz.size() < 2:
			continue
		# a house is a mesh now (step 3B): its atlas cell is still in the prop
		# sheet so the old captures keep working, but nothing draws it
		if BUILDING_KINDS.has(kind):
			continue
		_prop_size[kind] = Vector2(float(sz[0]), float(sz[1]))
		var mat := ShaderMaterial.new()
		if ResourceLoader.exists(PROP_SHADER):
			mat.shader = load(PROP_SHADER)
			mat.set_shader_parameter("albedo_tex", _tex(PROP_ATLAS))
			mat.set_shader_parameter("scissor", 0.42)
			mat.set_shader_parameter("cell_rect",
				Vector4(float(uv[0]), float(uv[1]), float(uv[2]), float(uv[3])))
		_prop_mats[kind] = mat
		_place_kind(kind, decor.get(kind, []))


## One MultiMesh per prop kind for the WHOLE region, not one per chunk. The
## instances never change once placed, so the GPU keeps one buffer per kind and a
## chunk coming or going costs nothing on the prop side; the billboard turns the
## quad towards the camera in the vertex shader, which a MultiMesh cannot do.
func _place_kind(kind: String, list: Variant) -> void:
	if typeof(list) != TYPE_ARRAY or _prop_mats.is_empty():
		return
	var rows: Array = list
	if rows.is_empty():
		return
	var mat: ShaderMaterial = _prop_mats.get(kind, null)
	if mat == null or mat.shader == null:
		return
	var size: Vector2 = _prop_size.get(kind, Vector2.ONE)
	# Pass one: keep only the rows that are really there. Instance data is only
	# handed to the GPU once instance_count is final, so no transform is ever
	# written into a buffer that a later resize would throw away.
	var good: Array = []
	for raw in rows:
		if typeof(raw) != TYPE_ARRAY:
			continue
		var row: Array = raw
		if row.size() < 2:
			continue
		good.append(row)
	if good.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _quad
	mm.instance_count = good.size()
	# the shader moves the quad towards the camera, so the AABB has to be the
	# whole region or Godot culls the sprite that is behind the camera
	mm.custom_aabb = AABB(Vector3(-8.0, -4.0, -8.0), Vector3(
		float(data.get("width")) * float(data.get("cell")) + 16.0,
		48.0,
		float(data.get("height")) * float(data.get("cell")) + 16.0))
	for i in range(good.size()):
		var row: Array = good[i]
		# decor is stored in tenths of a metre, in world XZ
		var x := float(row[0]) * 0.1
		var z := float(row[1]) * 0.1
		var scale := float(row[2]) * 0.01 if row.size() > 2 else 1.0
		var mirror := 0.0
		if row.size() > 3 and int(row[3]) % 2 == 1:
			mirror = 1.0
		var w := size.x * scale
		var h := size.y * scale
		var ground := float(data.call("height_at", Vector2(x, z)))
		mm.set_instance_transform(i, Transform3D(
			Basis().scaled(Vector3(w, h, 1.0)),
			Vector3(x, ground + h * 0.5, z)))
		# the transform actually given to the MultiMesh, so the rules test can
		# compare the sprite's feet with the ground instead of trusting a comment
		_layout.append([kind, x, z, w, h, ground + h * 0.5])
		# r = fade, g = mirror, b = shade. The shade breaks up a row of identical
		# sprites without a second texture; it is a hash of the position, so it is
		# stable across frames.
		var shade := 0.9 + 0.1 * fposmod(sin(x * 12.9898 + z * 78.233) * 43758.5453, 1.0)
		mm.set_instance_color(i, Color(1.0, mirror, shade, 1.0))
		if h > 1.3:
			_tall.append([kind, i, x, z, h])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Props_%s" % kind
	mmi.multimesh = mm
	mmi.material_override = mat
	# billboards shadow badly (the quad turns to the camera, so its shadow does
	# too); the trees get a soft blob from the actor's shadow sprite instead
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	_prop_mms[kind] = mmi
	_stats["props"] = int(_stats.get("props", 0)) + mm.instance_count


# --------------------------------------------------------------- buildings ---
## Step 3B: the village is no longer a row of cardboard cut-outs. Every house,
## tower, gate, well, jetty, sign and torch is a low-poly MESH assembled from
## `BuildingKit.gd` out of one 512 px atlas, so it turns with the camera, casts a
## real shadow and stands ON the hill instead of being pasted over it.
##
## Why the meshes are built here and not shipped as .glb: the kit code is the one
## source of truth. A file can be forgotten by the next person who changes a
## roof, a function cannot - and the whole village is ten small meshes, built
## once in a few milliseconds and then shared by every instance of that kind.
##
## Batching: one MultiMesh per (kind, variant) for the WHOLE region, exactly like
## the props. The five cottages are three shapes, so the village is 10 draw
## calls; the per-house tint rides in the instance colour and the per-house fade
## in the instance custom data, so one pass draws houses that dissolve
## independently when the camera passes in front of them.
func _build_buildings() -> void:
	if data == null or not ResourceLoader.exists(BUILD_SCRIPT):
		push_warning("[REGION] BuildingKit.gd tidak ada, bangunan 3D dilewati")
		return
	var decor: Variant = data.get("decor")
	if typeof(decor) != TYPE_DICTIONARY:
		return
	var kit_script: Script = load(BUILD_SCRIPT)
	if kit_script == null:
		return
	_kit = kit_script.new()
	if _kit == null:
		return
	_kit_meta = _kit.call("kit_meta")
	if _kit_meta.is_empty():
		push_warning("[REGION] building_kit.json tidak ada, bangunan 3D dilewati")
		return
	var atlas := _tex(BUILD_ATLAS)
	if atlas == null:
		push_warning("[REGION] building_atlas.png tidak ada")
		return
	_build_mat = ShaderMaterial.new()
	if ResourceLoader.exists(BUILD_SHADER):
		_build_mat.shader = load(BUILD_SHADER)
	_build_mat.set_shader_parameter("atlas", atlas)
	# 128 px cells in a 512 px sheet: a constant, because every cell is the same
	# size and the shader therefore needs no table
	_build_mat.set_shader_parameter("cell_size", 128.0 / 512.0)
	# the fade of a building comes from its instance custom data, not a uniform:
	# one MultiMesh holds the whole village
	_build_mat.set_shader_parameter("instance_fade", 1.0)
	# the flame cell is the one that animates; the kit's manifest is the only
	# place that knows where it sits in the atlas
	var cell_map: Dictionary = _kit.call("cells_of", _kit_meta)
	if cell_map.has("flame"):
		_build_mat.set_shader_parameter("flame_cell", cell_map["flame"])
	var dict: Dictionary = decor
	for kind in BUILDING_KINDS:
		var rows: Variant = dict.get(kind, [])
		if typeof(rows) != TYPE_ARRAY:
			continue
		_place_buildings(kind, rows)


## Place every decor row of one kind. Variants come from the row's own flip flag
## and a hash of its position, so the village keeps three different houses
## without the region JSON having to say which is which - and the choice is
## stable between runs.
func _place_buildings(kind: String, rows: Array) -> void:
	if _kit == null or _build_mat == null:
		return
	var kind_meta: Dictionary = (_kit_meta.get("kinds", {}) as Dictionary).get(kind, {})
	if kind_meta.is_empty():
		return
	var variants := maxi(1, int(kind_meta.get("variants", 1)))
	# pass one: read the rows and work out where each one goes, so the MultiMesh
	# is only sized once per variant
	var buckets: Dictionary = {}
	for raw in rows:
		if typeof(raw) != TYPE_ARRAY:
			continue
		var row: Array = raw
		if row.size() < 2:
			continue
		# decor is stored in tenths of a metre, in world XZ
		var x := float(row[0]) * 0.1
		var z := float(row[1]) * 0.1
		var scale := 1.0
		if row.size() > 2 and float(row[2]) > 0.0:
			scale = clampf(float(row[2]) * 0.01, 0.75, 1.35)
		var salt := 0
		if row.size() > 3:
			salt = int(row[3])
		var variant := absi(hash("%d/%d/%d" % [int(round(x * 7.0)), int(round(z * 7.0)), salt])) % variants
		var yaw := _building_yaw(kind, x, z)
		var entry := {"x": x, "z": z, "scale": scale, "variant": variant, "yaw": yaw}
		if not buckets.has(variant):
			buckets[variant] = []
		(buckets[variant] as Array).append(entry)
	for v in buckets.keys():
		var variant := int(v)
		var made: Dictionary = _kit.call("make", kind, variant, _kit_meta)
		if made.is_empty():
			push_warning("[REGION] kit tidak bisa membangun %s#%d" % [kind, variant])
			continue
		var group: Array = buckets[variant]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = made["mesh"]
		mm.instance_count = group.size()
		# the meshes are placed all over the region, so the AABB has to be the
		# whole region: a MultiMesh never moves its instances afterwards
		mm.custom_aabb = AABB(Vector3(-8.0, -8.0, -8.0), Vector3(
			float(data.get("width")) * float(data.get("cell")) + 16.0,
			64.0,
			float(data.get("height")) * float(data.get("cell")) + 16.0))
		var mmkey := "%s|%d" % [kind, variant]
		var top := float(made.get("top", 2.0))
		for i in range(group.size()):
			var e: Dictionary = group[i]
			var ex := float(e["x"])
			var ez := float(e["z"])
			var sc := float(e["scale"])
			var yaw := float(e["yaw"])
			var basis := Basis(Vector3.UP, yaw)
			if not is_equal_approx(sc, 1.0):
				basis = basis.scaled(Vector3(sc, sc, sc))
			# the FOOT of the house sits on the LOWEST corner of its footprint,
			# not on the tile centre: the guard tower stands on a 1,8 m step and
			# a house placed at the tile's average height shows daylight under
			# one corner while burying the other
			var foot := _building_foot(kind, ex, ez, yaw, sc)
			mm.set_instance_transform(i, Transform3D(basis, Vector3(ex, foot, ez)))
			# the tint is per instance so all five cottages share one mesh;
			# alpha stays 1.0 because the shader reads COLOR.a as a detail class
			var tint := _building_tint(kind, ex, ez)
			mm.set_instance_color(i, Color(tint.r, tint.g, tint.b, 1.0))
			# r = fade (see the shader): solid until the camera passes in front
			mm.set_instance_custom_data(i, Color(1.0, 0.0, 0.0, 1.0))
			# the block radius is NOT scaled: it is the collision contract from
			# step 2 (a circle on the tile), not a measurement of the model. A
			# tower drawn at 0.75 must still take the room RegionData says it takes
			_build_layout.append([kind, variant, ex, ez, foot, yaw, top * sc,
				float(made.get("block", 0.0))])
			# only the tall ones can hide the knight; a sign post cannot
			if top * sc > 2.4:
				_build_tall.append([mmkey, i, ex, ez, top * sc])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Buildings_%s_%d" % [kind, variant]
		mmi.multimesh = mm
		mmi.material_override = _build_mat
		# houses DO cast: they are the first real geometry in the valley, and a
		# village with no shadows under the eaves looks like it is floating
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mmi)
		_build_mms[mmkey] = mmi
		_stats["buildings"] = int(_stats.get("buildings", 0)) + mm.instance_count


## The lowest of the four ground heights under a building's footprint, so a house
## on a slope never floats on its downhill corner. `scale` is the instance scale
## and `yaw` its rotation, so the sampled corners are the ones that are drawn.
func _building_foot(kind: String, x: float, z: float, yaw: float, scale: float) -> float:
	var size: Vector2 = _footprint(kind) * scale
	var half := size * 0.5
	var lowest := INF
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var local := Vector2(half.x * sx, half.y * sz).rotated(-yaw)
			var p := Vector2(x, z) + local
			lowest = minf(lowest, float(data.call("height_at", p)))
	if lowest == INF:
		return float(data.call("height_at", Vector2(x, z)))
	return lowest


## Footprint in metres: the kit's real bounds, from the same JSON the mesher
## reads, so the foundation and the sampled ground agree with the drawn walls.
func _footprint(kind: String) -> Vector2:
	var kk: Dictionary = (_kit_meta.get("kinds", {}) as Dictionary).get(kind, {})
	if kk.is_empty():
		return Vector2(2.0, 2.0)
	return Vector2(float(kk.get("w", 2.0)), float(kk.get("d", 2.0)))


## Which way a building faces. Houses turn their front (the door) towards the
## middle of the zone they stand in - the village well, the tower yard, the pass -
## which is where a person walking up to it comes from. A torch or a sign post is
## symmetric, so it keeps the world's default facing.
func _building_yaw(kind: String, x: float, z: float) -> float:
	if kind != "cottage" and kind != "tower" and kind != "gate":
		return 0.0
	var centre := _zone_centre(x, z)
	var to := centre - Vector2(x, z)
	if to.length() < 0.6:
		return 0.0
	# +z is the front of every mesh, so turn +z onto the direction of the centre
	return atan2(to.x, to.y)


## Centre of the smallest zone that contains this point; the region's own point
## if no zone does.
func _zone_centre(x: float, z: float) -> Vector2:
	var p := Vector2(x, z)
	var best := Rect2()
	var best_area := INF
	for raw in data.get("zones"):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var zone: Dictionary = raw
		var rect: Array = zone.get("rect", [])
		if rect.size() < 4:
			continue
		var r := Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3]))
		if not r.has_point(p):
			continue
		var area := r.get_area()
		if area < best_area:
			best_area = area
			best = r
	if best_area == INF:
		return p
	return best.get_center()


## Per-house shade: cream plaster, warm ochre, cool grey. Deterministic from the
## position, so the same cottage is the same colour on every run and in every
## screenshot; three tones is enough to stop a row reading as clones.
func _building_tint(kind: String, x: float, z: float) -> Color:
	var palette: Array = [
		Color(1.0, 1.0, 1.0),
		Color(0.99, 0.94, 0.86),
		Color(0.92, 0.88, 0.84),
		Color(0.96, 0.90, 0.80),
	]
	if kind == "tower" or kind == "gate":
		# stone reads colder and lighter than plaster, so it keeps the world's
		# own grey instead of the village's cream
		palette = [Color(1.0, 1.0, 1.0), Color(0.96, 0.97, 0.98), Color(1.0, 0.99, 0.95)]
	if kind == "torch" or kind == "sign":
		return palette[0]
	var h := absi(int(hash(str(int(round(x * 10.0)), ":", int(round(z * 10.0))))))
	return palette[h % palette.size()]


# ---------------------------------------------------------------- streaming ---
func set_view_centre(pos: Vector2) -> void:
	if data == null:
		return
	var csz: int = int(data.get("chunk"))
	var last := int(data.call("chunk_count")) - 1
	var t: Vector2i = data.call("world_to_tile", pos)
	var c := Vector2i(clampi(t.x / csz, 0, last), clampi(t.y / csz, 0, last))
	_centres = [c]
	_schedule(c)


func _schedule(c: Vector2i) -> void:
	var want := {}
	var radius := view_radius + (1 if prefetch else 0)
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var cc := Vector2i(c.x + dx, c.y + dz)
			if _chunks.has(cc) or _pending.has(cc):
				continue
			want[cc] = (dx * dx + dz * dz)
	var keys := want.keys()
	keys.sort_custom(func(a, b): return int(want[a]) < int(want[b]))
	_queue = keys
	_prune(c)


## Drop chunks that are far away: nodes, meshes and their vertex memory.
func _prune(c: Vector2i) -> void:
	var radius := view_radius + 2
	for key in _chunks.keys():
		var cc: Vector2i = key
		var d := maxi(absi(cc.x - c.x), absi(cc.y - c.y))
		if d <= radius:
			continue
		var node: Node3D = _chunks[cc]
		if node != null and is_instance_valid(node):
			node.queue_free()
		_chunks.erase(cc)
		_stats["unloaded"] = int(_stats.get("unloaded", 0)) + 1


func _process(_delta: float) -> void:
	if data == null or _centres.is_empty():
		return
	_collect_tasks()
	var guard := 0
	while guard < 2 and _pending.size() < 2 and not _queue.is_empty():
		var cc: Vector2i = _queue.pop_front()
		if _chunks.has(cc) or _pending.has(cc):
			continue
		_spawn_task(cc)
		guard += 1


func _spawn_task(cc: Vector2i) -> void:
	if not threaded:
		_build_now(cc)
		return
	if not ResourceLoader.exists(MESH_SCRIPT):
		_build_now(cc)
		return
	var script: Script = load(MESH_SCRIPT)
	if script == null:
		_build_now(cc)
		return
	# one task per chunk; the arrays come back through a dictionary the thread
	# fills in (a plain Dictionary is safe because only the worker touches it
	# until the task reports complete)
	# Captured into LOCALS on purpose. A lambda that mentions `data` or `script`
	# reads a member of this node, so the thread would be holding a pointer to a
	# node the scene tree may free under it - which is an abort, not an error
	# message ("world rules ... exit 134" with every check green). A local keeps
	# its own reference alive for as long as the task runs.
	var grid: RefCounted = data
	var baker: Script = script
	var cx: int = cc.x
	var cz: int = cc.y
	var out := {}
	var task := WorkerThreadPool.add_task(
		func() -> void: out["arrays"] = baker.call("build", grid, cx, cz),
		false, "region chunk %d,%d" % [cx, cz])
	_pending[cc] = task
	_task_chunk[task] = cc
	_pending_arrays[task] = out


func _collect_tasks() -> void:
	for cc in _pending.keys():
		var task: int = _pending[cc]
		if not WorkerThreadPool.is_task_completed(task):
			continue
		WorkerThreadPool.wait_for_task_completion(task)
		var out: Dictionary = _pending_arrays.get(task, {})
		_pending.erase(cc)
		_pending_arrays.erase(task)
		_task_chunk.erase(task)
		var arrays: Variant = out.get("arrays", {})
		if typeof(arrays) != TYPE_DICTIONARY:
			continue
		_upload(cc, arrays)


## Build one chunk on the calling thread. Used at boot, on a teleport, and
## whenever the thread pool is unavailable.
func _build_now(cc: Vector2i) -> void:
	if ResourceLoader.exists(MESH_SCRIPT):
		var script: Script = load(MESH_SCRIPT)
		if script != null:
			var arrays: Variant = script.call("build", data, cc.x, cc.y)
			if typeof(arrays) == TYPE_DICTIONARY:
				_upload(cc, arrays)
				return
	_upload(cc, {})


## Build the visible ring right now. Called behind a fade, so a long frame here
## is honest; the alternative is a player falling through an empty world.
func force_build() -> void:
	if data == null or _centres.is_empty():
		return
	var c: Vector2i = _centres[0]
	for dz in range(-view_radius, view_radius + 1):
		for dx in range(-view_radius, view_radius + 1):
			var cc := Vector2i(c.x + dx, c.y + dz)
			if _chunks.has(cc):
				continue
			if _pending.has(cc):
				var task: int = _pending[cc]
				WorkerThreadPool.wait_for_task_completion(task)
				var out: Dictionary = _pending_arrays.get(task, {})
				_pending.erase(cc)
				_pending_arrays.erase(task)
				_task_chunk.erase(task)
				var arrays: Variant = out.get("arrays", {})
				if typeof(arrays) == TYPE_DICTIONARY:
					_upload(cc, arrays)
					continue
			_build_now(cc)


func _upload(cc: Vector2i, arrays: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	var node := Node3D.new()
	node.name = "Chunk_%d_%d" % [cc.x, cc.y]

	var mesh := ArrayMesh.new()
	var vertex_total := 0
	var mats := [_terrain_mat, _cliff_mat, _wood_mat, _water_mat]
	for i in range(SURFACES.size()):
		var surf: Dictionary = arrays.get(SURFACES[i], {})
		if surf.is_empty():
			continue
		var verts: PackedVector3Array = surf.get("verts", PackedVector3Array())
		if verts.size() < 3:
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = surf.get("norms", PackedVector3Array())
		arr[Mesh.ARRAY_TEX_UV] = surf.get("uvs", PackedVector2Array())
		arr[Mesh.ARRAY_TEX_UV2] = surf.get("uv2s", PackedVector2Array())
		arr[Mesh.ARRAY_COLOR] = surf.get("colors", PackedColorArray())
		arr[Mesh.ARRAY_INDEX] = surf.get("indices", PackedInt32Array())
		var surface := mesh.get_surface_count()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(surface, mats[i])
		vertex_total += verts.size()

	if mesh.get_surface_count() > 0:
		var mi := MeshInstance3D.new()
		mi.name = "Ground"
		mi.mesh = mesh
		# the ground never casts: props are unshaded billboards that cast nothing,
		# so the only caster left is the knight, and letting a 192 m flat sheet
		# cast onto itself is the classic recipe for shadow acne on every tile
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mi)

	add_child(node)
	_chunks[cc] = node
	_stats["chunks"] = _chunks.size()
	_stats["vertices"] = int(_stats.get("vertices", 0)) + vertex_total
	_stats["built"] = int(_stats.get("built", 0)) + 1
	_stats["draws"] = _chunks.size() + _prop_mms.size()
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	_stats["build_ms_total"] = float(_stats.get("build_ms_total", 0.0)) + ms
	_stats["build_ms_worst"] = maxf(float(_stats.get("build_ms_worst", 0.0)), ms)


# --------------------------------------------------------------- occlusion ---
## Dither away the props standing between the camera and the knight.
##
## The list is only the tall props (a tuft never hides anybody) and the caller
## runs this on a tile change or four times a second, so this is not a per-frame
## scan of 2 959 instances.
##
## The maths lives in `occluders_for()` so it can be tested without a renderer:
## a headless run cannot read instance colours back out of a MultiMesh (the known
## dead end from step 2), but the DECISION of which prop fades is pure geometry.
##
## 3A changed the shape of the decision. The old test was binary (hide / show)
## with a fixed 0.85 m corridor, tuned for a camera looking almost straight down.
## At pitch 30 the camera looks along the corridor at a shallow angle, so the
## corridor has to be wider than the prop and the fade has to be partial: a tree
## turns to a half-dithered veil so the knight's silhouette still reads through
## it, instead of vanishing and leaving a hole in the forest.
func update_occluders(player: Vector2, camera_xz: Vector2,
		radius: float = 1.05, reach: float = 2.5) -> void:
	if _tall.is_empty() and _build_tall.is_empty():
		return
	var plan := occluders_for(player, camera_xz, radius, reach)
	# anything that was fading and is not in the plan goes back to solid
	for key in _faded.keys():
		if plan.has(key):
			continue
		_set_fade(key, 1.0)
		_faded.erase(key)
	for key in plan.keys():
		var fade := float(plan[key])
		var was := float(_faded.get(key, 1.0))
		if is_equal_approx(was, fade):
			continue
		_set_fade(key, fade)
		_faded[key] = fade


## Which props and buildings must fade, and how much: {"kind/idx": fade 0..1} for
## sprites and "b:kind|variant/idx" for meshes. Pure function of the layout, the
## knight and the camera; no node access at all.
func occluders_for(player: Vector2, camera_xz: Vector2,
		radius: float = 1.05, reach: float = 2.5) -> Dictionary:
	var out := {}
	var dir := player - camera_xz
	var dist := dir.length()
	if dist < 0.5:
		return out
	var dirn := dir / dist
	for item in _tall:
		var fade := _corridor_fade(item, camera_xz, dirn, dist, radius, reach)
		if fade < 0.0:
			continue
		out["%s/%d" % [item[0], int(item[1])]] = fade
	# step 3B: a house is as capable of hiding the knight as a tree is. Its fade
	# goes through the instance custom data instead of the instance colour, since
	# the colour holds the house's tint now.
	for item in _build_tall:
		var fade := _corridor_fade(item, camera_xz, dirn, dist, radius, reach)
		if fade < 0.0:
			continue
		out["b:%s/%d" % [item[0], int(item[1])]] = fade
	return out


## How much something standing at item[2], item[3] blocks the view of the knight,
## or -1 if it is outside the corridor. [name, index, x, z, height] for both
## lists, which is why they share this.
func _corridor_fade(item: Array, camera_xz: Vector2, dirn: Vector2, dist: float,
		radius: float, reach: float) -> float:
	if item.size() < 4:
		return -1.0
	var to_prop := Vector2(float(item[2]), float(item[3])) - camera_xz
	var along := to_prop.dot(dirn)
	if along < 0.5 or along > dist + reach:
		return -1.0
	var lateral := absf(to_prop.cross(dirn))
	if lateral > radius:
		return -1.0
	# straight on the line = fully dithered down to a quarter, at the edge of the
	# corridor = barely touched
	var strength := 1.0 - lateral / maxf(radius, 0.001)
	return clampf(1.0 - 0.75 * strength, 0.25, 1.0)


func _set_fade(key: String, fade: float) -> void:
	if key.begins_with("b:"):
		_set_build_fade(key.substr(2), fade)
		return
	var parts := key.split("/")
	if parts.size() != 2:
		return
	var kind := parts[0]
	var idx := int(parts[1])
	var mmi: MultiMeshInstance3D = _prop_mms.get(kind, null)
	if mmi == null or mmi.multimesh == null or idx < 0 or idx >= mmi.multimesh.instance_count:
		return
	var c: Color = mmi.multimesh.get_instance_color(idx)
	mmi.multimesh.set_instance_color(idx, Color(fade, c.g, c.b, c.a))


## A mesh building fades through the instance CUSTOM data, because its instance
## colour carries the plaster tint. `body` is "kind|variant/index".
func _set_build_fade(body: String, fade: float) -> void:
	var parts := body.split("/")
	if parts.size() != 2:
		return
	var mmi: MultiMeshInstance3D = _build_mms.get(parts[0], null)
	if mmi == null or mmi.multimesh == null:
		return
	var idx := int(parts[1])
	if idx < 0 or idx >= mmi.multimesh.instance_count:
		return
	var data_now: Color = mmi.multimesh.get_instance_custom_data(idx)
	mmi.multimesh.set_instance_custom_data(idx, Color(fade, data_now.g, data_now.b, data_now.a))


# --------------------------------------------------------------------- api ---
func chunk_nodes() -> Dictionary:
	return _chunks


## Every prop's placement as the mesher computed it: [kind, x, z, w, h, y] where
## y is the centre of the instance, exactly what was handed to the MultiMesh.
## The rules test walks THIS instead of reading instance transforms back out of
## the MultiMesh, because a headless run has no render device and a read-back
## from the GPU buffer returns zeros there while the drawn world is correct.
func prop_layout() -> Array:
	return _layout


## Every 3D building as placed: [kind, variant, x, z, y, yaw, top, block].
## Same reason as prop_layout(): a headless run cannot read instance transforms
## back out of a MultiMesh, so the test walks the numbers the mesher handed over.
func building_layout() -> Array:
	return _build_layout


func stats() -> Dictionary:
	_stats["chunks"] = _chunks.size()
	_stats["draws"] = _chunks.size() + _prop_mms.size() + _build_mms.size()
	_stats["prop_kinds"] = _prop_mms.size()
	_stats["build_kinds"] = _build_mms.size()
	_stats["pending"] = _pending.size()
	return _stats


## Day phase tint: the props are unshaded billboards, and the ground is lit by
## the sun, so the day's colour is applied here as well to keep them together.
func set_light_tint(colour: Color) -> void:
	var v := Vector3(colour.r, colour.g, colour.b)
	var mats: Array = [_terrain_mat, _cliff_mat, _wood_mat, _build_mat]
	for kind in _prop_mats.keys():
		mats.append(_prop_mats[kind])
	for mat in mats:
		if mat != null and (mat as ShaderMaterial).shader != null:
			(mat as ShaderMaterial).set_shader_parameter("light_tint", v)


## How lit the windows and the torches are: 0 at noon, 1 at deep night. The
## diorama drives it from the lamp's own energy (WorldClock), so a house lights
## up exactly when the village lamp does instead of on its own schedule.
func set_nightness(v: float) -> void:
	if _build_mat == null or _build_mat.shader == null:
		return
	_build_mat.set_shader_parameter("night", clampf(v, 0.0, 1.0))


## The cliff shader's window follows the player, so standing behind a two-level
## wall never hides the knight behind a slab of rock.
func set_player_xz(pos: Vector2) -> void:
	if _cliff_mat == null or _cliff_mat.shader == null:
		return
	_cliff_mat.set_shader_parameter("player_xz", pos)


func set_radius(r: int) -> void:
	view_radius = clampi(r, 0, RADIUS_MAX)


func clear() -> void:
	for key in _chunks.keys():
		var node: Node3D = _chunks[key]
		if node != null and is_instance_valid(node):
			node.queue_free()
	_chunks.clear()


## Block until every chunk task has reported. A test scene that calls quit()
## while a baker thread is still walking the byte grids tears the data out from
## under it, and the engine answers with a crash instead of a failure.
func drain() -> void:
	# stop FIRST: every frame this node lives it can spawn another prefetch task,
	# and a task started after the wait below is a task that outlives the process
	set_process(false)
	_queue.clear()
	_centres.clear()
	for cc in _pending.keys():
		var task: int = _pending[cc]
		if not WorkerThreadPool.is_task_completed(task):
			WorkerThreadPool.wait_for_task_completion(task)
	_pending.clear()
	_pending_arrays.clear()
	_task_chunk.clear()


func _exit_tree() -> void:
	# nothing may be left in flight once this node starts going away: the task
	# holds the byte grid and the baker script, and the scene tree is free to drop
	# both the moment we return
	set_process(false)
	_queue.clear()
	for cc in _pending.keys():
		var task: int = _pending[cc]
		if not WorkerThreadPool.is_task_completed(task):
			WorkerThreadPool.wait_for_task_completion(task)
	_pending.clear()
	_pending_arrays.clear()
	_task_chunk.clear()
