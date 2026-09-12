shader_type canvas_item;
render_mode unshaded, blend_add;

// Data masks, not sRGB albedo. Each cell stores glow/core/hotspot contributions.
uniform sampler2D head_atlas : filter_linear, repeat_disable;
uniform vec3 primary_ink = vec3(1.0);
varying vec4 tint;
varying vec3 glow;
varying float frame;
varying float kind;

void vertex() {
	tint = COLOR;
	glow = INSTANCE_CUSTOM.rgb;
	// Signed type encoding cannot jump to the neighboring type when OpenGL
	// quantizes a phase just below 64 to float16's exact 64.
	kind = INSTANCE_CUSTOM.a < 0.0 ? 64.0 : 0.0;
	frame = min(INSTANCE_CUSTOM.a < 0.0 ? -INSTANCE_CUSTOM.a - 1.0 : INSTANCE_CUSTOM.a, 63.999);
}

vec3 sample_frame(float index, vec2 uv) {
	vec2 cell = vec2(mod(index, 8.0), floor(index / 8.0));
	return texture(head_atlas, (cell + uv) / vec2(8.0, 16.0)).rgb;
}

void fragment() {
	float first = floor(frame);
	float next = mod(first + 1.0, 64.0);
	vec3 weights = mix(sample_frame(kind + first, UV), sample_frame(kind + next, UV), fract(frame));
	vec3 light = weights.r * glow
		+ weights.g * mix(primary_ink, vec3(1.0), 0.18)
		+ weights.b * mix(primary_ink, vec3(1.0), 0.76);
	COLOR = vec4(light * tint.rgb, tint.a);
}
