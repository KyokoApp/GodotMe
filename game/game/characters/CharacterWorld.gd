extends Node3D
## The living layer of the diorama: the knight you steer, the guard who talks,
## and three orcs on patrol.
##
## It is added *inside* the diorama, so it inherits its ground and lighting, and
## it asks the world for the prop footprints instead of guessing them. If the
## world pack is missing it still runs (empty blockers) instead of crashing.
##
## Everything character-specific comes from the `.tres` resources; this script
## only decides where people stand and what the buttons do.

const DEF_PATHS := {
	"knight": "res://game/characters/data/knight.tres",
	"soldier": "res://game/characters/data/soldier.tres",
	"orc": "res://game/characters/data/orc.tres",
}
const ACTOR_SCRIPT := "res://game/characters/Actor.gd"
const NPC_SCRIPT := "res://game/characters/Npc.gd"
const ENEMY_SCRIPT := "res://game/characters/Enemy.gd"
const TOUCH_SCRIPT := "res://game/characters/TouchControls.gd"
const DIALOGUE_SCRIPT := "res://game/characters/DialogueBox.gd"
const FONT_BODY := "res://game/assets/PixelifySans.woff2"

const PLAYER_START := Vector2(3.6, 7.2)
## The guard stands beside the first bend of the path, two steps from where the
## knight starts: the player must be able to tap Bicara without hunting for him.
const NPC_START := Vector2(2.4, 4.2)

## Patrol routes for the three orcs: they are placed away from the path start so
## the first thing the player sees is not a fight.
const ORC_SETUP := [
	{"at": Vector2(9.2, -2.4), "route": [Vector2(9.2, -2.4), Vector2(10.6, 0.4)]},
	{"at": Vector2(7.0, 2.6), "route": [Vector2(7.0, 2.6), Vector2(5.0, 4.4), Vector2(8.8, 4.0)]},
	{"at": Vector2(1.2, -4.6), "route": [Vector2(1.2, -4.6), Vector2(4.0, -4.0)]},
]

const DIALOGUE := {
	"speaker": "Penjaga Bram",
	"pages": [
		"Berhenti sejenak, pengembara. Jalur ini basah oleh embun, bukan darah — setidaknya sampai tadi malam.",
		"Aku Bram, penjaga gerbang lembah. Sejak orc turun dari bukit, kami menghitung langkah sendiri.",
		"Pondok tua itu masih berdiri. Kalau kau hendak ke sana, jangan menyimpang dari jalur.",
	],
	"options": [
		{
			"label": "Ada yang bisa kubantu?",
			"reply": "Bawa pulang kayu bakar dari tepi hutan, dan aku akan mengingat namamu saat gerbang dibuka.",
		},
		{
			"label": "Apa yang mereka cari?",
			"reply": "Besi tua. Atau mungkin batu bara yang dulu kami sembunyikan di bawah pondok. Aku belum berani memeriksanya.",
		},
	],
}

var _defs := {}
var _player: Node3D
var _npc: Node3D
var _orcs: Array = []
var _camera_rig: Node3D
var _controls: Node
var _dialogue: Node
var _toast: Label
var _hint: Label
var _blocker_list: Array = []
var _bounds_rect := Rect2(-12.0, -9.0, 24.0, 18.0)
var _shake := 0.0
var _shake_base := Vector3.ZERO
var _toast_time := 0.0
var _ready_ok := false


func _ready() -> void:
	_defs = _load_defs()
	if _defs.is_empty():
		push_error("[CHAR] tidak ada definisi karakter yang bisa dimuat")
		return
	_wire_ground()
	_spawn_cast()
	_build_ui()
	_wire_camera()
	_ready_ok = true
	var cast := _orcs.size() + (1 if _npc != null else 0) + (1 if _player != null else 0)
	print("[CHAR] siap: %d aktor, %d orc, blocker %d" % [
		cast, _orcs.size(), _blockers_count()])
	_report_cast()


## One line per actor: where they stand, which strip frame is up, and how many
## frames their SpriteFrames actually holds. A missing or empty strip shows up
## in the CI log instead of as an invisible character in a screenshot.
func _report_cast() -> void:
	for actor in [_player, _npc] + _orcs:
		if actor == null or not is_instance_valid(actor):
			continue
		var sp: AnimatedSprite3D = actor.get("sprite")
		if sp == null:
			print("[CHAR] %s TANPA sprite" % actor.name)
			continue
		var frames: SpriteFrames = sp.sprite_frames
		var count := frames.get_frame_count(sp.animation) if frames != null else 0
		print("[CHAR] %-8s pos=%s anim=%s frame=%d/%d pixel=%.4f a=%.2f" % [
			actor.name, str(actor.position), sp.animation, sp.frame, count,
			sp.pixel_size, sp.modulate.a])


func cast_ready() -> bool:
	return _ready_ok


# ------------------------------------------------------------------ setup ----
func _load_defs() -> Dictionary:
	var out := {}
	for key in DEF_PATHS.keys():
		var path := String(DEF_PATHS[key])
		if not ResourceLoader.exists(path):
			push_error("[CHAR] definisi tidak ditemukan: %s" % path)
			continue
		var res: Resource = load(path)
		if res == null:
			push_error("[CHAR] definisi gagal dimuat: %s" % path)
			continue
		out[key] = _as_definition(res, path)
	return out


## A .tres whose `script` did not attach still carries every property. Instead of
## dying on a missing method later, rebuild a proper CharacterDef from those
## values and say so once, loudly.
func _as_definition(res: Resource, path: String) -> Resource:
	if res.get_script() != null:
		return res
	var script: Script = load("res://game/characters/CharacterDef.gd")
	if script == null:
		push_error("[CHAR] CharacterDef.gd tidak bisa dimuat")
		return res
	var def: Resource = script.new()
	for key in ["id", "display_name", "role", "sprite_dir", "frame_size",
			"pixel_scale", "pivot", "body_width_px", "content_height_px",
			"world_pixel_size", "walk_stride_m", "run_stride_m", "body_radius_m",
			"animations"]:
		def.set(key, res.get(key))
	push_warning("[CHAR] %s tanpa skrip; definisi dibangun ulang dari properti" % path)
	return def


func _wire_ground() -> void:
	# the diorama knows where its trees and rocks are; ask it, do not copy it.
	# This has to run before the cast is spawned so each actor is born with its
	# blockers already in place.
	var world := get_parent()
	if world != null and world.has_method("blockers"):
		_blocker_list = world.call("blockers")
	if world != null and world.has_method("ground_rect"):
		var rect: Rect2 = world.call("ground_rect")
		_bounds_rect = rect.grow(-1.2)


func _spawn_cast() -> void:
	_player = _spawn("knight", ACTOR_SCRIPT, PLAYER_START)
	if _player != null:
		_player.name = "Knight"
		_player.connect("attacked", Callable(self, "_on_attacked"))
		_player.connect("hurt", Callable(self, "_on_player_hurt"))

	_npc = _spawn("soldier", NPC_SCRIPT, NPC_START)
	if _npc != null:
		_npc.name = "Penjaga"
		_npc.set("post", NPC_START)
		_npc.set("player", _player)

	for i in range(ORC_SETUP.size()):
		var conf: Dictionary = ORC_SETUP[i]
		var at: Vector2 = conf["at"]
		var orc := _spawn("orc", ENEMY_SCRIPT, at)
		if orc == null:
			continue
		orc.name = "Orc%d" % i
		orc.set("patrol", conf["route"])
		orc.set("player", _player)
		orc.connect("battle_triggered", Callable(self, "_on_battle_triggered"))
		_orcs.append(orc)


func _spawn(def_key: String, script_path: String, at: Vector2) -> Node3D:
	if not _defs.has(def_key):
		return null
	var script: Script = load(script_path)
	if script == null:
		push_error("[CHAR] skrip tidak ada: %s" % script_path)
		return null
	var actor: Node3D = script.new()
	actor.call("setup", _defs[def_key])
	actor.set("blockers", _blocker_list)
	actor.set("bounds", _bounds_rect)
	actor.position = Vector3(at.x, 0.0, at.y)
	add_child(actor)
	return actor


func _blockers_count() -> int:
	return _blocker_list.size()


# --------------------------------------------------------------------- ui ----
func _build_ui() -> void:
	_controls = (load(TOUCH_SCRIPT) as Script).new()
	_controls.name = "TouchControls"
	add_child(_controls)
	_controls.connect("attack_pressed", Callable(self, "_on_attack_pressed"))
	_controls.connect("interact_pressed", Callable(self, "_on_interact_pressed"))

	_dialogue = (load(DIALOGUE_SCRIPT) as Script).new()
	_dialogue.name = "Dialogue"
	add_child(_dialogue)
	_dialogue.connect("closed", Callable(self, "_on_dialogue_closed"))

	var layer := CanvasLayer.new()
	layer.name = "Notices"
	layer.layer = 11
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	_toast = Label.new()
	_toast.add_theme_font_override("font", _font(FONT_BODY))
	_toast.add_theme_font_size_override("font_size", 20)
	_toast.add_theme_color_override("font_color", Color(0.97, 0.92, 0.82))
	_toast.add_theme_color_override("font_shadow_color", Color(0.05, 0.03, 0.02, 0.9))
	_toast.add_theme_constant_override("shadow_outline_size", 5)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.anchor_left = 0.0
	_toast.anchor_right = 1.0
	_toast.anchor_top = 0.0
	_toast.anchor_bottom = 0.0
	_toast.offset_top = 96.0
	_toast.offset_bottom = 132.0
	_toast.modulate.a = 0.0
	root.add_child(_toast)

	_hint = Label.new()
	_hint.add_theme_font_override("font", _font(FONT_BODY))
	_hint.add_theme_font_size_override("font_size", 17)
	_hint.add_theme_color_override("font_color", Color(0.93, 0.87, 0.75))
	_hint.add_theme_color_override("font_shadow_color", Color(0.05, 0.03, 0.02, 0.9))
	_hint.add_theme_constant_override("shadow_outline_size", 4)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.anchor_left = 0.0
	_hint.anchor_right = 1.0
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_top = -206.0
	_hint.offset_bottom = -178.0
	_hint.text = ""
	root.add_child(_hint)


func _wire_camera() -> void:
	var world := get_parent()
	if world == null:
		return
	_camera_rig = world.get_node_or_null("CameraRig") as Node3D
	if _camera_rig == null:
		return
	_shake_base = _camera_rig.rotation_degrees
	if _camera_rig.has_method("set_follow_target"):
		_camera_rig.call("set_follow_target", _player)
	if _controls != null and _controls.has_method("block_rects"):
		_camera_rig.set("touch_blockers", _controls.call("block_rects"))


# ------------------------------------------------------------------ frame ----
func _process(delta: float) -> void:
	if not _ready_ok or _player == null:
		return
	_update_shake(delta)
	_update_toast(delta)
	_update_hint()

	var locked := _dialogue != null and bool(_dialogue.get("is_open"))
	var dir := Vector2.ZERO
	if not locked and _controls != null:
		var stick: Vector2 = _controls.get("stick_vector")
		dir = stick
		var kb := Vector2(Input.get_axis("ui_left", "ui_right"),
			Input.get_axis("ui_up", "ui_down"))
		if kb.length() > 0.1:
			dir = kb
	dir = dir.limit_length(1.0)

	var world_dir := _to_world(dir)
	_player.call("drive", world_dir, dir.length() > 0.55, delta)
	if _player.has_method("set_block") and _controls != null:
		_player.call("set_block", bool(_controls.get("block_held")) and not locked)


## Screen stick -> ground direction, using the camera rig's own yaw so "up"
## always means "away from the viewer" even if the diorama angle changes.
func _to_world(dir: Vector2) -> Vector2:
	if dir.length() < 0.01:
		return Vector2.ZERO
	var bas := Basis.IDENTITY
	if _camera_rig != null:
		bas = _camera_rig.global_transform.basis
	var right := Vector3(bas.x.x, 0.0, bas.x.z)
	var forward := Vector3(-bas.z.x, 0.0, -bas.z.z)
	if right.length() < 0.001:
		right = Vector3.RIGHT
	if forward.length() < 0.001:
		forward = Vector3.FORWARD
	right = right.normalized()
	forward = forward.normalized()
	var move := right * dir.x + forward * (-dir.y)
	var flat := Vector2(move.x, move.z)
	if flat.length() < 0.001:
		return Vector2.ZERO
	return flat.normalized() * dir.length()


func _update_hint() -> void:
	if _hint == null or _npc == null:
		return
	var near := false
	if _npc.has_method("can_talk_to"):
		near = bool(_npc.call("can_talk_to", _player))
	var locked := _dialogue != null and bool(_dialogue.get("is_open"))
	_hint.text = "Tekan Bicara untuk bercakap dengan penjaga" if (near and not locked) else ""
	if _controls != null:
		_controls.set("interact_enabled", near and not locked)


func _on_attack_pressed() -> void:
	if _dialogue != null and bool(_dialogue.get("is_open")):
		return
	if _player != null:
		_player.call("try_attack")


func _on_interact_pressed() -> void:
	if _dialogue == null or bool(_dialogue.get("is_open")):
		return
	if _npc == null or _player == null:
		return
	if not bool(_npc.call("can_talk_to", _player)):
		return
	_dialogue.call("open", String(DIALOGUE["speaker"]), DIALOGUE["pages"],
		DIALOGUE["options"])
	# the parchment covers the right thumb; controls come back when it closes
	if _controls != null and _controls.has_method("show_controls"):
		_controls.call("show_controls", false)


func _on_dialogue_closed() -> void:
	if _controls != null and _controls.has_method("show_controls"):
		_controls.call("show_controls", true)


func _on_attacked(actor: Node3D) -> void:
	_shake = maxf(_shake, 0.35)
	if actor == _player:
		_strike_orcs()


## The knight's sword reaches about a metre and a half in front of him. Only the
## nearest orc takes the hit, so a swing never clears a crowd.
func _strike_orcs() -> void:
	await get_tree().create_timer(0.28).timeout
	if _player == null or not is_instance_valid(_player):
		return
	if bool(_player.call("is_dead")):
		return
	var facing := float(_player.get("facing"))
	var best: Node3D = null
	var best_d := 99.0
	for orc in _orcs:
		if orc == null or not is_instance_valid(orc) or bool(orc.call("is_dead")):
			continue
		var d := Vector2(orc.position.x - _player.position.x, orc.position.z - _player.position.z)
		if d.length() > 1.6:
			continue
		if facing * d.x < -0.25:
			continue
		if d.length() < best_d:
			best_d = d.length()
			best = orc
	if best == null:
		return
	best.call("take_hit")
	var hp := int(best.get("hp")) - 1
	best.set("hp", hp)
	if hp <= 0:
		best.call("die")


func _on_player_hurt(_actor: Node3D) -> void:
	_shake = maxf(_shake, 0.8)


func _on_battle_triggered(_actor: Node3D) -> void:
	_shake = maxf(_shake, 0.9)
	_show_toast("Orc menghadang — pertempuran menyusul.")


func _show_toast(text: String) -> void:
	if _toast == null:
		return
	_toast.text = text
	_toast_time = 2.6


func _update_toast(delta: float) -> void:
	if _toast == null:
		return
	if _toast_time > 0.0:
		_toast_time = maxf(0.0, _toast_time - delta)
		_toast.modulate.a = minf(1.0, _toast.modulate.a + delta * 6.0)
	else:
		_toast.modulate.a = maxf(0.0, _toast.modulate.a - delta * 2.0)


func _update_shake(delta: float) -> void:
	if _camera_rig == null:
		return
	if _shake <= 0.0:
		return
	_shake = maxf(0.0, _shake - delta * 2.4)
	var t := Time.get_ticks_msec() * 0.001
	var amp := _shake * 0.35
	_camera_rig.rotation_degrees = _shake_base + Vector3(
		sin(t * 47.0) * amp, sin(t * 31.0) * amp * 0.6, 0.0)
	if _shake <= 0.0:
		_camera_rig.rotation_degrees = _shake_base


# ------------------------------------------------------------- day / night ---
## Used by VisualTest; the diorama's own defaults are restored for "day".
func set_time_of_day(night: bool) -> void:
	var world := get_parent()
	if world == null:
		return
	var sun := world.get_node_or_null("Sun") as DirectionalLight3D
	var we := world.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if sun != null:
		if night:
			sun.light_color = Color(0.62, 0.72, 1.0)
			sun.light_energy = 0.34
		else:
			sun.light_color = Color(1.0, 0.96, 0.90)
			sun.light_energy = 1.1
	if we == null or we.environment == null:
		return
	var env := we.environment
	if night:
		env.ambient_light_color = Color(0.20, 0.26, 0.44)
		env.ambient_light_energy = 0.34
		env.fog_light_color = Color(0.26, 0.31, 0.45)
		env.background_color = Color(0.13, 0.16, 0.25)
		env.fog_density = 0.006
	else:
		env.ambient_light_color = Color(0.50, 0.56, 0.72)
		env.ambient_light_energy = 0.48
		env.fog_light_color = Color(0.74, 0.68, 0.62)
		env.background_color = Color(0.42, 0.35, 0.30)
		env.fog_density = 0.0045


## Test hook: push the virtual stick without a finger. Used by VisualTest so the
## knight really walks (same code path as the player) instead of being teleported.
## Hooks for the visual test: drive the cast without a fingertip.
func press_interact() -> void:
	_on_interact_pressed()


func teleport_player(to: Vector2) -> void:
	if _player != null:
		_player.position = Vector3(to.x, 0.0, to.y)


func dialogue() -> Node:
	return _dialogue


func set_virtual_stick(v: Vector2) -> void:
	if _controls != null:
		_controls.set("stick_vector", v.limit_length(1.0))


func player() -> Node3D:
	return _player


func npc() -> Node3D:
	return _npc


func orcs() -> Array:
	return _orcs


func _font(path: String) -> Font:
	var f := FontFile.new()
	if f.load_dynamic_font(path) != OK:
		return ThemeDB.fallback_font
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.hinting = TextServer.HINTING_NONE
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return f
