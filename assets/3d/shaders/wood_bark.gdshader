shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 bark_dark : source_color = vec4(0.18, 0.12, 0.075, 1.0);
uniform vec4 bark_light : source_color = vec4(0.42, 0.30, 0.19, 1.0);
uniform float weathered = 0.28;

varying vec3 bark_pos;

void vertex() {
	bark_pos = VERTEX;
}

void fragment() {
	float grain = sin(bark_pos.y * 34.0 + sin(bark_pos.x * 18.0) * 1.7 + sin(bark_pos.z * 23.0)) * 0.5 + 0.5;
	float cracks = smoothstep(0.77, 0.97, grain);
	vec3 bark = mix(bark_dark.rgb, bark_light.rgb, grain * 0.70);
	bark = mix(bark, vec3(0.54, 0.48, 0.40), weathered * (1.0 - cracks));
	bark *= mix(1.0, 0.68, cracks);
	ALBEDO = bark;
	ROUGHNESS = 0.93;
	SPECULAR = 0.12;
}
