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
	print("[GAME] penghuni dimuat dari paket karakter")


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


## The place banner: three seconds of name, then gone. The paragraph that used to
## sit in the bottom-left corner of the field lives in Jurnal now.
func _announce_area() -> void:
	var title := _area_constant("AREA_NAME", "Dunia tidak termuat")
	var subtitle := _area_constant("AREA_SUBTITLE", "")
	_area_note = ("Lembah ini jalan tua menuju pegunungan. Penjaga Bram berdiri di "
		+ "tikungan; orc berkeliaran di tepi hutan. Jalur aman setelah ketiganya "
		+ "dihalau.")
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


func _apply_settings() -> void:
	# --- tilt-shift blur follows the quality preset
	if _tilt_mat != null:
		_tilt_mat.set_shader_parameter("blur_pixels", float(_settings.call("tilt_blur")))
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
	print("[PERF] fps=%d kualitas=%s skala3d=%.2f partikel=%d bayangan=%s" % [
		Engine.get_frames_per_second(), String(_settings.call("quality")),
		float(_settings.call("render_scale")), particles,
		str(_settings.call("shadows_enabled"))])


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
		_cast.call("teleport_player", Vector2(-8.5, 6.0))
		await get_tree().create_timer(0.5).timeout
	elif walk_secs > 0.0:
		await _drive_walk(walk_secs)
	if scenario == "stick" and _cast != null and is_instance_valid(_cast):
		# near the guard, so the contextual button is up too, with the floating
		# stick drawn pushed in: at rest it is invisible and proves nothing
		_cast.call("teleport_player", Vector2(3.4, 5.2))
		await get_tree().create_timer(0.55).timeout
		var pad: Variant = _cast.call("touch_controls") if _cast.has_method("touch_controls") else null
		if pad != null:
			pad.call("show_controls", true)
			if pad.has_method("preview_stick"):
				pad.call("preview_stick", true)
		await get_tree().create_timer(0.3).timeout
	if scenario == "dialogue":
		await _open_dialogue_for_capture()
	elif scenario == "map":
		if _hud != null:
			_hud.call("open_map")
		await get_tree().create_timer(0.6).timeout
	elif scenario == "fog":
		await _walk_far()
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


## Walk with the same virtual stick a thumb would push.
func _drive_walk(seconds: float) -> void:
	if _cast == null or not is_instance_valid(_cast):
		return
	_cast.call("set_virtual_stick", Vector2(-0.35, -0.8))
	await get_tree().create_timer(seconds).timeout
	_cast.call("set_virtual_stick", Vector2.ZERO)
	await get_tree().create_timer(0.15).timeout


## Walk a long way in steps so the fog really opens up, like a player crossing the
## valley would. Only used by the capture harness.
func _walk_far() -> void:
	if _cast == null or not is_instance_valid(_cast):
		return
	var route := [Vector2(3.6, 7.2), Vector2(9.0, 4.0), Vector2(10.0, -2.0),
		Vector2(6.0, -6.5), Vector2(0.0, -6.0), Vector2(-6.0, -2.0)]
	for point in route:
		_cast.call("teleport_player", point)
		await get_tree().create_timer(0.12).timeout
	_cast.call("teleport_player", Vector2(-3.0, 3.0))
	await get_tree().create_timer(0.35).timeout


func _open_dialogue_for_capture() -> void:
	if _cast == null or not is_instance_valid(_cast):
		return
	_cast.call("teleport_player", Vector2(3.4, 5.8))
	await get_tree().create_timer(0.1).timeout
	_cast.call("press_interact")
	await get_tree().create_timer(0.4).timeout
	var dlg: Variant = _cast.call("dialogue")
	if dlg != null and bool(dlg.get("is_open")):
		dlg.call("advance")
	await get_tree().create_timer(2.6).timeout


# ---------------------------------------------------------------- helpers ----
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
