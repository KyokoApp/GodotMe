extends Node3D
## Screenshots for step 3C. One run per state, on a real (xvfb) display:
##
##   godot --path game --resolution 1280x720 res://game/tests/BattleShot.tscn -- \
##     --state=menu --capture=/abs/docs/screenshots --capture-name=51_battle_menu
##
## Every shot comes from the REAL battle scene standing on the REAL region, not
## from a mock. What is scripted is only the *input*: which button is pressed and
## which enemy is picked, exactly what a thumb would do. The states that cannot be
## reached by tapping quickly (a boss at half health, a party about to lose) are
## reached by setting the party's numbers and letting the engine play the rest -
## the animations and the interface are the same ones the player sees.

const HARNESS := preload("res://game/tests/TestHarness.gd")
const DIORAMA := "res://game/world/Diorama.tscn"
const BATTLE := "res://game/battle/BattleScene.gd"

var world: Node3D = null
var battle: Node3D = null


func _ready() -> void:
	await get_tree().process_frame
	if not HARNESS.has_arg("--capture="):
		print("[SHOT] butuh --capture=<dir>")
		get_tree().quit(2)
		return
	var state := HARNESS.arg("--state=", "awal")
	print("[SHOT] mulai state=%s" % state)
	# A capture run that never reaches its capture line hangs the whole CI job
	# (a real failure this step had: one state awaited a signal that the software
	# renderer never sent, and the job sat there for forty minutes). The watchdog
	# turns any such bug into a logged, bounded exit instead.
	_watchdog(90.0)
	if not ResourceLoader.exists(DIORAMA):
		print("[SHOT] Diorama tidak ada")
		get_tree().quit(2)
		return
	world = load(DIORAMA).instantiate()
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame
	var region: Variant = world.call("region")
	var spot: Vector2 = world.call("start_position")
	# Build the ground under the arena before anything stands on it. The field
	# does this for the player every time he crosses a tile; here there is no
	# cast to walk, so the shot asks the world directly (the same call a teleport
	# makes). Without it the battle stands on a hole: the first ten captures
	# showed the interface over flat fog.
	world.call("stream_now", spot)
	await get_tree().process_frame
	if state == "dunia":
		# A reference shot of the world alone, from the world's own camera: if
		# this one comes out grey too, the fault is in this stage, not in the
		# battle. It is also the only frame that can be compared with the field
		# captures from step 1/3A, which are known good.
		await get_tree().create_timer(1.2).timeout
		_diagnostics(state)
		await HARNESS.capture(self, "51_pertarungan_dunia", 0.2)
		return
	var script: Script = load(BATTLE)
	battle = script.new()
	battle.name = "Battle"
	add_child(battle)
	battle.call("start", region, spot, "ujian_orc", {
		"level": 3, "exp": 320, "leaf": 240, "seed": 7,
		"observed": {"orc_prajurit": ["tombak"], "orc_pemimpin": ["tombak", "es"]},
	})
	await _reach(state)
	_describe(state)
	_diagnostics(state)
	var shot := HARNESS.arg("--capture-name=", "51_pertarungan_%s" % state)
	# the transition shot must not wait: its whole point is a frame mid-flight
	await HARNESS.capture(self, shot, 0.0 if state == "transisi" else 0.35)


## One line of numbers per shot. A screenshot can only be judged by looking at
## it, but when it comes out wrong the first question is always "is the world
## there, are the fighters there, is the camera the right one" - and the CI log is
## the only place to ask. Printed as the last thing before the frame is grabbed,
## so `tail` shows it next to the capture line.
func _describe(state: String) -> void:
	var stats: Dictionary = {}
	if world != null and world.has_method("stream_stats"):
		stats = world.call("stream_stats")
	var chunks := int(stats.get("loaded", stats.get("chunks", -1)))
	var view: Node3D = battle.get("view")
	var sprite_count := 0
	var cam_pos := Vector3.ZERO
	var cam_current := "?"
	if view != null:
		var sprites: Variant = view.get("_sprites")
		if typeof(sprites) == TYPE_DICTIONARY:
			sprite_count = (sprites as Dictionary).size()
		var cam: Camera3D = view.get("camera") as Camera3D
		if cam != null:
			cam_pos = cam.global_position
			cam_current = "ya" if cam.current else "tidak"
	print("[SHOT] state=%s region=%s chunk=%d sprite=%d kamera=%s pos=%s ui=%s" % [
		state, "ada" if world.call("region") != null else "TIDAK",
		chunks, sprite_count, cam_current, str(cam_pos.round()),
		str(ui_size())])


## Everything that decides whether a 3D frame is drawn. Added after the first
## capture run came back with the interface over flat brown: a screenshot can say
## "wrong", it cannot say WHICH of camera, world, environment or materials is
## missing - and a wrong guess costs a twelve-minute CI round trip.
func _diagnostics(state: String) -> void:
	var vp := get_viewport()
	var cam := vp.get_camera_3d()
	print("[DIAG] viewport %s renderer=%s" % [str(vp.get_visible_rect().size),
		RenderingServer.get_video_adapter_name()])
	print("[DIAG] kamera aktif=%s pos=%s fov=%.1f near=%.2f far=%.1f" % [
		cam.get_path() if cam != null else "TIDAK ADA",
		str(cam.global_position.round()) if cam != null else "-",
		cam.fov if cam != null else 0.0, cam.near if cam != null else 0.0,
		cam.far if cam != null else 0.0])
	for node in _cameras(self, []):
		var c: Camera3D = node
		print("[DIAG]   kamera %s current=%s pos=%s" % [c.get_path(), str(c.current),
			str(c.global_position.round())])
	var env := _world_env(self)
	if env == null:
		print("[DIAG] WorldEnvironment TIDAK ADA")
	else:
		print("[DIAG] env bg_mode=%d warna_bg=%s sky=%s sky_mat=%s fog=%.3f" % [
			env.background_mode, str(env.background_color), str(env.sky),
			env.sky.sky_material.get_class() if env.sky != null and env.sky.sky_material != null else "-",
			env.fog_density])
	var view: Node3D = world.call("view") if world != null else null
	var chunks := 0
	var mesh_ok := 0
	var sample := ""
	if view != null and view.has_method("chunk_nodes"):
		var nodes: Dictionary = view.call("chunk_nodes")
		chunks = nodes.size()
		for key in nodes.keys():
			var chunk: Node3D = nodes[key]
			var mi := chunk.get_node_or_null("Ground") as MeshInstance3D
			if mi == null:
				continue
			mesh_ok += 1
			if sample == "":
				var mat := mi.mesh.surface_get_material(0) if mi.mesh != null and mi.mesh.get_surface_count() > 0 else null
				var tex: Variant = null
				if mat is ShaderMaterial:
					tex = (mat as ShaderMaterial).get_shader_parameter("atlas")
				sample = "aabb=%s visible=%s atlas=%s" % [str(mi.mesh.get_aabb()),
					str(mi.visible), "ADA" if tex != null else "NULL"]
	print("[DIAG] chunk=%d mesh_tanah=%d %s" % [chunks, mesh_ok, sample])
	if battle != null:
		var layer: CanvasLayer = battle.get("_wipe_layer") as CanvasLayer
		var mat: ShaderMaterial = battle.get("_wipe_mat") as ShaderMaterial
		print("[DIAG] transisi layer=%s t=%s" % [
			"tampil" if layer != null and layer.visible else "parkir",
			str(mat.get_shader_parameter("t")) if mat != null else "-"])
		var v: Node3D = battle.get("view")
		if v != null:
			var sprites: Variant = v.get("_sprites")
			if typeof(sprites) == TYPE_DICTIONARY and not (sprites as Dictionary).is_empty():
				var first_uid: int = (sprites as Dictionary).keys()[0]
				var sp: AnimatedSprite3D = (sprites as Dictionary)[first_uid]
				print("[DIAG] sprite uid=%d visible=%s pos=%s frames=%s teks=%s" % [
					first_uid, str(sp.is_visible_in_tree()), str(sp.global_position.round()),
					str(sp.sprite_frames != null),
					str(sp.sprite_frames != null and sp.sprite_frames.get_frame_count("idle") > 0
						and sp.sprite_frames.get_frame_texture("idle", 0) != null)])
	var vp_img := vp.get_texture().get_image()
	if vp_img != null and vp_img.get_width() > 8:
		var w := vp_img.get_width()
		var h := vp_img.get_height()
		print("[DIAG] piksel tengah=%s kiri-atas=%s bawah=%s" % [
			str(vp_img.get_pixel(w / 2, h / 2)), str(vp_img.get_pixel(8, 8)),
			str(vp_img.get_pixel(w / 2, h - 8))])


## Which render layers the first battle sprite is on. A camera and a mesh with
## no layer in common is the classic "3D draws nothing" trap.
func _first_sprite_layers() -> int:
	var v: Node3D = battle.get("view") if battle != null else null
	if v == null:
		return -1
	var sprites: Variant = v.get("_sprites")
	if typeof(sprites) != TYPE_DICTIONARY or (sprites as Dictionary).is_empty():
		return -2
	var uid: int = (sprites as Dictionary).keys()[0]
	var sp: AnimatedSprite3D = (sprites as Dictionary)[uid]
	return sp.layers


func _cameras(node: Node, out: Array) -> Array:
	for child in node.get_children():
		if child is Camera3D:
			out.append(child)
		_cameras(child, out)
	return out


func _world_env(node: Node) -> Environment:
	for child in node.get_children():
		if child is WorldEnvironment:
			return (child as WorldEnvironment).environment
		var found := _world_env(child)
		if found != null:
			return found
	return null


func ui_size() -> Vector2:
	var ui: Control = battle.get("ui")
	return ui.size if ui != null else Vector2.ZERO


func _watchdog(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	print("[SHOT] batas waktu %.0f s tercapai, keluar." % seconds)
	get_tree().quit(3)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _logic() -> RefCounted:
	var l: RefCounted = battle.get("logic")
	return l


func _ui() -> Control:
	var c: Control = battle.get("ui")
	return c


func _foe(index: int) -> Dictionary:
	var foes: Array = _logic().get("foes")
	var out: Dictionary = foes[index]
	return out


func _ready_battle() -> void:
	# let the shatter finish so the arena is fully visible
	await _wait(1.6)


func _reach(state: String) -> void:
	match state:
		"transisi":
			# mid-shatter. The wipe tween is running, so the honest way to catch it
			# is to stand still and let it pass: 0.25 s into a 0.55 s shatter is a
			# real frame of the real transition, not a hand-set uniform fighting
			# the tween back on the next frame.
			await _wait(0.25)
			return
		"awal":
			await _ready_battle()
			return
		"menu":
			await _ready_battle()
			_ui().call("select_target", int(_foe(1)["uid"]))
			_ui().call("refresh")
			return
		"kelemahan":
			await _ready_battle()
			# two known weaknesses on the leader and one on a soldier: the "?" row
			var observed: Dictionary = _logic().get("observed")
			observed["orc_pemimpin"] = ["tombak", "es"]
			observed["orc_prajurit"] = ["tombak", "api"]
			_ui().call("select_target", int(_foe(3)["uid"]))
			_ui().call("refresh")
			return
		"boost":
			await _ready_battle()
			_logic().set("awaiting", (_logic().get("allies") as Array)[0])
			_ui().call("_cycle_boost")
			_ui().call("_cycle_boost")
			_ui().call("refresh")
			return
		"break":
			await _ready_battle()
			var foe := _foe(0)
			foe["shield"] = 1
			_trigger_attack(int(foe["uid"]))
			await _wait(0.75)
			return
		"damage":
			await _ready_battle()
			_trigger_attack(int(_foe(1)["uid"]))
			await _wait(0.42)
			return
		"fase2":
			await _ready_battle()
			var boss := _foe(3)
			boss["hp"] = int(float(boss["hp_max"]) * 0.5) + 4
			_trigger_attack(int(boss["uid"]))
			await _wait(1.5)
			return
		"hasil":
			await _ready_battle()
			for raw in (_logic().get("foes") as Array):
				var foe: Dictionary = raw
				foe["hp"] = 0
				foe["alive"] = false
			_logic().set("finished", true)
			_logic().set("result", "win")
			battle.call("_finish")
			await _wait(0.7)
			return
		"kamera":
			# Is ANY 3D drawn under the battle camera? A bright box three metres
			# over the arena answers that in one frame: if the box shows and the
			# world does not, the fault is the world's materials; if nothing
			# shows, the fault is the camera or the 3D pass itself.
			await _ready_battle()
			_probe_box()
			await _wait(0.3)
			return
		"bawah":
			# The battle position, looking straight DOWN: the frame that proved
			# geometry does render from here. A picture of what is under the lens
			# says more than any pixel count.
			await _ready_battle()
			var cam := _battle_camera()
			cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
			cam.position.y -= 2.0
			await _wait(0.4)
			return
		"samping":
			# The battle position with the lens laid back to half the pitch: the
			# transition between "renders" and "does not".
			await _ready_battle()
			var cam2 := _battle_camera()
			cam2.rotation_degrees = Vector3(-45.0, 5.0, 0.0)
			await _wait(0.4)
			return
		"kotak":
			# A bright box on the arena floor from the battle lens: if the box is
			# invisible too, the whole view is fogged or covered, not just sprites.
			await _ready_battle()
			_probe_box()
			await _wait(0.4)
			return
		"kamerasalin":
			# Same transform, different camera OBJECT: the world's own camera is
			# moved onto the battle camera's position, rotation, fov and planes.
			# If the world appears now, the transform is fine and the battle's
			# Camera3D itself is what renders nothing (cull mask, projection...).
			# If it stays empty, the position is simply wrong.
			await _ready_battle()
			var rig := world.get_node_or_null("CameraRig/Camera3D") as Camera3D
			var cam := _battle_camera()
			if rig != null and cam != null:
				rig.global_transform = cam.global_transform
				rig.fov = cam.fov
				rig.near = cam.near
				rig.far = cam.far
				rig.current = true
				print("[PROBE] salin: battle cull=%d near=%.2f far=%.1f proj=%d | dunia cull=%d near=%.2f far=%.1f" % [
					cam.cull_mask, cam.near, cam.far, cam.projection,
					rig.cull_mask, rig.near, rig.far])
			await _wait(0.35)
			return
		"duakamera":
			# Hand the frame back to the world's own camera. If the arena appears
			# now, the battle camera is what breaks the 3D pass; if it stays
			# brown, something in the battle's own subtree is.
			await _ready_battle()
			var rig := world.get_node_or_null("CameraRig/Camera3D") as Camera3D
			if rig != null:
				rig.current = true
			await _wait(0.35)
			return
		"kalah":
			await _ready_battle()
			for raw in (_logic().get("allies") as Array):
				var ally: Dictionary = raw
				ally["hp"] = 0
				ally["alive"] = false
			_logic().set("finished", true)
			_logic().set("result", "lose")
			battle.call("_finish")
			await _wait(0.7)
			return
		_:
			await _ready_battle()
			return


## Try every camera arrangement that could explain an empty frame, and report a
## coverage number for each. Coverage = share of pixels that differ from the flat
## background the frame had when nothing was drawn.
func _camera_trials() -> void:
	var battle_cam := _battle_camera()
	var world_cam := world.get_node_or_null("CameraRig/Camera3D") as Camera3D
	if battle_cam == null:
		print("[PROBE] kamera pertarungan tidak ada")
		return
	var at := Vector3(centre().x, 0.0, centre().y)
	print("[PROBE] battle visible_in_tree=%s parent_visible=%s world_3d=%s vp_world_3d=%s" % [
		str(battle_cam.is_visible_in_tree()),
		str((battle_cam.get_parent() as Node3D).is_visible_in_tree()),
		str(battle_cam.get_world_3d().get_rid()), str(get_viewport().world_3d.get_rid())])
	print("[PROBE] battle pos=%s fov=%.1f near=%.2f far=%.1f pusat=%s" % [
		str(battle_cam.global_position.round()), battle_cam.fov, battle_cam.near,
		battle_cam.far, str(at.round())])
	await _coverage("A battle apa adanya", battle_cam)
	if world_cam != null:
		await _coverage("B kamera dunia", world_cam)
	# Where exactly does it break? Same aim, several positions along the line the
	# battle lens sits on, plus the world camera's own spot.
	var spots: Array = [
		["battle 46,8,170", Vector3(46.0, 8.0, 170.0)],
		["dunia   42,9,165", Vector3(42.0, 9.0, 165.0)],
		["tinggi  46,14,170", Vector3(46.0, 14.0, 170.0)],
		["rendah  46,4,170", Vector3(46.0, 4.0, 170.0)],
		["dekat   44,8,164", Vector3(44.0, 8.0, 164.0)],
		["belakang 46,8,178", Vector3(46.0, 8.0, 178.0)],
	]
	for entry in spots:
		var row: Array = entry
		var probe := Camera3D.new()
		probe.name = "Probe"
		probe.fov = battle_cam.fov
		probe.near = battle_cam.near
		probe.far = battle_cam.far
		add_child(probe)
		probe.global_position = row[1]
		probe.look_at(at, Vector3.UP)
		await _coverage(String(row[0]), probe)
		probe.queue_free()
		await get_tree().process_frame
	# Culling: give every mesh in the world a huge margin. If the arena appears
	# with the battle camera, the ground was being frustum-culled, not missing.
	for mi in _meshes(self, []):
		var m: MeshInstance3D = mi
		m.extra_cull_margin = 400.0
	await _coverage("A2 battle, culling dilonggarkan", battle_cam)


func _meshes(node: Node, out: Array) -> Array:
	for child in node.get_children():
		if child is MeshInstance3D:
			out.append(child)
		_meshes(child, out)
	return out


func centre() -> Vector2:
	return battle.get("centre")


func _coverage(label: String, cam: Camera3D) -> void:
	cam.current = true
	await get_tree().create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		print("[PROBE] %s: tidak ada gambar" % label)
		return
	var w := img.get_width()
	var h := img.get_height()
	var bg := img.get_pixel(4, 4)
	var drawn := 0
	var total := 0
	for y in range(0, h, 6):
		for x in range(0, w, 6):
			total += 1
			var c := img.get_pixel(x, y)
			if absf(c.r - bg.r) + absf(c.g - bg.g) + absf(c.b - bg.b) > 0.08:
				drawn += 1
	print("[PROBE] %s: %d/%d piksel berisi (%.1f%%) kamera=%s" % [
		label, drawn, total, 100.0 * float(drawn) / float(maxi(1, total)),
		str(cam.get_path())])


## A magenta box, unshaded, floating over the middle of the arena.
func _battle_camera() -> Camera3D:
	var v: Node3D = battle.get("view")
	if v == null:
		return null
	return v.get("camera") as Camera3D


func _probe_box() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.0, 2.0, 2.0)
	var mi := MeshInstance3D.new()
	mi.name = "ProbeBox"
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.1, 0.9)
	mi.material_override = mat
	var spot: Vector2 = battle.get("centre")
	var y := 2.0
	if world != null and world.has_method("region"):
		var region: Variant = world.call("region")
		if region != null:
			y = float(region.call("height_at", spot)) + 1.5
	mi.position = Vector3(spot.x, y, spot.y)
	add_child(mi)
	var cam := _battle_camera()
	if cam == null:
		print("[PROBE] kotak: kamera pertarungan tidak ada")
		return
	print("[PROBE] kotak %s layar=%s belakang=%s cull=%d sprite_layers=%d" % [
		str(mi.global_position.round()), str(cam.unproject_position(mi.global_position).round()),
		str(cam.is_position_behind(mi.global_position)), cam.cull_mask, _first_sprite_layers()])
	# The picture itself is the measurement (a magenta box is impossible to miss
	# in a 640x360 frame); reading the framebuffer back mid-frame was where this
	# step hung, so it does not do that any more.


## Act as if the player had tapped Serang (or the skill) on that enemy, without
## waiting for the tap: the events still play at their real speed.
func _trigger_attack(target_uid: int) -> void:
	var allies: Array = _logic().get("allies")
	var knight: Dictionary = allies[0]
	var foe: Dictionary = {}
	for raw in (_logic().get("foes") as Array):
		if int((raw as Dictionary)["uid"]) == target_uid:
			foe = raw
	var action := {"kind": "skill", "id": "tebas_naik", "target": target_uid, "boost": 0}
	if int(knight["sp"]) < 6:
		action = {"kind": "attack", "target": target_uid, "boost": 0}
	_logic().set("awaiting", knight)
	# `_apply` is the controller's own path: engine first, then the animation
	battle.call("_apply", action)
	await get_tree().process_frame
	_ui().call("refresh")
