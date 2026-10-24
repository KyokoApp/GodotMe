extends Node
## Automated launcher test suite (dev tool, excluded from the APK).
##
##   godot --headless --path launcher res://tests/TestRunner.tscn -- \
##     --scenario=first_install --data-root=user://t_first --manifest=http://127.0.0.1:8765/manifests/v100.json
##
## Every check prints "CHECK <name> PASS|FAIL <detail>" so the shell driver can
## also grep the transcript.

var scenario := ""
var failures := 0
var checks := 0


func _ready() -> void:
	# hard stop: a stuck scenario must fail fast, not burn the CI budget
	var budget := 75.0
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("--budget="):
			budget = float(String(arg).substr("--budget=".length()))
	if budget > 0.0:
		get_tree().create_timer(budget).timeout.connect(func():
			print("RESULT %s TIMEOUT after %.0fs (%d failures so far)" % [scenario, budget, failures])
			get_tree().quit(3)
		)
	for arg in OS.get_cmdline_user_args():
		var a := String(arg)
		if a.begins_with("--scenario="):
			scenario = a.substr("--scenario=".length())
	print("SCENARIO %s" % scenario)
	print("LEGACY_ROOT %s" % Cfg.data_root())

	match scenario:
		"unit":
			await _scenario_unit()
		"first_install":
			await _scenario_first_install()
		"partial_update":
			await _scenario_partial_update()
		"resume":
			await _scenario_resume()
		"bad_hash":
			await _scenario_bad_hash()
		"offline":
			await _scenario_offline()
		"launcher_too_old":
			await _scenario_launcher_too_old()
		"blocked":
			await _scenario_blocked()
		"signed_ok":
			await _scenario_signed_ok()
		"signed_bad":
			await _scenario_signed_bad()
		"install_and_boot":
			await _scenario_install_and_boot()
		"startup_rollback":
			await _scenario_startup_rollback()
		"capture":
			await _scenario_capture()
		_:
			_check(false, "scenario dikenal", scenario)

	print("RESULT %s %s (%d checks, %d failures)" % [scenario, "PASS" if failures == 0 else "FAIL", checks, failures])
	await get_tree().process_frame
	get_tree().quit(0 if failures == 0 else 1)


# ---------------------------------------------------------------- helpers ----
func _check(cond: bool, label: String, extra: String = "") -> void:
	checks += 1
	if cond:
		print("CHECK %s PASS" % label)
	else:
		failures += 1
		print("CHECK %s FAIL %s" % [label, extra])


func _wait_state(targets: Array, timeout_s: float = 30.0) -> Dictionary:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if targets.has(Updater.state):
			return {"state": Updater.state, "ctx": Updater.ctx}
		await get_tree().process_frame
	return {"state": -1, "ctx": {}}


func _wait_until(cond: Callable, timeout_s: float = 30.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if cond.call():
			return true
		await get_tree().process_frame
	return false


## Point the launcher at another manifest at runtime (the same override file an
## operator can drop on the device: <data_root>/manifest_url.txt).
func _set_manifest(url: String) -> void:
	var f := FileAccess.open(Cfg.data_root().path_join("manifest_url.txt"), FileAccess.WRITE)
	f.store_string(url)
	f.flush()
	f = null


func _install(manifest_url: String, timeout_s: float = 40.0) -> Dictionary:
	_set_manifest(manifest_url)
	Updater.start()
	return await _wait_state([Updater.State.READY, Updater.State.ERROR,
		Updater.State.OFFLINE_READY, Updater.State.LAUNCHER_UPDATE_REQUIRED], timeout_s)


func _base() -> String:
	var url := Cfg.manifest_url()
	var i := url.find("/manifests/")
	return url.substr(0, i) if i > 0 else url


func _pack_count() -> int:
	var dir := Cfg.data_root().path_join("packs")
	return Util.list_files(dir).size()


func _transcript_has(needle: String) -> bool:
	for e in Log.entries():
		if String(e.get("text", "")).contains(needle):
			return true
	return false


# -------------------------------------------------------------- unit tests ---
func _scenario_unit() -> void:
	_check(Util.human_size(1536) == "1,5 KB", "human_size KB", Util.human_size(1536))
	_check(Util.human_size(5 * 1024 * 1024 + 300 * 1024) == "5,3 MB", "human_size MB")
	_check(Util.is_hex64("a".repeat(64)), "is_hex64 valid")
	_check(not Util.is_hex64("a".repeat(63)), "is_hex64 invalid")
	_check(Util.resolve_url("http://h/m/version.json", "packs/x.pck") == "http://h/m/packs/x.pck",
		"resolve relative", Util.resolve_url("http://h/m/version.json", "packs/x.pck"))
	_check(Util.resolve_url("http://127.0.0.1:8765/manifests/v100.json", "packs/core.pck")
		== "http://127.0.0.1:8765/manifests/packs/core.pck", "resolve relative with port",
		Util.resolve_url("http://127.0.0.1:8765/manifests/v100.json", "packs/core.pck"))
	_check(Util.resolve_url("https://x/releases/latest/download/version.json", "packs/a.pck")
		== "https://x/releases/latest/download/packs/a.pck", "resolve github-release style",
		Util.resolve_url("https://x/releases/latest/download/version.json", "packs/a.pck"))
	_check(Util.resolve_url("http://h/m/version.json", "/packs/x.pck") == "http://h/packs/x.pck",
		"resolve root-absolute", Util.resolve_url("http://h/m/version.json", "/packs/x.pck"))
	_check(Util.resolve_url("http://h/m/version.json", "https://cdn/y.pck") == "https://cdn/y.pck",
		"resolve absolute")
	_check(Hasher.sha256_text("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
		"sha256 abc")

	var good := {
		"version": "1.0.0",
		"min_launcher_version": 1,
		"main_scene": "res://game/Main.tscn",
		"packages": [{
			"name": "core", "url": "packs/core.pck", "size": 10,
			"sha256": "a".repeat(64), "load_order": 10,
		}],
	}
	_check(Manifest.validate(good)["ok"], "manifest valid")
	var missing: Dictionary = good.duplicate(true)
	missing.erase("version")
	_check(not Manifest.validate(missing)["ok"], "manifest tanpa version ditolak")
	var dup: Dictionary = good.duplicate(true)
	dup["packages"] = [good["packages"][0], good["packages"][0]]
	_check(not Manifest.validate(dup)["ok"], "nama paket ganda ditolak")
	var badsha: Dictionary = good.duplicate(true)
	badsha["packages"][0]["sha256"] = "xyz"
	_check(not Manifest.validate(badsha)["ok"], "sha256 salah ditolak")
	var unsafe: Dictionary = good.duplicate(true)
	unsafe["main_scene"] = "res://scenes/Launcher.tscn"
	_check(Manifest.validate(unsafe)["ok"], "validasi dasar lolos (aturan res://game dicek saat muat)")

	var raw := "{\"version\":\"1.0.0\"}".to_utf8_buffer()
	var d1 := Manifest.digest_bytes(raw)
	var d2 := Manifest.digest_bytes(raw)
	_check(d1 == d2 and d1.size() == 32, "digest_bytes deterministik")

	# Package URL safety
	_check(Util.parse_json_text("nope")["ok"] == false, "json tidak valid ditolak")


# ----------------------------------------------------------- full pipeline ---
func _scenario_first_install() -> void:
	Updater.start()
	var r := await _wait_state([Updater.State.READY, Updater.State.ERROR])
	_check(r["state"] == Updater.State.READY, "state READY", str(r))
	_check(Store.active_version() == "1.0.0", "versi aktif 1.0.0", Store.active_version())
	_check(Updater.has_playable_version(), "versi bisa dimainkan")
	_check(_pack_count() == 6, "enam paket tersimpan", str(_pack_count()))
	var meta := Store.active_meta()
	var all_ok := (meta.get("packages", []) as Array).size() == 6
	for pkg in meta.get("packages", []):
		if not Store.pack_ready(pkg):
			all_ok = false
	_check(all_ok, "keenam paket ada dan berukuran tepat", JSON.stringify(meta.get("packages", [])))
	var prev: Variant = Util.read_json(Cfg.active_file()).get("previous", "")
	_check(String(prev) == "", "instalasi pertama tanpa versi sebelumnya", String(prev))
	# pretend the player has progress: save data lives OUTSIDE the pack tree
	DirAccess.make_dir_recursive_absolute("user://save")
	var sf := FileAccess.open("user://save/slot1.json", FileAccess.WRITE)
	sf.store_string(JSON.stringify({"slot": 1, "gold": 4242, "chapter": 3}))
	sf.flush()
	sf = null
	_check(FileAccess.file_exists("user://save/slot1.json"), "berkas save dibuat sebelum update")


func _scenario_partial_update() -> void:
	# phase 1: fresh install of 1.0.0
	var r1 := await _install(_base() + "/manifests/v100.json")
	_check(r1["state"] == Updater.State.READY, "instalasi 1.0.0 selesai", str(r1))
	var before := _pack_count()
	_check(before == 6, "enam paket setelah instalasi awal", str(before))
	DirAccess.make_dir_recursive_absolute("user://save")
	var sf := FileAccess.open("user://save/slot1.json", FileAccess.WRITE)
	sf.store_string(JSON.stringify({"slot": 1, "gold": 4242, "chapter": 3}))
	sf.flush()
	sf = null

	# phase 2: delta update to 1.1.0 (only characters.pck differs)
	var r2 := await _install(_base() + "/manifests/v110.json")
	_check(r2["state"] == Updater.State.READY, "naik ke 1.1.0", str(r2))
	_check(Store.active_version() == "1.1.0", "versi aktif 1.1.0", Store.active_version())
	_check(_pack_count() == before + 1, "hanya satu paket baru diunduh",
		"%d -> %d" % [before, _pack_count()])
	_check(Store.previous_version() == "1.0.0", "versi sebelumnya dicatat", Store.previous_version())
	var save_data := Util.read_json("user://save/slot1.json")
	_check(int(save_data.get("gold", 0)) == 4242, "save pemain utuh setelah update",
		JSON.stringify(save_data))
	var meta := Store.active_meta()
	var all_ok := true
	for pkg in meta.get("packages", []):
		if not Store.pack_ready(pkg):
			all_ok = false
	_check(all_ok, "keenam paket lengkap setelah delta")


func _scenario_resume() -> void:
	Updater.start()
	var seen := await _wait_until(func(): return float(Updater.snap.get("percent", 0.0)) >= 0.25, 40.0)
	_check(seen, "unduhan mulai berjalan")
	var pkg := {}
	for p in Updater.plan:
		pkg = p
	var tmp := Store.partial_path(pkg)
	Updater.cancel()
	var r := await _wait_state([Updater.State.IDLE, Updater.State.ERROR], 20.0)
	_check(r["state"] == Updater.State.IDLE, "dijeda ke IDLE", str(r))
	var partial_size := Util.file_size(tmp)
	_check(partial_size > 0, "berkas sementara tersimpan", str(partial_size))
	var full_size := int(pkg.get("size", 0))
	_check(partial_size < full_size, "berkas sementara belum lengkap",
		"%d / %d" % [partial_size, full_size])

	Updater.start()
	var r2 := await _wait_state([Updater.State.READY, Updater.State.ERROR], 60.0)
	_check(r2["state"] == Updater.State.READY, "lanjut sampai READY", str(r2))
	_check(_transcript_has("dilanjutkan dari") or _transcript_has("Melanjutkan"),
		"log menunjukkan resume")
	_check(Store.active_version() == "2.0.0", "versi 2.0.0 aktif", Store.active_version())


func _scenario_bad_hash() -> void:
	Updater.start()
	var r := await _wait_state([Updater.State.READY, Updater.State.ERROR])
	_check(r["state"] == Updater.State.ERROR, "berakhir di ERROR", str(r))
	_check(String(r["ctx"].get("kind", "")) == "hash", "jenis kesalahan hash",
		String(r["ctx"].get("kind", "")))
	_check(String(r["ctx"].get("detail", "")).contains("SHA-256"), "pesan menyebut SHA-256",
		String(r["ctx"].get("detail", "")))
	_check(Util.list_files(Cfg.partial_dir()).size() == 0, "berkas .tmp rusak dihapus")
	_check(Store.active_version() == "", "tidak ada versi aktif setelah gagal",
		Store.active_version())


func _scenario_offline() -> void:
	var r1 := await _install(_base() + "/manifests/v100.json")
	_check(r1["state"] == Updater.State.READY, "pasang 1.0.0 dulu", str(r1))
	var r := await _install("http://127.0.0.1:1/version.json", 30.0)
	_check(r["state"] == Updater.State.OFFLINE_READY, "state OFFLINE_READY", str(r))
	_check(bool(r["ctx"].get("can_play", false)), "versi lama tetap bisa dimainkan")
	_check(Store.active_version() == "1.0.0", "masih di 1.0.0", Store.active_version())
	_check(Updater.has_playable_version(), "paket lama utuh")


func _scenario_launcher_too_old() -> void:
	Updater.start()
	var r := await _wait_state([Updater.State.LAUNCHER_UPDATE_REQUIRED, Updater.State.ERROR])
	_check(r["state"] == Updater.State.LAUNCHER_UPDATE_REQUIRED, "butuh launcher baru", str(r))
	_check(not bool(r["ctx"].get("can_play", false)), "belum ada versi untuk dimainkan")


func _scenario_blocked() -> void:
	var r1 := await _install(_base() + "/manifests/v100.json")
	_check(r1["state"] == Updater.State.READY, "pasang 1.0.0 dulu", str(r1))
	Store.block("1.1.0")
	var r := await _install(_base() + "/manifests/v110.json")
	_check(r["state"] == Updater.State.ERROR, "versi yang ditahan tidak dipasang", str(r))
	_check(String(r["ctx"].get("kind", "")) == "blocked", "jenis kesalahan blocked",
		String(r["ctx"].get("kind", "")))
	Updater.retry()
	var r2 := await _wait_state([Updater.State.READY, Updater.State.ERROR], 40.0)
	_check(r2["state"] == Updater.State.READY, "Coba Lagi memaksa pemasangan ulang", str(r2))
	_check(Store.active_version() == "1.1.0", "versi 1.1.0 terpasang", Store.active_version())


func _scenario_startup_rollback() -> void:
	# in-process flavour: healthy 1.0.0 -> broken 1.2.0 "dies" on boot
	var r1 := await _install(_base() + "/manifests/v110.json")
	_check(r1["state"] == Updater.State.READY, "pasang 1.1.0 dulu", str(r1))
	var r2 := await _install(_base() + "/manifests/v120_broken.json")
	_check(r2["state"] == Updater.State.READY, "paket rusak terpasang (rusak saat boot, bukan saat unduh)",
		str(r2))
	_check(Store.active_version() == "1.2.0", "1.2.0 aktif", Store.active_version())
	# the watchdog writes this before handing over to the game:
	Guard.arm("1.2.0")
	var pending := Store.pending_rollback()
	_check(bool(pending.get("needed", false)), "sistem tahu boot belum sehat",
		JSON.stringify(pending))
	var recovered := Guard.handle_startup_rollback()
	_check(recovered, "pemulihan saat start terdeteksi")
	_check(Store.active_version() == "1.1.0", "kembali ke 1.1.0", Store.active_version())
	_check(Store.is_blocked("1.2.0"), "versi rusak ditandai")
	_check(Updater.has_playable_version(), "versi hasil rollback bisa dimainkan")


func _scenario_signed_ok() -> void:
	Updater.start()
	var r := await _wait_state([Updater.State.READY, Updater.State.ERROR], 40.0)
	_check(r["state"] == Updater.State.READY, "manifest bertanda tangan diterima", str(r))
	_check(Store.active_version() == "1.0.0", "versi 1.0.0 terpasang", Store.active_version())


func _scenario_signed_bad() -> void:
	Updater.start()
	var r := await _wait_state([Updater.State.READY, Updater.State.ERROR], 40.0)
	_check(r["state"] == Updater.State.ERROR, "tanda tangan rusak ditolak", str(r))
	_check(Store.active_version() == "", "tidak ada yang terpasang", Store.active_version())


## Real crash path: install a pack that dies on boot, then let the process die.
## The next process (bash case "crash") must recover through the file sentinel.
func _scenario_install_and_boot() -> void:
	Updater.start()
	var r := await _wait_state([Updater.State.READY, Updater.State.ERROR], 40.0)
	_check(r["state"] == Updater.State.READY, "paket rusak tetap terpasang", str(r))
	_check(Store.active_version() == "1.2.0", "versi 1.2.0 aktif", Store.active_version())
	print("BOOTING_BROKEN_PACKS")
	Updater.play()   # the sample game intentionally crashes here
	await get_tree().create_timer(10.0).timeout
	_check(false, "proses seharusnya sudah mati karena paket rusak")


func _scenario_capture() -> void:
	var dir := ""
	for arg in OS.get_cmdline_user_args():
		var a := String(arg)
		if a.begins_with("--captures="):
			dir = a.substr("--captures=".length())
	if dir == "":
		dir = "user://captures"
	DirAccess.make_dir_recursive_absolute(dir)

	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(host)
	var launcher: Control = load("res://scenes/Launcher.tscn").instantiate()
	host.add_child(launcher)
	await get_tree().create_timer(1.6).timeout
	await _shot(dir, "01_menyiapkan")

	var r := await _wait_until(func(): return Updater.state == Updater.State.DOWNLOADING, 40.0)
	_check(r, "masuk fase unduh")
	await _wait_until(func(): return float(Updater.snap.get("percent", 0.0)) > 0.28, 40.0)
	await _shot(dir, "02_mengunduh")

	var r2 := await _wait_state([Updater.State.READY, Updater.State.ERROR], 90.0)
	_check(r2["state"] == Updater.State.READY, "siap dimainkan", str(r2))
	await get_tree().create_timer(0.8).timeout
	await _shot(dir, "03_siap")

	# error state screenshot: force a themed failure
	Updater._fail("Paket characters rusak (SHA-256 tidak cocok) setelah 3 percobaan.", "hash")
	await get_tree().create_timer(0.6).timeout
	await _shot(dir, "04_kendala")

	# offline + rollback modal screenshots
	Updater._set_state(Updater.State.OFFLINE_READY, {
		"message": "Mode luring",
		"detail": "Tidak bisa menghubungi server. Versi 1.0.0 siap dimainkan.",
		"can_retry": true,
		"can_play": true,
		"version": "1.0.0",
	})
	await get_tree().create_timer(0.6).timeout
	await _shot(dir, "05_luring")

	launcher._show_modal("Pemulihan Otomatis",
		"Game tidak merespons dalam 25 detik. Kembali ke versi 1.0.0 yang terakhir stabil.",
		"Mengerti")
	await get_tree().create_timer(0.7).timeout
	await _shot(dir, "06_pemulihan")


func _shot(dir: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := dir.path_join(name + ".png")
	var err := img.save_png(path)
	print("SHOT %s -> %s (err %d, %dx%d)" % [name, path, err, img.get_width(), img.get_height()])
