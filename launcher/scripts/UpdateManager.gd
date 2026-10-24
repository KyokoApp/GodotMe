extends Node
## UpdateManager.gd - the whole check -> delta download -> verify -> install ->
## load pipeline (autoload "Updater"). UI listens to three signals and never
## touches the network itself.

enum State {
	IDLE,
	CHECKING,
	DOWNLOADING,
	VERIFYING,
	INSTALLING,
	READY,
	OFFLINE_READY,
	ERROR,
	LAUNCHER_UPDATE_REQUIRED,
}

signal state_changed(state: int, ctx: Dictionary)
signal progress_changed(snap: Dictionary)
signal plan_ready(manifest: Dictionary, plan: Array)

var state: int = State.IDLE
var ctx: Dictionary = {}
var snap: Dictionary = {}
var manifest: Dictionary = {}
var plan: Array = []
var manifest_url: String = ""

var _running := false
var _cancel := false
var _speed_bps := 0.0
var _speed_bytes := 0
var _speed_ms := 0
var _bytes_done := 0
var _bytes_total := 0
var _current_pkg := ""
var _pkg_count := 0
var _pkg_index := 0


func _ready() -> void:
	set_process(false)


# --------------------------------------------------------------- public API --
func start() -> void:
	if _running:
		return
	_cancel = false
	_run()


func retry() -> void:
	Store.unblock_all()
	if _running:
		cancel()
		await get_tree().create_timer(0.15).timeout
	start()


func cancel() -> void:
	_cancel = true


func play() -> void:
	## Boot whatever version is active. Safe to call from the Main button.
	var meta := Store.active_meta()
	if meta.is_empty():
		_fail("Belum ada versi game yang terpasang.", "no_install")
		return
	Log.info("Menyiapkan boot versi %s." % String(meta.get("version", "")))
	Guard.arm(String(meta.get("version", "")))
	var loader := PackLoader.new()
	var res := loader.boot_version(meta)
	if not res["ok"]:
		Guard.disarm(false)
		Log.error(String(res["error"]))
		var restored := Store.rollback()
		Guard.pending_notice = "%s%s" % [String(res["error"]),
			(" Kembali ke versi %s." % restored) if restored != "" else " Tidak ada versi cadangan."]
		_set_state(State.ERROR, {
			"message": "Gagal membuka game.",
			"detail": String(res["error"]),
			"kind": "boot",
			"can_retry": true,
			"can_play": Store.has_version(Store.active_version()),
		})
		return
	Log.ok("Game dimulai dari %s." % String(res["main_scene"]))


func local_version() -> String:
	return Store.active_version()


func has_playable_version() -> bool:
	return Store.has_version(Store.active_version())


# ------------------------------------------------------------------ pipeline --
func _run() -> void:
	_running = true
	_cancel = false
	Store.ensure()

	var local_version := Store.active_version()
	_set_state(State.CHECKING, {
		"message": "Mencari kabar dari kerajaan…",
		"detail": "Menghubungi server pembaruan",
		"can_retry": false,
		"can_play": has_playable_version(),
		"version": local_version,
	})

	var fetched := await _fetch_manifest()
	if _cancel:
		_finish_cancel()
		return

	if not fetched["ok"]:
		Log.warn("Manifest gagal diambil: %s" % String(fetched["error"]))
		var cache := _cached_manifest()
		if local_version != "" and has_playable_version():
			manifest = cache.get("data", {})
			_set_state(State.OFFLINE_READY, {
				"message": "Mode luring",
				"detail": "Tidak bisa menghubungi server. Versi %s siap dimainkan." % local_version,
				"error": String(fetched["error"]),
				"can_retry": true,
				"can_play": true,
				"version": local_version,
			})
		else:
			_set_state(State.ERROR, {
				"message": "Tidak bisa memeriksa pembaruan.",
				"detail": String(fetched["error"]) + " Periksa koneksi internet lalu coba lagi.",
				"kind": "network",
				"can_retry": true,
				"can_play": false,
				"version": "",
			})
		_running = false
		return

	manifest = fetched["data"]
	manifest_url = fetched["url"]
	plan_ready.emit(manifest, [])

	# 1. launcher compatibility gate -----------------------------------------
	var min_ver := Manifest.min_launcher_version(manifest)
	if min_ver > Cfg.LAUNCHER_VERSION:
		Log.warn("Manifest butuh launcher v%d, kita v%d." % [min_ver, Cfg.LAUNCHER_VERSION])
		_set_state(State.LAUNCHER_UPDATE_REQUIRED, {
			"message": "Pembaruan aplikasi diperlukan",
			"detail": "Game versi %s membutuhkan launcher v%d. Unduh APK baru dari kanal resmi. Versi terpasang masih bisa dimainkan." % [
				Manifest.version(manifest), min_ver],
			"can_retry": true,
			"can_play": has_playable_version(),
			"version": local_version,
			"remote_version": Manifest.version(manifest),
		})
		_running = false
		return

	# 2. compare with what is installed --------------------------------------
	var remote_version := Manifest.version(manifest)
	var active_meta := Store.active_meta()
	var plan_list := _build_plan(manifest, active_meta)
	var changed: Array = plan_list.filter(func(p): return bool(p.get("changed", true)))
	plan = plan_list
	plan_ready.emit(manifest, plan_list)

	if Store.is_blocked(remote_version):
		_set_state(State.ERROR, {
			"message": "Versi %s ditahan" % remote_version,
			"detail": "Versi ini gagal dimuat sebelumnya, jadi pembaruan ditahan agar game tidak berulang kali gagal. Tekan Coba Lagi untuk mencoba memasangnya sekali lagi.",
			"kind": "blocked",
			"can_retry": true,
			"can_play": has_playable_version(),
			"version": local_version,
			"remote_version": remote_version,
			"changelog": Manifest.changelog_lines(manifest),
		})
		_running = false
		return

	if changed.is_empty() and local_version == remote_version and has_playable_version():
		Log.ok("Sudah versi terbaru: %s." % local_version)
		_set_state(State.READY, {
			"message": "Semua sudah siap",
			"detail": "Versi %s terpasang dan terverifikasi." % local_version,
			"can_retry": false,
			"can_play": true,
			"version": local_version,
			"up_to_date": true,
			"changelog": Manifest.changelog_lines(manifest),
		})
		_running = false
		return

	# 3. free space ----------------------------------------------------------
	var need := 0
	for pkg in changed:
		need += int(pkg.get("size", 0)) - Util.file_size(Store.partial_path(pkg))
	need = max(0, need) + Cfg.MIN_FREE_SPACE_MARGIN
	var free := Util.free_space(Cfg.data_root())
	if free > 0 and free < need:
		_set_state(State.ERROR, {
			"message": "Ruang penyimpanan kurang",
			"detail": "Butuh sekitar %s, tersisa %s. Kosongkan penyimpanan lalu coba lagi." % [
				Util.human_size(need), Util.human_size(free)],
			"kind": "storage",
			"can_retry": true,
			"can_play": has_playable_version(),
			"version": local_version,
		})
		_running = false
		return

	# 4. download -----------------------------------------------------------
	_set_state(State.DOWNLOADING, {
		"message": "Mengunduh pembaruan",
		"detail": "%d paket berubah dari %d." % [changed.size(), plan_list.size()],
		"can_retry": false,
		"can_play": has_playable_version(),
		"version": remote_version,
		"changelog": Manifest.changelog_lines(manifest),
	})
	_bytes_total = 0
	for pkg in changed:
		_bytes_total += int(pkg.get("size", 0))
	_bytes_done = 0
	_speed_bps = 0.0
	_speed_bytes = 0
	_speed_ms = Time.get_ticks_msec()
	_pkg_count = changed.size()
	_pkg_index = 0

	for pkg in changed:
		if _cancel:
			_finish_cancel()
			return
		var ok := await _download_package(pkg, changed.size())
		if not ok:
			if _cancel:
				_finish_cancel()
				return
			_running = false
			return
		_bytes_done += int(pkg.get("size", 0))
		_pkg_index += 1
		_emit_progress(true)

	# 5. install ------------------------------------------------------------
	_set_state(State.INSTALLING, {
		"message": "Memasang pembaruan",
		"detail": "Menyusun versi %s…" % remote_version,
		"can_retry": false,
		"can_play": has_playable_version(),
		"version": remote_version,
	})

	var meta := {
		"version": remote_version,
		"installed_at": Util.now_iso(),
		"main_scene": Manifest.main_scene(manifest),
		"min_launcher_version": min_ver,
		"packages": [],
		"manifest": manifest,
	}
	for pkg in plan_list:
		var entry := {
			"name": String(pkg.get("name", "")),
			"sha256": String(pkg.get("sha256", "")),
			"size": int(pkg.get("size", 0)),
			"load_order": int(pkg.get("load_order", 0)),
		}
		if not Store.pack_ready(entry):
			_fail("Paket %s tidak lengkap setelah pemasangan." % String(entry["name"]), "install")
			_running = false
			return
		meta["packages"].append(entry)

	Store.activate(meta)
	Guard.disarm(true)
	Store.gc()


	_set_state(State.READY, {
		"message": "Pembaruan selesai",
		"detail": "Versi %s siap dimainkan." % remote_version,
		"can_retry": false,
		"can_play": true,
		"version": remote_version,
		"up_to_date": true,
		"changelog": Manifest.changelog_lines(manifest),
	})
	Log.ok("Pemasangan selesai: %s" % remote_version)
	_running = false
	return


# ---------------------------------------------------------------- manifest ---
func _fetch_manifest() -> Dictionary:
	var urls: Array[String] = []
	var primary := Cfg.manifest_url()
	urls.append(primary)
	if Cfg.MANIFEST_URL_FALLBACK != "":
		urls.append(Cfg.MANIFEST_URL_FALLBACK)

	var last_error := "Alamat manifest belum diatur."
	for url in urls:
		if url.strip_edges() == "":
			continue
		Log.info("Mengambil manifest: %s" % url)
		var res: Dictionary = await Http.fetch_text(url, Cfg.HTTP_CONNECT_TIMEOUT_S)
		if _cancel:
			return {"ok": false, "error": "Dibatalkan."}
		if not res["ok"]:
			last_error = String(res["error"])
			Log.warn("Gagal: %s" % last_error)
			continue
		var text := String(res.get("body", ""))
		var parsed := Util.parse_json_text(text)
		if not parsed["ok"]:
			last_error = "Manifest bukan JSON yang valid."
			continue
		var data: Dictionary = parsed["value"]
		var valid := Manifest.validate(data)
		if not valid["ok"]:
			last_error = String(valid["error"])
			continue
		if data.has("game") and String(data["game"]) != Cfg.GAME_ID:
			last_error = "Manifest milik game lain (%s)." % String(data["game"])
			continue
		var sig := await _fetch_signature(url)
		if Cfg.require_signature():
			if sig == "":
				last_error = "Manifest tidak ditandatangani padahal tanda tangan wajib."
				Log.error(last_error)
				continue
			var vr := Manifest.verify_signature_bytes(
				PackedByteArray(String(res.get("body", "")).to_utf8_buffer()), sig,
				Cfg.PUBLIC_KEY_PATH)
			if not vr["ok"]:
				last_error = String(vr["error"])
				Log.error("Verifikasi tanda tangan gagal: %s" % last_error)
				continue
			Log.ok("Tanda tangan manifest valid.")
		elif sig != "":
			var vr2 := Manifest.verify_signature_bytes(
				PackedByteArray(String(res.get("body", "")).to_utf8_buffer()), sig,
				Cfg.PUBLIC_KEY_PATH)
			if vr2["ok"]:
				Log.ok("Tanda tangan manifest valid.")
			else:
				Log.warn("Tanda tangan manifest tidak bisa diverifikasi: %s" % String(vr2["error"]))
		# cache for offline display
		Util.write_json_atomic(Cfg.manifest_cache_file(), {
			"url": url,
			"fetched_at": Util.now_iso(),
			"data": data,
		})
		return {"ok": true, "error": "", "data": data, "url": url, "text": text}
	return {"ok": false, "error": last_error}


## version.json.sig is optional; a missing one simply means "unsigned".
func _fetch_signature(manifest_url_value: String) -> String:
	var res: Dictionary = await Http.fetch_text(manifest_url_value + ".sig", 10.0, 65536)
	if not res["ok"]:
		return ""
	var txt := String(res.get("body", "")).strip_edges()
	# accept both a raw base64 blob and a file with newlines
	txt = txt.replace("\n", "").replace("\r", "").replace(" ", "")
	return txt


func _cached_manifest() -> Dictionary:
	return Util.read_json(Cfg.manifest_cache_file())


# -------------------------------------------------------------------- plan ---
func _build_plan(remote: Dictionary, active_meta: Dictionary) -> Array:
	var installed := {}
	for pkg in active_meta.get("packages", []):
		installed[String(pkg.get("name", ""))] = pkg
	var out: Array = []
	for pkg in Manifest.packages(remote):
		var entry: Dictionary = pkg.duplicate(true)
		entry["url"] = Util.resolve_url(manifest_url, String(pkg.get("url", "")))
		var name := String(pkg.get("name", ""))
		var have: Dictionary = installed.get(name, {})
		var same := (not have.is_empty()) \
			and String(have.get("sha256", "")).to_lower() == String(pkg.get("sha256", "")).to_lower()
		var present := Store.pack_ready(entry)
		entry["changed"] = not (same and present)
		entry["resume_bytes"] = Util.file_size(Store.partial_path(entry))
		out.append(entry)
	return out


# ---------------------------------------------------------------- download ---
func _download_package(pkg: Dictionary, pkg_total: int) -> bool:
	var name := String(pkg.get("name", "?"))
	_current_pkg = name
	var tmp := Store.partial_path(pkg)
	var dest := Store.pack_path(pkg)
	var expected := int(pkg.get("size", 0))
	DirAccess.make_dir_recursive_absolute(tmp.get_base_dir())

	var attempt := 0
	while attempt < Cfg.DOWNLOAD_RETRIES:
		attempt += 1
		var resumed := Util.file_size(tmp)
		if resumed > 0:
			Log.info("Melanjutkan %s dari %s." % [name, Util.human_size(resumed)])
		_set_state(State.DOWNLOADING, {
			"message": "Mengunduh pembaruan",
			"detail": "%s (%s) — paket %d dari %d" % [name, Util.human_size(expected), _pkg_index + 1, pkg_total],
			"can_retry": false,
			"can_play": has_playable_version(),
			"version": Manifest.version(manifest),
			"package": name,
			"attempt": attempt,
			"changelog": Manifest.changelog_lines(manifest),
		})

		var res: Dictionary = await Http.download_to_file(
			String(pkg.get("url", "")), tmp, expected, true,
			func(done: int, total: int): _on_pkg_progress(done, total, expected),
			func(): return _cancel,
			Cfg.HTTP_STALL_TIMEOUT_S)

		if _cancel:
			return false
		if not res["ok"]:
			Log.warn("Percobaan %d/%d gagal untuk %s: %s" % [
				attempt, Cfg.DOWNLOAD_RETRIES, name, String(res["error"])])
			if attempt >= Cfg.DOWNLOAD_RETRIES:
				_fail("Unduhan %s gagal: %s" % [name, String(res["error"])], "download")
				return false
			await get_tree().create_timer(1.2 * attempt).timeout
			continue

		if int(res.get("resumed_from", 0)) > 0:
			Log.info("%s dilanjutkan dari %s." % [name, Util.human_size(int(res["resumed_from"]))])

		# ---- verify --------------------------------------------------------
		_set_state(State.VERIFYING, {
			"message": "Memeriksa keutuhan paket",
			"detail": "%s — SHA-256" % name,
			"can_retry": false,
			"can_play": has_playable_version(),
			"version": Manifest.version(manifest),
			"package": name,
		})
		_emit_progress(true)
		await get_tree().process_frame
		var digest := Hasher.sha256_file(tmp, Cfg.HASH_CHUNK_SIZE)
		var want := String(pkg.get("sha256", "")).to_lower()
		if digest != want:
			Log.error("Hash %s tidak cocok (dapat %s, harus %s). Berkas dihapus." % [name, digest, want])
			DirAccess.remove_absolute(tmp)
			if attempt >= Cfg.DOWNLOAD_RETRIES:
				_fail("Paket %s rusak (SHA-256 tidak cocok) setelah %d percobaan." % [name, attempt], "hash")
				return false
			continue
		Log.ok("SHA-256 %s cocok." % name)

		# ---- move into place ------------------------------------------------
		if FileAccess.file_exists(dest):
			DirAccess.remove_absolute(dest)
		var mv := DirAccess.rename_absolute(tmp, dest)
		if mv != OK:
			_fail("Tidak bisa memindahkan paket %s ke tempatnya." % name, "install")
			return false
		return true
	return false


func _on_pkg_progress(done: int, total: int, expected: int) -> void:
	var now := Time.get_ticks_msec()
	var dt := float(now - _speed_ms) / 1000.0
	if dt >= 0.25:
		var delta := done - _speed_bytes
		if delta < 0:
			delta = 0
		var inst := float(delta) / max(dt, 0.001)
		_speed_bps = inst if _speed_bps <= 0.0 else lerp(_speed_bps, inst, 0.35)
		_speed_bytes = done
		_speed_ms = now
	var pkg_total := expected if expected > 0 else max(total, 1)
	_emit_progress(false, done, pkg_total)


func _emit_progress(force: bool, pkg_done: int = -1, pkg_total: int = -1) -> void:
	var done := _bytes_done
	if pkg_done >= 0:
		done += pkg_done
	var total := max(_bytes_total, 1)
	var pct := clampf(float(done) / float(total), 0.0, 1.0)
	var remaining := max(0, total - done)
	var eta := -1.0
	if _speed_bps > 1024.0:
		eta = float(remaining) / _speed_bps
	snap = {
		"percent": pct,
		"bytes_done": done,
		"bytes_total": total,
		"speed_bps": _speed_bps,
		"eta_s": eta,
		"package": _current_pkg,
		"pkg_done": pkg_done,
		"pkg_total": pkg_total,
		"pkg_index": _pkg_index,
		"pkg_count": _pkg_count,
		"state": state,
	}
	progress_changed.emit(snap)


# ------------------------------------------------------------------ states ---
func _set_state(s: int, c: Dictionary) -> void:
	state = s
	ctx = c
	state_changed.emit(s, c)


func _fail(message: String, kind: String) -> void:
	Log.error(message)
	_set_state(State.ERROR, {
		"message": "Terjadi kendala",
		"detail": message,
		"kind": kind,
		"can_retry": true,
		"can_play": has_playable_version(),
		"version": Store.active_version(),
	})


func _finish_cancel() -> void:
	Log.warn("Dihentikan oleh pengguna.")
	_set_state(State.IDLE, {
		"message": "Dihentikan",
		"detail": "Unduhan dijeda. Tekan Coba Lagi untuk melanjutkan.",
		"can_retry": true,
		"can_play": has_playable_version(),
		"version": Store.active_version(),
	})
	_running = false
