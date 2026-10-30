// Deformação da pele sob a ferramenta (pressão afunda, pinça puxa)
global uniform vec3 press_pos;
global uniform float press_amt;
global uniform float press_r;
global uniform vec3 pull_pos;
global uniform float pull_amt;
global uniform float pull_r;

vec3 skin_deform(vec3 wp) {
	vec2 dp = wp.xz - press_pos.xz;
	float k = exp(-dot(dp, dp) / (press_r * press_r));
	// anel do espremedor: afunda em volta e empurra o centro para cima
	float ring = exp(-pow(length(dp) - press_r * 0.6, 2.0) / (press_r * press_r * 0.08));
	float dy = -press_amt * (k * 0.6 + ring * 0.6) + press_amt * 0.5 * exp(-dot(dp, dp) / (press_r * press_r * 0.12));
	vec2 dq = wp.xz - pull_pos.xz;
	float kq = exp(-dot(dq, dq) / (pull_r * pull_r));
	dy += pull_amt * kq;
	return vec3(0.0, dy, 0.0);
}
