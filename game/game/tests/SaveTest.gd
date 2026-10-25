extends Node
## Headless gate for the save contract. Everything here is about the promise
## "progress is never lost", which is not something a screenshot can prove:
##
##   * round trip: what was written comes back
##   * atomic write: a failed write never destroys the previous save
##   * damage: a corrupted file falls back to the backup instead of starting over
##   * versioning: an old schema is migrated, a *newer* one is left untouched
##   * persistence outside the launcher's tree: the save lives in user://save/
##
##   godot --headless --path game res://game/tests/SaveTest.tscn
##
## Exit code 1 on any failure, so CI refuses to ship a broken save layer.

const SAVE_SCRIPT := "res://game/save/SaveGame.gd"
const TEST_DIR := "user://savetest"

var failures := 0
var checks := 0


func _ready() -> void:
	await get_tree().process_frame
	if not ResourceLoader.exists(SAVE_SCRIPT):
		_check(false, "skrip save ada", SAVE_SCRIPT)
		_finish()
		return
	_reset_dir()
	await _test_round_trip()
	await _test_atomic_write_keeps_previous()
	await _test_corruption_falls_back_to_backup()
	await _test_migration_from_v0()
	await _test_newer_schema_is_untouched()
	await _test_not_inside_launcher_tree()
	_finish()


func _finish() -> void:
	print("[SAVE] %d pemeriksaan, %d gagal" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)


func _check(cond: bool, label: String, extra: String = "") -> void:
	checks += 1
	if cond:
		print("[SAVE] PASS %s" % label)
	else:
		failures += 1
		print("[SAVE] FAIL %s %s" % [label, extra])


func _reset_dir() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		var f := TEST_DIR.path_join("slot1.json" + suffix)
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	DirAccess.make_dir_recursive_absolute(TEST_DIR)


func _new_save() -> RefCounted:
	return (load(SAVE_SCRIPT) as Script).new(TEST_DIR)


func _write_raw(file: String, text: String) -> void:
	var f := FileAccess.open(file, FileAccess.WRITE)
	f.store_string(text)
	f.flush()
	f = null


func _read_dict(file: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _test_round_trip() -> void:
	_reset_dir()
	var a := _new_save()
	_check(String(a.call("load_game")) == "save_baru", "slot kosong = permainan baru",
		String(a.call("load_game")))
	a.call("set_flag", "bram_kenal")
	a.call("set_flag", "bram_janji")
	a.call("add_counter", "orcs_defeated", 2)
	a.call("set_player_position", Vector2(3.5, -1.25))
	a.call("add_play_time", 12.5)
	_check(String(a.call("save_now")) == "", "save berhasil ditulis")

	var b := _new_save()
	var note := String(b.call("load_game"))
	_check(note == "save_dibaca", "save dibaca kembali", note)
	_check(bool(b.call("has_flag", "bram_kenal")), "flag tersimpan")
	_check(not bool(b.call("has_flag", "bram_tanya")), "flag yang tidak diset tetap kosong")
	_check(int(b.call("get_counter", "orcs_defeated")) == 2, "counter tersimpan",
		str(b.call("get_counter", "orcs_defeated")))
	var pos: Vector2 = b.call("player_position")
	_check(absf(pos.x - 3.5) < 0.01 and absf(pos.y + 1.25) < 0.01,
		"posisi pemain tersimpan", str(pos))
	_check(absf(float(b.call("play_time")) - 12.5) < 0.01, "waktu bermain tersimpan",
		str(b.call("play_time")))
	_check(not FileAccess.file_exists(TEST_DIR.path_join("slot1.json.tmp")),
		"berkas sementara dibersihkan setelah sukses")


## The write path must never leave a half file where the good one was.
func _test_atomic_write_keeps_previous() -> void:
	_reset_dir()
	var a := _new_save()
	a.call("load_game")
	a.call("set_counter", "orcs_defeated", 1)
	a.call("save_now")
	a.call("set_counter", "orcs_defeated", 2)
	a.call("save_now")
	_check(FileAccess.file_exists(TEST_DIR.path_join("slot1.json.bak")),
		"cadangan dibuat saat menimpa save lama")
	# simulate the interrupted write: a stray .tmp must be ignored on load
	_write_raw(TEST_DIR.path_join("slot1.json.tmp"), "{\"schema\": 1, \"flags\"")
	var b := _new_save()
	_check(String(b.call("load_game")) == "save_dibaca", "berkas .tmp tidak dipakai")
	_check(int(b.call("get_counter", "orcs_defeated")) == 2, "isi save terakhir dipakai",
		str(b.call("get_counter", "orcs_defeated")))


func _test_corruption_falls_back_to_backup() -> void:
	_reset_dir()
	var a := _new_save()
	a.call("load_game")
	a.call("set_counter", "orcs_defeated", 1)
	a.call("save_now")
	a.call("add_counter", "orcs_defeated", 1)   # 2 -> 2 triggers .bak of "1"
	a.call("save_now")
	a.call("add_counter", "orcs_defeated", 1)
	a.call("save_now")
	# now damage the primary: truncated JSON, the classic kill -9 result
	_write_raw(TEST_DIR.path_join("slot1.json"), "{\"schema\": 1, \"flags\": {")
	var b := _new_save()
	var note := String(b.call("load_game"))
	_check(note == "save_dipulihkan_dari_cadangan", "save rusak dipulihkan dari cadangan",
		note)
	_check(int(b.call("get_counter", "orcs_defeated")) == 2,
		"isi cadangan yang dipakai (2, bukan 3 yang rusak)",
		str(b.call("get_counter", "orcs_defeated")))


func _test_migration_from_v0() -> void:
	_reset_dir()
	# schema 0: the shape a build before versioning would have written
	_write_raw(TEST_DIR.path_join("slot1.json"),
		"{\"game\": \"re-traveller\", \"schema\": 0, \"flags\": {\"bram_kenal\": true}}")
	var a := _new_save()
	var note := String(a.call("load_game"))
	_check(note == "save_dibaca", "save skema 0 tetap terbaca", note)
	_check(int(a.get("migrated_from")) == 0, "migrasi dicatat", str(a.get("migrated_from")))
	_check(bool(a.call("has_flag", "bram_kenal")), "flag lama ikut pindah")
	_check(int(a.call("get_counter", "orcs_defeated")) == 0,
		"counter baru mulai dari nol, bukan crash")
	_check(String(a.call("save_now")) == "", "hasil migrasi bisa disimpan lagi")
	var on_disk := _read_dict(TEST_DIR.path_join("slot1.json"))
	# the migration chain runs all the way to the current schema, fog included
	_check(int(on_disk.get("schema", -1)) == 2, "berkas kini berskema 2",
		str(on_disk.get("schema")))
	_check(typeof(on_disk.get("fog", null)) == TYPE_DICTIONARY,
		"save lama mendapat fog kosong", str(on_disk.get("fog", "tidak ada")))


## A save from a newer build must survive: we do not understand it, so we must
## not overwrite it with our older shape.
func _test_newer_schema_is_untouched() -> void:
	_reset_dir()
	var future := "{\"game\": \"re-traveller\", \"schema\": 99, \"flags\": {\"raja_hidup\": true}}"
	_write_raw(TEST_DIR.path_join("slot1.json"), future)
	var a := _new_save()
	var note := String(a.call("load_game"))
	_check(bool(a.get("read_only")), "skema lebih baru ditandai hanya-baca", note)
	var error := String(a.call("save_now"))
	_check(error != "", "menyimpan ditolak saat hanya-baca", error)
	var still_there := FileAccess.get_file_as_string(TEST_DIR.path_join("slot1.json"))
	_check(still_there == future, "berkas versi baru tidak diubah sama sekali")


func _test_not_inside_launcher_tree() -> void:
	# The launcher deletes package files under user://retraveller/ when it rolls
	# back or installs a new version. Player progress must not live there.
	var a := _new_save()
	a.call("load_game")
	_check(not String(a.get("path")).begins_with("user://retraveller"),
		"save berada di luar pohon data peluncur", String(a.get("path")))
	_check(String(a.get("path")).begins_with("user://save"), "lokasi save: user://save/",
		String(a.get("path")))
