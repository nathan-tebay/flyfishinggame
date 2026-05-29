shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

uniform vec4 blade_color : source_color = vec4(0.025, 0.105, 0.045, 1.0);
uniform float sway_speed = 0.85;
uniform float sway_amount = 0.026;

varying float tip_height;

void vertex() {
	tip_height = clamp(UV.y, 0.0, 1.0);
	float sway = sin(TIME * sway_speed + VERTEX.x * 1.7 + VERTEX.z * 2.3);
	VERTEX.x += sway * sway_amount * tip_height;
	VERTEX.z += sin(TIME * 0.7 + VERTEX.x) * sway_amount * tip_height * 0.24;
}

void fragment() {
	ALBEDO = blade_color.rgb * mix(0.72, 1.0, tip_height);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
