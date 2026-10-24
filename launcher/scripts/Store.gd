extends Node
## Store.gd - installed-version bookkeeping (autoload "Store").
##
## Layout under user://retraveller/
##   active.json               {"version","previous","pending_boot","installed_at"}
##   versions/<version>.json   per-version package list (active + 1 previous kept)
##   packs/<name>-<sha12>.pck  content-addressed package files (shared by versions)
##   partial/<name>-<sha12>.tmp
##   boot_ok.json              written by the GAME once its first frame is up
##
## Packages are content addressed, so "update one biome" only ever adds one file
## and rollback keeps working without duplicating unchanged packages.

signal active_changed(active: Dictionary)


func _ready() -> void:
	ensure()


func ensure() -> void:
	Cfg.ensure_dirs()


# ------------------------------------------------------------------ active ---
func active() -> Dictionary:
	var d := Util.read_json(Cfg.active_file())
	if d.is_empty():
		return {"version": "", "previous": "", "pending_boot": false}
	return {
		"version": String(d.get("version", "")),
		"previous": String(d.get("previous", "")),
		"pending_boot": bool(d.get("pending_boot", false)),
		"installed_at": String(d.get("installed_at", "")),
		"blocked": d.get("blocked", []),
	}


func write_active(d: Dictionary) -> void:
	Util.write_json_atomic(Cfg.active_file(), d)
	active_changed.emit(active())


func active_version() -> String:
	return String(active().get("version", ""))


func previous_version() -> String:
	return String(active().get("previous", ""))


func active_meta() -> Dictionary:
	return version_meta(active_version())


# ------------------------------------------------------------ version metas --
func version_meta_path(version: String) -> String:
	return Cfg.versions_dir().path_join(version + ".json")


func version_meta(version: String) -> Dictionary:
	if version == "":
		return {}
	return Util.read_json(version_meta_path(version))


func save_version_meta(meta: Dictionary) -> void:
	var v := String(meta.get("version", ""))
	if v == "":
		return
	Util.write_json_atomic(version_meta_path(v), meta)


func installed_versions() -> Array[String]:
	var out: Array[String] = []
	for f in Util.list_files(Cfg.versions_dir()):
		if f.ends_with(".json"):
			out.append(f.trim_suffix(".json"))
	out.sort()
	return out


func has_version(version: String) -> bool:
	if version == "":
		return false
	var meta := version_meta(version)
	if meta.is_empty():
		return false
	for pkg in meta.get("packages", []):
		if not FileAccess.file_exists(pack_path(pkg)):
			return false
	return true


# ------------------------------------------------------------------- packs ---
func pack_file_name(pkg: Dictionary) -> String:
	var sha := String(pkg.get("sha256", ""))
	return "%s-%s.pck" % [String(pkg.get("name", "pack")), Util.short_hash(sha)]


func pack_path(pkg: Dictionary) -> String:
	return Cfg.packs_dir().path_join(pack_file_name(pkg))


func partial_path(pkg: Dictionary) -> String:
	return Cfg.partial_dir().path_join(pack_file_name(pkg) + ".tmp")


func pack_ready(pkg: Dictionary) -> bool:
	var p := pack_path(pkg)
	var expected := int(pkg.get("size", 0))
	return FileAccess.file_exists(p) and (expected <= 0 or Util.file_size(p) == expected)


## Activate a fully-downloaded version.
func activate(meta: Dictionary) -> void:
	var version := String(meta.get("version", ""))
	var prev := active_version()
	if prev == version:
		prev = previous_version()
	save_version_meta(meta)
	write_active({
		"version": version,
		"previous": prev,
		"pending_boot": false,
		"installed_at": Util.now_iso(),
	})
	Log.ok("Versi aktif: %s (sebelumnya: %s)" % [version, prev if prev != "" else "-"])


func blocked_versions() -> Array:
	var d := Util.read_json(Cfg.active_file())
	var arr: Array = d.get("blocked", [])
	return arr


func is_blocked(version: String) -> bool:
	return blocked_versions().has(version)


func block(version: String) -> void:
	if version == "":
		return
	var d := active()
	var arr: Array = blocked_versions()
	if not arr.has(version):
		arr.append(version)
	d["blocked"] = arr
	write_active(d)
	Log.warn("Versi %s ditandai bermasalah." % version)


func unblock_all() -> void:
	var d := active()
	if d.get("blocked", []).is_empty():
		return
	d["blocked"] = []
	write_active(d)


func mark_boot_pending(flag: bool) -> void:
	var d := active()
	d["pending_boot"] = flag
	write_active(d)


# ------------------------------------------------------------ boot sentinel --
func boot_ok_version() -> String:
	var d := Util.read_json(Cfg.boot_ok_file())
	return String(d.get("version", ""))


func write_boot_ok(version: String) -> void:
	Util.write_json_atomic(Cfg.boot_ok_file(), {
		"version": version,
		"at": Util.now_iso(),
		"schema": 1,
	})


func clear_boot_ok() -> void:
	if FileAccess.file_exists(Cfg.boot_ok_file()):
		DirAccess.remove_absolute(Cfg.boot_ok_file())


## True when the game was launched last time but never reported a healthy boot.
func pending_rollback() -> Dictionary:
	var a := active()
	if not bool(a.get("pending_boot", false)):
		return {"needed": false}
	if boot_ok_version() == String(a.get("version", "")):
		return {"needed": false}
	return {
		"needed": true,
		"version": String(a.get("version", "")),
		"previous": String(a.get("previous", "")),
	}


## Go back one version. Returns the version now active ("" when impossible).
func rollback() -> String:
	var a := active()
	var prev := String(a.get("previous", ""))
	var broken := String(a.get("version", ""))
	clear_boot_ok()
	if prev == "" or not has_version(prev):
		write_active({"version": "", "previous": "", "pending_boot": false, "installed_at": ""})
		Log.error("Rollback gagal: tidak ada versi sebelumnya yang utuh.")
		return ""
	var blocked: Array = blocked_versions()
	if broken != "" and not blocked.has(broken):
		blocked.append(broken)
	write_active({
		"version": prev,
		"previous": "",
		"pending_boot": false,
		"installed_at": Util.now_iso(),
		"blocked": blocked,
	})
	Log.warn("Rollback dari %s ke %s." % [broken, prev])
	# the broken version's meta stays on disk until the next successful install
	gc()
	return prev


# ---------------------------------------------------------------------- gc ---
## Delete package files and version metas that no kept version references.
func gc() -> void:
	var keep: Array[String] = []
	var a := active_version()
	var p := previous_version()
	if a != "":
		keep.append(a)
	if p != "" and not keep.has(p):
		keep.append(p)

	var referenced := {}
	for v in keep:
		var meta := version_meta(v)
		for pkg in meta.get("packages", []):
			referenced[pack_file_name(pkg)] = true

	var packs_dir := Cfg.packs_dir()
	for f in Util.list_files(packs_dir):
		if not referenced.has(f):
			DirAccess.remove_absolute(packs_dir.path_join(f))
			Log.info("Hapus paket tidak terpakai: %s" % f)

	for f in Util.list_files(Cfg.versions_dir()):
		if not f.ends_with(".json"):
			continue
		var v := f.trim_suffix(".json")
		if not keep.has(v):
			DirAccess.remove_absolute(Cfg.versions_dir().path_join(f))
			Log.info("Hapus catatan versi lama: %s" % v)

	# stale partial downloads for packages that are no longer wanted
	for f in Util.list_files(Cfg.partial_dir()):
		if f.ends_with(".tmp") and not referenced.has(f.trim_suffix(".tmp")):
			# keep .tmp for packages we are actively resuming
			pass


## Sum of package sizes actually present on disk for the kept versions.
func disk_usage() -> int:
	return Util.dir_size(Cfg.data_root())
