extends Node3D
## Scene `CharacterTest`: the three characters side by side, every animation
## cycling and labelled, a metre ruler and a foot-pivot cross.
##
## Run it on a desktop to eyeball the art:
##   godot --path game res://game/tests/CharacterTest.tscn
## or let CI take the screenshot:
##   ... --capture=<dir> --capture-name=09_karakter

const CharacterAssets := preload("res://game/characters/CharacterAssets.gd")
const HARNESS := preload("res://game/tests/TestHarness.gd")
const RULER := preload("res://game/tests/RulerOverlay.gd")

const IDS := ["knight", "soldier", "orc"]
const SPOTS := [Vector3(-2.7, 0.0, 0.0), Vector3(0.0, 0.0, 0.0), Vector3(2.9, 0.0, 0.0)]
const ANIM_SECONDS := 2.4
const FONT_BODY := "res://game/assets/PixelifySans.woff2"
const FONT_TITLE := "res://game/assets/PixelifySans-SemiBold.woff2"

var camera: Camera3D
var actors: Array = []
var anim_lists: Array = []
var labels: Array = []
var _indexes: Array = [0, 0, 0]
var _timer := 0.0
var _font_body: Font
var _font_title: Font


func _ready() -> void:
	_font_body = _font(FONT_BODY)
	_font_title = _font(FONT_TITLE)
	_build_stage()
	_build_actors()
	_build_overlay()
	await _run()


func _run() -> void:
	await HARNESS.capture(self, "09_karakter", 2.4)
	await HARNESS.quit_after(self, 45.0)


# ------------------------------------------------------------------ stage ----
func _build_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.15, 0.17, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.60, 0.70)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.10
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-42.0, -28.0, 0.0)
	sun.light_color = Color(1.0, 0.96, 0.90)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)

	var plane := PlaneMesh.new()
	plane.size = Vector2(24.0, 12.0)
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	var grass := _texture("res://game/world/textures/grass_tile.png")
	if grass != null:
		mat.albedo_texture = grass
		mat.uv1_scale = Vector3(12.0, 6.0, 1.0)
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	else:
		mat.albedo_color = Color(0.22, 0.28, 0.18)
	mat.roughness = 1.0
	ground.material_override = mat
	add_child(ground)

	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 32.0
	camera.position = Vector3(0.0, 2.5, 8.8)
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.95, 0.0), Vector3.UP)
	camera.current = true


func _build_actors() -> void:
	var script: Script = load("res://game/characters/Actor.gd")
	for i in range(IDS.size()):
		var id := String(IDS[i])
		var path := "res://game/characters/data/%s.tres" % id
		if not ResourceLoader.exists(path):
			push_error("[TEST] definisi hilang: %s" % path)
			continue
		var def: Resource = load(path)
		var actor: Node3D = script.new()
		actor.call("setup", def)
		actor.position = SPOTS[i]
		add_child(actor)
		actors.append(actor)

		# every animation loops in this scene, including the one-shot attacks,
		# so the label always names what is on screen
		var frames: SpriteFrames = actor.get("sprite").sprite_frames
		for anim in frames.get_animation_names():
			frames.set_animation_loop(anim, true)
		var names: Array = def.call("anim_names")
		anim_lists.append(names)
		actor.get("sprite").play(String(names[0]))
	print("[TEST] CharacterTest: %d karakter, animasi: %s" % [actors.size(), str(anim_lists)])


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Labels"
	layer.layer = 5
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	var ruler := Control.new()
	ruler.set_anchors_preset(Control.PRESET_FULL_RECT)
	ruler.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ruler.set_script(RULER)
	ruler.set("camera", camera)
	ruler.set("actors", actors)
	root.add_child(ruler)

	var title := Label.new()
	title.text = "Uji karakter — tinggi relatif, pivot kaki, dan animasi"
	title.add_theme_font_override("font", _font_title)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.97, 0.92, 0.82))
	title.position = Vector2(26.0, 18.0)
	root.add_child(title)

	var legend := Label.new()
	legend.text = _legend_text()
	legend.add_theme_font_override("font", _font_body)
	legend.add_theme_font_size_override("font_size", 14)
	legend.add_theme_color_override("font_color", Color(0.88, 0.84, 0.74))
	legend.position = Vector2(26.0, 54.0)
	root.add_child(legend)

	for i in range(IDS.size()):
		var label := Label.new()
		label.add_theme_font_override("font", _font_body)
		label.add_theme_font_size_override("font_size", 16)
		label.add_theme_color_override("font_color", Color(0.98, 0.94, 0.86))
		label.add_theme_color_override("font_shadow_color", Color(0.05, 0.04, 0.03, 0.9))
		label.add_theme_constant_override("shadow_outline_size", 4)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.custom_minimum_size = Vector2(280.0, 0.0)
		root.add_child(label)
		labels.append(label)


func _legend_text() -> String:
	var lines: Array = []
	for i in range(IDS.size()):
		var def: Resource = actors[i].get("def") if i < actors.size() else null
		if def == null:
			continue
		lines.append("%s (%.2f m): %s" % [
			String(def.get("display_name")), float(def.call("height_m")),
			", ".join(anim_lists[i])])
	return "\n".join(lines)


# ------------------------------------------------------------------ frame ----
func _process(delta: float) -> void:
	if actors.is_empty():
		return
	_timer += delta
	if _timer >= ANIM_SECONDS:
		_timer = 0.0
		_cycle()
	_update_labels()


func _cycle() -> void:
	for i in range(actors.size()):
		var names: Array = anim_lists[i]
		if names.is_empty():
			continue
		_indexes[i] = (int(_indexes[i]) + 1) % names.size()
		var anim := String(names[int(_indexes[i])])
		var sprite: AnimatedSprite3D = actors[i].get("sprite")
		sprite.play(anim)
		sprite.frame = 0


func _update_labels() -> void:
	for i in range(actors.size()):
		if i >= labels.size():
			break
		var actor: Node3D = actors[i]
		var def: Resource = actor.get("def")
		var sprite: AnimatedSprite3D = actor.get("sprite")
		var anim := String(sprite.animation)
		var entry: Dictionary = def.call("anim_entry", anim)
		var fps := 10.0
		var frames_n := 0
		if entry != null:
			fps = float(entry.get("fps", 10.0))
			frames_n = int(entry.get("frames", 0))
		var label: Label = labels[i]
		label.text = "%s\n%s · %df · %.0f fps" % [
			String(def.get("display_name")).to_upper(), anim, frames_n, fps]
		var above := actor.global_position + Vector3(0.0, float(def.call("height_m")) + 0.32, 0.0)
		var p := camera.unproject_position(above)
		label.position = p - Vector2(140.0, 46.0)


func _texture(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	return ImageTexture.create_from_image(img)


func _font(path: String) -> Font:
	var f := FontFile.new()
	if f.load_dynamic_font(path) != OK:
		return ThemeDB.fallback_font
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.hinting = TextServer.HINTING_NONE
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return f
