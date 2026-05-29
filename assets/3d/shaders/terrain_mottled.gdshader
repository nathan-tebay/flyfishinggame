shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 color_a : source_color = vec4(0.18, 0.29, 0.10, 1.0);
uniform vec4 color_b : source_color = vec4(0.30, 0.40, 0.16, 1.0);
uniform vec4 fleck_color : source_color = vec4(0.40, 0.34, 0.24, 1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness_texture : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ao_texture : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float patch_scale = 0.23;
uniform float fleck_amount = 0.10;
uniform float material_roughness = 0.94;
uniform float texture_scale = 0.22;
uniform float texture_amount = 0.78;

varying vec2 terrain_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	terrain_pos = VERTEX.xz;
}

void fragment() {
	float broad = value_noise(terrain_pos * patch_scale);
	float fine = value_noise(terrain_pos * patch_scale * 7.0);
	float fleck = smoothstep(1.0 - fleck_amount, 1.0, fine);
	vec3 base = mix(color_a.rgb, color_b.rgb, broad);
	vec2 tex_uv = terrain_pos * texture_scale;
	vec3 detail = texture(albedo_texture, tex_uv).rgb;
	detail *= mix(color_a.rgb, color_b.rgb, 0.5) / max(vec3(0.22), vec3(dot(detail, vec3(0.333))));
	base = mix(base, detail, texture_amount);
	ALBEDO = mix(base, fleck_color.rgb, fleck * 0.18);
	NORMAL_MAP = texture(normal_texture, tex_uv).rgb;
	NORMAL_MAP_DEPTH = 0.56;
	ROUGHNESS = mix(texture(roughness_texture, tex_uv).r, material_roughness, 0.34);
	AO = texture(ao_texture, tex_uv).r;
	SPECULAR = 0.16;
}
