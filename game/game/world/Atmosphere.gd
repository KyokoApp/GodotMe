extends Node3D
## Atmosphere: the small moving things that stop a diorama from looking like a
## photograph of a diorama.
##
## Four systems, one per mood, each a CPUParticles3D so it runs on the
## Compatibility renderer and on weak Android GPUs (GPU particles are a luxury we
## do not need for forty specks of pollen):
##
##   dust       pollen in the sunbeam           - morning and noon
##   petals     leaves on the wind              - afternoon
##   fireflies  warm bugs in the grass          - evening and night
##   fog        ground mist, big slow quads     - dawn and night
##
## Every system is always present. Switching a phase changes its tint alpha and
## `emitting`; it never adds or removes nodes, so nothing allocates while the
## player walks around.
##
## Textures come from `tools/gen_atmosphere.py` (real PNGs, dithered by hand -
## nothing is drawn at runtime).

const ART := preload("res://game/world/WorldArt.gd")
const TEX_DIR := "res://game/world/textures/atmosphere/"

## How hard each system runs per phase (0 = off, 1 = full). These are art
## decisions: dawn is the foggiest hour in a real valley, noon has the most dust
## in the light, dusk is when leaves move, night belongs to the fireflies.
const MIX := {
	"pagi": {"dust": 0.55, "petals": 0.0, "fireflies": 0.0, "fog": 1.0},
	"siang": {"dust": 0.90, "petals": 0.25, "fireflies": 0.0, "fog": 0.15},
	"sore": {"dust": 0.50, "petals": 1.0, "fireflies": 0.15, "fog": 0.50},
	"malam": {"dust": 0.0, "petals": 0.10, "fireflies": 1.0, "fog": 0.70},
}

var _systems := {}
var _base_alpha := {}
var _base_amount := {}
var _amount_scale := 1.0
var _phase := "sore"


func setup() -> void:
	_build("dust", "mote_dust.png", 46, 11.0, 1.25,
		Vector2(0.10, 0.10), Color(1.0, 0.96, 0.88), false,
		Vector3(0.02, -0.02, 0.0), Vector2(0.10, 0.30))
	_build("petals", "petal.png", 26, 7.0, 4.4,
		Vector2(0.34, 0.20), Color(1.0, 0.92, 0.82), false,
		Vector3(0.30, -0.45, 0.15), Vector2(0.18, 0.45))
	_build("fireflies", "firefly.png", 34, 6.5, 0.95,
		Vector2(0.22, 0.22), Color(1.0, 0.92, 0.62), true,
		Vector3(0.0, 0.0, 0.0), Vector2(0.05, 0.22))
	_build("fog", "fog_puff.png", 10, 16.0, 0.45,
		Vector2(7.0, 4.0), Color(0.93, 0.90, 0.86, 0.55), false,
		Vector3(0.05, 0.0, 0.0), Vector2(0.06, 0.18))
	set_phase(_phase)
	print("[WORLD] atmosfer siap: %d sistem, tekstur %d" % [
		_systems.size(), _textures_ok()])


func _build(id: String, texture_file: String, amount: int, lifetime: float,
		height: float, quad: Vector2, tint: Color, additive: bool,
		gravity: Vector3, velocity: Vector2) -> void:
	var tex := ART.tex(TEX_DIR + texture_file)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.albedo_color = Color.WHITE
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if additive:
		# a firefly is light, not paint: it adds to the scene behind it
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED

	var mesh := QuadMesh.new()
	mesh.size = quad
	mesh.material = mat

	var p := CPUParticles3D.new()
	p.name = id
	p.mesh = mesh
	p.amount = amount
	p.lifetime = lifetime
	# Fill the air before the first frame: a capture taken one second after boot
	# must show a lived-in valley, not forty particles still queuing up.
	p.preprocess = lifetime
	p.randomness = 0.75
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(13.0, 0.25, 10.0)
	p.position = Vector3(0.0, height, 0.0)
	p.direction = Vector3(0.0, 1.0, 0.0)
	p.spread = 70.0
	p.gravity = gravity
	p.initial_velocity_min = velocity.x
	p.initial_velocity_max = velocity.y
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.35
	p.color = tint
	_base_alpha[id] = tint.a
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.angular_velocity_min = -18.0
	p.angular_velocity_max = 18.0
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-24.0, -4.0, -18.0), Vector3(48.0, 16.0, 36.0))
	add_child(p)
	_systems[id] = p
	_base_amount[id] = amount


## Switch the mood. Alpha carries the amount: keeping `amount` fixed avoids the
## cost spike (and the visible "burst") of re-allocating a particle system when
## the clock rolls over.
func set_phase(id: String) -> void:
	if not MIX.has(id):
		return
	_phase = id
	var mix: Dictionary = MIX[id]
	for key in mix.keys():
		if not _systems.has(key):
			continue
		var p: CPUParticles3D = _systems[key]
		var amount := float(mix[key])
		var tint := p.color
		# the sprite's own alpha (fog is translucent by design) scales the mix
		var base := float(_base_alpha.get(key, 1.0))
		p.color = Color(tint.r, tint.g, tint.b, clampf(amount * base, 0.0, 1.0))
		p.emitting = amount > 0.03


## Quality preset hook: weak phones pay less for the same picture. `amount` is
## the only knob that really costs, so it is the only one scaled.
func set_amount_scale(scale: float) -> void:
	_amount_scale = clampf(scale, 0.1, 2.0)
	for key in _systems.keys():
		var p: CPUParticles3D = _systems[key]
		var base := int(_base_amount.get(key, p.amount))
		p.amount = maxi(1, int(round(float(base) * _amount_scale)))


func amount_scale() -> float:
	return _amount_scale


func phase() -> String:
	return _phase


func intensity(kind: String) -> float:
	if not _systems.has(kind):
		return 0.0
	return float((_systems[kind] as CPUParticles3D).color.a)


func systems() -> Dictionary:
	return _systems


func _textures_ok() -> int:
	var ok := 0
	for key in _systems.keys():
		var p: CPUParticles3D = _systems[key]
		var mesh := p.mesh as QuadMesh
		if mesh != null and mesh.material is StandardMaterial3D:
			if (mesh.material as StandardMaterial3D).albedo_texture != null:
				ok += 1
	return ok
