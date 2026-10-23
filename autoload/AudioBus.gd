extends Node
## Centralized Audio Manager for BGM crossfades, spatial/UI SFX pooling, and bus volume control.

const SFX_POOL_SIZE: int = 8

var _bgm_player: AudioStreamPlayer
var _ambient_player: AudioStreamPlayer
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_cursor: int = 0

var _sound_cache: Dictionary = {
	"swing": "res://assets/audio/sfx/sfx_swing.wav",
	"hit": "res://assets/audio/sfx/sfx_hit.wav",
	"lantern_ignite": "res://assets/audio/sfx/sfx_lantern_ignite.wav",
	"step": "res://assets/audio/sfx/sfx_step.wav",
	"ui_tap": "res://assets/audio/sfx/sfx_ui_tap.wav",
	"quest_chime": "res://assets/audio/sfx/sfx_quest_chime.wav"
}

func _ready() -> void:
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = &"BGM"
	add_child(_bgm_player)

	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.bus = &"Ambient"
	add_child(_ambient_player)

	for i in range(SFX_POOL_SIZE):
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_sfx_pool.append(p)

func play_sfx(sfx_key: String, pitch_min: float = 0.92, pitch_max: float = 1.08) -> void:
	var path: String = String(_sound_cache.get(sfx_key, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var stream: AudioStream = load(path) as AudioStream
	if stream == null:
		return
	var player: AudioStreamPlayer = _sfx_pool[_sfx_cursor]
	_sfx_cursor = (_sfx_cursor + 1) % SFX_POOL_SIZE
	player.stream = stream
	player.pitch_scale = randf_range(pitch_min, pitch_max)
	player.play()

func play_bgm(bgm_path: String) -> void:
	if not ResourceLoader.exists(bgm_path):
		return
	var stream: AudioStream = load(bgm_path) as AudioStream
	if _bgm_player.stream == stream and _bgm_player.playing:
		return
	_bgm_player.stream = stream
	_bgm_player.play()

func set_bus_volume_linear(bus_name: StringName, linear_val: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear_val, 0.0001, 1.0)))
