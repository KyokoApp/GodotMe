shader_type spatial;
// Dirt path decal.
//
// A hard-edged strip of dirt across a grass meadow reads as a painted band, so
// the strip samples the *grass tile underneath it* and mixes the two with a
// noisy, feathered edge. The mesh only supplies the shape; the look comes from
// blending the same two tiles the ground uses.
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_disabled;

uniform sampler2D dirt_tex : source_color, filter_nearest, repeat_enable;
uniform sampler2D grass_tex : source_color, filter_nearest, repeat_enable;
uniform float half_width = 0.8;   // strip half width in metres (for square texels)
uniform float feather = 0.28;
uniform vec3 dirt_tint : source_color = vec3(1.42, 1.34, 1.20);

varying vec2 ground_uv;

void vertex() {
	// UV2 carries world XZ / tile size, so the grass under the path lines up
	// exactly with the ground plane's own tiling.
	ground_uv = UV2;
}

void fragment() {
	// 0 exactly at both long edges, 1 in the middle of the strip
	float edge = clamp(min(UV.x, 1.0 - UV.x) * 2.0, 0.0, 1.0);
	// square texels: X in metres/2 across, Y already metres/2 along
	vec2 duv = vec2(UV.x * half_width, UV.y);
	// two samples at different scales keep the tile from reading as stripes
	vec3 dirt = (texture(dirt_tex, duv).rgb * 0.62
		+ texture(dirt_tex, duv * 0.37 + vec2(0.31, 0.17)).rgb * 0.38) * dirt_tint;
	vec3 grass = texture(grass_tex, ground_uv).rgb;

	// noise pushes the boundary in and out so the track looks worn, not painted
	float n1 = texture(dirt_tex, duv * 2.3).r;
	float n2 = texture(dirt_tex, duv * 5.7).g;
	float wear = (n1 - 0.5) * 0.55 + (n2 - 0.5) * 0.30;
	float mask = smoothstep(0.12, 0.12 + feather, edge + wear);

	ALBEDO = mix(grass, dirt, mask);
	ALPHA = 1.0;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
