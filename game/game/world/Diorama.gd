## No `class_name`: the game runs inside the launcher's project, whose global
## class cache knows nothing about scripts that arrive later inside a .pck. A
## `class_name` reference (e.g. `Diorama.AREA_NAME`) therefore failed to parse
## on the phone - black screen, no boot_ok, watchdog rollback. Everything this
## script needs from its own pack is reached through preload constants.
extends Node3D
## The world: REGION "Yaros", 192x192 tiles of tiered terrain, streamed.
##
## Step 2 replaced a hand-placed 26x20 glade with a region that is DATA. Nothing
## below knows where a tree stands or where the road turns: `regions/yaros.json`
## holds three byte grids (height, terrain, structure), the decorations, the
## markers and the zones, and `tools/build_region.py` wrote it from a declarative
## spec. This script's job is the three things data cannot do on its own:
##
##   * light   - sun, fog, day cycle, the village lamp;
##   * view    - ask RegionView for the chunks around the player and unload the
##               rest (a phone cannot hold 36 864 tiles of mesh);
##   * map     - paint WorldMap's byte grid from the region, so the minimap,
##               the full map and the fog of war describe the same ground the
##               player is walking on, without a second render pass.
##
## Movement rules live in RegionData (can_stand / height_at / find_path). The
## cast asks the world for them and never keeps a copy.

const WORLD_DIR := "res://game/world/"
const TEX_DIR := WORLD_DIR + "textures/"
const REGION_JSON := WORLD_DIR + "regions/yaros.json"
const DATA_SCRIPT := WORLD_DIR + "RegionData.gd"
const VIEW_SCRIPT := WORLD_DIR + "RegionView.gd"
const CAMERA_RIG := preload("res://game/world/DioramaCamera.gd")
const CLOCK_SCRIPT := WORLD_DIR + "WorldClock.gd"
const ATMOSPHERE_SCRIPT := WORLD_DIR + "Atmosphere.gd"
const MAP_SCRIPT := WORLD_DIR + "WorldMap.gd"

## Kept because Main.gd reads these two constants through the script's constant
## map to write the opening banner. The ZONE banner (below) is the live one.
const AREA_NAME := "Lembah Senja"
const AREA_SUBTITLE := "Yaros, awal perjalanan"

## How far the player sees for the map's fog, in metres. Bigger than the old
## valley's 6: a region has landmarks worth seeing coming.
const SIGHT_M := 11.0
## Chunks kept around the player. 1 => 3x3 chunks = 96x96 m, comfortably wider
## than the camera sees at its widest zoom.
const VIEW_RADIUS := 1

## Emitted when the player walks into another named zone: Main turns it into the
## banner ("Hutan Pinus / hutan lebat"), so the world is the only place that
## decides where a zone starts.
signal zone_changed(title: String, subtitle: String)

var _region: RefCounted
var _view: Node3D
var _sun: DirectionalLight3D
var _camera: Node3D
var _env: Environment
var _clock: Node
var _atmosphere: Node
var _lamp: OmniLight3D
var _map: RefCounted
var _zone := ""
var _last_tile := Vector2i(-9999, -9999)
var _stream_timer := 0.0


func _ready() -> void:
	_build_environment()
	_load_region()
	_build_view()
	_build_map()
	_build_atmosphere()
	_build_clock()
	_build_camera()
	_stream_now(_start_position())
	print("[WORLD] %s %dx%d ubin, %d chunk, %d prop, %d marker, %d zona" % [
		String(_region.get("label")) if _region != null else "(tanpa peta)",
		int(_region.get("width")) if _region != null else 0,
		int(_region.get("height")) if _region != null else 0,
		int(_region.call("chunk_count")) if _region != null else 0,
		(int((_region.get("decor") as Dictionary).size()) if _region != null else 0),
		(_region.get("markers") as Array).size() if _region != null else 0,
		(_region.get("zones") as Array).size() if _region != null else 0])


# ------------------------------------------------------------------ loading ---
func _load_region() -> void:
	if not ResourceLoader.exists(DATA_SCRIPT) or not FileAccess.file_exists(REGION_JSON):
		push_error("[WORLD] peta region tidak ada di paket dunia: %s" % REGION_JSON)
		return
	var script: Script = load(DATA_SCRIPT)
	if script == null:
		push_error("[WORLD] RegionData.gd gagal dimuat")
		return
	var region: RefCounted = script.new()
	if not bool(region.call("load_file", REGION_JSON)):
		push_error("[WORLD] peta region gagal dibaca")
		return
	_region = region


func _build_view() -> void:
	if _region == null:
		return
	if not ResourceLoader.exists(VIEW_SCRIPT):
		push_error("[WORLD] RegionView.gd tidak ada di paket dunia")
		return
	var script: Script = load(VIEW_SCRIPT)
	if script == null:
		return
	_view = script.new() as Node3D
	_view.name = "Region"
	add_child(_view)
	_view.call("setup", _region, VIEW_RADIUS)


# --------------------------------------------------------------- lighting ----
func _build_environment() -> void:
	print("[WORLD] renderer=%s, membangun Yaros" % RenderingServer.get_video_adapter_name())
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
	# thinner than the valley's: the region is 192 m across and the camera looks
	# 60 m, so the old density would paint a wall of haze at the far chunk
	env.fog_density = 0.006
	env.fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.30
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.12
	_env = env

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
	# 60 m of shadow map covers the visible chunks; further out the fog does the
	# hiding and a bigger map would only cost resolution on the phone
	_sun.directional_shadow_max_distance = 60.0
	_sun.shadow_bias = 0.04
	_sun.shadow_normal_bias = 1.2
	_sun.shadow_blur = 1.4
	add_child(_sun)


func _build_atmosphere() -> void:
	if not ResourceLoader.exists(ATMOSPHERE_SCRIPT):
		push_warning("[WORLD] Atmosphere.gd tidak ada di paket ini")
		return
	var script: Script = load(ATMOSPHERE_SCRIPT)
	if script == null:
		return
	_atmosphere = script.new()
	_atmosphere.name = "Atmosphere"
	add_child(_atmosphere)
	_atmosphere.call("setup")


## The village lamp: one warm pool of light where the torches are, so the village
## has a heart at dusk. Placed from the region marker, not from a number here.
func _build_clock() -> void:
	_lamp = OmniLight3D.new()
	_lamp.name = "VillageLamp"
	_lamp.light_color = Color(1.0, 0.78, 0.45)
	_lamp.omni_range = 9.0
	_lamp.light_energy = 0.0
	_lamp.shadow_enabled = false
	add_child(_lamp)
	if _region != null:
		var m: Dictionary = _region.call("marker", "Kembali ke desa")
		if not m.is_empty():
			var p: Vector2 = _region.call("marker_pos", m)
			var y := float(_region.call("height_at", p)) + 1.9
			_lamp.position = Vector3(p.x, y, p.y)

	if not ResourceLoader.exists(CLOCK_SCRIPT):
		push_warning("[WORLD] WorldClock.gd tidak ada, dunia tetap dengan satu waktu")
		return
	var script: Script = load(CLOCK_SCRIPT)
	if script == null:
		return
	_clock = script.new()
	_clock.name = "WorldClock"
	add_child(_clock)
	_clock.call("setup", _sun, _env, _lamp)
	_clock.connect("phase_changed", Callable(self, "_on_phase_changed"))
	# RT_WORLD_PHASE lets a capture or a QA run open the game at dusk without
	# waiting eight minutes; a normal build starts in the late afternoon gold.
	var want := OS.get_environment("RT_WORLD_PHASE")
	if want == "":
		want = "sore"
	_clock.call("set_phase", want)
	_on_phase_changed(String(want))


# -------------------------------------------------------------------- map ----
## Paint WorldMap's byte grid from the region. One loop over 36 864 tiles at
## boot (~40 ms), then the minimap can render any window of it for free.
func _build_map() -> void:
	if _region == null or not ResourceLoader.exists(MAP_SCRIPT):
		push_warning("[WORLD] WorldMap.gd tidak ada, minimap kosong")
		return
	var script: Script = load(MAP_SCRIPT)
	if script == null:
		return
	var map: RefCounted = script.new()
	var w := int(_region.get("width"))
	var h := int(_region.get("height"))
	var cell := float(_region.get("cell"))
	map.call("setup", w, h, cell, _region.get("origin"))
	map.set("label", String(_region.get("label")))
	map.set("sight_m", SIGHT_M)

	var kinds: Dictionary = script.get_script_constant_map()
	var K_GRASS := int(kinds.get("KIND_GRASS", 0))
	var K_DIRT := int(kinds.get("KIND_DIRT", 1))
	var K_WATER := int(kinds.get("KIND_WATER", 2))
	var K_ROCK := int(kinds.get("KIND_ROCK", 3))
	var K_FOREST := int(kinds.get("KIND_FOREST", 4))
	var K_BUILDING := int(kinds.get("KIND_BUILDING", 5))
	var K_DEEP := int(kinds.get("KIND_DEEP", 6))
	var K_STONE := int(kinds.get("KIND_STONE", 7))
	var K_SNOW := int(kinds.get("KIND_SNOW", 8))
	var K_SAND := int(kinds.get("KIND_SAND", 9))

	for tz in range(h):
		for tx in range(w):
			var kind := K_GRASS
			var ter := int(_region.call("tile_terrain", tx, tz))
			var code := int(_region.call("struct_code", tx, tz))
			match ter:
				7:
					kind = K_WATER
				8:
					kind = K_DEEP
				3:
					kind = K_ROCK
				10:
					kind = K_STONE
				6:
					kind = K_SNOW
				4:
					kind = K_SAND
				2:
					kind = K_DIRT
				5:
					kind = K_DIRT
				9:
					kind = K_DIRT
				_:
					kind = K_GRASS
			if code == 2:
				kind = K_DIRT   # a bridge reads as road on the map
			if int(_region.call("tile_height", tx, tz)) >= 4 and kind == K_GRASS:
				kind = K_STONE   # high ground is paler on the map, like on foot
			map.call("set_tile", tx, tz, kind)

	# woods and buildings from the decorations, painted ON TOP of the ground but
	# only onto grass, so a road never disappears under a tree
	var decor: Dictionary = _region.get("decor")
	for kind_name in ["pine", "oak"]:
		for raw in (decor.get(kind_name, []) as Array):
			_paint_marker_tiles(map, raw, 2, K_FOREST)
	for kind_name in ["cottage", "tower", "gate", "well", "dock"]:
		var radius := 2 if kind_name in ["cottage", "tower", "gate", "dock"] else 1
		for raw in (decor.get(kind_name, []) as Array):
			_paint_marker_tiles(map, raw, radius, K_BUILDING)

	# places of interest: the map's own markers, verbatim
	for raw in (_region.get("markers") as Array):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var m: Dictionary = raw
		var kind := String(m.get("kind", ""))
		var poi := "landmark"
		match kind:
			"npc_spawn":
				poi = "npc"
			"enemy_camp":
				poi = "enemy"
			"chest", "resource_node":
				poi = "pickup"
			"fast_travel":
				poi = "door"
			"region_gate":
				poi = "gate"
			"cave_entrance":
				poi = "cave"
			"home_plot":
				poi = "home"
			"player_start":
				continue
			_:
				poi = "landmark"
		map.call("add_poi", poi, String(m.get("name", "")),
			Vector2(float(m.get("x", 0.0)), float(m.get("y", 0.0))),
			float(m.get("radius", 2.5)))
	_map = map
	print("[WORLD] peta %dx%d ubin (%.0f m/ubin), poi %d, jenis peta %d" % [
		w, h, cell, (map.get("pois") as Array).size(),
		(kinds.size())])


func _paint_marker_tiles(map: RefCounted, raw: Variant, radius: int, kind: int) -> void:
	if typeof(raw) != TYPE_ARRAY:
		return
	var row: Array = raw
	if row.size() < 2:
		return
	var x := int(floor(float(row[0]) * 0.1))
	var z := int(floor(float(row[1]) * 0.1))
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var tx := x + dx
			var tz := z + dz
			if int(map.call("tile_at", tx, tz)) == 0:
				map.call("set_tile", tx, tz, kind)


# ----------------------------------------------------------------- camera ----
func _build_camera() -> void:
	_camera = CAMERA_RIG.new()
	_camera.name = "CameraRig"
	_camera.start_zoom = 20.0
	if _map != null:
		# the leash comes from the map, so a bigger region widens it with no new
		# number here
		_camera.call("set_map_bounds", (_map.call("bounds") as Rect2).grow(-2.0))
		_camera.bounds = (_map.call("bounds") as Rect2).size * 0.5 - Vector2(4.0, 4.0)
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.fov = 30.0
	cam.near = 0.5
	# 160 m: the far chunk is inside the frame at the widest zoom, and the fog
	# hides the cut
	cam.far = 160.0
	cam.position = Vector3(0.0, 0.0, _camera.start_zoom)
	cam.current = true
	_camera.add_child(cam)
	add_child(_camera)
	print("[WORLD] kamera siap, cam ada=%s" % (_camera.get_node_or_null("Camera3D") != null))


# ------------------------------------------------------------------ frame ----
func _process(delta: float) -> void:
	if _region == null:
		return
	var player := _player_position()
	if player == null:
		return
	var pos: Vector2 = player
	var tile: Vector2i = _region.call("world_to_tile", pos)
	# streaming only when the player crosses a tile: asking every frame would
	# rebuild the same 3x3 ring sixty times a second
	if tile != _last_tile:
		_last_tile = tile
		if _view != null:
			_view.call("set_view_centre", pos)
			_view.call("update_occluders", pos, _camera_xz())
		_announce_zone(pos)
	if _atmosphere != null:
		# the pollen belongs to the camera, not to the origin of the world
		_atmosphere.position = Vector3(pos.x, 0.0, pos.y)
	_stream_timer += delta
	if _stream_timer > 0.25:
		_stream_timer = 0.0
		if _view != null:
			_view.call("update_occluders", pos, _camera_xz())
			_view.call("set_player_xz", pos)


func _player_position() -> Variant:
	var cast := get_node_or_null("Characters")
	if cast == null or not cast.has_method("player"):
		return null
	var p: Node3D = cast.call("player")
	if p == null or not is_instance_valid(p):
		return null
	return Vector2(p.position.x, p.position.z)


func _camera_xz() -> Vector2:
	if _camera == null:
		return Vector2.ZERO
	return Vector2(_camera.global_position.x, _camera.global_position.z)


## Banner text when the player enters a named zone.
func _announce_zone(pos: Vector2) -> void:
	var zone := String(_region.call("zone_at", pos))
	if zone == _zone:
		return
	_zone = zone
	var subtitle := "jalan tua"
	for raw in (_region.get("zones") as Array):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var z: Dictionary = raw
		if String(z.get("name", "")) != zone:
			continue
		subtitle = String(z.get("subtitle", z.get("kind", "")))
		break
	emit_signal("zone_changed", zone, subtitle)


func _on_phase_changed(id: String) -> void:
	if _atmosphere != null and _atmosphere.has_method("set_phase"):
		_atmosphere.call("set_phase", id)
	if _view != null and _sun != null:
		# props are unshaded billboards; the phase warms them through this tint
		_view.call("set_light_tint", _sun.light_color * (0.72 + 0.28 * _sun.light_energy))


# ---------------------------------------------------------------- time API ---
func set_phase(id: String) -> void:
	if _clock != null:
		_clock.call("set_phase", id)


func phase_name() -> String:
	if _clock == null:
		return ""
	return String(_clock.call("phase_name"))


func set_time_of_day(night: bool) -> void:
	if _clock != null:
		_clock.call("set_time_of_day", night)


func clock() -> Node:
	return _clock


func map() -> RefCounted:
	return _map


func camera_rig() -> Node3D:
	return _camera


func set_shadows_enabled(on: bool) -> void:
	if _sun != null:
		_sun.shadow_enabled = on


func set_atmosphere_scale(scale: float) -> void:
	if _atmosphere != null and _atmosphere.has_method("set_amount_scale"):
		_atmosphere.call("set_amount_scale", scale)


func atmosphere() -> Node:
	return _atmosphere


func lamp() -> OmniLight3D:
	return _lamp


func reset_view() -> void:
	if _camera != null:
		_camera.call("reset")


# -------------------------------------------------------- region interface ---
## The movement/navigation data. RegionData is the only owner of the rules; the
## cast keeps a reference and asks it.
func region() -> RefCounted:
	return _region


func view() -> Node3D:
	return _view


func start_position() -> Vector2:
	return _start_position()


func _start_position() -> Vector2:
	if _region == null:
		return Vector2.ZERO
	return _region.call("start_position")


func zone_at(pos: Vector2) -> String:
	if _region == null:
		return ""
	return String(_region.call("zone_at", pos))


func stream_now(pos: Vector2) -> void:
	_stream_now(pos)


func _stream_now(pos: Vector2) -> void:
	if _view == null:
		return
	_view.call("set_view_centre", pos)
	_view.call("set_player_xz", pos)
	_view.call("force_build")
	_last_tile = _region.call("world_to_tile", pos) if _region != null else Vector2i.ZERO


## Streaming numbers for the HUD's FPS line and for the CI report.
func stream_stats() -> Dictionary:
	if _view == null:
		return {}
	return _view.call("stats")


## Props do not have collision bodies - they never did. The region rules and the
## few footprints that matter (houses, the tower, the gate) are enough, and the
## cast asks `can_stand` instead of scanning a list every frame.
func blockers() -> Array:
	var out: Array = []
	if _region == null:
		return out
	# radii in metres; a static function on RegionData cannot be reached through
	# an instance, so the footprint table lives here next to the code that uses it
	var radii := {"cottage": 2.0, "tower": 2.4, "gate": 2.2, "well": 0.9}
	for kind_name in radii.keys():
		var radius := float(radii[kind_name])
		var decor: Dictionary = _region.get("decor")
		for raw in (decor.get(kind_name, []) as Array):
			if typeof(raw) != TYPE_ARRAY:
				continue
			var row: Array = raw
			if row.size() < 2:
				continue
			out.append({"x": float(row[0]) * 0.1, "z": float(row[1]) * 0.1,
				"r": radius, "kind": kind_name})
	return out


## Walkable area in world XZ, used as the outer fence for the actors.
func ground_rect() -> Rect2:
	if _region == null:
		return Rect2(0.0, 0.0, 1.0, 1.0)
	return (_region.call("bounds") as Rect2).grow(-1.0)
