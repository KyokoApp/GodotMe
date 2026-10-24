extends RefCounted
## Loads character strips off a pack and slices them into SpriteFrames.
##
## Packs are plain PCKPacker archives, so the PNGs are stored raw and there are
## no `.import` files: every texture is decoded here from bytes. Slicing happens
## at runtime with AtlasTexture regions, which keeps one GPU texture per strip
## and lets a frame be swapped without re-uploading anything.
##
## The width check is deliberate: a strip whose width is not
## `frames * frame_width` would silently play a torn animation, so it is
## reported and skipped instead.

static var _tex_cache: Dictionary = {}
static var _frames_cache: Dictionary = {}


static func png(path: String) -> ImageTexture:
	if _tex_cache.has(path):
		return _tex_cache[path] as ImageTexture
	if not FileAccess.file_exists(path):
		push_error("[CHAR] PNG hilang: %s" % path)
		return null
	var img := Image.new()
	var err := img.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
	if err != OK:
		push_error("[CHAR] PNG rusak (%d): %s" % [err, path])
		return null
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[path] = tex
	return tex


static func build_frames(def: Resource) -> SpriteFrames:
	var key := String(def.get("id"))
	if _frames_cache.has(key):
		return _frames_cache[key] as SpriteFrames

	var frames_px: Vector2i = def.get("frame_size")
	var fw := frames_px.x
	var fh := frames_px.y
	var dir := String(def.get("sprite_dir"))
	var sf := SpriteFrames.new()
	if sf.has_animation("default"):
		sf.remove_animation("default")

	for raw in def.get("animations"):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = raw
		var anim := String(entry.get("name", ""))
		var path := dir.path_join(String(entry.get("file", "")))
		var count := int(entry.get("frames", 0))
		var tex := png(path)
		if tex == null or count <= 0:
			continue
		if tex.get_width() != count * fw or tex.get_height() != fh:
			push_error("[CHAR] %s/%s: lebar %d, seharusnya %d x %d" % [
				key, anim, tex.get_width(), count, fw])
			continue
		sf.add_animation(anim)
		sf.set_animation_speed(anim, float(entry.get("fps", 10.0)))
		sf.set_animation_loop(anim, bool(entry.get("loop", true)))
		for i in range(count):
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(float(i * fw), 0.0, float(fw), float(fh))
			# clip so nearest sampling can never peek at the neighbouring frame
			at.filter_clip = true
			sf.add_frame(anim, at)
	_frames_cache[key] = sf
	return sf


## Everything wrong with a definition, as human readable lines. Used by the
## headless validator that CI runs before it builds anything.
static func problems_for(def: Resource) -> Array:
	var out: Array = []
	if def == null:
		out.append("definisi karakter null")
		return out
	var id := String(def.get("id"))
	var dir := String(def.get("sprite_dir"))
	var frames_px: Vector2i = def.get("frame_size")
	if not DirAccess.dir_exists_absolute(dir):
		out.append("%s: folder sprite tidak ada (%s)" % [id, dir])
	if frames_px.x <= 0 or frames_px.y <= 0:
		out.append("%s: frame_size tidak masuk akal" % id)
	var pivot: Vector2 = def.get("pivot")
	if pivot.x < 0.0 or pivot.x > float(frames_px.x) or pivot.y < 0.0 \
			or pivot.y > float(frames_px.y):
		out.append("%s: pivot %s di luar frame %s" % [id, pivot, frames_px])
	var names: Array = def.get("animations")
	if names.is_empty():
		out.append("%s: tidak ada animasi" % id)
	for raw in names:
		if typeof(raw) != TYPE_DICTIONARY:
			out.append("%s: entri animasi bukan dictionary" % id)
			continue
		var entry: Dictionary = raw
		var anim := String(entry.get("name", ""))
		var path := dir.path_join(String(entry.get("file", "")))
		var count := int(entry.get("frames", 0))
		var fps := float(entry.get("fps", 0.0))
		if count <= 0:
			out.append("%s/%s: jumlah frame 0" % [id, anim])
		if fps <= 0.0:
			out.append("%s/%s: fps 0" % [id, anim])
		if not FileAccess.file_exists(path):
			out.append("%s/%s: berkas tidak ada (%s)" % [id, anim, path])
			continue
		var tex := png(path)
		if tex == null:
			out.append("%s/%s: PNG tidak terbaca" % [id, anim])
			continue
		if tex.get_width() != count * frames_px.x:
			out.append("%s/%s: lebar %d != %d frame x %d px" % [
				id, anim, tex.get_width(), count, frames_px.x])
		if tex.get_height() != frames_px.y:
			out.append("%s/%s: tinggi %d != %d" % [id, anim, tex.get_height(), frames_px.y])
	return out


## Frame silhouettes, for the validator: one Rect2i per non-empty frame.
static func empty_frames(def: Resource) -> Array:
	var out: Array = []
	var frames_px: Vector2i = def.get("frame_size")
	var dir := String(def.get("sprite_dir"))
	for raw in def.get("animations"):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = raw
		var anim := String(entry.get("name", ""))
		var path := dir.path_join(String(entry.get("file", "")))
		var tex := png(path)
		if tex == null:
			continue
		var img := tex.get_image()
		var count := int(entry.get("frames", 0))
		for i in range(count):
			var region := Rect2i(i * frames_px.x, 0, frames_px.x, frames_px.y)
			var sub := img.get_region(region)
			if sub.is_empty() or sub.get_used_rect().size == Vector2i.ZERO:
				out.append("%s/%s: frame %d kosong" % [String(def.get("id")), anim, i])
	return out


static func clear_cache() -> void:
	_tex_cache.clear()
	_frames_cache.clear()
