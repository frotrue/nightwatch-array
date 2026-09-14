shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform float age = 0.0;
uniform float phase = 0.0;
uniform float charge = 0.0;
uniform float completion = 0.0;
uniform float motion = 1.0;
uniform float flashes = 1.0;
uniform vec4 primary : source_color = vec4(0.72, 0.63, 0.51, 1.0);
uniform vec4 glow : source_color = vec4(0.89, 0.78, 0.63, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
		mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float clouds(vec2 p) {
	return noise(p) * 0.56 + noise(p * 2.03 + 8.3) * 0.28
		+ noise(p * 4.07 + 17.6) * 0.16;
}

void fragment() {
	vec4 tint = COLOR;
	vec2 p = (UV - 0.5) * 2.08;
	float r = length(p);
	float aa = max(fwidth(r), 0.002);
	float disc = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, r);
	vec3 color = vec3(0.0);
	if (r < 1.0 + aa) {
		float z = sqrt(max(0.0, 1.0 - dot(p, p)));
		float latitude = asin(clamp(p.y, -1.0, 1.0));
		float longitude = atan(p.x, max(z, 0.0001));
		// Differential rotation shears cloud filaments between latitude belts.
		float wind = age * (0.12 + 0.025 * sin(latitude * 11.0));
		vec2 air = vec2(longitude + wind + phase, latitude * 2.7);
		float turbulence = clouds(air * vec2(3.0, 4.0) + vec2(0.0, age * 0.025));
		float belt = sin(latitude * 21.0 + turbulence * 2.8);
		float fine = clouds(air * vec2(10.0, 20.0) + turbulence);
		float strands = sin(latitude * 86.0 + turbulence * 6.0 + fine * 2.0);
		vec3 dark_belt = primary.rgb * vec3(0.64, 0.52, 0.42);
		vec3 pale_cloud = mix(glow.rgb, vec3(0.96, 0.88, 0.72), 0.28);
		color = mix(dark_belt, pale_cloud, smoothstep(-0.8, 0.85, belt));
		color *= 0.83 + fine * 0.23 + strands * (0.04 + charge * 0.025);
		// A slowly turning oval storm stays attached to the rotating globe.
		float storm_lon = longitude + age * 0.11 + phase * 0.25 - 0.50;
		storm_lon = atan(sin(storm_lon), cos(storm_lon));
		vec2 storm = vec2(storm_lon / 0.32, (latitude - 0.24) / 0.14);
		float storm_r = length(storm);
		float curl = sin(storm_r * 13.0 - atan(storm.y, storm.x) * 2.0 - age * 0.75);
		float storm_mask = 1.0 - smoothstep(0.65, 1.40, storm_r);
		vec3 storm_color = mix(primary.rgb * vec3(0.91, 0.55, 0.36), pale_cloud, curl * 0.20 + 0.33);
		color = mix(color, storm_color, storm_mask * 0.86);
		vec3 normal = normalize(vec3(p, z));
		float light = max(dot(normal, normalize(vec3(-0.48, -0.36, 0.83))), 0.0);
		color *= 0.13 + pow(light, 0.80) * 0.94;
		// The observation reveal belongs to the material, within the limb.
		color += pale_cloud * pow(z, 0.5) * fine * charge * 0.035;
		float sweep = exp(-pow((p.x - mix(-1.15, 1.15, completion)) * 9.0, 2.0));
		color += glow.rgb * sweep * sin(completion * 3.14159265) * 0.38 * flashes * motion;
		color += glow.rgb * pow(1.0 - z, 7.0) * light * 0.12;
	}
	COLOR = vec4(color * tint.rgb, disc * tint.a);
}
