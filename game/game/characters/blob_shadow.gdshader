shader_type spatial;
// Uniform blob shadow for actors. The sprite packs ship without a baked shadow
// ("with shadows" variants are intentionally not used), so every character gets
// the same soft oval from the engine and nobody's feet look pasted on.
//
// Unshaded on purpose: a shadow must not be re-lit by the sun, or the oval goes
// bright at noon and disappears at dusk.
render_mode blend_mix, depth_draw_never, cull_disabled, specular_disabled, shadows_disabled, unshaded;

uniform vec4 shadow_color : source_color = vec4(0.055, 0.06, 0.05, 0.46);
uniform float softness : hint_range(0.05, 0.95) = 0.55;
uniform float core : hint_range(0.0, 1.0) = 0.25;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	// two stops: a dense core under the feet, then a long feathered falloff
	float a = 1.0 - smoothstep(1.0 - softness, 1.0, d);
	a *= mix(0.72, 1.0, 1.0 - smoothstep(0.0, core, d));
	ALBEDO = shadow_color.rgb;
	ALPHA = shadow_color.a * a;
}
