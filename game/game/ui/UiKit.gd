extends RefCounted
## One place for the game's UI look: fonts, parchment, nine-patches and the
## 24x24 icon set.
##
## Why a kit at all: `Main.gd` and `DialogueBox.gd` had each grown their own copy
## of `_font`, `_tex` and `_nine`. Two copies drift - a 20 px margin here, a 22 px
## margin there - and the parchment starts looking like two different materials.
##
## Textures are read as bytes, not `load()`ed: the game ships inside plain
## PCKPacker archives with no `.import` files, so `load()` on a PNG path returns
## nothing (see WorldArt.gd for the same trick in the world pack).

const PARCHMENT := "res://game/assets/parchment.png"
const CREST := "res://game/assets/crest.png"
const FONT_BODY := "res://game/assets/PixelifySans.woff2"
const FONT_TITLE := "res://game/assets/PixelifySans-SemiBold.woff2"
const ICON_DIR := "res://game/assets/ui/icons/"
const ATLAS_PNG := "res://game/assets/ui/atlas_ui.png"
const ATLAS_JSON := "res://game/assets/ui/atlas_ui.json"

const INK := Color(0.17, 0.12, 0.09)
const INK_SOFT := Color(0.36, 0.28, 0.20)
const BRASS := Color(0.78, 0.62, 0.33)
const CREAM := Color(0.98, 0.94, 0.86)
const DANGER := Color(0.55, 0.16, 0.12)

## The icon set, in the order `tools/gen_game_ui.py` writes it. Kept here so a
## missing PNG is a readable error instead of a blank button.
const ICONS := [
	"heart_full", "heart_empty", "sun", "moon", "gear", "save", "arrow_left",
	"talk", "door", "inspect", "take", "map", "close", "book",
	# step 3C: the six weapons and six elements the weakness board is built from,
	# plus the shield. They are listed here for the same reason as the others -
	# this list is what the "?" row can draw and what the atlas must contain.
	"w_pedang", "w_tombak", "w_kapak", "w_busur", "w_tongkat", "w_belati",
	"e_api", "e_es", "e_petir", "e_angin", "e_cahaya", "e_kegelapan",
	"perisai",
]

## Touch floors, in DESIGN pixels of the 1280x720 canvas.
##
## The canvas is stretched to the phone by its height, so on a 2340x1080 screen
## one design pixel is 1.5 device pixels, and at ~400 dpi that is 0.6 dp. The
## brief's 48 dp therefore lands at ~80 design pixels, and its 72 dp action
## button at ~120. Rounded up, and used everywhere a finger has to land.
const TOUCH_MIN := 80.0
const TOUCH_BIG := 132.0

static var _tex_cache := {}
static var _font_cache := {}
static var _atlas_cache := {}


static func tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	if not FileAccess.file_exists(path):
		push_warning("[UI] tekstur tidak ada: %s" % path)
		return null
	var data := FileAccess.get_file_as_bytes(path)
	var img := Image.new()
	if img.load_png_from_buffer(data) != OK:
		push_warning("[UI] PNG rusak: %s" % path)
		return null
	var t := ImageTexture.create_from_image(img)
	_tex_cache[path] = t
	return t


## Icons come off the packed atlas when it exists (one texture, one bind for the
## whole HUD) and fall back to the authored single PNGs in an editor run.
static func icon(name: String) -> Texture2D:
	var regions := _atlas()
	if regions.has(name):
		var r: Rect2 = regions[name]
		var a := AtlasTexture.new()
		a.atlas = tex(ATLAS_PNG)
		a.region = r
		a.filter_clip = true
		return a
	return tex(ICON_DIR + name + ".png")


static func _atlas() -> Dictionary:
	if not _atlas_cache.is_empty():
		return _atlas_cache
	if not FileAccess.file_exists(ATLAS_JSON) or not FileAccess.file_exists(ATLAS_PNG):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ATLAS_JSON))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var entries: Dictionary = (parsed as Dictionary).get("entries", {})
	var out := {}
	for key in entries.keys():
		var e: Dictionary = entries[key]
		out[String(key)] = Rect2(float(e.get("x", 0)), float(e.get("y", 0)),
			float(e.get("w", 24)), float(e.get("h", 24)))
	_atlas_cache = out
	return out


static func icon_rect(name: String, size: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture = icon(name)
	r.custom_minimum_size = Vector2(size, size)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return r


## Pixel font with optional tracking, loaded from the ui pack.
static func font(path: String = FONT_BODY, tracking: int = 0) -> Font:
	var key := "%s|%d" % [path, tracking]
	if _font_cache.has(key):
		return _font_cache[key]
	var f := FontFile.new()
	if f.load_dynamic_font(path) != OK:
		return ThemeDB.fallback_font
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.hinting = TextServer.HINTING_NONE
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	var out: Font = f
	if tracking != 0:
		var v := FontVariation.new()
		v.base_font = f
		v.spacing_glyph = tracking
		v.spacing_space = tracking * 2
		out = v
	_font_cache[key] = out
	return out


## Parchment nine-patch. `margin` is the border of the source PNG that must not
## stretch; `mx`/`my` are the text margins inside it.
static func parchment(margin: int = 20, mx: int = 22, my: int = 12) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex(PARCHMENT)
	sb.set_texture_margin_all(margin)
	sb.content_margin_left = mx
	sb.content_margin_right = mx
	sb.content_margin_top = my
	sb.content_margin_bottom = my
	return sb


## The parchment 9-slice at chip size. The brass border is scaled down to 12 px,
## so the margin the TEXT gets has to be wider than 12 - at (12, 8, 4) the label
## is drawn on top of the frame, and a screenshot showed "Orc Prajurit" running
## into the corner of its plate. 16/6 clears the border on every side.
##
## `BattleShot._check_frame` reads the styleboxes of the live fight back and
## fails the build if any panel breaks this rule, so a new caller cannot repeat
## the mistake quietly.
static func parchment_small() -> StyleBoxTexture:
	return parchment(12, 16, 6)


## Scale a whole HUD layer by the player's "ukuran UI" setting, around the
## centre of the screen.
##
## Scaling a single knob is the only version of "UI size" that cannot drift: a
## second set of font sizes would rot the first time somebody forgets one. The
## layer transform leaves drawing, hit-testing and anchors untouched, and a
## canvas-layer transform is free (it is one matrix on the CPU).
static func apply_layer_scale(layer: CanvasLayer, factor: float,
		viewport_size: Vector2) -> void:
	if layer == null:
		return
	var f := clampf(factor, 0.75, 1.3)
	if is_equal_approx(f, 1.0):
		layer.transform = Transform2D.IDENTITY
		return
	var pivot := viewport_size * 0.5
	layer.transform = Transform2D(0.0, Vector2(f, f), 0.0, pivot * (1.0 - f))


static func label(text: String, size: int = 18, color: Color = INK,
		title: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(FONT_TITLE if title else FONT_BODY,
		3 if title else 1))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## The one button style in the game: parchment, ink, brass on press.
static func button(text: String, min_size: Vector2 = Vector2(352, 50),
		size: int = 19) -> Button:
	var b := Button.new()
	b.text = text
	var th := Theme.new()
	th.default_font = font(FONT_BODY)
	b.theme = th
	b.add_theme_stylebox_override("normal", parchment())
	b.add_theme_stylebox_override("hover", parchment())
	b.add_theme_stylebox_override("pressed", parchment())
	b.add_theme_stylebox_override("focus", parchment())
	b.add_theme_font_override("font", font(FONT_TITLE, 2))
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", INK)
	b.custom_minimum_size = min_size
	return b


## A button whose label is enough on its own (already themed), used for the
## small top-corner controls.
static func chip(text: String, min_size: Vector2 = Vector2(130, 46)) -> Button:
	return button(text, min_size, 18)
