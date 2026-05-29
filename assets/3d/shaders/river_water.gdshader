shader_type spatial;
// Transparent water must not pre-write depth: the textured cobble bed is an
// intentional part of the visible shallow-water read.
render_mode blend_mix, cull_back, specular_schlick_ggx;

uniform vec4 shallow_color : source_color = vec4(0.075, 0.215, 0.215, 1.0);
uniform vec4 deep_color : source_color = vec4(0.010, 0.045, 0.058, 1.0);
uniform vec4 riffle_color : source_color = vec4(0.13, 0.30, 0.30, 1.0);
uniform vec4 foam_color : source_color = vec4(0.29, 0.42, 0.44, 1.0);
uniform sampler2D flow_streak_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D ripple_normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float wave_height = 0.020;
uniform float wave_speed = 1.45;
uniform float streak_scale = 1.0;
uniform float turbulence_strength = 0.42;
uniform float normal_strength = 0.48;
uniform int debug_view = 0;

varying vec4 flow_data;
varying vec2 surface_pos;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		value += noise2(p) * amplitude;
		p = p * 2.03 + vec2(17.3, 9.1);
		amplitude *= 0.5;
	}
	return value;
}

void vertex() {
	flow_data = COLOR;
	surface_pos = VERTEX.xz;
	float speed = clamp(COLOR.r, 0.0, 1.0);
	float depth = clamp(COLOR.g, 0.0, 1.0);
	float shallow = 1.0 - depth;
	float turbulence = clamp(COLOR.b, 0.0, 1.0);
	float curvature = clamp(COLOR.a, 0.0, 1.0);
	float phase = TIME * wave_speed * mix(0.45, 1.8, speed);
	float long_wave = sin(VERTEX.x * mix(0.18, 0.72, speed) - phase);
	float cross_wave = sin(VERTEX.z * mix(0.38, 1.05, shallow + 0.15) + VERTEX.x * 0.08 + phase * 0.54);
	float diagonal = sin((VERTEX.x * 0.46 + VERTEX.z * 0.32) - phase * 1.18);
	float boil = fbm(VERTEX.xz * 0.30 + vec2(-TIME * speed * 0.45, TIME * 0.12)) - 0.5;
	float chop = clamp(turbulence * 0.86 + shallow * 0.26 + curvature * 0.30, 0.0, 1.0);
	VERTEX.y += (long_wave * 0.30 + cross_wave * 0.22 + diagonal * 0.14 + boil * 0.62)
			* wave_height * mix(0.12, 1.0, chop) * turbulence_strength;
}

void fragment() {
	float speed = clamp(flow_data.r, 0.0, 1.0);
	float depth = clamp(flow_data.g, 0.0, 1.0);
	float shallow = 1.0 - depth;
	float turbulence = clamp(flow_data.b, 0.0, 1.0);
	float curvature = clamp(flow_data.a, 0.0, 1.0);

	vec2 streak_uv = vec2(surface_pos.x * 0.030 * streak_scale - TIME * mix(0.035, 0.18, speed),
			surface_pos.y * 0.115 + TIME * 0.018);
	vec2 streak_uv_fast = vec2(surface_pos.x * 0.055 + surface_pos.y * 0.012 - TIME * mix(0.12, 0.44, speed),
			surface_pos.y * 0.185 + TIME * 0.035);
	vec2 normal_uv = vec2(surface_pos.x * 0.105 - TIME * mix(0.045, 0.22, speed),
			surface_pos.y * 0.155 + TIME * 0.030);
	float long_streak = texture(flow_streak_texture, streak_uv).r;
	float fine_streak = texture(flow_streak_texture, streak_uv_fast).g;
	float broken_noise = fbm(streak_uv_fast * 3.1 + vec2(7.0, 2.0));
	float broad_boils = fbm(streak_uv * 2.2 + vec2(13.7, 2.4));
	float thread_mask = smoothstep(0.50, 0.88, long_streak + fine_streak * 0.18 + broken_noise * 0.08);
	float riffle_mask = smoothstep(0.58, 0.94, fine_streak * 0.38 + broken_noise * 0.36 + turbulence * 0.34);
	float foam_gate = smoothstep(0.72, 0.98, turbulence + broken_noise * 0.10 + fine_streak * 0.05);
	float foam = foam_gate * (0.18 + shallow * 0.82) * (thread_mask * 0.022 + riffle_mask * 0.035);
	foam = clamp(foam, 0.0, 0.055);

	vec3 water = mix(deep_color.rgb, shallow_color.rgb, shallow);
	float riffle_brightness = clamp((thread_mask * 0.12 + riffle_mask * 0.13 + broad_boils * 0.07)
			* turbulence * (0.18 + shallow * 0.82), 0.0, 0.18);
	water = mix(water, riffle_color.rgb, riffle_brightness);
	water += vec3(0.006, 0.014, 0.013) * (fine_streak - 0.5) * shallow * turbulence;
	water = mix(water, deep_color.rgb * 0.72, depth * depth * 0.32);

	float fresnel = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 3.0);
	water = mix(water, vec3(0.13, 0.22, 0.27), fresnel * 0.07);

	vec3 normal_tex = texture(ripple_normal_texture, normal_uv).rgb;
	float normal_amount = clamp(normal_strength * (0.20 + turbulence * 0.65 + shallow * 0.25), 0.0, 0.72);
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), normal_tex, normal_amount);
	NORMAL_MAP_DEPTH = mix(0.16, 0.54, normal_amount);

	ROUGHNESS = mix(0.46, 0.70, clamp(turbulence + foam * 2.0, 0.0, 1.0));
	SPECULAR = 0.20;
	EMISSION = vec3(0.0);

	vec3 final_albedo = mix(water, foam_color.rgb, foam * 0.42);
	float final_alpha = mix(0.40, 0.72, depth) + fresnel * 0.025;
	if (debug_view == 1) {
		final_albedo = mix(vec3(0.10, 0.56, 0.72), vec3(0.02, 0.025, 0.18), depth);
		final_alpha = 0.86;
	} else if (debug_view == 2) {
		final_albedo = mix(vec3(0.04, 0.10, 0.45), vec3(0.95, 0.44, 0.06), speed);
		final_alpha = 0.86;
	} else if (debug_view == 3) {
		final_albedo = vec3(foam * 8.0, turbulence, 0.10 + foam * 3.0);
		final_alpha = 0.86;
	} else if (debug_view == 4) {
		final_albedo = mix(vec3(0.06, 0.16, 0.48), vec3(0.96, 0.62, 0.08), curvature);
		final_alpha = 0.86;
	} else if (debug_view == 5) {
		final_albedo = vec3(thread_mask, normal_tex.r * 0.65 + 0.15, normal_tex.g * 0.55 + speed * 0.30);
		final_alpha = 0.86;
	}
	ALBEDO = final_albedo;
	ALPHA = final_alpha;
}
