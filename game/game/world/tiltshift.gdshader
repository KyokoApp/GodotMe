shader_type canvas_item;
// Tilt-shift + vignette for the HD-2D look.
//
// The Compatibility renderer (what the launcher APK is compiled with) has no
// depth of field, so the "miniature" blur is done here, in screen space: sharp
// through a horizontal band around the focus line, progressively blurred away
// from it. Vertical-only blur is what makes it read as tilt-shift rather than
// as a soft lens.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float focus_line : hint_range(0.0, 1.0) = 0.54;
uniform float sharp_band : hint_range(0.0, 0.6) = 0.13;
uniform float blur_pixels : hint_range(0.0, 12.0) = 3.2;
uniform float vignette : hint_range(0.0, 1.5) = 0.34;
uniform vec3 warm_tint = vec3(1.02, 0.995, 0.94);

void fragment() {
	vec2 uv = SCREEN_UV;
	float dist = abs(uv.y - focus_line);
	float amount = smoothstep(sharp_band, sharp_band + 0.40, dist);
	vec2 step_px = vec2(0.0, amount * blur_pixels / 720.0);

	// 9-tap vertical blur; weights keep the sharp centre crisp
	vec3 col = texture(screen_tex, uv).rgb * 0.32;
	col += (texture(screen_tex, uv + step_px * 0.5).rgb
		+ texture(screen_tex, uv - step_px * 0.5).rgb) * 0.19;
	col += (texture(screen_tex, uv + step_px).rgb
		+ texture(screen_tex, uv - step_px).rgb) * 0.13;
	col += (texture(screen_tex, uv + step_px * 2.0).rgb
		+ texture(screen_tex, uv - step_px * 2.0).rgb) * 0.02;

	col *= warm_tint;
	vec2 c = uv - vec2(0.5);
	col *= 1.0 - vignette * dot(c, c) * 1.1;
	COLOR = vec4(col, 1.0);
}
