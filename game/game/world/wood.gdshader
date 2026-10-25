// Planks: bridge decks, rails, posts, docks and wooden floors.
//
// Same atlas as the ground (cell 6 is the plank texture), UVs in metres, so a
// deck two tiles long shows a continuous grain instead of two identical squares.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_disabled;

// No `source_color` on the atlas: the world loads its PNGs as raw bytes
// (see RegionView._tex), so the shader must sample them as they are stored.
// The hint would make the GPU decode them as sRGB - a dark green grass tile
// arrived almost black, and the whole valley came out muddy brown.
uniform sampler2D atlas : filter_nearest, repeat_enable;
uniform vec2 cell_wood = vec2(0.5, 0.5);
uniform float tile_scale = 1.0;
uniform vec3 light_tint : source_color = vec3(1.0, 1.0, 1.0);

void fragment() {
	vec2 local = fract(UV / tile_scale);
	vec3 plank = texture(atlas, cell_wood + vec2(local.x, local.y) * vec2(0.25, 0.5)).rgb;
	ALBEDO = plank * COLOR.rgb * COLOR.a * light_tint;
	ROUGHNESS = 0.9;
	SPECULAR = 0.0;
}
