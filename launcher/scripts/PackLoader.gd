class_name PackLoader
extends RefCounted
## Loads a version's packages into the resource filesystem, in manifest order.
##
## Contract: every game file lives under res://game/ . That guarantees a package
## can never shadow a launcher file (UI, fonts, config), which in turn makes
## rollback-after-boot-failure safe to do inside the same process.


func load_version(meta: Dictionary) -> Dictionary:
	if meta.is_empty():
		return {"ok": false, "error": "Catatan versi tidak ditemukan."}
	var packages: Array = meta.get("packages", [])
	if packages.is_empty():
		return {"ok": false, "error": "Versi ini tidak memuat paket apa pun."}
	# The game runs inside this process, so an environment variable is a channel
	# that needs no file and no parsing. Without it the game had to *guess* the
	# installed version from a hardcoded path - and guess a default when that
	# file lived somewhere else. Both ends now agree by construction. Set here,
	# in the one function every boot path goes through (boot_version and the
	# tests both call it).
	OS.set_environment("RT_ACTIVE_VERSION", String(meta.get("version", "")))
	OS.set_environment("RT_DATA_ROOT", Cfg.data_root())

	var ordered := packages.duplicate()
	ordered.sort_custom(func(a, b): return int(a.get("load_order", 0)) < int(b.get("load_order", 0)))

	var loaded: Array[String] = []
	for pkg in ordered:
		var path := Store.pack_path(pkg)
		if not FileAccess.file_exists(path):
			_unload(loaded)
			return {"ok": false, "error": "Paket hilang: %s" % path.get_file()}
		if not ProjectSettings.load_resource_pack(path, true):
			_unload(loaded)
			return {"ok": false, "error": "Paket rusak / tidak bisa dimuat: %s" % path.get_file()}
		loaded.append(path)
		Log.info("Paket dimuat: %s (%s)" % [String(pkg.get("name", "?")), Util.human_size(int(pkg.get("size", 0)))])

	var main_scene := String(meta.get("main_scene", ""))
	if not main_scene.begins_with("res://game/"):
		_unload(loaded)
		return {"ok": false, "error": "main_scene harus berada di res://game/ (ditemukan: %s)." % main_scene}
	if not ResourceLoader.exists(main_scene):
		_unload(loaded)
		return {"ok": false, "error": "Scene utama tidak ditemukan di dalam paket: %s" % main_scene}
	return {"ok": true, "error": "", "main_scene": main_scene, "loaded": loaded}


func boot_version(meta: Dictionary) -> Dictionary:
	var res := load_version(meta)
	if not res["ok"]:
		return res

	var tree := Engine.get_main_loop() as SceneTree
	var err := tree.change_scene_to_file(String(res["main_scene"]))
	if err != OK:
		return {"ok": false, "error": "Gagal membuka scene utama (kode %d)." % err}
	return res


func _unload(paths: Array[String]) -> void:
	for p in paths:
		if ProjectSettings.load_resource_pack(p, false):
			Log.warn("Paket dilepas: %s" % p.get_file())
