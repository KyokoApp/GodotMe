class_name Hasher
extends RefCounted
## Streaming SHA-256 (never loads a whole .pck into RAM - phones matter).


static func sha256_file(path: String, chunk_size: int = 512 * 1024) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	while true:
		var chunk := f.get_buffer(chunk_size)
		if chunk.size() <= 0:
			break
		ctx.update(chunk)
	var digest := ctx.finish()
	f = null
	return digest.hex_encode().to_lower()


static func sha256_text(text: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(text.to_utf8_buffer())
	return ctx.finish().hex_encode().to_lower()
