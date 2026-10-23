class_name TouchHUDController
extends CanvasLayer
## Mobile Touch-Only HUD for LANTERNFALL (Godot 4.7).
## Implements left virtual joystick, right action cluster (>= 64px / 48dp buttons: Attack, Dodge, Skill 1, Skill 2, Contextual Interact),
## tap-to-interact raycast on 3D world objects, notch safe-area margins, animated floating damage numbers,
## branching dialogue panel, Inventory/Crafting/SkillTree/Pondok/Map tabs, Settings menu, and Credits screen.

@export var player_path: NodePath

var _joystick_touch_idx: int = -1
var _joystick_center: Vector2 = Vector2(150.0, 560.0)
var _joystick_radius: float = 72.0
var _joystick_vec: Vector2 = Vector2.ZERO

@onready var safe_margin: MarginContainer = $SafeAreaMargin
@onready var hp_bar: ProgressBar = $SafeAreaMargin/TopBar/StatsBox/HPBar
@onready var stamina_bar: ProgressBar = $SafeAreaMargin/TopBar/StatsBox/StaminaBar
@onready var oil_bar: ProgressBar = $SafeAreaMargin/TopBar/StatsBox/OilBar
@onready var currency_label: Label = $SafeAreaMargin/TopBar/CurrencyLabel
@onready var region_banner: Label = $SafeAreaMargin/TopBar/RegionBanner
@onready var dialogue_panel: PanelContainer = $SafeAreaMargin/DialoguePanel
@onready var dialogue_speaker: Label = $SafeAreaMargin/DialoguePanel/VBox/SpeakerLabel
@onready var dialogue_text: RichTextLabel = $SafeAreaMargin/DialoguePanel/VBox/BodyText
@onready var choices_box: VBoxContainer = $SafeAreaMargin/DialoguePanel/VBox/ChoicesBox
@onready var pause_tab_panel: PanelContainer = $SafeAreaMargin/PauseMenuPanel
@onready var credits_panel: PanelContainer = $SafeAreaMargin/CreditsPanel
@onready var joystick_pad: JoystickPad = $JoystickPad
@onready var slot_weapon_label: Label = $SafeAreaMargin/PauseMenuPanel/PauseVBox/EquipRow/SlotWeapon/SlotWeaponLabel
@onready var slot_cloak_label: Label = $SafeAreaMargin/PauseMenuPanel/PauseVBox/EquipRow/SlotCloak/SlotCloakLabel
@onready var slot_lantern_label: Label = $SafeAreaMargin/PauseMenuPanel/PauseVBox/EquipRow/SlotLantern/SlotLanternLabel

## StyleBox tombol lebar (dobo_ui) untuk pilihan dialog — butuh tinggi >= 92px
## karena margin 9-patch ujungnya 46px, jadi tidak dipasang di tema global.
const WIDE_BUTTON_NORMAL = preload("res://assets/ui/styles/button_wide_normal.tres")
const WIDE_BUTTON_HOVER = preload("res://assets/ui/styles/button_wide_hover.tres")
const WIDE_BUTTON_PRESSED = preload("res://assets/ui/styles/button_wide_pressed.tres")
const CHOICE_BUTTON_HEIGHT: int = 100

func _ready() -> void:
	_apply_notch_safe_area()
	_refresh_equipment_readouts()
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

func _apply_notch_safe_area() -> void:
	if safe_margin == null:
		return
	var safe_rect: Rect2i = DisplayServer.get_display_safe_area()
	var win_size: Vector2i = DisplayServer.window_get_size()
	if win_size.x > 0 and win_size.y > 0:
		var left_pad: int = maxi(24, safe_rect.position.x)
		var top_pad: int = maxi(16, safe_rect.position.y)
		var right_pad: int = maxi(24, win_size.x - (safe_rect.position.x + safe_rect.size.x))
		var bottom_pad: int = maxi(16, win_size.y - (safe_rect.position.y + safe_rect.size.y))
		safe_margin.add_theme_constant_override("margin_left", left_pad)
		safe_margin.add_theme_constant_override("margin_top", top_pad)
		safe_margin.add_theme_constant_override("margin_right", right_pad)
		safe_margin.add_theme_constant_override("margin_bottom", bottom_pad)

func _unhandled_input(event: InputEvent) -> void:
	var player: PlayerController = _get_player()
	if player == null:
		return

	if event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event as InputEventScreenTouch
		if st.pressed:
			# Left half of screen controls virtual joystick
			if st.position.x < 520.0 and st.position.y > 300.0 and _joystick_touch_idx == -1:
				_joystick_touch_idx = st.index
				_joystick_center = st.position
				_update_joystick_delta(st.position, player)
			else:
				# Tap-to-interact raycast on 3D world objects
				_try_tap_to_interact(st.position, player)
		else:
			if st.index == _joystick_touch_idx:
				_joystick_touch_idx = -1
				_joystick_vec = Vector2.ZERO
				player.set_touch_move_vector(Vector2.ZERO)
				if joystick_pad != null:
					joystick_pad.release()

	elif event is InputEventScreenDrag:
		var sd: InputEventScreenDrag = event as InputEventScreenDrag
		if sd.index == _joystick_touch_idx:
			_update_joystick_delta(sd.position, player)

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

# Right-hand Touch Action Button callbacks (each button >= 64x64 px / 48dp minimum with scale bounce feedback)
func on_btn_attack_pressed() -> void:
	var p: PlayerController = _get_player()
	if p != null:
		p.trigger_attack()

func on_btn_dodge_pressed() -> void:
	var p: PlayerController = _get_player()
	if p != null:
		p.trigger_dodge()

func on_btn_skill1_pressed() -> void:
	var p: PlayerController = _get_player()
	if p != null:
		p.trigger_skill_1_sinar_fokus()

func on_btn_skill2_pressed() -> void:
	var p: PlayerController = _get_player()
	if p != null:
		p.trigger_skill_2_perisai_senja()

func on_btn_interact_pressed() -> void:
	var p: PlayerController = _get_player()
	if p != null:
		p.trigger_contextual_interact()

func on_btn_lockon_pressed() -> void:
	var p: PlayerController = _get_player()
	if p != null:
		p.toggle_lock_on()

func on_btn_toggle_pause_menu() -> void:
	if pause_tab_panel != null:
		pause_tab_panel.visible = not pause_tab_panel.visible
		_refresh_equipment_readouts()
		AudioBus.play_sfx("ui_tap", 1.0, 1.05)

## Mengisi 3 slot perlengkapan di panel Jurnal dari GameState.
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

func on_btn_toggle_credits() -> void:
	if credits_panel != null:
		credits_panel.visible = not credits_panel.visible
		AudioBus.play_sfx("ui_tap", 1.0, 1.05)

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

func _on_currency_changed(embun: int, kelip: int) -> void:
	if currency_label != null:
		currency_label.text = "Koin Embun: %d   |   Pecahan Kelip: %d" % [embun, kelip]

func _on_chunk_entered(_chunk_id: String, region_name: String) -> void:
	if region_banner != null:
		region_banner.text = region_name

func _on_dialogue_started(_npc_id: String, node_id: String) -> void:
	if dialogue_panel == null or not DialogueManager.dialogue_db.has(node_id):
		return
	dialogue_panel.visible = true
	var entry: Dictionary = DialogueManager.dialogue_db[node_id]
	if dialogue_speaker != null:
		dialogue_speaker.text = String(entry.get("speaker", ""))
	if dialogue_text != null:
		dialogue_text.text = String(entry.get("text", ""))
	if choices_box != null:
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

func _on_toast_notification(msg: String, _cat: String) -> void:
	if region_banner != null:
		region_banner.text = msg

func _get_player() -> PlayerController:
	var nodes: Array[Node] = get_tree().get_nodes_in_group("player")
	if nodes.size() > 0 and nodes[0] is PlayerController:
		return nodes[0] as PlayerController
	return null
