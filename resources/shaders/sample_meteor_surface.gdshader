shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform float age = 0.0;
uniform float phase = 0.0;
uniform float charge : hint_range(0.0, 1.0) = 0.0;
uniform float completion : hint_range(0.0, 1.0) = 0.0;
uniform float motion : hint_range(0.0, 1.0) = 1.0;
uniform float flashes : hint_range(0.0, 1.0) = 1.0;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float grain(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(cell), hash21(cell + vec2(1.0, 0.0)), f.x),
		mix(hash21(cell + vec2(0.0, 1.0)), hash21(cell + vec2(1.0)), f.x), f.y);
}

void fragment() {
	vec4 tint = COLOR;
	// Pixel-space bounds match the authored quad; its local origin is the core.
	vec2 p = vec2(-86.0, -18.0) + UV * vec2(104.0, 36.0);
	float clock = age + completion * 0.45 * motion;
	float turn = phase + clock * 0.23 + sin(clock * 0.67 + phase) * 0.13;
	float c = cos(turn);
	float s = sin(turn);
	float contraction = 1.0 - completion * 0.68 * motion;
	vec2 q = mat2(vec2(c, -s), vec2(s, c)) * p / contraction;
	q.y *= 1.12;
	float angle = atan(q.y, q.x);
	float radius = 5.4 * (1.0 + 0.10 * sin(angle * 3.0 + phase)
		+ 0.065 * sin(angle * 5.0 - 0.8) + 0.035 * sin(angle * 7.0 + 1.4));
	float distance = length(q) - radius;
	float aa = max(fwidth(distance), 0.24);
	float core = 1.0 - smoothstep(-aa * 0.5, aa * 0.5, distance);
	float roughness = grain(q * 0.52 + vec2(phase, 1.7));
	float fine = grain(q * 1.65 + vec2(2.8, phase));
	vec2 sphere = p / (radius * contraction);
	vec3 normal = normalize(vec3(sphere * 0.90,
		sqrt(max(0.02, 1.0 - dot(sphere, sphere)))) + vec3((roughness - 0.5) * 0.35));
	float light = max(0.0, dot(normal, normalize(vec3(0.55, -0.62, 0.65))));
	vec3 rock = mix(vec3(0.045, 0.16, 0.17), vec3(0.64, 0.77, 0.67), light);
	rock *= 0.71 + roughness * 0.36 + fine * 0.13;
	float veins = 1.0 - smoothstep(0.025, 0.095, abs(roughness - 0.52));
	rock += veins * vec3(0.08, 0.25, 0.23) * (0.6 + charge * 0.35);
	float hot_face = pow(light, 9.0) * (0.33 + fine * 0.25);
	rock = mix(rock, vec3(0.96, 0.97, 0.83), hot_face);

	float behind = max(0.0, -p.x);
	float u = clamp(behind / 82.0, 0.0, 1.0);
	float tail_gate = smoothstep(-1.0, 7.0, -p.x) * pow(1.0 - u, 1.6);
	float flow = sin(u * 12.0 - clock * 3.1 + phase) * (0.3 + u * 1.65);
	float width = 2.3 + u * 2.6;
	float haze = exp(-pow((p.y - flow * 0.6) / width, 2.0)) * 0.17;
	float filament_a = exp(-pow((p.y - flow - 1.15 - u * 1.7) / (0.65 + u * 0.7), 2.0));
	float filament_b = exp(-pow((p.y + flow * 0.65 + 1.0 + u * 1.3) / (0.6 + u * 0.8), 2.0));
	float flow_grain = 0.7 + 0.3 * grain(vec2(p.x * 0.13 + clock * 2.0, p.y * 0.3 + phase));
	float tail = (haze + filament_a * 0.22 + filament_b * 0.12) * tail_gate * flow_grain;
	tail *= 1.0 - completion * 0.7;
	float halo = exp(-dot(p, p) / 66.0) * (0.18 + charge * 0.025);
	float bow_radius = length(p / vec2(7.4, 8.0));
	float bow = exp(-pow((bow_radius - 1.0) * 4.5, 2.0))
		* smoothstep(-0.2, 0.85, p.x / max(length(p), 0.01)) * 0.15;
	float shimmer = 0.0;
	for (int i = 0; i < 3; i++) {
		float lane = float(i) - 1.0;
		vec2 offset = vec2(-5.5 - completion * (11.0 + float(i) * 2.0) * motion,
			lane * (3.0 + completion * 6.0 * motion));
		shimmer += exp(-dot(p - offset, p - offset) / 0.8)
			* sin(completion * 3.14159265) * 0.52 * flashes;
	}
	float glow_alpha = clamp(tail + halo + bow + shimmer, 0.0, 1.0);
	glow_alpha *= 1.0 - smoothstep(13.0, 18.0, abs(p.y));
	vec3 glow_color = mix(vec3(0.31, 0.72, 0.70), vec3(0.85, 0.96, 0.87),
		clamp(shimmer * 2.0 + halo, 0.0, 1.0));
	float alpha = core + glow_alpha * (1.0 - core);
	vec3 rgb = (rock * core + glow_color * glow_alpha * (1.0 - core)) / max(alpha, 0.0001);
	COLOR = vec4(rgb, alpha) * tint;
}
