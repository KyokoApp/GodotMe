extends RefCounted
## REGION data: the whole of "Yaros" as numbers, loaded from a JSON file that
## `tools/build_region.py` writes out of a declarative spec.
##
## Why the game reads data instead of a scene: 192x192 tiles is 36 864 surfaces.
## A hand-placed scene that size is impossible to edit from a phone, impossible
## to validate, and impossible to rebuild deterministically. Here the world is
## three byte grids plus three lists, and every rule (what a cliff is, what a
## bridge is, which tiles a knight may cross) lives in ONE file.
##
## The rules, in one paragraph, because they are the whole movement model:
##   * a tile at height h is drawn at h * `level_h` metres;
##   * two tiles one level apart are a bank the knight walks up (the mesh turns
##     that edge into a slope, and `height_at` interpolates across it);
##   * two tiles two levels apart are a cliff - blocked, unless one of them is a
##     stone flight (`S_STAIR`), which has a landing in the middle;
##   * the snow summits (height 5) and the walled rim are scenery;
##   * deep and shallow water block walking, except a marked ford (`S_RAMP`),
##     which is how the stepping stones to the lake shrine work;
##   * fences, walls, gates and doors block.
##
## No `class_name`: the game runs inside the launcher's project, whose global
## class cache knows nothing about scripts that arrive later inside a .pck.

const SCHEMA := 1

# --- terrain (must match tools/build_region.py) ----------------------------
const T_GRASS := 0
const T_TALL := 1
const T_DIRT := 2
const T_ROCK := 3
const T_SAND := 4
const T_MUD := 5
const T_SNOW := 6
const T_SHALLOW := 7
const T_DEEP := 8
const T_WOOD := 9
const T_STONE := 10

const TERRAIN_WALKABLE := [T_GRASS, T_TALL, T_DIRT, T_ROCK, T_SAND, T_MUD,
	T_SNOW, T_WOOD, T_STONE]
const TERRAIN_WATER := [T_SHALLOW, T_DEEP]

# --- structures ------------------------------------------------------------
const S_NONE := 0
const S_STAIR := 1
const S_BRIDGE := 2
const S_FENCE := 3
const S_WALL := 4
const S_GATE := 5
const S_DOOR := 6
const S_RAMP := 7
const S_BLOCKING := [S_FENCE, S_WALL, S_GATE, S_DOOR]

## Ceiling on the A* expansion, so a path request can never freeze a frame.
const PATH_BUDGET := 24000

var loaded := false
var width := 0
var height := 0
var cell := 1.0
var level_h := 1.8
var chunk := 32
var label := "Yaros"
var seed_value := 0
## World XZ of the centre of tile (0, 0).
var origin := Vector2.ZERO
var decor: Dictionary = {}
var markers: Array = []
var zones: Array = []
var routes: Array = []
var stats: Dictionary = {}

var _h := PackedByteArray()
var _t := PackedByteArray()
var _s := PackedByteArray()
## Cells touched by a prop footprint: {tile_index: Array of [x, z, r]}.
var _blockers: Dictionary = {}


# ------------------------------------------------------------------ loading --
func load_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		push_warning("[REGION] berkas peta tidak ada: %s" % path)
		return false
	var text := FileAccess.get_file_as_string(path)
	if text.length() < 16:
		push_warning("[REGION] peta kosong: %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[REGION] JSON peta rusak: %s" % path)
		return false
	var data: Dictionary = parsed
	if int(data.get("schema", 0)) > SCHEMA:
		push_warning("[REGION] peta dari versi lebih baru (schema %d)" % int(data.get("schema", 0)))
		return false
	width = int(data.get("width", 0))
	height = int(data.get("height", 0))
	if width <= 0 or height <= 0:
		return false
	cell = float(data.get("cell", 1.0))
	level_h = float(data.get("level_h", 1.8))
	chunk = maxi(8, int(data.get("chunk", 32)))
	label = String(data.get("label", data.get("name", "Yaros")))
	seed_value = int(data.get("seed", 0))
	var org: Array = data.get("origin", [])
	if org.size() >= 2:
		origin = Vector2(float(org[0]), float(org[1]))
	_h = _decode(String(data.get("grid_height", "")), width * height)
	_t = _decode(String(data.get("grid_terrain", "")), width * height)
	_s = _decode(String(data.get("grid_structure", "")), width * height)
	if _h.size() != width * height or _t.size() != width * height or _s.size() != width * height:
		push_warning("[REGION] grid peta tidak cocok dengan %dx%d" % [width, height])
		return false
	var d: Variant = data.get("decor", {})
	decor = d if typeof(d) == TYPE_DICTIONARY else {}
	var mk: Variant = data.get("markers", [])
	markers = mk if typeof(mk) == TYPE_ARRAY else []
	var zs: Variant = data.get("zones", [])
	zones = zs if typeof(zs) == TYPE_ARRAY else []
	var rt: Variant = data.get("routes", [])
	routes = rt if typeof(rt) == TYPE_ARRAY else []
	var st: Variant = data.get("stats", {})
	stats = st if typeof(st) == TYPE_DICTIONARY else {}
	_index_blockers()
	loaded = true
	return true


func _decode(b64: String, expect: int) -> PackedByteArray:
	if b64.length() < 4:
		return PackedByteArray()
	var raw := Marshalls.base64_to_raw(b64)
	if raw.size() != expect:
		push_warning("[REGION] grid %d byte, harusnya %d" % [raw.size(), expect])
	return raw


## Props that stand in the way are indexed per tile once, so a walking knight
## asks a dictionary instead of scanning 3 000 trees every frame.
func _index_blockers() -> void:
	_blockers.clear()
	for kind in decor.keys():
		var radius := blocker_radius(String(kind))
		if radius <= 0.0:
			continue
		var list: Array = decor[kind]
		for entry in list:
			if typeof(entry) != TYPE_ARRAY:
				continue
			var row: Array = entry
			if row.size() < 2:
				continue
			var p := Vector2(float(row[0]) * 0.1, float(row[1]) * 0.1)
			var t := world_to_tile(p)
			var key := t.y * width + t.x
			if not _blockers.has(key):
				_blockers[key] = []
			(_blockers[key] as Array).append([p.x, p.y, radius])


static func blocker_radius(kind: String) -> float:
	match kind:
		"cottage":
			return 2.0
		"oak":
			return 0.8
		"pine":
			return 0.5
		"rock":
			return 0.65
		"stump":
			return 0.45
		"well":
			return 0.9
		"tower":
			return 2.4
		"gate":
			return 2.2
		"dock":
			return 0.0
		_:
			return 0.0


# ------------------------------------------------------------------- tiles ---
func in_bounds(tx: int, tz: int) -> bool:
	return tx >= 0 and tz >= 0 and tx < width and tz < height


func tile_height(tx: int, tz: int) -> int:
	if not in_bounds(tx, tz):
		return 0
	return _h[tz * width + tx]


func tile_terrain(tx: int, tz: int) -> int:
	if not in_bounds(tx, tz):
		return T_GRASS
	return _t[tz * width + tx]


func tile_struct(tx: int, tz: int) -> int:
	if not in_bounds(tx, tz):
		return S_NONE
	return _s[tz * width + tx]


func struct_code(tx: int, tz: int) -> int:
	return tile_struct(tx, tz) & 0x0F


func struct_dir(tx: int, tz: int) -> int:
	return (tile_struct(tx, tz) >> 4) & 0x0F


func world_to_tile(pos: Vector2) -> Vector2i:
	if width == 0 or height == 0:
		return Vector2i.ZERO
	var corner := origin - Vector2(width, height) * cell * 0.5
	return Vector2i(int(floor((pos.x - corner.x) / cell)),
		int(floor((pos.y - corner.y) / cell)))


func tile_centre(tx: int, tz: int) -> Vector2:
	var corner := origin - Vector2(width, height) * cell * 0.5
	return corner + (Vector2(tx, tz) + Vector2(0.5, 0.5)) * cell


func bounds() -> Rect2:
	if width == 0 or height == 0:
		return Rect2()
	var size := Vector2(width, height) * cell
	return Rect2(origin - size * 0.5, size)


## The three byte grids, for callers that walk the whole map once (the map
## painter). Reading 36 864 tiles through `call()` tripled that walk's cost.
func raw_tiles() -> Dictionary:
	return {"height": _h, "terrain": _t, "structure": _s}


func chunk_count() -> int:
	var n := int(ceil(float(width) / float(chunk)))
	return n


# ----------------------------------------------------------------- heights ---
## Corner heights of one tile (TL, TR, BL, BR), the surface the mesh draws.
##
## A corner is shared by up to four tiles. When those four are within one level
## of each other the corner takes their average - that is what turns a one-level
## bank into a ramp with no seam between the tiles. When they are not, the corner
## keeps its own tile's height, which leaves a hard edge; the mesh puts a cliff
## wall exactly there.
func corner_heights(tx: int, tz: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(4)
	var own := float(tile_height(tx, tz)) * level_h
	for i in range(4):
		var dx := 0 if i % 2 == 0 else 1
		var dz := 0 if i < 2 else 1
		var lo := 999
		var hi := -999
		var total := 0
		var count := 0
		for oz in range(-1, 1):
			for ox in range(-1, 1):
				var qx := tx + dx + ox
				var qz := tz + dz + oz
				if not in_bounds(qx, qz):
					continue
				var hv := tile_height(qx, qz)
				lo = mini(lo, hv)
				hi = maxi(hi, hv)
				total += hv
				count += 1
		if count > 0 and hi - lo <= 1:
			out[i] = (float(total) / float(count)) * level_h
		else:
			out[i] = own
	return out


## Metres above the world floor at a point, interpolated across the tile's four
## corners. Walking over a bank is smooth because this is the same surface the
## mesh draws, not a step function.
func height_at(pos: Vector2) -> float:
	var t := world_to_tile(pos)
	if not in_bounds(t.x, t.y):
		return 0.0
	var c := tile_centre(t.x, t.y)
	var u := clampf((pos.x - c.x) / cell + 0.5, 0.0, 1.0)
	var v := clampf((pos.y - c.y) / cell + 0.5, 0.0, 1.0)
	var code := struct_code(t.x, t.y)
	if code == S_STAIR:
		# a flight is four real steps in the mesh, so the feet have to stand on
		# the steps, not on the straight line through them
		return _stair_height(pos, t.x, t.y)
	if code == S_BRIDGE:
		# the deck of a bridge is drawn 12 cm above the road it spans
		return _flat_height(t.x, t.y, u, v) + 0.12
	# water sits below the bank: a knight in the shallows is ankle-deep
	if tile_terrain(t.x, t.y) == T_SHALLOW:
		return _flat_height(t.x, t.y, u, v) - 0.10
	return _flat_height(t.x, t.y, u, v)


func _flat_height(tx: int, tz: int, u: float, v: float) -> float:
	var ch := corner_heights(tx, tz)
	var top := lerpf(ch[0], ch[1], u)
	var bot := lerpf(ch[2], ch[3], u)
	return lerpf(top, bot, v)


## Bottom and top of a stone flight, the same two numbers the mesher draws its
## four steps between. One function, so the feet and the stone cannot drift.
func stair_profile(tx: int, tz: int) -> PackedFloat32Array:
	var low := 1.0e9
	var high := -1.0e9
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = tx + d.x
		var nz: int = tz + d.y
		if not in_bounds(nx, nz):
			continue
		var hv := float(tile_height(nx, nz)) * level_h
		low = minf(low, hv)
		high = maxf(high, hv)
	if low > 1.0e8:
		low = 0.0
		high = level_h
	var top := maxf(high, float(tile_height(tx, tz)) * level_h)
	if top - low < 0.05:
		low = maxf(0.0, top - level_h)
	var out := PackedFloat32Array()
	out.append(low)
	out.append(top)
	return out


const STAIR_STEPS := 4


func _stair_height(pos: Vector2, tx: int, tz: int) -> float:
	var prof := stair_profile(tx, tz)
	var low := prof[0]
	var top := prof[1]
	var c := tile_centre(tx, tz)
	var local := (pos - c) / cell + Vector2(0.5, 0.5)
	var dir := struct_dir(tx, tz)
	var along := local.x
	match dir:
		1:
			along = local.y
		2:
			along = 1.0 - local.x
		3:
			along = 1.0 - local.y
	var step := clampi(int(floor(along * float(STAIR_STEPS))), 0, STAIR_STEPS - 1)
	return lerpf(low, top, float(step + 1) / float(STAIR_STEPS))


# ------------------------------------------------------------- walkability ---
func walkable_tile(tx: int, tz: int) -> bool:
	if not in_bounds(tx, tz):
		return false
	var code := struct_code(tx, tz)
	if S_BLOCKING.has(code):
		return false
	if code == S_BRIDGE:
		return true
	if tile_height(tx, tz) >= 5:
		return false
	var ter := tile_terrain(tx, tz)
	if ter == T_SHALLOW:
		return code == S_RAMP
	if TERRAIN_WATER.has(ter):
		return false
	return TERRAIN_WALKABLE.has(ter)


## May the knight cross from one tile to the neighbour? One level is a bank, two
## levels only over a stone flight.
func step_ok(ax: int, az: int, bx: int, bz: int) -> bool:
	if not (walkable_tile(ax, az) and walkable_tile(bx, bz)):
		return false
	var dh := absi(tile_height(ax, az) - tile_height(bx, bz))
	if dh <= 1:
		return true
	if dh == 2:
		return struct_code(ax, az) == S_STAIR or struct_code(bx, bz) == S_STAIR
	return false


## Can a body of `radius` metres stand at `pos`? The centre and eight points
## around it must be walkable, and every one of them must be reachable from the
## centre tile - a circle cannot straddle a cliff edge.
func can_stand(pos: Vector2, radius: float) -> bool:
	var t := world_to_tile(pos)
	if not walkable_tile(t.x, t.y):
		return false
	var r := maxf(0.05, radius) * 0.8
	for i in range(8):
		var ang := TAU * float(i) / 8.0
		var p := pos + Vector2(cos(ang), sin(ang)) * r
		var q := world_to_tile(p)
		if q == t:
			continue
		if not step_ok(t.x, t.y, q.x, q.y):
			return false
	return true


## Prop footprints near a point, as [x, z, r] triples.
func blockers_near(pos: Vector2, radius: float) -> Array:
	var out: Array = []
	var t := world_to_tile(pos)
	var span := int(ceil((radius + 2.5) / cell))
	for dz in range(-span, span + 1):
		for dx in range(-span, span + 1):
			var key := (t.y + dz) * width + (t.x + dx)
			if not _blockers.has(key):
				continue
			for raw in _blockers[key]:
				var row: Array = raw
				var d := Vector2(float(row[0]), float(row[1])).distance_to(pos)
				if d <= radius + float(row[2]) + 0.1:
					out.append(row)
	return out


func zone_at(pos: Vector2) -> String:
	var t := world_to_tile(pos)
	for raw in zones:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var z: Dictionary = raw
		var r: Array = z.get("rect", [])
		if r.size() < 4:
			continue
		if t.x >= int(r[0]) and t.y >= int(r[1]) and t.x < int(r[0]) + int(r[2]) \
				and t.y < int(r[1]) + int(r[3]):
			return String(z.get("name", ""))
	return "Jalan Tua"


func markers_of(kind: String) -> Array:
	var out: Array = []
	for raw in markers:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var m: Dictionary = raw
		if String(m.get("kind", "")) == kind:
			out.append(m)
	return out


func marker(name: String) -> Dictionary:
	for raw in markers:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var m: Dictionary = raw
		if String(m.get("name", "")) == name:
			return m
	return {}


## Marker position in world XZ (the JSON stores tile centres).
func marker_pos(m: Dictionary) -> Vector2:
	return Vector2(float(m.get("x", 0.0)), float(m.get("y", 0.0)))


# ---------------------------------------------------------------- pathing ----
## Nearest walkable tile to a point, spiralling outwards. Used when a marker is
## authored half a tile inside a fence or a doorway.
func nearest_walkable(tile: Vector2i, max_radius: int = 10) -> Vector2i:
	if walkable_tile(tile.x, tile.y):
		return tile
	for r in range(1, max_radius + 1):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dz) != r:
					continue
				var q := Vector2i(tile.x + dx, tile.y + dz)
				if walkable_tile(q.x, q.y):
					return q
	return tile


## A* over the tile grid. Four-way, cost 1, Manhattan heuristic - simple on
## purpose: a quest marker does not need a smooth path, it needs a yes/no and a
## list of tiles the NPC can follow.
func find_path(from: Vector2, to: Vector2) -> Array:
	var a := world_to_tile(from)
	var b := world_to_tile(to)
	if not walkable_tile(a.x, a.y):
		a = nearest_walkable(a)
	if not walkable_tile(b.x, b.y):
		b = nearest_walkable(b)
	var start := a.y * width + a.x
	var goal := b.y * width + b.x
	if start == goal:
		return [tile_centre(b.x, b.y)]
	var open: Array = [start]
	var came: Dictionary = {}
	var cost: Dictionary = {start: 0}
	var closed: Dictionary = {}
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var visited := 0
	while not open.is_empty():
		visited += 1
		if visited > PATH_BUDGET:
			return []
		# pick the cheapest by f = g + h (open list is small; a linear scan beats
		# a heap for the distances this game asks for)
		var best_i := 0
		var best_f := 1.0e9
		for i in range(open.size()):
			var node: int = open[i]
			var g := float(cost.get(node, 0))
			var nx := node % width
			var nz := node / width
			var h := float(absi(nx - b.x) + absi(nz - b.y))
			if g + h < best_f:
				best_f = g + h
				best_i = i
		var current: int = open[best_i]
		open.remove_at(best_i)
		if current == goal:
			return _rebuild(came, current)
		closed[current] = true
		var cx := current % width
		var cz := current / width
		for d: Vector2i in dirs:
			var nx2: int = cx + d.x
			var nz2: int = cz + d.y
			if not step_ok(cx, cz, nx2, nz2):
				continue
			var nxt: int = nz2 * width + nx2
			if closed.has(nxt):
				continue
			var tentative: float = float(cost.get(current, 0)) + 1.0
			if cost.has(nxt) and tentative >= float(cost[nxt]):
				continue
			cost[nxt] = tentative
			came[nxt] = current
			if not open.has(nxt):
				open.append(nxt)
	return []


func _rebuild(came: Dictionary, node: int) -> Array:
	var out: Array = []
	var guard := 0
	while came.has(node) and guard < 100000:
		out.append(tile_centre(node % width, node / width))
		node = int(came[node])
		guard += 1
	out.append(tile_centre(node % width, node / width))
	out.reverse()
	return out


## Distance along the main road, in tiles, for the report and the travel test.
func road_tiles() -> float:
	return float(stats.get("road_tiles", 0.0))


func start_position() -> Vector2:
	var m := markers_of("player_start")
	if m.is_empty():
		return tile_centre(width / 2, height / 2)
	return marker_pos(m[0] as Dictionary)
