extends RefCounted
## Data-driven dialogue: the conversation lives in JSON next to the character's
## sprites, not in the code that draws it.
##
## A node is one conversation. Which node the player gets depends on the save:
## flags he set earlier and counters the world raised (orcs defeated, etc.).
## Adding a character's story therefore means adding a JSON entry, exactly like
## adding a character means adding a `.tres` + a PNG.
##
## Shape of the file:
##
##   {
##     "schema": 1,
##     "speaker": "Penjaga Bram",
##     "entry": ["setelah_bersih", "pertemuan", "ulangan"],   // first match wins
##     "nodes": {
##       "pertemuan": {
##         "when":   {"no_flags": ["bram_kenal"]},
##         "pages":  [{"speaker": "Penjaga Bram", "text": "..."}],
##         "choices":[{"label": "...", "reply": "...",
##                     "set_flags": ["bram_janji"]}]
##       }
##     }
##   }
##
## `when` supports: flags, no_flags, min_counters, max_counters. Anything it does
## not understand is ignored on purpose - an unknown condition must not make a
## conversation impossible to reach.
##
## `problems()` is the CI gate: a story with a missing page, an empty choice
## label or an entry node that does not exist fails the build instead of showing
## the player a blank parchment.

const DEFAULT_SPEAKER := "?"

var source := ""
var speaker := DEFAULT_SPEAKER
var entry: Array = []
var nodes: Dictionary = {}

var _problems: Array = []


## Load and validate. Returns "" on success, otherwise a human readable reason.
func parse(path: String) -> String:
	source = path
	if not FileAccess.file_exists(path):
		return "berkas dialog tidak ada: %s" % path
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return "dialog %s bukan JSON objek" % path
	var root: Dictionary = parsed
	var schema := int(root.get("schema", 1))
	if schema > 1:
		return "dialog %s memakai skema %d (kode ini hanya paham 1)" % [path, schema]
	speaker = String(root.get("speaker", DEFAULT_SPEAKER))
	var raw_entry: Variant = root.get("entry", [])
	entry = raw_entry if typeof(raw_entry) == TYPE_ARRAY else []
	var raw_nodes: Variant = root.get("nodes", {})
	nodes = raw_nodes if typeof(raw_nodes) == TYPE_DICTIONARY else {}
	_problems = _collect_problems()
	return ""


func _fail(reason: String) -> void:
	_problems.append(reason)


func _collect_problems() -> Array:
	var out: Array = []
	if entry.is_empty():
		out.append("%s: daftar entry kosong" % source)
	if nodes.is_empty():
		out.append("%s: tidak ada node percakapan" % source)
	for id in entry:
		if not nodes.has(String(id)):
			out.append("%s: entry '%s' tidak ada di nodes" % [source, String(id)])
	for id in nodes.keys():
		var node: Dictionary = nodes[id]
		var pages: Array = node.get("pages", [])
		if pages.is_empty():
			out.append("%s: node '%s' tidak punya halaman" % [source, String(id)])
		for page in pages:
			var text := ""
			if typeof(page) == TYPE_DICTIONARY:
				text = String((page as Dictionary).get("text", ""))
			elif typeof(page) == TYPE_STRING:
				text = String(page)
			if text.strip_edges() == "":
				out.append("%s: node '%s' punya halaman kosong" % [source, String(id)])
		var choices: Array = node.get("choices", [])
		for i in range(choices.size()):
			var choice: Dictionary = choices[i]
			if String(choice.get("label", "")).strip_edges() == "":
				out.append("%s: node '%s' pilihan %d tanpa label" % [source, String(id), i])
			if String(choice.get("reply", "")).strip_edges() == "":
				out.append("%s: node '%s' pilihan %d tanpa balasan" % [source, String(id), i])
	return out


func problems() -> Array:
	return _problems


## Which conversation does this player get right now?
func pick(save: RefCounted) -> Dictionary:
	for id in entry:
		var node_id := String(id)
		if not nodes.has(node_id):
			continue
		var node: Dictionary = nodes[node_id]
		if _matches(node.get("when", {}), save):
			return _node_result(node_id, node)
	# Nothing matched: fall back to the last entry so the guard always speaks.
	if not entry.is_empty():
		var fallback := String(entry[entry.size() - 1])
		if nodes.has(fallback):
			return _node_result(fallback, nodes[fallback])
	return {}


func _node_result(id: String, node: Dictionary) -> Dictionary:
	var pages: Array = []
	for raw in node.get("pages", []):
		if typeof(raw) == TYPE_DICTIONARY:
			var page: Dictionary = raw
			pages.append({
				"speaker": String(page.get("speaker", speaker)),
				"text": String(page.get("text", "")),
			})
		else:
			pages.append({"speaker": speaker, "text": String(raw)})
	var choices: Array = []
	for raw in node.get("choices", []):
		var choice: Dictionary = raw
		choices.append({
			"label": String(choice.get("label", "")),
			"reply": String(choice.get("reply", "")),
			"set_flags": choice.get("set_flags", []),
		})
	return {
		"id": id,
		"speaker": speaker,
		"pages": pages,
		"choices": choices,
		"set_flags": node.get("set_flags", []),
	}


func _matches(when: Variant, save: RefCounted) -> bool:
	if typeof(when) != TYPE_DICTIONARY:
		return true
	var cond: Dictionary = when
	# A missing save is a valid state (first frame); treat it as "nothing done".
	var flags: Array = cond.get("flags", [])
	for flag in flags:
		if not bool(save.call("has_flag", String(flag))):
			return false
	var no_flags: Array = cond.get("no_flags", [])
	for flag in no_flags:
		if bool(save.call("has_flag", String(flag))):
			return false
	var min_counters: Dictionary = cond.get("min_counters", {})
	for key in min_counters.keys():
		if int(save.call("get_counter", String(key))) < int(min_counters[key]):
			return false
	var max_counters: Dictionary = cond.get("max_counters", {})
	for key in max_counters.keys():
		if int(save.call("get_counter", String(key))) > int(max_counters[key]):
			return false
	return true
