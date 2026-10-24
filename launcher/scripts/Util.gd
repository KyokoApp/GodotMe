class_name Util
extends RefCounted
## Small dependency-free helpers shared by the launcher and the sample game.


static func read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


static func read_json(path: String) -> Dictionary:
	var text := read_text(path)
	if text.strip_edges() == "":
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


static func write_text_atomic(path: String, text: String) -> bool:
	var dir := path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.flush()
	f = null
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(tmp, path) == OK


static func write_json_atomic(path: String, value: Dictionary) -> bool:
	return write_text_atomic(path, JSON.stringify(value, "  "))


static func parse_json_text(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "JSON tidak valid.", "value": {}}
	return {"ok": true, "error": "", "value": parsed}


static func human_size(bytes: int) -> String:
	if bytes < 0:
		return "-"
	var b := float(bytes)
	if b < 1024.0:
		return "%d B" % int(b)
	if b < 1024.0 * 1024.0:
		return "%.1f KB" % (b / 1024.0)
	if b < 1024.0 * 1024.0 * 1024.0:
		var mb := b / (1024.0 * 1024.0)
		return ("%.1f MB" % mb).replace(".", ",")
	var gb := b / (1024.0 * 1024.0 * 1024.0)
	return ("%.2f GB" % gb).replace(".", ",")


static func human_speed(bytes_per_sec: float) -> String:
	if bytes_per_sec <= 1.0:
		return "-"
	return human_size(int(bytes_per_sec)) + "/s"


static func human_eta(seconds: float) -> String:
	if seconds <= 0.0 or seconds > 86400.0:
		return "-"
	var s := int(seconds)
	if s < 60:
		return "%d dtk" % s
	var m := s / 60
	var rest := s % 60
	if m < 60:
		return "%d mnt %02d dtk" % [m, rest]
	var h := m / 60
	return "%d jam %02d mnt" % [h, m % 60]


static func is_hex64(s: String) -> bool:
	if s.length() != 64:
		return false
	for c in s:
		var ok := (c >= "0" and c <= "9") or (c >= "a" and c <= "f") or (c >= "A" and c <= "F")
		if not ok:
			return false
	return true


static func looks_like_url(s: String) -> bool:
	return s.begins_with("https://") or s.begins_with("http://") \
		or s.begins_with("file://") or s.begins_with("res://") \
		or s.begins_with("user://") or s.begins_with("/")


## Resolve a possibly-relative package URL against the manifest's own URL.
static func resolve_url(base_url: String, maybe_relative: String) -> String:
	if maybe_relative.begins_with("http://") or maybe_relative.begins_with("https://") \
			or maybe_relative.begins_with("file://") or maybe_relative.begins_with("res://") \
			or maybe_relative.begins_with("user://"):
		return maybe_relative
	# root-absolute URLs inherit the manifest's origin
	if maybe_relative.begins_with("/"):
		var scheme_end := base_url.find("://")
		if scheme_end > 0:
			var authority_end := base_url.find("/", scheme_end + 3)
			if authority_end > 0:
				return base_url.substr(0, authority_end) + maybe_relative
		return maybe_relative
	# plain relative path: resolve against the manifest's own directory
	var slash := base_url.rfind("/")
	var scheme_pos := base_url.find("://")
	if slash <= scheme_pos + 2:
		return maybe_relative
	return base_url.substr(0, slash + 1) + maybe_relative


static func file_size(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var n := f.get_length()
	f = null
	return n


static func now_iso() -> String:
	return Time.get_datetime_string_from_system(true) + "Z"


static func short_hash(h: String) -> String:
	return h.substr(0, 8) if h.length() >= 8 else h


## Directory size in bytes (recursive, best effort).
static func dir_size(path: String) -> int:
	var total := 0
	var d := DirAccess.open(path)
	if d == null:
		return 0
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name != "." and name != "..":
			var full := path.path_join(name)
			if d.current_is_dir():
				total += dir_size(full)
			else:
				total += file_size(full)
		name = d.get_next()
	d.list_dir_end()
	return total


static func list_files(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(path)
	if d == null:
		return out
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name != "." and name != ".." and not d.current_is_dir():
			out.append(name)
		name = d.get_next()
	d.list_dir_end()
	return out


static func list_dirs(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(path)
	if d == null:
		return out
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name != "." and name != ".." and d.current_is_dir():
			out.append(name)
		name = d.get_next()
	d.list_dir_end()
	return out


static func free_space(path: String) -> int:
	var d := DirAccess.open(path)
	if d == null:
		return -1
	return d.get_space_left()
