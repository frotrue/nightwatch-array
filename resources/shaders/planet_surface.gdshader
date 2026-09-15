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
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
		mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float clouds(vec2 p) {
	p += vec2(noise(p * 0.45 + 11.0), noise(p * 0.45 - 7.0)) * 0.65;
	mat2 turn = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	return noise(p) * 0.56 + noise(turn * p * 2.03 + 8.3) * 0.28
		+ noise(turn * p * 4.07 + 17.6) * 0.16;
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
		float tilt = 0.12 + sin(phase) * 0.12;
		vec2 tilted = mat2(vec2(cos(tilt), -sin(tilt)), vec2(sin(tilt), cos(tilt))) * p;
		float latitude = asin(clamp(tilted.y, -1.0, 1.0));
		float longitude = atan(tilted.x, max(z, 0.0001));
		// Differential rotation shears cloud filaments between latitude belts.
		float wind = age * (0.16 + 0.035 * sin(latitude * 8.0));
		vec2 air = vec2(longitude + wind + phase, latitude * 2.7);
		float turbulence = clouds(air * vec2(2.2, 3.0) + vec2(0.0, age * 0.025));
		float belt = sin(latitude * 15.0 + (turbulence - 0.5) * 3.0);
		float fine = clouds(air * vec2(5.0, 17.0) + turbulence);
		float strands = clouds(air * vec2(9.0, 36.0) + fine * 1.4);
		vec3 dark_belt = primary.rgb * vec3(0.62, 0.48, 0.36);
		vec3 pale_cloud = mix(glow.rgb, vec3(0.93, 0.89, 0.79), 0.40);
		color = mix(dark_belt, pale_cloud, smoothstep(-0.65, 0.72, belt + (fine - 0.5) * 1.25));
		color *= 0.86 + fine * 0.21 + (strands - 0.5) * (0.18 + charge * 0.06);
		// A slowly turning oval storm stays attached to the rotating globe.
		float storm_lon = longitude + age * 0.11 + phase * 0.25 - 0.50;
		storm_lon = atan(sin(storm_lon), cos(storm_lon));
		vec2 storm = vec2(storm_lon / 0.34, (latitude - 0.24) / 0.17);
		float storm_r = length(storm);
		float swirl = atan(storm.y, storm.x) - exp(-storm_r * 0.8) * 3.8 - age * 0.3;
		float curl = clouds(vec2(cos(swirl), sin(swirl)) * storm_r * 4.5 + phase);
		float storm_mask = 1.0 - smoothstep(0.62, 1.42, storm_r + (curl - 0.5) * 0.18);
		vec3 storm_color = mix(primary.rgb * vec3(0.88, 0.47, 0.30), pale_cloud, smoothstep(0.28, 0.80, curl));
		color = mix(color, storm_color, storm_mask * 0.82);
		vec3 normal = normalize(vec3(p, z));
		float light = max(dot(normal, normalize(vec3(-0.68, -0.30, 0.66))), 0.0);
		color *= 0.08 + pow(light, 0.80) * 0.94;
		// The observation reveal belongs to the material, within the limb.
		color += pale_cloud * pow(z, 0.5) * fine * charge * 0.035;
		float sweep = exp(-pow((longitude / 1.57 - mix(-1.15, 1.15, completion)) * 5.0, 2.0));
		color += glow.rgb * sweep * sin(completion * 3.14159265) * (0.16 + z * 0.20) * flashes * motion;
		color += glow.rgb * pow(1.0 - z, 7.0) * light * 0.12;
	}
	COLOR = vec4(color * tint.rgb, disc * tint.a);
}
