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
			"game/ui/UiKit.gd",
			"game/ui/Settings.gd",
		],
	},
	"characters": {
		"order": 20,
		# every character script, definition and strip: this is the package a
		# sprite update replaces on its own, without touching world or core.
		"files": [
			"game/characters/CharacterDef.gd",
			"game/characters/CharacterAssets.gd",
			"game/characters/Actor.gd",
			"game/characters/Enemy.gd",
			"game/characters/Npc.gd",
			"game/characters/CharacterWorld.gd",
			"game/characters/TouchControls.gd",
			"game/characters/DialogueBox.gd",
			"game/characters/blob_shadow.gdshader",
			"game/characters/dust_puff.gdshader",
			"game/characters/data/knight.tres",
			"game/characters/data/soldier.tres",
			"game/characters/data/orc.tres",
			# the guard's story and the player's save live with the cast: the
			# story is data (editable without touching code) and the save is the
			# progress of the characters that story is about.
			"game/characters/data/bram.json",
			"game/dialogue/DialogueTree.gd",
			"game/save/SaveGame.gd",
			"game/assets/characters/knight/LICENSE.txt",
			"game/assets/characters/soldier/SOURCE.txt",
			"game/assets/characters/orc/SOURCE.txt",
			"game/assets/characters/knight/idle.png",
			"game/assets/characters/knight/walk.png",
			"game/assets/characters/knight/run.png",
			"game/assets/characters/knight/attack_1.png",
			"game/assets/characters/knight/attack_2.png",
			"game/assets/characters/knight/attack_3.png",
			"game/assets/characters/knight/block.png",
			"game/assets/characters/knight/hurt.png",
			"game/assets/characters/knight/death.png",
			"game/assets/characters/knight/jump_start.png",
			"game/assets/characters/knight/jump_transition.png",
			"game/assets/characters/knight/jump_fall.png",
			"game/assets/characters/soldier/idle.png",
			"game/assets/characters/soldier/walk.png",
			"game/assets/characters/soldier/attack_1.png",
			"game/assets/characters/soldier/attack_2.png",
			"game/assets/characters/soldier/attack_3.png",
			"game/assets/characters/soldier/hurt.png",
			"game/assets/characters/soldier/death.png",
			"game/assets/characters/soldier/arrow_100.png",
			"game/assets/characters/soldier/arrow_32.png",
			"game/assets/characters/orc/idle.png",
			"game/assets/characters/orc/walk.png",
			"game/assets/characters/orc/attack_1.png",
			"game/assets/characters/orc/attack_2.png",
			"game/assets/characters/orc/hurt.png",
			"game/assets/characters/orc/death.png",
		],
	},
	"enemies": {
		"order": 30,
		"files": ["game/assets/divider.png"],
	},
	"world": {
		"order": 40,
		# the whole diorama lives in this pack: scene, camera and every texture.
		"files": [
			"game/world/Diorama.tscn",
			"game/world/Diorama.gd",
			"game/world/DioramaCamera.gd",
			"game/world/WorldArt.gd",
			"game/world/WorldClock.gd",
			"game/world/Atmosphere.gd",
			"game/world/tiltshift.gdshader",
			"game/world/path.gdshader",
			"game/world/textures/tree_pine.png",
			"game/world/textures/tree_oak.png",
			"game/world/textures/cottage.png",
			"game/world/textures/bush.png",
			"game/world/textures/rock.png",
			"game/world/textures/grass_tile.png",
			"game/world/textures/path_tile.png",
			"game/world/textures/atmosphere/mote_dust.png",
			"game/world/textures/atmosphere/firefly.png",
			"game/world/textures/atmosphere/petal.png",
			"game/world/textures/atmosphere/fog_puff.png",
		],
	},
	"ui": {
		"order": 50,
		"files": [
			# every UI asset lives here, so a UI pass never forces a core download
			"game/assets/PixelifySans.woff2",
			"game/assets/PixelifySans-SemiBold.woff2",
			"game/assets/parchment.png",
			"game/assets/crest.png",
			"game/assets/divider.png",
			"game/assets/ui/icons/heart_full.png",
			"game/assets/ui/icons/heart_empty.png",
			"game/assets/ui/icons/sun.png",
			"game/assets/ui/icons/moon.png",
			"game/assets/ui/icons/gear.png",
			"game/assets/ui/icons/save.png",
			"game/assets/ui/icons/arrow_left.png",
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
	# release-folder layout: version.json sits next to packs/
	var root_copy := out_dir.path_join(tag + ".json")
	var rf := FileAccess.open(root_copy, FileAccess.WRITE)
	rf.store_string(text)
	rf.flush()
	rf = null
	if sign and FileAccess.file_exists(path + ".sig"):
		DirAccess.copy_absolute(path + ".sig", root_copy + ".sig")
	print("[FIXTURES] manifest %s -> %s (+ root copy)" % [tag, path])
