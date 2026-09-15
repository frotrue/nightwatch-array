shader_type canvas_item;
render_mode unshaded;

uniform float phase = 0.0;
uniform float motion = 1.0;
uniform float pulses = 1.0;

void fragment() {
	vec4 tint = COLOR;
	vec2 p = (UV - 0.5) * 200.0;
	// Projection of a tilted magnetic axis around the fixed spin axis.
	vec3 axis = normalize(vec3(0.82 * cos(phase), 0.48, 0.82 * sin(phase)));
	vec2 projected = normalize(axis.xy);
	float along = dot(p, projected);
	float across = abs(p.x * projected.y - p.y * projected.x);
	float length_scale = 70.0 * length(axis.xy);
	float beam = exp(-pow(across / (1.4 + abs(along) * 0.045), 2.0));
	beam *= smoothstep(7.0, 16.0, abs(along)) * (1.0 - smoothstep(12.0, length_scale, abs(along)));
	float pulse = pow(abs(sin(phase)), 8.0) * pulses * motion;
	float r = length(p) / 9.0;
	float disk = 1.0 - smoothstep(0.92, 1.0, r);
	float depth = sqrt(max(0.0, 1.0 - r * r));
	float hot = exp(-length(p - axis.xy * 5.0) * 0.9);
	vec3 globe = mix(vec3(0.31, 0.44, 0.56), vec3(0.83, 0.91, 0.98), pow(depth, 0.65));
	globe += hot * 0.15 + pulse * 0.07;
	float halo = exp(-length(p) / 12.0) * 0.12;
	float beam_alpha = beam * 0.22 * motion;
	float alpha = max(disk, halo + beam_alpha);
	COLOR = vec4(mix(vec3(0.53, 0.68, 0.82), globe, disk) * tint.rgb, alpha * tint.a);
}
