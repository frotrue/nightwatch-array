shader_type canvas_item;
render_mode unshaded, blend_mix;

// A local emitting sphere, not a screen filter. Simulation age keeps the
// surface still while paused and makes renderer comparison captures repeatable.
uniform float age = 0.0;
uniform float phase = 0.0;

float hash3(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x),
		mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
		mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float turbulence(vec3 p) {
	return noise3(p) * 0.57 + noise3(p * 2.03 + 9.2) * 0.28
		+ noise3(p * 4.11 + 21.8) * 0.15;
}

void fragment() {
	vec4 tint = COLOR;
	vec2 p = (UV - 0.5) * 3.2;
	float r = length(p);
	float aa = max(fwidth(r), 0.003);
	float disc = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, r);
	vec3 light = vec3(0.0);
	float opacity = 0.0;
	float t = age * 0.045;
	if (r < 1.0 + aa) {
		float z = sqrt(max(0.0, 1.0 - dot(p, p)));
		vec3 sphere = vec3(p, z);
		float rotation = phase + t * 0.35;
		sphere.xz = mat2(vec2(cos(rotation), -sin(rotation)), vec2(sin(rotation), cos(rotation))) * sphere.xz;
		vec3 flow = vec3(t * 0.28, -t * 0.17, phase * 3.0);
		float broad = turbulence(sphere * 3.4 + flow);
		vec3 warped = sphere * 10.0 + vec3(broad * 2.0, t * 0.4, -t * 0.25);
		float cells = turbulence(warped);
		float grain = noise3(warped * 1.8 + t * 0.3);
		float heat = clamp(cells * 0.72 + broad * 0.37 + grain * 0.09, 0.0, 1.0);
		// Dark intergranular lanes and broad active regions remain visible even
		// at the normal 60-80 pixel diameter; avoid a white, featureless centre.
		vec3 surface = mix(vec3(0.55, 0.12, 0.018), vec3(1.0, 0.55, 0.13), smoothstep(0.27, 0.65, heat));
		surface = mix(surface, vec3(1.0, 0.83, 0.39), smoothstep(0.61, 0.85, heat) * 0.85);
		float active_region = smoothstep(0.69, 0.82, broad) * 0.65;
		surface *= (1.0 - active_region) * (0.30 + 0.70 * pow(z, 0.55));
		light = surface;
		opacity = disc;
	}
	if (r > 0.97) {
		vec2 direction = p / max(r, 0.001);
		float exterior = max(0.0, r - 1.0);
		float filaments = turbulence(vec3(direction * 8.0, phase + t + exterior * 5.0));
		float wisps = pow(max(0.0, filaments), 2.5);
		float corona = exp(-exterior * 10.0) * (0.16 + wisps * 0.58);
		// Separate, unequal magnetic arches: local loops rather than a repeated
		// flower-shaped outline. Footpoints blend into the luminous limb.
		float arches = 0.0;
		for (int i = 0; i < 3; i++) {
			float index = float(i);
			float angle = phase * 0.31 + index * 2.17 + 0.2 * sin(index * 7.0);
			vec2 axis = vec2(cos(angle), sin(angle));
			vec2 local = vec2(dot(p, vec2(-axis.y, axis.x)), dot(p, axis));
			float arch_size = 0.13 + 0.045 * sin(index * 4.2 + 1.0);
			float arch_dist = abs(length(vec2(local.x * 0.85, (local.y - 0.98) * 0.8)) - arch_size);
			float thread = exp(-arch_dist / max(0.010, aa * 0.5)) * smoothstep(0.985, 1.035, local.y);
			arches += thread * (0.55 + 0.25 * sin(index + age * 0.3));
		}
		float outer_alpha = clamp(corona + arches * 0.68, 0.0, 0.9) * (1.0 - disc);
		vec3 outer_light = mix(vec3(0.98, 0.24, 0.035), vec3(1.0, 0.55, 0.15), clamp(arches, 0.0, 1.0));
		float total = opacity + outer_alpha;
		light = (light * opacity + outer_light * outer_alpha) / max(total, 0.0001);
		opacity = total;
	}
	COLOR = vec4(light * tint.rgb, opacity * tint.a);
}
