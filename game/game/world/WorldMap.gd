extends RefCounted
## The ground as DATA: a grid of terrain tiles, the places of interest on it, and
## which of those tiles the player has already seen.
##
## Why a grid at all: the minimap must be drawn from the map, not from a second
## camera. A second viewport costs a full extra render pass on a phone; a
## 26x20 byte grid costs nothing and can be turned into a small texture on the
## CPU in one go (and only when the player changes tile).
##
## Nothing here knows about meshes, sprites or the diorama. `Diorama.gd` paints
## this grid from the layout it already owns, `Minimap.gd` reads it, and the
## camera asks it for its outer fence. When step 2 adds tiered terrain, this is
## the interface it grows behind - the minimap does not need to change.
##
## No `class_name`: the game runs inside the launcher's project (see
## WorldArt.gd for the long version).

## Terrain kinds. Small numbers on purpose: they become the red/green/blue bytes
## of the minimap texture, so the palette lives next to them.
const KIND_GRASS := 0
const KIND_DIRT := 1
const KIND_WATER := 2
const KIND_ROCK := 3
const KIND_FOREST := 4
const KIND_BUILDING := 5
## Step 2 grew the palette when the region arrived: a tiered map needs to show
## how deep the water is, and the stone plateau and snow caps are not rock.
const KIND_DEEP := 6
const KIND_STONE := 7
const KIND_SNOW := 8
const KIND_SAND := 9

## Warm fantasy palette, matched to the game's parchment and to the diorama's
## grass/dirt textures. No blue neon, no saturated cyan "water" - the pond reads
## as slate green because that is what water looks like at dusk in this valley.
const PALETTE := {
	KIND_GRASS: Color(0.35, 0.42, 0.25),
	KIND_DIRT: Color(0.61, 0.48, 0.31),
	KIND_WATER: Color(0.28, 0.40, 0.43),
	KIND_ROCK: Color(0.44, 0.40, 0.35),
	KIND_FOREST: Color(0.19, 0.27, 0.17),
	KIND_BUILDING: Color(0.53, 0.35, 0.25),
	KIND_DEEP: Color(0.20, 0.31, 0.36),
	KIND_STONE: Color(0.55, 0.52, 0.46),
	KIND_SNOW: Color(0.78, 0.82, 0.82),
	KIND_SAND: Color(0.72, 0.64, 0.47),
}
const UNEXPLORED := Color(0.11, 0.09, 0.07)
## How much of the colour survives in a tile that is remembered but out of the
## player's current sight: the map reads as "seen", not as "bright as daylight".
const SEEN_DIM := 0.45

## Kinds the knight may stand on. Forest is walkable ground with trees on it (the
## prop footprints do the real blocking), water, bare rock and buildings are not.
const WALKABLE := [KIND_GRASS, KIND_DIRT, KIND_FOREST, KIND_STONE, KIND_SNOW,
	KIND_SAND, KIND_ROCK]

const FOG_KEY := "fog"
const FOG_SCHEMA := 1

var width := 0
var height := 0
## Metres per tile. The valley uses 1 m; a country-sized region can use 2 or 4
## and nothing here needs to change - only the texture gets coarser.
var cell := 1.0
## World XZ of the CENTRE of tile (0, 0).
var origin := Vector2.ZERO
var label := ""
## Places of interest: {kind: "door"|"pickup"|"quest"|"npc", label: String,
## pos: Vector2 (world XZ), radius: float}.
var pois: Array = []

var _tiles := PackedByteArray()
var _fog := PackedByteArray()
var _explored := 0
## Bumped every time a new tile is revealed. The minimap rebuilds its texture
## only when this number changes - that is how "update on tile change, not every
## frame" is enforced in one place instead of in every caller.
var fog_revision := 0
## Default sight radius in metres. Wide enough that walking does not feel like
## scratching the dark off with a fingernail, small enough that the forest is
## still unknown when the player starts.
var sight_m := 5.0


## Size the grid, then start in the dark. `world_origin` is the centre of tile
## (0,0), i.e. the map's top-left corner in world XZ; passing the ground rect's
## position is the usual call.
func setup(w: int, h: int, metres_per_tile: float = 1.0, world_origin: Vector2 = Vector2.ZERO) -> void:
	width = maxi(0, w)
	height = maxi(0, h)
	cell = maxf(0.05, metres_per_tile)
	origin = world_origin
	_tiles = PackedByteArray()
	_tiles.resize(width * height)
	_tiles.fill(KIND_GRASS)
	_fog = PackedByteArray()
	_fog.resize(width * height)
	_fog.fill(0)
	_explored = 0
	fog_revision += 1


func is_ready() -> bool:
	return width > 0 and height > 0 and _tiles.size() == width * height


func fill(kind: int) -> void:
	if not is_ready():
		return
	_tiles.fill(kind)


func in_bounds(tx: int, tz: int) -> bool:
	return tx >= 0 and tz >= 0 and tx < width and tz < height


func set_tile(tx: int, tz: int, kind: int) -> void:
	if not in_bounds(tx, tz):
		return
	_tiles[tz * width + tx] = kind


func tile_at(tx: int, tz: int) -> int:
	if not in_bounds(tx, tz):
		return KIND_GRASS
	return _tiles[tz * width + tx]


## World XZ -> tile. Written as floor((pos - corner) / cell) so a tile's fraction
## is consistent with `tile_centre` (which is what the minimap reads back).
func world_to_tile(pos: Vector2) -> Vector2i:
	if width == 0 or height == 0:
		return Vector2i.ZERO
	var corner := origin - Vector2(width, height) * cell * 0.5
	return Vector2i(
		int(floor((pos.x - corner.x) / cell)),
		int(floor((pos.y - corner.y) / cell)))


func tile_centre(tx: int, tz: int) -> Vector2:
	var corner := origin - Vector2(width, height) * cell * 0.5
	return corner + (Vector2(tx, tz) + Vector2(0.5, 0.5)) * cell


## Outer fence of the map in world XZ.
func bounds() -> Rect2:
	if width == 0 or height == 0:
		return Rect2()
	var size := Vector2(width, height) * cell
	return Rect2(origin - size * 0.5, size)


func walkable_at(world: Vector2) -> bool:
	var t := world_to_tile(world)
	if not in_bounds(t.x, t.y):
		return false
	return WALKABLE.has(tile_at(t.x, t.y))


# ------------------------------------------------------------------ painting --
## Paint every tile whose centre lies within `radius_m` of `at`.
func paint_disc(at: Vector2, radius_m: float, kind: int) -> void:
	if not is_ready():
		return
	var r := maxf(0.0, radius_m)
	var t := world_to_tile(at)
	var span := int(ceil(r / cell))
	for dz in range(-span - 1, span + 2):
		for dx in range(-span - 1, span + 2):
			var tx := t.x + dx
			var tz := t.y + dz
			if not in_bounds(tx, tz):
				continue
			if tile_centre(tx, tz).distance_to(at) <= r:
				set_tile(tx, tz, kind)


## Paint a road between two points: a disc swept along the segment.
func paint_line(a: Vector2, b: Vector2, radius_m: float, kind: int) -> void:
	if not is_ready():
		return
	var span_m := a.distance_to(b)
	var steps := maxi(1, int(ceil(span_m / maxf(0.2, cell * 0.5))))
	for i in range(steps + 1):
		paint_disc(a.lerp(b, float(i) / float(steps)), radius_m, kind)


func add_poi(kind: String, label_text: String, pos: Vector2, radius: float = 2.5) -> void:
	pois.append({"kind": kind, "label": label_text, "pos": pos, "radius": radius})


func pois_of(kind: String) -> Array:
	var out: Array = []
	for p in pois:
		var e: Dictionary = p
		if String(e.get("kind", "")) == kind:
			out.append(e)
	return out


# ---------------------------------------------------------------------- fog --
## Open the map around `at`. Returns true when at least one tile is new, which is
## the only moment the minimap texture has to be rebuilt.
func reveal(at: Vector2, radius_m: float = -1.0) -> bool:
	if not is_ready():
		return false
	var r := sight_m if radius_m < 0.0 else maxf(0.0, radius_m)
	var t := world_to_tile(at)
	var span := int(ceil(r / cell))
	var fresh := false
	for dz in range(-span - 1, span + 2):
		for dx in range(-span - 1, span + 2):
			var tx := t.x + dx
			var tz := t.y + dz
			if not in_bounds(tx, tz):
				continue
			var idx := tz * width + tx
			if _fog[idx] != 0:
				continue
			if tile_centre(tx, tz).distance_to(at) > r:
				continue
			_fog[idx] = 1
			_explored += 1
			fresh = true
	if fresh:
		fog_revision += 1
	return fresh


func reveal_all() -> void:
	if not is_ready():
		return
	_fog.fill(1)
	_explored = width * height
	fog_revision += 1


func explored(tx: int, tz: int) -> bool:
	if not in_bounds(tx, tz):
		return false
	return _fog[tz * width + tx] != 0


func explored_count() -> int:
	return _explored


func explored_ratio() -> float:
	if width * height == 0:
		return 0.0
	return float(_explored) / float(width * height)


## Fog as a compact string, row by row. 26x20 is 520 characters; a 200x120 region
## is 24 000, still smaller than the rounded JSON a list of indices would need.
func fog_bits() -> String:
	if not is_ready():
		return ""
	var out := PackedStringArray()
	out.resize(_fog.size())
	for i in range(_fog.size()):
		out[i] = "1" if _fog[i] != 0 else "0"
	return "".join(out)


## Versioned fog blob for the save file. `schema` and the size travel with the
## bits so a save written on a bigger map is not smeared onto a smaller one.
func fog_payload() -> Dictionary:
	return {
		"schema": FOG_SCHEMA,
		"map": label,
		"w": width,
		"h": height,
		"cell": cell,
		"bits": fog_bits(),
	}


## Returns "" when the blob fits this map, or a short reason when it does not
## (a different map or size: the player simply starts with no explored ground,
## which is what an older save looks like too).
func load_fog(payload: Dictionary) -> String:
	if payload.is_empty():
		return "kosong"
	var schema := int(payload.get("schema", 0))
	if schema > FOG_SCHEMA:
		return "fog dari versi lebih baru"
	var w := int(payload.get("w", 0))
	var h := int(payload.get("h", 0))
	if w != width or h != height:
		return "ukuran peta berbeda (%dx%d vs %dx%d)" % [w, h, width, height]
	var bits := String(payload.get("bits", ""))
	if bits.length() != width * height:
		return "jumlah ubin tidak cocok"
	_fog = PackedByteArray()
	_fog.resize(width * height)
	_explored = 0
	for i in range(width * height):
		var on := bits[i] == "1"
		_fog[i] = 1 if on else 0
		if on:
			_explored += 1
	fog_revision += 1
	return ""


# ------------------------------------------------------------------ texture --
## Colour of one tile, fog included. The single place that decides what the map
## looks like, so the minimap and the full map can never disagree.
func tile_colour(tx: int, tz: int) -> Color:
	if not in_bounds(tx, tz):
		return UNEXPLORED
	var idx := tz * width + tx
	if _fog[idx] == 0:
		return UNEXPLORED
	var base: Color = PALETTE.get(_tiles[idx], PALETTE[KIND_GRASS])
	if not _in_current_sight(tx, tz):
		return base.darkened(1.0 - SEEN_DIM)
	return base


## The whole map as an Image, `scale` pixels per tile. Used by the full map
## panel, which is opened on purpose and can afford one build.
func render_image(scale: int = 4) -> Image:
	if not is_ready():
		return Image.create(1, 1, false, Image.FORMAT_RGBA8)
	var s := maxi(1, scale)
	var img := Image.create(width * s, height * s, false, Image.FORMAT_RGBA8)
	for tz in range(height):
		for tx in range(width):
			var c := tile_colour(tx, tz)
			img.fill_rect(Rect2i(tx * s, tz * s, s, s), c)
	return img


## A square window of tiles around `centre`, `tiles` across, `scale` pixels per
## tile. The minimap only ever asks for a bounded window, so the cost of its
## texture is the same on a 26x20 valley and on a 200x120 region.
func render_window(centre: Vector2i, tiles: int, scale: int = 4) -> Image:
	var s := maxi(1, scale)
	var n := maxi(1, tiles)
	var img := Image.create(n * s, n * s, false, Image.FORMAT_RGBA8)
	img.fill(UNEXPLORED)
	var half := n / 2
	for row in range(n):
		for col in range(n):
			var tx := centre.x - half + col
			var tz := centre.y - half + row
			if not in_bounds(tx, tz):
				continue
			img.fill_rect(Rect2i(col * s, row * s, s, s), tile_colour(tx, tz))
	return img


## Tile at the centre of a `tiles`-wide window, plus the fraction into that tile,
## so the minimap can slide by sub-tile amounts instead of jumping a whole tile.
func window_offset(centre: Vector2, tiles: int) -> Vector2:
	var t := world_to_tile(centre)
	var c := tile_centre(t.x, t.y)
	var frac := Vector2((centre.x - c.x) / cell, (centre.y - c.y) / cell)
	return frac


## Pixels per tile chosen so the whole map stays inside a phone-friendly
## texture: a 26x20 valley gets 8 px/tile, a 200x120 region gets 2.
func texture_scale(max_side: int = 320) -> int:
	if width == 0 or height == 0:
		return 1
	var longest := maxi(width, height)
	return clampi(max_side / maxi(1, longest), 1, 8)


# -------------------------------------------------------------------- sight ---
## Tiles the player can see right now: a hard-edged disc is fine at minimap size
## and costs no extra state. Kept as a small helper so `render_image` reads like
## a sentence.
var _sight_tile := Vector2i(-9999, -9999)
var _sight_radius_tiles := 0


func set_sight(centre: Vector2, radius_m: float = -1.0) -> void:
	var r := sight_m if radius_m < 0.0 else radius_m
	_sight_tile = world_to_tile(centre)
	_sight_radius_tiles = int(ceil(r / cell))


func _in_current_sight(tx: int, tz: int) -> bool:
	if _sight_radius_tiles <= 0:
		return true
	return Vector2(tx - _sight_tile.x, tz - _sight_tile.y).length() <= float(_sight_radius_tiles)
