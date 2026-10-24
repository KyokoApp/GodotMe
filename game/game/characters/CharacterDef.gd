extends Resource
## One character, entirely as data.
##
## Adding a character is: drop the PNG strips in `game/assets/characters/<id>/`,
## add an entry to `tools/import_character_sprites.py`, run `--import`. No game
## code names a character anywhere; the runtime reads this resource only.
##
## Units: source pixels for `frame_size` / `pivot` / `*_px`, metres for the rest.
## `pivot` is measured from the non-transparent bounding box of the IDLE strip,
## so it is the middle of the feet, not the middle of the canvas.

@export var id: String = ""
@export var display_name: String = ""
## "player", "npc" or "enemy". Drives which brain CharacterWorld attaches.
@export var role: String = "npc"
@export var sprite_dir: String = ""
@export var frame_size: Vector2i = Vector2i(100, 100)
## Multiplier on `world_pixel_size`; only used because the packs were drawn at
## different resolutions (see DESIGN_NOTES section 9).
@export var pixel_scale: float = 1.0
## Feet pivot inside one frame, in source pixels, y measured from the top.
@export var pivot: Vector2 = Vector2(50.0, 60.0)
@export var body_width_px: int = 20
@export var content_height_px: int = 32
## The one global scale: metres per source pixel at pixel_scale 1.0.
@export var world_pixel_size: float = 0.05
## Metres covered by one full walk / run cycle. Speed is derived from this so
## the feet never slide (DESIGN_NOTES section 9).
@export var walk_stride_m: float = 0.75
@export var run_stride_m: float = 0.0
## Collision circle and blob-shadow size; the painted sprite is wider than the
## body because of the weapon, so this is not derived from the bbox width.
@export var body_radius_m: float = 0.3
## Each entry: {name, file, frames, fps, loop, hold_last}.
@export var animations: Array = []


func has_anim(anim: String) -> bool:
	return not anim_entry(anim).is_empty()


## Empty dictionary when the animation is not in this character's set.
func anim_entry(anim: String) -> Dictionary:
	for a in animations:
		if typeof(a) == TYPE_DICTIONARY and String((a as Dictionary).get("name", "")) == anim:
			return a as Dictionary
	return {}


func anim_names() -> Array:
	var out: Array = []
	for a in animations:
		if typeof(a) == TYPE_DICTIONARY:
			out.append(String((a as Dictionary).get("name", "")))
	return out


## Metres per source pixel for this character, i.e. what AnimatedSprite3D wants.
func pixel_world() -> float:
	return world_pixel_size * pixel_scale


func height_m() -> float:
	return float(content_height_px) * pixel_world()


func blob_size() -> Vector2:
	return Vector2(body_radius_m * 2.6, body_radius_m * 1.6)


## Nominal speed of a locomotion animation, in metres per second.
func locomotion_speed(anim: String) -> float:
	var entry := anim_entry(anim)
	if entry.is_empty():
		return 0.0
	var frames := float(entry.get("frames", 1))
	var fps := float(entry.get("fps", 10.0))
	var stride := walk_stride_m if anim == "walk" else run_stride_m
	if frames <= 0.0 or fps <= 0.0 or stride <= 0.0:
		return 0.0
	return stride / (frames / fps)
