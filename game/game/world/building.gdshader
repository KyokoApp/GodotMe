// Buildings for REGION "Yaros" (step 3B): low-poly meshes with pixel textures.
//
// One atlas, one material per BUILDING (not per face), so a house with a stone
// foundation, plaster walls, six windows, a shingled roof and a chimney is one
// draw call. That is the whole reason the UV contract below is unusual:
//
//   UV   = texture repeats (metres / tile size, or 0..1 for a single-cell decal)
//   UV2  = the atlas cell's origin (u0, v0)
//   COLOR.rgb = tint (white in the mesh; MultiMesh carries the per-house shade)
//   COLOR.a   = detail class: 1.0 lit (window, flame), 0.4 small detail
//               (door, sign, iron band), 0.0 structure - it is NOT transparency
//
// Every cell is 128 px in a 512 px atlas, so the cell size is a constant - no
// uniform array of cell rects, no dynamic indexing, nothing the Compatibility
// renderer might not support on a phone.
//
// cull_disabled is not laziness: the kit's quads are wound for their outward
// normal (counter-clockwise seen from outside), which is Godot's BACK face, and
// several parts - a gate leaf, a banner, a sign board - are a single plane that
// has to be visible from behind as well. Fixing the winding would still leave
// the decals one-sided.
//
// Two more things happen here, both needed by the step-3A camera:
//   * dither fade, so a cottage standing between the lens and the knight
//     dissolves in a pixel pattern instead of hiding him;
//   * a warm emission on the glow pixels that follows the day phase, so the
//     windows light up at dusk without a second material per building.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_disabled;

// No `source_color`: the world loads its PNGs as raw bytes (see RegionView._tex),
// so the shader samples them as stored. The hint made grass arrive almost black
// in step 2 and turned the whole valley brown.
uniform sampler2D atlas : filter_nearest, repeat_enable;
uniform float cell_size = 0.25;
uniform vec3 light_tint = vec3(1.0, 1.0, 1.0);
// the texture is sampled as stored (see the note about sRGB above), so this is
// where the palette is lifted to sit next to the unshaded billboards and the
// terrain. 1.0 = the texture's own colour, lit by the sun and the ambient.
uniform float albedo_gain = 1.0;
// occlusion: 1 = solid, 0 = fully dithered away
uniform float fade : hint_range(0.0, 1.0) = 1.0;
// when 1, the fade comes from the instance's custom data (r) instead, so each
// house in one MultiMesh can dissolve on its own when the camera passes it
uniform float instance_fade = 0.0;
// small details (doors, signs, iron bands) are dropped past this range: at a
// hundred metres they are smaller than a pixel and only cost fill rate
uniform float detail_range = 120.0;
// 0 = day, 1 = deep night: the windows and the torch flames
uniform float night : hint_range(0.0, 1.0) = 0.0;
// the atlas origin of the flame cell. The torch's quads are the only ones that
// animate, and they animate through the four frames packed into their own cell,
// so the shader recognises them by their cell instead of needing a second
// material and a second draw call for one torch.
uniform vec2 flame_cell = vec2(-1.0, -1.0);

varying vec2 tex_uv;
varying vec2 cell_origin;
varying float v_glow;
varying float v_fade;
varying float v_small;

void vertex() {
	tex_uv = UV;
	cell_origin = UV2;
	// COLOR.a is a detail class, not transparency: 1.0 = lit (windows, flames),
	// 0.4 = a small detail (a door, a sign, an iron band), 0.0 = structure.
	v_glow = smoothstep(0.9, 1.0, COLOR.a);
	v_small = (COLOR.a > 0.05 && COLOR.a < 0.9) ? 1.0 : 0.0;
	// the fade is a uniform for a stand-alone mesh and the instance's own custom
	// data inside a MultiMesh, where one buffer holds the whole village
	v_fade = mix(fade, INSTANCE_CUSTOM.r, instance_fade);
}

void fragment() {
	// distance limit first: a fragment that is too far is not worth a sample.
	// Measured in VIEW space, so no camera uniform is needed and it works the
	// same inside a MultiMesh. The small details (a door, a sign, an iron band)
	// go first - at a hundred metres they are smaller than a pixel.
	float dist = length(VERTEX);
	if (dist > detail_range * 2.6 || (v_small > 0.5 && dist > detail_range)) {
		discard;
	}

	vec2 local = fract(tex_uv);
	// a flame cell holds four frames side by side; the quad is mapped to the
	// first quarter of the cell and this slides it across
	bool flame = flame_cell.x >= 0.0 && distance(cell_origin, flame_cell) < 0.002;
	if (flame) {
		local.x = local.x * 0.25 + 0.25 * float(int(TIME * 7.0) % 4);
	}
	vec4 tex = texture(atlas, cell_origin + local * cell_size);

	// the decal cells (a window, a door, a banner, a flame) are painted on an
	// empty cell: without a scissor their transparent corners would be drawn as
	// a black rectangle on the wall
	if (tex.a < 0.42) {
		discard;
	}

	// 8x8 ordered dither, checked in screen pixels: readable at phone DPI and
	// stable while walking, unlike noise
	ivec2 p = ivec2(FRAGCOORD.xy);
	float threshold = float((p.x * 3 + p.y * 5) % 8) / 8.0 + 0.0625;
	if (threshold > v_fade) {
		discard;
	}

	vec3 base = tex.rgb * COLOR.rgb * light_tint * albedo_gain;
	// A pane of glass in daylight is a dark, cool hole in the wall - not a lamp.
	// The first capture of step 3B showed every window on the village as a
	// bright yellow lamp at noon, because the cell is painted warm and only the
	// EMISSION was being faded. The ALBEDO has to go dark as well.
	if (v_glow > 0.5 && !flame) {
		// scale the cell down and cool it instead of replacing it: the oak frame
		// has to stay visible, or every window is a black rectangle
		vec3 daylight = tex.rgb * vec3(0.16, 0.19, 0.26);
		base = mix(daylight, base, clamp(night * 1.6, 0.0, 1.0));
	}
	ALBEDO = base;
	// windows: dark at noon, clearly lit at night; the flame is always hot
	float warm = v_glow * (0.02 + 1.05 * night);
	if (flame) {
		warm = 1.0;
	}
	EMISSION = tex.rgb * warm * 1.6;
	ROUGHNESS = 0.9;
}
