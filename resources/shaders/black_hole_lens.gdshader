shader_type canvas_item;
render_mode unshaded;

// One background copy is shared by the local lens. Foreground targets and HUD
// are drawn later and retain their exact visible/interactive positions.
uniform sampler2D background : hint_screen_texture, repeat_disable, filter_linear;
uniform vec2 screen_extent = vec2(0.08, 0.14);
uniform float visibility : hint_range(0.0, 1.0) = 1.0;
uniform float strength : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float mask = (1.0 - smoothstep(0.72, 1.0, r)) * smoothstep(0.18, 0.25, r);
	float bend = 0.19 * exp(-pow((r - 0.38) / 0.19, 2.0));
	vec2 source_uv = SCREEN_UV - p / max(r, 0.001) * bend * screen_extent * strength;
	vec3 warped = textureLod(background, clamp(source_uv, vec2(0.0), vec2(1.0)), 0.0).rgb;
	COLOR = vec4(warped, mask * visibility);
}
