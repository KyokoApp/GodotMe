shader_type spatial;
render_mode depth_prepass_alpha, cull_disabled, diffuse_toon;

uniform sampler2D sprite_tex : source_color, filter_nearest;
uniform float wind_strength : hint_range(0.0, 2.0) = 0.35;
uniform float wind_speed : hint_range(0.1, 6.0) = 2.1;
uniform vec3 player_lantern_pos = vec3(0.0);
uniform float player_lantern_radius = 9.5;
uniform float region_restoration_ratio : hint_range(0.0, 1.0) = 0.25;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Top vertices sway with wind (UV.y closer to 0 is top of billboard)
	float height_factor = clamp(1.0 - UV.y, 0.0, 1.0);
	float sway = sin(TIME * wind_speed + world_pos.x * 1.4 + world_pos.z * 0.9) * wind_strength * height_factor;
	VERTEX.x += sway * 0.25;
}

void fragment() {
	vec4 col = texture(sprite_tex, UV);
	if (col.a < 0.15) {
		discard;
	}
	float luma = dot(col.rgb, vec3(0.299, 0.587, 0.114));
	vec3 senyap_mono = mix(vec3(luma * 0.4), vec3(0.15, 0.14, 0.20), 0.5);
	float dist = distance(world_pos, player_lantern_pos);
	float local_restore = 1.0 - smoothstep(player_lantern_radius - 2.5, player_lantern_radius, dist);
	float restore = clamp(max(region_restoration_ratio, local_restore), 0.0, 1.0);

	ALBEDO = mix(senyap_mono, col.rgb, restore);
	ALPHA = col.a;
}
