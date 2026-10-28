// Billboards for REGION "Yaros": trees, rocks, houses, the gate, the tower.
//
// Four things this shader has to do at once, which is why it is not a
// StandardMaterial3D:
//   1. yaw-only billboard - the sprite turns with the camera around the vertical
//      axis and stays upright, so a pine does not lean when the camera pitches;
//   2. one atlas for every prop, with the cell chosen per instance, so a chunk
//      draws eighty props in ONE call (a MultiMesh can only bind one texture);
//   3. a per-instance horizontal flip, so one pine texture yields two
//      silhouettes and a forest stops looking stamped;
//   4. a per-instance dithered fade, used when the knight walks behind a house
//      or a tree: the occluder dissolves in a pixel pattern instead of turning
//      into a transparent pane that sorts wrongly against the next tree.
//
// Unshaded on purpose. The art bakes its own light (sun from the upper left, as
// in every texture in this game), the world's sun never moves, and a lit
// billboard on a phone costs a normal pass for no visible gain. The day phase
// tints the whole set through `light_tint`, so props still warm up at dusk.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque, cull_disabled;

// No `source_color` on the atlas: the world loads its PNGs as raw bytes
// (see RegionView._tex), so the shader must sample them as they are stored.
// The hint would make the GPU decode them as sRGB - a dark green grass tile
// arrived almost black, and the whole valley came out muddy brown.
uniform sampler2D albedo_tex : filter_nearest, repeat_disable;
// alpha below this is thrown away; the sprites are hard-edged pixel art, so a
// low threshold keeps pine needles from thinning out
uniform float scissor : hint_range(0.0, 1.0) = 0.42;
// (x, y, width, height) in atlas UV space. One material per prop kind, so this
// is a single rect and the instance only has to say "mirror me" and "fade me".
uniform vec4 cell_rect = vec4(0.0, 0.0, 1.0, 1.0);
// multiplied into every prop: the clock's dusk amber lives here
uniform vec3 light_tint = vec3(1.0, 1.0, 1.0);

varying vec2 sprite_uv;

void vertex() {
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), 1.0);
	vec3 origin = MODEL_MATRIX[3].xyz;
	// camera right, flattened to the ground plane: that is a yaw-only billboard
	vec3 right = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z));
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 world = origin + right * (VERTEX.x * scale.x) + up * (VERTEX.y * scale.y);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	sprite_uv = VERTEX.xy + vec2(0.5);
}

void fragment() {
	// the instance colour carries r = fade, g = mirror, b = shade. Reading it
	// here instead of in vertex() is deliberate: Godot folds the MultiMesh
	// instance colour into COLOR at the end of the vertex stage, so this is the
	// only place it is guaranteed to be present - and it keeps the shader inside
	// what the Compatibility renderer offers.
	float fade = COLOR.r;
	float mirror = COLOR.g;
	float shade = COLOR.b;
	vec4 cell = cell_rect;
	vec2 uv = sprite_uv;
	if (mirror > 0.5) {
		uv.x = 1.0 - uv.x;
	}
	// atlas v grows downwards, the quad's uv grows upwards
	vec2 tex_uv = vec2(cell.x + uv.x * cell.z, cell.y + (1.0 - uv.y) * cell.w);
	vec4 tex = texture(albedo_tex, tex_uv);
	// 8x8 ordered dither, checked in screen pixels: readable at phone DPI and
	// stable while walking, unlike a noise function
	ivec2 p = ivec2(FRAGCOORD.xy);
	float threshold = float((p.x * 3 + p.y * 5) % 8) / 8.0 + 0.0625;
	if (tex.a < scissor || threshold > fade) {
		discard;
	}
	ALBEDO = tex.rgb * light_tint * shade;
	ALPHA = 1.0;
}
