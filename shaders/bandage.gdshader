shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;
// Curativo adesivo: fita bege perfurada com tecido + almofada de gaze no meio,
// segue a curva da pele e "desenrola" ao ser aplicado.
#include "res://shaders/noise.gdshaderinc"
#include "res://shaders/deform.gdshaderinc"

uniform float aspect = 0.38;     // meia-largura em UV (comprimento = 1)
uniform float unroll = 1.0;      // 0..1 aplicando de uma ponta à outra
uniform float stain = 0.0;       // sangue/pus atravessando a gaze
uniform vec3 stain_col : source_color = vec3(0.6, 0.08, 0.1);
uniform float rot = 0.0;
uniform float half_size = 0.1;
uniform float sss_amount = 0.15;
uniform vec3 sss_color : source_color = vec3(1.0, 0.8, 0.6);

varying vec3 wn;

float shape(vec2 uv) {
	float hw = aspect;
	float dx = max(abs(uv.x) - (1.0 - hw), 0.0);
	return length(vec2(dx, uv.y)) - hw;      // < 0 dentro
}

float hgt(vec2 uv) {
	float pad = (1.0 - smoothstep(0.55, 0.59, abs(uv.x))) * (1.0 - smoothstep(aspect * 0.78, aspect * 0.84, abs(uv.y)));
	return pad * 0.6 + smoothstep(0.0, -0.05, shape(uv)) * 0.2;
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX += skin_deform(w);
	wn = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec2 uv = UV;
	float d = shape(uv);
	if (d > 0.0 || uv.x > -1.0 + 2.0 * unroll || COLOR.a < 0.5) {
		discard;
	}
	// fita adesiva: tecido bege com trama e furinhos
	vec3 tape = vec3(0.9, 0.72, 0.56);
	vec2 g = uv * vec2(55.0, 55.0);
	float weave = 0.5 + 0.25 * sin(g.x * 6.28) + 0.25 * sin(g.y * 6.28);
	tape *= 0.9 + 0.1 * weave;
	vec2 hp = fract(uv * vec2(9.0, 9.0)) - 0.5;
	float hole = 1.0 - smoothstep(0.06, 0.1, length(hp));
	tape = mix(tape, tape * 0.7, hole * 0.8);
	// gaze no meio
	float pad = (1.0 - smoothstep(0.55, 0.57, abs(uv.x))) * (1.0 - smoothstep(aspect * 0.78, aspect * 0.81, abs(uv.y)));
	vec2 pg = uv * vec2(70.0, 70.0);
	float gauze = 0.85 + 0.15 * max(abs(sin(pg.x * 3.14)), abs(sin(pg.y * 3.14)));
	vec3 padc = vec3(0.98, 0.96, 0.95) * gauze;
	float st = stain * (1.0 - smoothstep(0.0, 0.42 + fbm(uv * 4.0) * 0.12, length(uv * vec2(1.0, 1.0 / max(aspect, 0.3)))));
	padc = mix(padc, stain_col, st * 0.7);
	vec3 col = mix(tape, padc, pad);
	// borda mais escura (onde a fita encosta)
	col *= 0.82 + 0.18 * smoothstep(0.0, -0.05, d);
	// relevo da almofada
	float e = 0.01;
	float h0 = hgt(uv);
	float du = (hgt(uv + vec2(e, 0.0)) - h0) / e;
	float dv = (hgt(uv + vec2(0.0, e)) - h0) / e;
	float c = cos(rot);
	float s = sin(rot);
	vec2 gr = vec2(du * c - dv * s, du * s + dv * c) / max(half_size, 0.001);
	vec3 n = normalize(wn - vec3(gr.x, 0.0, gr.y) * 0.006);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ALBEDO = col;
	ALPHA = 1.0;
	ROUGHNESS = mix(0.75, 0.95, pad);
}

#include "res://shaders/lighting.gdshaderinc"
