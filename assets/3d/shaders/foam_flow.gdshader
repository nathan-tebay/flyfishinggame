shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled;

uniform vec4 foam_color : source_color = vec4(0.82, 0.92, 0.93, 0.34);
uniform float pulse_speed = 2.3;
uniform float streak_scale = 42.0;

varying float foam_alpha;

void vertex() {
	foam_alpha = max(COLOR.a, 0.18);
	VERTEX.y += sin(VERTEX.x * 2.7 + VERTEX.z * 1.3 + TIME * pulse_speed) * 0.006;
}

void fragment() {
	float streak = sin((UV.x - TIME * 0.23) * streak_scale + UV.y * 8.0) * 0.5 + 0.5;
	ALBEDO = foam_color.rgb;
	EMISSION = foam_color.rgb * 0.06;
	ALPHA = foam_color.a * foam_alpha * mix(0.55, 1.0, streak);
}
