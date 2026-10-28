// Step 3C : the battle transition - shatter and swirl, never a zoom.
//
// A zoom reads as "the camera moved". This effect reads as "the field broke
// apart": the picture is cut into square shards that slide away along their own
// diagonal while the whole frame rotates and shrinks around the centre, and the
// battle is revealed underneath. Built from the screen texture, so it works on
// the Compatibility renderer a phone uses, with no viewport of its own.
//
// `t` runs 0 -> 1. At 0 nothing is covered. At 1 the screen is fully replaced
// (alpha 0 everywhere), which is when the controller swaps the scene behind it
// and plays the shader backwards to close the battle.
shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float t : hint_range(0.0, 1.0) = 0.0;
// the cell the shards break along, in screen fraction. 24 shards across a phone
// reads as "shattered" without turning into noise.
uniform vec2 shard_grid = vec2(16.0, 10.0);
uniform float swirl = 0.55;
// the colour of the gap between the shards, so the reveal is a dark tear rather
// than a soft dissolve
uniform vec3 tear_color = vec3(0.04, 0.03, 0.03);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 centre = vec2(0.5, 0.5);
	vec2 rel = uv - centre;

	// shards: which cell is this pixel in, and when does that shard leave
	vec2 cell = floor(uv * shard_grid);
	vec2 local = fract(uv * shard_grid);
	float seed = hash(cell);
	// each shard has its own start, so they peel away one after another
	float start = seed * 0.35;
	float span = 0.65;
	float k = clamp((t - start) / span, 0.0, 1.0);
	// the shard's own direction: outward from the centre, biased by its hash
	vec2 dir = normalize(rel + vec2(seed - 0.5, hash(cell + 7.0) - 0.5) * 0.35 + vec2(0.0001));
	float mag = length(rel);

	// swirl: the whole frame turns as it breaks, more towards the edge
	float ang = k * swirl * (0.35 + mag);
	float cs = cos(ang);
	float sn = sin(ang);
	vec2 turned = vec2(rel.x * cs - rel.y * sn, rel.x * sn + rel.y * cs);
	turned *= 1.0 - 0.18 * k;

	// the shard slides outward and shrinks a little
	vec2 shard_uv = turned + centre + dir * k * (0.05 + 0.11 * seed);
	// a 2% shrink per shard makes the gaps between them, and the gaps are what
	// makes it read as broken glass instead of a wipe
	vec2 inner = (local - 0.5) * (1.0 - 0.10 * k) + 0.5;
	vec2 sample_uv = (cell + inner) / shard_grid;
	sample_uv = mix(sample_uv, shard_uv, k);

	vec3 col = textureLod(screen_tex, sample_uv, 0.0).rgb;
	// Darken the torn edge of every shard - but only once the shards have begun
	// to move. Drawn unconditionally, this grid of dark seams is painted over a
	// perfectly intact frame, and every battle screenshot carried a permanent
	// black grid across the arena because at t = 0 the "broken glass" edges
	// existed while the glass was still whole.
	float edge = min(min(local.x, 1.0 - local.x), min(local.y, 1.0 - local.y));
	float tear = (1.0 - smoothstep(0.0, 0.06 + 0.12 * k, edge)) * clamp(k * 2.5, 0.0, 1.0);
	col = mix(col, tear_color, tear);

	// and the whole overlay fades out at the end, so nothing pops when the
	// controller swaps the scene behind it
	float cover = 1.0 - smoothstep(0.82, 1.0, t);
	// ... and it has to be INVISIBLE at the start, not merely a copy: a shader
	// that is always at least partly drawn costs a full-screen pass over the
	// arena for the whole fight.
	float lead = smoothstep(0.0, 0.06, t);
	COLOR = vec4(col, clamp(cover * lead * (0.35 + 0.65 * (1.0 - k)), 0.0, 1.0));
}
