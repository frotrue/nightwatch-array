shader_type canvas_item;
render_mode unshaded, blend_mix;

// Local emission only: no screen texture, backdrop warp or extra screen copy.
// Age comes from the fixed tick, so pause and deterministic captures agree.
uniform float visual_time = 0.0;
uniform float motion = 1.0;
uniform float pulses = 1.0;
uniform int effect_mode = 0;

float hash1(float x) {
	return fract(sin(x * 127.1 + 31.7) * 43758.5453);
}

void fragment() {
	vec4 tint = COLOR;
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float aa = max(fwidth(r), 0.002);
	float angle = atan(p.y, p.x);
	float t = visual_time;
	float core = 1.0 - smoothstep(0.16 - aa, 0.16 + aa, r);
	float rim = exp(-pow((r - 0.176) / 0.017, 2.0));
	float halo = exp(-max(r - 0.18, 0.0) * 12.0) * 0.23;
	float outflow = 0.0;
	float ring_light = 0.0;
	if (effect_mode == 0) {
		// Fronts move monotonically away from the white mouth. Fade both ends
		// of each cycle so a new front never flashes into view at the rim.
		for (int i = 0; i < 3; i++) {
			float phase = fract(t * 0.27 + float(i) / 3.0);
			float radius = 0.21 + phase * 0.72;
			float envelope = smoothstep(0.0, 0.13, phase) * (1.0 - smoothstep(0.55, 1.0, phase));
			float ripple = sin(angle * 5.0 + float(i) * 2.1) * 0.005 * phase;
			float front = exp(-pow((r - radius - ripple) / (0.006 + phase * 0.009 + aa), 2.0));
			ring_light += front * envelope * 0.34;
		}
	} else {
		// Two broad, tapered emission cones offer a second silhouette to compare.
		vec2 axis = vec2(0.32, -0.9474);
		float along = abs(dot(p, axis));
		float across = abs(dot(p, vec2(-axis.y, axis.x)));
		float cone = exp(-pow(across / (0.025 + along * 0.095), 2.0));
		float envelope = smoothstep(0.15, 0.25, along) * (1.0 - smoothstep(0.45, 0.94, along));
		float knots = 0.68 + 0.32 * sin(along * 29.0 - t * 4.2);
		outflow = cone * envelope * knots * 0.72;
	}
	// One analytic streak per angular sector: bounded cost, no particle nodes,
	// random-number consumption or per-frame CPU geometry allocations.
	float sector = floor((angle + 3.14159265) * 7.63943727);
	float seed = hash1(sector);
	float centre_angle = -3.14159265 + (sector + 0.25 + seed * 0.5) / 7.63943727;
	float phase = fract(t * (0.23 + seed * 0.18) + hash1(sector + 71.0));
	float distance_out = 0.20 + phase * 0.76;
	float angular_mask = exp(-pow((angle - centre_angle) * max(r, 0.2) / 0.0045, 2.0));
	float trail = smoothstep(-0.075, -0.005, r - distance_out) * (1.0 - smoothstep(0.0, 0.012, r - distance_out));
	float particles = angular_mask * trail * smoothstep(0.0, 0.13, phase) * (1.0 - smoothstep(0.55, 1.0, phase));
	if (effect_mode == 1) particles *= pow(abs(dot(p / max(r, 0.001), vec2(0.32, -0.9474))), 10.0);
	float animated = (ring_light + outflow + particles * 0.65) * motion;
	float breath = 1.0 + sin(t * 1.1) * 0.025 * motion * pulses;
	float opacity = max(core, (rim * 0.76 + halo + animated) * breath);
	opacity *= 1.0 - smoothstep(0.94, 1.0, r);
	vec3 colour = mix(vec3(0.40, 0.78, 1.0), vec3(0.96, 0.99, 1.0), max(core, particles * 0.8));
	COLOR = vec4(colour * tint.rgb, clamp(opacity, 0.0, 1.0) * tint.a);
}
