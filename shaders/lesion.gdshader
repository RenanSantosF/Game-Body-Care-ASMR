shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;
// Lesões em remendos colados na pele (UV -1..1).
// Cada tipo define cor e um campo de altura; a normal vem do gradiente da altura,
// dando volume real (inchaço, crateras, crostas, cortes com bordas).
// fx (RGBA): R = limpo, G = sangue acumulado, B = livre, A = profundidade do corte
#include "res://shaders/noise.gdshaderinc"
#include "res://shaders/deform.gdshaderinc"

uniform int kind = 0;
uniform vec3 skin : source_color = vec3(0.95, 0.75, 0.6);
uniform float seed = 0.0;
uniform float heal = 0.0;
uniform float strength = 1.0;
uniform float use_mask = 0.0;
uniform sampler2D mask : filter_linear, repeat_disable;
uniform sampler2D fx : filter_linear, repeat_disable;
uniform sampler2D fxw : filter_linear, repeat_disable;
uniform float use_fx = 0.0;
uniform float open_amt = 0.0;
uniform float wet = 0.0;
uniform float scar = 0.0;      // corte cicatrizando (casquinha)
uniform float pore = 0.0;
uniform vec3 tint : source_color = vec3(1.0);      // marca de poro (espinha) no meio da cicatriz
uniform float rot = 0.0;
uniform float half_size = 0.1;
uniform float sss_amount = 0.5;
uniform vec3 sss_color : source_color = vec3(0.9, 0.2, 0.15);

const int INFLAM = 0;
const int DIRT = 1;
const int PUS = 2;
const int BLOOD = 3;
const int FAVO = 4;
const int WOUND = 5;
const int CALLUS = 6;
const int CRUST = 7;
const int BRUISE = 8;
const int CUT = 9;
const int TRACK = 10;
const int FLUID = 11;
const int OILY = 12;
const int SCRAPE = 13;
const int SCAR = 14;
const int STUBBLE = 15;
const int CREAM = 16;

varying vec3 wn;

float blob(vec2 uv, float s, float edge) {
	float n = fbm(uv * 2.4 + s);
	return 1.0 - smoothstep(edge - 0.3, edge, length(uv) + (n - 0.5) * 0.75);
}

uniform float fill = 0.0;          // preenche a máscara toda (pomada cobrindo tudo no fim)
float clean_m(vec2 uv) {
	return use_mask > 0.5 ? max(texture(mask, uv * 0.5 + 0.5).r, fill * (0.75 + 0.25 * fbm(uv * 3.0 + seed))) : 0.0;
}

vec4 fxs(vec2 uv) {
	if (use_fx < 0.5) {
		return vec4(0.0);
	}
	vec4 f = texture(fx, uv * 0.5 + 0.5);
	f.g *= 1.0 - texture(fxw, uv * 0.5 + 0.5).r;
	return f;
}

// abertura do corte a partir do canal A (já pintado macio)
float cut_open(float a) {
	return smoothstep(0.62 - open_amt * 0.4, 0.95, a);
}

float hfield(vec2 uv) {
	float r = length(uv);
	float h = 0.0;
	float m = clean_m(uv);
	if (kind == INFLAM) {
		h = (1.0 - smoothstep(0.0, 1.0, r)) * 0.55;
	} else if (kind == DIRT) {
		float sh = blob(uv, seed, 1.0);
		float clump = smoothstep(0.25, 0.75, sh * (0.5 + fbm(uv * 4.0 + seed * 1.7) * 0.8));
		vec2 gr = voronoi(uv * 26.0 + seed);
		float grain = (1.0 - smoothstep(0.0, 0.35, gr.x)) * step(0.55, h21(floor(uv * 26.0 + seed)));
		h = (clump * 0.35 + grain * 0.35 * smoothstep(0.1, 0.5, sh) + fbm(uv * 14.0) * 0.12 * clump) * (1.0 - m);
	} else if (kind == PUS || kind == BLOOD || kind == FLUID) {
		h = smoothstep(0.05, 0.6, blob(uv, seed, 0.95)) * 0.7 * (1.0 - m) + fbm(uv * 9.0) * 0.05;
	} else if (kind == FAVO) {
		float e = (fbm(uv * 2.0 + seed) - 0.5) * 0.4;
		float wound = 1.0 - smoothstep(0.6, 0.85, r + e);
		vec2 vr = voronoi(uv * 5.5 + seed);
		float hole = (1.0 - smoothstep(0.08, 0.2, vr.x)) * wound * (1.0 - heal);
		float rim = exp(-pow((r + e - 0.8) * 7.0, 2.0));
		h = -wound * 0.35 - hole * 0.9 + rim * 0.45 + fbm(uv * 12.0) * 0.12 * wound;
	} else if (kind == WOUND) {
		float e = (fbm(uv * 2.2 + seed) - 0.5) * 0.4;
		float w = 1.0 - smoothstep(0.4, 0.75, r + e);
		float rim = exp(-pow((r + e - 0.72) * 6.0, 2.0));
		h = -w * 0.7 * (1.0 - heal) + rim * 0.4 + fbm(uv * 14.0) * 0.15 * w;
	} else if (kind == CALLUS) {
		float e = (fbm(uv * 2.0 + seed) - 0.5) * 0.3;
		float a = 1.0 - smoothstep(0.6, 0.95, r + e);
		vec2 vr = voronoi(uv * 4.5 + seed);
		float crack = 1.0 - smoothstep(0.0, 0.06, vr.y);
		h = (a * 0.7 - crack * 0.35 * a + fbm(uv * 10.0) * 0.15 * a) * (1.0 - m * 0.95);
	} else if (kind == CRUST) {
		float e = (fbm(uv * 2.4 + seed) - 0.5) * 0.45;
		float a = 1.0 - smoothstep(0.5, 0.85, r + e);
		vec2 vr = voronoi(uv * 6.0 + seed);
		h = (a * (0.5 + fbm(uv * 8.0 + seed) * 0.5) - (1.0 - smoothstep(0.0, 0.06, vr.y)) * 0.3 * a) * (1.0 - m);
	} else if (kind == TRACK) {
		float y0 = sin(uv.x * 5.0 + seed) * 0.22;
		float d = abs(uv.y - y0);
		h = (1.0 - smoothstep(0.02, 0.2, d)) * 0.6 * (1.0 - smoothstep(0.8, 1.0, abs(uv.x)));
	} else if (kind == SCRAPE) {
		h = -(1.0 - smoothstep(0.3, 1.0, r)) * 0.2;
	} else if (kind == CREAM) {
		h = smoothstep(0.15, 0.8, m) * (0.45 + 0.3 * fbm(uv * 7.0 + seed)) * (1.0 - smoothstep(0.75, 1.0, r));
	}
	vec4 f = fxs(uv);
	float co = cut_open(f.a);
	h += smoothstep(0.05, 0.5, f.a) * 0.25 * (1.0 - co);  // lábios levemente elevados
	h -= co * 1.3;                                          // fundo do corte
	h += smoothstep(0.08, 0.6, f.g) * 0.5;                  // sangue empoça por cima
	return h;
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX += skin_deform(w);
	wn = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec2 uv = UV;
	float r = length(uv);
	float m = clean_m(uv);
	vec4 f = fxs(uv);
	vec3 red = vec3(0.82, 0.24, 0.24);
	vec3 col = skin;
	float a = 0.0;
	float gloss = 0.0;
	float bump = 1.0;
	if (kind == INFLAM) {
		float e = (fbm(uv * 2.5 + seed) - 0.5) * 0.35;
		a = (1.0 - smoothstep(0.1, 1.0, r + e)) * 0.85;
		col = mix(skin, red, 0.6 + 0.25 * (1.0 - r));
		col = mix(col, col * vec3(0.95, 0.75, 0.8), smoothstep(0.4, 0.0, r) * 0.3);
		// pulsação quente da inflamação
		a *= 1.0 + 0.09 * sin(TIME * 2.3 + seed) * (1.0 - heal);
		gloss = 0.35;
	} else if (kind == DIRT) {
		float sh = blob(uv, seed, 1.0);
		float n = fbm(uv * 4.0 + seed * 1.7);
		float clump = smoothstep(0.2, 0.7, sh * (0.5 + n * 0.8));
		// terra úmida: marrom com variação + grãos redondos
		col = mix(vec3(0.2, 0.13, 0.07), vec3(0.42, 0.3, 0.17), fbm(uv * 7.0 + seed * 3.0));
		col = mix(col, vec3(0.3, 0.27, 0.12), smoothstep(0.55, 0.8, fbm(uv * 3.0 + 4.0)) * 0.35);
		vec2 gr = voronoi(uv * 26.0 + seed);
		float grain = (1.0 - smoothstep(0.0, 0.35, gr.x)) * step(0.55, h21(floor(uv * 26.0 + seed))) * smoothstep(0.1, 0.5, sh);
		col = mix(col, vec3(0.12, 0.08, 0.04) + 0.1 * h21(floor(uv * 26.0)), grain);
		// película fina nas bordas (poeira), grossa no meio
		a = max(clump, smoothstep(0.05, 0.4, sh) * 0.45);
		a = max(a, grain * 0.95) * 0.97;
		// sujeira borrada: limpo deixa um véu marrom que some
		a *= 1.0 - smoothstep(0.05, 0.95, m);
		gloss = 0.1;
	} else if (kind == PUS || kind == BLOOD || kind == FLUID) {
		float b = blob(uv, seed, 0.95);
		a = smoothstep(0.03, 0.3, b);
		float n = fbm(uv * 5.0 + seed);
		float thick = smoothstep(0.1, 0.8, b);
		if (kind == PUS) {
			col = mix(mix(skin, vec3(1.0, 0.94, 0.72) * tint, 0.6), vec3(0.86, 0.72, 0.36) * tint, thick);
			col = mix(col, vec3(0.72, 0.74, 0.4), smoothstep(0.6, 0.9, fbm(uv * 3.0 + 9.0)) * 0.3);
			col *= 0.9 + n * 0.15;
			a *= 0.6 + 0.35 * thick;
		} else if (kind == BLOOD) {
			col = mix(vec3(0.72, 0.1, 0.1), vec3(0.32, 0.01, 0.03), thick);
		} else {
			col = mix(skin * 1.05, vec3(1.0, 0.97, 0.88), 0.3);
			a *= 0.5;
		}
		a *= 1.0 - smoothstep(0.1, 0.9, m);
		gloss = 0.95;
	} else if (kind == FAVO) {
		float e = (fbm(uv * 2.0 + seed) - 0.5) * 0.4;
		float wound = 1.0 - smoothstep(0.6, 0.85, r + e);
		vec3 base = mix(vec3(0.5, 0.12, 0.08), vec3(0.78, 0.36, 0.24), fbm(uv * 6.0 + seed));
		vec2 vr = voronoi(uv * 5.5 + seed);
		float hole = (1.0 - smoothstep(0.08, 0.2, vr.x)) * smoothstep(0.0, 0.3, wound);
		base = mix(base, vec3(0.92, 0.8, 0.45), (1.0 - smoothstep(0.0, 0.07, vr.y)) * 0.4);
		base = mix(base, vec3(0.12, 0.01, 0.01), hole * (1.0 - heal));
		vec3 rim = mix(skin, red, 0.85);
		col = mix(rim, base, wound);
		col = mix(col, mix(skin, vec3(1.0, 0.62, 0.62), 0.45), heal);
		a = max(wound, (1.0 - smoothstep(0.75, 1.0, r + e)) * 0.8);
		gloss = 0.6 * (1.0 - heal * 0.6);
	} else if (kind == WOUND) {
		float e = (fbm(uv * 2.2 + seed) - 0.5) * 0.4;
		float w = 1.0 - smoothstep(0.4, 0.75, r + e);
		float deep = 1.0 - smoothstep(0.05, 0.45, r + e);
		col = mix(mix(skin, red, 0.85), vec3(0.6, 0.07, 0.07), w);
		col = mix(col, vec3(0.28, 0.01, 0.02), deep * 0.8);
		col = mix(col, vec3(0.95, 0.85, 0.6), (1.0 - smoothstep(0.0, 0.08, voronoi(uv * 9.0 + seed).y)) * w * 0.25);
		col = mix(col, mix(skin, vec3(1.0, 0.62, 0.62), 0.45), heal);
		a = (1.0 - smoothstep(0.7, 1.0, r + e));
		gloss = 0.85 * (1.0 - heal * 0.7);
	} else if (kind == CALLUS) {
		float e = (fbm(uv * 2.0 + seed) - 0.5) * 0.3;
		a = 1.0 - smoothstep(0.6, 0.95, r + e);
		col = mix(vec3(0.8, 0.66, 0.43), vec3(0.97, 0.88, 0.67), fbm(uv * 7.0 + seed));
		vec2 vr = voronoi(uv * 4.5 + seed);
		col = mix(col, vec3(0.45, 0.32, 0.18), (1.0 - smoothstep(0.0, 0.05, vr.y)) * 0.75);
		// raspado: pele nova rosada com riscos
		float scr = abs(sin(uv.x * 90.0 + fbm(uv * 3.0) * 6.0));
		vec3 raw = mix(skin, vec3(1.0, 0.6, 0.58), 0.4) * (0.9 + 0.1 * smoothstep(0.0, 0.3, scr));
		col = mix(col, raw, smoothstep(0.2, 0.9, m));
		a *= 1.0 - smoothstep(0.75, 1.0, m) * 0.85;
		gloss = 0.05 + m * 0.25;
	} else if (kind == CRUST) {
		float e = (fbm(uv * 2.4 + seed) - 0.5) * 0.45;
		a = 1.0 - smoothstep(0.5, 0.85, r + e);
		col = mix(vec3(0.3, 0.08, 0.05), vec3(0.58, 0.28, 0.11), fbm(uv * 8.0 + seed));
		vec2 vr = voronoi(uv * 6.0 + seed);
		col = mix(col, vec3(0.9, 0.75, 0.4), (1.0 - smoothstep(0.0, 0.05, vr.y)) * 0.3);
		col = mix(col, vec3(0.95, 0.5, 0.5), smoothstep(0.2, 0.9, m));
		a *= 1.0 - smoothstep(0.7, 1.0, m) * 0.85;
		gloss = 0.2 + m * 0.5;
	} else if (kind == BRUISE) {
		float e = (fbm(uv * 2.0 + seed) - 0.5) * 0.4;
		float b = 1.0 - smoothstep(0.1, 1.0, r + e);
		col = mix(vec3(0.75, 0.7, 0.3), vec3(0.42, 0.18, 0.45), smoothstep(0.1, 0.7, b));
		a = b * 0.75;
		bump = 0.3;
	} else if (kind == TRACK) {
		float y0 = sin(uv.x * 5.0 + seed) * 0.22;
		float d = abs(uv.y - y0);
		float along = smoothstep(-1.0, -0.8, uv.x) * (1.0 - smoothstep(0.8, 1.0, uv.x));
		a = (1.0 - smoothstep(0.03, 0.32, d)) * along * 0.85;
		col = mix(skin, red, 0.55 + 0.3 * (1.0 - smoothstep(0.0, 0.1, d)));
		gloss = 0.4;
		col = mix(col, mix(skin, vec3(1.0, 0.62, 0.62), 0.4), heal);
	} else if (kind == CREAM) {
		// creme branco espesso, com marcas do espalhar
		float streak = fbm(vec2(uv.x * 3.0, uv.y * 18.0) + seed);
		// creme grosso: quase opaco onde espalhou, mais fino só na borda
		a = smoothstep(0.08, 0.45, m) * (1.0 - smoothstep(0.82, 1.0, r)) * (0.82 + 0.15 * streak);
		col = mix(vec3(0.95, 0.94, 0.9), vec3(1.0, 0.995, 0.98), streak);
		col = mix(col, skin * 1.05, smoothstep(0.4, 0.08, m) * 0.45);
		gloss = 0.75;
	} else if (kind == OILY) {
		a = (1.0 - smoothstep(0.3, 1.0, r)) * 0.22;
		col = vec3(1.0, 0.95, 0.75);
		gloss = 1.0;
	} else if (kind == STUBBLE) {
		// pontinhos dos pelos raspados
		vec2 cell = floor(uv * 55.0);
		vec2 fp = fract(uv * 55.0) - 0.5 - (vec2(h21(cell), h21(cell + 3.7)) - 0.5) * 0.6;
		float dot_ = (1.0 - smoothstep(0.08, 0.16, length(fp))) * step(0.35, h21(cell + 9.1));
		float area = 1.0 - smoothstep(0.55, 1.0, r + (fbm(uv * 2.0 + seed) - 0.5) * 0.3);
		col = vec3(0.12, 0.08, 0.06);
		a = dot_ * area * 0.85;
		gloss = 0.1;
	} else if (kind == SCAR) {
		float e = (fbm(uv * 2.5 + seed) - 0.5) * 0.35;
		a = (1.0 - smoothstep(0.15, 1.0, r + e)) * 0.6;
		col = mix(skin, vec3(0.93, 0.52, 0.55), 0.5) * (0.95 + 0.08 * fbm(uv * 8.0 + seed));
		float pc = (1.0 - smoothstep(0.04, 0.12, r)) * pore;
		col = mix(col, vec3(0.45, 0.15, 0.12), pc * 0.8);
		a = max(a, pc * 0.8);
		gloss = 0.45;
	} else if (kind == SCRAPE) {
		a = (1.0 - smoothstep(0.3, 1.0, r)) * 0.7;
		float scr = abs(sin(uv.y * 120.0 + fbm(uv * 4.0) * 5.0));
		a = (1.0 - smoothstep(0.35, 1.0, r + (fbm(uv * 3.0 + seed) - 0.5) * 0.35)) * 0.92;
		col = mix(skin, vec3(0.78, 0.2, 0.18), 0.75) * (0.8 + 0.2 * smoothstep(0.0, 0.25, scr));
		// pontinhos de sangue seco e carne viva brilhante
		col = mix(col, vec3(0.38, 0.03, 0.04), smoothstep(0.62, 0.75, vnoise(uv * 40.0 + seed)) * 0.85);
		col = mix(col, vec3(0.95, 0.5, 0.45), smoothstep(0.7, 0.85, fbm(uv * 9.0 - seed)) * 0.4);
		gloss = 0.85;
	}

	a *= strength;
	// ---- corte pintado (canal A) e sangue (canal G)
	if (use_fx > 0.5) {
		float co = cut_open(f.a);
		float lip = smoothstep(0.05, 0.5, f.a) * (1.0 - co);
		float halo = smoothstep(0.0, 0.25, f.a);
		col = mix(col, mix(skin, red, 0.7), halo * 0.6 * (1.0 - a));
		a = max(a, halo * 0.7);
		col = mix(col, col * vec3(1.05, 0.85, 0.85), lip);
		vec3 inside = mix(vec3(0.55, 0.05, 0.07), vec3(0.2, 0.0, 0.02), smoothstep(0.7, 1.0, f.a));
		inside = mix(inside, vec3(0.95, 0.9, 0.7), smoothstep(0.9, 1.0, f.a) * 0.15 * open_amt);
		vec3 crust = mix(vec3(0.42, 0.14, 0.1), vec3(0.62, 0.3, 0.22), fbm(uv * 20.0));
		inside = mix(inside, crust, scar);
		col = mix(col, inside, co);
		col = mix(col, mix(skin, vec3(0.95, 0.55, 0.58), 0.5), lip * scar * 0.6);
		a = max(a, co);
		gloss = max(gloss, co * 0.9 * (1.0 - scar));
		float bl = smoothstep(0.04, 0.3, f.g) * (1.0 - scar);
		// sangue fresco: vermelho vivo fino nas bordas, escuro onde empoça
		col = mix(col, mix(vec3(0.78, 0.04, 0.06), vec3(0.36, 0.0, 0.02), smoothstep(0.25, 0.95, f.g)), bl);
		a = max(a, bl * 0.98);
		gloss = max(gloss, bl);
	}

	if (kind != FAVO && kind != WOUND && kind != TRACK) {
		a *= 1.0 - heal;
	} else {
		a *= 1.0 - smoothstep(0.6, 1.0, heal) * 0.9;
	}
	// brilho molhado logo depois de limpar
	float wt = wet * m;
	a *= COLOR.a;
	float wa = wt * 0.35 * COLOR.a;
	if (a < 0.01 && wa < 0.01) {
		discard;
	}
	if (a < 0.01) {
		col = skin * 0.97;
	}
	gloss = max(gloss, wt);

	// normal a partir do campo de altura
	float e = 0.012;
	float h0 = hfield(uv);
	float hu = hfield(uv + vec2(e, 0.0));
	float hv = hfield(uv + vec2(0.0, e));
	float du = (hu - h0) / e;
	float dv = (hv - h0) / e;
	float c = cos(rot);
	float s = sin(rot);
	vec2 g = vec2(du * c - dv * s, du * s + dv * c) / max(half_size, 0.001);
	vec3 n = normalize(wn - vec3(g.x, 0.0, g.y) * 0.012 * bump);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ALBEDO = col * (0.92 + 0.08 * clamp(h0, -1.0, 1.0));
	ALPHA = clamp(max(a, wa), 0.0, 1.0);
	ROUGHNESS = mix(0.72, 0.06, gloss);
}

#include "res://shaders/lighting.gdshaderinc"
