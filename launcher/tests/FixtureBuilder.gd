extends Node
## Builds the test fixtures: six modular .pck files plus a family of manifests.
## Dev tool only - excluded from the exported launcher APK.
##
## Run:
##   godot --headless --path launcher res://tests/FixtureBuilder.tscn -- \
##     --game-dir=/abs/path/to/game --out=/tmp/fixtures [--private-key=priv.pem]

const PACK_FILES := {
	"core": {
		"order": 10,
		"files": [
			"game/Main.tscn",
			"game/Main.gd",
			"game/assets/crest.png",
		],
	},
	"characters": {
		"order": 20,
		"files": ["game/assets/parchment.png"],
	},
	"enemies": {
		"order": 30,
		"files": ["game/assets/divider.png"],
	},
	"world": {
		"order": 40,
		"files": ["game/assets/bg.png"],
	},
	"ui": {
		"order": 50,
		"files": [
			"game/assets/Jacquard12.woff2",
			"game/assets/PixelifySans.woff2",
		],
	},
	"audio": {
		"order": 60,
		"files": [],
	},
}

var game_dir := ""
var out_dir := ""
var private_key_path := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var a := String(arg)
		if a.begins_with("--game-dir="):
			game_dir = a.substr("--game-dir=".length())
		elif a.begins_with("--out="):
			out_dir = a.substr("--out=".length())
		elif a.begins_with("--private-key="):
			private_key_path = a.substr("--private-key=".length())
	if game_dir == "" or out_dir == "":
		printerr("Butuh --game-dir= dan --out=")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out_dir.path_join("packs"))
	DirAccess.make_dir_recursive_absolute(out_dir.path_join("manifests"))
	_build_all()
	get_tree().quit(0)


func _build_all() -> void:
	# ---- v1.0.0 -------------------------------------------------------------
	var v100 := {}
	for name in PACK_FILES.keys():
		var extra := {"%s/stamp.txt" % name: "stamp %s v1.0.0\n" % name}
		if name == "audio":
			extra["audio/silence.txt"] = "placeholder audio payload for the demo pack\n"
		v100[name] = _pack(name, "100", extra)
	_write_manifest("v100", "1.0.0", 1, v100, [
		"Rilis pertama: enam paket modular.",
		"Dunia contoh dimuat dari paket, bukan dari APK.",
	])

	# ---- v1.1.0 : only characters.pck changes -------------------------------
	var v110 := v100.duplicate(true)
	v110["characters"] = _pack("characters", "110",
		{"characters/stamp.txt": "stamp characters v1.1.0\n"})
	_write_manifest("v110", "1.1.0", 1, v110, [
		"Rambut dan jubah karakter diperbarui.",
		"Update ini hanya mengunduh characters.pck.",
	])

	# ---- v1.2.0 : core.pck ships a deliberately broken boot -----------------
	var v120 := v110.duplicate(true)
	v120["core"] = _pack("core", "120", {"game/FAIL_BOOT": "boom\n"})
	_write_manifest("v120_broken", "1.2.0", 1, v120, [
		"Uji rollback: paket core sengaja rusak.",
	])

	# ---- bad hash manifest --------------------------------------------------
	var bad := v110.duplicate(true)
	var ch: Dictionary = bad["characters"].duplicate(true)
	var h := String(ch["sha256"])
	h = ("0" if h[0] != "0" else "1") + h.substr(1)
	ch["sha256"] = h
	bad["characters"] = ch
	_write_manifest("v110_badhash", "1.1.0", 1, bad, ["Uji hash rusak."])

	# ---- launcher too old ---------------------------------------------------
	_write_manifest("v100_toonew", "1.0.0", 99, v100, ["Uji min_launcher_version."])

	# ---- slow single-pack manifest (resume test) ----------------------------
	var slow := {}
	var slow_pack := _pack("world", "slow", {
		"world/stamp.txt": "stamp world slow\n",
	}, "/slow/packs/")
	slow["world"] = slow_pack
	_write_manifest("slow", "2.0.0", 1, slow, ["Uji jeda & lanjut unduhan."])

	# ---- signed manifest ----------------------------------------------------
	if private_key_path != "":
		_write_manifest("v100_signed", "1.0.0", 1, v100, [
			"Manifest bertanda tangan.",
		], true)
		_write_manifest("v100_badsig", "1.0.0", 1, v100, [
			"Manifest dengan tanda tangan rusak.",
		], true, true)

	print("[FIXTURES] selesai di %s" % out_dir)


func _pack(name: String, tag: String, extra_files: Dictionary,
		url_prefix: String = "packs/") -> Dictionary:
	var file_name := "%s_%s.pck" % [name, tag]
	var pck_path := out_dir.path_join("packs").path_join(file_name)
	var pck := PCKPacker.new()
	if pck.pck_start(pck_path, 32) != OK:
		printerr("pck_start gagal: %s" % pck_path)
		return {}
	var spec: Dictionary = PACK_FILES[name]
	for rel in spec["files"]:
		var src := game_dir.path_join(rel)
		if not FileAccess.file_exists(src):
			printerr("Hilang: %s" % src)
			continue
		pck.add_file("res://" + rel, src)
	for target in extra_files.keys():
		var data := String(extra_files[target]).to_utf8_buffer()
		# write a scratch file so add_file can stay the single code path
		var scratch := out_dir.path_join("_scratch.bin")
		var f := FileAccess.open(scratch, FileAccess.WRITE)
		f.store_buffer(data)
		f.flush()
		f = null
		pck.add_file("res://game/" + String(target), scratch)
	pck.flush()

	var size := Util.file_size(pck_path)
	var sha := Hasher.sha256_file(pck_path)
	print("[FIXTURES] %s  %s  %s" % [file_name, Util.human_size(size), sha.substr(0, 12)])
	return {
		"name": name,
		"url": url_prefix + file_name,
		"size": size,
		"sha256": sha,
		"load_order": int(spec["order"]),
	}


func _write_manifest(tag: String, version: String, min_launcher: int,
		packs: Dictionary, changelog: Array, sign: bool = false,
		corrupt_signature: bool = false) -> void:
	var entries: Array = []
	for name in packs.keys():
		var p: Dictionary = packs[name]
		if p.is_empty():
			continue
		entries.append(p)
	var data := {
		"schema": 1,
		"game": Cfg.GAME_ID,
		"version": version,
		"min_launcher_version": min_launcher,
		"released_at": Util.now_iso(),
		"main_scene": "res://game/Main.tscn",
		"changelog": changelog,
		"packages": entries,
	}
	var text := JSON.stringify(data, "  ")
	var path := out_dir.path_join("manifests").path_join(tag + ".json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.flush()
	f = null
	if sign:
		if not FileAccess.file_exists(private_key_path):
			printerr("Kunci privat tidak ada: %s" % private_key_path)
		else:
			var key := CryptoKey.new()
			if key.load_from_string(FileAccess.get_file_as_string(private_key_path)) != OK:
				printerr("Kunci privat tidak valid.")
			else:
				var digest := Manifest.digest_bytes(text.to_utf8_buffer())
				var sig := Crypto.new().sign(HashingContext.HASH_SHA256, digest, key)
				if corrupt_signature and sig.size() > 8:
					sig[4] = (sig[4] + 1) % 256
				var sf := FileAccess.open(path + ".sig", FileAccess.WRITE)
				sf.store_string(Marshalls.raw_to_base64(sig))
				sf.flush()
				sf = null
				print("[FIXTURES] tanda tangan %s (%d bita)%s" % [
					tag, sig.size(), " RUSAK" if corrupt_signature else ""])
	print("[FIXTURES] manifest %s -> %s" % [tag, path])
