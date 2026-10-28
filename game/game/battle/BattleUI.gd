extends Control
## The battle interface: parchment, ink, brass - the same kit as the rest of the
## game (step 1's field HUD), because a battle screen in a different style would
## look like a different game.
##
## What it owns:
##   * the command menu (Serang / Skill / Item / Bertahan / Kabur) and the big
##     BOOST button, which is deliberately the largest control on screen;
##   * the turn bar: the next eight actors, Speed order, redrawn every turn;
##   * the Shield pips and the weakness "?" row over every enemy, plus the full
##     6x6 weapon/element grid for the selected enemy - the board the player is
##     really learning;
##   * the party status strip: HP, SP, BP;
##   * floating damage numbers, 1x/2x/3x speed and Auto;
##   * the result screen.
##
## It never computes a number. `BattleScene` plays the engine's events and calls
## the small setters here; this file only draws and emits what the player tapped.

signal action_chosen(action: Dictionary)
signal speed_changed(speed: int)
signal auto_toggled(on: bool)
signal result_closed

## UiKit lives in the `core` package, this file in `enemies`. Loaded by PATH at
## runtime rather than preloaded, so neither package drags the other in at
## compile time (the packs are mounted separately by the launcher).
const KIT_PATH := "res://game/ui/UiKit.gd"
const FONT_BODY := "res://game/assets/PixelifySans.woff2"

## Untyped on purpose: `Script` as a static type would make the compiler look for
## `button()` on the Script base class, while a dynamic call on the script object
## is exactly how `const KIT = preload(...)` calls a static function.
static var _kit_cache = null


func _kit():
	if _kit_cache == null:
		_kit_cache = load(KIT_PATH)
	return _kit_cache

const LEATHER := Color(0.20, 0.15, 0.11)
const BRASS := Color(0.70, 0.55, 0.28)
const CREAM := Color(0.98, 0.94, 0.86)
const GOLD := Color(0.93, 0.78, 0.42)
const INK := Color(0.17, 0.12, 0.09)
const DANGER := Color(0.72, 0.20, 0.14)
const WEAK := Color(0.86, 0.42, 0.20)

var logic: RefCounted = null
var view: Node3D = null
var speed := 1
var auto := false
## Set by the controller while it is waiting for a tap. Informational: the menu
## itself already follows `logic.awaiting`, which cannot drift.
var awaiting_ready := false

var _root: Control
var _turn_bar: HBoxContainer
var _tools: HBoxContainer
var _party_plate: PanelContainer
var _result_panel: PanelContainer
var _marks: Dictionary = {}        ## uid -> {plate, name, pips, weak} above an enemy
var _hit_boxes: Dictionary = {}    ## uid -> Button (tap an enemy)
var _popups: Control
var _log: Label
var _log_lines: Array = []
var _command: PanelContainer
var _command_box: VBoxContainer
var _sub: PanelContainer
var _sub_box: VBoxContainer
var _boost_btn: Button
var _speed_btn: Button
var _auto_btn: Button
var _party_box: HBoxContainer
var _selected := -1
var _boost := 0
var _grid_panel: PanelContainer
var _grid_box: VBoxContainer
var _result: Control
var _result_label: RichTextLabel


func setup(battle_logic: RefCounted, battle_view: Node3D) -> void:
	logic = battle_logic
	view = battle_view
	# Anchors written out, not `set_anchors_preset`: this control is a direct
	# child of a CanvasLayer, has no Control parent, and a preset alone left it a
	# fixed rect at (0,0). Every corner below is then placed from `size`.
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	resized.connect(_layout)
	_layout()
	refresh()


# ------------------------------------------------------------------- build ---
func _build() -> void:
	# turn bar, top left
	var plate := _plate()
	plate.position = Vector2(20, 14)
	add_child(plate)
	_turn_bar = HBoxContainer.new()
	_turn_bar.add_theme_constant_override("separation", 6)
	plate.add_child(_turn_bar)

	# speed + auto, top right
	var tools := HBoxContainer.new()
	tools.name = "Tools"
	tools.add_theme_constant_override("separation", 8)
	_tools = tools
	add_child(tools)
	_speed_btn = _kit().chip("1x", Vector2(76, 48))
	_speed_btn.pressed.connect(_cycle_speed)
	tools.add_child(_speed_btn)
	_auto_btn = _kit().chip("Auto", Vector2(96, 48))
	_auto_btn.pressed.connect(_toggle_auto)
	tools.add_child(_auto_btn)

	# message line, bottom centre-left
	_log = _kit().label("", 17, CREAM)
	_log.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_log.add_theme_constant_override("outline_size", 4)
	_log.custom_minimum_size = Vector2(700, 40)
	add_child(_log)

	# party strip, bottom left
	var party_plate := _plate()
	_party_plate = party_plate
	add_child(party_plate)
	_party_box = HBoxContainer.new()
	_party_box.add_theme_constant_override("separation", 14)
	party_plate.add_child(_party_box)

	# command menu, bottom right
	_command = _plate()
	add_child(_command)
	_command_box = VBoxContainer.new()
	_command_box.add_theme_constant_override("separation", 8)
	_command.add_child(_command_box)
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	_command_box.add_child(row1)
	var attack : Button = _kit().button("Serang", Vector2(150, 54))
	attack.name = "Serang"
	attack.pressed.connect(func() -> void: _emit({"kind": "attack"}))
	row1.add_child(attack)
	var skill : Button = _kit().button("Skill", Vector2(118, 54))
	skill.name = "Skill"
	skill.pressed.connect(_open_skills)
	row1.add_child(skill)
	var item : Button = _kit().button("Item", Vector2(112, 54))
	item.name = "Item"
	item.pressed.connect(_open_items)
	row1.add_child(item)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	_command_box.add_child(row2)
	var guard : Button = _kit().button("Bertahan", Vector2(150, 48))
	guard.name = "Bertahan"
	guard.pressed.connect(func() -> void: _emit({"kind": "guard"}))
	row2.add_child(guard)
	var flee : Button = _kit().button("Kabur", Vector2(120, 48))
	flee.name = "Kabur"
	flee.pressed.connect(func() -> void: _emit({"kind": "flee"}))
	row2.add_child(flee)
	# the BOOST button: the biggest thing on screen, as asked
	_boost_btn = _kit().button("BOOST", Vector2(190, 76), 26)
	_boost_btn.name = "BOOST"
	_boost_btn.pressed.connect(_cycle_boost)
	row2.add_child(_boost_btn)

	# sub menu (skills / items), appears above the command menu
	_sub = _plate()
	_sub.visible = false
	add_child(_sub)
	_sub_box = VBoxContainer.new()
	_sub_box.add_theme_constant_override("separation", 6)
	_sub.add_child(_sub_box)

	# the 6x6 knowledge board for the selected enemy
	_grid_panel = _plate()
	_grid_panel.position = Vector2(20, 96)
	_grid_panel.visible = false
	add_child(_grid_panel)
	_grid_box = VBoxContainer.new()
	_grid_box.add_theme_constant_override("separation", 4)
	_grid_panel.add_child(_grid_box)

	_popups = Control.new()
	_popups.name = "Popups"
	_popups.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popups.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_popups)

	_result = _build_result()


## Every corner is placed from `size`, in one function, and re-run on every
## resize. The first version wrote `position = Vector2(-430, -210)` on a control
## whose anchors had just been set to the BOTTOM-RIGHT corner: `position` is
## measured from the parent's top-left, not from the anchor, so the command menu,
## the party strip, the speed buttons and the result sheet all landed off the
## left/top edge of the screen - visible only as a parchment sliver in the corner
## of the first ten battle screenshots. Anchors stay at 0 so `position` means what
## it looks like it means.
func _layout() -> void:
	var w := size.x
	var h := size.y
	if w <= 1.0:
		w = 1280.0
	if h <= 1.0:
		h = 720.0
	if _tools != null:
		_tools.position = Vector2(w - 200.0, 18.0)
	if _log != null:
		_log.position = Vector2(26.0, h - 246.0)
	if _party_plate != null:
		_party_plate.position = Vector2(20.0, h - 138.0)
	if _command != null:
		# the menu is as wide as its own content (Serang/Skill/Item on one row,
		# Bertahan/Kabur/BOOST on the next); an earlier version assumed 430 px and
		# the BOOST button - the biggest control in the game - hung off the edge
		_command.position = Vector2(w - _command.get_combined_minimum_size().x - 18.0,
			h - _command.get_combined_minimum_size().y - 18.0)
	if _sub != null:
		var sub_w := 320.0
		_sub.position = Vector2(w - sub_w - 24.0, h - 470.0)
	if _result_panel != null:
		_result_panel.position = Vector2((w - 520.0) * 0.5, (h - 360.0) * 0.5)


func _plate() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _kit().parchment())
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	return p


func _build_result() -> Control:
	var wrap := Control.new()
	wrap.name = "Result"
	wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.04, 0.03, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.add_child(dim)
	var panel := _plate()
	_result_panel = panel
	panel.custom_minimum_size = Vector2(520, 360)
	wrap.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	_result_label = RichTextLabel.new()
	_result_label.bbcode_enabled = true
	_result_label.fit_content = true
	_result_label.custom_minimum_size = Vector2(470, 240)
	_result_label.add_theme_font_override("normal_font", _kit().font(FONT_BODY, 1))
	_result_label.add_theme_font_size_override("normal_font_size", 19)
	_result_label.add_theme_color_override("default_color", INK)
	box.add_child(_result_label)
	var ok : Button = _kit().button("Lanjut", Vector2(240, 56))
	ok.name = "Lanjut"
	ok.pressed.connect(func() -> void:
		wrap.visible = false
		result_closed.emit())
	box.add_child(ok)
	add_child(wrap)
	return wrap


# ------------------------------------------------------------------ refresh ---
## Redraw everything that can change. Cheap enough (a few dozen nodes) and it
## cannot drift from the engine, which is the whole point.
func refresh() -> void:
	if logic == null:
		return
	_refresh_turn_bar()
	_refresh_marks()
	_refresh_party()
	_refresh_commands()
	_refresh_grid()


func _refresh_turn_bar() -> void:
	if _turn_bar == null:
		return
	for child in _turn_bar.get_children():
		child.queue_free()
	for raw in logic.call("turn_preview"):
		var unit: Dictionary = raw
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", _kit().parchment_small())
		# the DISTINGUISHING word, not the first six characters: `substr(0, 6)`
		# turned "Orc Prajurit", "Orc Pengintai" and "Orc Pemimpin" into eight
		# identical "Orc Pe" chips, which is a turn bar that says nothing
		var label : Label = _kit().label(_short_name(String(unit["name"])), 13,
			INK if String(unit["side"]) == "ally" else Color(0.42, 0.12, 0.09))
		chip.add_child(label)
		if bool(unit["broken"]):
			chip.modulate = Color(0.65, 0.60, 0.75)
		_turn_bar.add_child(chip)


## "Orc Pemimpin" -> "Pemimpin". The full name is on the plate over the enemy,
## so the bar only has to tell the unit TYPES apart - and a whole word is both
## shorter and readable, where a fixed-length cut is neither. A name with no
## space is used as it is.
func _short_name(full: String) -> String:
	var cut := full.find(" ")
	if cut <= 0 or cut + 1 >= full.length():
		return full
	return full.substr(cut + 1)


func _refresh_marks() -> void:
	var seen: Dictionary = {}
	for raw in logic.get("units"):
		var unit: Dictionary = raw
		# allies are on the party strip at the bottom; a Shield plate with three
		# "?" over the hero would be a lie
		if String(unit["side"]) != "foe":
			continue
		var uid := int(unit["uid"])
		seen[uid] = true
		var entry: Dictionary = _marks.get(uid, {})
		if entry.is_empty():
			entry = _make_mark(unit)
			_marks[uid] = entry
		_update_mark(entry, unit)
		var plate: Control = entry["plate"]
		plate.visible = bool(unit["alive"])
	for uid in _marks.keys():
		if not seen.has(uid):
			var gone: Dictionary = _marks[uid]
			(gone["plate"] as Control).queue_free()
			_marks.erase(uid)
			if _hit_boxes.has(uid):
				(_hit_boxes[uid] as Button).queue_free()
				_hit_boxes.erase(uid)


## The plate above one enemy: name, Shield pips, the "?" row - and, kept in the
## same dictionary, the labels themselves. An earlier draft looked them up again
## with `get_node()` on every refresh, which is both slower and a typed-assignment
## trap (`get_node()` hands back a `Node`).
func _make_mark(unit: Dictionary) -> Dictionary:
	var plate := PanelContainer.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_theme_stylebox_override("panel", _kit().parchment_small())
	plate.modulate = Color(1.0, 1.0, 1.0, 0.94)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(box)
	var name_label: Label = _kit().label(String(unit["name"]), 13, INK)
	box.add_child(name_label)
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 3)
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(pips)
	var weak := HBoxContainer.new()
	weak.add_theme_constant_override("separation", 2)
	weak.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(weak)
	# a tap target over the sprite itself, so picking a target is one thumb tap
	var hit := Button.new()
	hit.name = "Hit%d" % int(unit["uid"])
	hit.flat = true
	hit.modulate = Color(1, 1, 1, 0.0)
	hit.custom_minimum_size = Vector2(96, 110)
	hit.pressed.connect(func() -> void: select_target(int(unit["uid"])))
	_hit_boxes[int(unit["uid"])] = hit
	# both go straight onto the interface: the plate is a label, the button is the
	# thing the thumb hits, and neither is a child of the other
	add_child(plate)
	add_child(hit)
	return {"plate": plate, "name": name_label, "pips": pips, "weak": weak}


func _update_mark(entry: Dictionary, unit: Dictionary) -> void:
	var name_label: Label = entry["name"]
	name_label.text = String(unit["name"])
	var pips: HBoxContainer = entry["pips"]
	for child in pips.get_children():
		child.queue_free()
	var shield := int(unit["shield"])
	var shield_max := maxi(1, int(unit["shield_max"]))
	for i in range(shield_max):
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(9, 9)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if bool(unit["broken"]):
			pip.color = Color(0.45, 0.38, 0.62)
		elif i < shield:
			pip.color = BRASS
		else:
			pip.color = Color(0.55, 0.48, 0.40, 0.35)
		pips.add_child(pip)
	var weak: HBoxContainer = entry["weak"]
	for child in weak.get_children():
		child.queue_free()
	# the "?" row: an icon appears only once the party has hit that weakness
	var observed: Dictionary = logic.get("observed")
	var known: Array = observed.get(String(unit["id"]), [])
	var shown := 0
	for tag in known:
		if shown >= 4:
			break
		var icon: TextureRect = _kit().icon_rect(_icon_for(String(tag)), 18)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		weak.add_child(icon)
		shown += 1
	var slot_count := maxi(3, (unit["weak"] as Array).size())
	while shown < slot_count and shown < 4:
		var q: Label = _kit().label("?", 15, Color(0.35, 0.28, 0.22))
		q.mouse_filter = Control.MOUSE_FILTER_IGNORE
		weak.add_child(q)
		shown += 1


func _icon_for(tag: String) -> String:
	for w in (logic.get("data").get("weapons") as Array):
		if String(w) == tag:
			return "w_" + tag
	for e in (logic.get("data").get("elements") as Array):
		if String(e) == tag:
			return "e_" + tag
	return "perisai"


func _refresh_party() -> void:
	if _party_box == null:
		return
	for child in _party_box.get_children():
		child.queue_free()
	for raw in logic.get("allies"):
		var unit: Dictionary = raw
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		var title : Label = _kit().label("%s  Lv %d" % [String(unit["name"]), int(logic.get("level"))], 15, INK)
		col.add_child(title)
		col.add_child(_bar(float(unit["hp"]) / maxf(1.0, float(unit["hp_max"])),
			Color(0.55, 0.20, 0.16), "HP %d/%d" % [int(unit["hp"]), int(unit["hp_max"])]))
		col.add_child(_bar(float(unit["sp"]) / maxf(1.0, float(unit["sp_max"])),
			Color(0.25, 0.35, 0.55), "SP %d/%d" % [int(unit["sp"]), int(unit["sp_max"])]))
		var bp_row := HBoxContainer.new()
		bp_row.add_theme_constant_override("separation", 3)
		var bp_label : Label = _kit().label("BP", 13, INK)
		bp_row.add_child(bp_label)
		for i in range(int(logic.get("data").call("balance_int", "bp_max", 5))):
			var pip := ColorRect.new()
			pip.custom_minimum_size = Vector2(12, 12)
			pip.color = GOLD if i < int(unit["bp"]) else Color(0.5, 0.42, 0.30, 0.3)
			bp_row.add_child(pip)
		col.add_child(bp_row)
		_party_box.add_child(col)


func _bar(ratio: float, colour: Color, text: String) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(230, 20)
	var bg := ColorRect.new()
	bg.color = Color(0.25, 0.20, 0.15, 0.35)
	bg.size = Vector2(230, 16)
	wrap.add_child(bg)
	var fill := ColorRect.new()
	fill.color = colour
	fill.size = Vector2(230.0 * clampf(ratio, 0.0, 1.0), 16)
	wrap.add_child(fill)
	var label : Label = _kit().label(text, 12, CREAM)
	label.position = Vector2(6, -1)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 3)
	wrap.add_child(label)
	return wrap


func _refresh_commands() -> void:
	if _boost_btn == null:
		return
	var awaiting: Dictionary = logic.get("awaiting")
	var mine := not awaiting.is_empty() and String(awaiting["side"]) == "ally"
	var bp := int(awaiting.get("bp", 0)) if mine else 0
	var cap: int = mini(bp, int(logic.get("data").call("balance_int", "bp_spend_max", 3)))
	if _boost > cap:
		_boost = cap
	_boost_btn.text = "BOOST" if _boost == 0 else "BOOST x%d" % (_boost + 1)
	_boost_btn.disabled = not mine or cap <= 0
	_command.visible = mine and _result.visible == false
	_log.text = String(_log_lines[-1]) if not _log_lines.is_empty() else ""


# ------------------------------------------------------------------ actions ---
func _cycle_boost() -> void:
	var awaiting: Dictionary = logic.get("awaiting")
	if awaiting.is_empty():
		return
	var cap: int = mini(int(awaiting.get("bp", 0)),
		int(logic.get("data").call("balance_int", "bp_spend_max", 3)))
	_boost = (_boost + 1) % (cap + 1)
	_refresh_commands()


func _emit(action: Dictionary) -> void:
	if _result.visible:
		return
	action["boost"] = _boost
	if not action.has("target"):
		action["target"] = _target_uid()
	action_chosen.emit(action)
	_boost = 0
	_sub.visible = false
	_boost_btn.text = "BOOST"


func _target_uid() -> int:
	if _selected >= 0:
		for raw in logic.get("foes"):
			var unit: Dictionary = raw
			if int(unit["uid"]) == _selected and bool(unit["alive"]):
				return _selected
	for raw in logic.get("foes"):
		var unit: Dictionary = raw
		if bool(unit["alive"]):
			return int(unit["uid"])
	return -1


func select_target(uid: int) -> void:
	_selected = uid
	_refresh_grid()
	refresh()


func _open_skills() -> void:
	var awaiting: Dictionary = logic.get("awaiting")
	if awaiting.is_empty():
		return
	for child in _sub_box.get_children():
		child.queue_free()
	var title : Label = _kit().label("Skill", 17, INK, true)
	_sub_box.add_child(title)
	for raw in (awaiting.get("skills", []) as Array):
		var sk: Dictionary = logic.get("data").call("skill", String(raw))
		if sk.is_empty():
			continue
		var cost := int(sk.get("sp", 0))
		var enough := int(awaiting["sp"]) >= cost
		var b : Button = _kit().button("%s  (%d SP)" % [String(sk.get("name", "")), cost], Vector2(300, 46), 16)
		b.disabled = not enough
		var id := String(sk.get("id", ""))
		b.pressed.connect(func() -> void: _emit({"kind": "skill", "id": id}))
		_sub_box.add_child(b)
	var back : Button = _kit().chip("Tutup", Vector2(120, 42))
	back.pressed.connect(func() -> void: _sub.visible = false)
	_sub_box.add_child(back)
	_sub.visible = true


func _open_items() -> void:
	var awaiting: Dictionary = logic.get("awaiting")
	if awaiting.is_empty():
		return
	for child in _sub_box.get_children():
		child.queue_free()
	_sub_box.add_child(_kit().label("Item", 17, INK, true))
	# the inventory is party-wide and lives in the engine; the unit dictionary has
	# no item list, and asking it for one (as an earlier draft did) drew an empty
	# menu with nothing but a Close button on it
	var inventory: Dictionary = logic.get("inventory")
	var data = logic.get("data")
	for raw in (data.call("items") as Array):
		var item: Dictionary = raw
		var id := String(item.get("id", ""))
		var count := int(inventory.get(id, 0))
		if count <= 0:
			continue
		var b : Button = _kit().button("%s  x%d" % [String(item.get("name", id)), count], Vector2(300, 46), 16)
		b.disabled = count <= 0
		b.pressed.connect(func() -> void: _emit({"kind": "item", "id": id}))
		_sub_box.add_child(b)
	var back : Button = _kit().chip("Tutup", Vector2(120, 42))
	back.pressed.connect(func() -> void: _sub.visible = false)
	_sub_box.add_child(back)
	_sub.visible = true


func _cycle_speed() -> void:
	speed = 1 if speed == 3 else speed + 1
	_speed_btn.text = "%dx" % speed
	speed_changed.emit(speed)


func _toggle_auto() -> void:
	auto = not auto
	_auto_btn.text = "Auto ●" if auto else "Auto"
	auto_toggled.emit(auto)


# ------------------------------------------------------------------ effects ---
func float_text(screen_pos: Vector2, text: String, colour: Color, big: bool = false) -> void:
	if _popups == null:
		return
	var label : Label = _kit().label(text, 30 if big else 22, colour, big)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 5)
	label.position = screen_pos + Vector2(-24, -16)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popups.add_child(label)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position", label.position + Vector2(0, -54), 0.75)
	tween.tween_property(label, "modulate:a", 0.0, 0.75).set_delay(0.25)
	tween.set_parallel(false)
	tween.tween_callback(func() -> void:
		if is_instance_valid(label):
			label.queue_free())


func note(text: String) -> void:
	if text.strip_edges() == "":
		return
	_log_lines.append(text)
	if _log_lines.size() > 40:
		_log_lines.remove_at(0)
	if _log != null:
		_log.text = text


## The 6x6 board: every weapon and element, "?" until the party has hit that
## weakness, and a dimmed icon for the ones it has tried and found nothing.
func _refresh_grid() -> void:
	if _grid_box == null:
		return
	if _selected < 0:
		_grid_panel.visible = false
		return
	var unit := {}
	for raw in logic.get("foes"):
		var row: Dictionary = raw
		if int(row["uid"]) == _selected:
			unit = row
	if unit.is_empty():
		_grid_panel.visible = false
		return
	for child in _grid_box.get_children():
		child.queue_free()
	_grid_box.add_child(_kit().label("Kelemahan: %s" % String(unit["name"]), 15, INK, true))
	var data = logic.get("data")
	var observed: Dictionary = logic.get("observed")
	var known: Array = observed.get(String(unit["id"]), [])
	for label_text in ["Senjata", "Elemen"]:
		var row_box := HBoxContainer.new()
		row_box.add_theme_constant_override("separation", 4)
		var tag_label : Label = _kit().label(label_text, 12, INK)
		tag_label.custom_minimum_size = Vector2(64, 20)
		row_box.add_child(tag_label)
		var tags: Array = data.get("weapons") if label_text == "Senjata" else data.get("elements")
		for tag in tags:
			var id := String(tag)
			if known.has(id):
				row_box.add_child(_kit().icon_rect(_icon_for(id), 20))
			else:
				var tried := _tried(id)
				var q : Label = _kit().label("?" if not tried else "·", 15,
					Color(0.35, 0.28, 0.22) if not tried else Color(0.55, 0.20, 0.15))
				q.custom_minimum_size = Vector2(20, 20)
				row_box.add_child(q)
		_grid_box.add_child(row_box)
	_grid_panel.visible = true


## Has the party already tried this type and learned it is NOT a weakness? The
## engine records only successes, so "tried" is kept here as a display hint.
func _tried(tag: String) -> bool:
	var tried: Dictionary = logic.get("tried")
	return bool(tried.get(tag, false))


## Called every frame by the controller: keeps the plates and the tap targets on
## top of their sprites as the camera shakes.
func tick_display() -> void:
	if view == null:
		return
	for raw in logic.get("units"):
		var unit: Dictionary = raw
		var uid := int(unit["uid"])
		var entry: Dictionary = _marks.get(uid, {})
		var hit: Button = _hit_boxes.get(uid, null)
		var screen := Vector2.ZERO
		if view.has_method("unit_screen"):
			screen = view.call("unit_screen", uid)
		# while the result sheet is up, no plate and no tap target belongs on screen:
		# `tick_display` runs every frame, so hiding them once in `show_result` was
		# undone on the very next frame (the "Orc Prajurit" plate sat on top of the
		# defeat text in the captured result screen)
		var sheet_up := _result != null and _result.visible
		var on_screen := screen != Vector2.ZERO and bool(unit["alive"]) and not sheet_up
		if not entry.is_empty():
			var plate: Control = entry["plate"]
			plate.visible = on_screen
			if on_screen:
				plate.position = screen - Vector2(plate.size.x * 0.5, 0.0)
		if hit != null:
			hit.visible = on_screen
			if on_screen:
				hit.position = screen - Vector2(46, 96)


# ------------------------------------------------------------------- result ---
func show_result(summary: Dictionary) -> void:
	var won := bool(summary.get("win", false))
	var lines: Array = []
	if won:
		lines.append("[b]Menang[/b]")
		lines.append("EXP +%d" % int(summary.get("exp", 0)))
		lines.append("Leaf +%d" % int(summary.get("leaf", 0)))
		var drops: Array = summary.get("drops", [])
		if not drops.is_empty():
			var names: Array = []
			for id in drops:
				var item: Dictionary = logic.get("data").call("item", String(id))
				names.append(String(item.get("name", id)))
			lines.append("Dapat: %s" % ", ".join(names))
		if bool(summary.get("level_up", false)):
			lines.append("[b]Naik ke Level %d[/b]" % int(summary.get("level", 1)))
	else:
		lines.append("[b]Kalah[/b]")
		lines.append("Kembali ke simpanan terakhir.")
		lines.append("Leaf -%d" % int(summary.get("penalty", 0)))
	if bool(summary.get("fled", false)):
		lines = ["[b]Kabur[/b]", "Kembali ke jalan."]
	_result_label.text = "\n".join(lines)
	# the plates above the enemies belong to the fight; on the result sheet they
	# float over the panel and collide with its text (the "Orc Prajurit" plate
	# landed on top of "Kembali ke simpanan terakhir" in the first shots)
	for uid in _marks.keys():
		var entry: Dictionary = _marks[uid]
		(entry["plate"] as Control).visible = false
	_result.visible = true
	_sub.visible = false
	_command.visible = false
	for uid in _marks.keys():
		var entry: Dictionary = _marks[uid]
		(entry["plate"] as Control).visible = false
	for uid in _hit_boxes.keys():
		(_hit_boxes[uid] as Button).visible = false
	_result.visible = true
	_command.visible = false
	_sub.visible = false
