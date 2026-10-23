class_name TouchHUDController
extends CanvasLayer
## ─────────────────────────────────────────────────────────────────────────
## HUD sentuh LANTERNFALL (Godot 4.7) — tata letak bersih & berjenjang.
##
##   • kiri atas   : bar HP / Stamina / Minyak + jumlah koin
##   • kanan atas  : SATU tombol MENU radial — semua konten lain ada di sini
##                   (Jurnal, Kredit, Pengaturan, Skill 1/2, Tutup)
##   • kiri bawah  : analog joystick (visual: JoystickPad)
##   • kanan bawah : hanya kontrol gerakan (SERANG, HINDAR) + AKSI kontekstual
##                   yang muncul sendiri saat ada objek yang bisa disentuh
##   • bawah tengah: panel dialog (hanya saat dialog berjalan)
##
## Game di-pause selama menu/panel terbuka. HUD tetap hidup karena
## process_mode = PROCESS_MODE_ALWAYS (diset di TouchHUD.tscn).
## ─────────────────────────────────────────────────────────────────────────

const WIDE_BUTTON_NORMAL = preload("res://assets/ui/styles/button_wide_normal.tres")
const WIDE_BUTTON_HOVER = preload("res://assets/ui/styles/button_wide_hover.tres")
const WIDE_BUTTON_PRESSED = preload("res://assets/ui/styles/button_wide_pressed.tres")
const CHOICE_BUTTON_HEIGHT: int = 100
const INTERACT_CHECK_INTERVAL: float = 0.25
const TOAST_HOLD: float = 2.2
const TOAST_FADE: float = 0.6
const BASE_PADDING: float = 20.0
const VOLUME_STEPS: Array[String] = ["0%", "25%", "50%", "75%", "100%"]

@export var player_path: NodePath

# ── Joystick ─────────────────────────────────────────────────────────────
var _joystick_touch_idx: int = -1
var _joystick_center: Vector2 = Vector2(150.0, 560.0)
var _joystick_radius: float = 72.0
var _joystick_vec: Vector2 = Vector2.ZERO

var _interact_timer: float = 0.0
var _toast_tween: Tween = null

# ── Referensi node ───────────────────────────────────────────────────────
@onready var hud_root: Control = $HudRoot
@onready var hp_bar: ProgressBar = $HudRoot/StatusBox/HPBar
@onready var stamina_bar: ProgressBar = $HudRoot/StatusBox/StaminaBar
@onready var oil_bar: ProgressBar = $HudRoot/StatusBox/OilBar
@onready var coin_label: Label = $HudRoot/StatusBox/CoinRow/CoinLabel
@onready var toast_label: Label = $HudRoot/ToastLabel
@onready var radial_button: Button = $HudRoot/RadialButton
@onready var radial_layer: Control = $HudRoot/RadialLayer
@onready var btn_attack: Button = $HudRoot/BtnAttack
@onready var btn_dodge: Button = $HudRoot/BtnDodge
@onready var btn_interact: Button = $HudRoot/BtnInteract
@onready var dialogue_panel: PanelContainer = $HudRoot/DialoguePanel
@onready var dialogue_speaker: Label = $HudRoot/DialoguePanel/VBox/SpeakerLabel
@onready var dialogue_text: RichTextLabel = $HudRoot/DialoguePanel/VBox/BodyText
@onready var choices_box: VBoxContainer = $HudRoot/DialoguePanel/VBox/ChoicesBox
@onready var jurnal_panel: PanelContainer = $HudRoot/JurnalPanel
@onready var credits_panel: PanelContainer = $HudRoot/CreditsPanel
@onready var settings_panel: PanelContainer = $HudRoot/SettingsPanel
@onready var slot_weapon_label: Label = $HudRoot/JurnalPanel/PauseVBox/EquipRow/SlotWeapon/SlotWeaponLabel
@onready var slot_cloak_label: Label = $HudRoot/JurnalPanel/PauseVBox/EquipRow/SlotCloak/SlotCloakLabel
@onready var slot_lantern_label: Label = $HudRoot/JurnalPanel/PauseVBox/EquipRow/SlotLantern/SlotLanternLabel
@onready var opt_graphics: OptionButton = $HudRoot/SettingsPanel/SettingsVBox/RowGrafis/OptGrafis
@onready var opt_colorblind: OptionButton = $HudRoot/SettingsPanel/SettingsVBox/RowWarna/OptWarna
@onready var opt_language: OptionButton = $HudRoot/SettingsPanel/SettingsVBox/RowBahasa/OptBahasa
@onready var btn_battery: Button = $HudRoot/SettingsPanel/SettingsVBox/BtnBattery
@onready var opt_vol_master: OptionButton = $HudRoot/SettingsPanel/SettingsVBox/RowVolMaster/OptVolMaster
@onready var opt_vol_bgm: OptionButton = $HudRoot/SettingsPanel/SettingsVBox/RowVolBgm/OptVolBgm
@onready var opt_vol_sfx: OptionButton = $HudRoot/SettingsPanel/SettingsVBox/RowVolSfx/OptVolSfx
@onready var joystick_pad: JoystickPad = $JoystickPad


func _ready() -> void:
	_apply_notch_safe_area()
	_init_settings_ui()
	_close_all_menus()
	EventBus.player_hp_changed.connect(_on_hp_changed)
	EventBus.player_stamina_changed.connect(_on_stamina_changed)
	EventBus.lantern_oil_changed.connect(_on_oil_changed)
	EventBus.currency_changed.connect(_on_currency_changed)
	EventBus.chunk_entered.connect(_on_chunk_entered)
	EventBus.dialogue_started.connect(_on_dialogue_started)
	EventBus.dialogue_ended.connect(_on_dialogue_ended)
	EventBus.floating_damage_spawned.connect(_on_floating_damage_spawned)
	EventBus.toast_notification.connect(_on_toast_notification)
	_refresh_all_readouts()
	_show_toast("Desa Rembang (Prolog)")


# ════════════════════════════════════════════════════════════════════════
# Tata letak & safe area
# ════════════════════════════════════════════════════════════════════════

## Safe area dari sistem dipakai sebagai INSET pada HudRoot (bukan margin
## container). Nilainya dikonversi dari piksel fisik layar ke satuan desain
## 1280×720 — kalau tidak, inset notch bisa ratusan "px desain" dan HUD
## bergeser jauh dari tempatnya.
func _apply_notch_safe_area() -> void:
	if hud_root == null:
		return
	var win: Vector2i = DisplayServer.window_get_size()
	if win.x <= 0 or win.y <= 0:
		hud_root.set_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, int(BASE_PADDING))
		return
	var vis: Rect2 = get_viewport().get_visible_rect()
	var scale_to_design: Vector2 = Vector2(vis.size.x / float(win.x), vis.size.y / float(win.y))
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	var inset_left: float = BASE_PADDING + maxf(0.0, float(safe.position.x) * scale_to_design.x)
	var inset_top: float = BASE_PADDING + maxf(0.0, float(safe.position.y) * scale_to_design.y)
	var inset_right: float = BASE_PADDING + maxf(0.0, float(win.x - (safe.position.x + safe.size.x)) * scale_to_design.x)
	var inset_bottom: float = BASE_PADDING + maxf(0.0, float(win.y - (safe.position.y + safe.size.y)) * scale_to_design.y)
	hud_root.offset_left = inset_left
	hud_root.offset_top = inset_top
	hud_root.offset_right = -inset_right
	hud_root.offset_bottom = -inset_bottom


# ════════════════════════════════════════════════════════════════════════
# Menu radial & panel
# ════════════════════════════════════════════════════════════════════════

func _is_menu_open() -> bool:
	return (radial_layer != null and radial_layer.visible) \
		or (jurnal_panel != null and jurnal_panel.visible) \
		or (credits_panel != null and credits_panel.visible) \
		or (settings_panel != null and settings_panel.visible)


func _close_all_menus() -> void:
	if radial_layer != null:
		radial_layer.visible = false
	if jurnal_panel != null:
		jurnal_panel.visible = false
	if credits_panel != null:
		credits_panel.visible = false
	if settings_panel != null:
		settings_panel.visible = false
	_update_pause_state()


## Game berhenti selama menu terbuka; HUD sendiri tetap jalan (process_mode).
func _update_pause_state() -> void:
	var should_pause: bool = _is_menu_open()
	if get_tree().paused != should_pause:
		get_tree().paused = should_pause
	_sync_controls_visibility()


## Kontrol gerakan disembunyikan saat menu/panel terbuka atau dialog berjalan:
## tidak ada gunanya ditampilkan (game berhenti) dan letaknya berbenturan
## dengan panel tengah bawah.
func _sync_controls_visibility() -> void:
	var hide_actions: bool = _is_menu_open() or DialogueManager.is_dialogue_active
	for btn in [btn_attack, btn_dodge, btn_interact]:
		if btn != null:
			btn.visible = not hide_actions
	if hide_actions:
		_release_joystick()


func _animate_radial(opening: bool) -> void:
	if radial_layer == null:
		return
	for child in radial_layer.get_children():
		if not (child is CanvasItem):
			continue
		var item: CanvasItem = child as CanvasItem
		var tw: Tween = item.create_tween()
		tw.set_parallel(true)
		if opening:
			item.scale = Vector2(0.65, 0.65)
			item.modulate.a = 0.0
			tw.tween_property(item, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(item, "modulate:a", 1.0, 0.16)
		else:
			tw.tween_property(item, "scale", Vector2.ONE, 0.05)
			tw.tween_property(item, "modulate:a", 1.0, 0.05)


func on_radial_button_pressed() -> void:
	if radial_layer == null:
		return
	if radial_layer.visible:
		_close_all_menus()
	else:
		_close_panels()
		radial_layer.visible = true
		_animate_radial(true)
		_update_pause_state()
		AudioBus.play_sfx("ui_tap", 1.0, 1.05)


func _close_panels() -> void:
	if jurnal_panel != null:
		jurnal_panel.visible = false
	if credits_panel != null:
		credits_panel.visible = false
	if settings_panel != null:
		settings_panel.visible = false


func on_rad_jurnal_pressed() -> void:
	_open_panel(jurnal_panel)


func on_rad_kredit_pressed() -> void:
	_open_panel(credits_panel)


func on_rad_setelan_pressed() -> void:
	_open_panel(settings_panel)


func on_rad_tutup_pressed() -> void:
	AudioBus.play_sfx("ui_tap", 1.0, 1.05)
	_close_all_menus()


func on_rad_sinar_pressed() -> void:
	_close_all_menus()
	var p: PlayerController = _get_player()
	if p != null:
		p.trigger_skill_1_sinar_fokus()


func on_rad_kelip_pressed() -> void:
	_close_all_menus()
	var p: PlayerController = _get_player()
	if p != null:
		p.trigger_skill_2_perisai_senja()


func _open_panel(panel: PanelContainer) -> void:
	AudioBus.play_sfx("ui_tap", 1.0, 1.05)
	_close_panels()
	if radial_layer != null:
		radial_layer.visible = false
	if panel == null:
		return
	panel.visible = true
	if panel == jurnal_panel:
		_refresh_equipment_readouts()
	_update_pause_state()


func on_close_jurnal_pressed() -> void:
	AudioBus.play_sfx("ui_tap", 1.0, 1.05)
	_close_all_menus()


func on_close_credits_pressed() -> void:
	AudioBus.play_sfx("ui_tap", 1.0, 1.05)
	_close_all_menus()


func on_close_settings_pressed() -> void:
	AudioBus.play_sfx("ui_tap", 1.0, 1.05)
	_close_all_menus()


# ════════════════════════════════════════════════════════════════════════
# Pengaturan
# ════════════════════════════════════════════════════════════════════════

func _init_settings_ui() -> void:
	if opt_graphics != null:
		for label in ["Rendah", "Sedang", "Tinggi"]:
			opt_graphics.add_item(label)
		opt_graphics.selected = clampi(int(GameState.settings.get("graphics_preset", 1)), 0, 2)
		opt_graphics.item_selected.connect(_on_graphics_selected)

	if opt_colorblind != null:
		for label in ["Normal", "Protanopia", "Deuteranopia", "Tritanopia"]:
			opt_colorblind.add_item(label)
		opt_colorblind.selected = clampi(int(GameState.settings.get("colorblind_mode", 0)), 0, 3)
		opt_colorblind.item_selected.connect(_on_colorblind_selected)

	if opt_language != null:
		for label in ["Bahasa Indonesia", "English"]:
			opt_language.add_item(label)
		opt_language.selected = 0 if String(GameState.settings.get("language", "id")) == "id" else 1
		opt_language.item_selected.connect(_on_language_selected)

	_fill_volume(opt_vol_master, "master_vol", "Master")
	_fill_volume(opt_vol_bgm, "bgm_vol", "BGM")
	_fill_volume(opt_vol_sfx, "sfx_vol", "SFX")
	_refresh_battery_label()


func _fill_volume(opt: OptionButton, setting_key: String, bus: StringName) -> void:
	if opt == null:
		return
	for label in VOLUME_STEPS:
		opt.add_item(label)
	var value: float = float(GameState.settings.get(setting_key, 0.9))
	opt.selected = clampi(int(round(value * 4.0)), 0, 4)
	opt.item_selected.connect(func(index: int) -> void:
		_on_volume_selected(index, setting_key, bus)
	)


func _on_graphics_selected(index: int) -> void:
	GameState.settings["graphics_preset"] = index
	EventBus.graphics_preset_changed.emit(index)


func _on_colorblind_selected(index: int) -> void:
	GameState.settings["colorblind_mode"] = index
	EventBus.colorblind_mode_changed.emit(index)


func _on_language_selected(index: int) -> void:
	var locale: String = "id" if index == 0 else "en"
	GameState.settings["language"] = locale
	TranslationServer.set_locale(locale)


func _on_volume_selected(index: int, setting_key: String, bus: StringName) -> void:
	var value: float = clampf(float(index) * 0.25, 0.0, 1.0)
	GameState.settings[setting_key] = value
	AudioBus.set_bus_volume_linear(bus, value)


func on_battery_pressed() -> void:
	var enabled: bool = not bool(GameState.settings.get("battery_saver_30fps", false))
	GameState.settings["battery_saver_30fps"] = enabled
	Engine.max_fps = 30 if enabled else 60
	_refresh_battery_label()
	AudioBus.play_sfx("ui_tap", 1.0, 1.05)


func _refresh_battery_label() -> void:
	if btn_battery == null:
		return
	var enabled: bool = bool(GameState.settings.get("battery_saver_30fps", false))
	btn_battery.text = "Hemat baterai (30 FPS): %s" % ("HIDUP" if enabled else "MATI")


# ════════════════════════════════════════════════════════════════════════
# Input sentuh
# ════════════════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	_interact_timer -= delta
	if _interact_timer <= 0.0:
		_interact_timer = INTERACT_CHECK_INTERVAL
		_update_interact_button()


func _unhandled_input(event: InputEvent) -> void:
	if _is_menu_open() or DialogueManager.is_dialogue_active:
		return
	var player: PlayerController = _get_player()
	if player == null:
		return

	if event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event as InputEventScreenTouch
		if st.pressed:
			if st.position.x < 520.0 and st.position.y > 300.0 and _joystick_touch_idx == -1:
				_joystick_touch_idx = st.index
				_joystick_center = st.position
				_update_joystick_delta(st.position, player)
			else:
				_try_tap_to_interact(st.position, player)
		else:
			if st.index == _joystick_touch_idx:
				_joystick_touch_idx = -1
				_release_joystick()
				player.set_touch_move_vector(Vector2.ZERO)

	elif event is InputEventScreenDrag:
		var sd: InputEventScreenDrag = event as InputEventScreenDrag
		if sd.index == _joystick_touch_idx:
			_update_joystick_delta(sd.position, player)


func _release_joystick() -> void:
	_joystick_vec = Vector2.ZERO
	if joystick_pad != null:
		joystick_pad.release()


func _update_joystick_delta(touch_pos: Vector2, player: PlayerController) -> void:
	var diff: Vector2 = touch_pos - _joystick_center
	if diff.length() > _joystick_radius:
		diff = diff.normalized() * _joystick_radius
	_joystick_vec = diff / _joystick_radius
	player.set_touch_move_vector(_joystick_vec)
	if joystick_pad != null:
		joystick_pad.set_state(_joystick_center, _joystick_vec, _joystick_radius)


func _try_tap_to_interact(screen_pos: Vector2, player: PlayerController) -> void:
	var vp: Viewport = get_viewport()
	var cam: Camera3D = vp.get_camera_3d()
	if cam == null:
		return
	var from: Vector3 = cam.project_ray_origin(screen_pos)
	var to: Vector3 = from + cam.project_ray_normal(screen_pos) * 35.0
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	var hit: Dictionary = space.intersect_ray(query)
	if not hit.is_empty() and hit.has("collider"):
		var col: Object = hit["collider"]
		if col is Node3D and col.has_method("interact_with_player"):
			var target_node: Node3D = col as Node3D
			if player.global_position.distance_to(target_node.global_position) <= 4.5:
				target_node.call("interact_with_player", player)


## Tombol AKSI cuma muncul kalau ada objek yang bisa disentuh di sekitar.
func _update_interact_button() -> void:
	if btn_interact == null:
		return
	# selama menu/dialog terbuka semua kontrol gerakan disembunyikan
	if _is_menu_open() or DialogueManager.is_dialogue_active:
		btn_interact.visible = false
		return
	var player: PlayerController = _get_player()
	if player == null or player.interact_area == null:
		if btn_interact.visible:
			btn_interact.visible = false
		return
	var found: bool = false
	for area in player.interact_area.get_overlapping_areas():
		if area.has_method("interact_with_player"):
			found = true
			break
	if not found:
		for body in player.interact_area.get_overlapping_bodies():
			if body.has_method("interact_with_player"):
				found = true
				break
	if btn_interact.visible != found:
		btn_interact.visible = found


# ════════════════════════════════════════════════════════════════════════
# Tombol aksi
# ════════════════════════════════════════════════════════════════════════

func on_btn_attack_pressed() -> void:
	var p: PlayerController = _get_player()
	if p != null:
		p.trigger_attack()


func on_btn_dodge_pressed() -> void:
	var p: PlayerController = _get_player()
	if p != null:
		p.trigger_dodge()


func on_btn_interact_pressed() -> void:
	var p: PlayerController = _get_player()
	if p != null:
		p.trigger_contextual_interact()


# ════════════════════════════════════════════════════════════════════════
# Pembacaan status
# ════════════════════════════════════════════════════════════════════════

func _refresh_all_readouts() -> void:
	_on_hp_changed(GameState.current_hp, GameState.max_hp)
	_on_stamina_changed(GameState.current_stamina, GameState.max_stamina)
	_on_oil_changed(GameState.current_lantern_oil, GameState.max_lantern_oil)
	_on_currency_changed(GameState.koin_embun, GameState.pecahan_kelip)


func _on_hp_changed(cur: int, mx: int) -> void:
	if hp_bar != null:
		hp_bar.max_value = mx
		hp_bar.value = cur


func _on_stamina_changed(cur: float, mx: float) -> void:
	if stamina_bar != null:
		stamina_bar.max_value = mx
		stamina_bar.value = cur


func _on_oil_changed(cur: float, mx: float) -> void:
	if oil_bar != null:
		oil_bar.max_value = mx
		oil_bar.value = cur


func _on_currency_changed(embun: int, _kelip: int) -> void:
	if coin_label != null:
		coin_label.text = str(embun)


func _on_chunk_entered(_chunk_id: String, region_name: String) -> void:
	_show_toast(region_name)


func _on_toast_notification(msg: String, _cat: String) -> void:
	_show_toast(msg)


func _show_toast(msg: String) -> void:
	if toast_label == null:
		return
	toast_label.text = msg
	toast_label.modulate.a = 1.0
	if is_instance_valid(_toast_tween):
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(TOAST_HOLD)
	_toast_tween.tween_property(toast_label, "modulate:a", 0.0, TOAST_FADE)


# ════════════════════════════════════════════════════════════════════════
# Dialog
# ════════════════════════════════════════════════════════════════════════

func _on_dialogue_started(_npc_id: String, node_id: String) -> void:
	if dialogue_panel == null or not DialogueManager.dialogue_db.has(node_id):
		return
	dialogue_panel.visible = true
	_sync_controls_visibility()
	var entry: Dictionary = DialogueManager.dialogue_db[node_id]
	if dialogue_speaker != null:
		dialogue_speaker.text = String(entry.get("speaker", ""))
	if dialogue_text != null:
		dialogue_text.text = String(entry.get("text", ""))
	if choices_box == null:
		return
	for child in choices_box.get_children():
		child.queue_free()
	var ch_list: Array = entry.get("choices", [])
	for i in range(ch_list.size()):
		var c_dict: Dictionary = ch_list[i]
		var btn: Button = Button.new()
		btn.custom_minimum_size = Vector2(0, CHOICE_BUTTON_HEIGHT)
		btn.add_theme_stylebox_override("normal", WIDE_BUTTON_NORMAL)
		btn.add_theme_stylebox_override("hover", WIDE_BUTTON_HOVER)
		btn.add_theme_stylebox_override("pressed", WIDE_BUTTON_PRESSED)
		btn.text = "▸ " + String(c_dict.get("label", "Lanjut"))
		var idx: int = i
		btn.pressed.connect(func() -> void: DialogueManager.select_choice(idx))
		choices_box.add_child(btn)


func _on_dialogue_ended(_npc_id: String) -> void:
	if dialogue_panel != null:
		dialogue_panel.visible = false
	_sync_controls_visibility()


# ════════════════════════════════════════════════════════════════════════
# Jurnal: perlengkapan
# ════════════════════════════════════════════════════════════════════════

func _refresh_equipment_readouts() -> void:
	if slot_weapon_label != null:
		slot_weapon_label.text = _item_short_name(GameState.equipped_weapon_id)
	if slot_cloak_label != null:
		slot_cloak_label.text = _item_short_name(GameState.equipped_cloak_id)
	if slot_lantern_label != null:
		slot_lantern_label.text = _item_short_name(GameState.equipped_lantern_id)


## "wpn_dayung_retak" -> "Dayung Retak"
func _item_short_name(item_id: String) -> String:
	if item_id.is_empty():
		return "Kosong"
	var parts: PackedStringArray = item_id.split("_")
	if parts.size() < 2:
		return item_id.capitalize()
	var words: Array[String] = []
	for i in range(1, parts.size()):
		words.append(parts[i].capitalize())
	return " ".join(words)


# ════════════════════════════════════════════════════════════════════════
# Angka kerusakan melayang
# ════════════════════════════════════════════════════════════════════════

func _on_floating_damage_spawned(_world_pos: Vector3, amount: int, is_crit: bool, is_light: bool) -> void:
	var lbl: Label = Label.new()
	lbl.text = "%d%s" % [amount, "!" if is_crit else ""]
	lbl.modulate = Color(1.0, 0.92, 0.55) if is_light else Color(0.95, 0.78, 0.72)
	lbl.position = Vector2(640.0 + randf_range(-45.0, 45.0), 300.0 + randf_range(-25.0, 25.0))
	add_child(lbl)
	var tw: Tween = create_tween()
	tw.tween_property(lbl, "position:y", lbl.position.y - 42.0, 0.55)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.55)
	tw.tween_callback(lbl.queue_free)


func _get_player() -> PlayerController:
	var nodes: Array[Node] = get_tree().get_nodes_in_group("player")
	if nodes.size() > 0 and nodes[0] is PlayerController:
		return nodes[0] as PlayerController
	return null
