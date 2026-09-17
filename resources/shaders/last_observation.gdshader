shader_type canvas_item;
render_mode unshaded;

uniform sampler2D sky : source_color, filter_linear_mipmap, repeat_disable;
uniform float aspect = 1.777778;
uniform float clock = 0.0;
uniform float presence = 0.0;
uniform float charge = 0.0;
uniform float collapse = 0.0;
uniform float blackout = 0.0;
uniform float motion = 1.0;
uniform float flare = 1.0;
uniform float horizon_radius = 0.005;
uniform float camera_dive = 0.0;
uniform float camera_zoom = 1.0;
uniform float camera_roll = 0.0;
uniform vec2 camera_offset = vec2(0.0);
uniform float camera_rush = 0.0;
uniform float camera_crossing = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}
float clouds(vec2 p) {
	float v = 0.0, a = 0.55;
	for (int i = 0; i < 4; i++) { v += noise(p) * a; p = p * 2.03 + vec2(3.1, 8.7); a *= 0.47; }
	return v;
}
vec2 rotate(vec2 p, float a) { return mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * p; }
vec2 sky_uv(vec2 p) {
	vec2 cover = vec2(max(1.0, 1.777778 / aspect), max(1.0, aspect / 1.777778)) * 1.04;
	return (p - 0.5) / cover + 0.5;
}

void fragment() {
	vec2 screen_p = (UV - vec2(0.5, 0.465)) * vec2(aspect, 1.0);
	vec2 p = rotate(screen_p, -camera_roll) / camera_zoom + camera_offset;
	float r = length(p), angle = atan(p.y, p.x);
	float radius = horizon_radius;
	float gravity = presence * (0.013 + charge * 0.012 + collapse * 0.10) * motion;
	float pull = gravity / max(r, 0.055) * (1.0 - smoothstep(0.15, 1.25, r));
	// The distant sky moves more slowly than the horizon and nearby light flecks.
	vec2 far_p = rotate(screen_p, -camera_roll * 0.72) / mix(1.0, max(1.0, camera_zoom), 0.14) + camera_offset * 0.4;
	vec2 warped = rotate(far_p * (1.0 - pull), collapse * 1.7 * motion / (1.0 + r * 4.0));
	vec2 uv = warped / vec2(aspect, 1.0) + vec2(0.5, 0.465);
	// Radial exposure trails reveal speed while the view is still outside the
	// horizon. Nearby retained flecks use actual earlier camera poses as well.
	vec2 streak = normalize(far_p + vec2(0.0001)) * camera_rush * 0.10 / vec2(aspect, 1.0);
	vec3 background = texture(sky, sky_uv(clamp(uv, vec2(0.001), vec2(0.999)))).rgb * 0.46;
	background += texture(sky, sky_uv(clamp(uv + streak * 0.33, vec2(0.001), vec2(0.999)))).rgb * 0.26;
	background += texture(sky, sky_uv(clamp(uv + streak * 0.67, vec2(0.001), vec2(0.999)))).rgb * 0.17;
	background += texture(sky, sky_uv(clamp(uv + streak, vec2(0.001), vec2(0.999)))).rgb * 0.11;
	vec3 color = background * mix(0.5, 0.28, smoothstep(0.0, 0.55, collapse) * motion);
	// Refracted background light travels around the horizon; the core stays opaque.
	float critical = exp(-pow((r - radius * 1.11) / max(radius * 0.12, 0.001), 2.0));
	vec2 echo = vec2(cos(angle + clock * 0.011 * motion), sin(angle + clock * 0.011 * motion));
	vec3 rim_sky = texture(sky, sky_uv(vec2(0.5) + echo * vec2(0.25, 0.43))).rgb;
	color += rim_sky * critical * presence * 0.58;
	float haze = exp(-max(r - radius, 0.0) * 9.0) * smoothstep(radius * 0.9, radius * 1.7, r);
	color += vec3(0.12, 0.15, 0.23) * haze * presence * (0.4 + charge);
	// A tilted, textured accretion disc, with a lensed arc above and below.
	vec2 disc = rotate(p, -0.23);
	vec2 ellipse = vec2(disc.x, disc.y * 4.8);
	float er = length(ellipse);
	float ea = atan(ellipse.y, ellipse.x);
	float radial = exp(-pow((er - radius * 1.9) / max(radius * 0.70, 0.001), 2.0));
	float bands = 0.38 + 0.62 * clouds(vec2(er * 130.0 + clouds(ellipse * 18.0) * 5.0, ea * 4.0 - clock * 0.05 * motion));
	float dust = clouds(vec2(ea * 4.0 + clock * 0.03 * motion, er * 38.0));
	float disc_light = radial * bands * (0.25 + dust) * presence * (0.20 + charge * 0.8 + collapse * 1.2);
	float asymmetric = mix(0.45, 1.3, smoothstep(-radius * 2.2, radius * 2.2, disc.x));
	vec3 disc_color = mix(vec3(0.38, 0.48, 0.65), vec3(0.95, 0.76, 0.54), dust);
	float shadow = 1.0 - smoothstep(radius * 0.97, radius * 1.015, r);
	color *= 1.0 - shadow * presence;
	float front = smoothstep(-0.008, 0.024, disc.y);
	color += disc_color * disc_light * asymmetric * mix(1.0 - shadow, 1.0, front);
	float photon = exp(-abs(r - radius * 1.03) / max(radius * 0.018, 0.001));
	color += vec3(0.80, 0.86, 0.94) * photon * presence * (0.15 + charge * 0.32);
	// The late polar emission grows slowly; no periodic flash or strobe.
	float jet_growth = smoothstep(0.40, 1.0, charge) + collapse * 1.15;
	float jet_width = 0.012 + abs(disc.y) * 0.075;
	float jet = exp(-pow(disc.x / jet_width, 2.0)) * exp(-abs(disc.y) * 2.0);
	jet *= smoothstep(radius * 0.65, radius * 1.4, abs(disc.y));
	jet *= 0.65 + 0.35 * clouds(vec2(disc.x * 110.0, disc.y * 26.0 - clock * 0.10 * motion));
	color += vec3(0.50, 0.68, 0.97) * jet * jet_growth * 0.75;
	float eruption = mix(smoothstep(0.36, 0.78, collapse), smoothstep(0.04, 0.7, camera_rush), motion);
	float glow = exp(-r * mix(4.0, 0.38, eruption));
	float core_opacity = max(1.0 - smoothstep(0.70, 0.96, collapse), smoothstep(0.12, 0.48, camera_dive));
	float engulf_core = 1.0 - shadow * core_opacity;
	color += vec3(0.64, 0.73, 0.89) * eruption * glow * mix(0.10, 1.05, flare) * engulf_core;
	color *= 1.0 - smoothstep(0.65, 1.0, length(screen_p)) * 0.5;
	// Passing the horizon lets the remaining foreground disc fall out of view.
	color *= 1.0 - camera_crossing;
	color *= 1.0 - blackout;
	COLOR = vec4(color, 1.0);
}
