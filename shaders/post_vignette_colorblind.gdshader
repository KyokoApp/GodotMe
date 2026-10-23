shader_type canvas_item;

uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.38;
uniform int colorblind_mode : hint_range(0, 3) = 0; // 0=Off, 1=Protanopia, 2=Deuteranopia, 3=Tritanopia
uniform vec4 region_grade : source_color = vec4(0.96, 0.93, 0.88, 1.0);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec3 col = tex.rgb * region_grade.rgb;

	// Colorblind accessibility matrices
	if (colorblind_mode == 1) {
		// Protanopia safe shift
		col = vec3(
			dot(col, vec3(0.56667, 0.43333, 0.0)),
			dot(col, vec3(0.55833, 0.44167, 0.0)),
			dot(col, vec3(0.0, 0.24167, 0.75833))
		);
	} else if (colorblind_mode == 2) {
		// Deuteranopia safe shift
		col = vec3(
			dot(col, vec3(0.625, 0.375, 0.0)),
			dot(col, vec3(0.70, 0.30, 0.0)),
			dot(col, vec3(0.0, 0.30, 0.70))
		);
	} else if (colorblind_mode == 3) {
		// Tritanopia safe shift
		col = vec3(
			dot(col, vec3(0.95, 0.05, 0.0)),
			dot(col, vec3(0.0, 0.43333, 0.56667)),
			dot(col, vec3(0.0, 0.475, 0.525))
		);
	}

	// Soft dusk vignette
	vec2 centered_uv = UV * (1.0 - UV.yx);
	float vig = centered_uv.x * centered_uv.y * 15.0;
	vig = clamp(pow(vig, vignette_intensity * 0.6), 0.0, 1.0);
	col *= mix(0.45, 1.0, vig);

	COLOR = vec4(col, tex.a);
}
