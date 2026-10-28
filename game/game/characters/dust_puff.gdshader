shader_type spatial;
// Soft dust mote for footsteps. A billboarded quad with a radial falloff, so a
// walking actor kicks up dust without a single texture being shipped for it.
// Unshaded: dust is lit by the scene's mood through its colour, not by the sun.
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled, fog_disabled;

uniform vec4 dust_color : source_color = vec4(0.62, 0.55, 0.43, 0.38);
uniform float softness : hint_range(0.05, 1.0) = 0.9;

void vertex() {
	// billboard, keeping the per-particle scale from MODEL_MATRIX
	mat4 mat_world = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]),
		normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	mat_world = mat_world * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat_world;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float a = 1.0 - smoothstep(1.0 - softness, 1.0, length(p));
	ALBEDO = dust_color.rgb;
	ALPHA = dust_color.a * a;
}
