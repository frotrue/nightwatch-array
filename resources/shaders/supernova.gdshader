shader_type canvas_item;
render_mode unshaded;

uniform float progress = 0.0;
uniform float initial_radius = 0.4;
uniform float motion = 1.0;
uniform float flashes = 1.0;
uniform float seed_phase = 0.0;

float hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1)), f.x), f.y);
}
float clouds(vec2 p) {
	p += vec2(noise(p + 13.0), noise(p - 7.0)) * 1.2;
	mat2 turn = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	float value = noise(p) * 0.5;
	p = turn * p * 2.03 + 11.0;
	value += noise(p) * 0.28;
	p = turn * p * 2.11 - 7.0;
	return value + noise(p) * 0.14 + noise(turn * p * 1.93) * 0.08;
}

void fragment() {
	vec4 tint = COLOR;
	vec2 p = (UV - 0.5) * 2.0;
	float t = clamp(progress, 0.0, 1.0);
	float radius = mix(initial_radius * 0.8, 0.88, pow(t, 0.72));
	vec2 flow = p / max(radius, 0.05);
	float cloud = clouds(flow * 5.0 + vec2(seed_phase, t * -0.8));
	float r = length(p) * (0.91 + clouds(flow * 2.3 + seed_phase) * 0.18);
	float shell = exp(-pow((r - radius * 0.8) / (0.075 + radius * 0.22), 2.0));
	shell *= smoothstep(0.25, 0.75, cloud) * smoothstep(0.0, 0.16, t);
	float interior = exp(-r * r / max(0.001, radius * radius * 0.48)) * cloud * 0.35;
	float fade = 1.0 - smoothstep(0.55, 1.0, t);
	float gas = (shell * 0.72 + interior) * fade * motion;
	float rebound = mix(initial_radius, max(initial_radius, 0.22), smoothstep(0.0, 0.12, t) * motion);
	float core_radius = max(0.025, rebound * (1.0 - smoothstep(0.12, 0.55, t)));
	float core = exp(-pow(r / core_radius, 2.8)) * (1.0 - smoothstep(0.1, 0.55, t));
	vec3 gas_color = mix(vec3(0.54, 0.24, 0.13), vec3(0.95, 0.65, 0.37), cloud);
	vec3 core_color = mix(vec3(0.88, 0.57, 0.30), vec3(1.0, 0.88, 0.68), flashes);
	float alpha = clamp(gas + core, 0.0, 1.0) * (1.0 - smoothstep(0.94, 1.0, length(p)));
	COLOR = vec4(mix(gas_color, core_color, core) * tint.rgb, alpha * tint.a);
}
