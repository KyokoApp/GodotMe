shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_toon, specular_toon;

// Core visual mechanic: Senyap steals color (monochrome slate-violet).
// Player Lantern and lit Beacon Lanterns restore muted pastel palette smoothly.
uniform vec4 base_pastel_color : source_color = vec4(0.58, 0.67, 0.54, 1.0);
uniform vec4 senyap_tint : source_color = vec4(0.14, 0.13, 0.19, 1.0);
uniform sampler2D albedo_tex : source_color, filter_nearest;
uniform bool use_texture = false;

uniform vec3 player_lantern_pos = vec3(0.0, 0.0, 0.0);
uniform float player_lantern_radius : hint_range(0.0, 30.0) = 9.5;
uniform float region_restoration_ratio : hint_range(0.0, 1.0) = 0.25;
uniform float edge_softness : hint_range(0.5, 8.0) = 3.0;
uniform int toon_steps : hint_range(2, 4) = 3;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 tex_col = use_texture ? texture(albedo_tex, UV) : vec4(1.0);
	vec3 target_pastel = base_pastel_color.rgb * tex_col.rgb;

	// Luminance for monochrome Senyap state
	float luma = dot(target_pastel, vec3(0.299, 0.587, 0.114));
	vec3 monochrome_dark = mix(vec3(luma * 0.45), senyap_tint.rgb, 0.55);

	// Calculate restoration factor from Player Lantern + Regional Quest State
	float dist_to_lantern = distance(world_pos, player_lantern_pos);
	float local_light_factor = 1.0 - smoothstep(
		max(0.1, player_lantern_radius - edge_softness),
		player_lantern_radius,
		dist_to_lantern
	);

	// Subtle organic frontier shimmer along the edge of light
	float wave = sin(world_pos.x * 2.3 + TIME * 2.2) * cos(world_pos.z * 2.3 - TIME * 1.8) * 0.06;
	float restore_weight = clamp(max(region_restoration_ratio, local_light_factor + wave), 0.0, 1.0);

	ALBEDO = mix(monochrome_dark, target_pastel, restore_weight);
	ROUGHNESS = 0.85;
	SPECULAR = 0.1;
}

void light() {
	// 3-step Toon quantized shading for warm storybook feel
	float ndotl = max(dot(NORMAL, LIGHT), 0.0);
	float stepped = floor(ndotl * float(toon_steps)) / float(toon_steps);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * (stepped * 0.85 + 0.15);
}
