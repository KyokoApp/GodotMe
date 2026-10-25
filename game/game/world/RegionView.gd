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
var _prop_mat: ShaderMaterial
var _quad: ArrayMesh
var _chunks: Dictionary = {}        # Vector2i -> Node3D
var _props_by_chunk: Dictionary = {}  # Vector2i -> Array of [kind, x, z, scale, flip]
var _prop_index: Dictionary = {}    # kind -> index in the atlas
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
	_index_props()
	_bucket_props()
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
	var prop := ShaderMaterial.new()
	if ResourceLoader.exists(PROP_SHADER):
		prop.shader = load(PROP_SHADER)
		prop.set_shader_parameter("albedo_tex", _tex(PROP_ATLAS))
		prop.set_shader_parameter("scissor", 0.42)
		prop.set_shader_parameter("cell_rects", _prop_rects_from(_prop_meta()))
	_prop_mat = prop


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


## Read the atlas manifest: which cell holds which prop, and how big that prop
## is in metres. One file, so the art tool and the mesher cannot drift apart.
func _index_props() -> void:
	var meta := _prop_meta()
	if meta.is_empty():
		push_warning("[REGION] prop_atlas.json tidak ada, prop dunia dilewati")
		return
	for raw in meta.get("cells", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var cell: Dictionary = raw
		var kind := String(cell.get("kind", ""))
		_prop_index[kind] = int(cell.get("index", 0))
		var sz: Array = cell.get("size_m", [1.0, 1.0])
		if sz.size() >= 2:
			_prop_size[kind] = Vector2(float(sz[0]), float(sz[1]))


func _prop_rects_from(meta: Dictionary) -> PackedVector4Array:
	var out := PackedVector4Array()
	out.resize(16)
	for i in range(16):
		out[i] = Vector4(0.0, 0.0, 1.0, 1.0)
	for raw in meta.get("cells", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var cell: Dictionary = raw
		var idx := int(cell.get("index", 0))
		var uv: Array = cell.get("uv", [])
		if idx < 0 or idx >= 16 or uv.size() < 4:
			continue
		out[idx] = Vector4(float(uv[0]), float(uv[1]), float(uv[2]), float(uv[3]))
	return out


## Bucket every decoration into the chunk that owns it, once. Doing this per
## chunk build would re-walk 2 959 entries 36 times for no reason.
func _bucket_props() -> void:
	_props_by_chunk.clear()
	if data == null:
		return
	var decor: Dictionary = data.get("decor")
	if typeof(decor) != TYPE_DICTIONARY:
		return
	var csz: int = int(data.get("chunk"))
	var w: int = int(data.get("width"))
	var h: int = int(data.get("height"))
	for kind in decor.keys():
		var k := String(kind)
		if not _prop_index.has(k):
			continue
		var list: Array = decor[kind]
		for raw in list:
			if typeof(raw) != TYPE_ARRAY:
				continue
			var row: Array = raw
			if row.size() < 2:
				continue
			# decor is stored in tenths of a metre, in world XZ
			var x := float(row[0]) * 0.1
			var z := float(row[1]) * 0.1
			var scale := float(row[2]) * 0.01 if row.size() > 2 else 1.0
			var flip := int(row[3]) if row.size() > 3 else 0
			var tx := int(floor(x))
			var tz := int(floor(z))
			if tx < 0 or tz < 0 or tx >= w or tz >= h:
				continue
			var cell := Vector2i(tx / csz, tz / csz)
			if not _props_by_chunk.has(cell):
				_props_by_chunk[cell] = []
			(_props_by_chunk[cell] as Array).append([k, x, z, scale, flip])


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
	var out := {}
	var task := WorkerThreadPool.add_task(
		func() -> void: out["arrays"] = script.call("build", data, cc.x, cc.y),
		false, "region chunk %d,%d" % [cc.x, cc.y])
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
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		node.add_child(mi)

	var prop_count := _add_props(node, cc)
	add_child(node)
	_chunks[cc] = node
	_stats["chunks"] = _chunks.size()
	_stats["vertices"] = int(_stats.get("vertices", 0)) + vertex_total
	_stats["props"] = int(_stats.get("props", 0)) + prop_count
	_stats["built"] = int(_stats.get("built", 0)) + 1
	_stats["draws"] = _chunks.size() * 2 + _prop_chunk_count()
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	_stats["build_ms_total"] = float(_stats.get("build_ms_total", 0.0)) + ms
	_stats["build_ms_worst"] = maxf(float(_stats.get("build_ms_worst", 0.0)), ms)


func _prop_chunk_count() -> int:
	var n := 0
	for key in _chunks.keys():
		if _props_by_chunk.has(key):
			n += 1
	return n


## One MultiMesh per chunk for every prop in it: the atlas means a chunk's
## eighty trees, rocks and bushes are ONE draw call, not one per sprite.
func _add_props(parent: Node3D, cc: Vector2i) -> int:
	if not _props_by_chunk.has(cc) or _prop_mat == null:
		return 0
	if _prop_mat.shader == null:
		return 0
	var list: Array = _props_by_chunk[cc]
	if list.is_empty():
		return 0
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _quad
	mm.instance_count = list.size()
	var level_h: float = float(data.get("level_h"))
	var i := 0
	for raw in list:
		var row: Array = raw
		var kind := String(row[0])
		if not _prop_size.has(kind):
			continue
		var size: Vector2 = _prop_size[kind]
		var x := float(row[1])
		var z := float(row[2])
		var scale := float(row[3]) if row.size() > 3 else 1.0
		var flip := int(row[4]) if row.size() > 4 else 0
		var ground := float(data.call("height_at", Vector2(x, z)))
		var w := size.x * scale
		var h := size.y * scale
		var basis := Basis().scaled(Vector3(w, h, 1.0))
		mm.set_instance_transform(i, Transform3D(basis, Vector3(x, ground + h * 0.5, z)))
		mm.set_instance_custom_data(i, Color(
			float(_prop_index.get(kind, 0)), float(flip), 1.0, 1.0))
		i += 1
	if i <= 0:
		return 0
	mm.instance_count = i
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Props"
	mmi.multimesh = mm
	mmi.material_override = _prop_mat
	# billboards shadow badly (the quad turns to the camera, so its shadow does
	# too); the trees get a soft blob from the actor's shadow sprite instead
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	return i


# --------------------------------------------------------------- occlusion ---
## Dither away the props standing between the camera and the knight. Only the
## chunks next to the player are touched, and only when the player changes tile,
## so this is not a per-frame scan.
func update_occluders(player: Vector2, camera_xz: Vector2) -> void:
	if data == null or _chunks.is_empty():
		return
	var csz: int = int(data.get("chunk"))
	var t: Vector2i = data.call("world_to_tile", player)
	var centre := Vector2i(t.x / csz, t.y / csz)
	var dir := (player - camera_xz)
	var reach := dir.length()
	if reach < 0.5:
		return
	var dirn := dir / reach
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var cc := Vector2i(centre.x + dx, centre.y + dz)
			if not _chunks.has(cc):
				continue
			var list: Array = _props_by_chunk.get(cc, [])
			if list.is_empty():
				continue
			var node: Node3D = _chunks[cc]
			var mmi := node.get_node_or_null("Props") as MultiMeshInstance3D
			if mmi == null or mmi.multimesh == null:
				continue
			var mm := mmi.multimesh
			for i in range(mini(list.size(), mm.instance_count)):
				var row: Array = list[i]
				var p := Vector2(float(row[1]), float(row[2]))
				var to_prop := p - camera_xz
				var along := to_prop.dot(dirn)
				var lateral := absf(to_prop.cross(dirn))
				var fade := 1.0
				if along > 0.5 and along < reach + 1.5 and lateral < 0.85:
					var height := float((_prop_size.get(String(row[0]), Vector2.ONE)).y)
					# only tall things hide the knight; a tuft never does
					fade = 0.0 if height > 1.3 else 1.0
				var custom := mm.get_instance_custom_data(i)
				if not is_equal_approx(custom.z, fade):
					custom.z = fade
					mm.set_instance_custom_data(i, custom)


# --------------------------------------------------------------------- api ---
func chunk_nodes() -> Dictionary:
	return _chunks


func stats() -> Dictionary:
	_stats["chunks"] = _chunks.size()
	_stats["draws"] = _chunks.size() * 2 + _prop_chunk_count()
	_stats["pending"] = _pending.size()
	return _stats


## Day phase tint: the props are unshaded billboards, and the ground is lit by
## the sun, so the day's colour is applied here as well to keep them together.
func set_light_tint(colour: Color) -> void:
	var v := Vector3(colour.r, colour.g, colour.b)
	for mat in [_prop_mat, _terrain_mat, _cliff_mat, _wood_mat]:
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


func _exit_tree() -> void:
	for cc in _pending.keys():
		var task: int = _pending[cc]
		if not WorkerThreadPool.is_task_completed(task):
			WorkerThreadPool.wait_for_task_completion(task)
	_pending.clear()
	_pending_arrays.clear()
	_task_chunk.clear()
