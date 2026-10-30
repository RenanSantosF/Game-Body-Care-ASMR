shader_type spatial;
// Pele suave estilizada: AO assado nos vértices, poros sutis, borda avermelhada (falso SSS)

uniform vec3 skin : source_color = vec3(0.96, 0.76, 0.62);
uniform vec3 skin_deep : source_color = vec3(0.82, 0.42, 0.38);
uniform sampler2D paint : source_color, filter_linear, repeat_disable;
uniform vec4 paint_rect = vec4(-3.0, -1.5, 6.0, 3.0);

varying vec3 wp;
varying float vao;

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vao = COLOR.r;
}

void fragment() {
	float n = vnoise(wp.xz * 7.0) * 0.5 + vnoise(wp.xz * 21.0) * 0.3 + vnoise(wp.xz * 75.0) * 0.2;
	vec3 c = skin * (0.95 + n * 0.08);
	c = mix(skin_deep, c, smoothstep(0.3, 0.95, vao));
	c *= mix(0.6, 1.0, smoothstep(0.2, 0.9, vao));
	vec2 uv = (wp.xz - paint_rect.xy) / paint_rect.zw;
	vec4 pt = texture(paint, uv);
	c = mix(c, pt.rgb, pt.a);
	ALBEDO = c;
	ROUGHNESS = mix(0.58, 0.2, pt.a);
	SPECULAR = 0.35;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	EMISSION = skin_deep * rim * 0.12;
}
