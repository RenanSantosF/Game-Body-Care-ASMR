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
uniform float hematoma = 0.0;
// corte progressivo do alicate: sulco na linha groove_at, avançando de um lado (groove_dir) até groove_prog
uniform float groove_at = 9.0;
uniform float groove_prog = 0.0;
uniform float groove_dir = 1.0;
uniform float lift_amt = 0.0;
uniform float use_mask = 0.0;
uniform sampler2D mask : filter_linear, repeat_disable;
uniform float seed = 0.0;
uniform float sss_amount = 0.4;
uniform vec3 sss_color : source_color = vec3(1.0, 0.5, 0.5);

float cut_front(float u) {
	float f = groove_dir > 0.0 ? (-1.0 + 2.2 * groove_prog) - u : u - (1.0 - 2.2 * groove_prog);
	return smoothstep(-0.05, 0.25, f);
}

void vertex() {
	// a parte já cortada da ponta levanta um pouquinho (unha cortada "solta")
	if (UV.y > groove_at) {
		VERTEX.y += (UV.y - groove_at) * lift_amt * cut_front(UV.x) * groove_prog;
	}
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
	col = mix(col, vec3(0.3, 0.2, 0.1), d * smoothstep(0.6, 0.72, vnoise(vec2(u * 9.0, v * 16.0) + seed)) * 0.75);
	float f = fungus * (1.0 - m);
	float fn = fbm(vec2(u * 3.0, v * 5.0) + seed);
	col = mix(col, mix(vec3(0.8, 0.62, 0.22), vec3(0.62, 0.48, 0.2), fn), f * smoothstep(0.2, 0.55, fn + 0.2));
	float hem = hematoma * (1.0 - smoothstep(0.3, 0.75, length(vec2(u * 0.8, (v - 0.5) * 1.1)) + (fbm(vec2(u, v) * 3.0 + seed) - 0.5) * 0.3));
	col = mix(col, mix(vec3(0.16, 0.02, 0.07), vec3(0.32, 0.06, 0.18), fbm(vec2(u, v) * 6.0)), hem);
	// sulco do corte (fresta escura com borda clara) e rachadura fina à frente
	float gd = abs(v - groove_at);
	float cf = cut_front(u);
	col = mix(col, vec3(0.12, 0.05, 0.05), (1.0 - smoothstep(0.012, 0.028, gd)) * cf);
	col = mix(col, vec3(1.0, 0.98, 0.94), smoothstep(0.028, 0.036, gd) * (1.0 - smoothstep(0.036, 0.05, gd)) * cf * 0.9);
	float ahead = (1.0 - cf) * smoothstep(0.6, 1.0, 1.0 - abs(u - (groove_dir > 0.0 ? -1.0 + 2.2 * groove_prog : 1.0 - 2.2 * groove_prog)) * 4.0);
	col = mix(col, vec3(0.6, 0.45, 0.4), (1.0 - smoothstep(0.0, 0.006, gd)) * ahead * step(0.01, groove_prog));
	// borda recém-cortada: branca e áspera
	if (cut_at < 5.0) {
		float rim = smoothstep(cut_at - 0.06, cut_at, v);
		col = mix(col, vec3(0.97, 0.95, 0.9) * (0.9 + 0.1 * h21(floor(vec2(u * 60.0, v * 8.0)))), rim * 0.85);
	}
	float stripe = (1.0 - smoothstep(0.05, 0.25, abs(u + 0.35))) * 0.25;
	ALBEDO = col + stripe * (1.0 - f);
	ROUGHNESS = mix(0.12, 0.75, max(f, d * 0.6));
}

#include "res://shaders/lighting.gdshaderinc"
