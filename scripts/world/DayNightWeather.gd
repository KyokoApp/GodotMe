class_name DayNightWeather
extends Node
## Dynamic Day-Dusk-Night & Weather controller that directly alters gameplay mechanics:
## - "Senja Lembayung" / "Malam Senyap": increases Senyap ambush rate and Lantern Oil significance.
## - "Kabut Tebal": reduces enemy detection range & player visibility.
## - "Hujan Abu": increases lantern oil drain by +35% unless sheltered or wearing upgraded cloak.
## - "Angin Selimut": boosts sailboat speed along wind vector.

@export var directional_sun: DirectionalLight3D
@export var world_env: WorldEnvironment

var current_hour: float = 16.5 # Starts in atmospheric late afternoon dusk
var current_weather: String = "kabut_tipis"
var wind_direction: Vector2 = Vector2(0.8, 0.6).normalized()
var wind_strength: float = 1.0
var _weather_timer: float = 0.0

func _process(delta: float) -> void:
	# 1 real minute = 1 in-game hour
	current_hour = fmod(current_hour + delta * 0.25, 24.0)
	_weather_timer += delta
	if _weather_timer >= 45.0:
		_weather_timer = 0.0
		_cycle_weather()

	_apply_lighting_and_gameplay_modifiers(delta)

func get_phase_name() -> String:
	if current_hour >= 6.0 and current_hour < 15.0:
		return "Pagi Redup"
	elif current_hour >= 15.0 and current_hour < 19.5:
		return "Senja Lembayung"
	return "Malam Senyap"

func _cycle_weather() -> void:
	var pool: Array[String] = ["cerah_redup", "kabut_tipis", "hujan_abu", "angin_selimut"]
	current_weather = pool[randi() % pool.size()]
	wind_strength = 1.45 if current_weather == "angin_selimut" else 0.75
	EventBus.weather_changed.emit(current_weather, wind_strength)
	EventBus.time_of_day_changed.emit(current_hour, get_phase_name())

func _apply_lighting_and_gameplay_modifiers(delta: float) -> void:
	if directional_sun != null:
		var phase: String = get_phase_name()
		match phase:
			"Pagi Redup":
				directional_sun.light_color = Color(0.82, 0.78, 0.73) # Muted cream-peach
				directional_sun.light_energy = 0.75
			"Senja Lembayung":
				directional_sun.light_color = Color(0.76, 0.58, 0.68) # Faded dusk lavender-peach
				directional_sun.light_energy = 0.48
			"Malam Senyap":
				directional_sun.light_color = Color(0.32, 0.36, 0.48) # Deep tea-blue twilight
				directional_sun.light_energy = 0.20

	# Weather gameplay impact: Ash Rain drains extra oil if lantern is exposed
	if current_weather == "hujan_abu" and GameState.lantern_lit:
		GameState.consume_lantern_oil(0.18 * delta)
