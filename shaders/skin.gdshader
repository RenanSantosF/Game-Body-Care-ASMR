shader_type spatial;
// Pele realista estilizada:
//  - luz com espalhamento subsuperficial (lighting.gdshaderinc)
//  - microrrelevo procedural (poros, rugas finas) virando normal
//  - manchas, vermelhidão nas dobras, veias suaves
//  - deformação sob a ferramenta (deform.gdshaderinc)
//  - pintura dinâmica (respingos) com volume e brilho molhado
#include "res://shaders/noise.gdshaderinc"
#include "res://shaders/deform.gdshaderinc"

uniform vec3 skin : source_color = vec3(0.96, 0.76, 0.62);
uniform vec3 skin_deep : source_color = vec3(0.82, 0.42, 0.38);
uniform float sss_amount = 0.55;
uniform vec3 sss_color : source_color = vec3(0.95, 0.3, 0.2);
uniform sampler2D paint : source_color, filter_linear, repeat_disable;
uniform vec4 paint_rect = vec4(-3.0, -1.5, 6.0, 3.0);
uniform vec2 paint_texel = vec2(0.0005, 0.001);

varying vec3 wp;
varying vec3 wn;
varying float vao;

float detail(vec2 p) {
	// poros: pontinhos afundados
	vec2 vr = voronoi(p * 160.0);
	float pores = (1.0 - smoothstep(0.0, 0.22, vr.x)) * 0.55;
	// rugas finas cruzadas
	float w1 = abs(sin(dot(p, vec2(0.8, 0.6)) * 260.0 + vnoise(p * 30.0) * 6.0));
	float w2 = abs(sin(dot(p, vec2(-0.5, 0.86)) * 210.0 + vnoise(p * 25.0 + 7.0) * 6.0));
	float wr = (1.0 - smoothstep(0.0, 0.18, w1)) * 0.25 + (1.0 - smoothstep(0.0, 0.15, w2)) * 0.18;
	float fine = vnoise(p * 70.0) * 0.25;
	return fine - pores - wr * vnoise(p * 6.0);
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 d0 = skin_deform(w);
	float e = 0.004;
	vec3 dx = skin_deform(w + vec3(e, 0.0, 0.0));
	vec3 dz = skin_deform(w + vec3(0.0, 0.0, e));
	VERTEX += d0;
	vec3 n = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	n = normalize(n - vec3((dx.y - d0.y) / e, 0.0, (dz.y - d0.y) / e) * n.y);
	wn = n;
	wp = w + d0;
	vao = COLOR.r;
}

void fragment() {
	vec2 p = wp.xz;
	// cor: manchas suaves + vermelhidão nas dobras + veias
	float mott = fbm(p * 3.0);
	vec3 c = skin * (0.93 + mott * 0.12);
	c = mix(c, c * vec3(1.04, 0.92, 0.9), smoothstep(0.55, 0.8, fbm(p * 6.0 + 3.0)) * 0.5);
	float vein = 1.0 - smoothstep(0.0, 0.06, abs(fbm(p * vec2(0.8, 1.9) + vec2(4.0, 1.0)) - 0.5));
	c = mix(c, c * vec3(0.88, 0.92, 1.05), vein * 0.1 * smoothstep(0.6, 0.95, vao));
	c = mix(skin_deep, c, smoothstep(0.3, 0.95, vao));
	c *= mix(0.55, 1.0, smoothstep(0.15, 0.9, vao));

	// relevo de detalhe -> normal
	float e = 0.0015;
	float h0 = detail(p);
	float hx = detail(p + vec2(e, 0.0));
	float hz = detail(p + vec2(0.0, e));
	vec3 n = normalize(wn - vec3((hx - h0) / e, 0.0, (hz - h0) / e) * 0.00045);
	c *= 0.96 + 0.06 * h0;

	// respingos (sangue/pus) pintados na pele
	vec2 uv = (wp.xz - paint_rect.xy) / paint_rect.zw;
	vec4 pt = texture(paint, uv);
	float px = texture(paint, uv + vec2(paint_texel.x, 0.0)).a;
	float pz = texture(paint, uv + vec2(0.0, paint_texel.y)).a;
	n = normalize(n - vec3(px - pt.a, 0.0, pz - pt.a) * 2.5);
	c = mix(c, pt.rgb * (0.85 + 0.3 * pt.a), smoothstep(0.02, 0.5, pt.a));

	ALBEDO = c;
	ROUGHNESS = mix(0.62, 0.12, smoothstep(0.05, 0.4, pt.a));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}

#include "res://shaders/lighting.gdshaderinc"
