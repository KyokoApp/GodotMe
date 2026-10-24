class_name Http
extends RefCounted
## Minimal, resumable HTTPS client built on HTTPClient.
##
## Why not HTTPRequest? We need HTTP Range resume, stall detection and byte
## level progress into a file - all of which HTTPRequest hides from us. No
## native plugin is involved, so this keeps working from inside a PCK update.

const REDIRECT_CODES := [301, 302, 303, 307, 308]
const USER_AGENT := "ReTravellerLauncher/1.0 (Godot 4.7.2)"
const CONNECT_TIMEOUT_S := 12.0
const STALL_TIMEOUT_S := 20.0
const MAX_REDIRECTS := 5


class Url extends RefCounted:
	var scheme: String = "https"
	var host: String = ""
	var port: int = -1
	var path: String = "/"
	var error: String = ""


static func parse_url(url: String) -> Url:
	var u := Url.new()
	var rest := url
	var scheme_end := url.find("://")
	if scheme_end < 0:
		u.error = "URL tanpa skema: %s" % url
		return u
	u.scheme = url.substr(0, scheme_end).to_lower()
	rest = url.substr(scheme_end + 3)
	if u.scheme == "file":
		u.host = ""
		u.path = rest
		return u
	if not (u.scheme == "http" or u.scheme == "https"):
		u.error = "Skema tidak didukung: %s" % u.scheme
		return u
	var slash := rest.find("/")
	var authority := rest
	if slash >= 0:
		authority = rest.substr(0, slash)
		u.path = rest.substr(slash)
	else:
		u.path = "/"
	var colon := authority.rfind(":")
	if colon > 0:
		u.host = authority.substr(0, colon)
		u.port = int(authority.substr(colon + 1))
	else:
		u.host = authority
		u.port = 443 if u.scheme == "https" else 80
	if u.host == "":
		u.error = "Host kosong."
	return u


## Small JSON/text fetch.
static func fetch_text(url: String, timeout_s: float = 20.0, max_bytes: int = 4 * 1024 * 1024) -> Dictionary:
	var tmp := "user://retraveller/partial/_fetch_%d.tmp" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(tmp.get_base_dir())
	var r := await download_to_file(url, tmp, -1, false, null, null, timeout_s)
	if not r["ok"]:
		DirAccess.remove_absolute(tmp)
		return r
	if int(r.get("bytes", 0)) > max_bytes:
		DirAccess.remove_absolute(tmp)
		return _err("Respons terlalu besar.")
	var body := FileAccess.get_file_as_bytes(tmp)
	DirAccess.remove_absolute(tmp)
	r["body"] = body.get_string_from_utf8()
	return r


## Download (or copy) a URL into dest_path, resuming from the current file size
## when resume is true. expected_size < 0 means "whatever the server sends".
static func download_to_file(url: String, dest_path: String, expected_size: int = -1,
		resume: bool = true, progress_cb = null, cancel_cb = null,
		stall_timeout_s: float = STALL_TIMEOUT_S) -> Dictionary:
	var u := parse_url(url)
	if u.error != "":
		return _err(u.error)

	if u.scheme == "file" or url.begins_with("res://") or url.begins_with("user://"):
		return _copy_local(url, dest_path, expected_size, resume, progress_cb, cancel_cb)

	var redirects := 0
	var target := url
	while true:
		var res: Dictionary = await _http_download(target, dest_path, expected_size,
			resume, progress_cb, cancel_cb, stall_timeout_s)
		if res.get("redirect", "") != "":
			redirects += 1
			if redirects > MAX_REDIRECTS:
				return _err("Terlalu banyak pengalihan (redirect).")
			target = Util.resolve_url(target, String(res["redirect"]))
			continue
		return res


static func _copy_local(url: String, dest_path: String, expected_size: int, resume: bool,
		progress_cb, cancel_cb) -> Dictionary:
	var src := url
	if src.begins_with("file://"):
		src = src.substr(7)
	DirAccess.make_dir_recursive_absolute(dest_path.get_base_dir())
	var total := Util.file_size(src)
	if total <= 0:
		return _err("Berkas sumber tidak ditemukan: %s" % src)
	if expected_size > 0 and total != expected_size:
		return _err("Ukuran berkas sumber %d != %d di manifest." % [total, expected_size])
	var offset := 0
	if resume:
		offset = Util.file_size(dest_path)
	if offset > total:
		DirAccess.remove_absolute(dest_path)
		offset = 0
	var fin := FileAccess.open(src, FileAccess.READ)
	if fin == null:
		return _err("Tidak bisa membuka sumber.")
	var fout: FileAccess
	if offset > 0 and FileAccess.file_exists(dest_path):
		fout = FileAccess.open(dest_path, FileAccess.READ_WRITE)
		fout.seek_end()
	else:
		offset = 0
		fout = FileAccess.open(dest_path, FileAccess.WRITE)
	if fout == null:
		fin = null
		return _err("Tidak bisa menulis ke %s." % dest_path)
	fin.seek(offset)
	var done := offset
	while done < total:
		if cancel_cb is Callable and cancel_cb.is_valid() and cancel_cb.call():
			fout.flush(); fout = null; fin = null
			return _err("Dibatalkan.", -1)
		var chunk := fin.get_buffer(262144)
		if chunk.size() <= 0:
			break
		fout.store_buffer(chunk)
		done += chunk.size()
		if progress_cb is Callable and progress_cb.is_valid():
			progress_cb.call(done, total)
	fout.flush()
	fout = null
	fin = null
	return {"ok": true, "error": "", "code": 0, "bytes": done, "resumed_from": offset}


static func _http_download(url: String, dest_path: String, expected_size: int, resume: bool,
		progress_cb, cancel_cb, stall_timeout_s: float) -> Dictionary:
	var u := parse_url(url)
	if u.error != "":
		return _err(u.error)
	DirAccess.make_dir_recursive_absolute(dest_path.get_base_dir())

	var client := HTTPClient.new()
	var tls: TLSOptions = null
	if u.scheme == "https":
		tls = TLSOptions.client()
	var cerr := client.connect_to_host(u.host, u.port, tls)
	if cerr != OK:
		return _err("Gagal menghubungi %s (kode %d)." % [u.host, cerr])

	# --- wait for connection -------------------------------------------------
	var started := Time.get_ticks_msec()
	while client.get_status() in [HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING]:
		client.poll()
		if Time.get_ticks_msec() - started > int(CONNECT_TIMEOUT_S * 1000.0):
			client.close()
			return _err("Waktu koneksi habis ke %s." % u.host)
		if cancel_cb is Callable and cancel_cb.is_valid() and cancel_cb.call():
			client.close()
			return _err("Dibatalkan.", -1)
		await _tick()
	var st := client.get_status()
	if st != HTTPClient.STATUS_CONNECTED:
		client.close()
		return _err("Tidak bisa terhubung ke %s (status %d)." % [u.host, st])

	# --- resume bookkeeping --------------------------------------------------
	var offset := 0
	if resume:
		offset = Util.file_size(dest_path)
	var headers := PackedStringArray([
		"User-Agent: " + USER_AGENT,
		"Accept: */*",
		"Connection: close",
	])
	if offset > 0:
		headers.append("Range: bytes=%d-" % offset)

	if client.request(HTTPClient.METHOD_GET, u.path, headers) != OK:
		client.close()
		return _err("Permintaan HTTP gagal disusun.")

	# --- wait for response ---------------------------------------------------
	started = Time.get_ticks_msec()
	while not client.has_response():
		client.poll()
		var s := client.get_status()
		if s in [HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CANT_RESOLVE,
				HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR,
				HTTPClient.STATUS_DISCONNECTED]:
			client.close()
			return _err("Koneksi terputus saat menunggu respons (status %d)." % s)
		if Time.get_ticks_msec() - started > int(STALL_TIMEOUT_S * 1000.0):
			client.close()
			return _err("Server tidak merespons.")
		if cancel_cb is Callable and cancel_cb.is_valid() and cancel_cb.call():
			client.close()
			return _err("Dibatalkan.", -1)
		await _tick()

	var code := client.get_response_code()
	if REDIRECT_CODES.has(code):
		var loc := client.get_response_header_value("location")
		client.close()
		if loc.strip_edges() == "":
			return _err("Pengalihan tanpa Location.")
		return {"ok": false, "error": "", "code": code, "redirect": loc}

	if code == 416:
		# Range not satisfiable: our partial file already equals the full size.
		client.close()
		if expected_size > 0 and Util.file_size(dest_path) == expected_size:
			return {"ok": true, "error": "", "code": 416, "bytes": expected_size,
				"resumed_from": offset}
		DirAccess.remove_absolute(dest_path)
		return _err("Rentang unduhan ditolak server (416).")

	if code != 200 and code != 206:
		client.close()
		return _err("Server mengembalikan kode %d." % code, code)

	var total := -1
	if code == 206:
		var cr := client.get_response_header_value("content-range")  # e.g. bytes 100-999/1000
		var slash := cr.rfind("/")
		if slash >= 0:
			total = int(cr.substr(slash + 1))
		if offset <= 0:
			offset = 0
	else:
		# server ignored our Range header -> restart the file from zero
		offset = 0
		var cl := client.get_response_header_value("content-length")
		if cl != "":
			total = int(cl)
	if expected_size > 0:
		if total > 0 and total != expected_size:
			client.close()
			return _err("Ukuran di server %s != manifest %s." % [
				Util.human_size(total), Util.human_size(expected_size)])
		total = expected_size

	var mode := FileAccess.READ_WRITE if offset > 0 else FileAccess.WRITE
	var fout := FileAccess.open(dest_path, mode)
	if fout == null:
		client.close()
		return _err("Tidak bisa menulis ke %s (ruang penyimpanan?)." % dest_path)
	if offset > 0:
		fout.seek_end()

	# --- stream body --------------------------------------------------------
	var done := offset
	var last_progress_ms := Time.get_ticks_msec()
	var last_emit_ms := 0
	while client.get_status() == HTTPClient.STATUS_BODY:
		client.poll()
		var chunk := client.read_response_body_chunk()
		if chunk.size() > 0:
			fout.store_buffer(chunk)
			done += chunk.size()
			last_progress_ms = Time.get_ticks_msec()
			if progress_cb is Callable and progress_cb.is_valid() \
					and (last_progress_ms - last_emit_ms > 90 or (total > 0 and done >= total)):
				last_emit_ms = last_progress_ms
				progress_cb.call(done, total)
		else:
			if Time.get_ticks_msec() - last_progress_ms > int(stall_timeout_s * 1000.0):
				fout.flush()
				fout = null
				client.close()
				return _err("Unduhan berhenti merespons (stall).")
		if cancel_cb is Callable and cancel_cb.is_valid() and cancel_cb.call():
			fout.flush()
			fout = null
			client.close()
			return _err("Dibatalkan.", -1)
		await _tick()

	fout.flush()
	fout = null
	var final_status := client.get_status()
	client.close()
	if final_status == HTTPClient.STATUS_CONNECTION_ERROR:
		return _err("Koneksi terputus saat mengunduh.")
	if expected_size > 0 and done != expected_size:
		return _err("Ukuran berkas terunduh %s != %s." % [
			Util.human_size(done), Util.human_size(expected_size)])
	return {"ok": true, "error": "", "code": code, "bytes": done, "resumed_from": offset}


static func _err(message: String, code: int = 0) -> Dictionary:
	return {"ok": false, "error": message, "code": code, "bytes": 0, "resumed_from": 0}


static func _tick() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame
