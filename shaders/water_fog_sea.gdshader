shader_type spatial;
render_mode blend_mix, depth_draw_opaque, unshaded;

// Sea of Fog ("Selimut") & Harbor water shader with gentle ripples and foam
uniform vec4 shallow_color : source_color = vec4(0.28, 0.38, 0.44, 1.0);
uniform vec4 deep_fog_color : source_color = vec4(0.14, 0.16, 0.22, 1.0);
uniform vec4 foam_color : source_color = vec4(0.76, 0.78, 0.74, 1.0);
uniform float wave_speed : hint_range(0.1, 3.0) = 0.8;
uniform float weather_turbulence : hint_range(0.0, 2.0) = 0.3;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float wave = sin(world_pos.x * 0.7 + TIME * wave_speed) * cos(world_pos.z * 0.6 + TIME * wave_speed * 0.8);
	VERTEX.y += wave * (0.08 + weather_turbulence * 0.12);
}

void fragment() {
	float pattern = sin(world_pos.x * 1.8 + TIME * wave_speed) * cos(world_pos.z * 1.8 - TIME * wave_speed * 0.7);
	float quantized = floor((pattern * 0.5 + 0.5) * 3.0) / 3.0;
	vec3 col = mix(deep_fog_color.rgb, shallow_color.rgb, quantized);
	if (pattern > 0.78) {
		col = mix(col, foam_color.rgb, 0.65);
	}
	ALBEDO = col;
}
