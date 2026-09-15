shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform float radius = 40.0;
uniform float rotation_phase = 0.0;
uniform float age = 0.0;
uniform float phase = 0.0;
uniform float charge = 0.0;
uniform float icy = 0.0;
uniform float flashes = 1.0;
uniform float completion = 0.0;
varying vec2 local_position;

float hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

vec3 crystal_cell(vec2 p) {
	vec2 cell = floor(p);
	vec2 local = fract(p);
	float nearest = 8.0, second = 8.0, identity = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 offset = vec2(float(x), float(y));
			vec2 seed = vec2(hash(cell + offset), hash(cell + offset + 19.7));
			float d = length(offset + seed * 0.7 + 0.15 - local);
			if (d < nearest) { second = nearest; nearest = d; identity = seed.x; }
			else { second = min(second, d); }
		}
	}
	return vec3(nearest, second - nearest, identity);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
		mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float crater_relief(vec2 q, vec3 crater, vec2 local_light) {
	vec2 offset = (q - crater.xy) / crater.z;
	float r = length(offset) * (0.95 + noise(q * 22.0 + phase) * 0.10);
	float basin = 1.0 - smoothstep(0.12, 0.87, r);
	float wall = exp(-pow((r - 0.72) / 0.22, 2.0));
	float rim = exp(-pow((r - 1.0) / 0.10, 2.0));
	float facing = dot(offset / max(length(offset), 0.01), local_light);
	return -basin * 0.30 - wall * facing * 0.16 + rim * (0.06 + facing * 0.11);
}

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	vec4 face = COLOR;
	// Fragment UVs retain the original surface, so markings stay on each chunk.
	vec2 p = completion > 0.0 ? (UV - 0.5) * 2.0 : local_position / max(radius, 0.01);
	float c = cos(rotation_phase);
	float s = sin(rotation_phase);
	vec2 q = mat2(vec2(c, -s), vec2(s, c)) * p;
	float coarse = noise(q * 5.0 + phase);
	float grain = noise(q * 38.0 + phase);
	vec2 rounded = p / vec2(0.96, 0.86);
	float z = sqrt(max(0.0, 1.0 - dot(rounded, rounded)));
	vec3 normal = normalize(vec3(rounded, z + 0.12));
	vec3 light_direction = normalize(vec3(-0.65, -0.46, 0.72));
	float light = max(0.0, dot(normal, light_direction));
	float roughness = noise(q * 13.0 + coarse * 1.4);
	vec3 color;
	if (icy < 0.5) {
		vec2 local_light = mat2(vec2(c, -s), vec2(s, c)) * normalize(light_direction.xy);
		float relief = crater_relief(q, vec3(-0.32, -0.19, 0.16), local_light)
			+ crater_relief(q, vec3(0.30, 0.10, 0.21), local_light)
			+ crater_relief(q, vec3(-0.13, 0.40, 0.10), local_light);
		float grit = (grain - 0.5) * 0.13 + (roughness - 0.5) * 0.19;
		float mineral = smoothstep(0.61, 0.86, coarse) * 0.13;
		float diffuse = 0.14 + pow(light, 0.82) * 0.80;
		color = face.rgb * max(0.045, diffuse + relief + grit * (0.60 + charge * 0.40) + mineral);
	} else {
		// Frost and embedded fractures share a volume instead of a fan of glass triangles.
		vec2 parallax = vec2(sin(age * 0.24 + phase), cos(age * 0.19)) * 0.045;
		float inner = noise((q + parallax) * 7.0 + phase);
		vec3 crystal = crystal_cell((q - parallax * 0.45) * 3.5 + phase);
		float fracture = 1.0 - smoothstep(0.012, 0.055, crystal.y);
		float frost = smoothstep(0.36, 0.70, coarse * 0.72 + grain * 0.28);
		float facet = mix(0.81, 1.10, crystal.z);
		float diffuse = (0.21 + pow(light, 0.70) * 0.72) * facet;
		color = face.rgb * mix(vec3(0.29, 0.57, 0.73), vec3(0.94, 1.02, 1.04), frost * 0.65 + inner * 0.35) * diffuse;
		color *= 1.0 - fracture * 0.20;
		color += face.rgb * fracture * (0.055 + charge * 0.12) * light;
		vec3 facet_normal = normalize(normal + vec3(crystal.z - 0.5, roughness - 0.5, 0.0) * 0.28);
		float specular = pow(max(dot(facet_normal, normalize(light_direction + vec3(0, 0, 1))), 0.0), 34.0);
		color += face.rgb * specular * (0.14 + frost * 0.14) * flashes;
		color += face.rgb * pow(1.0 - z, 3.0) * light * 0.09;
		color += face.rgb * sin(completion * 3.14159265) * fracture * 0.15 * flashes;
	}
	COLOR = vec4(clamp(color, vec3(0.0), vec3(1.0)), face.a);
}
