shader_type spatial;
// Travesseiro fofo com costuras em losango

uniform vec3 base : source_color = vec3(0.55, 0.35, 0.78);
uniform vec2 half_size = vec2(4.5, 3.0);
uniform float puff = 0.35;

varying vec2 lp;

void vertex() {
	lp = VERTEX.xz;
	vec2 q = abs(VERTEX.xz) / half_size;
	float e = (1.0 - pow(q.x, 6.0)) * (1.0 - pow(q.y, 6.0));
	// gomos do acolchoado
	vec2 g = VERTEX.xz * 1.3;
	float quilt = 0.5 + 0.5 * cos(g.x + g.y) * cos(g.x - g.y);
	VERTEX.y += puff * clamp(e, 0.0, 1.0) - 0.05 * (1.0 - quilt) * e;
	VERTEX.y -= (1.0 - clamp(e, 0.0, 1.0)) * 0.5;
}

void fragment() {
	vec2 g = lp * 1.3;
	float a = abs(sin((g.x + g.y) * 0.5));
	float b = abs(sin((g.x - g.y) * 0.5));
	float seam = 1.0 - smoothstep(0.0, 0.06, min(a, b));
	vec3 c = base * (0.92 + 0.08 * sin(lp.x * 40.0) * sin(lp.y * 40.0));
	c = mix(c, base * 0.6, seam * 0.8);
	ALBEDO = c;
	ROUGHNESS = 0.9;
	SPECULAR = 0.15;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = base * rim * 0.12;
}
