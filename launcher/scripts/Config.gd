extends Node
## Config.gd - the launcher's single configuration surface (autoload "Cfg").
##
## Everything an operator ever needs to edit lives here. The launcher itself is
## generic: it knows nothing about the game beyond the manifest contract.

const LAUNCHER_VERSION: int = 2
const GAME_ID: String = "re-traveller"

## Build stamp, shown in the journal so "which build is installed" is never a
## guess. The value lives in project.godot ([re_traveller] build_id) because that
## file ends up byte-for-byte inside the APK, which lets CI prove that a published
## artifact was really built from this commit.
func build_id() -> String:
	return String(ProjectSettings.get_setting("re_traveller/build_id", "dev"))

## Where the launcher reads version.json (HTTPS, must return JSON).
## Default points at the GitHub Releases of this repo: replace with your own
## hosting whenever you have it - see docs/BUILD_AND_RELEASE.md.
const MANIFEST_URL: String = "https://github.com/KyokoApp/GodotMe/releases/latest/download/version.json"

## Optional second mirror, tried only if MANIFEST_URL fails. Empty = disabled.
const MANIFEST_URL_FALLBACK: String = ""

## Manifest signing. Generate a key pair once (see BUILD_AND_RELEASE.md), commit
## only the public key. When REQUIRE_SIGNATURE is true the launcher refuses to
## install a manifest that is not signed with the matching private key.
const PUBLIC_KEY_PATH: String = "res://signing/public_key.pem"
const REQUIRE_SIGNATURE: bool = false

## Networking
const HTTP_CONNECT_TIMEOUT_S: float = 12.0
const HTTP_STALL_TIMEOUT_S: float = 20.0
const HTTP_MAX_REDIRECTS: int = 5
const DOWNLOAD_RETRIES: int = 3
const USER_AGENT: String = "ReTravellerLauncher/1.0 (Godot)"
const CHUNK_SIZE: int = 256 * 1024
const HASH_CHUNK_SIZE: int = 512 * 1024

## Rollback / boot watchdog
const BOOT_SENTINEL_TIMEOUT_S: float = 25.0
const KEEP_VERSIONS: int = 2           # active + 1 previous
const MIN_FREE_SPACE_MARGIN: int = 48 * 1024 * 1024

## Directory layout under user:// (save data deliberately lives elsewhere)
const DIR_ROOT: String = "user://retraveller"
const DIR_VERSIONS: String = "user://retraveller/versions"
const DIR_PARTIAL: String = "user://retraveller/partial"
const DIR_LOGS: String = "user://retraveller/logs"
const FILE_ACTIVE: String = "user://retraveller/active.json"
const FILE_MANIFEST_CACHE: String = "user://retraveller/manifest_cache.json"
const FILE_SETTINGS: String = "user://retraveller/launcher_settings.json"
## Written by the *game* once its first frame is up. The contract is documented
## in docs/GAME_CONTRACT.md; the launcher only ever reads it.
const FILE_BOOT_OK: String = "user://retraveller/boot_ok.json"

var _root_override: String = ""
var _manifest_override: String = ""
var _require_signature_override: int = -1
var _autoplay_override: int = -1


func _ready() -> void:
	_parse_cmdline()


static func a_arg_equals(arg: String, value: String) -> bool:
	return arg == value


func _parse_cmdline() -> void:
	for raw in OS.get_cmdline_user_args():
		var arg := String(raw)
		if arg.begins_with("--data-root="):
			_root_override = arg.substr("--data-root=".length())
		elif arg.begins_with("--manifest="):
			_manifest_override = arg.substr("--manifest=".length())
		elif arg.begins_with("--manifest-url="):
			_manifest_override = arg.substr("--manifest-url=".length())
		elif arg.begins_with("--require-signature="):
			_require_signature_override = int(arg.substr("--require-signature=".length()))
		elif a_arg_equals(arg, "--autoplay"):
			_autoplay_override = 1
		elif a_arg_equals(arg, "--no-autoplay"):
			_autoplay_override = 0


## Sandbox root used for every piece of launcher state. Tests point this at
## separate folders (user://test_a, ...) so scenarios never collide.
func data_root() -> String:
	return _root_override if _root_override != "" else DIR_ROOT


func versions_dir() -> String:
	return data_root().path_join("versions")


func packs_dir() -> String:
	return data_root().path_join("packs")


func partial_dir() -> String:
	return data_root().path_join("partial")


func logs_dir() -> String:
	return data_root().path_join("logs")


func active_file() -> String:
	return data_root().path_join("active.json")


func manifest_cache_file() -> String:
	return data_root().path_join("manifest_cache.json")


func settings_file() -> String:
	return data_root().path_join("launcher_settings.json")


func boot_ok_file() -> String:
	return data_root().path_join("boot_ok.json")


## Manifest URL resolution order:
##   data_root/manifest_url.txt  (operator / test override, wins at runtime)
##   --manifest= on the command line
##   Config.MANIFEST_URL          (the shipped default)
func manifest_url() -> String:
	var override_path: String = data_root().path_join("manifest_url.txt")
	if FileAccess.file_exists(override_path):
		var txt := FileAccess.get_file_as_string(override_path).strip_edges()
		if txt != "":
			return txt
	if _manifest_override != "":
		return _manifest_override
	return MANIFEST_URL


## Manifest signature enforcement (see Manifest.verify_signature).
func require_signature() -> bool:
	if _require_signature_override >= 0:
		return _require_signature_override == 1
	var settings := Util.read_json(settings_file())
	if settings.has("require_signature"):
		return bool(settings["require_signature"])
	return REQUIRE_SIGNATURE


## Auto-boot the installed game once an update check reports READY.
## Off by default; --autoplay or a settings entry turns it on.
func autoplay_enabled() -> bool:
	if _autoplay_override >= 0:
		return _autoplay_override == 1
	var settings := Util.read_json(settings_file())
	return bool(settings.get("autoplay", false))


func ensure_dirs() -> void:
	for d in [data_root(), versions_dir(), packs_dir(), partial_dir(), logs_dir()]:
		DirAccess.make_dir_recursive_absolute(d)
