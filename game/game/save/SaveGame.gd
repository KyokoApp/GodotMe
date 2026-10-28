extends RefCounted
## Versioned player save. One slot, one JSON file, and a rule that the player
## never loses progress because of a bad write or a future schema.
##
##   user://save/slot1.json       the save
##   user://save/slot1.json.bak   the previous good save
##
## Deliberate choices:
##   * It lives in `user://save/`, NOT inside the launcher's `user://retraveller/`
##     tree. The launcher deletes package files it no longer needs and may wipe
##     a broken version; player progress must survive all of that.
##   * Every write is atomic: `.tmp` -> read back and verify -> rename. A crash
##     mid-save can therefore never leave a half-written file.
##   * Every save carries `schema`. A newer schema than this build understands is
##     left untouched on disk (we start a fresh session in memory instead of
##     destroying somebody's progress from a future version).
##   * Every save carries `sha256` over the sorted payload, and a mismatch falls
##     back to the `.bak` copy.
##
## Version history:
##   0  implicit, never shipped: {flags: {...}} only, no counters, no position
##   1  first shipped schema: flags, counters, player position, play time
##   2  + `fog`: the ground the player has already explored, as the map's own
##      versioned blob (see WorldMap.fog_payload). A schema-1 save simply starts
##      with an empty fog, which is exactly what "never been anywhere" means.
##   3  + `battle`: what step 3C's battles produced - level, EXP, Leaf, HP/SP,
##      the items left, and the weaknesses the party has LEARNED per enemy id
##      (the "?" wall is progress, so it has to survive a reload). A schema-2
##      save loads with an empty battle blob, i.e. a level 1 party with no
##      knowledge, which is exactly what a save from before battles means.

const SAVE_DIR := "user://save"
const SLOT_FILE := "slot1.json"
const BAK_SUFFIX := ".bak"
const TMP_SUFFIX := ".tmp"
const SCHEMA := 3
const GAME_ID := "re-traveller"

var path := ""
var bak_path := ""
var schema := SCHEMA
## Set when the file on disk was written by a newer build: we must not overwrite
## it, so saving is disabled for this session and the player is told.
var read_only := false
var recovered_from_backup := false
var migrated_from := -1

var _flags: Dictionary = {}
var _counters: Dictionary = {}
var _position := Vector2.ZERO
var _has_position := false
var _play_time_s := 0.0
## Explored map ground, kept as an opaque dictionary: the save does not need to
## know what a tile is, only how to carry it safely between runs.
var _fog: Dictionary = {}
## Battle progress (step 3C), also opaque: level, EXP, Leaf, HP/SP, inventory and
## the weakness table the party has learned.
var _battle: Dictionary = {}


func _init(dir: String = "") -> void:
	# An explicit folder wins (tests); then RT_SAVE_DIR (QA builds on a device);
	# then the real slot. Same code everywhere, no #if test flags.
	if dir == "":
		dir = OS.get_environment("RT_SAVE_DIR")
	if dir == "":
		dir = SAVE_DIR
	path = dir.path_join(SLOT_FILE)
	bak_path = path + BAK_SUFFIX


# ------------------------------------------------------------------ loading --
## Read the slot from disk. Never fails loudly: a fresh game is better than a
## crash, and the reason is kept for the caller to log.
func load_game() -> String:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var primary := _read(path)
	if primary.ok:
		_absorb(primary.data)
		return "save_dibaca"
	# A damaged primary is expected once in a while (killed process, full disk).
	# The backup exists for exactly that.
	var backup := _read(bak_path)
	if backup.ok:
		_absorb(backup.data)
		recovered_from_backup = true
		return "save_dipulihkan_dari_cadangan"
	_absorb({})
	return "save_baru" if not FileAccess.file_exists(path) else "save_rusak"


## Returns {ok: bool, error: String, data: Dictionary}.
func _read(file: String) -> Dictionary:
	if not FileAccess.file_exists(file):
		return {"ok": false, "error": "tidak ada", "data": {}}
	var text := FileAccess.get_file_as_string(file)
	if text.strip_edges() == "":
		return {"ok": false, "error": "kosong", "data": {}}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "bukan JSON objek", "data": {}}
	var data: Dictionary = parsed
	var stamp := String(data.get("sha256", ""))
	if stamp != "" and stamp != _hash_of(data):
		return {"ok": false, "error": "sidik jari tidak cocok", "data": {}}
	if String(data.get("game", GAME_ID)) != GAME_ID:
		return {"ok": false, "error": "milik game lain", "data": {}}
	var file_schema := int(data.get("schema", 0))
	if file_schema > SCHEMA:
		# Do not migrate downwards and do not overwrite: this build is older than
		# the file. The player can still play; their newer progress stays intact.
		read_only = true
		return {"ok": false, "error": "skema %d lebih baru" % file_schema, "data": {}}
	if file_schema < SCHEMA:
		data = _migrate(data, file_schema)
		migrated_from = file_schema
	return {"ok": true, "error": "", "data": data}


## Migration chain. Each step upgrades one schema version and is small on
## purpose - a migration that needs more than a few lines is a redesign.
func _migrate(data: Dictionary, from_version: int) -> Dictionary:
	var out := data.duplicate(true)
	var v := from_version
	if v < 1:
		# schema 0 kept only flags; counters and position simply did not exist.
		if not out.has("counters"):
			out["counters"] = {}
		if not out.has("position"):
			out["position"] = {}
		v = 1
	if v < 2:
		# schema 2 added the explored ground; an older save has seen nothing.
		if not out.has("fog"):
			out["fog"] = {}
		v = 2
	if v < 3:
		# schema 3 added the battle blob: no battles fought, nothing learned.
		if not out.has("battle"):
			out["battle"] = {}
		v = 3
	out["schema"] = v
	return out


func _absorb(data: Dictionary) -> void:
	_flags = {}
	var flags: Variant = data.get("flags", {})
	if typeof(flags) == TYPE_DICTIONARY:
		for key in (flags as Dictionary).keys():
			if bool(flags[key]):
				_flags[String(key)] = true
	_counters = {}
	var counters: Variant = data.get("counters", {})
	if typeof(counters) == TYPE_DICTIONARY:
		for key in (counters as Dictionary).keys():
			_counters[String(key)] = int(counters[key])
	var pos: Variant = data.get("position", {})
	if typeof(pos) == TYPE_DICTIONARY and (pos as Dictionary).has("x"):
		_position = Vector2(float(pos["x"]), float(pos["z"] if pos.has("z") else 0.0))
		_has_position = true
	else:
		_position = Vector2.ZERO
		_has_position = false
	_play_time_s = float(data.get("play_time_s", 0.0))
	var fog: Variant = data.get("fog", {})
	_fog = fog if typeof(fog) == TYPE_DICTIONARY else {}
	var battle: Variant = data.get("battle", {})
	_battle = battle if typeof(battle) == TYPE_DICTIONARY else {}


# ------------------------------------------------------------------ queries --
func has_flag(flag: String) -> bool:
	return _flags.has(flag)


func flag_list() -> Array:
	var out: Array = _flags.keys()
	out.sort()
	return out


func get_counter(name: String) -> int:
	return int(_counters.get(name, 0))


func counter_list() -> Dictionary:
	return _counters.duplicate()


func has_position() -> bool:
	return _has_position


func player_position() -> Vector2:
	return _position


func play_time() -> float:
	return _play_time_s


## The explored-ground blob as written last time. Empty for a new game or for a
## save that predates the map.
func fog() -> Dictionary:
	return _fog.duplicate(true)


func set_fog(payload: Dictionary) -> void:
	_fog = payload.duplicate(true)


func has_fog() -> bool:
	return not _fog.is_empty()


## Battle progress as last written. Empty for a save from before step 3C.
func battle() -> Dictionary:
	return _battle.duplicate(true)


func set_battle(payload: Dictionary) -> void:
	_battle = payload.duplicate(true)


func has_battle() -> bool:
	return not _battle.is_empty()


# ------------------------------------------------------------------ changes --
func set_flag(flag: String, on: bool = true) -> void:
	if on:
		_flags[flag] = true
	else:
		_flags.erase(flag)


func add_counter(name: String, amount: int = 1) -> int:
	var value := get_counter(name) + amount
	_counters[name] = value
	return value


func set_counter(name: String, value: int) -> void:
	_counters[name] = value


func set_player_position(pos: Vector2) -> void:
	_position = pos
	_has_position = true


func add_play_time(seconds: float) -> void:
	_play_time_s = maxf(0.0, _play_time_s + seconds)


# ------------------------------------------------------------------- saving --
## Snapshot as it is written to disk (sorted keys so the hash is stable).
func to_dictionary() -> Dictionary:
	var pos := {}
	if _has_position:
		pos = {"x": _position.x, "z": _position.y}
	var payload := {
		"game": GAME_ID,
		"schema": SCHEMA,
		"saved_at": Time.get_datetime_string_from_system(true),
		"flags": _flags.duplicate(true),
		"counters": _counters.duplicate(true),
		"position": pos,
		"play_time_s": _play_time_s,
		"fog": _fog.duplicate(true),
		"battle": _battle.duplicate(true),
	}
	payload["sha256"] = _hash_of(payload)
	return payload


## Atomic write: temp file, verified by reading it back, then renamed.
## Returns "" on success or a short reason.
func save_now() -> String:
	if read_only:
		return "save hanya-baca (berkas dari versi lebih baru)"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var text := JSON.stringify(to_dictionary(), "  ", true)
	var tmp := path + TMP_SUFFIX
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return "tidak bisa menulis %s" % tmp
	f.store_string(text + "\n")
	f.flush()
	f = null
	# verify before touching the real slot: a truncated write must not win
	var check := FileAccess.get_file_as_string(tmp)
	if check != text + "\n":
		DirAccess.remove_absolute(tmp)
		return "verifikasi tulis gagal"
	if FileAccess.file_exists(path):
		# keep the last *valid* save as the backup
		var current := _read(path)
		if current.ok:
			DirAccess.copy_absolute(path, bak_path)
	if DirAccess.rename_absolute(tmp, path) != OK:
		DirAccess.remove_absolute(tmp)
		return "gagal mengganti berkas save"
	return ""


## Delete both files (used by tests and by a future "mulai ulang" button).
func erase() -> void:
	for file in [path, bak_path, path + TMP_SUFFIX]:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)


# -------------------------------------------------------------------- utils --
func _hash_of(data: Dictionary) -> String:
	var copy := data.duplicate(true)
	copy.erase("sha256")
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(JSON.stringify(_canonical(copy), "", true).to_utf8_buffer())
	return ctx.finish().hex_encode()


## Numbers are normalised before hashing. JSON has one number type but GDScript
## has two, and a value written as int 2 can come back as float 2.0 - hashing the
## raw dictionary would then reject our own save file. Everything is turned into
## a fixed-precision string first, so writer and reader always agree.
func _canonical(value: Variant) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			var out := {}
			for key in (value as Dictionary).keys():
				out[String(key)] = _canonical(value[key])
			return out
		TYPE_ARRAY:
			var list: Array = []
			for item in (value as Array):
				list.append(_canonical(item))
			return list
		TYPE_INT, TYPE_FLOAT:
			return "%.3f" % float(value)
		_:
			return value
