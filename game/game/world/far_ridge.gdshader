shader_type spatial;
// Distant ridge silhouettes for the HD-2D horizon.
//
// Step 3A lowered the camera to ~30 degrees, which means the sky is now part of
// the picture. A flat background colour read as a grey wall behind the hills, so
// the far hills are drawn as two concentric rings of jagged quads. Unshaded on
// purpose: they are atmosphere, not geometry, and the fog already mixes them into
// the sky. The gradient runs from the haze colour at the foot to the crest
// colour at the top, which is what makes a ridge read as far away instead of as a
// cardboard cut-out.
render_mode unshaded, cull_disabled, shadows_disabled;

uniform vec3 crest_color = vec3(0.42, 0.46, 0.52);
uniform vec3 base_color = vec3(0.78, 0.76, 0.72);
// how quickly the crest colour takes over: higher = thinner haze band
uniform float haze_power = 1.5;

void fragment() {
	float h = clamp(UV.y, 0.0, 1.0);
	ALBEDO = mix(base_color, crest_color, pow(h, haze_power));
}
