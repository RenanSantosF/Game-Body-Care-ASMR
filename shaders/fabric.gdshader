shader_type spatial;
render_mode cull_disabled;
// Pano (trama de tecido) ou algodão (fibras fofas). Fica manchado com o que limpa.
#include "res://shaders/noise.gdshaderinc"

uniform int kind = 0;           // 0 pano, 1 algodão
uniform vec3 base : source_color = vec3(0.55, 0.78, 0.95);
uniform vec3 soil_col : source_color = vec3(0.4, 0.3, 0.15);
uniform float soil = 0.0;
uniform float wet = 0.6;

varying vec3 lp;

void vertex() {
	lp = VERTEX;
	if (kind == 1) {
		float f = vnoise(VERTEX.xz * 14.0 + VERTEX.y * 9.0) * 0.18 + vnoise(VERTEX.xy * 31.0) * 0.08;
		VERTEX += NORMAL * f;
	}
}

void fragment() {
	vec3 col;
	if (kind == 0) {
		vec2 g = UV * vec2(70.0, 60.0);
		float warp = 0.5 + 0.5 * sin(g.x * 6.2831);
		float weft = 0.5 + 0.5 * sin(g.y * 6.2831);
		float weave = mix(warp, weft, step(0.5, fract((floor(g.x) + floor(g.y)) * 0.5)));
		col = base * (0.78 + 0.22 * weave) * (0.92 + 0.08 * vnoise(UV * 12.0));
		col *= 1.0 - wet * 0.18;
	} else {
		float fib = vnoise(lp.xz * 60.0 + lp.y * 40.0) * 0.5 + vnoise(lp.xy * 90.0) * 0.5;
		col = vec3(0.97, 0.97, 0.95) * (0.86 + 0.14 * fib);
	}
	float sp = smoothstep(0.35, 0.75, fbm(UV * 5.0 + lp.xz * 8.0) + soil * 0.6 - 0.25);
	col = mix(col, soil_col, clamp(soil, 0.0, 0.85) * sp);
	ALBEDO = col;
	ROUGHNESS = kind == 0 ? 0.92 - wet * 0.3 : 0.98;
	SPECULAR = 0.2;
	if (kind == 1) {
		float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
		EMISSION = vec3(0.12) * rim;
	}
}
