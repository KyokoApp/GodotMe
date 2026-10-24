class_name UiTheme
extends RefCounted
## Builds the Re - Traveller UI theme from bitmap art + OFL pixel fonts.
##
## Typography rule (see docs/DESIGN_NOTES.md): a single pixel family, Pixelify
## Sans (OFL). Regular for body, SemiBold for the wordmark and actions. Nothing
## renders below 16px so it stays readable on a phone.

const TEX := "res://ui/textures/"
const FONT_LOGO := "res://ui/fonts/PixelifySans-SemiBold.woff2"
const FONT_BODY := "res://ui/fonts/PixelifySans-Regular.woff2"
const FONT_BOLD := "res://ui/fonts/PixelifySans-SemiBold.woff2"

const COL_INK := Color(0.165, 0.11, 0.086)
const COL_INK_SOFT := Color(0.30, 0.22, 0.16)
const COL_INK_FAINT := Color(0.42, 0.34, 0.25)
const COL_CREAM := Color(0.980, 0.941, 0.839)
const COL_PARCH := Color(0.929, 0.855, 0.694)
const COL_BRASS := Color(0.910, 0.745, 0.408)
const COL_BRASS_DIM := Color(0.588, 0.427, 0.235)
const COL_RUST := Color(0.760, 0.320, 0.200)
const COL_GREEN := Color(0.463, 0.604, 0.329)
const COL_TEAL := Color(0.149, 0.353, 0.329)
const COL_SHADOW := Color(0.06, 0.04, 0.03, 0.55)

static var _cache: Theme = null


static func get_theme() -> Theme:
	if _cache == null:
		_cache = build()
	return _cache


static func build() -> Theme:
	var t := Theme.new()
	var f_logo := _font(FONT_LOGO)
	var f_body := _font(FONT_BODY)
	var f_bold := _font(FONT_BOLD)
	t.default_font = f_body
	t.default_font_size = 20

	# ---------------------------------------------------------------- labels --
	# base Label (no variation: a type cannot be a variation of itself)
	t.set_font("font", "Label", f_body)
	t.set_font_size("font_size", "Label", 20)
	t.set_color("font_color", "Label", COL_PARCH)
	t.set_color("font_shadow_color", "Label", COL_SHADOW)
	t.set_constant("shadow_offset_y", "Label", 1)
	t.set_constant("line_spacing", "Label", 4)

	_label(t, "TitleLabel", f_logo, 76, COL_CREAM)
	_label(t, "SubtitleLabel", f_body, 22, COL_BRASS)
	_label(t, "PanelHeading", f_bold, 17, COL_BRASS_DIM)
	_label(t, "StateTitle", f_bold, 34, COL_INK)
	_label(t, "DetailLabel", f_body, 19, COL_INK_SOFT)
	_label(t, "SmallLabel", f_body, 16, COL_PARCH)
	_label(t, "TinyLabel", f_body, 16, COL_PARCH)
	_label(t, "InkLabel", f_bold, 18, COL_BRASS)
	_label(t, "ErrorLabel", f_bold, 19, COL_RUST)

	# --------------------------------------------------------------- buttons --
	_button_variation(t, "PrimaryButton", f_bold, 30, COL_INK,
		_tex("button_gold_normal.png", 12, 22, 8), _tex("button_gold_hover.png", 12, 22, 8),
		_tex("button_gold_pressed.png", 12, 22, 8), _tex("button_gold_pressed.png", 12, 22, 8))
	_button_variation(t, "SecondaryButton", f_bold, 20, COL_CREAM,
		_tex("button_wood_normal.png", 14, 18, 6), _tex("button_wood_hover.png", 14, 18, 6),
		_tex("button_wood_pressed.png", 14, 18, 6), _tex("button_wood_pressed.png", 14, 18, 6))

	# ---------------------------------------------------------------- panels --
	# Variations MUST be registered against their base type or the lookups
	# silently fall back to the plain control style.
	t.set_type_variation("ParchmentPanel", "PanelContainer")
	t.set_stylebox("panel", "ParchmentPanel", _tex("panel_parchment.png", 20, 30, 26))
	t.set_type_variation("InkPanel", "PanelContainer")
	t.set_stylebox("panel", "InkPanel", _tex("panel_ink.png", 14, 20, 12))
	t.set_type_variation("ModalPanel", "PanelContainer")
	t.set_stylebox("panel", "ModalPanel", _tex("panel_parchment.png", 20, 36, 30))
	# any bare PanelContainer is a dark carte-ink card
	t.set_stylebox("panel", "PanelContainer", _tex("panel_ink.png", 14, 20, 12))
	t.set_type_variation("CrestFrame", "PanelContainer")
	t.set_stylebox("panel", "CrestFrame", _tex("icon_frame.png", 16, 12, 12))

	# ---------------------------------------------------------------- progress --
	t.set_stylebox("background", "ProgressBar", _tex("bar_track.png", 10, 8, 4))
	t.set_stylebox("fill", "ProgressBar", _tex("bar_fill.png", 10, 6, 4))
	t.set_font_size("font_size", "ProgressBar", 0)

	# ------------------------------------------------------------- scrollbar ---
	var grab := StyleBoxFlat.new()
	grab.bg_color = COL_BRASS_DIM
	grab.set_corner_radius_all(3)
	var grab_hi := grab.duplicate() as StyleBoxFlat
	grab_hi.bg_color = COL_BRASS
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.10, 0.14, 0.13, 0.45)
	bar_bg.set_corner_radius_all(3)
	for sb in [grab, grab_hi, bar_bg] as Array[StyleBoxFlat]:
		sb.content_margin_left = 0
		sb.content_margin_right = 0
		sb.content_margin_top = 0
		sb.content_margin_bottom = 0
	t.set_stylebox("scroll", "VScrollBar", bar_bg)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab_hi)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab_hi)

	# -------------------------------------------------------------- rich text --
	t.set_font("normal_font", "RichTextLabel", f_body)
	t.set_font("bold_font", "RichTextLabel", f_bold)
	t.set_font_size("normal_font_size", "RichTextLabel", 18)
	t.set_font_size("bold_font_size", "RichTextLabel", 18)
	t.set_color("default_color", "RichTextLabel", COL_INK_SOFT)
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	t.set_constant("line_separation", "RichTextLabel", 6)

	# -------------------------------------------------------------- tooltip ----
	t.set_stylebox("panel", "TooltipPanel", _tex("panel_ink.png", 14, 16, 10))
	t.set_font("font", "TooltipLabel", f_body)
	t.set_font_size("font_size", "TooltipLabel", 16)
	t.set_color("font_color", "TooltipLabel", COL_PARCH)
	return t


# ------------------------------------------------------------------ helpers --
static func _font(path: String) -> FontFile:
	var f: FontFile = null
	if ResourceLoader.exists(path):
		f = load(path) as FontFile
	if f == null:
		f = FontFile.new()
		if f.load_dynamic_font(path) != OK:
			Log.warn("Font tidak bisa dimuat: %s" % path)
			return f
	# pixel fonts must never be smoothed
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.hinting = TextServer.HINTING_NONE
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	f.multichannel_signed_distance_field = false
	f.generate_mipmaps = false
	f.allow_system_fallback = false
	return f


static func _tex(file: String, margin: int, mx: int, my: int) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	var path := TEX + file
	if ResourceLoader.exists(path):
		sb.texture = load(path)
	sb.set_texture_margin_all(margin)
	sb.content_margin_left = mx
	sb.content_margin_right = mx
	sb.content_margin_top = my
	sb.content_margin_bottom = my
	return sb


static func _label(t: Theme, variation: String, font: Font, size: int, color: Color) -> void:
	t.set_type_variation(variation, "Label")
	t.set_font("font", variation, font)
	t.set_font_size("font_size", variation, size)
	t.set_color("font_color", variation, color)
	t.set_color("font_shadow_color", variation, COL_SHADOW)
	t.set_constant("shadow_offset_x", variation, 1)
	t.set_constant("shadow_offset_y", variation, 2)
	t.set_constant("shadow_outline_size", variation, 0)
	t.set_constant("line_spacing", variation, 6)


static func _button_variation(t: Theme, variation: String, font: Font, size: int, color: Color,
		normal: StyleBox, hover: StyleBox, pressed: StyleBox, disabled: StyleBox) -> void:
	t.set_type_variation(variation, "Button")
	t.set_font("font", variation, font)
	t.set_font_size("font_size", variation, size)
	t.set_color("font_color", variation, color)
	t.set_color("font_hover_color", variation, color)
	t.set_color("font_pressed_color", variation, color)
	t.set_color("font_focus_color", variation, color)
	t.set_color("font_disabled_color", variation, Color(color.r, color.g, color.b, 0.45))
	t.set_color("font_outline_color", variation, COL_INK)
	t.set_constant("outline_size", variation, 2 if color != COL_INK else 0)
	t.set_constant("h_separation", variation, 10)
	t.set_stylebox("normal", variation, normal)
	t.set_stylebox("hover", variation, hover)
	t.set_stylebox("pressed", variation, pressed)
	t.set_stylebox("disabled", variation, disabled)
	t.set_stylebox("focus", variation, StyleBoxEmpty.new())
