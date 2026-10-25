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

uniform sampler2D albedo_tex : source_color, filter_nearest, repeat_disable;
// alpha below this is thrown away; the sprites are hard-edged pixel art, so a
// low threshold keeps pine needles from thinning out
uniform float scissor : hint_range(0.0, 1.0) = 0.42;
// (x, y, width, height) in atlas UV space, one per prop kind
uniform vec4 cell_rects[16];
// multiplied into every prop: the clock's dusk amber lives here
uniform vec3 light_tint = vec3(1.0, 1.0, 1.0);

varying vec2 sprite_uv;
varying vec4 inst;

void vertex() {
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), 1.0);
	vec3 origin = MODEL_MATRIX[3].xyz;
	// camera right, flattened to the ground plane: that is a yaw-only billboard
	vec3 right = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z));
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 world = origin + right * (VERTEX.x * scale.x) + up * (VERTEX.y * scale.y);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	sprite_uv = VERTEX.xy + vec2(0.5);
	inst = INSTANCE_CUSTOM;
}

void fragment() {
	int idx = int(inst.x + 0.5);
	vec4 cell = cell_rects[idx];
	vec2 uv = sprite_uv;
	if (inst.y > 0.5) {
		uv.x = 1.0 - uv.x;
	}
	// atlas v grows downwards, the quad's uv grows upwards
	vec2 tex_uv = vec2(cell.x + uv.x * cell.z, cell.y + (1.0 - uv.y) * cell.w);
	vec4 tex = texture(albedo_tex, tex_uv);
	// 8x8 ordered dither, checked in screen pixels: readable at phone DPI and
	// stable while walking, unlike a noise function
	ivec2 p = ivec2(FRAGCOORD.xy);
	float threshold = float((p.x * 3 + p.y * 5) % 8) / 8.0 + 0.0625;
	if (tex.a < scissor || threshold > inst.z) {
		discard;
	}
	ALBEDO = tex.rgb * light_tint;
	ALPHA = 1.0;
}
