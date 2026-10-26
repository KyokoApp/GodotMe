extends Node3D
## Gate for step 3B: the buildings are MESHES built from a modular kit.
##
##   godot --headless --path game res://game/tests/BuildingTest.tscn
##
## A screenshot can show that the village looks right. It cannot show that every
## cell the kit asks for exists in the atlas (a typo yields an invisible wall,
## and an invisible wall still "looks fine" with the wall behind it), that the
## houses stand on the lowest corner of their footprint instead of floating over
## a slope, that a cottage is still one mesh with one material, or that the
## triangle count fits a phone. This scene checks those.
##
## The same scene is the capture stage: with `--capture=` it lays the whole kit
## out on a plain plinth and takes one shot from the side named by `--view=`,
## in the light named by `--time=`:
##
##   godot --path game res://game/tests/BuildingTest.tscn -- \
##     --view=kanan --time=malam --capture=<dir> --capture-name=51_bangunan_kanan_malam
##
## Exit code 1 on any broken rule.

const HARNESS := preload("res://game/tests/TestHarness.gd")
const KIT_SCRIPT := preload("res://game/world/BuildingKit.gd")
const DATA_SCRIPT := preload("res://game/world/RegionData.gd")
const VIEW_SCRIPT := preload("res://game/world/RegionView.gd")

const KIT_META := "res://game/world/building_kit.json"
const KIT_ATLAS := "res://game/world/textures/building_atlas.png"
const KIT_SHADER := "res://game/world/building.gdshader"
const REGION_JSON := "res://game/world/regions/yaros.json"

## The collision contract from step 2, by heart and on purpose: RegionData says
## how much room a house takes when the knight walks into it, and step 3B is not
## allowed to change that just because the house is a mesh now. If either side
## moves, this test fails and somebody has to decide which number is right.
const BLOCK_CONTRACT := {
	"cottage": 2.0, "tower": 2.4, "gate": 2.2, "well": 0.9,
}

## A cottage is a box, six windows, a door, a roof and a chimney. Anything much
## past this is a modelling accident, not a detail: the phone draws these.
const MAX_TRIS_PER_BUILDING := 900
const MAX_VILLAGE_TRIS := 16000
const MAX_VERTS_PER_BUILDING := 1400

var failures := 0
var checks := 0
var _kit: RefCounted
var _meta: Dictionary
var _view: Node3D
var _region: RefCounted


func _ready() -> void:
	await get_tree().process_frame
	if HARNESS.has_arg("--capture="):
		await _stage_shot()
		return
	if not _load():
		print("[BUILDING] gagal memuat kit, %d gagal" % failures)
		get_tree().quit(1)
		return
	_test_manifest()
	_test_atlas()
	_test_meshes()
	_test_cells_are_real()
	_test_variants()
	_test_budget()
	await _test_region()
	_test_occluders()
	_test_parts()
	print("[BUILDING] %d pemeriksaan, %d gagal" % [checks, failures])
	await _shutdown()


func _check(cond: bool, label: String, extra: String = "") -> void:
	checks += 1
	if cond:
		print("[BUILDING] PASS %s" % label)
	else:
		failures += 1
		print("[BUILDING] FAIL %s %s" % [label, extra])


func _load() -> bool:
	if not FileAccess.file_exists(KIT_META):
		_check(false, "building_kit.json ada", KIT_META)
		return false
	_kit = KIT_SCRIPT.new()
	if _kit == null:
		_check(false, "BuildingKit.gd termuat")
		return false
	_meta = _kit.call("kit_meta")
	_check(not _meta.is_empty(), "building_kit.json terbaca sebagai JSON")
	return not _meta.is_empty()


# --------------------------------------------------------------- manifest -----
func _test_manifest() -> void:
	var cells: Array = _meta.get("cells", [])
	_check(cells.size() == 16, "atlas kit memuat 16 sel", str(cells.size()))
	var seen: Dictionary = {}
	var bad: Array = []
	var tile_ok := 0
	for raw in cells:
		if typeof(raw) != TYPE_DICTIONARY:
			bad.append("sel bukan objek")
			continue
		var c: Dictionary = raw
		var name := String(c.get("name", ""))
		if name == "" or seen.has(name):
			bad.append("nama kosong/ganda: %s" % name)
			continue
		seen[name] = true
		var uv: Array = c.get("uv", [])
		var rect: Array = c.get("rect", [])
		if uv.size() < 4 or rect.size() < 4:
			bad.append("%s tanpa uv/rect" % name)
			continue
		if float(uv[0]) < 0.0 or float(uv[1]) < 0.0 \
				or float(uv[0]) + float(uv[2]) > 1.001 or float(uv[1]) + float(uv[3]) > 1.001:
			bad.append("%s keluar atlas" % name)
		if float(c.get("tile_m", 0.0)) > 0.0:
			tile_ok += 1
	_check(bad.is_empty(), "setiap sel punya nama, uv dan rect yang sah", str(bad))
	# the one link between the two halves of step 3B: every cell the kit code
	# asks for by name has to exist here, or a wall silently disappears
	var required: Array = KIT_SCRIPT.required_cells()
	var missing: Array = []
	for name in required:
		if not seen.has(String(name)):
			missing.append(name)
	_check(missing.is_empty(), "semua sel yang dipakai kode ada di atlas", str(missing))
	_check(tile_ok >= 8, "sel yang dipetakan berulang punya ukuran meter", str(tile_ok))
	# kinds
	var kinds: Dictionary = _meta.get("kinds", {})
	_check(kinds.size() >= 7, "kit mengenal tujuh jenis bangunan", str(kinds.size()))
	var flat: Array = []
	for k in kinds.keys():
		var e: Dictionary = kinds[k]
		var w := float(e.get("w", 0.0))
		var d := float(e.get("d", 0.0))
		var h := float(e.get("h", 0.0))
		if w <= 0.2 or d <= 0.2 or h <= 0.2:
			flat.append("%s ukuran nol" % k)
		if int(e.get("variants", 0)) < 1:
			flat.append("%s tanpa varian" % k)
	_check(flat.is_empty(), "setiap jenis punya ukuran dan varian", str(flat))


# ------------------------------------------------------------------ atlas -----
## Read the PNG the way the game reads it (raw bytes, no sRGB) and prove that
## every cell actually has paint in it: an all-empty cell is a building with a
## hole where its roof should be, and nothing else in this test would notice.
func _test_atlas() -> void:
	if not FileAccess.file_exists(KIT_ATLAS):
		_check(false, "building_atlas.png ada", KIT_ATLAS)
		return
	var img := Image.new()
	if img.load_png_from_buffer(FileAccess.get_file_as_bytes(KIT_ATLAS)) != OK:
		_check(false, "building_atlas.png terbaca")
		return
	var declared: Array = _meta.get("atlas", [0, 0])
	_check(img.get_width() == int(declared[0]) and img.get_height() == int(declared[1]),
		"atlas sesuai ukuran yang dicatat", "%dx%d" % [img.get_width(), img.get_height()])
	var empty: Array = []
	var flat: Array = []
	for raw in _meta.get("cells", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var c: Dictionary = raw
		var rect: Array = c.get("rect", [])
		if rect.size() < 4:
			continue
		var r := Rect2i(int(rect[0]), int(rect[1]), int(rect[2]), int(rect[3]))
		var region := img.get_region(r)
		var colours: Dictionary = {}
		for y in range(0, region.get_height(), 4):
			for x in range(0, region.get_width(), 4):
				var px := region.get_pixel(x, y)
				if px.a > 0.01:
					colours[px.to_rgba32()] = true
		if colours.is_empty():
			empty.append(String(c.get("name", "?")))
		if colours.size() < 2:
			flat.append(String(c.get("name", "?")))
	_check(empty.is_empty(), "tidak ada sel atlas yang kosong", str(empty))
	_check(flat.is_empty(), "tidak ada sel yang hanya satu warna", str(flat))
	print("[BUILDING] atlas %dx%d, %d sel" % [img.get_width(), img.get_height(),
		(_meta.get("cells", []) as Array).size()])


# ----------------------------------------------------------------- meshes -----
func _test_meshes() -> void:
	var kinds: Dictionary = _meta.get("kinds", {})
	var bad: Array = []
	var totals := ""
	for kind in kinds.keys():
		var variants := maxi(1, int((kinds[kind] as Dictionary).get("variants", 1)))
		var tri_here := 0
		var vert_here := 0
		for v in range(variants):
			var made: Dictionary = _kit.call("make", String(kind), v, _meta)
			var label := "%s#%d" % [kind, v]
			if made.is_empty():
				bad.append("%s gagal dibangun" % label)
				continue
			var mesh: ArrayMesh = made.get("mesh", null)
			if mesh == null or mesh.get_surface_count() != 1:
				bad.append("%s bukan satu permukaan" % label)
				continue
			var arrays: Dictionary = made["arrays"]
			var verts: PackedVector3Array = arrays["verts"]
			var index: PackedInt32Array = arrays["index"]
			var norms: PackedVector3Array = arrays["norms"]
			var uv2s: PackedVector2Array = arrays["uv2s"]
			var cols: PackedColorArray = arrays["colors"]
			var counts := [verts.size(), norms.size(), uv2s.size(), cols.size()]
			if counts[0] == 0 or index.size() % 3 != 0:
				bad.append("%s indeks rusak" % label)
				continue
			for n in counts:
				if int(n) != counts[0]:
					bad.append("%s atribut tidak sejajar" % label)
			var worst_index := 0
			for i in index:
				worst_index = maxi(worst_index, i)
			if worst_index >= verts.size():
				bad.append("%s indeks keluar batas" % label)
			var bounds: AABB = KIT_SCRIPT.bounds_of(arrays)
			var top := float(made.get("top", 0.0))
			if absf(bounds.end.y - top) > 0.35:
				bad.append("%s tinggi %.2f bukan %.2f" % [label, bounds.end.y, top])
			# a jetty's piles reach 1,6 m under the water; nothing may dive deeper
			# than that, and nothing may hang in the air either
			if bounds.position.y < -1.8:
				bad.append("%s turun %.2f m" % [label, bounds.position.y])
			var size_kind: Vector2 = Vector2(
				float((kinds[kind] as Dictionary).get("w", 2.0)),
				float((kinds[kind] as Dictionary).get("d", 2.0)))
			if bounds.size.x > size_kind.x + 0.8 or bounds.size.z > size_kind.y + 0.8:
				bad.append("%s lebih lebar dari catatan kit" % label)
			# normals must be real normals, not zero: a zero normal makes a wall
			# light up like a lamp
			var flat_normals := 0
			for nrm in norms:
				if absf(nrm.length() - 1.0) > 0.02:
					flat_normals += 1
			if flat_normals > 0:
				bad.append("%s punya %d normal rusak" % [label, flat_normals])
			# the detail classes the shader understands, and nothing else
			var odd_alpha := 0
			for c in cols:
				if absf(c.a) > 0.01 and absf(c.a - KIT_SCRIPT.DETAIL) > 0.01 \
						and absf(c.a - KIT_SCRIPT.LIT) > 0.01:
					odd_alpha += 1
			if odd_alpha > 0:
				bad.append("%s punya %d alpha kelas aneh" % [label, odd_alpha])
			tri_here += int(made["tris"])
			vert_here += verts.size()
			if int(made["tris"]) > MAX_TRIS_PER_BUILDING:
				bad.append("%s %d segitiga, terlalu berat" % [label, int(made["tris"])])
			if verts.size() > MAX_VERTS_PER_BUILDING:
				bad.append("%s %d verteks, terlalu berat" % [label, verts.size()])
			# determinism: the same kit must build the same mesh twice, or the
			# captures of two runs cannot be compared
			var again: Dictionary = _kit.call("make_tinted", String(kind), v, _meta, Color.WHITE)
			if not again.is_empty():
				var v2: PackedVector3Array = (again["arrays"] as Dictionary)["verts"]
				if v2.size() != verts.size() or (v2.size() > 0 and not v2[0].is_equal_approx(verts[0])):
					bad.append("%s tidak deterministik" % label)
		totals += "%s=%d segitiga/%d v  " % [kind, tri_here, vert_here]
	_check(bad.is_empty(), "semua varian terbangun utuh", str(bad))
	print("[BUILDING] mesh: %s" % totals)


## Every vertex must name a cell that exists in the atlas. A typo in a cell name
## is invisible in every other check - the wall is simply not drawn - so this is
## the one that catches it.
func _test_cells_are_real() -> void:
	var known: Array = []
	for raw in _meta.get("cells", []):
		if typeof(raw) == TYPE_DICTIONARY:
			var uv: Array = (raw as Dictionary).get("uv", [])
			if uv.size() >= 2:
				known.append(Vector2(float(uv[0]), float(uv[1])))
	var bad: Array = []
	for kind in (_kit_meta_kinds() as Array):
		var made: Dictionary = _kit.call("make", String(kind), 0, _meta)
		if made.is_empty():
			continue
		var uv2s: PackedVector2Array = (made["arrays"] as Dictionary)["uv2s"]
		var unknown := 0
		for uv in uv2s:
			var found := false
			for k in known:
				if (k as Vector2).distance_to(uv) < 0.0005:
					found = true
					break
			if not found:
				unknown += 1
		if unknown > 0:
			bad.append("%s: %d verteks memakai sel tak dikenal" % [kind, unknown])
	_check(bad.is_empty(), "setiap verteks menunjuk sel atlas yang ada", str(bad))


func _kit_meta_kinds() -> Array:
	var out: Array = []
	for k in (_meta.get("kinds", {}) as Dictionary).keys():
		out.append(String(k))
	return out


## The variants have to differ: three identical cottages would pass every other
## check here and still leave a village of clones.
func _test_variants() -> void:
	for kind in ["cottage", "tower", "sign"]:
		var variants := maxi(1, int(((_meta.get("kinds", {}) as Dictionary).get(kind, {}) as Dictionary)
			.get("variants", 1)))
		if variants < 2:
			continue
		var shapes: Array = []
		for v in range(variants):
			var made: Dictionary = _kit.call("make", kind, v, _meta)
			if made.is_empty():
				continue
			var bounds: AABB = KIT_SCRIPT.bounds_of(made["arrays"])
			shapes.append("%d/%.2f" % [int(made["tris"]), bounds.size.y])
		var distinct := {}
		for shape in shapes:
			distinct[shape] = true
		_check(distinct.size() == variants, "%s punya %d bentuk berbeda" % [kind, variants],
			str(shapes))


# ----------------------------------------------------------------- budget -----
## The phone budget, counted rather than hoped for: the whole village of Yaros,
## every instance, in triangles.
func _test_budget() -> void:
	if _region == null and not _load_region():
		return
	var decor: Dictionary = _region.get("decor")
	var kinds: Dictionary = _meta.get("kinds", {})
	var total := 0
	var instanced := 0
	for kind in (VIEW_SCRIPT.BUILDING_KINDS as Array):
		var rows: Variant = decor.get(kind, [])
		if typeof(rows) != TYPE_ARRAY:
			continue
		var variants := maxi(1, int((kinds.get(kind, {}) as Dictionary).get("variants", 1)))
		# the worst case: every instance a different variant, so no variant is
		# dropped as unused
		var worst := 0
		for v in range(variants):
			var made: Dictionary = _kit.call("make", String(kind), v, _meta)
			if not made.is_empty():
				worst = maxi(worst, int(made["tris"]))
		total += worst * (rows as Array).size()
		instanced += (rows as Array).size()
	print("[BUILDING] anggaran: %d instance, %d segitiga terburuk" % [instanced, total])
	_check(instanced >= 20, "desa memakai kit untuk >= 20 bangunan", str(instanced))
	_check(total <= MAX_VILLAGE_TRIS, "segitiga seluruh desa di bawah anggaran",
		"%d <= %d" % [total, MAX_VILLAGE_TRIS])


func _load_region() -> bool:
	if not FileAccess.file_exists(REGION_JSON):
		return false
	_region = DATA_SCRIPT.new()
	return bool(_region.call("load_file", REGION_JSON))


# ----------------------------------------------------------------- region -----
## The kit on its own can be perfect and the village still wrong: the wrong place,
# a house on the average height of a slope, a billboard house left standing next
## to its own mesh. This is the part that checks the region.
func _test_region() -> void:
	if _region == null and not _load_region():
		_check(false, "peta Yaros termuat")
		return
	_view = VIEW_SCRIPT.new()
	_view.name = "RegionViewProbe"
	add_child(_view)
	_view.call("setup", _region, 0)
	await get_tree().process_frame
	var layout: Array = _view.call("building_layout")
	_check(layout.size() >= 20, "desa menaruh >= 20 bangunan 3D", str(layout.size()))
	var kinds_seen: Dictionary = {}
	var floating: Array = []
	var sunk: Array = []
	for raw in layout:
		var row: Array = raw
		if row.size() < 8:
			continue
		var kind := String(row[0])
		kinds_seen[kind] = int(kinds_seen.get(kind, 0)) + 1
		var x := float(row[2])
		var z := float(row[3])
		var foot := float(row[4])
		var ground: float = float(_region.call("height_at", Vector2(x, z)))
		# the foot sits on the LOWEST corner, so it may be below the ground under
		# the middle of the house (a slope) but never above it
		if foot > ground + 0.02:
			floating.append("%s di %.1f/%.1f: kaki %.2f > tanah %.2f" % [kind, x, z, foot, ground])
		if foot < ground - 3.2:
			sunk.append("%s di %.1f/%.1f: kaki %.2f, tanah %.2f" % [kind, x, z, foot, ground])
	_check(floating.is_empty(), "tidak ada bangunan yang melayang", str(floating))
	_check(sunk.is_empty(), "tidak ada bangunan yang tenggelam", str(sunk))
	var missing: Array = []
	for kind in ["cottage", "tower", "gate", "well", "dock"]:
		if not kinds_seen.has(kind):
			missing.append(kind)
	_check(missing.is_empty(), "rumah, menara, gerbang, sumur, dermaga semuanya 3D",
		str(missing))
	print("[BUILDING] desa: %s" % str(kinds_seen))
	# the collision contract, unchanged from step 2
	var wrong_block: Array = []
	for raw in layout:
		var row: Array = raw
		if row.size() < 8:
			continue
		var kind := String(row[0])
		if not BLOCK_CONTRACT.has(kind):
			continue
		if absf(float(row[7]) - float(BLOCK_CONTRACT[kind])) > 0.01:
			wrong_block.append("%s %.2f != %.2f" % [kind, float(row[7]), BLOCK_CONTRACT[kind]])
	_check(wrong_block.is_empty(), "radius tabrakan sama dengan kontrak langkah 2",
		str(wrong_block))
	var contract_src := 0
	for kind in BLOCK_CONTRACT.keys():
		if is_equal_approx(DATA_SCRIPT.blocker_radius(kind), float(BLOCK_CONTRACT[kind])):
			contract_src += 1
	_check(contract_src == BLOCK_CONTRACT.size(),
		"RegionData sendiri masih memakai angka yang sama", str(contract_src))
	# and the sprites are gone: a cottage may not be drawn twice
	var leftover: Array = []
	for raw in _view.call("prop_layout"):
		var row: Array = raw
		if row.size() > 0 and VIEW_SCRIPT.BUILDING_KINDS.has(String(row[0])):
			leftover.append(String(row[0]))
	_check(leftover.is_empty(), "tidak ada lagi bangunan yang digambar sebagai sprite",
		str(leftover))
	var stats: Dictionary = _view.call("stats")
	_check(int(stats.get("buildings", 0)) >= 20, "penghitung instance melaporkan bangunan 3D",
		str(stats.get("buildings", 0)))
	print("[BUILDING] draw: %d chunk + %d jenis prop + %d batch bangunan = %d" % [
		int(stats.get("chunks", 0)), int(stats.get("prop_kinds", 0)),
		int(stats.get("build_kinds", 0)), int(stats.get("draws", 0))])


## The occlusion corridor must see a house as an occluder now that it is a mesh,
## and the fade key has to be the one the region knows how to write.
func _test_occluders() -> void:
	if _view == null:
		_check(false, "RegionView tersedia untuk uji occlusion")
		return
	var tower: Array = []
	for raw in _view.call("building_layout"):
		var row: Array = raw
		if row.size() >= 6 and String(row[0]) == "tower":
			tower = row
			break
	_check(not tower.is_empty(), "menara ada di layout untuk uji occlusion")
	if tower.is_empty():
		return
	var x := float(tower[2])
	var z := float(tower[3])
	# the camera 9 m south of the tower, the knight 3 m north of it: the tower is
	# squarely in between
	var plan: Dictionary = _view.call("occluders_for", Vector2(x, z + 3.0),
		Vector2(x, z - 9.0), 1.05, 2.5)
	var building_keys := 0
	var lowest := 1.0
	for key in plan.keys():
		if String(key).begins_with("b:"):
			building_keys += 1
			lowest = minf(lowest, float(plan[key]))
	_check(building_keys >= 1, "menara ikut memudar saat menghalangi kamera",
		str(building_keys))
	_check(lowest < 1.0 and lowest >= 0.24, "pemudaran bangunan setengah, bukan hilang",
		"%.2f" % lowest)


## The kit's own inventory, printed so the report can quote it instead of
## describing it from memory.
func _test_parts() -> void:
	var lines := ""
	var empty: Array = []
	for kind in ["cottage", "tower", "gate", "well", "dock", "sign", "torch"]:
		var parts: Array = KIT_SCRIPT.parts_of(kind)
		if (parts as Array).is_empty():
			empty.append(kind)
		lines += "%s: %s | " % [kind, ", ".join(parts)]
	_check(empty.is_empty(), "setiap jenis punya daftar bagian", str(empty))
	print("[BUILDING] kit: %s" % lines)


func _shutdown() -> void:
	if _view != null and _view.has_method("drain"):
		_view.call("drain")
		_view.queue_free()
		_view = null
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if failures == 0 else 1)


# ------------------------------------------------------------------ stage -----
## The capture stage: the whole kit on a plain plinth, so the four sides of a
## building can be photographed without a forest in the way. This is a measuring
## instrument, not the game: the game itself is captured through Main.tscn.
func _stage_shot() -> void:
	var side := HARNESS.arg("--view=", "depan")
	var time := HARNESS.arg("--time=", "siang")
	var night := time == "malam"
	_build_stage(night)
	_place_kit(night)
	_frame_camera(side)
	await get_tree().process_frame
	await get_tree().process_frame
	var default_name := "50_bangunan_%s_%s" % [side, time]
	await HARNESS.capture(self, default_name, 1.4)
	await HARNESS.quit_after(self, 40.0)


func _build_stage(night: bool) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.07, 0.13) if night else Color(0.44, 0.55, 0.68)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.42, 0.58) if night else Color(1.0, 0.97, 0.92)
	env.ambient_light_energy = 0.30 if night else 0.62
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	# the windows and the torch flame are emission, so the night shot needs glow
	# to bloom them the way the game's Environment does
	env.glow_enabled = true
	env.glow_intensity = 0.75 if night else 0.2
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(0.62, 0.72, 1.0) if night else Color(1.0, 0.94, 0.84)
	sun.light_energy = 0.22 if night else 1.25
	sun.rotation_degrees = Vector3(-52.0, -34.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	if night:
		# a cold fill from the other side so a night silhouette still reads
		var fill := DirectionalLight3D.new()
		fill.light_color = Color(0.42, 0.52, 0.86)
		fill.light_energy = 0.35
		fill.rotation_degrees = Vector3(-28.0, 148.0, 0.0)
		add_child(fill)

	# the plinth: a plain slab, so nothing competes with the buildings
	var ground := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(64.0, 0.6, 64.0)
	ground.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.36, 0.25) if not night else Color(0.16, 0.20, 0.16)
	mat.roughness = 0.95
	ground.material_override = mat
	ground.position = Vector3(0.0, -0.3, 0.0)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)


## One of everything the kit can build, arranged as a small square: the tower in
## the middle, cottages around it, the gate on the road in, the well and the
## jetty at the edge, signs and torches where a village puts them.
func _place_kit(night: bool) -> void:
	var atlas := _load_tex(KIT_ATLAS)
	var mat := ShaderMaterial.new()
	mat.shader = load(KIT_SHADER)
	mat.set_shader_parameter("atlas", atlas)
	mat.set_shader_parameter("cell_size", 128.0 / 512.0)
	mat.set_shader_parameter("night", 1.0 if night else 0.0)
	mat.set_shader_parameter("instance_fade", 0.0)
	var cells: Dictionary = _kit.call("cells_of", _meta)
	if cells.has("flame"):
		mat.set_shader_parameter("flame_cell", cells["flame"])
	var layout := [
		["tower", 1, Vector3(0.0, 0.0, 0.0), 0.0, Color(1.0, 1.0, 1.0)],
		["cottage", 0, Vector3(-7.4, 0.0, 3.2), 1.05, Color(1.0, 1.0, 1.0)],
		["cottage", 1, Vector3(-7.0, 0.0, -4.4), -1.75, Color(0.97, 0.92, 0.84)],
		["cottage", 2, Vector3(7.2, 0.0, 4.0), -1.02, Color(0.99, 0.94, 0.86)],
		["gate", 0, Vector3(0.0, 0.0, -8.6), 0.0, Color(0.96, 0.97, 0.98)],
		["well", 0, Vector3(3.4, 0.0, -1.6), 0.0, Color(1.0, 1.0, 1.0)],
		["dock", 0, Vector3(9.2, 0.0, -6.2), 0.0, Color(1.0, 1.0, 1.0)],
		["sign", 1, Vector3(-3.6, 0.0, -7.2), 0.35, Color(1.0, 1.0, 1.0)],
		["torch", 0, Vector3(-2.2, 0.0, 0.6), 0.0, Color(1.0, 1.0, 1.0)],
		["torch", 0, Vector3(2.4, 0.0, 1.8), 0.0, Color(1.0, 1.0, 1.0)],
	]
	for raw in layout:
		var row: Array = raw
		# tinted per building, because a stand-alone MeshInstance3D has no
		# MultiMesh instance colour to carry the shade
		var made: Dictionary = _kit.call("make_tinted", String(row[0]), int(row[1]),
			_meta, row[4])
		if made.is_empty():
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Kit_%s_%d" % [row[0], int(row[1])]
		mi.mesh = made["mesh"]
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.position = row[2]
		mi.rotation.y = float(row[3])
		add_child(mi)


## Four sides around the tower, so the kit is photographed from every direction
## instead of only from the angle the camera happens to like.
func _frame_camera(side: String) -> void:
	var yaw := 0.0
	match side:
		"depan":
			yaw = 0.0
		"kanan":
			yaw = PI * 0.5
		"belakang":
			yaw = PI
		"kiri":
			yaw = PI * 1.5
		_:
			yaw = 0.0
	var cam := Camera3D.new()
	cam.name = "StageCamera"
	cam.fov = 42.0
	cam.near = 0.2
	cam.far = 400.0
	var dist := 21.0
	var height := 8.6
	cam.position = Vector3(sin(yaw) * dist, height, cos(yaw) * dist)
	add_child(cam)
	cam.look_at(Vector3(0.0, 2.6, 0.0), Vector3.UP)
	cam.make_current()


## The game reads its PNGs as raw bytes (see RegionView._tex): an imported sRGB
## texture arrives almost black and the whole valley went brown in step 2. The
## stage has to sample the atlas the same way or the capture lies.
func _load_tex(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	return ImageTexture.create_from_image(img)
