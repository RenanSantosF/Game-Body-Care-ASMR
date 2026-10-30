shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;
// Lesões pintadas em remendos colados na pele (UV -1..1).
#include "res://shaders/noise.gdshaderinc"

uniform int kind = 0;
uniform vec3 skin : source_color = vec3(0.95, 0.75, 0.6);
uniform float seed = 0.0;
uniform float heal = 0.0;
uniform float cut = 1.0;
uniform float open_amt = 0.0;
uniform float use_mask = 0.0;
uniform float strength = 1.0;
uniform sampler2D mask : filter_linear, repeat_disable;

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

float blob(vec2 uv, float s, float edge) {
	float n = fbm(uv * 2.4 + s);
	return 1.0 - smoothstep(edge - 0.25, edge, length(uv) + (n - 0.5) * 0.75);
}

void fragment() {
	vec2 uv = UV;
	float r = length(uv);
	float m = use_mask > 0.5 ? texture(mask, uv * 0.5 + 0.5).r : 0.0;
	vec3 red = vec3(0.86, 0.3, 0.3);
	vec3 col = skin;
	float a = 0.0;
	float gloss = 0.0;
	if (kind == INFLAM) {
		float e = (fbm(uv * 2.5 + seed) - 0.5) * 0.35;
		a = (1.0 - smoothstep(0.15, 1.0, r + e)) * 0.8;
		col = mix(skin, red, 0.8);
		gloss = 0.2;
	} else if (kind == DIRT) {
		float sh = blob(uv, seed, 1.0);
		float n = fbm(uv * 4.0 + seed * 1.7);
		a = smoothstep(0.25, 0.6, sh * (0.55 + n * 0.7));
		col = mix(vec3(0.22, 0.14, 0.08), vec3(0.48, 0.34, 0.19), fbm(uv * 9.0 + seed * 3.0));
		float sp = step(0.86, h21(floor(uv * 34.0) + seed)) * smoothstep(0.1, 0.5, sh);
		col = mix(col, vec3(0.1, 0.07, 0.04), sp);
		a = max(a, sp * 0.95) * 0.95;
		gloss = 0.08;
	} else if (kind == PUS || kind == BLOOD || kind == FLUID) {
		float b = blob(uv, seed, 0.95);
		a = smoothstep(0.05, 0.35, b);
		float n = fbm(uv * 5.0 + seed);
		if (kind == PUS) {
			col = mix(vec3(0.9, 0.74, 0.25), vec3(1.0, 0.94, 0.62), n);
			col = mix(col, vec3(0.72, 0.78, 0.3), smoothstep(0.6, 0.9, fbm(uv * 3.0 + 9.0)) * 0.4);
		} else if (kind == BLOOD) {
			col = mix(vec3(0.38, 0.02, 0.04), vec3(0.68, 0.07, 0.08), n);
		} else {
			col = mix(vec3(1.0, 0.97, 0.85), skin, 0.4);
			a *= 0.55;
		}
		a *= 0.97;
		gloss = 0.92;
	} else if (kind == FAVO) {
		float e = (fbm(uv * 2.0 + seed) - 0.5) * 0.4;
		float wound = 1.0 - smoothstep(0.6, 0.85, r + e);
		vec3 base = mix(vec3(0.55, 0.16, 0.1), vec3(0.78, 0.42, 0.26), fbm(uv * 6.0 + seed));
		vec2 vr = voronoi(uv * 5.5 + seed);
		float hole = (1.0 - smoothstep(0.1, 0.2, vr.x)) * smoothstep(0.0, 0.3, wound);
		base = mix(base, vec3(0.92, 0.8, 0.45), (1.0 - smoothstep(0.0, 0.06, vr.y)) * 0.35);
		base = mix(base, vec3(0.16, 0.02, 0.02), hole * (1.0 - heal));
		vec3 rim = mix(skin, red, 0.85);
		col = mix(rim, base, wound);
		col = mix(col, mix(skin, vec3(1.0, 0.6, 0.62), 0.5), heal);
		a = max(wound, (1.0 - smoothstep(0.75, 1.0, r + e)) * 0.75);
		gloss = 0.55;
	} else if (kind == WOUND) {
		float e = (fbm(uv * 2.2 + seed) - 0.5) * 0.4;
		float w = 1.0 - smoothstep(0.45, 0.75, r + e);
		float deep = 1.0 - smoothstep(0.1, 0.45, r + e);
		col = mix(mix(skin, red, 0.85), vec3(0.62, 0.08, 0.08), w);
		col = mix(col, vec3(0.3, 0.02, 0.03), deep * 0.8);
		col = mix(col, mix(skin, vec3(1.0, 0.6, 0.62), 0.5), heal);
		a = (1.0 - smoothstep(0.7, 1.0, r + e));
		gloss = 0.8;
	} else if (kind == CALLUS) {
		float e = (fbm(uv * 2.0 + seed) - 0.5) * 0.3;
		a = 1.0 - smoothstep(0.65, 0.95, r + e);
		col = mix(vec3(0.82, 0.68, 0.45), vec3(0.96, 0.87, 0.66), fbm(uv * 7.0 + seed));
		vec2 vr = voronoi(uv * 4.5 + seed);
		col = mix(col, vec3(0.5, 0.36, 0.22), (1.0 - smoothstep(0.0, 0.05, vr.y)) * 0.75);
		col = mix(col, mix(skin, vec3(1.0, 0.6, 0.6), 0.35), m);
		a *= 1.0 - m * 0.9;
		gloss = 0.05;
	} else if (kind == CRUST) {
		float e = (fbm(uv * 2.4 + seed) - 0.5) * 0.45;
		a = 1.0 - smoothstep(0.55, 0.85, r + e);
		col = mix(vec3(0.35, 0.1, 0.06), vec3(0.6, 0.3, 0.12), fbm(uv * 8.0 + seed));
		vec2 vr = voronoi(uv * 6.0 + seed);
		col = mix(col, vec3(0.9, 0.75, 0.4), (1.0 - smoothstep(0.0, 0.05, vr.y)) * 0.3);
		col = mix(col, vec3(0.95, 0.55, 0.55), m);
		a *= 1.0 - m * 0.85;
		gloss = 0.25;
	} else if (kind == BRUISE) {
		float e = (fbm(uv * 2.0 + seed) - 0.5) * 0.4;
		float b = 1.0 - smoothstep(0.1, 1.0, r + e);
		col = mix(vec3(0.75, 0.7, 0.3), vec3(0.42, 0.18, 0.45), smoothstep(0.1, 0.7, b));
		a = b * 0.8;
	} else if (kind == CUT || kind == TRACK) {
		float y0 = kind == TRACK ? sin(uv.x * 5.0 + seed) * 0.22 : 0.0;
		float d = abs(uv.y - y0);
		float along = smoothstep(-1.0, -0.85, uv.x) * (1.0 - smoothstep(0.85, 1.0, uv.x));
		float halo = (1.0 - smoothstep(0.04, 0.3, d)) * along;
		col = mix(skin, red, 0.75);
		a = halo * (kind == TRACK ? 0.75 : 0.5);
		float cx = -0.9 + 1.8 * cut;
		float w = 0.025 + open_amt * 0.05;
		float slit = (1.0 - smoothstep(w * 0.6, w, d)) * step(uv.x, cx) * step(-0.92, uv.x);
		col = mix(col, vec3(0.5, 0.03, 0.05), slit);
		col = mix(col, vec3(0.25, 0.0, 0.02), slit * (1.0 - smoothstep(0.0, w * 0.5, d)));
		a = max(a, slit);
		gloss = slit * 0.8;
		col = mix(col, mix(skin, vec3(1.0, 0.62, 0.62), 0.4), heal);
	} else if (kind == OILY) {
		a = (1.0 - smoothstep(0.3, 1.0, r)) * 0.25;
		col = vec3(1.0, 0.95, 0.75);
		gloss = 1.0;
	}
	if (kind == DIRT || kind == PUS || kind == BLOOD || kind == FLUID) {
		a *= 1.0 - smoothstep(0.1, 0.9, m);
	}
	if (kind != FAVO && kind != WOUND && kind != CUT && kind != TRACK) {
		a *= 1.0 - heal;
	} else {
		a *= 1.0 - smoothstep(0.6, 1.0, heal) * 0.9;
	}
	a *= COLOR.a * strength;
	if (a < 0.01) {
		discard;
	}
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
	ROUGHNESS = mix(0.75, 0.12, gloss);
	SPECULAR = mix(0.3, 0.85, gloss);
}
