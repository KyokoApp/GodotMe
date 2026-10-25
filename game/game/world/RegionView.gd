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
const WATER_SHADER := "res://game/world/water.gdshader"
const TERRAIN_SHADER := "res://game/world/terrain.gdshader"
const CLIFF_SHADER := "res://game/world/cliff.gdshader"
const WOOD_SHADER := "res://game/world/wood.gdshader"
## Surfaces inside one chunk mesh, in the order they are built.
const SURFACES := ["terrain", "cliff", "wood", "water"]

## How many chunks around the player's own chunk stay visible. 1 => 3x3 chunks
## = 96x96 m, which is wider than the camera can see at any zoom on the ladder.
const RADIUS_MAX := 2

var data: RefCounted
var view_radius := 1
## Chunks are built one ring further out than they are shown, so the next chunk
## is ready before the player walks into it.
var prefetch := true

var _terrain_mat: ShaderMaterial
var _cliff_mat: ShaderMaterial
var _wood_mat: ShaderMaterial
var _water_mat: ShaderMaterial
var _prop_mats: Dictionary = {}     # kind -> ShaderMaterial with its atlas cell
var _prop_mms: Dictionary = {}      # kind -> MultiMeshInstance3D
var _tall: Array = []               # [kind, index, x, z, height] of occluders
var _layout: Array = []             # [kind, x, z, w, h, ground] every placed prop
var _faded: Dictionary = {}         # "kind/index" -> 0.0 while dissolved
var _quad: ArrayMesh
var _chunks: Dictionary = {}        # Vector2i -> Node3D
var _prop_size: Dictionary = {}     # kind -> Vector2 metres
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
	_stats["build_ms_total"] = 0.0
	_build_materials()
	_build_quad()
	_build_props()
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
		"shallow_tint": Color(0.62, 0.80, 0.78),
		"deep_tint": Color(0.30, 0.46, 0.52),
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


func _tex(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


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
## Dither away the props standing between the camera and the knight. The list is
## only the tall props (a tuft never hides anybody) and the caller runs this on a
## tile change or four times a second, so this is not a per-frame scan of 2 959
## instances.
func update_occluders(player: Vector2, camera_xz: Vector2) -> void:
	if _tall.is_empty():
		return
	var dir := player - camera_xz
	var reach := dir.length()
	if reach < 0.5:
		return
	var dirn := dir / reach
	for item in _tall:
		var kind: String = item[0]
		var idx: int = item[1]
		var x: float = item[2]
		var z: float = item[3]
		var to_prop := Vector2(x, z) - camera_xz
		var along := to_prop.dot(dirn)
		var lateral := absf(to_prop.cross(dirn))
		var hide := along > 0.5 and along < reach + 1.5 and lateral < 0.85
		var key := "%s/%d" % [kind, idx]
		var was := _faded.has(key)
		if hide == was:
			continue
		var mmi: MultiMeshInstance3D = _prop_mms.get(kind, null)
		if mmi == null or mmi.multimesh == null or idx >= mmi.multimesh.instance_count:
			continue
		var c: Color = mmi.multimesh.get_instance_color(idx)
		mmi.multimesh.set_instance_color(idx, Color(0.0 if hide else 1.0, c.g, c.b, c.a))
		if hide:
			_faded[key] = true
		else:
			_faded.erase(key)


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


func stats() -> Dictionary:
	_stats["chunks"] = _chunks.size()
	_stats["draws"] = _chunks.size() + _prop_mms.size()
	_stats["prop_kinds"] = _prop_mms.size()
	_stats["pending"] = _pending.size()
	return _stats


## Day phase tint: the props are unshaded billboards, and the ground is lit by
## the sun, so the day's colour is applied here as well to keep them together.
func set_light_tint(colour: Color) -> void:
	var v := Vector3(colour.r, colour.g, colour.b)
	var mats: Array = [_terrain_mat, _cliff_mat, _wood_mat]
	for kind in _prop_mats.keys():
		mats.append(_prop_mats[kind])
	for mat in mats:
		if mat != null and (mat as ShaderMaterial).shader != null:
			(mat as ShaderMaterial).set_shader_parameter("light_tint", v)


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
	for cc in _pending.keys():
		var task: int = _pending[cc]
		if not WorkerThreadPool.is_task_completed(task):
			WorkerThreadPool.wait_for_task_completion(task)
	_pending.clear()
	_pending_arrays.clear()
	_task_chunk.clear()
	set_process(false)


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
