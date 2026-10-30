// Ruídos pré-calculados em texturas (rápido no celular). Ver autoload/noise_lib.gd.
// Escala: 1 unidade de "p" = 1 célula; as texturas repetem a cada 32 unidades.
global uniform sampler2D g_vn : filter_linear_mipmap, repeat_enable;
global uniform sampler2D g_fbm : filter_linear_mipmap, repeat_enable;
global uniform sampler2D g_c1 : filter_linear_mipmap, repeat_enable;
global uniform sampler2D g_c2 : filter_linear_mipmap, repeat_enable;

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	return texture(g_vn, p * 0.03125).r;
}
float fbm(vec2 p) {
	return 0.47 + (texture(g_fbm, p * 0.03125).r - 0.5) * 0.6;
}
// x = distância ao centro mais próximo, y = distância até a borda da célula
vec2 voronoi(vec2 p) {
	vec2 uv = p * 0.03125;
	return vec2(texture(g_c1, uv).r * 0.85, texture(g_c2, uv).r * 0.5);
}
