// Water for the region: a still surface with a scrolling swell, a shore line
// and a cheap sky highlight. Two samples of the water texture at different
// speeds read as depth without a normal map.
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, specular_schlick_ggx;

// No `source_color` on the atlas: the world loads its PNGs as raw bytes
// (see RegionView._tex), so the shader must sample them as they are stored.
// The hint would make the GPU decode them as sRGB - a dark green grass tile
// arrived almost black, and the whole valley came out muddy brown.
uniform sampler2D water_tex : filter_nearest, repeat_enable;
uniform vec3 shallow_tint : source_color = vec3(0.62, 0.80, 0.78);
uniform vec3 deep_tint : source_color = vec3(0.30, 0.46, 0.52);
uniform vec3 foam_tint : source_color = vec3(0.92, 0.95, 0.90);
uniform float foam_width = 0.20;

void fragment() {
	// UV is world XZ in metres: the same ripple flows across tile borders
	vec2 uv1 = UV * 0.24 + vec2(TIME * 0.010, TIME * 0.004);
	vec2 uv2 = UV * 0.31 - vec2(TIME * 0.006, TIME * 0.009);
	vec3 a = texture(water_tex, uv1).rgb;
	vec3 b = texture(water_tex, uv2).rgb;
	float swell = (a.r + b.g) * 0.5;

	// COLOR.rgb is the depth tint written per water tile, COLOR.a marks a tile
	// that touches land. The foam lives on the lattice of the world UV, so it
	// runs along the shore of every tile that touches ground.
	vec3 base = COLOR.rgb;
	vec2 cell = fract(UV);
	float edge = min(min(cell.x, 1.0 - cell.x), min(cell.y, 1.0 - cell.y));
	float shore = (1.0 - smoothstep(0.0, foam_width, edge)) * COLOR.a;
	float lace = smoothstep(0.35, 0.75, swell + 0.25 * sin(UV.x * 9.0 + TIME * 0.6));

	ALBEDO = mix(base * (0.82 + 0.30 * swell), foam_tint, shore * lace * 0.85);
	ROUGHNESS = mix(0.14, 0.55, shore);
	METALLIC = 0.10;
	ALPHA = mix(0.93, 0.99, shore);
	// a whisper of normal variation so the sun leaves a moving glint
	NORMAL = normalize(NORMAL + vec3((a.r - 0.5) * 0.25, 0.0, (b.g - 0.5) * 0.25));
}
