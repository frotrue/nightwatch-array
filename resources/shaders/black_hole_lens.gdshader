shader_type canvas_item;
render_mode unshaded;

// Copy the sky and ordinary meteors once, before the black hole and HUD.
uniform sampler2D background : hint_screen_texture, repeat_disable, filter_linear;
uniform vec2 screen_extent = vec2(0.08, 0.14);
uniform float visibility : hint_range(0.0, 1.0) = 1.0;
uniform float strength : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float mask = 1.0 - smoothstep(0.98, 1.0, r);
	// Radial inverse-distance deflection stretches nearby stars around the
	// silhouette. Taper to zero locally instead of warping the whole sky.
	float bend = 0.145 / max(r, 0.33) * (1.0 - smoothstep(0.55, 1.0, r));
	vec2 source_uv = SCREEN_UV - p / max(r, 0.001) * bend * screen_extent * strength * visibility;
	vec3 warped = textureLod(background, clamp(source_uv, vec2(0.0), vec2(1.0)), 0.0).rgb;
	COLOR = vec4(warped, mask);
}
