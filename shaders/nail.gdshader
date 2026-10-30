shader_type spatial;
render_mode depth_draw_always;
// Unha: lúnula, borda livre, sujeira, micose, corte
#include "res://shaders/noise.gdshaderinc"
#include "res://shaders/deform.gdshaderinc"

uniform vec3 pink : source_color = vec3(0.96, 0.66, 0.68);
uniform float dirt = 0.0;
uniform float fungus = 0.0;
uniform float cut_at = 9.0;
uniform float keep_from = -1.0;
uniform float use_mask = 0.0;
uniform sampler2D mask : filter_linear, repeat_disable;
uniform float seed = 0.0;
uniform float sss_amount = 0.4;
uniform vec3 sss_color : source_color = vec3(1.0, 0.5, 0.5);

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * skin_deform(w);
}

void fragment() {
	float u = UV.x;
	float v = UV.y;
	if (v > cut_at || v < keep_from) {
		discard;
	}
	float m = use_mask > 0.5 ? texture(mask, vec2(u * 0.5 + 0.5, clamp(v / 1.6, 0.0, 1.0))).r : 0.0;
	vec3 col = pink;
	// contorno e cutícula
	float edge = smoothstep(0.78, 1.0, abs(u));
	col = mix(col, pink * 0.72, edge);
	col = mix(col * 0.8, col, smoothstep(0.0, 0.07, v));
	float lun = 1.0 - smoothstep(0.12, 0.2, length(vec2(u * 0.35, v - 0.02)));
	col = mix(col, vec3(1.0, 0.94, 0.92), lun * 0.8);
	col = mix(col, vec3(1.0, 0.97, 0.92), smoothstep(0.82, 0.9, v) * (1.0 - edge * 0.5));
	col = mix(col, vec3(0.97, 0.92, 0.75), smoothstep(1.0, 1.4, v));
	float d = dirt * (1.0 - m);
	float under = smoothstep(0.78, 0.9, v) * (0.6 + 0.4 * fbm(vec2(u * 4.0, v * 6.0) + seed));
	col = mix(col, vec3(0.2, 0.12, 0.06), d * under);
	col = mix(col, vec3(0.75, 0.62, 0.35), d * smoothstep(1.0, 1.3, v) * 0.6);
	col = mix(col, vec3(0.35, 0.24, 0.13), d * step(0.83, h21(floor(vec2(u, v) * 22.0) + seed)) * 0.8);
	float f = fungus * (1.0 - m);
	float fn = fbm(vec2(u * 3.0, v * 5.0) + seed);
	col = mix(col, mix(vec3(0.8, 0.62, 0.22), vec3(0.62, 0.48, 0.2), fn), f * smoothstep(0.2, 0.55, fn + 0.2));
	float stripe = (1.0 - smoothstep(0.05, 0.25, abs(u + 0.35))) * 0.25;
	ALBEDO = col + stripe * (1.0 - f);
	ROUGHNESS = mix(0.12, 0.75, max(f, d * 0.6));
}

#include "res://shaders/lighting.gdshaderinc"
