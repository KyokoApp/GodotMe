extends Node
## Guard.gd - crash / boot watchdog (autoload "Guard").
##
## The launcher process *hosts* the game (load_resource_pack + change_scene), so
## a GDScript error storm or a hard crash can take the whole app down before any
## rollback code gets a chance to run. Two mechanisms cover both cases:
##
##   1. file sentinel - the game writes user://.../boot_ok.json on its first
##      healthy frame. If the next start finds pending_boot=true but the sentinel
##      names a different version, Store.rollback() runs before anything else.
##   2. in-process watchdog - if the scene changes but the sentinel never
##      arrives within Config.BOOT_SENTINEL_TIMEOUT_S, we roll back live and
##      return to the launcher UI with an explanation.

const LAUNCHER_SCENE := "res://scenes/Launcher.tscn"

var pending_notice: String = ""
var _armed := false
var _version := ""
var _elapsed := 0.0


## Called immediately before the game scene is changed.
func arm(version: String) -> void:
	_armed = true
	_version = version
	_elapsed = 0.0
	Store.clear_boot_ok()
	Store.mark_boot_pending(true)
	Log.info("Penjaga boot aktif untuk versi %s." % version)


func disarm(healthy: bool = true) -> void:
	_armed = false
	if healthy:
		Store.mark_boot_pending(false)


func _process(delta: float) -> void:
	if not _armed:
		return
	_elapsed += delta
	if Store.boot_ok_version() == _version:
		_armed = false
		Store.mark_boot_pending(false)
		Log.ok("Game melaporkan boot sehat (%s)." % _version)
		return
	if _elapsed >= Cfg.BOOT_SENTINEL_TIMEOUT_S:
		_armed = false
		_recover("Game tidak merespons dalam %d detik." % int(Cfg.BOOT_SENTINEL_TIMEOUT_S))


## Run at launcher start, before any update check.
func handle_startup_rollback() -> bool:
	var info := Store.pending_rollback()
	if not bool(info.get("needed", false)):
		Store.clear_boot_ok()
		return false
	var broken := String(info.get("version", ""))
	Log.error("Boot terakhir gagal untuk versi %s." % broken)
	var restored := Store.rollback()
	if restored != "":
		pending_notice = "Versi %s gagal dimuat. Kembali ke versi %s yang terakhir stabil." % [broken, restored]
	else:
		pending_notice = "Versi %s gagal dimuat dan tidak ada versi cadangan. Silakan unduh ulang." % broken
	return true


func _recover(reason: String) -> void:
	Log.error(reason)
	var broken := Store.active_version()
	var restored := Store.rollback()
	if broken != "":
		Store.block(broken)
	if restored != "":
		pending_notice = "%s Kembali ke versi %s." % [reason, restored]
	else:
		pending_notice = "%s Tidak ada versi cadangan yang bisa dipakai." % reason
	# we are still inside the launcher process: reload the launcher UI
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.change_scene_to_file(LAUNCHER_SCENE)
