shader_type spatial;
// Tubos: verme, larva, pus, fluido
#include "res://shaders/noise.gdshaderinc"

uniform int kind = 0;
uniform float segs = 14.0;
uniform float frozen = 0.0;
uniform vec3 tint : source_color = vec3(1.0);

void fragment() {
	float rib = 0.5 + 0.5 * cos(UV.y * segs * 6.2831);
	vec3 col;
	float gloss = 0.6;
	if (kind == 0) {
		col = mix(vec3(0.72, 0.45, 0.42), vec3(0.92, 0.68, 0.62), rib);
		col = mix(col, vec3(0.5, 0.25, 0.25), smoothstep(0.94, 1.0, UV.y));
	} else if (kind == 1) {
		col = mix(vec3(0.86, 0.82, 0.68), vec3(0.99, 0.97, 0.9), rib);
		col = mix(col, vec3(0.2, 0.15, 0.1), smoothstep(0.95, 1.0, UV.y));
	} else if (kind == 2) {
		col = mix(vec3(0.93, 0.76, 0.26), vec3(1.0, 0.94, 0.62), fbm(UV * vec2(3.0, 12.0)));
		gloss = 0.95;
	} else if (kind == 3) {
		col = vec3(0.12, 0.17, 0.1) * (0.8 + rib * 0.4);
		gloss = 0.85;
	} else if (kind == 4) {
		col = vec3(0.6, 0.38, 0.18) * (0.85 + 0.3 * fbm(UV * vec2(2.0, 20.0)));
		gloss = 0.1;
	} else if (kind == 5) {
		col = mix(tint, vec3(0.86, 0.38, 0.36), 0.35 + 0.1 * rib);
		gloss = 0.45;
	} else {
		col = vec3(0.18, 0.12, 0.08) * (0.8 + 0.4 * UV.x);
		gloss = 0.5;
	}
	if (kind != 5) {
		col *= tint;
	}
	col = mix(col, vec3(0.82, 0.93, 1.0), frozen * 0.8);
	ALBEDO = col;
	ROUGHNESS = mix(0.85, 0.1, gloss);
	SPECULAR = 0.6;
}
