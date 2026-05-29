shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 gravel_color : source_color = vec4(0.38, 0.34, 0.26, 1.0);
uniform vec4 cobble_color : source_color = vec4(0.25, 0.29, 0.25, 1.0);
uniform vec4 deep_color : source_color = vec4(0.035, 0.10, 0.095, 1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness_texture : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ao_texture : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float texture_scale = 0.17;

varying vec4 habitat;
varying vec2 bed_pos;

void vertex() {
	habitat = COLOR;
	bed_pos = VERTEX.xz;
}

void fragment() {
	float depth = clamp(habitat.r, 0.0, 1.0);
	float gravel = clamp(habitat.g, 0.0, 1.0);
	vec2 tex_uv = bed_pos * texture_scale;
	vec3 photo_substrate = texture(albedo_texture, tex_uv).rgb;
	vec3 substrate = mix(cobble_color.rgb, gravel_color.rgb, gravel);
	photo_substrate *= substrate / max(vec3(0.20), vec3(dot(photo_substrate, vec3(0.333))));
	substrate = mix(substrate, photo_substrate, 0.88);
	substrate = mix(substrate, deep_color.rgb, depth * 0.46);
	ALBEDO = substrate;
	NORMAL_MAP = texture(normal_texture, tex_uv).rgb;
	NORMAL_MAP_DEPTH = 0.74;
	ROUGHNESS = mix(texture(roughness_texture, tex_uv).r, 0.64, depth * 0.45);
	AO = texture(ao_texture, tex_uv).r;
	SPECULAR = 0.26;
}
