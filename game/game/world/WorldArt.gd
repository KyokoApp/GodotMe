class_name WorldArt
extends RefCounted
## Runtime texture loading for world content.
##
## The packs are plain PCKPacker archives, so PNGs are stored raw and there are
## no .import files to `load()`: every texture comes off the pack as bytes and is
## turned into an ImageTexture here. Results are cached per path.


static var _cache: Dictionary = {}


static func tex(path: String) -> ImageTexture:
	if _cache.has(path):
		return _cache[path]
	if not FileAccess.file_exists(path):
		push_error("Tekstur dunia tidak ditemukan: %s" % path)
		return null
	var data := FileAccess.get_file_as_bytes(path)
	var img := Image.new()
	if img.load_png_from_buffer(data) != OK:
		push_error("PNG rusak: %s" % path)
		return null
	var t := ImageTexture.create_from_image(img)
	_cache[path] = t
	return t


## Billboard material for a prop: alpha-scissored so it can cast real shadows
## (transparent materials do not), per-pixel shading so the sun actually lights
## the sprite, and nearest filtering because it is pixel art.
static func sprite_material(texture: Texture2D, tint: Color = Color.WHITE,
		unshaded: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = texture
	m.albedo_color = tint
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.45
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if unshaded \
		else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.95
	return m


## Ground material. `tiles_x`/`tiles_z` control the texture repeat so one 256 px
## tile can cover several metres without stretching.
static func ground_material(texture: Texture2D, tiles_x: float,
		tiles_z: float, tint: Color = Color.WHITE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = texture
	m.albedo_color = tint
	m.uv1_scale = Vector3(tiles_x, tiles_z, 1.0)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.roughness = 1.0
	m.metallic = 0.0
	return m
