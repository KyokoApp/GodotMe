extends Node
## Headless gate for the character data, run before anything is built:
##
##   godot --headless --path game res://game/tests/ValidateCharacters.tscn
##
## It fails (exit 1) on: a missing definition, a strip whose width is not
## `frames x frame_width`, an empty frame, a zero fps animation, a pivot outside
## the frame, or an animation that did not make it into SpriteFrames. It also
## prints the stride arithmetic that keeps the feet from sliding.

const CharacterAssets := preload("res://game/characters/CharacterAssets.gd")

const DEF_DIR := "res://game/characters/data/"
const IDS := ["knight", "soldier", "orc"]


func _ready() -> void:
	var problems := 0
	for id in IDS:
		var path: String = DEF_DIR + String(id) + ".tres"
		if not ResourceLoader.exists(path):
			print("[VALIDATE] FAIL %s tidak ada" % path)
			problems += 1
			continue
		var def: Resource = load(path)
		var found := CharacterAssets.problems_for(def)
		found.append_array(CharacterAssets.empty_frames(def))

		var frames := CharacterAssets.build_frames(def)
		var anims := frames.get_animation_names()
		if anims.is_empty():
			found.append("%s: SpriteFrames kosong" % id)
		for anim in anims:
			if frames.get_frame_count(anim) <= 0:
				found.append("%s/%s: 0 frame di SpriteFrames" % [id, anim])

		var walk_speed := float(def.call("locomotion_speed", "walk"))
		var walk_entry: Dictionary = def.call("anim_entry", "walk")
		var cycle := 0.0
		if not walk_entry.is_empty():
			cycle = float(walk_entry.get("frames", 1)) / maxf(1.0, float(walk_entry.get("fps", 10.0)))
		var slip := 0.0
		if cycle > 0.0:
			slip = (walk_speed * cycle) / maxf(0.001, float(def.get("walk_stride_m")))

		print("[VALIDATE] %-8s %2d anim  %5.2f m  pivot %s  langkah %.2f m/s x %.2f s = %.2f m (rasio %.3f)" % [
			id, anims.size(), float(def.call("height_m")), str(def.get("pivot")),
			walk_speed, cycle, walk_speed * cycle, slip])

		for raw in found:
			print("[VALIDATE] FAIL %s" % String(raw))
		problems += found.size()

	if problems == 0:
		print("[VALIDATE] karakter OK: semua strip utuh, semua animasi termuat")
	else:
		print("[VALIDATE] karakter GAGAL: %d masalah" % problems)
	get_tree().quit(0 if problems == 0 else 1)
