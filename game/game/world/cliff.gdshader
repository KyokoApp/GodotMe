// Cliff faces. The rock cell of the terrain atlas, UVs in metres on both axes so
// the strata stay horizontal and the texture repeats every two metres instead of
// once per tile.
//
// Two effects, both for the same reason - a tiered world must never let a cliff
// hide the player:
//   * vertex colour alpha is a fake AO: 0.62 at the foot of the wall, 1.0 at the
//     lip, which gives the cliff weight without a light probe;
//   * a "window": fragments close to the player's ground position dissolve in an
//     8x8 dither. The knight standing right behind a two-level wall is still
//     visible through the rock instead of being swallowed by it.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_disabled;

uniform sampler2D atlas : source_color, filter_nearest, repeat_enable;
uniform vec2 cell_cliff = vec2(0.75, 0.0);
uniform float tile_scale = 2.0;
// world XZ of the player, set every frame by the world
uniform vec2 player_xz = vec2(-9999.0, -9999.0);
uniform float window_radius = 2.6;
uniform vec3 light_tint : source_color = vec3(1.0, 1.0, 1.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 local = fract(UV / tile_scale);
	vec3 rock = texture(atlas, cell_cliff + vec2(local.x, local.y) * vec2(0.25, 0.5)).rgb;
	// moss creeps up from the foot of the wall
	float moss = smoothstep(0.55, 0.0, COLOR.a) * smoothstep(0.5, 0.9, rock.g);
	rock = mix(rock, rock * vec3(0.78, 0.92, 0.66), moss * 0.5);

	float d = distance(world_pos.xz, player_xz);
	if (d < window_radius) {
		ivec2 p = ivec2(FRAGCOORD.xy);
		float threshold = float((p.x * 5 + p.y * 3) % 8) / 8.0 + 0.0625;
		float keep = mix(0.0, 1.0, smoothstep(window_radius * 0.35, window_radius, d));
		if (threshold > keep) {
			discard;
		}
	}
	ALBEDO = rock * COLOR.a * light_tint;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
