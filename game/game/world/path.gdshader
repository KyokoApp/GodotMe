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
uniform float dirt_scale = 1.6;
uniform float feather = 0.22;
uniform vec3 dirt_tint : source_color = vec3(1.42, 1.34, 1.20);

varying vec2 ground_uv;

void vertex() {
	// UV2 carries world XZ / tile size, so the grass under the path lines up
	// exactly with the ground plane's own tiling.
	ground_uv = UV2;
}

void fragment() {
	// how far inside the strip this fragment is (0 at the edge, 1 in the middle)
	float edge = clamp(min(UV.x, 1.0 - UV.x) * 2.0, 0.0, 1.0);
	// UV is already in metres/2 on both axes, so the dirt never stretches
	vec3 dirt = texture(dirt_tex, UV * dirt_scale).rgb * dirt_tint;
	vec3 grass = texture(grass_tex, ground_uv).rgb;

	// two scales of noise break the outline so the track reads as worn ground
	float n1 = texture(dirt_tex, UV * 3.7).r;
	float n2 = texture(dirt_tex, UV * 9.1).g;
	float wear = (n1 - 0.5) * 0.45 + (n2 - 0.5) * 0.25;
	float mask = smoothstep(0.0, feather, edge + wear);

	ALBEDO = mix(grass, dirt, mask);
	ALPHA = 1.0;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
