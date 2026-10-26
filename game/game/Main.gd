extends Control
## Re - Traveller : boot shell and the field.
##
## Its jobs, in order:
##   1. report a healthy boot to the launcher (user://retraveller/boot_ok.json);
##   2. build the diorama and the cast, each out of its own pack;
##   3. show the field HUD (almost nothing) and the one menu;
##   4. keep the player's settings wired to the renderer.
##
## Step 1 changed only the third job. The valley, the packs, the save and the
## rollback path are untouched: the HUD used to be a stack of large parchment
## boxes with the objective, the hearts, a narrative paragraph and an FPS line on
## screen at all times. All of that is now in the menu (Jurnal), and the field is
## a minimap, one menu button and one contextual action button.
##
## The world owns the numbers; this script only moves them between the cast, the
## HUD, the menu and the settings file.

const DIORAMA := "res://game/world/Diorama.tscn"
const TILT_SHIFT := "res://game/world/tiltshift.gdshader"

const FONT_BODY := "res://game/assets/PixelifySans.woff2"
const FONT_TITLE := "res://game/assets/PixelifySans-SemiBold.woff2"

const KIT := preload("res://game/ui/UiKit.gd")
const SETTINGS := preload("res://game/ui/Settings.gd")
const FIELD_HUD := "res://game/ui/FieldHud.gd"
const MENU_SCRIPT := "res://game/ui/Menu.gd"

const UI_SCALE_CYCLE := ["kecil", "sedang", "besar"]
const STICK_SENS_CYCLE := [0.8, 1.0, 1.2, 1.4]

var _font_body: Font
var _font_title: Font
var _diorama: Node3D
var _cast: Node3D
var _hud_layer: CanvasLayer
var _hud: Control
var _menu_layer: CanvasLayer
var _menu: Control
var _settings: RefCounted
var _tilt_mat: ShaderMaterial
var _phase_timer := 0.0
var _perf_timer := 0.0
var _refresh_timer := 0.0
var _area_note := ""
var _battle: Node3D = null


func _ready() -> void:
	if FileAccess.file_exists("res://game/FAIL_BOOT"):
		printerr("[GAME] Penanda kerusakan ditemukan, sengaja gagal boot.")
		OS.crash("Simulasi paket rusak (FAIL_BOOT)")

	_report_healthy_boot()
	_settings = SETTINGS.new()
	_settings.call("load_settings")
	_font_body = _font(FONT_BODY, 1)
	_font_title = _font(FONT_TITLE, 3)
	_build_world()
	_build_hud()
	_build_menu()
	_apply_settings()
	_announce_area()
	_fade_in()
	_maybe_capture_or_quit()


# ------------------------------------------------------------------ world ----
func _build_world() -> void:
	if ResourceLoader.exists(DIORAMA):
		_diorama = load(DIORAMA).instantiate() as Node3D
		add_child(_diorama)
		# the world decides where a zone begins; the HUD says its name
		if _diorama.has_signal("zone_changed"):
			_diorama.connect("zone_changed", Callable(self, "_on_zone_changed"))
		_add_cast()
	else:
		# A missing world pack must not look like a crash: say it plainly.
		_diorama = null

	var layer := CanvasLayer.new()
	layer.name = "Post"
	layer.layer = 1
	add_child(layer)

	var rect := ColorRect.new()
	rect.name = "TiltShift"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	if ResourceLoader.exists(TILT_SHIFT):
		mat.shader = load(TILT_SHIFT)
	_tilt_mat = mat
	rect.material = mat
	layer.add_child(rect)


## The cast lives in the characters pack and is added *inside* the diorama, so
## it can ask the world for its prop footprints and inherit its light.
func _add_cast() -> void:
	var path := "res://game/characters/CharacterWorld.gd"
	if _diorama == null or not ResourceLoader.exists(path):
		print("[GAME] paket karakter tidak ada, diorama tetap tampil tanpa penghuni")
		return
	var script: Script = load(path)
	if script == null:
		print("[GAME] skrip karakter gagal dimuat")
		return
	var cast: Node3D = script.new()
	cast.name = "Characters"
	_diorama.add_child(cast)
	_cast = cast
	# the cast asks for a battle; the shell is what loads the battle pack, so a
	# missing enemies pack degrades to the field instead of a broken game
	if cast.has_signal("battle_requested"):
		cast.connect("battle_requested", Callable(self, "_on_battle_requested"))
	print("[GAME] penghuni dimuat dari paket karakter")


# ----------------------------------------------------------------- battle ----
## Step 3C. The battle scene is loaded by PATH, not preloaded: it lives in its own
## package, and a core.pck that preloaded it would fail to load at all if that
## package were missing.
func _on_battle_requested(actor: Node3D) -> void:
	if _battle != null:
		return
	var path := "res://game/battle/BattleScene.gd"
	if not ResourceLoader.exists(path):
		print("[GAME] paket pertarungan tidak ada, orc hanya menghadang")
		return
	var script: Script = load(path)
	if script == null:
		return
	var region: Variant = _cast.call("battle_region") if _cast != null else null
	var progress: Dictionary = _cast.call("battle_progress") if _cast != null else {}
	var spot: Vector2 = _cast.call("battle_spot") if _cast != null else Vector2.ZERO
	if _cast != null:
		_cast.call("set_battle_mode", true)
	if _hud != null:
		_hud.visible = false
	if _menu != null:
		_menu.visible = false
	if _tilt_mat != null:
		# the tilt-shift band belongs to the field's lens; over a closer battle
		# camera it would blur the very sprites the player has to read
		_tilt_mat.set_shader_parameter("blur_pixels", 0.0)
	_battle = script.new()
	_battle.name = "Battle"
	add_child(_battle)
	_battle.connect("battle_finished", Callable(self, "_on_battle_finished"))
	_battle.call("start", region, spot, "pos_gunung", progress)


func _on_battle_finished(summary: Dictionary) -> void:
	if _cast != null:
		_cast.call("apply_battle_result", summary)
		_cast.call("set_battle_mode", false)
	if _hud != null:
		_hud.visible = true
	if _battle != null and is_instance_valid(_battle):
		_battle.queue_free()
	_battle = null
	_apply_settings()
	_refresh_field()


## Read a constant off the diorama's own script, at runtime (`Diorama.AREA_NAME`
## does not exist in the launcher's project, where the packed game runs).
func _area_constant(key: String, fallback: String) -> String:
	if _diorama == null or _diorama.get_script() == null:
		return fallback
	var consts: Dictionary = (_diorama.get_script() as Script).get_script_constant_map()
	return String(consts.get(key, fallback))


## Notch and rounded-corner guard: the display's safe area can be a few dozen
## pixels smaller than the screen. On desktop the insets are zero.
func _safe_insets() -> Vector2:
	var screen := DisplayServer.screen_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if screen.x <= 0 or screen.y <= 0 or safe.size.x <= 0:
		return Vector2.ZERO
	var vp := get_viewport()
	var width := float(vp.get_visible_rect().size.x) if vp != null else 1280.0
	if width <= 0.0:
		width = 1280.0
	var k := width / float(screen.x)
	return Vector2(maxf(0.0, float(safe.position.x)) * k,
		maxf(0.0, float(safe.position.y)) * k)


# -------------------------------------------------------------------- hud ----
func _build_hud() -> void:
	if not ResourceLoader.exists(FIELD_HUD):
		push_error("[GAME] FieldHud.gd tidak ada di paket ui")
		return
	_hud_layer = CanvasLayer.new()
	# The launcher's boot test looks for `HUD` by name to prove the interface came
	# out of core.pck; keep the contract, not just the behaviour.
	_hud_layer.name = "HUD"
	_hud_layer.layer = 2
	add_child(_hud_layer)
	_hud = (load(FIELD_HUD) as Script).new()
	_hud.name = "FieldHud"
	_hud_layer.add_child(_hud)
	_hud.call("apply_safe_area", _safe_insets())
	_hud.connect("menu_pressed", Callable(self, "_on_menu_pressed"))
	_hud.connect("action_pressed", Callable(self, "_on_action_pressed"))
	if _diorama != null and _diorama.has_method("map"):
		_hud.call("set_map", _diorama.call("map"))


## Walking into another zone: name + what it is, three seconds, then gone. The
## zone comes from the region data (its rect and its name), never from a table
## here, so adding a zone to the map adds a banner.
func _on_zone_changed(title: String, subtitle: String) -> void:
	if _hud == null or title == "":
		return
	_hud.call("show_banner", title, subtitle)


## The place banner: three seconds of name, then gone. The paragraph that used to
## sit in the bottom-left corner of the field lives in Jurnal now.
func _announce_area() -> void:
	var title := _area_constant("AREA_NAME", "Dunia tidak termuat")
	var subtitle := _area_constant("AREA_SUBTITLE", "")
	_area_note = ("Yaros: lembah, hutan pinus dan dataran batu yang menanjak ke "
		+ "Pos Gunung. Penjaga Bram berdiri di desa; orc berkeliaran di tepi hutan. "
		+ "Jalur aman setelah ketiganya dihalau.")
	if _diorama == null:
		subtitle = "Paket dunia tidak ditemukan — kembali dan periksa pembaruan."
	if _hud != null:
		_hud.call("show_banner", title, subtitle)


# ------------------------------------------------------------------- menu ----
func _build_menu() -> void:
	if not ResourceLoader.exists(MENU_SCRIPT):
		push_error("[GAME] Menu.gd tidak ada di paket ui")
		return
	_menu_layer = CanvasLayer.new()
	_menu_layer.name = "MenuLayer"
	_menu_layer.layer = 4
	add_child(_menu_layer)
	_menu = (load(MENU_SCRIPT) as Script).new()
	_menu.name = "Menu"
	_menu_layer.add_child(_menu)
	# the menu must keep working while the world is frozen
	_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	_menu.call("set_settings", _settings)
	if _diorama != null and _diorama.has_method("map"):
		_menu.call("set_map", _diorama.call("map"))
	_menu.connect("resume_requested", Callable(self, "_on_resume_pressed"))
	_menu.connect("save_requested", Callable(self, "_on_save_pressed"))
	_menu.connect("launcher_confirmed", Callable(self, "_on_back_pressed"))
	_menu.connect("map_requested", Callable(self, "_on_map_requested"))
	_menu.connect("setting_changed", Callable(self, "_on_toggle"))


func _on_menu_pressed() -> void:
	_open_menu("lanjut")


func _open_menu(page: String) -> void:
	if _menu == null:
		return
	_refresh_menu_state()
	if _hud != null:
		_hud.call("hide_action")
	_menu.call("open", page)
	get_tree().paused = true


func _refresh_menu_state() -> void:
	if _menu == null:
		return
	var st := {"objective": "—", "hearts": 0, "max_hearts": 3, "orcs_defeated": 0,
		"orcs_total": 3, "phase": "", "play_time": 0.0, "area_note": _area_note}
	if _cast != null and is_instance_valid(_cast) and _cast.has_method("hud_state"):
		var cast_state: Dictionary = _cast.call("hud_state")
		for key in cast_state.keys():
			st[key] = cast_state[key]
	if _diorama != null and _diorama.has_method("phase_name"):
		st["phase"] = String(_diorama.call("phase_name")).capitalize()
	st["status"] = _status_text()
	_menu.call("set_state", st)


func _on_action_pressed() -> void:
	if _cast != null and is_instance_valid(_cast) and _cast.has_method("act"):
		_cast.call("act")


func _on_map_requested() -> void:
	if _hud != null:
		_hud.call("open_map")


func _on_save_pressed() -> void:
	var note := "save tidak tersedia"
	if _cast != null and _cast.has_method("save_now"):
		note = String(_cast.call("save_now"))
	if _menu != null:
		_menu.call("set_save_note", "Progres tersimpan." if note == ""
			else "Gagal menyimpan: " + note)


func _on_resume_pressed() -> void:
	get_tree().paused = false
	if _menu != null:
		_menu.call("close")
	# closing the sheet is a good moment to put the run on disk
	if _cast != null and _cast.has_method("save_now"):
		_cast.call("save_now")


func _on_back_pressed() -> void:
	if _cast != null and _cast.has_method("save_now"):
		_cast.call("save_now")
	get_tree().paused = false
	await _fade_out()
	get_tree().change_scene_to_file("res://scenes/Launcher.tscn")


## One line of state in the menu header, so a player who paused to think can see
## where the run stands without opening Jurnal.
func _status_text() -> String:
	if _cast == null or not is_instance_valid(_cast) or not _cast.has_method("hud_state"):
		return ""
	var st: Dictionary = _cast.call("hud_state")
	var phase := ""
	if _diorama != null and _diorama.has_method("phase_name"):
		phase = String(_diorama.call("phase_name")).capitalize()
	return "Orc %d / %d · Nyawa %d / %d · %s" % [
		int(st.get("orcs_defeated", 0)), int(st.get("orcs_total", 3)),
		int(st.get("hearts", 0)), int(st.get("max_hearts", 3)), phase]


# --------------------------------------------------------------- settings ----
func _on_toggle(key: String) -> void:
	if _settings == null:
		return
	match key:
		"quality":
			_settings.call("cycle_quality")
		"ui_scale":
			var i := UI_SCALE_CYCLE.find(String(_settings.call("get_value", "ui_scale")))
			_settings.call("set_value", "ui_scale", UI_SCALE_CYCLE[(i + 1) % UI_SCALE_CYCLE.size()])
		"stick_mode":
			var fixed := bool(_settings.call("stick_fixed"))
			_settings.call("set_value", "stick_mode", "mengambang" if fixed else "tetap")
		"stick_sensitivity":
			var current := float(_settings.call("stick_sensitivity"))
			var next: Variant = STICK_SENS_CYCLE[0]
			for value in STICK_SENS_CYCLE:
				if float(value) > current + 0.01:
					next = value
					break
			_settings.call("set_value", "stick_sensitivity", next)
		_:
			_settings.call("set_value", key, not bool(_settings.call("get_value", key)))
	_settings.call("save")
	_apply_settings()
	if _menu != null:
		_menu.call("refresh_values")


## The tilt-shift band has to sit where the new pitch puts the player: the band
## is in screen space, and a 30-degree lens frames the knight lower than the old
## top-down one did. Focus line and band width come from camera.json (one place),
## the blur amount from the quality preset.
func _apply_lens_post() -> void:
	if _tilt_mat == null:
		return
	var band := {"focus_line": 0.54, "sharp_band": 0.30}
	if _diorama != null and _diorama.has_method("camera_rig"):
		var rig: Node3D = _diorama.call("camera_rig")
		if rig != null and rig.has_method("tilt_shift"):
			band = rig.call("tilt_shift")
	_tilt_mat.set_shader_parameter("focus_line", float(band.get("focus_line", 0.54)))
	_tilt_mat.set_shader_parameter("sharp_band", float(band.get("sharp_band", 0.30)))


func _apply_settings() -> void:
	# --- tilt-shift blur follows the quality preset
	if _tilt_mat != null:
		_tilt_mat.set_shader_parameter("blur_pixels", float(_settings.call("tilt_blur")))
	_apply_lens_post()
	if _hud != null:
		_hud.call("apply_ui_scale", float(_settings.call("ui_scale")))
		_hud.call("set_fps_visible", bool(_settings.call("fps_visible")))
	if _menu != null:
		KIT.apply_layer_scale(_menu_layer, float(_settings.call("ui_scale")),
			get_viewport().get_visible_rect().size)
	# --- world knobs: shadows, atmosphere, and the shake scale
	if _diorama != null:
		if _diorama.has_method("set_shadows_enabled"):
			_diorama.call("set_shadows_enabled", bool(_settings.call("shadows_enabled")))
		if _diorama.has_method("set_atmosphere_scale"):
			_diorama.call("set_atmosphere_scale", float(_settings.call("atmosphere_scale")))
	if _cast != null and is_instance_valid(_cast):
		if _cast.has_method("set_shake_scale"):
			_cast.call("set_shake_scale", 1.0 if bool(_settings.call("get_value", "shake")) else 0.0)
		var pad: Variant = _cast.call("touch_controls") if _cast.has_method("touch_controls") else null
		if pad != null:
			pad.call("set_sensitivity", float(_settings.call("stick_sensitivity")))
			pad.set("fixed_mode", bool(_settings.call("stick_fixed")))
	# --- frame budget and 3D resolution
	Engine.max_fps = int(_settings.call("fps_cap"))
	var vp := get_viewport()
	if vp != null:
		vp.scaling_3d_scale = float(_settings.call("render_scale"))


# ------------------------------------------------------------------ frame ----
func _process(delta: float) -> void:
	_perf_timer += delta
	_refresh_timer += delta
	_phase_timer += delta
	if _hud != null:
		_hud.call("tick", delta, String(_settings.call("quality")).capitalize())
	if _phase_timer >= 0.5:
		_phase_timer = 0.0
		_refresh_phase()
	if _refresh_timer >= 0.1:
		_refresh_timer = 0.0
		_refresh_field()
	if _perf_timer >= 5.0:
		_perf_timer = 0.0
		_perf_line()


## Everything the field needs, a few times a second: the map, the edge marker and
## the one button. The cast is the source of truth for all three.
func _refresh_field() -> void:
	if _hud == null or _cast == null or not is_instance_valid(_cast):
		return
	var player: Node3D = _cast.call("player") if _cast.has_method("player") else null
	if player == null:
		return
	var at := Vector2(player.position.x, player.position.z)
	var heading := Vector2(0.0, -1.0)
	if _cast.has_method("heading"):
		heading = _cast.call("heading")
	var markers: Array = _cast.call("field_markers") if _cast.has_method("field_markers") else []
	_hud.call("update_field", at, heading, markers)
	var quest: Dictionary = _cast.call("quest_target") if _cast.has_method("quest_target") else {}
	_hud.call("set_quest_target", quest.get("pos", Vector2.ZERO), not quest.is_empty())
	var action: Dictionary = _cast.call("interaction") if _cast.has_method("interaction") else {}
	if action.is_empty() or get_tree().paused or bool(_hud.call("full_map_open")):
		_hud.call("hide_action")
	else:
		_hud.call("set_action", String(action.get("kind", "")), String(action.get("label", "")))


func _refresh_phase() -> void:
	if _hud == null or _diorama == null or not _diorama.has_method("phase_name"):
		return
	var phase := String(_diorama.call("phase_name"))
	if phase == "":
		return
	_hud.call("set_phase", "moon" if phase == "malam" else "sun", phase)


## One line every five seconds in the log, so `adb logcat` on the phone is enough
## to compare presets without reading pixels.
func _perf_line() -> void:
	var particles := 0
	if _diorama != null and _diorama.has_method("atmosphere"):
		var atmo: Node = _diorama.call("atmosphere")
		if atmo != null and atmo.has_method("systems"):
			var systems: Dictionary = atmo.call("systems")
			for key in systems.keys():
				particles += int((systems[key] as CPUParticles3D).amount)
	var stream := {}
	if _diorama != null and _diorama.has_method("stream_stats"):
		stream = _diorama.call("stream_stats")
	print("[PERF] fps=%d kualitas=%s skala3d=%.2f partikel=%d bayangan=%s chunk=%d draw=%d prop=%d build_maks=%.1fms" % [
		Engine.get_frames_per_second(), String(_settings.call("quality")),
		float(_settings.call("render_scale")), particles,
		str(_settings.call("shadows_enabled")),
		int(stream.get("chunks", 0)), int(stream.get("draws", 0)),
		int(stream.get("props", 0)), float(stream.get("build_ms_worst", 0.0))])


# ---------------------------------------------------------------- curtain ----
func _fade_in() -> void:
	var curtain := _make_curtain()
	add_child(curtain)
	var tw := create_tween()
	tw.tween_property(curtain, "modulate:a", 0.0, 0.7).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(curtain.queue_free)


func _fade_out() -> void:
	var curtain := _make_curtain()
	curtain.modulate.a = 0.0
	add_child(curtain)
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(curtain, "modulate:a", 1.0, 0.35).set_trans(Tween.TRANS_SINE)
	await tw.finished


func _make_curtain() -> ColorRect:
	var rect := ColorRect.new()
	rect.color = Color(0.07, 0.05, 0.04, 1.0)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


# --------------------------------------------------------------- contract ----
func _report_healthy_boot() -> void:
	# The launcher exports these before changing scene (PackLoader.boot_version).
	var root := OS.get_environment("RT_DATA_ROOT")
	if root == "":
		root = "user://retraveller"
	var version := OS.get_environment("RT_ACTIVE_VERSION")
	if version == "":
		var active := root.path_join("active.json")
		if FileAccess.file_exists(active):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(active))
			if typeof(parsed) == TYPE_DICTIONARY:
				version = String((parsed as Dictionary).get("version", ""))
	if version == "":
		version = "belum ada"
	DirAccess.make_dir_recursive_absolute(root)
	var f := FileAccess.open(root.path_join("boot_ok.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({
			"version": version,
			"schema": 1,
			"scene": "res://game/Main.tscn",
			"at": Time.get_datetime_string_from_system(true),
		}, "  "))
		f.flush()
		f = null
	print("[GAME] boot_ok ditulis untuk versi %s" % version)


# ------------------------------------------------------- capture harness -----
## CI (and the owner's own screenshots) drive the game through the same doors a
## thumb uses: the banner, the menu, the contextual button, the map. No test-only
## code path changes what is drawn.
func _maybe_capture_or_quit() -> void:
	var capture_dir := ""
	var capture_name := "08_diorama"
	var scenario := ""
	var menu_page := ""
	var walk_secs := 0.0
	var hug := -1.0
	var zone_key := ""
	var phase_want := ""
	var zoom_want := 0.0
	var pitch_want := 0.0
	var fov_want := 0.0
	for raw in OS.get_cmdline_user_args():
		var a := String(raw)
		if a.begins_with("--capture="):
			capture_dir = a.substr("--capture=".length())
		elif a.begins_with("--capture-name="):
			capture_name = a.substr("--capture-name=".length())
		elif a.begins_with("--hud="):
			scenario = a.substr("--hud=".length())
		elif a.begins_with("--menu="):
			menu_page = a.substr("--menu=".length())
		elif a.begins_with("--walk="):
			walk_secs = float(a.substr("--walk=".length()))
		elif a.begins_with("--zone="):
			zone_key = a.substr("--zone=".length())
		elif a.begins_with("--phase="):
			phase_want = a.substr("--phase=".length())
		elif a.begins_with("--zoom="):
			# the old name for the camera distance; the lens itself never zooms
			zoom_want = float(a.substr("--zoom=".length()))
		elif a.begins_with("--distance="):
			zoom_want = float(a.substr("--distance=".length()))
		elif a.begins_with("--pitch="):
			pitch_want = float(a.substr("--pitch=".length()))
		elif a.begins_with("--fov="):
			fov_want = float(a.substr("--fov=".length()))
		elif a.begins_with("--test-quit-after="):
			hug = float(a.substr("--test-quit-after=".length()))
	if hug > 0.0:
		await get_tree().create_timer(hug).timeout
		print("[GAME] keluar otomatis untuk pengujian.")
		get_tree().quit(0)
		return
	if scenario == "" and menu_page == "" and capture_dir == "":
		return
	# let the curtain finish and one bloom frame settle
	await get_tree().create_timer(1.0).timeout
	if scenario == "field_only" and _cast != null and is_instance_valid(_cast):
		# stand in the open, far from anybody: the HUD at its emptiest
		_cast.call("teleport_player", _spot(-9.0, -7.0))
		await get_tree().create_timer(0.5).timeout
	elif walk_secs > 0.0:
		await _drive_walk(walk_secs)
	if scenario == "stick" and _cast != null and is_instance_valid(_cast):
		# near the guard, so the contextual button is up too, with the floating
		# stick drawn pushed in: at rest it is invisible and proves nothing
		_cast.call("teleport_player", _guard_spot())
		await get_tree().create_timer(0.55).timeout
		var pad: Variant = _cast.call("touch_controls") if _cast.has_method("touch_controls") else null
		if pad != null:
			pad.call("show_controls", true)
			if pad.has_method("preview_stick"):
				pad.call("preview_stick", true)
		await get_tree().create_timer(0.3).timeout
	if zone_key != "":
		await _go_to_zone(zone_key, phase_want, zoom_want, pitch_want, fov_want)
	if scenario == "dialogue":
		await _open_dialogue_for_capture()
	elif scenario == "map":
		if _hud != null:
			_hud.call("open_map")
		await get_tree().create_timer(0.6).timeout
	elif scenario == "fog":
		await _walk_far()
	elif scenario == "occlusion":
		await _occlude_for_capture()
	elif scenario == "banner":
		if _hud != null:
			_hud.call("show_banner", _area_constant("AREA_NAME", "Lembah Senja"),
				_area_constant("AREA_SUBTITLE", ""))
		await get_tree().create_timer(0.7).timeout
	if scenario != "banner" and scenario != "dialogue" and _hud != null:
		# a shot of the field must show the empty field, not the 3 s title card
		_hud.call("dismiss_banner")
	if menu_page != "":
		if menu_page == "jeda":
			menu_page = "lanjut"
		_open_menu(menu_page)
		await get_tree().create_timer(0.45).timeout
	if capture_dir != "":
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(capture_dir)
		var img := get_viewport().get_texture().get_image()
		var path := capture_dir.path_join(capture_name + ".png")
		var err := img.save_png(path)
		print("[GAME] capture %s -> %s (err %d, %dx%d)" % [
			capture_name, path, err, img.get_width(), img.get_height()])
		get_tree().quit(0)
		return
	# a menu-only capture run (no --capture) still exits, so CI never waits
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(0)


## Stand the knight on the far side of a tall prop so it covers him, which is the
## shot that proves the dithering occlusion works at the new, lower pitch.
func _occlude_for_capture() -> void:
	if _cast == null or _diorama == null:
		return
	var rig: Node3D = _diorama.call("camera_rig") if _diorama.has_method("camera_rig") else null
	var view: Node3D = _diorama.call("view") if _diorama.has_method("view") else null
	var player: Node3D = _cast.call("player")
	if rig == null or view == null or player == null:
		return
	var cam_xz := Vector2(rig.global_position.x, rig.global_position.z)
	var here := Vector2(player.position.x, player.position.z)
	var layout: Array = view.call("prop_layout")
	var best: Array = []
	var best_d := 1.0e9
	for raw in layout:
		var row: Array = raw
		if row.size() < 5:
			continue
		if float(row[4]) < 2.2:
			continue
		var d: float = Vector2(float(row[1]), float(row[2])).distance_to(here)
		if d < best_d:
			best_d = d
			best = row
	if best.is_empty():
		print("[GAME] tidak ada prop tinggi di dekat pemain untuk tangkapan occlusion")
		return
	var prop := Vector2(float(best[1]), float(best[2]))
	var away := (prop - cam_xz).normalized()
	var spot := prop + away * 1.5
	_cast.call("teleport_player", spot)
	# the occluder pass runs four times a second and the rig glides after the
	# teleport, so give both time to arrive before the shutter
	await get_tree().create_timer(1.1).timeout
	print("[GAME] tangkapan occlusion: prop %s, pemain di %s" % [str(prop), str(spot)])


## Walk with the same virtual stick a thumb would push.
func _drive_walk(seconds: float) -> void:
	if _cast == null or not is_instance_valid(_cast):
		return
	_cast.call("set_virtual_stick", Vector2(-0.35, -0.8))
	await get_tree().create_timer(seconds).timeout
	_cast.call("set_virtual_stick", Vector2.ZERO)
	await get_tree().create_timer(0.15).timeout


## Put the camera somewhere named, for a screenshot: a marker's name from the
## region ("Hutan Pinus"), or one of the three shapes the brief asks to see -
## "stairs", "cliff" and "water" - found by scanning the map instead of by
## remembering a coordinate.
func _go_to_zone(key: String, phase_want: String, zoom_want: float,
		pitch_want: float = 0.0, fov_want: float = 0.0) -> void:
	if _cast == null or not is_instance_valid(_cast) or _diorama == null:
		return
	var spot: Variant = _spot_for(key)
	if spot == null:
		print("[GAME] zona '%s' tidak ditemukan di peta" % key)
		return
	_cast.call("teleport_player", spot)
	await get_tree().create_timer(0.9).timeout
	if phase_want != "" and _diorama.has_method("set_phase"):
		_diorama.call("set_phase", phase_want)
	var rig: Node3D = _diorama.call("camera_rig") if _diorama.has_method("camera_rig") else null
	if rig != null and rig.has_method("set_lens"):
		# Scripted framing for a capture, the same door a cutscene uses. The
		# player never gets here: nothing on the touch screen reaches set_lens.
		rig.call("set_lens",
			pitch_want if pitch_want > 0.0 else NAN,
			fov_want if fov_want > 0.0 else NAN,
			zoom_want if zoom_want > 0.0 else NAN)
		rig.call("set_follow_target", _cast.call("player"))
		if rig.has_method("snap_to_target"):
			rig.call("snap_to_target")
	_apply_lens_post()
	await get_tree().create_timer(0.7).timeout
	print("[GAME] tangkapan zona %s di %s" % [key, str(spot)])


## Resolve a name to a place. Marker names first (they are the map's own names),
## then the three special shapes.
func _spot_for(key: String) -> Variant:
	var region: RefCounted = _diorama.call("region") if _diorama != null else null
	if region == null:
		return null
	var m: Dictionary = region.call("marker", key)
	if not m.is_empty():
		return region.call("marker_pos", m)
	# a zone name: the middle of its rectangle, snapped to walkable ground
	for raw in (region.get("zones") as Array):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var z: Dictionary = raw
		if String(z.get("name", "")) != key:
			continue
		var r: Array = z.get("rect", [])
		if r.size() >= 4:
			var centre := Vector2(float(r[0]) + float(r[2]) * 0.5,
				float(r[1]) + float(r[3]) * 0.5)
			var t: Vector2i = region.call("world_to_tile", centre)
			var q: Vector2i = region.call("nearest_walkable", t, 24)
			return region.call("tile_centre", q.x, q.y)
	if key == "stairs":
		return _find_tile(region, "stairs")
	if key == "cliff":
		return _find_tile(region, "cliff")
	if key == "cliff_inner":
		return _find_tile(region, "cliff_inner")
	if key == "water":
		return _find_tile(region, "water")
	return null


## Scan the region's grids once for a tile of a given shape, preferring one near
## the main road so the picture has a foreground.
func _find_tile(region: RefCounted, shape: String) -> Variant:
	var w := int(region.get("width"))
	var h := int(region.get("height"))
	var start: Vector2 = region.call("start_position")
	var best := Vector2.INF
	var best_d := 1.0e9
	for tz in range(2, h - 2):
		for tx in range(2, w - 2):
			var here := int(region.call("tile_height", tx, tz))
			match shape:
				"stairs":
					if int(region.call("struct_code", tx, tz)) != 1:
						continue
				"cliff":
					# the OUTSIDE corner: high ground with two lower neighbours at
					# right angles, where two walls meet and the mesh has to close
					# the corner without a hole
					var a := int(region.call("tile_height", tx + 1, tz))
					var b := int(region.call("tile_height", tx, tz + 1))
					if here - a < 3 or here - b < 3:
						continue
				"cliff_inner":
					# the INSIDE corner: low ground with cliffs on two sides, the
					# spot a naive mesher leaves a gap in
					var ca := int(region.call("tile_height", tx + 1, tz))
					var cb := int(region.call("tile_height", tx, tz + 1))
					if ca - here < 3 or cb - here < 3:
						continue
				"water":
					if int(region.call("tile_terrain", tx, tz)) != 8:
						continue
					# stand on the shore, look at the water
					var shore := false
					for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						if int(region.call("tile_terrain", tx + d.x, tz + d.y)) == 7:
							shore = true
					if not shore:
						continue
			var centre: Vector2 = region.call("tile_centre", tx, tz)
			var d2 := centre.distance_squared_to(start)
			if d2 < best_d:
				best_d = d2
				best = centre
				if shape != "water":
					return _behind(region, centre)
	if best == Vector2.INF:
		return null
	return _behind(region, best)


## Stand a couple of tiles back from a landmark so the landmark is in frame
## instead of under the knight's feet.
func _behind(region: RefCounted, at: Vector2) -> Variant:
	var t: Vector2i = region.call("world_to_tile", at)
	var q: Vector2i = region.call("nearest_walkable", Vector2i(t.x, t.y + 3), 10)
	return region.call("tile_centre", q.x, q.y)


## Walk a long way in steps so the fog really opens up, like a player crossing the
## valley would. Only used by the capture harness.
func _walk_far() -> void:
	if _cast == null or not is_instance_valid(_cast):
		return
	# the village, the fields, then the forest camp: a real crossing of Yaros
	var route := [_spot(0.0, 0.0), _spot(14.0, -6.0), _spot(28.0, -14.0),
		_spot(40.0, -26.0), _spot(38.0, -34.0)]
	for point in route:
		_cast.call("teleport_player", point)
		await get_tree().create_timer(0.12).timeout
	_cast.call("teleport_player", _spot(36.0, -30.0))
	await get_tree().create_timer(0.35).timeout


func _open_dialogue_for_capture() -> void:
	if _cast == null or not is_instance_valid(_cast):
		return
	_cast.call("teleport_player", _guard_spot())
	await get_tree().create_timer(0.1).timeout
	_cast.call("press_interact")
	await get_tree().create_timer(0.4).timeout
	var dlg: Variant = _cast.call("dialogue")
	if dlg != null and bool(dlg.get("is_open")):
		dlg.call("advance")
	await get_tree().create_timer(2.6).timeout


# ---------------------------------------------------------------- helpers ----
## A point relative to the region's start marker, so the capture harness keeps
## working when the map is rebuilt. Falls back to the old glade's coordinates.
func _spot(dx: float, dz: float) -> Vector2:
	if _diorama != null and _diorama.has_method("region"):
		var region: RefCounted = _diorama.call("region")
		if region != null:
			return (region.call("start_position") as Vector2) + Vector2(dx, dz)
	return Vector2(3.6 + dx, 7.2 + dz)


## The tile beside the guard, for the shots that need the action button up.
func _guard_spot() -> Vector2:
	if _diorama != null and _diorama.has_method("region"):
		var region: RefCounted = _diorama.call("region")
		if region != null:
			var m: Dictionary = region.call("marker", "Penjaga Bram")
			if not m.is_empty():
				return (region.call("marker_pos", m) as Vector2) + Vector2(-1.2, 0.6)
	return Vector2(3.4, 5.2)


func _font(path: String, tracking: int = 0) -> Font:
	var f := FontFile.new()
	if f.load_dynamic_font(path) != OK:
		return ThemeDB.fallback_font
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.hinting = TextServer.HINTING_NONE
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	if tracking == 0:
		return f
	var v := FontVariation.new()
	v.base_font = f
	v.spacing_glyph = tracking
	v.spacing_space = tracking * 2
	return v
