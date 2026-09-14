shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D background : hint_screen_texture, repeat_disable, filter_linear;
uniform float age = 0.0;
uniform float phase = 0.0;
uniform float charge = 0.0;
uniform float strength = 1.0;
uniform float pixel_scale = 1.0;

void fragment() {
	vec2 p = (UV - 0.5) * 6.4;
	float r = length(p);
	// Keep the body clear; broad heat waves reach surrounding stars and trails.
	float mask = smoothstep(0.98, 1.10, r) * (1.0 - smoothstep(1.65, 3.0, r));
	float t = age * 1.8;
	vec2 flow = vec2(
		sin(p.y * 4.5 - t * 1.2 + sin(p.x * 3.0 + t) + phase),
		cos(p.x * 4.0 - t + sin(p.y * 2.5 - t * 0.8) + phase));
	flow += normalize(p + vec2(0.0001)) * sin(r * 12.0 - t * 2.3 + phase) * 0.25;
	vec2 offset = flow * SCREEN_PIXEL_SIZE * (5.0 + charge * 4.0) * pixel_scale * mask * strength;
	// Fade displacement, not opacity: otherwise a sharp duplicate of each
	// meteor shows through underneath the refracted image.
	if (mask > 0.0) {
		COLOR = vec4(textureLod(background, clamp(SCREEN_UV + offset, SCREEN_PIXEL_SIZE, 1.0 - SCREEN_PIXEL_SIZE), 0.0).rgb, 1.0);
	} else {
		COLOR = vec4(0.0);
	}
}
