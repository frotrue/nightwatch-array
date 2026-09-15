shader_type canvas_item;
render_mode unshaded, blend_mix;

// Artistic emitting gas, not a predicted white-hole image. Inclined direct
// emission and a folded far-side image supply depth without volumetric marching.
// All flow comes from fixed-tick time. No texture generation or CPU particles.
uniform float visual_time = 0.0;
uniform float motion = 1.0;
uniform float pulses = 1.0;
uniform int effect_mode = 0;

float hash3(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}
float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1,0,0)), f.x),
                mix(hash3(i + vec3(0,1,0)), hash3(i + vec3(1,1,0)), f.x), f.y),
            mix(mix(hash3(i + vec3(0,0,1)), hash3(i + vec3(1,0,1)), f.x),
                mix(hash3(i + vec3(0,1,1)), hash3(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float turbulence(vec3 p) {
	return noise3(p) * 0.57 + noise3(p * 2.03 + 13.7) * 0.29
      + noise3(p * 4.11 - 6.8) * 0.14;
}
vec3 gas_colour(float heat) {
	// Reserve near-white for the small mouth; gas retains cool shadow and ivory detail.
	vec3 colour = mix(vec3(0.08,0.11,0.16), vec3(0.42,0.46,0.51), smoothstep(0.10,0.48,heat));
	return mix(colour, vec3(0.82,0.79,0.73), smoothstep(0.4,0.95,heat));
}
vec4 disc_light(vec2 p, float t, float inclination, float folded) {
	vec2 plane = vec2(p.x, p.y / inclination);
	float radius = length(plane);
	float angle = atan(plane.y,plane.x);
	float inner = 0.17;
	float radial_window = smoothstep(inner,inner + 0.055,radius) * (1.0 - smoothstep(0.43,0.76,radius));
	if (radial_window < 0.001) return vec4(0.0);
	// Advect patches outwards; differential rotation shears them into gas lanes.
	float shear = t * (0.18 + 0.027 / max(radius * radius,0.045));
	vec2 direction = vec2(cos(angle + shear),sin(angle + shear));
	float broad = turbulence(vec3(direction * 2.4, radius * 10.0 - t * 0.42));
	float lanes = turbulence(vec3(direction * 4.0, radius * 20.0 - t * 1.1 + broad * 4.5));
	float threads = noise3(vec3(direction * 9.0, radius * 42.0 - t * 1.8));
	float density = smoothstep(0.20,0.80,broad * 0.48 + lanes * 0.48 + threads * 0.04);
	float beaming = 0.48 + 0.60 * smoothstep(-0.8,0.85,-plane.x / max(radius,0.001));
	float heat = clamp(0.98 - radius * 0.93 + density * 0.20,0.0,1.0);
	float energy = radial_window * (0.10 + density * 0.82) * beaming;
	energy *= mix(1.0,0.72,folded);
	return vec4(gas_colour(heat),clamp(energy,0.0,0.94));
}
vec4 over(vec4 front, vec4 back) {
	float alpha = front.a + back.a * (1.0 - front.a);
	vec3 rgb = (front.rgb * front.a + back.rgb * back.a * (1.0 - front.a)) / max(alpha,0.0001);
	return vec4(rgb,alpha);
}
void fragment() {
	vec4 tint = COLOR;
	vec2 local = (UV - 0.5) * 2.0;
	float r = length(local);
	// Slow coherent motion reads as depth without a constantly erupting silhouette.
	float t = visual_time * 0.38;
	float aa = max(fwidth(r),0.002);
	// One persistent, slightly inclined axis; no camera-facing concentric rings.
	vec2 p = mat2(vec2(0.982,0.189),vec2(-0.189,0.982)) * local;
	vec2 direction = p / max(r,0.001);
	float cloud = turbulence(vec3(direction * 4.0, r * 9.5 - t * 0.43));
	float filament = turbulence(vec3(direction * 14.0, r * 30.0 - t * 1.03 + cloud * 2.0));
	float corona = exp(-max(r - 0.12,0.0) * 15.0) * (0.025 + pow(cloud,3.0) * 0.25);
	float wind = pow(smoothstep(0.33,0.75,filament),2.0) * exp(-max(r - 0.22,0.0) * 5.2);
	wind *= smoothstep(0.16,0.28,r) * (1.0 - smoothstep(0.48,0.78,r)) * motion;
	vec4 light = vec4(vec3(0.38,0.43,0.51),clamp(corona + wind * 0.045,0.0,0.3));
	float glow_radius = length(vec2(p.x,p.y / 0.34));
	float disc_glow = exp(-pow((glow_radius - 0.34) / 0.32,2.0)) * smoothstep(0.13,0.23,glow_radius) * (1.0 - smoothstep(0.55,0.94,glow_radius));
	light = over(vec4(vec3(0.55,0.59,0.65),disc_glow * 0.035),light);
	// A dim secondary folded image below, and the bright far side above the mouth.
	float folded_y = (abs(p.y) - 0.045) / 0.48;
	vec2 folded = vec2(p.x * 1.9,folded_y);
	vec4 far_side = disc_light(folded,t - 0.45,1.0,1.0);
	far_side.a *= smoothstep(0.025,0.14,abs(p.y)) * (p.y < 0.0 ? 0.64 : 0.12);
	light = over(far_side,light);
	// A graded radiance profile avoids a flat white button with a drawn outline.
	float edge_noise = (cloud - 0.5) * 0.008;
	float mouth = 1.0 - smoothstep(0.105 - aa + edge_noise,0.15 + aa + edge_noise,r);
	float blaze = exp(-r * r / 0.019) * 0.07;
	vec3 core_tint = mix(vec3(0.63,0.69,0.77),vec3(0.98,0.97,0.93),exp(-r * r / 0.009));
	light = over(vec4(core_tint,clamp(mouth + blaze,0.0,1.0)),light);
	// The near half crosses in front of the lower limb; the far half is occluded.
	vec4 direct = disc_light(p,t,0.23,0.0);
	direct.a *= p.y > 0.0 ? 1.0 : (1.0 - mouth);
	light = over(direct,light);
	// Scattered inner light spills into the gas, with no perfectly traced rim.
	float spill = exp(-r * r / 0.032) * (0.025 + cloud * 0.045);
	light.rgb = mix(light.rgb,vec3(1.0,0.98,0.91),spill);
	if (effect_mode == 1) {
		float along = abs(p.y);
		float width = 0.012 + along * 0.050;
		float wander = (noise3(vec3(along * 5.0 - t * 0.5,3.7,11.2)) - 0.5) * along * 0.042;
		float jet_profile = exp(-pow((p.x - wander) / width,2.0));
		float structure = turbulence(vec3(p.x * 64.0,along * 21.0 - t * 2.3,4.8));
		float jets = jet_profile * smoothstep(0.13,0.23,along) * (1.0 - smoothstep(0.38,0.65,along));
		jets *= (0.2 + structure * 0.8) * (p.y < 0.0 ? 0.33 : 0.20) * motion;
		light = over(vec4(mix(vec3(0.38,0.44,0.53),vec3(0.70,0.74,0.79),structure),jets),light);
	}
	float breath = 1.0 + sin(t * 0.8) * 0.005 * pulses * motion;
	light.a *= (1.0 - smoothstep(0.94,1.0,r));
	COLOR = vec4(clamp(light.rgb * breath,vec3(0.0),vec3(1.0)) * tint.rgb,clamp(light.a,0.0,1.0) * tint.a);
}
