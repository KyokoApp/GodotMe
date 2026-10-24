extends Node
## Log.gd - ring buffer + file log (autoload "Log").
## The CI test harness greps stdout for the "[LOGGER]" marker lines.

signal line_added(entry: Dictionary)

const LEVELS := ["info", "warn", "error", "ok"]

var _entries: Array[Dictionary] = []
var _file: FileAccess = null
var _max_entries: int = 300


func _ready() -> void:
	Cfg.ensure_dirs()
	_open_file()


func _open_file() -> void:
	var path: String = Cfg.logs_dir().path_join("launcher.log")
	# keep one rotated log so user:// never grows unbounded
	if FileAccess.file_exists(path):
		var size := FileAccess.get_file_as_string(path).length()
		if size > 512 * 1024:
			DirAccess.remove_absolute(Cfg.logs_dir().path_join("launcher.prev.log"))
			DirAccess.rename_absolute(path, Cfg.logs_dir().path_join("launcher.prev.log"))
	_file = FileAccess.open(path, FileAccess.WRITE)


func log_line(text: String, level: String = "info") -> void:
	if not LEVELS.has(level):
		level = "info"
	var entry := {
		"t": Time.get_time_string_from_system(),
		"level": level,
		"text": text,
	}
	_entries.append(entry)
	if _entries.size() > _max_entries:
		_entries = _entries.slice(_entries.size() - _max_entries)
	print("[LOGGER] %s %s" % [level.to_upper(), text])
	if _file != null:
		_file.store_line("%s [%s] %s" % [entry["t"], level, text])
		_file.flush()
	line_added.emit(entry)


func info(t: String) -> void:
	log_line(t, "info")


func warn(t: String) -> void:
	log_line(t, "warn")


func error(t: String) -> void:
	log_line(t, "error")


func ok(t: String) -> void:
	log_line(t, "ok")


func entries() -> Array[Dictionary]:
	return _entries.duplicate()


func tail(n: int) -> Array[Dictionary]:
	return _entries.slice(max(0, _entries.size() - n))
