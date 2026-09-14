shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform float radius = 40.0;
uniform float rotation_phase = 0.0;
uniform float age = 0.0;
uniform float phase = 0.0;
uniform float charge = 0.0;
uniform float icy = 0.0;
uniform float flashes = 1.0;
uniform float completion = 0.0;
varying vec2 local_position;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
		mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	vec4 face = COLOR;
	vec2 p = local_position / max(radius, 0.01);
	float c = cos(rotation_phase);
	float s = sin(rotation_phase);
	vec2 q = mat2(vec2(c, -s), vec2(s, c)) * p;
	float coarse = noise(q * 7.0 + phase);
	float grain = noise(q * 34.0 + phase);
	float texture_strength = 1.0 - completion * 0.65;
	vec3 color = face.rgb;
	if (icy < 0.5) {
		float ridges = abs(noise(q * 13.0 + coarse) - 0.5) * 2.0;
		color *= 0.79 + coarse * 0.34 + (grain - 0.5) * 0.20 * texture_strength;
		color += face.rgb * vec3(0.13, 0.11, 0.08) * ridges * charge * 0.28 * texture_strength;
	} else {
		// Offset inner layers give crystal depth without sampling the sky.
		vec2 parallax = vec2(sin(age * 0.24 + phase), cos(age * 0.19)) * 0.045;
		float inner = noise((q + parallax) * 9.0 + phase);
		float veins = 1.0 - smoothstep(0.012, 0.048, abs(inner - 0.48));
		float embedded = noise((q - parallax) * 21.0);
		color *= 0.63 + coarse * 0.38 + embedded * 0.12;
		color += face.rgb * vec3(0.09, 0.26, 0.32) * inner * texture_strength;
		color += face.rgb * vec3(0.37, 0.65, 0.72) * veins * (0.10 + charge * 0.25) * texture_strength;
		float sparkle = pow(max(0.0, sin(q.x * 10.0 + q.y * 7.0 + age * 0.55 + phase)), 24.0);
		color += face.rgb * vec3(0.28, 0.35, 0.36) * sparkle * pow(embedded, 3.0) * flashes * texture_strength;
	}
	COLOR = vec4(color, face.a);
}
