shader_type canvas_item;
render_mode unshaded;

uniform float phase = 0.0;
uniform float motion = 1.0;
uniform float pulses = 1.0;
uniform float emergence = 0.0;
uniform vec3 magnetic_axis = vec3(0.86, 0.5, 0.0);
uniform float beam_length = 150.0;
uniform float release = 0.0;

void fragment() {
	vec4 tint = COLOR;
	vec2 p = (UV - 0.5) * 480.0;
	// Projection of a tilted magnetic axis around the fixed spin axis.
	vec3 axis = magnetic_axis;
	vec2 projected = normalize(axis.xy);
	float along = dot(p, projected);
	float across = abs(p.x * projected.y - p.y * projected.x);
	float distance_along = abs(along);
	float length_scale = beam_length * length(axis.xy);
	float envelope = smoothstep(7.0, 15.0, distance_along)
		* (1.0 - smoothstep(length_scale * 0.2, length_scale, distance_along));
	float spine = exp(-pow(across / (1.25 + distance_along * 0.018), 2.0));
	float sheath = exp(-pow(across / (4.0 + distance_along * 0.075), 2.0));
	// Broad, shallow flow inside each pole makes the rotation readable without sparks.
	float stream = 0.88 + 0.12 * sin(distance_along * 0.14 - phase * 4.0) * motion * pulses;
	float pulse = pow(abs(sin(phase)), 8.0) * pulses * motion;
	float arrival = emergence * pulses * motion;
	float beam_alpha = (spine * 0.65 + sheath * 0.25) * envelope * stream * motion;
	beam_alpha *= 1.0 + pulse * 0.3 + arrival * 0.4 + release * 0.3;
	float r = length(p) / 9.5;
	float disk = 1.0 - smoothstep(0.92, 1.0, r);
	float depth = sqrt(max(0.0, 1.0 - r * r));
	float hot = exp(-length(p - axis.xy * 5.0) * 0.6);
	vec3 globe = mix(vec3(0.26, 0.42, 0.58), vec3(0.87, 0.95, 1.0), pow(depth, 0.65));
	globe += hot * 0.22 + pulse * 0.15 + arrival * 0.18;
	float halo = exp(-length(p) / 20.0) * (0.24 + pulse * 0.38 + arrival * 0.42);
	float core_glint = exp(-pow(length(p) / 15.0, 2.0)) * (pulse * 0.2 + arrival * 0.3);
	float alpha = clamp(max(disk, halo + beam_alpha + core_glint), 0.0, 1.0);
	vec3 emission = mix(vec3(0.42, 0.65, 0.85), vec3(0.85, 0.94, 1.0), spine);
	COLOR = vec4(mix(emission, globe, disk) * tint.rgb, alpha * tint.a);
}
