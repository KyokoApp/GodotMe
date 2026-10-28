extends Node
## Headless gate for the story layer:
##
##   * the JSON parses and passes the same `problems()` validation CI runs
##   * every condition path picks the conversation it is supposed to pick, so the
##     guard cannot repeat his first speech forever (or skip straight to the end)
##   * branches carry flags that the save then keeps
##   * the dialogue box shows the speaker of each page, because a two-person
##     exchange is the difference between a conversation and a wall of text
##
##   godot --headless --path game res://game/tests/DialogueTest.tscn

const TREE_SCRIPT := "res://game/dialogue/DialogueTree.gd"
const SAVE_SCRIPT := "res://game/save/SaveGame.gd"
const STORY := "res://game/characters/data/bram.json"
const SAVE_DIR := "user://dialoguetest"

var failures := 0
var checks := 0


func _ready() -> void:
	await get_tree().process_frame
	if not ResourceLoader.exists(TREE_SCRIPT):
		_check(false, "skrip dialog ada", TREE_SCRIPT)
		_finish()
		return
	await _test_story_valid()
	await _test_first_meeting()
	await _test_after_clearing()
	await _test_repeat_visit()
	await _test_choice_flags_reach_the_save()
	await _test_dialogue_box_speakers()
	_finish()


func _finish() -> void:
	print("[DLG] %d pemeriksaan, %d gagal" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)


func _check(cond: bool, label: String, extra: String = "") -> void:
	checks += 1
	if cond:
		print("[DLG] PASS %s" % label)
	else:
		failures += 1
		print("[DLG] FAIL %s %s" % [label, extra])


func _tree() -> RefCounted:
	var tree: RefCounted = (load(TREE_SCRIPT) as Script).new()
	var error := String(tree.call("parse", STORY))
	if error != "":
		_check(false, "dialog bisa dibaca", error)
	return tree


func _save(flags: Array = [], orcs: int = 0) -> RefCounted:
	var s: RefCounted = (load(SAVE_SCRIPT) as Script).new(SAVE_DIR)
	s.call("load_game")
	for flag in flags:
		s.call("set_flag", String(flag), true)
	s.call("set_counter", "orcs_defeated", orcs)
	return s


func _test_story_valid() -> void:
	var tree := _tree()
	var problems: Array = tree.call("problems")
	_check(problems.is_empty(), "cerita lolos validasi", str(problems))
	var nodes: Dictionary = tree.get("nodes")
	_check(nodes.size() >= 3, "ada minimal tiga percakapan berbeda", str(nodes.size()))
	_check((tree.get("entry") as Array).size() >= 2, "ada lebih dari satu titik masuk")


func _test_first_meeting() -> void:
	var tree := _tree()
	var node: Dictionary = tree.call("pick", _save())
	_check(String(node.get("id", "")) == "pertemuan", "pertemuan pertama memakai node 'pertemuan'",
		String(node.get("id", "")))
	_check((node.get("pages", []) as Array).size() >= 4, "minimal empat halaman",
		str((node.get("pages", []) as Array).size()))
	_check((node.get("choices", []) as Array).size() >= 2, "ada minimal satu cabang dua pilihan",
		str((node.get("choices", []) as Array).size()))
	_check((node.get("set_flags", []) as Array).has("bram_kenal"),
		"node pertama menandai dirinya sudah dilihat")


func _test_after_clearing() -> void:
	var tree := _tree()
	var node: Dictionary = tree.call("pick", _save(["bram_kenal"], 3))
	_check(String(node.get("id", "")) == "setelah_bersih",
		"setelah tiga orc, penjaga berganti cerita", String(node.get("id", "")))
	# two orcs down is not enough: the story must not jump ahead
	var early: Dictionary = tree.call("pick", _save(["bram_kenal"], 2))
	_check(String(early.get("id", "")) == "ulangan",
		"dua orc belum membuka cerita akhir", String(early.get("id", "")))


func _test_repeat_visit() -> void:
	var tree := _tree()
	var node: Dictionary = tree.call("pick", _save(["bram_kenal"], 0))
	_check(String(node.get("id", "")) == "ulangan", "kunjungan ulang memakai node 'ulangan'",
		String(node.get("id", "")))
	_check((node.get("pages", []) as Array).size() >= 2, "kunjungan ulang tetap punya isi")


func _test_choice_flags_reach_the_save() -> void:
	var tree := _tree()
	var node: Dictionary = tree.call("pick", _save())
	var choices: Array = node.get("choices", [])
	var chosen: Dictionary = choices[0]
	var flags: Array = chosen.get("set_flags", [])
	_check(not flags.is_empty(), "pilihan pertama membawa flag cerita", str(flags))
	var save := _save(["bram_kenal"])   # the entry node marks itself seen
	for flag in flags:
		save.call("set_flag", String(flag), true)
	_check(bool(save.call("has_flag", String(flags[0]))), "flag pilihan bisa disimpan")
	# ... and a flag that a node requires actually changes what comes next
	var next: Dictionary = tree.call("pick", save)
	_check(String(next.get("id", "")) == "ulangan",
		"setelah bercakap sekali, percakapan pertama tidak diulang",
		String(next.get("id", "")))


func _test_dialogue_box_speakers() -> void:
	var box: CanvasLayer = (load("res://game/characters/DialogueBox.gd") as Script).new()
	add_child(box)
	await get_tree().process_frame
	var pages := [
		{"speaker": "Penjaga Bram", "text": "Jalur itu sunyi lagi."},
		{"speaker": "Ksatria", "text": "Pondok tua itu masih terkunci."},
	]
	box.call("open", "Penjaga Bram", pages, [])
	await get_tree().process_frame
	var name_label: Label = box.get("_name_label")
	var text: Label = box.get("_text")
	_check(name_label.text == "Penjaga Bram", "nama pembicara halaman pertama",
		name_label.text)
	_check(text.text.contains("sunyi"), "teks halaman pertama tampil", text.text)
	# advance to the second page: the knight is now the one talking
	box.call("advance")
	box.call("advance")   # first tap finishes the typing, second one moves on
	await get_tree().process_frame
	_check(name_label.text == "Ksatria", "nama pembicara mengikuti halaman", name_label.text)
	_check(text.text.contains("terkunci"), "teks halaman kedua tampil", text.text)
	box.queue_free()
