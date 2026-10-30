// Luz de pele: difusa "wrap" + espalhamento subsuperficial avermelhado + dois lóbulos especulares
// Requer: uniform float sss_amount; uniform vec3 sss_color;

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float wrap = 0.5;
	float diff = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	float terminator = smoothstep(-0.25, 0.25, ndl) * (1.0 - smoothstep(0.2, 0.75, ndl));
	vec3 scatter = sss_color * terminator * sss_amount;
	DIFFUSE_LIGHT += (ALBEDO * diff + scatter) * LIGHT_COLOR * ATTENUATION / PI;
	vec3 H = normalize(VIEW + LIGHT);
	float nh = max(dot(NORMAL, H), 0.0);
	float gloss = 1.0 - ROUGHNESS;
	float fres = 0.04 + 0.96 * pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 5.0);
	float spec = pow(nh, 14.0) * 0.035 + pow(nh, mix(30.0, 400.0, gloss)) * gloss * gloss * (0.2 + gloss * 2.4);
	SPECULAR_LIGHT += spec * (0.5 + fres) * LIGHT_COLOR * ATTENUATION * max(ndl, 0.0);
}
