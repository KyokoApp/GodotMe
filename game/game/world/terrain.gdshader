// Ground for REGION "Yaros": one atlas, four samples, blended by vertex colour.
//
// Why blend instead of one texture per tile: a 192x192 region drawn one texture
// per tile shows 36 864 little squares and a grid of seams. Blending the grass,
// dirt, rock and sand cells of one atlas under a continuous world-space UV makes
// the forest floor bleed into the path and the path into the rock, with no seam
// to see - and the whole chunk is still ONE draw call, because the atlas is
// bound once.
//
//   COLOR.r = dirt   COLOR.g = rock   COLOR.b = sand   COLOR.a = snow
//   UV2.x   = shade  (tall grass darker, mud browner)
//   UV      = world XZ in metres, so `fract(uv / 2.0)` repeats per 2 m
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_disabled;

uniform sampler2D atlas : source_color, filter_nearest, repeat_enable;
uniform float tile_scale = 2.0;
// atlas cell origins in a 4x2 sheet (see tools/gen_region_tiles.py)
uniform vec2 cell_grass = vec2(0.0, 0.0);
uniform vec2 cell_dirt = vec2(0.25, 0.0);
uniform vec2 cell_sand = vec2(0.5, 0.0);
uniform vec2 cell_cliff = vec2(0.75, 0.0);
uniform vec2 cell_snow = vec2(0.0, 0.5);
uniform vec3 snow_tint : source_color = vec3(0.93, 0.95, 0.97);
uniform vec3 light_tint : source_color = vec3(1.0, 1.0, 1.0);

vec3 sample_cell(vec2 origin, vec2 uv) {
	// v grows downwards in the atlas, uv grows upwards in the world
	vec2 local = fract(uv);
	return texture(atlas, origin + vec2(local.x, local.y) * vec2(0.25, 0.5)).rgb;
}

void fragment() {
	vec2 uv = UV / tile_scale;
	vec3 grass = sample_cell(cell_grass, uv);
	vec3 dirt = sample_cell(cell_dirt, uv);
	vec3 rock = sample_cell(cell_cliff, uv);
	vec3 sand = sample_cell(cell_sand, uv);
	vec3 snow = sample_cell(cell_snow, uv);

	// sequential mixes keep the arithmetic to four lerps; the weights sum to at
	// most one per vertex, so nothing clips
	vec3 c = grass;
	c = mix(c, dirt, COLOR.r);
	c = mix(c, rock, COLOR.g);
	c = mix(c, sand, COLOR.b);
	c = mix(c, snow * snow_tint, COLOR.a);
	// A terraced region is mostly in its own shadow at every sun angle, so the
	// ground gets a small standing bounce of its own instead of going black in
	// the lee of every wall.
	c *= UV2.x;
	ALBEDO = c * light_tint;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
