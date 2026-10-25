// Planks: bridge decks, rails, posts, docks and wooden floors.
//
// Same atlas as the ground (cell 6 is the plank texture), UVs in metres, so a
// deck two tiles long shows a continuous grain instead of two identical squares.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_disabled;

uniform sampler2D atlas : source_color, filter_nearest, repeat_enable;
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
