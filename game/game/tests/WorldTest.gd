extends Node3D
## Headless gate for phase 6: the day cycle and the atmosphere.
##
## Light is the one thing a screenshot cannot check. A capture proves the dusk
## shot looks warm; it cannot prove that noon is brighter than midnight, that the
## lamp only burns after dark, or that a firefly in the afternoon is a bug. This
## scene builds the real diorama, walks all four phases and asserts the numbers.
##
##   godot --headless --path game res://game/tests/WorldTest.tscn
##
## Exit code 1 on any broken rule, so CI fails instead of shipping it.

const DIORAMA := "res://game/world/Diorama.tscn"
const PHASE_IDS := ["pagi", "siang", "sore", "malam"]

var failures := 0
var checks := 0
var _world: Node3D


func _ready() -> void:
	await get_tree().process_frame
	_world = load(DIORAMA).instantiate() as Node3D
	add_child(_world)
	for _i in 4:
		await get_tree().process_frame
	var clock: Node = _world.call("clock")
	if clock != null:
		clock.set("running", false)   # deterministic: only this test moves time
	await _test_wiring()
	await _test_light_per_phase()
	await _test_atmosphere()
	await _test_clock_runs()
	print("[WORLD] %d pemeriksaan, %d gagal" % [checks, failures])
	# Quit only after the diorama has actually left the tree. Calling quit() with
	# the region, its chunk tasks and its particles still alive killed the process
	# at teardown (exit 134 with every check green), which reads in CI as a failed
	# rule when no rule failed.
	var view: Node = _world.call("view") if _world.has_method("view") else null
	if view != null and view.has_method("drain"):
		view.call("drain")
	_world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("[WORLD] siap keluar")
	get_tree().quit(0 if failures == 0 else 1)


func _check(cond: bool, label: String, extra: String = "") -> void:
	checks += 1
	if cond:
		print("[WORLD] PASS %s" % label)
	else:
		failures += 1
		print("[WORLD] FAIL %s %s" % [label, extra])


func _test_wiring() -> void:
	var clock: Node = _world.call("clock")
	var atmo: Node = _world.call("atmosphere")
	_check(clock != null, "diorama punya WorldClock")
	_check(atmo != null, "diorama punya Atmosphere")
	_check(String(_world.call("phase_name")) == "sore", "diorama mulai di sore",
		String(_world.call("phase_name")))
	if clock != null:
		var ids: Array = clock.call("phase_ids")
		_check(ids == PHASE_IDS, "empat fase dikenal", str(ids))


func _test_light_per_phase() -> void:
	var sun: DirectionalLight3D = _world.get_node_or_null("Sun") as DirectionalLight3D
	var env: Environment = (_world.get_node("WorldEnvironment") as WorldEnvironment).environment
	var lamp: OmniLight3D = _world.call("lamp")
	_check(sun != null and env != null and lamp != null, "matahari, environment, lampu ada")
	if sun == null or env == null or lamp == null:
		return

	var seen := {}
	for id in PHASE_IDS:
		_world.call("set_phase", id)
		await get_tree().process_frame
		_check(String(_world.call("phase_name")) == id, "fase %s bisa dipilih" % id,
			String(_world.call("phase_name")))
		seen[id] = {
			"energy": sun.light_energy,
			"color": sun.light_color,
			"rot": sun.rotation_degrees,
			"fog": env.fog_density,
			"ambient": env.ambient_light_energy,
			"lamp": lamp.light_energy,
		}

	var noon: Dictionary = seen["siang"]
	var night: Dictionary = seen["malam"]
	var dawn: Dictionary = seen["pagi"]
	_check(float(night["energy"]) < float(noon["energy"]) - 0.3,
		"malam lebih gelap dari siang", "%.2f vs %.2f" % [night["energy"], noon["energy"]])
	_check((night["color"] as Color).b > (night["color"] as Color).r,
		"cahaya malam kebiruan, bukan neon", str(night["color"]))
	_check((noon["rot"] as Vector3).x < (dawn["rot"] as Vector3).x - 10.0,
		"matahari lebih tinggi saat siang", "%s vs %s" % [noon["rot"], dawn["rot"]])
	_check(float(dawn["fog"]) > float(noon["fog"]),
		"kabut paling tebal saat pagi", "%.4f vs %.4f" % [dawn["fog"], noon["fog"]])
	var sane := true
	for id in PHASE_IDS:
		var e := float((seen[id] as Dictionary)["ambient"])
		if e < 0.15 or e > 0.75:
			sane = false
	_check(sane, "ambient tiap fase masuk akal (0,15-0,75)")
	_check(float(noon["lamp"]) < 0.05 and float(night["lamp"]) > 0.8,
		"lampu pondok hanya menyala setelah gelap",
		"siang %.2f, malam %.2f" % [noon["lamp"], night["lamp"]])


func _test_atmosphere() -> void:
	var atmo: Node = _world.call("atmosphere")
	if atmo == null:
		return
	var systems: Dictionary = atmo.call("systems")
	_check(systems.size() == 4, "empat sistem atmosfer", str(systems.keys()))
	var textured := 0
	for key in systems.keys():
		var p: CPUParticles3D = systems[key]
		var mesh := p.mesh as QuadMesh
		if mesh != null and mesh.material is StandardMaterial3D:
			if (mesh.material as StandardMaterial3D).albedo_texture != null:
				textured += 1
	_check(textured == 4, "semua tekstur partikel termuat dari paket", str(textured))

	_world.call("set_phase", "malam")
	await get_tree().process_frame
	_check(float(atmo.call("intensity", "fireflies")) > 0.25,
		"kunang-kunang hidup saat malam", str(atmo.call("intensity", "fireflies")))
	_check(float(atmo.call("intensity", "dust")) < 0.1,
		"debu tidur saat malam", str(atmo.call("intensity", "dust")))
	var fly: CPUParticles3D = systems["fireflies"]
	_check(fly.emitting, "sistem kunang-kunang benar-benar memancar")

	_world.call("set_phase", "siang")
	await get_tree().process_frame
	_check(float(atmo.call("intensity", "dust")) > 0.4,
		"debu tampak saat siang", str(atmo.call("intensity", "dust")))
	_check(float(atmo.call("intensity", "fireflies")) < 0.1,
		"tidak ada kunang-kunang di siang hari", str(atmo.call("intensity", "fireflies")))

	_world.call("set_phase", "sore")
	await get_tree().process_frame
	_check(float(atmo.call("intensity", "petals")) > 0.5,
		"kelopak terbang saat sore", str(atmo.call("intensity", "petals")))


func _test_clock_runs() -> void:
	var clock: Node = _world.call("clock")
	if clock == null:
		return
	_world.call("set_phase", "siang")
	await get_tree().process_frame
	# Constants are not properties: read them off the script, not with get().
	var consts: Dictionary = (clock.get_script() as Script).get_script_constant_map()
	var day_seconds := float(consts.get("DAY_SECONDS", 480.0))
	clock.call("advance", day_seconds * 0.26)
	await get_tree().process_frame
	_check(String(_world.call("phase_name")) == "sore",
		"waktu berjalan dari siang ke sore", String(_world.call("phase_name")))
	clock.call("advance", day_seconds)
	await get_tree().process_frame
	_check(String(_world.call("phase_name")) == "sore",
		"sehari penuh kembali ke fase yang sama", String(_world.call("phase_name")))
	# the phase hook VisualTest has used since phase 2 must keep working
	_world.call("set_time_of_day", true)
	await get_tree().process_frame
	var night_ok := String(_world.call("phase_name")) == "malam"
	_world.call("set_time_of_day", false)
	await get_tree().process_frame
	_check(night_ok and String(_world.call("phase_name")) == "sore",
		"set_time_of_day(true/false) masih kompatibel", String(_world.call("phase_name")))
