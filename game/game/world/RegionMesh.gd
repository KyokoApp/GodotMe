extends RefCounted
## Turns one 32x32 chunk of region DATA into vertex arrays.
##
## Pure maths: it reads the three byte grids and returns PackedArrays. No nodes,
## no RenderingServer calls, no scene tree - which is exactly what makes it safe
## to run on a WorkerThreadPool while the phone keeps drawing. The main thread
## only uploads the finished arrays into an ArrayMesh (a memcpy of a few hundred
## kilobytes) instead of building geometry inside a frame.
##
## Four surfaces per chunk, one material each:
##   terrain  the tops; vertex colour carries the blend weights between the
##            grass, dirt, rock and sand cells of the atlas, plus snow in alpha
##   cliff    only edges that drop two levels or more, with fake AO at the foot
##   wood     bridge decks and rails
##   water    a surface 14 cm below the tile height, tinted by depth, foam on the
##            edges that touch land
##
## Geometry rules that matter:
##   * a top is a bilinear patch over the four corner heights, so a one-level
##     bank is a smooth ramp and two neighbouring tiles never leave a crack;
##   * a stone flight is drawn as four real steps with risers, rising towards
##     `struct_dir`;
##   * a bridge is a wooden deck 12 cm above the road with rails on the water
##     sides; the tiles around it keep their own tops;
##   * at the region border the world is closed with a skirt wall down to the
##     floor, so the outside of Yaros never shows the void;
##   * UVs are WORLD coordinates in metres, not per tile: the shader does
##     `fract(uv / 2.0)` so a texture repeats every two metres across tiles
##     instead of showing the same 256x256 square once per tile.

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

const S_NONE := 0
const S_STAIR := 1
const S_BRIDGE := 2
const S_FENCE := 3
const S_WALL := 4
const S_GATE := 5
const S_DOOR := 6
const S_RAMP := 7

## Terrain blend weights per kind: (dirt, rock, sand, snow) in 0..1.
## Grass is the base the others are mixed over, so it needs no channel.
const WEIGHTS := {
	T_GRASS: Vector4(0.0, 0.0, 0.0, 0.0),
	T_TALL: Vector4(0.0, 0.0, 0.0, 0.0),
	T_DIRT: Vector4(1.0, 0.0, 0.0, 0.0),
	T_MUD: Vector4(1.0, 0.0, 0.0, 0.0),
	T_ROCK: Vector4(0.0, 1.0, 0.0, 0.0),
	T_STONE: Vector4(0.0, 1.0, 0.0, 0.0),
	T_SAND: Vector4(0.0, 0.0, 1.0, 0.0),
	T_SNOW: Vector4(0.0, 0.25, 0.0, 0.75),
	T_SHALLOW: Vector4(0.0, 0.0, 1.0, 0.0),
	T_DEEP: Vector4(0.0, 0.0, 1.0, 0.0),
	T_WOOD: Vector4(1.0, 0.0, 0.0, 0.0),
}
## Grass shade multiplier per kind (tall grass reads darker, mud browner).
const SHADE := {
	T_GRASS: 1.0,
	T_TALL: 0.84,
	T_MUD: 0.86,
	T_SNOW: 1.0,
	T_ROCK: 1.0,
	T_STONE: 1.0,
	T_SAND: 1.0,
	T_DIRT: 1.0,
	T_WOOD: 1.0,
	T_SHALLOW: 1.0,
	T_DEEP: 1.0,
}

## Water tint per depth, written into vertex colour and read by the shader.
const WATER_SHALLOW := Color(0.60, 0.78, 0.76)
const WATER_DEEP := Color(0.26, 0.42, 0.50)


## Build the arrays for chunk (cx, cz). Empty when the chunk is outside the map.
static func build(data: RefCounted, cx: int, cz: int) -> Dictionary:
	var csz: int = int(data.get("chunk"))
	var w: int = int(data.get("width"))
	var h: int = int(data.get("height"))
	var x0: int = cx * csz
	var z0: int = cz * csz
	if x0 >= w or z0 >= h:
		return {}
	var x1: int = mini(w, x0 + csz)
	var z1: int = mini(h, z0 + csz)
	var cell: float = float(data.get("cell"))
	var level_h: float = float(data.get("level_h"))

	var terrain := _surface()
	var cliff := _surface()
	var wood := _surface()
	var water := _surface()

	for tz in range(z0, z1):
		for tx in range(x0, x1):
			var ter: int = int(data.call("tile_terrain", tx, tz))
			var code: int = int(data.call("struct_code", tx, tz))
			var centre: Vector2 = data.call("tile_centre", tx, tz)
			var base := Vector3(centre.x - cell * 0.5, 0.0, centre.y - cell * 0.5)
			if ter == T_SHALLOW or ter == T_DEEP:
				_add_bed(data, tx, tz, base, cell, level_h, ter, terrain)
				_add_water(data, tx, tz, base, cell, level_h, ter, water)
				continue
			if code == S_BRIDGE:
				_add_bridge(data, tx, tz, base, cell, level_h, wood, water)
				_add_walls(data, tx, tz, base, cell, level_h, cliff)
				continue
			if ter == T_WOOD:
				_add_wood_top(tx, tz, base, cell, data, wood)
				_add_walls(data, tx, tz, base, cell, level_h, cliff)
				continue
			_add_top(data, tx, tz, base, cell, ter, terrain)
			if code == S_STAIR:
				_add_steps(data, tx, tz, base, cell, level_h, terrain, wood)
			_add_walls(data, tx, tz, base, cell, level_h, cliff)
			if code == S_FENCE:
				_add_rail(base, cell, level_h, wood, int(data.call("tile_height", tx, tz)))
			elif code == S_GATE or code == S_WALL:
				_add_gate_wall(base, cell, level_h, wood, int(data.call("tile_height", tx, tz)))

	return {
		"terrain": terrain,
		"cliff": cliff,
		"wood": wood,
		"water": water,
		"chunk": Vector2i(cx, cz),
	}


static func _surface() -> Dictionary:
	return {
		"verts": PackedVector3Array(),
		"norms": PackedVector3Array(),
		"uvs": PackedVector2Array(),
		"uv2s": PackedVector2Array(),
		"colors": PackedColorArray(),
		"indices": PackedInt32Array(),
	}


## Push one quad (four corners, counter-clockwise seen from the front) into a
## surface. `uv` are world coordinates; `colour` is the terrain blend or the
## depth tint, `shade` the extra channel the terrain shader reads (tall grass,
## mud) and the foliage/wall AO.
static func quad(surf: Dictionary, p: Array, uv: Array, colour: Color,
		shade: float, normal: Vector3) -> void:
	var verts: PackedVector3Array = surf["verts"]
	var norms: PackedVector3Array = surf["norms"]
	var uvs: PackedVector2Array = surf["uvs"]
	var uv2s: PackedVector2Array = surf["uv2s"]
	var cols: PackedColorArray = surf["colors"]
	var idx: PackedInt32Array = surf["indices"]
	var first := verts.size()
	for i in range(4):
		verts.append(p[i])
		norms.append(normal)
		uvs.append(uv[i])
		uv2s.append(Vector2(shade, 0.0))
		cols.append(colour)
	idx.append(first)
	idx.append(first + 2)
	idx.append(first + 1)
	idx.append(first + 2)
	idx.append(first + 3)
	idx.append(first + 1)


## Same as `quad()`, but with one colour per corner. The ground uses this so the
## grass can dissolve into the path across a tile edge instead of switching
## texture on a dead-straight line.
static func quad4(surf: Dictionary, p: Array, uv: Array, cols_in: Array,
		shade: float, normal: Vector3) -> void:
	var verts: PackedVector3Array = surf["verts"]
	var norms: PackedVector3Array = surf["norms"]
	var uvs: PackedVector2Array = surf["uvs"]
	var uv2s: PackedVector2Array = surf["uv2s"]
	var cols: PackedColorArray = surf["colors"]
	var idx: PackedInt32Array = surf["indices"]
	var first := verts.size()
	for i in range(4):
		verts.append(p[i])
		norms.append(normal)
		uvs.append(uv[i])
		uv2s.append(Vector2(shade, 0.0))
		cols.append(cols_in[i])
	idx.append(first)
	idx.append(first + 2)
	idx.append(first + 1)
	idx.append(first + 2)
	idx.append(first + 3)
	idx.append(first + 1)


## Blend weights at one corner of a tile.
##
## Two failures bracket this function. Averaging the four tiles that meet at a
## corner dissolved a one-tile-wide path into the grass it crossed - the road
## disappeared. Taking the plain maximum swung the other way: a single dirt tile
## handed its full weight to all four of its neighbours, so 15% dirt tiles painted
## half the forest floor tan.
##
## So: mostly the tile's own surface, partly the strongest neighbour. A tile of
## path stays solid path, a meadow next to it fades over about a metre, and a
## scattered patch stays a patch.
static func _corner_weights(data: RefCounted, tx: int, tz: int) -> Array:
	var out: Array = []
	for i in range(4):
		var dx := 0 if i % 2 == 0 else 1
		var dz := 0 if i < 2 else 1
		var total := Vector4.ZERO
		for oz in range(-1, 1):
			for ox in range(-1, 1):
				var qx: int = tx + dx + ox
				var qz: int = tz + dz + oz
				if not bool(data.call("in_bounds", qx, qz)):
					continue
				var w: Vector4 = WEIGHTS.get(int(data.call("tile_terrain", qx, qz)),
					Vector4.ZERO)
				total = Vector4(maxf(total.x, w.x), maxf(total.y, w.y),
					maxf(total.z, w.z), maxf(total.w, w.w))
		var own: Vector4 = WEIGHTS.get(int(data.call("tile_terrain", tx, tz)),
			Vector4.ZERO)
		total = own * 0.55 + total * 0.45
		# snow carries 0.75 snow + 0.25 rock; two such neighbours must not add up
		# past one, or the shader's sequence of mixes overshoots
		var sum := total.x + total.y + total.z + total.w
		if sum > 1.0:
			total /= sum
		out.append(Color(total.x, total.y, total.z, total.w))
	return out


static func _normal(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	# counter-clockwise seen from above: +Y for a flat tile
	var n := (c - a).cross(b - a)
	if n.length() < 0.0001:
		return Vector3.UP
	return n.normalized()


## The top surface of one walkable tile, as a patch over its four corners.
static func _add_top(data: RefCounted, tx: int, tz: int, base: Vector3, cell: float,
		ter: int, surf: Dictionary) -> void:
	var ch: PackedFloat32Array = data.call("corner_heights", tx, tz)
	var p := [
		base + Vector3(0.0, ch[0], 0.0),
		base + Vector3(cell, ch[1], 0.0),
		base + Vector3(0.0, ch[2], cell),
		base + Vector3(cell, ch[3], cell),
	]
	var uv := [
		Vector2(p[0].x, p[0].z), Vector2(p[1].x, p[1].z),
		Vector2(p[2].x, p[2].z), Vector2(p[3].x, p[3].z),
	]
	var cols := _corner_weights(data, tx, tz)
	quad4(surf, p, uv, cols, float(SHADE.get(ter, 1.0)), _normal(p[0], p[1], p[2]))


## Bridge deck: wood, 12 cm above the road, plus rails where the neighbour is
## water and two posts down to the surface below.
static func _add_bridge(data: RefCounted, tx: int, tz: int, base: Vector3, cell: float,
		level_h: float, wood: Dictionary, water: Dictionary) -> void:
	var hgt: int = int(data.call("tile_height", tx, tz))
	# a bridge over a river sits at the height of the banks, and the water under
	# it is drawn by the water tiles next door; if the tile itself is water the
	# deck spans it at the higher of the two banks
	var y := float(hgt) * level_h + 0.12
	var p := [
		base + Vector3(0.0, y, 0.0), base + Vector3(cell, y, 0.0),
		base + Vector3(0.0, y, cell), base + Vector3(cell, y, cell),
	]
	var uv := [
		Vector2(base.x, base.z), Vector2(base.x + cell, base.z),
		Vector2(base.x, base.z + cell), Vector2(base.x + cell, base.z + cell),
	]
	quad(wood, p, uv, Color(1, 1, 1, 1), 1.0, Vector3.UP)
	for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
		var nx: int = tx + d.x
		var nz: int = tz + d.y
		var nt: int = int(data.call("tile_terrain", nx, nz))
		var over_water := nt == T_SHALLOW or nt == T_DEEP
		if over_water:
			_rail(wood, base, cell, y, d)
		# supports: a post at each corner of the tile, down to the water
		if over_water and (d.x > 0 or d.y > 0):
			var at := base + Vector3(0.0 if d.x <= 0 else cell, 0.0,
				0.0 if d.y <= 0 else cell)
			_post(wood, Vector3(at.x, y - 0.12, at.z), 0.14, 2.2)


static func _rail(wood: Dictionary, base: Vector3, cell: float, y: float,
		d: Vector2i) -> void:
	var hgt := 0.55
	var side_a: Vector3
	var side_b: Vector3
	if d.x == 1:
		side_a = base + Vector3(cell, y, 0.0)
		side_b = base + Vector3(cell, y, cell)
	elif d.x == -1:
		side_a = base + Vector3(0.0, y, cell)
		side_b = base + Vector3(0.0, y, 0.0)
	elif d.y == 1:
		side_a = base + Vector3(cell, y, cell)
		side_b = base + Vector3(0.0, y, cell)
	else:
		side_a = base + Vector3(0.0, y, 0.0)
		side_b = base + Vector3(cell, y, 0.0)
	var p := [side_a, side_a + Vector3(0, hgt, 0), side_b,
		side_b + Vector3(0, hgt, 0)]
	var uv := [Vector2(0, 0), Vector2(0, 1), Vector2(1, 0), Vector2(1, 1)]
	var n := (side_b - side_a).cross(Vector3.UP)
	quad(wood, p, uv, Color(1, 1, 1, 1), 0.9, n.normalized() if n.length() > 0.001 else Vector3.UP)


static func _post(wood: Dictionary, top: Vector3, half: float, height: float) -> void:
	var p := [
		top + Vector3(-half, 0, -half), top + Vector3(half, 0, -half),
		top + Vector3(-half, -height, -half), top + Vector3(half, -height, -half),
	]
	var uv := [Vector2(0, 0), Vector2(0.3, 0), Vector2(0, 1), Vector2(0.3, 1)]
	quad(wood, p, uv, Color(0.85, 0.85, 0.85, 1.0), 0.9, Vector3.FORWARD)
	var p2 := [
		top + Vector3(half, 0, -half), top + Vector3(half, 0, half),
		top + Vector3(half, -height, -half), top + Vector3(half, -height, half),
	]
	quad(wood, p2, uv, Color(0.85, 0.85, 0.85, 1.0), 0.9, Vector3.RIGHT)


## A wooden floor tile (dock, house floor): planks along X, drawn with the wood
## surface so the texture does not have to share the terrain blend.
static func _add_wood_top(tx: int, tz: int, base: Vector3, cell: float,
		data: RefCounted, wood: Dictionary) -> void:
	var ch: PackedFloat32Array = data.call("corner_heights", tx, tz)
	var p := [
		base + Vector3(0.0, ch[0], 0.0), base + Vector3(cell, ch[1], 0.0),
		base + Vector3(0.0, ch[2], cell), base + Vector3(cell, ch[3], cell),
	]
	var uv := [
		Vector2(base.x, base.z), Vector2(base.x + cell, base.z),
		Vector2(base.x, base.z + cell), Vector2(base.x + cell, base.z + cell),
	]
	quad(wood, p, uv, Color(1, 1, 1, 1), 1.0, _normal(p[0], p[1], p[2]))


## Cliff walls: only where the drop is two levels or more. A one-level bank is
## geometry of the tops themselves.
static func _add_walls(data: RefCounted, tx: int, tz: int, base: Vector3, cell: float,
		level_h: float, cliff: Dictionary) -> void:
	var here: PackedFloat32Array = data.call("corner_heights", tx, tz)
	var hh: int = int(data.call("tile_height", tx, tz))
	var dirs := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
	for d in dirs:
		var nx: int = tx + d.x
		var nz: int = tz + d.y
		var low_y: float
		var low_a: Vector3
		var low_b: Vector3
		if not bool(data.call("in_bounds", nx, nz)):
			# the edge of the world: close it down to the floor
			low_y = 0.0
			low_a = base
			low_b = base
			if d.x == 1:
				low_a = base + Vector3(cell, 0.0, 0.0)
				low_b = base + Vector3(cell, 0.0, cell)
			elif d.x == -1:
				low_a = base + Vector3(0.0, 0.0, cell)
				low_b = base + Vector3(0.0, 0.0, 0.0)
			elif d.y == 1:
				low_a = base + Vector3(cell, 0.0, cell)
				low_b = base + Vector3(0.0, 0.0, cell)
			else:
				low_a = base + Vector3(0.0, 0.0, 0.0)
				low_b = base + Vector3(cell, 0.0, 0.0)
			var top_a: Vector3
			var top_b: Vector3
			if d.x == 1:
				top_a = base + Vector3(cell, here[1], 0.0)
				top_b = base + Vector3(cell, here[3], cell)
			elif d.x == -1:
				top_a = base + Vector3(0.0, here[0], 0.0)
				top_b = base + Vector3(0.0, here[2], cell)
			elif d.y == 1:
				top_a = base + Vector3(0.0, here[2], cell)
				top_b = base + Vector3(cell, here[3], cell)
			else:
				top_a = base + Vector3(0.0, here[0], 0.0)
				top_b = base + Vector3(cell, here[1], 0.0)
			_wall_quad(cliff, top_a, top_b, low_a, low_b, d)
			continue
		var nh: int = int(data.call("tile_height", nx, nz))
		if hh - nh < 2:
			continue
		var low: PackedFloat32Array = data.call("corner_heights", nx, nz)
		if d.x == 1:
			low_a = base + Vector3(cell, low[1], 0.0)
			low_b = base + Vector3(cell, low[3], cell)
			_wall_quad(cliff, base + Vector3(cell, here[1], 0.0),
				base + Vector3(cell, here[3], cell), low_a, low_b, d)
		elif d.x == -1:
			low_a = base + Vector3(0.0, low[0], 0.0)
			low_b = base + Vector3(0.0, low[2], cell)
			_wall_quad(cliff, base + Vector3(0.0, here[2], cell),
				base + Vector3(0.0, here[0], 0.0), low_b, low_a, d)
		elif d.y == 1:
			low_a = base + Vector3(0.0, low[2], cell)
			low_b = base + Vector3(cell, low[3], cell)
			_wall_quad(cliff, base + Vector3(0.0, here[2], cell),
				base + Vector3(cell, here[3], cell), low_a, low_b, d)
		else:
			low_a = base + Vector3(cell, low[1], 0.0)
			low_b = base + Vector3(0.0, low[0], 0.0)
			_wall_quad(cliff, base + Vector3(cell, here[1], 0.0),
				base + Vector3(0.0, here[0], 0.0), low_a, low_b, d)


## One wall face: UVs in metres so the rock repeats every two metres and the
## strata stay horizontal, and vertex colour alpha carries the AO (dark at the
## foot, full at the lip).
static func _wall_quad(cliff: Dictionary, top_a: Vector3, top_b: Vector3,
		low_a: Vector3, low_b: Vector3, d: Vector2i) -> void:
	var run := top_a.distance_to(top_b)
	var height := maxf(0.05, top_a.y - low_a.y)
	var p := [low_a, low_b, top_a, top_b]
	var y0 := 0.0
	var y1 := height
	var uv := [
		Vector2(0.0, y0), Vector2(run, y0), Vector2(0.0, y1), Vector2(run, y1),
	]
	var n := Vector3.RIGHT if d.x == 1 else (Vector3.LEFT if d.x == -1
		else (Vector3.BACK if d.y == 1 else Vector3.FORWARD))
	# AO: the two bottom vertices darker than the two top ones
	var verts: PackedVector3Array = cliff["verts"]
	var norms: PackedVector3Array = cliff["norms"]
	var uvs: PackedVector2Array = cliff["uvs"]
	var uv2s: PackedVector2Array = cliff["uv2s"]
	var cols: PackedColorArray = cliff["colors"]
	var idx: PackedInt32Array = cliff["indices"]
	var first := verts.size()
	var shades := [0.62, 0.62, 1.0, 1.0]
	for i in range(4):
		verts.append(p[i])
		norms.append(n)
		uvs.append(uv[i])
		uv2s.append(Vector2(0.0, 0.0))
		cols.append(Color(1, 1, 1, shades[i]))
	idx.append(first)
	idx.append(first + 2)
	idx.append(first + 1)
	idx.append(first + 2)
	idx.append(first + 3)
	idx.append(first + 1)


## A stone flight: four real steps with risers, rising towards `struct_dir`, so
## the climb reads as stairs and not as a striped ramp.
static func _add_steps(data: RefCounted, tx: int, tz: int, base: Vector3, cell: float,
		level_h: float, terrain: Dictionary, wood: Dictionary) -> void:
	var prof: PackedFloat32Array = data.call("stair_profile", tx, tz)
	var low: float = prof[0]
	var top: float = prof[1]
	var dir: int = int(data.call("struct_dir", tx, tz))
	var ter: int = int(data.call("tile_terrain", tx, tz))
	var surf: Dictionary = wood if ter == T_WOOD else terrain
	var steps := 4
	var w: Vector4 = WEIGHTS.get(ter, Vector4(0.0, 1.0, 0.0, 0.0))
	var base_colour := Color(w.x, w.y, w.z, w.w)
	for s in range(steps):
		var t0 := float(s) / float(steps)
		var t1 := float(s + 1) / float(steps)
		var y0 := lerpf(low, top, t1)
		var inset := 0.02
		var p: Array = []
		match dir:
			0:   # rises towards +x
				p = [base + Vector3(cell * t0, y0, 0.0),
					base + Vector3(cell * t1 - inset, y0, 0.0),
					base + Vector3(cell * t0, y0, cell),
					base + Vector3(cell * t1 - inset, y0, cell)]
			1:   # rises towards +z
				p = [base + Vector3(0.0, y0, cell * t0),
					base + Vector3(cell, y0, cell * t0),
					base + Vector3(0.0, y0, cell * t1 - inset),
					base + Vector3(cell, y0, cell * t1 - inset)]
			2:   # rises towards -x
				p = [base + Vector3(cell * (1.0 - t1) + inset, y0, 0.0),
					base + Vector3(cell * (1.0 - t0), y0, 0.0),
					base + Vector3(cell * (1.0 - t1) + inset, y0, cell),
					base + Vector3(cell * (1.0 - t0), y0, cell)]
			_:
				p = [base + Vector3(0.0, y0, cell * (1.0 - t1) + inset),
					base + Vector3(cell, y0, cell * (1.0 - t1) + inset),
					base + Vector3(0.0, y0, cell * (1.0 - t0)),
					base + Vector3(cell, y0, cell * (1.0 - t0))]
		var uv := [Vector2(p[0].x, p[0].z), Vector2(p[1].x, p[1].z),
			Vector2(p[2].x, p[2].z), Vector2(p[3].x, p[3].z)]
		quad(surf, p, uv, base_colour, 1.0, Vector3.UP)


## A fence tile: three horizontal rails on two posts. It is drawn, not walked
## through - RegionData blocks the tile.
static func _add_rail(base: Vector3, cell: float, level_h: float, wood: Dictionary,
		hgt: int) -> void:
	var y := float(hgt) * level_h
	var body := Color(0.98, 0.94, 0.88, 1.0)
	for level: float in [0.35, 0.62, 0.9]:
		var yy: float = y + level
		var p := [base + Vector3(0.0, yy, cell * 0.5),
			base + Vector3(cell, yy, cell * 0.5),
			base + Vector3(0.0, yy + 0.09, cell * 0.5),
			base + Vector3(cell, yy + 0.09, cell * 0.5)]
		var uv := [Vector2(0, 0), Vector2(cell, 0), Vector2(0, 0.09), Vector2(cell, 0.09)]
		quad(wood, p, uv, body, 1.0, Vector3.UP)
	for x in [0.2, cell - 0.2]:
		_post(wood, base + Vector3(x, y + 0.95, cell * 0.5), 0.07, 0.95)


## A wall or a shut gate: a solid slab with a stone coping, so a boundary reads
## as built rather than as a missing tile.
static func _add_gate_wall(base: Vector3, cell: float, level_h: float,
		wood: Dictionary, hgt: int) -> void:
	var y := float(hgt) * level_h
	var p := [base + Vector3(0.0, y, 0.0), base + Vector3(cell, y, 0.0),
		base + Vector3(0.0, y + 1.5, 0.0), base + Vector3(cell, y + 1.5, 0.0)]
	var uv := [Vector2(0, 0), Vector2(cell, 0), Vector2(0, 1.5), Vector2(cell, 1.5)]
	quad(wood, p, uv, Color(0.9, 0.86, 0.8, 1.0), 1.0, Vector3.FORWARD)
	var p2 := [base + Vector3(cell, y, cell), base + Vector3(0.0, y, cell),
		base + Vector3(cell, y + 1.5, cell), base + Vector3(0.0, y + 1.5, cell)]
	quad(wood, p2, uv, Color(0.9, 0.86, 0.8, 1.0), 1.0, Vector3.BACK)


## The floor of the lake, drawn UNDER the water surface. Without it a water tile
## is a hole in the mesh: the surface is semi-transparent, so looking across a
## lake showed the background through it - flat black polygons with tile-shaped
## edges, which is what the Danau Cermin capture caught.
static func _add_bed(data: RefCounted, tx: int, tz: int, base: Vector3, cell: float,
		level_h: float, ter: int, surf: Dictionary) -> void:
	var ch: PackedFloat32Array = data.call("corner_heights", tx, tz)
	var drop := 0.55 if ter == T_SHALLOW else 1.30
	var p := [
		base + Vector3(0.0, ch[0] - drop, 0.0),
		base + Vector3(cell, ch[1] - drop, 0.0),
		base + Vector3(0.0, ch[2] - drop, cell),
		base + Vector3(cell, ch[3] - drop, cell),
	]
	var uv := [Vector2(p[0].x, p[0].z), Vector2(p[1].x, p[1].z),
		Vector2(p[2].x, p[2].z), Vector2(p[3].x, p[3].z)]
	# wet sand at the edge, darker silt in the deep: the same atlas cells the
	# shore uses, just mixed the other way round
	var sand := 0.75 if ter == T_SHALLOW else 0.35
	quad(surf, p, uv, Color(0.0, 0.15 if ter == T_DEEP else 0.0, sand, 0.0),
		0.78 if ter == T_DEEP else 0.9, Vector3.UP)


static func _add_water(data: RefCounted, tx: int, tz: int, base: Vector3, cell: float,
		level_h: float, ter: int, water: Dictionary) -> void:
	# one surface for the whole region (see RegionData._measure_water): a lake with
	# a stepped floor must not be a stack of floating sheets
	var y: float = float(data.get("water_y"))
	var shallow := ter == T_SHALLOW
	var foam := 0.0
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = tx + d.x
		var nz: int = tz + d.y
		if not bool(data.call("in_bounds", nx, nz)):
			continue
		var nt: int = int(data.call("tile_terrain", nx, nz))
		if nt != T_SHALLOW and nt != T_DEEP:
			foam = 1.0
	var tint: Color = WATER_SHALLOW if shallow else WATER_DEEP
	var p := [base + Vector3(0.0, y, 0.0), base + Vector3(cell, y, 0.0),
		base + Vector3(0.0, y, cell), base + Vector3(cell, y, cell)]
	var uv := [Vector2(p[0].x, p[0].z), Vector2(p[1].x, p[1].z),
		Vector2(p[2].x, p[2].z), Vector2(p[3].x, p[3].z)]
	# alpha of the vertex colour = "this tile touches land", used for the foam
	quad(water, p, uv, Color(tint.r, tint.g, tint.b, foam), 1.0, Vector3.UP)


## Every chunk built once, for tests and for the loading screen.
static func build_all(data: RefCounted) -> Dictionary:
	var n: int = int(data.call("chunk_count"))
	var chunks := 0
	var vertices := 0
	for cz in range(n):
		for cx in range(n):
			var arrays: Dictionary = build(data, cx, cz)
			if arrays.is_empty():
				continue
			chunks += 1
			for key in ["terrain", "cliff", "wood", "water"]:
				var surf: Dictionary = arrays[key]
				vertices += (surf["verts"] as PackedVector3Array).size()
	return {"chunks": chunks, "vertices": vertices}
