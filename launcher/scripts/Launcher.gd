extends Control
## Launcher.gd - the themed update screen.
##
## Pure presentation: it renders Updater's state and forwards button presses.
## No networking, no file juggling, no game logic lives here.

@onready var _background: TextureRect = $Background
@onready var _crest_stack: Control = $SafeArea/Columns/Left/CrestStack
@onready var _title: TextureRect = $SafeArea/Columns/Left/TitleBlock/Title
@onready var _subtitle: Label = $SafeArea/Columns/Left/TitleBlock/Subtitle
@onready var _left: VBoxContainer = $SafeArea/Columns/Left
@onready var _divider: TextureRect = $SafeArea/Columns/Left/Divider
@onready var _journal: PanelContainer = $SafeArea/Columns/Left/Journal
@onready var _log_lines: Label = $SafeArea/Columns/Left/Journal/Pad/Box/LogLines
@onready var _status_line: Label = $SafeArea/Columns/Left/Journal/Pad/Box/StatusLine
@onready var _right: PanelContainer = $SafeArea/Columns/Right
@onready var _heading: Label = $SafeArea/Columns/Right/Pad/Content/HeadRow/Heading
@onready var _version_pill: Label = $SafeArea/Columns/Right/Pad/Content/HeadRow/VersionPill
@onready var _state_title: Label = $SafeArea/Columns/Right/Pad/Content/StateTitle
@onready var _detail: Label = $SafeArea/Columns/Right/Pad/Content/Detail
@onready var _progress_block: VBoxContainer = $SafeArea/Columns/Right/Pad/Content/ProgressBlock
@onready var _bar: ProgressBar = $SafeArea/Columns/Right/Pad/Content/ProgressBlock/Bar
@onready var _pkg_label: Label = $SafeArea/Columns/Right/Pad/Content/ProgressBlock/BarMeta/PkgLabel
@onready var _speed_label: Label = $SafeArea/Columns/Right/Pad/Content/ProgressBlock/BarMeta/SpeedLabel
@onready var _changelog: ScrollContainer = $SafeArea/Columns/Right/Pad/Content/Changelog
@onready var _changelog_text: RichTextLabel = $SafeArea/Columns/Right/Pad/Content/Changelog/ChangelogText
@onready var _retry_button: Button = $SafeArea/Columns/Right/Pad/Content/ButtonRow/RetryButton
@onready var _play_button: Button = $SafeArea/Columns/Right/Pad/Content/ButtonRow/PlayButton
@onready var _dust: CPUParticles2D = $Dust
@onready var _dim: ColorRect = $ModalLayer/Dim
@onready var _modal: PanelContainer = $ModalLayer/Center/Modal
@onready var _modal_title: Label = $ModalLayer/Center/Modal/Pad/Box/ModalTitle
@onready var _modal_body: Label = $ModalLayer/Center/Modal/Pad/Box/ModalBody
@onready var _modal_ok: Button = $ModalLayer/Center/Modal/Pad/Box/ModalButtons/ModalOk

var _autoplay_done := false
var _pulse_tween: Tween
var _kenburns_tween: Tween
var _sparkle_tweens: Array[Tween] = []


func _ready() -> void:
	theme = UiTheme.get_theme()
	_dim.visible = false
	_modal.visible = false
	_modal_ok.pressed.connect(func(): _hide_modal())
	_retry_button.pressed.connect(_on_retry_pressed)
	_play_button.pressed.connect(_on_play_pressed)
	_play_button.disabled = true
	_retry_button.disabled = true

	Updater.state_changed.connect(_on_state_changed)
	Updater.progress_changed.connect(_on_progress)
	Updater.plan_ready.connect(_on_plan_ready)
	Log.line_added.connect(_on_log_line)

	_refresh_status_line()
	_render_log_tail()
	_play_entrance()
	_start_ken_burns()
	_start_sparkles()

	# crash recovery happens before we ever look at the network
	var recovered := Guard.handle_startup_rollback()
	if recovered and Guard.pending_notice != "":
		_show_modal("Pemulihan Otomatis", Guard.pending_notice, "Mengerti")
		Guard.pending_notice = ""
		# do not silently re-download the version that just failed
		_on_state_changed(Updater.state, Updater.ctx)
		return

	_on_state_changed(Updater.State.CHECKING, {
		"message": "Menyiapkan…",
		"detail": "Launcher v%d" % Cfg.LAUNCHER_VERSION,
		"can_retry": false,
		"can_play": Updater.has_playable_version(),
		"version": Store.active_version(),
	})
	await get_tree().create_timer(0.25).timeout
	Updater.start()


# ------------------------------------------------------------------ visuals --
func _play_entrance() -> void:
	# Containers re-place their children every layout pass, so animating
	# `position` would be fought (and could shove the layout around). Animate
	# opacity plus a small uniform scale instead.
	var items: Array[Control] = [_crest_stack, _title, _subtitle, _divider, _journal, _right]
	for i in items.size():
		var node: Control = items[i]
		node.modulate.a = 0.0
		node.pivot_offset = node.size * 0.5
		var start_scale := Vector2(0.97, 0.97)
		node.scale = start_scale
		var tw := create_tween().set_parallel(true)
		tw.tween_property(node, "modulate:a", 1.0, 0.40).set_delay(0.06 * i) \
			.set_ease(Tween.EASE_OUT)
		tw.tween_property(node, "scale", Vector2.ONE, 0.52).set_delay(0.06 * i) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	# the crest itself settles with a soft bounce
	_crest_stack.pivot_offset = _crest_stack.size * 0.5
	_crest_stack.scale = Vector2(0.86, 0.86)
	var ct := create_tween()
	ct.tween_property(_crest_stack, "scale", Vector2.ONE, 0.7) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func _start_ken_burns() -> void:
	# very slow drift so the painted background never feels like a still image
	_background.pivot_offset = _background.size * 0.5
	_background.scale = Vector2(1.02, 1.02)
	_kenburns_tween = create_tween().set_loops()
	_kenburns_tween.tween_property(_background, "scale", Vector2(1.075, 1.075), 42.0) \
		.set_trans(Tween.TRANS_SINE)
	_kenburns_tween.tween_property(_background, "scale", Vector2(1.02, 1.02), 42.0) \
		.set_trans(Tween.TRANS_SINE)


func _start_sparkles() -> void:
	for i in 3:
		var sp := TextureRect.new()
		sp.texture = load("res://ui/textures/fx_spark.png")
		sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sp.modulate = Color(1, 0.94, 0.76, 0.0)
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sp.size = Vector2(8, 8)
		add_child(sp)
		_drive_sparkle(sp, i)


func _drive_sparkle(sp: TextureRect, seed_i: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 977 + seed_i * 131
	var tw := create_tween().set_loops()
	# park it near the crest, then twinkle
	var wait := 1.2 + rng.randf() * 3.0
	tw.tween_callback(func():
		var base := _crest_stack.get_global_rect().position
		var p := base + Vector2(rng.randf_range(-26, _crest_stack.size.x + 20),
			rng.randf_range(-18, _crest_stack.size.y + 10))
		sp.global_position = p.round()
		var s := rng.randf_range(0.7, 1.6)
		sp.scale = Vector2(s, s)
		sp.modulate.a = 1.0
	)
	tw.tween_property(sp, "modulate:a", 0.0, 0.55).set_ease(Tween.EASE_IN)
	tw.tween_interval(wait)
	_sparkle_tweens.append(tw)


func _process(_delta: float) -> void:
	# keep the vignette/scrim covering the window on any aspect ratio
	if _background.size != size:
		_background.size = size
		_background.pivot_offset = size * 0.5
	var v: TextureRect = $Vignette
	v.size = size
	var scrim: TextureRect = $Scrim
	scrim.size = size


# --------------------------------------------------------------- rendering ---
func _on_state_changed(state: int, ctx: Dictionary) -> void:
	var message := String(ctx.get("message", ""))
	var detail := String(ctx.get("detail", ""))
	var can_play := bool(ctx.get("can_play", false))
	var can_retry := bool(ctx.get("can_retry", false))
	var version := String(ctx.get("version", Store.active_version()))

	_state_title.text = message
	_detail.text = detail
	_version_pill.text = ("v" + version) if version != "" else "v—"
	_play_button.disabled = not can_play
	_retry_button.disabled = not can_retry or not _is_idle_enough()

	_state_title.remove_theme_color_override("font_color")
	_state_title.remove_theme_color_override("font_shadow_color")
	match state:
		Updater.State.CHECKING:
			_state_title.add_theme_color_override("font_color", UiTheme.COL_INK)
			_show_progress(true, true)
			_retry_button.visible = false
		Updater.State.DOWNLOADING:
			_show_progress(true, false)
			_retry_button.visible = true
			_retry_button.text = "  Jeda"
		Updater.State.VERIFYING:
			_show_progress(true, false)
			_retry_button.visible = false
		Updater.State.INSTALLING:
			_show_progress(true, true)
			_retry_button.visible = false
		Updater.State.READY:
			_show_progress(false)
			_retry_button.visible = true
			_retry_button.text = "  Periksa Lagi"
			_pulse_play_button(true)
		Updater.State.OFFLINE_READY:
			_show_progress(false)
			_retry_button.visible = true
			_retry_button.text = "  Coba Lagi"
			_state_title.add_theme_color_override("font_color", Color(0.45, 0.32, 0.14))
			_pulse_play_button(true)
		Updater.State.LAUNCHER_UPDATE_REQUIRED:
			_show_progress(false)
			_retry_button.visible = true
			_retry_button.text = "  Periksa Lagi"
			_state_title.add_theme_color_override("font_color", UiTheme.COL_RUST)
		Updater.State.ERROR:
			_show_progress(false)
			_retry_button.visible = true
			_retry_button.text = "  Coba Lagi"
			_state_title.add_theme_color_override("font_color", UiTheme.COL_RUST)
			_pulse_play_button(false)
		_:
			_show_progress(false)
			_retry_button.visible = true
	if not can_play:
		_pulse_play_button(false)

	_render_changelog(ctx)
	_refresh_status_line()

	if Cfg.autoplay_enabled() and can_play and state == Updater.State.READY and not _autoplay_done:
		_autoplay_done = true
		Log.info("Autoplay: membuka game.")
		await get_tree().create_timer(0.4).timeout
		Updater.play()


func _is_idle_enough() -> bool:
	return Updater.state != Updater.State.DOWNLOADING


func _show_progress(show_it: bool, indeterminate: bool = false) -> void:
	_progress_block.visible = show_it
	_bar.indeterminate = indeterminate
	if indeterminate:
		_pkg_label.text = "Mohon tunggu…"
		_speed_label.text = ""


func _on_progress(snap: Dictionary) -> void:
	if not _progress_block.visible:
		_progress_block.visible = true
	var pct := float(snap.get("percent", 0.0)) * 100.0
	_bar.indeterminate = false
	_bar.value = pct
	var pkg := String(snap.get("package", ""))
	if pkg != "":
		var idx := int(snap.get("pkg_index", 0)) + 1
		var count := int(snap.get("pkg_count", 0))
		_pkg_label.text = "%s  %s / %s" % [pkg, Util.human_size(int(snap.get("bytes_done", 0))),
			Util.human_size(int(snap.get("bytes_total", 0)))]
		if count > 0:
			_speed_label.text = "%s  •  %s  •  %d/%d" % [
				Util.human_speed(float(snap.get("speed_bps", 0.0))),
				Util.human_eta(float(snap.get("eta_s", -1.0))),
				idx, count]
	else:
		_pkg_label.text = "%s / %s" % [Util.human_size(int(snap.get("bytes_done", 0))),
			Util.human_size(int(snap.get("bytes_total", 0)))]
	_speed_label.text = "%s  •  %s" % [Util.human_speed(float(snap.get("speed_bps", 0.0))),
		Util.human_eta(float(snap.get("eta_s", -1.0)))] if pkg == "" else _speed_label.text
	_refresh_status_line()


func _on_plan_ready(_manifest: Dictionary, _plan: Array) -> void:
	_refresh_status_line()


func _render_changelog(ctx: Dictionary) -> void:
	var lines: PackedStringArray = ctx.get("changelog", PackedStringArray())
	var bb := ""
	if lines.is_empty():
		if not Updater.manifest.is_empty():
			lines = Manifest.changelog_lines(Updater.manifest)
	if lines.is_empty():
		_changelog_text.text = "[i][color=#7a6a52]Belum ada catatan untuk versi ini.[/color][/i]"
		return
	for i in lines.size():
		var line := lines[i].strip_edges()
		if line == "":
			continue
		bb += "[color=#c9a35a]◆[/color]  " + line
		if i < lines.size() - 1:
			bb += "\n"
	_changelog_text.text = bb


func _refresh_status_line() -> void:
	var v := Store.active_version()
	var parts := PackedStringArray()
	parts.append("versi %s" % (v if v != "" else "belum ada"))
	parts.append("launcher v%d" % Cfg.LAUNCHER_VERSION)
	var used := Store.disk_usage()
	parts.append("%s tersimpan" % Util.human_size(used))
	_status_line.text = "  •  ".join(parts)
	_heading.text = "CATATAN PEMBARUAN" if Updater.manifest.is_empty() == false else "CATATAN PERJALANAN"


func _on_log_line(entry: Dictionary) -> void:
	_render_log_tail()


func _render_log_tail() -> void:
	var lines := Log.tail(3)
	var out := PackedStringArray()
	for e in lines:
		out.append(String(e.get("text", "")))
	_log_lines.text = "\n".join(out)
	if _log_lines.text == "":
		_log_lines.text = "Jurnal peluncur siap…"


# ------------------------------------------------------------------ actions --
func _on_play_pressed() -> void:
	_pulse_play_button(false)
	Log.info("Pemain menekan Main.")
	Updater.play()


func _on_retry_pressed() -> void:
	if Updater.state == Updater.State.DOWNLOADING:
		Updater.cancel()
		return
	Updater.retry()


func _pulse_play_button(on: bool) -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = null
	_play_button.modulate = Color.WHITE
	_play_button.scale = Vector2.ONE
	if not on:
		return
	_play_button.pivot_offset = _play_button.size * 0.5
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_property(_play_button, "modulate", Color(1.14, 1.1, 0.96, 1.0), 0.9) \
		.set_trans(Tween.TRANS_SINE)
	_pulse_tween.parallel().tween_property(_play_button, "scale", Vector2(1.02, 1.02), 0.9) \
		.set_trans(Tween.TRANS_SINE)
	_pulse_tween.tween_property(_play_button, "modulate", Color.WHITE, 0.9).set_trans(Tween.TRANS_SINE)
	_pulse_tween.parallel().tween_property(_play_button, "scale", Vector2.ONE, 0.9).set_trans(Tween.TRANS_SINE)


# -------------------------------------------------------------------- modal --
func _show_modal(title: String, body: String, ok_text: String = "Mengerti") -> void:
	_modal_title.text = title
	_modal_body.text = body
	_modal_ok.text = ok_text
	_dim.visible = true
	_modal.visible = true
	_dim.modulate.a = 0.0
	_modal.modulate.a = 0.0
	_modal.pivot_offset = _modal.size * 0.5
	_modal.scale = Vector2(0.94, 0.94)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_dim, "modulate:a", 1.0, 0.18)
	tw.tween_property(_modal, "modulate:a", 1.0, 0.22)
	tw.tween_property(_modal, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _hide_modal() -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_dim, "modulate:a", 0.0, 0.15)
	tw.tween_property(_modal, "modulate:a", 0.0, 0.15)
	tw.chain().tween_callback(func():
		_dim.visible = false
		_modal.visible = false
	)
