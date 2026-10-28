extends Node3D
## Headless gate for step 2: REGION "Yaros".
##
## A screenshot can show that the valley looks finished. It cannot show that the
## mountain gate is actually reachable, that no terrace is a trap, that two
## neighbouring chunks meet without a crack, that the walk from the village to
## Pos Gunung really takes two minutes, or that landing in a new part of the map
## loads in a time a phone can survive. This scene checks those.
##
##   godot --headless --path game res://game/tests/RegionTest.tscn
##
## Exit code 1 on any broken rule, so CI fails instead of shipping a map nobody
## can cross.

const REGION_JSON := "res://game/world/regions/yaros.json"
const PROP_META := "res://game/world/prop_atlas.json"
const DATA_SCRIPT := preload("res://game/world/RegionData.gd")
const MESH_SCRIPT := preload("res://game/world/RegionMesh.gd")
const VIEW_SCRIPT := preload("res://game/world/RegionView.gd")

## Markers allowed to be out of reach, with the reason. Everything else on the
## map must be walkable-to from the village or the map is broken.
const BLOCKED_BY_DESIGN := {
	"region_gate": "gerbang Pos Gunung sengaja terkunci (langkah 3)",
	"bridge_broken": "jembatan rusak: papan tengah hilang, harus memutar",
}

## Walk and run speed from the brief: the travel time is measured with these.
const WALK_SPEED := 3.5
const RUN_SPEED := 5.5

var failures := 0
var checks := 0
var _region: RefCounted
## Flood-filled reachability mask from the start tile (1 = reachable).
var _reachable := PackedByteArray()


func _ready() -> void:
	await get_tree().process_frame
	if not _load_region():
		print("[REGION] gagal memuat peta, %d gagal" % failures)
		get_tree().quit(1)
		return
	_test_grid()
	_test_height_rules()
	_test_reachability()
	_test_markers()
	_test_zones()
	_test_seams()
	_test_props()
	await _test_streaming()
	_test_travel_time()
	print("[REGION] %d pemeriksaan, %d gagal" % [checks, failures])
	await _shutdown()


## Wait for every baker thread, free the probe, and only then quit. The first
## version of this called quit() with the streaming probe still in the tree and
## the process died of SIGABRT at teardown - every check green, exit code 134.
func _shutdown() -> void:
	for node in get_children():
		if node.has_method("drain"):
			node.call("drain")
			print("[REGION] %s dikuras" % node.name)
		node.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("[REGION] siap keluar")
	get_tree().quit(0 if failures == 0 else 1)


func _check(cond: bool, label: String, extra: String = "") -> void:
	checks += 1
	if cond:
		print("[REGION] PASS %s" % label)
	else:
		failures += 1
		print("[REGION] FAIL %s %s" % [label, extra])


func _load_region() -> bool:
	if not FileAccess.file_exists(REGION_JSON):
		_check(false, "berkas peta ada", REGION_JSON)
		return false
	_region = DATA_SCRIPT.new()
	var ok: bool = bool(_region.call("load_file", REGION_JSON))
	_check(ok, "peta Yaros termuat", REGION_JSON)
	return ok


# ------------------------------------------------------------------- grid -----
func _test_grid() -> void:
	var w := int(_region.get("width"))
	var h := int(_region.get("height"))
	var chunk := int(_region.get("chunk"))
	_check(w == 192 and h == 192, "grid 192x192 ubin", "%dx%d" % [w, h])
	_check(chunk == 32, "chunk 32x32 ubin", str(chunk))
	_check(int(_region.call("chunk_count")) == 6, "6x6 = 36 chunk",
		str(_region.call("chunk_count")))
	_check(is_equal_approx(float(_region.get("level_h")), 1.8),
		"satu level = 1,8 m", str(_region.get("level_h")))
	var stats: Dictionary = _region.get("stats")
	_check(int(stats.get("walkable", 0)) > 25000, "ubin berjalan > 25 000",
		str(stats.get("walkable")))
	_check(float(stats.get("road_tiles", 0.0)) >= 450.0,
		"jalur utama >= 450 ubin", str(stats.get("road_tiles")))


# ------------------------------------------------------------ movement rule ---
## The official rule, checked against the data rather than trusted: one level is
## a bank, two levels need a stone flight, three is a cliff.
func _test_height_rules() -> void:
	var bad := 0
	var banks := 0
	var stairs := 0
	var cliffs := 0
	for tz in range(0, int(_region.get("height"))):
		for tx in range(0, int(_region.get("width"))):
			if not bool(_region.call("walkable_tile", tx, tz)):
				continue
			var here := int(_region.call("tile_height", tx, tz))
			for d in [Vector2i(1, 0), Vector2i(0, 1)]:
				var nx: int = tx + d.x
				var nz: int = tz + d.y
				if not bool(_region.call("walkable_tile", nx, nz)):
					continue
				var dh: int = absi(here - int(_region.call("tile_height", nx, nz)))
				var ok := bool(_region.call("step_ok", tx, tz, nx, nz))
				var stair := int(_region.call("struct_code", tx, tz)) == 1 \
					or int(_region.call("struct_code", nx, nz)) == 1
				if dh <= 1:
					banks += 1
					if not ok:
						bad += 1
				elif dh == 2 and stair:
					stairs += 1
					if not ok:
						bad += 1
				else:
					cliffs += 1
					if ok:
						bad += 1
	_check(bad == 0, "aturan tinggi konsisten di seluruh peta",
		"%d pelanggaran (%d lereng, %d tangga, %d tebing)" % [bad, banks, stairs, cliffs])
	_check(banks > 5000, "lereng satu level ada di mana-mana", str(banks))
	_check(cliffs > 0, "tebing dua level atau lebih memang ada", str(cliffs))


# ------------------------------------------------------------ reachability ---
## Flood fill from the player's start over the same `step_ok` the knight uses.
## Every walkable tile must be in that one component: a terrace nobody can leave,
## or reach, is the classic hand-made-map trap.
func _test_reachability() -> void:
	var w := int(_region.get("width"))
	var total := 0
	for tz in range(int(_region.get("height"))):
		for tx in range(w):
			if bool(_region.call("walkable_tile", tx, tz)):
				total += 1
	var start: Vector2i = _region.call("nearest_walkable",
		_region.call("world_to_tile", _region.call("start_position")), 12)
	var seen := PackedByteArray()
	seen.resize(w * int(_region.get("height")))
	var queue: Array = [start]
	seen[start.y * w + start.x] = 1
	var reached := 0
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while not queue.is_empty():
		var node: Vector2i = queue.pop_back()
		reached += 1
		for d in dirs:
			var nx: int = node.x + d.x
			var nz: int = node.y + d.y
			if nx < 0 or nz < 0 or nx >= w or nz >= int(_region.get("height")):
				continue
			if seen[nz * w + nx] == 1:
				continue
			if not bool(_region.call("step_ok", node.x, node.y, nx, nz)):
				continue
			seen[nz * w + nx] = 1
			queue.append(Vector2i(nx, nz))
	_check(reached == total, "tidak ada area terisolasi",
		"%d dari %d ubin terjangkau" % [reached, total])
	_reachable = seen


## Reachability of the tile a marker actually stands on. Snapping to the nearest
## walkable tile - which is right for a door or a chest - is wrong for a locked
## gate: the tile next to the gate is reachable by definition, so a snap would
## quietly report every locked gate as open.
func _own_tile_reachable(p: Vector2) -> bool:
	var w := int(_region.get("width"))
	var t: Vector2i = _region.call("world_to_tile", p)
	if t.x < 0 or t.y < 0 or t.x >= w or t.y >= int(_region.get("height")):
		return false
	if not bool(_region.call("walkable_tile", t.x, t.y)):
		return false
	return _reachable[t.y * w + t.x] == 1


func _tile_reachable(p: Vector2) -> bool:
	var w := int(_region.get("width"))
	var t: Vector2i = _region.call("nearest_walkable", _region.call("world_to_tile", p), 10)
	if t.x < 0 or t.y < 0 or t.x >= w or t.y >= int(_region.get("height")):
		return false
	return _reachable[t.y * w + t.x] == 1


func _test_markers() -> void:
	var markers: Array = _region.get("markers")
	_check(markers.size() >= 30, "marker peta cukup", str(markers.size()))
	var bad: Array = []
	var blocked_ok := 0
	for raw in markers:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var m: Dictionary = raw
		var kind := String(m.get("kind", ""))
		var pos := Vector2(float(m.get("x", 0.0)), float(m.get("y", 0.0)))
		if BLOCKED_BY_DESIGN.has(kind):
			# a locked gate and a broken bridge must NOT be reachable: that is the
			# whole point of them
			if not _own_tile_reachable(pos):
				blocked_ok += 1
			else:
				bad.append("%s harusnya terhalang" % String(m.get("name", "")))
			continue
		if not _tile_reachable(pos):
			bad.append(String(m.get("name", kind)))
	_check(bad.is_empty(), "semua tujuan bisa dicapai dengan berjalan", str(bad))
	_check(blocked_ok == BLOCKED_BY_DESIGN.size(), "blokir sengaja tetap terblokir",
		str(blocked_ok))
	# the hard requirement: the quest line has a real path end to end
	var start: Vector2 = _region.call("start_position")
	var gate: Dictionary = _region.call("marker", "Gerbang Pos Gunung")
	if not gate.is_empty():
		var t0 := Time.get_ticks_msec()
		var path: Array = _region.call("find_path", start, _region.call("marker_pos", gate))
		var ms := Time.get_ticks_msec() - t0
		_check(path.size() > 40, "A* menemukan jalan desa -> gerbang",
			"%d ubin, %d ms" % [path.size(), ms])
		# the whole path must be made of steps a body can take
		var broken := 0
		for i in range(path.size() - 1):
			var a: Vector2 = path[i]
			var b: Vector2 = path[i + 1]
			var ta: Vector2i = _region.call("world_to_tile", a)
			var tb: Vector2i = _region.call("world_to_tile", b)
			if not bool(_region.call("step_ok", ta.x, ta.y, tb.x, tb.y)):
				broken += 1
		_check(broken == 0, "setiap langkah di jalur A* sah", str(broken))
		print("[REGION] A* desa->gerbang: %d ubin, %.0f ms" % [path.size(), ms])


func _test_zones() -> void:
	var start: Vector2 = _region.call("start_position")
	_check(String(_region.call("zone_at", start)) == "Lembah Senja",
		"titik awal ada di Lembah Senja", String(_region.call("zone_at", start)))
	var gate: Dictionary = _region.call("marker", "Gerbang Pos Gunung")
	if not gate.is_empty():
		var z := String(_region.call("zone_at", _region.call("marker_pos", gate)))
		_check(z == "Pos Gunung", "gerbang ada di zona Pos Gunung", z)
	var zones: Array = _region.get("zones")
	_check(zones.size() >= 9, "sembilan zona bernama", str(zones.size()))
	var missing: Array = []
	for raw in zones:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var z: Dictionary = raw
		for key in ["name", "kind", "rect", "biome", "subtitle", "weather", "music"]:
			if not z.has(key) or str(z.get(key, "")) == "":
				missing.append("%s.%s" % [str(z.get("name", "?")), key])
	_check(missing.is_empty(), "tiap zona punya nama/biome/cuaca/musik", str(missing))


# ------------------------------------------------------------------- seams ---
## Two neighbouring chunks must produce identical vertex heights on the plane
## they share, or the world shows a hairline crack that no screenshot at 1280 px
## would catch.
func _test_seams() -> void:
	# (chunk, chunk, axis): 0 compares along x, 1 along z. The first version of
	# this test used the x formula for both pairs, so it compared the inside of a
	# chunk with itself and passed while saying nothing about the z seam.
	var pairs := [[Vector2i(2, 2), Vector2i(3, 2), 0], [Vector2i(2, 2), Vector2i(2, 3), 1]]
	var csz := int(_region.get("chunk"))
	var cell := float(_region.get("cell"))
	var origin: Vector2 = _region.get("origin")
	var corner := origin - Vector2(int(_region.get("width")),
		int(_region.get("height"))) * cell * 0.5
	for pair in pairs:
		var a: Vector2i = pair[0]
		var b: Vector2i = pair[1]
		var axis: int = pair[2]
		var left: Dictionary = MESH_SCRIPT.build(_region, a.x, a.y)
		var right: Dictionary = MESH_SCRIPT.build(_region, b.x, b.y)
		if left.is_empty() or right.is_empty():
			_check(false, "chunk %s dan %s terbangun" % [str(a), str(b)])
			continue
		var vertical := axis == 0
		var plane := corner.x + float(a.x + 1) * cell * float(csz)
		if not vertical:
			plane = corner.y + float(a.y + 1) * cell * float(csz)
		var lkeys := _boundary(_surface_verts(left, "terrain"), plane, vertical)
		var rkeys := _boundary(_surface_verts(right, "terrain"), plane, vertical)
		var same := lkeys.size() > 0 and lkeys == rkeys
		_check(same, "sambungan chunk %s|%s rapat" % [str(a), str(b)],
			"%d vs %d titik" % [lkeys.size(), rkeys.size()])
		# and the vertex count is believable: every tile has at least its quad
		var tiles := csz * csz
		var lverts := _surface_verts(left, "terrain")
		_check(lverts.size() >= tiles * 4,
			"chunk %s punya minimal 4 verteks per ubin" % str(a), str(lverts.size()))


## A chunk is four surfaces now (terrain, cliff, wood, water). The seam rule is
## about the GROUND lining up, so it reads the terrain surface only: a rock face
## on the boundary belongs to whichever side is higher, and finding it on one side
## and not the other is correct, not a crack.
func _surface_verts(arrays: Dictionary, key: String) -> PackedVector3Array:
	var surf: Dictionary = arrays.get(key, {})
	if surf.is_empty():
		return PackedVector3Array()
	return surf.get("verts", PackedVector3Array())


## Keys of the vertices sitting on a vertical plane, rounded to the millimetre so
## two chunks that computed the same corner match exactly.
func _boundary(verts: PackedVector3Array, plane: float, vertical: bool) -> Array:
	var out: Array = []
	for v in verts:
		var x_or_z := v.x if vertical else v.z
		if absf(x_or_z - plane) < 0.001:
			out.append("%+.3f|%+.3f" % [v.z if vertical else v.x, v.y])
	out.sort()
	return out


# ------------------------------------------------------------------- props ---
func _test_props() -> void:
	var decor: Dictionary = _region.get("decor")
	var count := 0
	for key in decor.keys():
		count += (decor[key] as Array).size()
	_check(count > 2000, "dekorasi > 2000 prop", str(count))
	if not FileAccess.file_exists(PROP_META):
		_check(false, "prop_atlas.json ada", PROP_META)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROP_META))
	if typeof(parsed) != TYPE_DICTIONARY:
		_check(false, "prop_atlas.json terbaca")
		return
	var meta: Dictionary = parsed
	var cells: Array = meta.get("cells", [])
	_check(cells.size() >= 14, "atlas prop memuat semua jenis", str(cells.size()))
	var bad: Array = []
	for raw in cells:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var c: Dictionary = raw
		var uv: Array = c.get("uv", [])
		var sz: Array = c.get("size_m", [])
		if uv.size() < 4 or sz.size() < 2:
			bad.append("%s tanpa uv/ukuran" % str(c.get("kind", "?")))
			continue
		if float(uv[0]) < 0.0 or float(uv[1]) < 0.0 or float(uv[0]) + float(uv[2]) > 1.001 \
				or float(uv[1]) + float(uv[3]) > 1.001:
			bad.append("%s keluar atlas" % str(c.get("kind", "?")))
		if float(sz[0]) <= 0.0 or float(sz[1]) <= 0.0:
			bad.append("%s ukuran nol" % str(c.get("kind", "?")))
	_check(bad.is_empty(), "sel atlas prop sah", str(bad))


# --------------------------------------------------------------- streaming ---
## Teleport to ten places and measure how long the ring around the player takes
## to exist. This is the number that decides whether the phone shows a hitch or
## a hole in the world after a fast-travel.
func _test_streaming() -> void:
	var view: Node3D = VIEW_SCRIPT.new() as Node3D
	view.name = "StreamProbe"
	# one thread, on purpose: the number this check prints is the worst case, and
	# the process can quit without a baker task still holding the byte grids
	view.set("threaded", false)
	add_child(view)
	view.call("setup", _region, 1)
	var spots: Array = []
	for name in ["Lembah Senja", "Jembatan Sedu", "Menara Penjaga", "Gua Berbisik",
			"Kuil Danau Cermin", "Pos Gunung", "Kembali ke desa", "Lahan rumah",
			"Orc tepi hutan", "Peti hutan"]:
		var m: Dictionary = _region.call("marker", name)
		if m.is_empty():
			continue
		spots.append(_region.call("marker_pos", m))
	_check(spots.size() >= 8, "sepuluh titik uji tersedia", str(spots.size()))
	var worst := 0.0
	var total := 0.0
	var chunks_min := 999
	for spot in spots:
		var t0 := Time.get_ticks_usec()
		view.call("set_view_centre", spot)
		view.call("force_build")
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		total += ms
		worst = maxf(worst, ms)
		var n: int = (view.call("chunk_nodes") as Dictionary).size()
		chunks_min = mini(chunks_min, n)
	_check(chunks_min >= 9, "teleport selalu membangun 3x3 chunk", str(chunks_min))
	_check(worst < 1500.0, "hitch terbesar setelah teleport di bawah 1,5 s",
		"%.0f ms" % worst)
	var stats: Dictionary = view.call("stats")
	print("[REGION] streaming: %d titik, rata-rata %.0f ms, terburuk %.0f ms, chunk %d, draw %d, prop %d, verteks %d" % [
		spots.size(), total / maxf(1.0, float(spots.size())), worst,
		int(stats.get("chunks", 0)), int(stats.get("draws", 0)),
		int(stats.get("props", 0)), int(stats.get("vertices", 0))])
	view.queue_free()
	await get_tree().process_frame


# ------------------------------------------------------------- travel time ---
## The brief asks for a two-to-three-minute walk from the village to Pos Gunung.
## Measured from the map's own route, at the map's own speed.
func _test_travel_time() -> void:
	var routes: Array = _region.get("routes")
	if routes.is_empty():
		_check(false, "jalur utama ada di data")
		return
	var main: Dictionary = routes[0]
	var tiles := float(main.get("length", 0.0))
	var walk := tiles / WALK_SPEED
	var run := tiles / RUN_SPEED
	print("[REGION] jalur %s: %.0f ubin, jalan %.0f s (%.1f menit), lari %.0f s" % [
		String(main.get("id", "?")), tiles, walk, walk / 60.0, run])
	_check(walk >= 110.0 and walk <= 175.0, "desa -> Pos Gunung 2-3 menit berjalan",
		"%.1f menit" % (walk / 60.0))
	_check(run < walk, "lari lebih cepat dari jalan", "%.0f s" % run)
