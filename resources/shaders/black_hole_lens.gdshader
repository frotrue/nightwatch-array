shader_type canvas_item;
render_mode unshaded;

// Copy the sky and ordinary meteors once, before the black hole and HUD.
uniform sampler2D background : hint_screen_texture, repeat_disable, filter_linear;
uniform vec2 screen_extent = vec2(0.08, 0.14);
uniform float visibility : hint_range(0.0, 1.0) = 1.0;
uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform float einstein_radius = 0.34;
uniform float taper_start = 0.6;

vec3 lensed_light(vec2 p, vec2 screen_uv, float amount) {
	float r = length(p);
	// Point-mass thin-lens equation beta = theta - theta_E^2 / theta.
	// Its signed source radius also produces the inverted secondary image.
	// Keep that image outside the opaque shadow; taper only in the far field.
	float bend = einstein_radius * einstein_radius / max(r, 0.12)
		* (1.0 - smoothstep(taper_start, 1.0, r));
	vec2 source_uv = screen_uv - p / max(r, 0.001) * bend * screen_extent * amount;
	return textureLod(background, clamp(source_uv, vec2(0.0), vec2(1.0)), 0.0).rgb;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float mask = 1.0 - smoothstep(0.98, 1.0, r);
	float amount = strength * visibility;
	vec3 warped;
	if (r < taper_start && amount > 0.001) {
		// Four subpixel rays preserve tiny stars and thin meteor arcs at the
		// critical curve. Work remains confined to this single local quad.
		vec2 pixel = SCREEN_PIXEL_SIZE * 0.25;
		vec2 local_pixel = pixel / screen_extent;
		warped = (lensed_light(p + local_pixel, SCREEN_UV + pixel, amount)
			+ lensed_light(p - local_pixel, SCREEN_UV - pixel, amount)
			+ lensed_light(p + local_pixel * vec2(1.0, -1.0), SCREEN_UV + pixel * vec2(1.0, -1.0), amount)
			+ lensed_light(p + local_pixel * vec2(-1.0, 1.0), SCREEN_UV + pixel * vec2(-1.0, 1.0), amount)) * 0.25;
	} else {
		warped = lensed_light(p, SCREEN_UV, amount);
	}
	COLOR = vec4(warped, mask);
}
