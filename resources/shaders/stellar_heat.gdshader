shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D background : hint_screen_texture, repeat_disable, filter_linear;
uniform float age = 0.0;
uniform float phase = 0.0;
uniform float charge = 0.0;
uniform float strength = 1.0;
uniform float pixel_scale = 1.0;

void fragment() {
	vec2 p = (UV - 0.5) * 3.6;
	float r = length(p);
	// Keep distortion outside the opaque body, and taper before the local copy
	// boundary. The displacement is tiny enough to keep nearby targets readable.
	float mask = smoothstep(0.95, 1.06, r) * (1.0 - smoothstep(1.20, 1.72, r));
	float t = age * 1.8;
	vec2 flow = vec2(
		sin(p.y * 13.0 - t * 1.7 + sin(p.x * 9.0 + t) + phase),
		cos(p.x * 12.0 - t * 1.3 + sin(p.y * 7.0 - t * 0.8) + phase));
	flow += normalize(p + vec2(0.0001)) * sin(r * 21.0 - t * 2.3 + phase) * 0.35;
	vec2 offset = flow * SCREEN_PIXEL_SIZE * (1.2 + charge * 1.1) * pixel_scale * mask * strength;
	COLOR = vec4(textureLod(background, clamp(SCREEN_UV + offset, SCREEN_PIXEL_SIZE, 1.0 - SCREEN_PIXEL_SIZE), 0.0).rgb, mask);
}
