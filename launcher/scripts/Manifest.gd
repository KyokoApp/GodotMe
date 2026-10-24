class_name Manifest
extends RefCounted
## Manifest parsing, validation and signature checking.
##
## Contract (version.json):
## {
##   "schema": 1,
##   "game": "re-traveller",
##   "version": "0.3.0",
##   "min_launcher_version": 1,
##   "released_at": "2026-10-24T10:00:00Z",
##   "main_scene": "res://game/Main.tscn",
##   "changelog": ["Baris pertama", "Baris kedua"],
##   "packages": [
##     {"name": "core", "url": "packs/core-0.3.0.pck", "size": 12345,
##      "sha256": "<64 hex>", "load_order": 10},
##     ...
##   ],
##   "signature": "<base64 RSA-SHA256 of the manifest body without this field>"
## }

const REQUIRED_PACKAGE_KEYS := ["name", "url", "size", "sha256", "load_order"]


static func validate(data: Dictionary) -> Dictionary:
	## returns {"ok": bool, "error": String}
	for key in ["version", "min_launcher_version", "packages", "main_scene"]:
		if not data.has(key):
			return _fail("Manifest tidak memuat kolom '%s'." % key)
	if typeof(data["version"]) != TYPE_STRING or String(data["version"]).strip_edges() == "":
		return _fail("Kolom 'version' harus berupa teks.")
	if typeof(data["main_scene"]) != TYPE_STRING or not String(data["main_scene"]).begins_with("res://"):
		return _fail("Kolom 'main_scene' harus berupa path res:// di dalam paket.")
	if typeof(data["min_launcher_version"]) != TYPE_FLOAT and typeof(data["min_launcher_version"]) != TYPE_INT:
		return _fail("Kolom 'min_launcher_version' harus berupa angka.")
	if typeof(data["packages"]) != TYPE_ARRAY or (data["packages"] as Array).is_empty():
		return _fail("Manifest tidak memuat daftar paket.")

	var seen := {}
	var orders := {}
	for pkg_v in data["packages"]:
		if typeof(pkg_v) != TYPE_DICTIONARY:
			return _fail("Setiap paket harus berupa objek.")
		var pkg: Dictionary = pkg_v
		for key in REQUIRED_PACKAGE_KEYS:
			if not pkg.has(key):
				return _fail("Paket tanpa kolom '%s'." % key)
		var pname := String(pkg["name"])
		if pname.strip_edges() == "" or pname.contains("/") or pname.contains(".."):
			return _fail("Nama paket tidak aman: '%s'." % pname)
		if seen.has(pname):
			return _fail("Nama paket ganda: '%s'." % pname)
		seen[pname] = true
		if not Util.is_hex64(String(pkg["sha256"])):
			return _fail("sha256 paket '%s' tidak valid (harus 64 hex)." % pname)
		if typeof(pkg["size"]) != TYPE_FLOAT and typeof(pkg["size"]) != TYPE_INT:
			return _fail("size paket '%s' harus angka." % pname)
		if int(pkg["size"]) <= 0:
			return _fail("size paket '%s' harus lebih dari 0." % pname)
		var order := int(pkg["load_order"])
		if orders.has(order):
			return _fail("load_order ganda (%d)." % order)
		orders[order] = pname
	if data.has("changelog") and typeof(data["changelog"]) != TYPE_ARRAY and typeof(data["changelog"]) != TYPE_STRING:
		return _fail("changelog harus berupa daftar teks atau teks.")
	return {"ok": true, "error": ""}


static func _fail(msg: String) -> Dictionary:
	return {"ok": false, "error": msg}


static func version(data: Dictionary) -> String:
	return String(data.get("version", ""))


static func min_launcher_version(data: Dictionary) -> int:
	return int(data.get("min_launcher_version", 1))


static func main_scene(data: Dictionary) -> String:
	return String(data.get("main_scene", ""))


static func packages(data: Dictionary) -> Array:
	var arr: Array = data.get("packages", [])
	var copy := arr.duplicate()
	copy.sort_custom(func(a, b): return int(a.get("load_order", 0)) < int(b.get("load_order", 0)))
	return copy


static func total_size(data: Dictionary) -> int:
	var total := 0
	for pkg in packages(data):
		total += int(pkg.get("size", 0))
	return total


static func changelog_lines(data: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var raw: Variant = data.get("changelog", [])
	if typeof(raw) == TYPE_STRING:
		for line in String(raw).split("\n", false):
			out.append(line.strip_edges())
	elif typeof(raw) == TYPE_ARRAY:
		for line in raw:
			out.append(String(line))
	return out


## Detached signature over the *exact bytes* of version.json, so any tool
## (openssl, python, Godot) can produce it without JSON canonicalisation.
##   openssl dgst -sha256 -sign private.pem -out version.json.sig.bin version.json
static func digest_bytes(raw: PackedByteArray) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(raw)
	return ctx.finish()


static func verify_signature_bytes(raw: PackedByteArray, signature_b64: String,
		public_key_path: String) -> Dictionary:
	if signature_b64.strip_edges() == "":
		return _fail("Manifest tidak ditandatangani.")
	if not FileAccess.file_exists(public_key_path):
		return _fail("Kunci publik tidak ditemukan di %s." % public_key_path)
	var key := CryptoKey.new()
	if key.load_from_string(FileAccess.get_file_as_string(public_key_path)) != OK:
		return _fail("Kunci publik tidak bisa dibaca.")
	var digest := digest_bytes(raw)
	var sig := Marshalls.base64_to_raw(signature_b64)
	if sig.is_empty():
		return _fail("Tanda tangan kosong atau bukan base64.")
	var crypto := Crypto.new()
	if not crypto.verify(HashingContext.HASH_SHA256, digest, sig, key):
		return _fail("Tanda tangan manifest tidak cocok.")
	return {"ok": true, "error": ""}


## Kept for callers that only have the text form.
static func verify_signature(text: String, signature_b64: String, public_key_path: String) -> Dictionary:
	return verify_signature_bytes(text.to_utf8_buffer(), signature_b64, public_key_path)
