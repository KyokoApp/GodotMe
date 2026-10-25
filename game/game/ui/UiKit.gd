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

const INK := Color(0.17, 0.12, 0.09)
const INK_SOFT := Color(0.36, 0.28, 0.20)
const BRASS := Color(0.78, 0.62, 0.33)
const CREAM := Color(0.98, 0.94, 0.86)
const DANGER := Color(0.55, 0.16, 0.12)

## The icon set, in the order `tools/gen_game_ui.py` writes it. Kept here so a
## missing PNG is a readable error instead of a blank button.
const ICONS := [
	"heart_full", "heart_empty", "sun", "moon", "gear", "save", "arrow_left",
]

static var _tex_cache := {}
static var _font_cache := {}


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


static func icon(name: String) -> Texture2D:
	return tex(ICON_DIR + name + ".png")


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
