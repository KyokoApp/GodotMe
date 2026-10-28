extends RefCounted
## Argument parsing and screenshot capture shared by the visual test scenes.
##
## It mirrors what Main.gd does for the game capture, so CI has one behaviour:
##   godot --path game res://game/tests/CharacterTest.tscn -- \
##     --capture=/abs/docs/screenshots --capture-name=09_karakter --capture-delay=2.0


static func arg(prefix: String, fallback: String = "") -> String:
	for raw in OS.get_cmdline_user_args():
		var a := String(raw)
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return fallback


static func has_arg(prefix: String) -> bool:
	for raw in OS.get_cmdline_user_args():
		if String(raw).begins_with(prefix):
			return true
	return false


## Wait, grab the frame, write the PNG, quit. Returns quietly when the run has
## no --capture argument (a plain scene run for eyeballing on desktop).
static func capture(node: Node, default_name: String, delay: float = 2.0) -> void:
	var dir := arg("--capture=")
	if dir == "":
		return
	var shot := arg("--capture-name=", default_name)
	var wait := float(arg("--capture-delay=", str(delay)))
	await node.get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(dir)
	var img := node.get_viewport().get_texture().get_image()
	# A shot whose only job is to answer "is the 3D there at all" does not need
	# 1280x720 of detail in the repository. `--capture-size=640x360` keeps the
	# diagnostic frames small; every other shot keeps the full frame.
	var wanted := arg("--capture-size=")
	if wanted != "" and img != null:
		var parts := wanted.split("x")
		if parts.size() == 2:
			var w := int(parts[0])
			var h := int(parts[1])
			if w > 0 and h > 0 and (img.get_width() != w or img.get_height() != h):
				img.resize(w, h, Image.INTERPOLATE_BILINEAR)
	var path := dir.path_join(shot + ".png")
	var err := img.save_png(path)
	print("[TEST] capture %s -> %s (err %d, %dx%d)" % [
		shot, path, err, img.get_width(), img.get_height()])
	node.get_tree().quit(0)


## Safety net so a headless run can never hang the CI job.
static func quit_after(node: Node, seconds: float = 25.0) -> void:
	# only a capture run needs the safety net; a desktop eyeball run should stay
	# on screen until the window is closed
	if not has_arg("--capture=") and not has_arg("--quit-after="):
		return
	var limit := float(arg("--quit-after=", str(seconds)))
	await node.get_tree().create_timer(limit).timeout
	print("[TEST] batas waktu %.1f s tercapai, keluar." % limit)
	node.get_tree().quit(0)
