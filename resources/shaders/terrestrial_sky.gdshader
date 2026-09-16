shader_type canvas_item;
render_mode unshaded;

uniform float dawn = 0.0;
uniform float sunrise = 0.0;

void fragment() {
	vec4 painted = texture(TEXTURE, UV);
	float height = smoothstep(0.1, 0.84, UV.y);
	// The approved ridges have blue below 0.34; the horizon sky is above 0.48.
	// Follow that painted edge instead of cutting the dawn into a horizontal band.
	float sky = mix(1.0, smoothstep(0.34, 0.48, painted.b), smoothstep(0.70, 0.81, UV.y));
	vec3 dawn_color = mix(vec3(0.10, 0.12, 0.22), vec3(0.64, 0.38, 0.32), height);
	vec3 morning = mix(vec3(0.21, 0.27, 0.39), vec3(0.88, 0.63, 0.46), height);
	vec3 color = mix(painted.rgb, dawn_color, dawn * mix(0.18, 0.60, height) * sky);
	color = mix(color, morning, sunrise * mix(0.25, 0.72, height) * sky);
	COLOR = vec4(color, painted.a);
}
