shader_type spatial;
render_mode depth_draw_always;
// Cúpulas: espinha com pus, bolha d'água, furúnculo, verruga, caroço.
// Pele fina translúcida deixa ver o pus; murcha com rugas; pode ser cortada (fx.a).
#include "res://shaders/noise.gdshaderinc"
#include "res://shaders/deform.gdshaderinc"

uniform int kind = 0;
uniform vec3 skin : source_color = vec3(0.95, 0.75, 0.6);
uniform float swell = 0.0;
uniform float hole = 0.0;
uniform float frozen = 0.0;
uniform float seed = 0.0;
uniform float alpha_mul = 1.0;
uniform float deflate = 0.0;
uniform vec3 pus_col : source_color = vec3(0.93, 0.78, 0.36);
uniform sampler2D fx : filter_linear, repeat_disable;
uniform sampler2D fxw : filter_linear, repeat_disable;
uniform float use_fx = 0.0;
uniform float open_amt = 0.0;
uniform float sss_amount = 0.9;
uniform vec3 sss_color : source_color = vec3(1.0, 0.45, 0.2);

varying vec3 lp;
varying vec3 wn;

float cut_a(vec3 q) {
	return use_fx > 0.5 ? texture(fx, q.xz * 0.5 + 0.5).a : 0.0;
}

void vertex() {
	lp = VERTEX;
	vec3 v = VERTEX;
	if (kind == 3) {
		float b = vnoise(v.xz * 5.0 + seed) * 0.28 + vnoise(v.xz * 12.0 + seed) * 0.14;
		v += NORMAL * b * smoothstep(-0.2, 0.6, v.y);
	}
	// murchar: achata e enruga
	float rr = length(v.xz);
	// murcho: pregas radiais (pele vazia enrugando), sem espiral
	float wr = sin(atan(v.z, v.x) * 7.0 + seed + sin(rr * 5.0 + seed) * 0.6) * sin(rr * 9.0) * 0.035 * deflate;
	v.y = v.y * (1.0 - deflate * 0.75) + wr * smoothstep(0.0, 0.4, v.y);
	// corte abre a cúpula
	float co = smoothstep(0.55 - open_amt * 0.4, 0.95, cut_a(v));
	v -= NORMAL * co * 0.35;
	v *= 1.0 + swell * 0.3;
	// lateja devagar (inflamação viva); para quando murcha
	if (kind != 3) {
		v.y *= 1.0 + 0.045 * sin(TIME * 2.3 + seed) * (1.0 - deflate) * smoothstep(0.0, 0.5, v.y);
	}
	VERTEX = v;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * skin_deform(w);
	wn = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	float h = clamp(lp.y, 0.0, 1.0);
	float top = smoothstep(0.55, 0.97, h);
	vec3 red = vec3(0.86, 0.3, 0.3);
	vec3 col = skin;
	float alpha = 1.0;
	float gloss = 0.6;
	if (kind == 0) {
		// base inflamada -> pele fina esticada -> cabeça de pus amarela
		// pele esticada: rosada na base, mais clara e fina no topo, pus amarelado aparecendo
		col = mix(mix(skin, red, 0.42), mix(skin, vec3(1.0, 0.7, 0.62), 0.45), smoothstep(0.1, 0.75, h));
		vec3 pus = mix(pus_col, mix(pus_col, vec3(1.0), 0.6), smoothstep(0.9, 1.0, h));
		col = mix(col, pus, smoothstep(0.72, 0.96, h) * (1.0 - deflate * 0.6));
		gloss = 0.7;
	} else if (kind == 1) {
		col = mix(mix(skin, red, 0.25), vec3(1.0, 0.98, 0.9), smoothstep(0.1, 0.9, h));
		alpha = 0.78 + 0.2 * deflate;
		gloss = 1.0;
	} else if (kind == 2) {
		col = mix(mix(skin, red, 0.45), mix(skin, vec3(0.8, 0.22, 0.25), 0.8), smoothstep(0.0, 0.6, h));
		col = mix(col, vec3(0.92, 0.55, 0.3), smoothstep(0.72, 0.85, h));
		col = mix(col, pus_col * 1.05, smoothstep(0.84, 0.95, h));
		col = mix(col, vec3(1.0, 0.97, 0.8), smoothstep(0.96, 1.0, h) * 0.6);
		gloss = 0.7;
	} else if (kind == 3) {
		col = mix(vec3(0.66, 0.56, 0.45), vec3(0.86, 0.78, 0.64), vnoise(lp.xz * 14.0 + seed));
		col = mix(col, vec3(0.38, 0.28, 0.2), step(0.9, h21(floor(lp.xz * 18.0))) * 0.7);
		gloss = 0.08;
	} else if (kind == 4) {
		col = mix(mix(skin, red, 0.5), skin, h);
		gloss = 0.4;
	} else if (kind == 5) {
		col = mix(vec3(0.9, 0.86, 0.72), vec3(0.98, 0.96, 0.88), 0.5 + 0.5 * cos(lp.z * 30.0));
		gloss = 0.6;
	}
	// rugas escurecem
	float rr = length(lp.xz);
	col *= 1.0 - deflate * 0.18 * (0.5 + 0.5 * sin(atan(lp.z, lp.x) * 7.0 + seed + sin(rr * 5.0 + seed) * 0.6));
	float hd = rr;
	vec3 hole_c = kind == 1 ? vec3(0.8, 0.5, 0.45) : vec3(0.3, 0.04, 0.03);
	col = mix(col, hole_c, (1.0 - smoothstep(0.08, 0.15, hd)) * hole * step(0.75, h));
	// corte: dentro vermelho com pus
	float ca = cut_a(lp);
	float co = smoothstep(0.55 - open_amt * 0.4, 0.95, ca);
	col = mix(col, mix(skin, red, 0.8), smoothstep(0.0, 0.4, ca) * 0.6);
	col = mix(col, mix(vec3(0.5, 0.04, 0.06), vec3(0.95, 0.82, 0.35), open_amt * 0.8), co);
	// sangue brotando do corte
	float bl = use_fx > 0.5 ? smoothstep(0.05, 0.35, texture(fx, lp.xz * 0.5 + 0.5).g * (1.0 - texture(fxw, lp.xz * 0.5 + 0.5).r)) : 0.0;
	col = mix(col, vec3(0.45, 0.02, 0.04), bl);
	gloss = max(gloss, bl);
	col = mix(col, vec3(0.82, 0.93, 1.0), frozen * 0.85);
	gloss = mix(max(gloss, co), 0.9, frozen);
	ALBEDO = col;
	// borda some na pele (sem quina)
	float edge = smoothstep(0.0, 0.22, lp.y);
	col = mix(skin, col, edge);
	ALPHA = alpha * alpha_mul * smoothstep(0.0, 0.12, lp.y);
	ROUGHNESS = mix(0.85, 0.06, gloss);
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(wn), 0.0)).xyz);
}

#include "res://shaders/lighting.gdshaderinc"
