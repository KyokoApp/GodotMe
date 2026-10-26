## No `class_name` on purpose - see WorldArt.gd: the game runs inside the
## launcher's project, whose class cache never saw this script.
extends RefCounted
## Step 3B: every building in Yaros is a low-poly MESH with pixel textures,
## assembled from one modular kit.
##
## Why a kit and not a model per house: the brief asks for many variations
## without new models, and the region has five cottages, two towers, a gate, a
## well, a jetty, five signs and seven torches. A cottage is a box of plaster
## with an oak frame, four corner posts, a door, three windows, a foundation, a
## gable roof (thatch or shingle) and sometimes a chimney - all of them the same
## fifteen primitives with different numbers. So one function builds all
## cottages, `variant` picks the roof and the extra floor, and the tint breaks up
## the row.
##
## Contract with the shader (`building.gdshader`), which is why the UVs look odd:
##   UV  = texture repeats (metres / the cell's tile size); a decal uses 0..0,992
##   UV2 = the atlas cell's origin - this is how a quad picks its cell
##   COLOR.rgb = tint, COLOR.a = detail class (LIT / DETAIL above, not alpha)
## Everything a building is made of therefore ends up in ONE surface with ONE
## material: a cottage is one draw call.
##
## The kit is data: `building_kit.json` lists the cells (name, atlas rect, how
## many metres one repeat covers) and the kinds (size, variants, block radius),
## and `tools/gen_building_kit.py` writes both that file and the atlas.

const META_PATH := "res://game/world/building_kit.json"
const ATLAS_PATH := "res://game/world/textures/building_atlas.png"

## Metres the foundation reaches below ground, so a house on a slope never shows
## daylight under its floor.
const FOOTING := 1.1

## A decal is mapped to the whole cell, but never to exactly 1.0: the shader
## wraps UVs with fract(), and fract(1.0) is 0.0 - every window would wear a
## one-pixel line of the cell's first row along its top and right edge.
const DECAL_UV := 0.9921875

## Vertex colour alpha is a detail class that the shader reads (see
## building.gdshader): LIT glows at night, DETAIL is a small decal the shader
## drops past `detail_range`, and 0 is structure. Nothing here is transparent.
const LIT := 1.0
const DETAIL := 0.4


static func load_meta() -> Dictionary:
	if not FileAccess.file_exists(META_PATH):
		push_warning("[KIT] building_kit.json tidak ada")
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(META_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[KIT] building_kit.json rusak")
		return {}
	return parsed


## name -> Vector2 cell origin in atlas UV space.
static func cells(meta: Dictionary) -> Dictionary:
	var out := {}
	for raw in (meta.get("cells", []) as Array):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var c: Dictionary = raw
		var uv: Array = c.get("uv", [])
		if uv.size() < 4:
			continue
		out[String(c.get("name", ""))] = Vector2(float(uv[0]), float(uv[1]))
	return out


## name -> metres covered by one repeat of that cell.
static func tiles(meta: Dictionary) -> Dictionary:
	var out := {}
	for raw in (meta.get("cells", []) as Array):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var c: Dictionary = raw
		out[String(c.get("name", ""))] = float(c.get("tile_m", 1.0))
	return out


static func kinds(meta: Dictionary) -> Dictionary:
	var raw: Variant = meta.get("kinds", {})
	return raw if typeof(raw) == TYPE_DICTIONARY else {}


# ------------------------------------------------------------------- buffer ---
static func _buf() -> Dictionary:
	return {
		"verts": PackedVector3Array(),
		"norms": PackedVector3Array(),
		"uvs": PackedVector2Array(),
		"uv2s": PackedVector2Array(),
		"colors": PackedColorArray(),
		"index": PackedInt32Array(),
	}


static func _vert(b: Dictionary, p: Vector3, n: Vector3, uv: Vector2, cell: Vector2,
		tint: Color, glow: float) -> int:
	var verts: PackedVector3Array = b["verts"]
	var idx := verts.size()
	verts.append(p)
	(b["norms"] as PackedVector3Array).append(n)
	(b["uvs"] as PackedVector2Array).append(uv)
	(b["uv2s"] as PackedVector2Array).append(cell)
	(b["colors"] as PackedColorArray).append(Color(tint.r, tint.g, tint.b, glow))
	b["verts"] = verts
	return idx


## A quad from four corners in order (a -> b -> c -> d around the face). `tile`
## is the cell's repeat size in metres; 0 means "decal": the whole cell fitted to
## the face exactly (doors, windows, signs, banners).
static func _quad(b: Dictionary, a: Vector3, bb: Vector3, c: Vector3, d: Vector3,
		n: Vector3, cell: Vector2, tile: float, tint: Color, glow: float = 0.0) -> void:
	var u: float
	var v: float
	if tile <= 0.0:
		u = DECAL_UV
		v = DECAL_UV
	else:
		u = (bb - a).length() / tile
		v = (d - a).length() / tile
	var i0 := _vert(b, a, n, Vector2(0.0, 0.0), cell, tint, glow)
	var i1 := _vert(b, bb, n, Vector2(u, 0.0), cell, tint, glow)
	var i2 := _vert(b, c, n, Vector2(u, v), cell, tint, glow)
	var i3 := _vert(b, d, n, Vector2(0.0, v), cell, tint, glow)
	var index: PackedInt32Array = b["index"]
	index.append_array([i0, i1, i2, i0, i2, i3])
	b["index"] = index


static func _tri(b: Dictionary, a: Vector3, bb: Vector3, c: Vector3, n: Vector3,
		cell: Vector2, tile: float, tint: Color, glow: float = 0.0) -> void:
	# project on the plane the triangle faces: a gable end lives in Y/Z, a cone
	# facet mostly in X/Z, so picking the axes by the normal keeps the grain right
	var ax := absf(n.x)
	var ay := absf(n.y)
	var az := absf(n.z)
	var use := tile if tile > 0.0 else 2.0
	var uv := func(p: Vector3) -> Vector2:
		if ay >= ax and ay >= az:
			return Vector2(p.x / use, p.z / use)
		if ax >= az:
			return Vector2(p.z / use, p.y / use)
		return Vector2(p.x / use, p.y / use)
	var i0 := _vert(b, a, n, uv.call(a), cell, tint, glow)
	var i1 := _vert(b, bb, n, uv.call(bb), cell, tint, glow)
	var i2 := _vert(b, c, n, uv.call(c), cell, tint, glow)
	var index: PackedInt32Array = b["index"]
	index.append_array([i0, i1, i2])
	b["index"] = index


## Axis-aligned box. `side` covers the four walls, `top`/`bottom` the caps; a
## building never needs a different texture per wall.
static func _box(b: Dictionary, mn: Vector3, mx: Vector3, side: Vector2,
		tile: float, tint: Color, top: Vector2 = Vector2.ZERO, glow: float = 0.0) -> void:
	var cap := top if top != Vector2.ZERO else side
	# +z (front)
	_quad(b, Vector3(mn.x, mn.y, mx.z), Vector3(mx.x, mn.y, mx.z),
		Vector3(mx.x, mx.y, mx.z), Vector3(mn.x, mx.y, mx.z), Vector3.BACK, side, tile, tint, glow)
	# -z (back)
	_quad(b, Vector3(mx.x, mn.y, mn.z), Vector3(mn.x, mn.y, mn.z),
		Vector3(mn.x, mx.y, mn.z), Vector3(mx.x, mx.y, mn.z), Vector3.FORWARD, side, tile, tint, glow)
	# +x
	_quad(b, Vector3(mx.x, mn.y, mx.z), Vector3(mx.x, mn.y, mn.z),
		Vector3(mx.x, mx.y, mn.z), Vector3(mx.x, mx.y, mx.z), Vector3.RIGHT, side, tile, tint, glow)
	# -x
	_quad(b, Vector3(mn.x, mn.y, mn.z), Vector3(mn.x, mn.y, mx.z),
		Vector3(mn.x, mx.y, mx.z), Vector3(mn.x, mx.y, mn.z), Vector3.LEFT, side, tile, tint, glow)
	# top
	_quad(b, Vector3(mn.x, mx.y, mx.z), Vector3(mx.x, mx.y, mx.z),
		Vector3(mx.x, mx.y, mn.z), Vector3(mn.x, mx.y, mn.z), Vector3.UP, cap, tile, tint, glow)


## A flat decal standing just off a wall (a door, a window, a sign board).
## `face` is the way it faces: +Z for a front wall, -X for the left flank. The
## corner order is chosen so the face winds towards `dir` whichever way it looks.
static func _decal(b: Dictionary, centre: Vector3, size: Vector2, face: Vector3,
		cell: Vector2, tint: Color, glow: float = 0.0) -> void:
	var right: Vector3
	if absf(face.z) > 0.5:
		right = Vector3(1.0, 0.0, 0.0) * signf(face.z)
	else:
		right = Vector3(0.0, 0.0, -1.0) * signf(face.x)
	var up := Vector3.UP
	var hw := right * (size.x * 0.5)
	var hh := up * (size.y * 0.5)
	_quad(b, centre - hw - hh, centre + hw - hh, centre + hw + hh, centre - hw + hh,
		face, cell, 0.0, tint, glow)


## Gable roof: two sloped faces, two triangular ends, a ridge cap. `ridge_axis`
## is "x" (the ridge runs along x, slopes face +z/-z) or "z".
##
## `inset` pulls the two triangular ENDS in from the roof's own edge, which is
## what a house needs: the roof overhangs the wall by 0.42 m, so a triangle drawn
## at the roof's edge would hang in mid-air. With `inset` the ends stand in the
## wall plane and carry the gable cell (plaster and crossed timbers); the sliver
## of roof past them reads as the soffit under the eaves.
static func _gable_roof(b: Dictionary, mn: Vector3, mx: Vector3, ridge_h: float,
		cell: Vector2, tile: float, tint: Color, axis: String = "x",
		inset: float = 0.0, end_cell: Vector2 = Vector2.ZERO) -> void:
	var rz := (mn.z + mx.z) * 0.5
	var rx := (mn.x + mx.x) * 0.5
	var ends: Vector2 = end_cell if end_cell != Vector2.ZERO else cell
	if axis == "x":
		# front slope (+z) and back slope (-z), both from the eaves up to the ridge
		_quad(b, Vector3(mn.x, mx.y, mx.z), Vector3(mx.x, mx.y, mx.z),
			Vector3(mx.x, ridge_h, rz), Vector3(mn.x, ridge_h, rz),
			Vector3(0.0, 1.0, 0.7).normalized(), cell, tile, tint)
		_quad(b, Vector3(mx.x, mx.y, mn.z), Vector3(mn.x, mx.y, mn.z),
			Vector3(mn.x, ridge_h, rz), Vector3(mx.x, ridge_h, rz),
			Vector3(0.0, 1.0, -0.7).normalized(), cell, tile, tint)
		# the gable ends: base on the wall (not on the eaves overhang), apex on the
		# ridge - a peak wider than its own house is the classic give-away
		_tri(b, Vector3(mn.x + inset, mx.y, mn.z + inset),
			Vector3(mn.x + inset, mx.y, mx.z - inset),
			Vector3(mn.x + inset, ridge_h, rz), Vector3.LEFT, ends, tile, tint)
		_tri(b, Vector3(mx.x - inset, mx.y, mx.z - inset),
			Vector3(mx.x - inset, mx.y, mn.z + inset),
			Vector3(mx.x - inset, ridge_h, rz), Vector3.RIGHT, ends, tile, tint)
		# ridge
		_box(b, Vector3(mn.x - 0.06, ridge_h - 0.08, rz - 0.1),
			Vector3(mx.x + 0.06, ridge_h + 0.06, rz + 0.1), cell, tile, tint)
	else:
		_quad(b, Vector3(mx.x, mx.y, mx.z), Vector3(mx.x, mx.y, mn.z),
			Vector3(rx, ridge_h, mn.z), Vector3(rx, ridge_h, mx.z),
			Vector3(0.7, 1.0, 0.0).normalized(), cell, tile, tint)
		_quad(b, Vector3(mn.x, mx.y, mn.z), Vector3(mn.x, mx.y, mx.z),
			Vector3(rx, ridge_h, mx.z), Vector3(rx, ridge_h, mn.z),
			Vector3(-0.7, 1.0, 0.0).normalized(), cell, tile, tint)
		_tri(b, Vector3(mn.x, mx.y, mx.z + inset), Vector3(mx.x, mx.y, mx.z + inset),
			Vector3(rx, ridge_h, mx.z + inset), Vector3.BACK, ends, tile, tint)
		_tri(b, Vector3(mx.x, mx.y, mn.z - inset), Vector3(mn.x, mx.y, mn.z - inset),
			Vector3(rx, ridge_h, mn.z - inset), Vector3.FORWARD, ends, tile, tint)
		_box(b, Vector3(rx - 0.1, ridge_h - 0.08, mn.z - 0.06),
			Vector3(rx + 0.1, ridge_h + 0.06, mx.z + 0.06), cell, tile, tint)


# ------------------------------------------------------------------ pieces ----
## The kit's parts, each one a named function so `describe()` can list them and
## the rules test can prove every part is actually reached by some building.
static func part_corner_post(b: Dictionary, x: float, z: float, y0: float, y1: float,
		cell: Vector2, tint: Color) -> void:
	_box(b, Vector3(x - 0.11, y0, z - 0.11), Vector3(x + 0.11, y1, z + 0.11),
		cell, 1.0, tint)


static func part_foundation(b: Dictionary, half_x: float, half_z: float, top_y: float,
		cells: Dictionary, tint: Color) -> void:
	box_foundation(b, Vector3(-half_x - 0.16, -FOOTING, -half_z - 0.16),
		Vector3(half_x + 0.16, top_y, half_z + 0.16), cells, tint)


## Exposed so a building can put a stone plinth anywhere (a tower's shaft step,
## a gate pier): one call, one texture, one tint.
static func box_foundation(b: Dictionary, mn: Vector3, mx: Vector3, cells: Dictionary,
		tint: Color) -> void:
	_box(b, mn, mx, cells.get("stone_pale", Vector2.ZERO), 2.0, tint)


static func part_chimney(b: Dictionary, x: float, z: float, y0: float, y1: float,
		cells: Dictionary, tint: Color) -> void:
	_box(b, Vector3(x - 0.28, y0, z - 0.28), Vector3(x + 0.28, y1, z + 0.28),
		cells.get("wall_stone", Vector2.ZERO), 1.4, tint)
	_box(b, Vector3(x - 0.36, y1, z - 0.36), Vector3(x + 0.36, y1 + 0.14, z + 0.36),
		cells.get("stone_pale", Vector2.ZERO), 1.0, tint)


static func part_window(b: Dictionary, x: float, y: float, z: float, face: Vector3,
		cells: Dictionary, tint: Color, w: float = 0.85, h: float = 0.85) -> void:
	_decal(b, Vector3(x, y, z), Vector2(w, h), face,
		cells.get("window", Vector2.ZERO), tint, 1.0)


## A closed ring of wall (the well's kerb, a tower's parapet): outer face, inner
## face and the rim on top. Eight sides is enough at the game's camera angle and
## costs 40 triangles rather than a cylinder's 200.
static func _ring(b: Dictionary, r_out: float, r_in: float, y0: float, y1: float,
		sides: int, cell: Vector2, tile: float, cap: Vector2, tint: Color) -> void:
	for i in range(sides):
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var o0 := Vector3(cos(a0) * r_out, 0.0, sin(a0) * r_out)
		var o1 := Vector3(cos(a1) * r_out, 0.0, sin(a1) * r_out)
		var in0 := Vector3(cos(a0) * r_in, 0.0, sin(a0) * r_in)
		var in1 := Vector3(cos(a1) * r_in, 0.0, sin(a1) * r_in)
		var mid := (o0 + o1) * 0.5
		var out_n := Vector3(mid.x, 0.0, mid.z).normalized()
		var down := Vector3(0.0, y0, 0.0)
		var up := Vector3(0.0, y1, 0.0)
		_quad(b, o0 + down, o1 + down, o1 + up, o0 + up, out_n, cell, tile, tint)
		_quad(b, in1 + down, in0 + down, in0 + up, in1 + up, -out_n, cell, tile, tint)
		_quad(b, in0 + up, in1 + up, o1 + up, o0 + up, Vector3.UP, cap, tile, tint)


# ------------------------------------------------------------------ cottage ---
static func _cottage(b: Dictionary, cells: Dictionary, variant: int, tint: Color) -> float:
	var hx := 2.8
	var hz := 2.1
	var plinth := 0.35
	var wall_top := plinth + 2.6
	part_foundation(b, hx, hz, plinth + 0.02, cells, tint)
	# ground floor: plaster between timbers, two metres to a repeat of the cell
	_box(b, Vector3(-hx, plinth, -hz), Vector3(hx, wall_top, hz),
		cells.get("wall_timber", Vector2.ZERO), 2.0, tint)
	var eave := wall_top
	if variant == 1:
		# jettied upper floor in dark boards, overhanging its own street: the
		# way a real timber-framed house grows a second storey
		_box(b, Vector3(-hx - 0.24, wall_top, -hz - 0.2),
			Vector3(hx + 0.24, wall_top + 1.15, hz + 0.2),
			cells.get("wall_wood", Vector2.ZERO), 1.6, tint)
		eave = wall_top + 1.15
		for sx in [-1.0, 1.0]:
			part_corner_post(b, (hx + 0.24) * sx, 0.0, wall_top, eave,
				cells.get("beam", Vector2.ZERO), tint)
	var top := eave
	var ridge := top + 1.9
	# corner posts on the ground floor
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			part_corner_post(b, hx * sx, hz * sz, plinth, wall_top, cells.get("beam", Vector2.ZERO), tint)
	# door and windows on the front, one window on each flank and the back
	_decal(b, Vector3(-0.75, plinth + 1.1, hz + 0.03), Vector2(1.1, 2.2), Vector3.BACK,
		cells.get("door", Vector2.ZERO), tint, DETAIL)
	part_window(b, 1.05, 1.95, hz + 0.03, Vector3.BACK, cells, tint)
	part_window(b, 2.0, 1.95, hz + 0.03, Vector3.BACK, cells, tint, 0.7, 0.7)
	part_window(b, hx + 0.03, 1.95, 0.15, Vector3.RIGHT, cells, tint)
	part_window(b, -hx - 0.03, 1.95, -0.15, Vector3.LEFT, cells, tint)
	part_window(b, -0.5, 1.95, -hz - 0.03, Vector3.FORWARD, cells, tint)
	# roof: thatch on the first and third variant, shingles on the second
	var roof_cell: Vector2 = cells.get("roof_thatch", Vector2.ZERO)
	if variant == 1:
		roof_cell = cells.get("roof_shingle", Vector2.ZERO)
	_gable_roof(b, Vector3(-hx - 0.42, eave, -hz - 0.42), Vector3(hx + 0.42, eave, hz + 0.42),
		ridge, roof_cell, 1.2, tint, "x", 0.42, cells.get("gable", Vector2.ZERO))
	# the beam under the eaves on both long walls
	for sz in [-1.0, 1.0]:
		_box(b, Vector3(-hx - 0.3, eave - 0.18, hz * sz - 0.09),
			Vector3(hx + 0.3, eave + 0.02, hz * sz + 0.09),
			cells.get("beam", Vector2.ZERO), 1.0, tint)
	var tallest := ridge
	if variant != 0:
		part_chimney(b, hx - 0.8, 0.35, ridge - 0.9, ridge + 0.35, cells, tint)
		tallest = ridge + 0.49
	if variant == 2:
		# a lean-to shed on the left flank: the cheapest variation in the kit,
		# and the one that makes the row of houses read as a lived-in village
		_box(b, Vector3(-hx - 1.55, plinth, -1.15), Vector3(-hx, 1.85, 1.15),
			cells.get("wall_wood", Vector2.ZERO), 1.6, tint)
		for sz in [-1.0, 1.0]:
			part_corner_post(b, -hx - 1.55, 1.15 * sz, plinth, 1.85,
				cells.get("beam", Vector2.ZERO), tint)
		_gable_roof(b, Vector3(-hx - 1.72, 1.85, -1.35), Vector3(-hx + 0.12, 1.85, 1.35),
			2.55, roof_cell, 1.2, tint, "z")
		part_window(b, -hx - 1.58, 1.25, 0.0, Vector3.LEFT, cells, tint, 0.55, 0.55)
	return tallest


# -------------------------------------------------------------------- tower ---
static func _tower(b: Dictionary, cells: Dictionary, variant: int, tint: Color) -> float:
	var hx := 1.9
	var shaft_top := 7.4
	box_foundation(b, Vector3(-hx - 0.32, -FOOTING, -hx - 0.32),
		Vector3(hx + 0.32, 0.55, hx + 0.32), cells, tint)
	_box(b, Vector3(-hx, 0.55, -hx), Vector3(hx, 4.5, hx),
		cells.get("wall_stone", Vector2.ZERO), 2.0, tint)
	# the shaft steps in above the door storey
	_box(b, Vector3(-hx + 0.22, 4.5, -hx + 0.22), Vector3(hx - 0.22, shaft_top, hx - 0.22),
		cells.get("wall_stone", Vector2.ZERO), 2.0, tint)
	# corbels carrying the hoarding
	for i in range(12):
		var ang := TAU * float(i) / 12.0
		var px := cos(ang) * (hx - 0.1)
		var pz := sin(ang) * (hx - 0.1)
		_box(b, Vector3(px - 0.13, shaft_top - 0.55, pz - 0.13),
			Vector3(px + 0.13, shaft_top, pz + 0.13), cells.get("beam", Vector2.ZERO), 1.0, tint)
	# timber hoarding, then the stone parapet on top of it
	_box(b, Vector3(-hx - 0.45, shaft_top, -hx - 0.45), Vector3(hx + 0.45, shaft_top + 1.0, hx + 0.45),
		cells.get("wall_wood", Vector2.ZERO), 1.6, tint)
	_box(b, Vector3(-hx - 0.45, shaft_top + 1.0, -hx - 0.45),
		Vector3(hx + 0.45, shaft_top + 1.35, hx + 0.45),
		cells.get("stone_pale", Vector2.ZERO), 1.6, tint)
	# merlons round the parapet: four a side, corners first
	var m := hx + 0.32
	var k := -m
	while k <= m + 0.01:
		for pair in [[k, -m], [k, m], [-m, k], [m, k]]:
			var bx: float = pair[0]
			var bz: float = pair[1]
			_box(b, Vector3(bx - 0.17, shaft_top + 1.35, bz - 0.17),
				Vector3(bx + 0.17, shaft_top + 1.8, bz + 0.17),
				cells.get("stone_pale", Vector2.ZERO), 1.2, tint)
		k += 0.92
	var top := shaft_top + 1.8
	if variant == 1:
		# conical slate roof with a pole and the traveller's pennant
		var apothem := hx + 0.5
		var peak := Vector3(0.0, top + 2.7, 0.0)
		var sides := 8
		for i in range(sides):
			var a0 := TAU * float(i) / float(sides)
			var a1 := TAU * float(i + 1) / float(sides)
			var p0 := Vector3(cos(a0) * apothem, top, sin(a0) * apothem)
			var p1 := Vector3(cos(a1) * apothem, top, sin(a1) * apothem)
			var mid := (p0 + p1) * 0.5
			var n := Vector3(mid.x, 1.4, mid.z).normalized()
			_tri(b, p0, p1, peak, n, cells.get("roof_dark", Vector2.ZERO), 1.2, tint)
		top = peak.y
		_box(b, Vector3(-0.05, top, -0.05), Vector3(0.05, top + 1.4, 0.05),
			cells.get("beam", Vector2.ZERO), 1.0, tint)
		var bcell: Vector2 = cells.get("banner", Vector2.ZERO)
		_quad(b, Vector3(0.06, top + 1.35, 0.0), Vector3(0.06, top + 1.35, 1.2),
			Vector3(0.06, top + 0.25, 1.2), Vector3(0.06, top + 0.25, 0.0),
			Vector3.RIGHT, bcell, 0.0, tint, DETAIL)
		_quad(b, Vector3(0.04, top + 1.35, 0.0), Vector3(0.04, top + 0.25, 0.0),
			Vector3(0.04, top + 0.25, 1.2), Vector3(0.04, top + 1.35, 1.2),
			Vector3.LEFT, bcell, 0.0, tint, DETAIL)
		top += 1.4
	# door at the foot, windows up the shaft
	_decal(b, Vector3(0.0, 1.65, hx + 0.03), Vector2(1.1, 2.2), Vector3.BACK,
		cells.get("door", Vector2.ZERO), tint, DETAIL)
	part_window(b, 0.0, 3.5, hx + 0.03, Vector3.BACK, cells, tint, 0.62, 0.8)
	part_window(b, 0.0, 5.8, hx - 0.19, Vector3.BACK, cells, tint, 0.62, 0.8)
	part_window(b, hx + 0.03, 3.5, 0.0, Vector3.RIGHT, cells, tint, 0.62, 0.8)
	part_window(b, -hx - 0.03, 3.5, 0.0, Vector3.LEFT, cells, tint, 0.62, 0.8)
	return top


# -------------------------------------------------------------------- gate ----
static func _gate(b: Dictionary, cells: Dictionary, tint: Color) -> float:
	var pier := 1.3
	var depth := 1.4
	var h := 4.2
	for sx in [-1.0, 1.0]:
		box_foundation(b, Vector3(sx * 1.55 - pier * 0.5, -FOOTING, -depth * 0.5),
			Vector3(sx * 1.55 + pier * 0.5, 0.4, depth * 0.5), cells, tint)
		_box(b, Vector3(sx * 1.55 - pier * 0.5, 0.4, -depth * 0.5),
			Vector3(sx * 1.55 + pier * 0.5, h, depth * 0.5),
			cells.get("wall_stone", Vector2.ZERO), 2.0, tint)
		# merlons on each pier
		for k in range(2):
			var cx := sx * 1.55 - 0.5 + float(k) * 0.55
			_box(b, Vector3(cx, h, -depth * 0.5), Vector3(cx + 0.3, h + 0.55, depth * 0.5),
				cells.get("stone_pale", Vector2.ZERO), 1.2, tint)
	# lintel beam across the opening
	_box(b, Vector3(-2.25, 3.5, -depth * 0.35), Vector3(2.25, 4.0, depth * 0.35),
		cells.get("beam", Vector2.ZERO), 1.0, tint)
	# two closed leaves, drawn on both faces so the gate reads from the road and
	# from inside the village
	for sx in [-1.0, 1.0]:
		_decal(b, Vector3(sx * 0.48, 1.75, 0.12), Vector2(0.94, 3.5), Vector3.BACK,
			cells.get("door", Vector2.ZERO), tint, DETAIL)
		_decal(b, Vector3(sx * 0.48, 1.75, -0.12), Vector2(0.94, 3.5), Vector3.FORWARD,
			cells.get("door", Vector2.ZERO), tint, DETAIL)
		for by in [1.25, 2.55]:
			for facing in [0.14, -0.14]:
				_box(b, Vector3(sx * 0.48 - 0.55, by, facing - 0.035),
					Vector3(sx * 0.48 + 0.55, by + 0.13, facing + 0.035),
					cells.get("iron", Vector2.ZERO), 0.8, tint)
	# a shingled hood over the lintel
	_gable_roof(b, Vector3(-2.45, 4.0, -depth * 0.6), Vector3(2.45, 4.0, depth * 0.6),
		4.95, cells.get("roof_shingle", Vector2.ZERO), 1.2, tint, "x")
	return 4.95


# -------------------------------------------------------------------- well ----
static func _well(b: Dictionary, cells: Dictionary, tint: Color) -> float:
	var h := 1.0
	var kerb: Vector2 = cells.get("wall_stone", Vector2.ZERO)
	var cope: Vector2 = cells.get("stone_pale", Vector2.ZERO)
	_ring(b, 1.05, 0.78, -0.45, h, 8, kerb, 1.4, kerb, tint)
	_ring(b, 1.18, 0.7, h, h + 0.18, 8, cope, 1.2, cope, tint)
	# the water down the shaft, kept under the coping so no light leaks out
	_box(b, Vector3(-0.72, h - 0.42, -0.72), Vector3(0.72, h - 0.36, 0.72),
		cells.get("floor_stone", Vector2.ZERO), 2.0, Color(0.24, 0.3, 0.34) * tint)
	# two posts and a thatched hood over the mouth
	for sx in [-1.0, 1.0]:
		_box(b, Vector3(sx * 0.88 - 0.08, h + 0.18, -0.08), Vector3(sx * 0.88 + 0.08, 2.55, 0.08),
			cells.get("beam", Vector2.ZERO), 1.0, tint)
	_box(b, Vector3(-0.96, 2.35, -0.07), Vector3(0.96, 2.47, 0.07),
		cells.get("beam", Vector2.ZERO), 1.0, tint)
	_gable_roof(b, Vector3(-1.18, 2.55, -0.78), Vector3(1.18, 2.55, 0.78), 3.25,
		cells.get("roof_thatch", Vector2.ZERO), 1.2, tint, "x")
	# bucket on its rope
	_box(b, Vector3(-0.17, 1.55, -0.17), Vector3(0.17, 1.92, 0.17),
		cells.get("plank_light", Vector2.ZERO), 0.8, tint)
	_box(b, Vector3(-0.02, 1.92, -0.02), Vector3(0.02, 2.35, 0.02),
		cells.get("iron", Vector2.ZERO), 0.8, tint)
	return 3.25


# -------------------------------------------------------------------- dock ----
static func _dock(b: Dictionary, cells: Dictionary, tint: Color) -> float:
	var hx := 2.4
	var hz := 1.2
	var deck := 0.42
	var plank: Vector2 = cells.get("plank_light", Vector2.ZERO)
	_box(b, Vector3(-hx, deck, -hz), Vector3(hx, deck + 0.2, hz), plank, 1.2, tint, plank)
	# piles standing in the water
	for px in [-hx + 0.22, -0.7, 0.7, hx - 0.22]:
		for pz in [-hz + 0.18, hz - 0.18]:
			_box(b, Vector3(px - 0.1, -1.6, pz - 0.1), Vector3(px + 0.1, deck, pz + 0.1),
				cells.get("beam", Vector2.ZERO), 1.0, tint)
	# bollards and a rope rail on the water side
	for px in [-hx + 0.5, 0.0, hx - 0.5]:
		_box(b, Vector3(px - 0.09, deck + 0.2, hz - 0.24), Vector3(px + 0.09, deck + 0.85, hz - 0.06),
			cells.get("beam", Vector2.ZERO), 1.0, tint)
	_box(b, Vector3(-hx + 0.5, deck + 0.7, hz - 0.18), Vector3(hx - 0.5, deck + 0.78, hz - 0.12),
		plank, 0.6, tint)
	# a mooring cleat at the far end, and a crate waiting for the boat
	_box(b, Vector3(-hx + 0.3, deck + 0.2, -hz + 0.3), Vector3(-hx + 0.66, deck + 0.44, -hz + 0.5),
		cells.get("iron", Vector2.ZERO), 0.8, tint)
	_box(b, Vector3(hx - 1.0, deck + 0.2, -hz + 0.25), Vector3(hx - 0.5, deck + 0.7, -hz + 0.72),
		plank, 0.9, tint)
	return deck + 0.85


# -------------------------------------------------------------------- sign ----
static func _sign(b: Dictionary, cells: Dictionary, variant: int, tint: Color) -> float:
	_box(b, Vector3(-0.07, -0.5, -0.07), Vector3(0.07, 2.0, 0.07),
		cells.get("beam", Vector2.ZERO), 1.0, tint)
	var board: Vector2 = cells.get("plank_light", Vector2.ZERO)
	for face in [Vector3.BACK, Vector3.FORWARD]:
		_decal(b, Vector3(0.0, 1.55, 0.09 * face.z), Vector2(1.05, 0.62), face, board, tint, DETAIL)
	_box(b, Vector3(-0.55, 1.86, -0.06), Vector3(0.55, 1.92, 0.06),
		cells.get("beam", Vector2.ZERO), 1.0, tint)
	if variant == 1:
		_gable_roof(b, Vector3(-0.64, 1.92, -0.24), Vector3(0.64, 1.92, 0.24), 2.2,
			cells.get("roof_shingle", Vector2.ZERO), 1.2, tint, "x")
	return 2.2 if variant == 1 else 2.0


# ------------------------------------------------------------------- torch ----
static func _torch(b: Dictionary, cells: Dictionary, tint: Color) -> float:
	_box(b, Vector3(-0.07, -0.4, -0.07), Vector3(0.07, 1.95, 0.07),
		cells.get("beam", Vector2.ZERO), 1.0, tint)
	_box(b, Vector3(-0.14, 1.95, -0.14), Vector3(0.14, 2.15, 0.14),
		cells.get("iron", Vector2.ZERO), 0.8, tint)
	# the flame: two crossed quads, four animation frames in one cell
	var flame: Vector2 = cells.get("flame", Vector2.ZERO)
	_decal(b, Vector3(0.0, 2.5, 0.0), Vector2(0.62, 0.88), Vector3.BACK, flame, tint, LIT)
	_decal(b, Vector3(0.0, 2.5, 0.0), Vector2(0.62, 0.88), Vector3.RIGHT, flame, tint, LIT)
	return 2.94


# --------------------------------------------------------------------- api ----
## Meshes are built once per (kind, variant) and reused: the village's five
## cottages are three shapes between them. Building them at load rather than
## shipping .glb files keeps ONE source of truth - the kit below - and means a
## tweak to a roof cannot drift out of sync with a file nobody regenerated.
static var _cache := {}


## Build one building, white, ready to be shaded per instance. Returns
##   {arrays, mesh, top, block, animate, verts, tris}
## `arrays` is the raw buffer (the test inspects it), `mesh` the ArrayMesh,
## `top` the height of the highest point for the occlusion box, `block` the
## collision radius (the same numbers RegionData uses) and `animate` marks the
## torches, whose flame slides through four frames.
static func build(kind: String, variant: int, meta: Dictionary) -> Dictionary:
	var key := "%s|%d" % [kind, variant]
	if _cache.has(key):
		return _cache[key]
	var made := build_tinted(kind, variant, meta, Color.WHITE)
	if not made.is_empty():
		_cache[key] = made
	return made


## Same, with the tint baked into the vertex colours. Only for a stand-alone
## MeshInstance3D (the test scene and the lighthouse on the world map); the
## region tints per instance instead, so all five cottages share one mesh.
static func build_tinted(kind: String, variant: int, meta: Dictionary, tint: Color,
		scale: float = 1.0) -> Dictionary:
	var cell_map := cells(meta)
	if cell_map.is_empty():
		return {}
	var b := _buf()
	var top := 0.0
	match kind:
		"cottage":
			top = _cottage(b, cell_map, variant % 3, tint)
		"tower":
			top = _tower(b, cell_map, variant % 2, tint)
		"gate":
			top = _gate(b, cell_map, tint)
		"well":
			top = _well(b, cell_map, tint)
		"dock":
			top = _dock(b, cell_map, tint)
		"sign":
			top = _sign(b, cell_map, variant % 2, tint)
		"torch":
			top = _torch(b, cell_map, tint)
		_:
			return {}
	var kk: Dictionary = kinds(meta).get(kind, {})
	var verts: PackedVector3Array = b["verts"]
	if not is_equal_approx(scale, 1.0):
		for i in range(verts.size()):
			verts[i] = verts[i] * scale
		b["verts"] = verts
		top *= scale
	var index: PackedInt32Array = b["index"]
	return {
		"arrays": b,
		"mesh": mesh_from(b),
		"top": top,
		"block": float(kk.get("block_radius", 0.0)) * scale,
		"animate": kind == "torch",
		"kind": kind,
		"variant": variant,
		"verts": verts.size(),
		"tris": index.size() / 3,
	}


static func mesh_from(arrays: Dictionary) -> ArrayMesh:
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = arrays["verts"]
	out[Mesh.ARRAY_NORMAL] = arrays["norms"]
	out[Mesh.ARRAY_TEX_UV] = arrays["uvs"]
	out[Mesh.ARRAY_TEX_UV2] = arrays["uv2s"]
	out[Mesh.ARRAY_COLOR] = arrays["colors"]
	out[Mesh.ARRAY_INDEX] = arrays["index"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return mesh


## The smallest and largest point of a built mesh, so the test can prove the
## building really is as tall as the kit claims and stands on y = 0.
static func bounds_of(arrays: Dictionary) -> AABB:
	var verts: PackedVector3Array = arrays["verts"]
	if verts.is_empty():
		return AABB()
	var mn := verts[0]
	var mx := verts[0]
	for v in verts:
		mn = Vector3(minf(mn.x, v.x), minf(mn.y, v.y), minf(mn.z, v.z))
		mx = Vector3(maxf(mx.x, v.x), maxf(mx.y, v.y), maxf(mx.z, v.z))
	return AABB(mn, mx - mn)


## Every building kind the kit can assemble, for the rules test and the report.
static func known_kinds(meta: Dictionary) -> Array:
	var out: Array = []
	for k in kinds(meta).keys():
		out.append(String(k))
	out.sort()
	return out


## Which parts a kind is assembled from. Printed by the BuildingTest so the
## report can list the kit honestly instead of describing it from memory.
static func parts_of(kind: String) -> Array:
	match kind:
		"cottage":
			return ["fondasi batu", "dinding plester + rangka kayu", "tiang sudut x4",
				"pintu", "jendela x4 (menyala malam)", "atap jerami / papan",
				"balok lis", "cerobong", "serambi (varian 2)", "loteng jongkok (varian 1)"]
		"tower":
			return ["fondasi batu", "batang batu bertingkat", "konsol kayu x12",
				"geladak kayu", "parapet batu", "merlon", "atap kerucut batu tulis (varian 1)",
				"tiang + panji", "pintu", "jendela x3"]
		"gate":
			return ["tiang batu x2", "merlon", "balok lintel", "daun pintu x2",
				"atap sirap", "pita besi"]
		"well":
			return ["kerb batu 8 sisi", "penutup batu", "air gelap", "tiang x2",
				"palang", "atap jerami", "timba", "tali"]
		"dock":
			return ["geladak papan", "tiang pancang x8", "bollard x3", "tali",
				"cleat besi", "peti"]
		"sign":
			return ["tiang", "papan (dua sisi)", "palang", "atap sirap (varian 1)"]
		"torch":
			return ["tiang", "keranjang besi", "nyala (4 bingkai, dua bidang)"]
	return []


# ------------------------------------------------------ instance wrapper ----
## The region loads this script from a path at runtime and calls through one
## instance. That is not laziness: a script resource is an Object, and reaching a
## STATIC function through it is not a guaranteed path in GDScript, while a plain
## instance method always is. The cache is static, so the shared meshes survive
## across instances - and there is only ever one region open.
func kit_meta() -> Dictionary:
	return load_meta()


func make(kind: String, variant: int, meta: Dictionary) -> Dictionary:
	return build(kind, variant, meta)


func cells_of(meta: Dictionary) -> Dictionary:
	return cells(meta)


func make_tinted(kind: String, variant: int, meta: Dictionary, tint: Color) -> Dictionary:
	return build_tinted(kind, variant, meta, tint)


## Room a building takes on the map, in metres, and how tall it stands.
func size_of(kind: String, meta: Dictionary) -> Vector3:
	var kk: Dictionary = kinds(meta).get(kind, {})
	if kk.is_empty():
		return Vector3(2.0, 2.0, 2.0)
	return Vector3(float(kk.get("w", 2.0)), float(kk.get("h", 2.0)), float(kk.get("d", 2.0)))


func variant_count(kind: String, meta: Dictionary) -> int:
	var kk: Dictionary = kinds(meta).get(kind, {})
	return maxi(1, int(kk.get("variants", 1)))


## Every element the kit draws, so a test can prove the atlas really has the
## cell each one asks for (a typo in a cell name yields an invisible building).
static func required_cells() -> Array:
	return ["wall_timber", "wall_wood", "wall_stone", "roof_shingle", "roof_thatch",
		"floor_stone", "window", "door", "beam", "gable", "plank_light", "iron",
		"banner", "stone_pale", "roof_dark", "flame"]
