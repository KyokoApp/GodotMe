extends RefCounted
## Player settings, kept apart from the save.
##
## Settings belong to the *device*, not to a story: turning the tilt-shift off
## must not touch progress, and wiping progress must not turn the blur back on.
## They live in `user://settings.json`, outside both `user://save/` and the
## launcher's data tree, so Periksa Lagi never resets what the player chose.
##
## Same discipline as SaveGame: schema number, defaults for missing keys, and a
## corrupt file falls back to defaults instead of crashing the boot.

const SCHEMA := 1
const FILE_NAME := "settings.json"
const QUALITIES := ["rendah", "sedang", "tinggi"]

const DEFAULTS := {
	"tilt_shift": true,
	"shake": true,
	"quality": "sedang",
}

var values := {}
var path := "user://settings.json"
var note := ""


func _init(dir: String = "") -> void:
	# Tests point this at a scratch folder; the game uses the player's home.
	if dir == "":
		dir = OS.get_environment("RT_SETTINGS_DIR")
	if dir == "":
		dir = "user://"
	path = dir.path_join(FILE_NAME)
	reset()


## Back to factory values (the button in the settings page uses this indirectly,
## through individual toggles).
func reset() -> void:
	values = DEFAULTS.duplicate(true)


func load_settings() -> String:
	reset()
	if not FileAccess.file_exists(path):
		note = "settings baru"
		return note
	var raw := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		note = "settings rusak, memakai bawaan"
		push_warning("[UI] settings tidak terbaca, memakai bawaan: %s" % path)
		return note
	var data: Dictionary = parsed
	var schema := int(data.get("schema", 0))
	if schema > SCHEMA:
		# A newer build wrote these. Do not guess at fields we do not know and do
		# not overwrite them: play on with defaults this session, leave the file.
		note = "settings dari versi lebih baru, hanya-baca"
		return note
	for key in DEFAULTS.keys():
		if data.has(key):
			set_value(key, data[key])
	note = "settings dibaca"
	return note


func save() -> String:
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var payload := {
		"schema": SCHEMA,
		"tilt_shift": bool(values.get("tilt_shift", true)),
		"shake": bool(values.get("shake", true)),
		"quality": String(values.get("quality", "sedang")),
	}
	var err := OK
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("[UI] settings tidak bisa ditulis: %s" % path)
		return "gagal menulis settings"
	f.store_string(JSON.stringify(payload, "  "))
	f.flush()
	f = null
	return "" if err == OK else "gagal menulis settings"


func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))


## Values are validated on the way in, not on the way out: nothing downstream
## has to re-check that "quality" is one of three words.
func set_value(key: String, value: Variant) -> bool:
	match key:
		"tilt_shift", "shake":
			values[key] = bool(value)
			return true
		"quality":
			var q := String(value)
			if not QUALITIES.has(q):
				return false
			values[key] = q
			return true
	return false


func quality() -> String:
	return String(values.get("quality", "sedang"))


## Next quality in the cycle; the settings button uses this.
func cycle_quality() -> String:
	var i := QUALITIES.find(quality())
	var next: String = QUALITIES[(i + 1) % QUALITIES.size()]
	values["quality"] = next
	return next


## Blur strength for the current quality (0 = no tilt-shift at all).
func tilt_blur() -> float:
	if not bool(get_value("tilt_shift")):
		return 0.0
	match quality():
		"rendah":
			return 1.2
		"tinggi":
			return 2.8
		_:
			return 2.0


## Multiplier for particle counts: weak phones pay less for atmosphere.
func atmosphere_scale() -> float:
	match quality():
		"rendah":
			return 0.35
		"tinggi":
			return 1.35
		_:
			return 1.0


func shadows_enabled() -> bool:
	return quality() != "rendah"
