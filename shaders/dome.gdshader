shader_type spatial;
render_mode depth_draw_always;
// Cúpulas: espinha com pus, bolha d'água, furúnculo, verruga, caroço
#include "res://shaders/noise.gdshaderinc"

uniform int kind = 0;
uniform vec3 skin : source_color = vec3(0.95, 0.75, 0.6);
uniform float swell = 0.0;
uniform float hole = 0.0;
uniform float frozen = 0.0;
uniform float seed = 0.0;
uniform float alpha_mul = 1.0;

varying vec3 lp;

void vertex() {
	lp = VERTEX;
	if (kind == 3) {
		float b = vnoise(VERTEX.xz * 5.0 + seed) * 0.28 + vnoise(VERTEX.xz * 12.0 + seed) * 0.14;
		VERTEX += NORMAL * b * smoothstep(-0.2, 0.6, VERTEX.y);
	}
	VERTEX *= 1.0 + swell * 0.3;
}

void fragment() {
	float h = clamp(lp.y, 0.0, 1.0);
	float top = smoothstep(0.55, 0.97, h);
	vec3 red = vec3(0.86, 0.3, 0.3);
	vec3 col = skin;
	float alpha = 1.0;
	float gloss = 0.6;
	if (kind == 0) {
		col = mix(mix(skin, red, 0.75), vec3(0.98, 0.86, 0.4), top);
		col = mix(col, vec3(1.0, 0.97, 0.82), smoothstep(0.9, 1.0, h) * 0.6);
		gloss = 0.8;
	} else if (kind == 1) {
		col = mix(mix(skin, red, 0.25), vec3(1.0, 0.98, 0.9), smoothstep(0.1, 0.9, h));
		alpha = 0.8;
		gloss = 1.0;
	} else if (kind == 2) {
		col = mix(vec3(0.66, 0.14, 0.2), vec3(0.88, 0.32, 0.32), h);
		col = mix(col, vec3(0.96, 0.84, 0.34), smoothstep(0.8, 0.93, h));
		gloss = 0.75;
	} else if (kind == 3) {
		col = mix(vec3(0.68, 0.58, 0.46), vec3(0.86, 0.78, 0.64), vnoise(lp.xz * 14.0 + seed));
		col = mix(col, vec3(0.4, 0.3, 0.22), step(0.9, h21(floor(lp.xz * 18.0))) * 0.7);
		gloss = 0.08;
	} else if (kind == 4) {
		col = mix(mix(skin, red, 0.5), skin, h);
		gloss = 0.4;
	} else if (kind == 5) {
		col = mix(vec3(0.9, 0.86, 0.72), vec3(0.98, 0.96, 0.88), 0.5 + 0.5 * cos(lp.z * 30.0));
		gloss = 0.6;
	}
	float hd = length(lp.xz);
	col = mix(col, vec3(0.3, 0.04, 0.03), (1.0 - smoothstep(0.1, 0.17, hd)) * hole * step(0.75, h));
	col = mix(col, vec3(0.82, 0.93, 1.0), frozen * 0.85);
	gloss = mix(gloss, 0.9, frozen);
	ALBEDO = col;
	ALPHA = alpha * alpha_mul;
	ROUGHNESS = mix(0.85, 0.08, gloss);
	SPECULAR = 0.65;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	EMISSION = red * rim * 0.12;
}
