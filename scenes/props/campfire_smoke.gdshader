// Big soft smoke plume on a single Y-billboarded quad (UV: y 0 top .. 1 bottom).
// Billowing fbm, soft alpha, widens and dissipates with height, drifts with the
// global wind. No pixel cells: the retro pipeline provides the pixelation.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, skip_vertex_transform;

global uniform vec2 wind_direction;
global uniform float wind_strength;

uniform float rise_speed : hint_range(0.05, 2.0, 0.05) = 0.35;
uniform float sway : hint_range(0.0, 1.0, 0.05) = 0.25;
// How much the plume leans downwind at wind strength 1.
uniform float wind_drift : hint_range(0.0, 2.0, 0.05) = 0.7;
uniform vec4 smoke_color : source_color = vec4(0.62, 0.62, 0.65, 1.0);
uniform vec4 smoke_color_dark : source_color = vec4(0.32, 0.32, 0.36, 1.0);
uniform float density : hint_range(0.0, 1.0, 0.05) = 0.55;

varying float v_wind_x;  // wind projected on the billboard's horizontal axis

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), f.x),
			mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.55;
	for (int i = 0; i < 4; i++) {
		v += vnoise(p) * a;
		p = p * 2.05 + vec2(11.3, 5.1);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 cam_right = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z));
	vec3 world = origin + cam_right * VERTEX.x + vec3(0.0, VERTEX.y, 0.0);
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	v_wind_x = dot(vec3(wind_direction.x, 0.0, wind_direction.y), cam_right);
}

void fragment() {
	float phase = fract(dot(NODE_POSITION_WORLD.xz, vec2(0.53, 0.771))) * 23.0;
	float up = 1.0 - UV.y;   // 0 bottom .. 1 top
	float x = (UV.x - 0.5) * 2.0;

	// The column bends with the wind and meanders slowly.
	float bend = v_wind_x * wind_strength * wind_drift * up * up
			+ sin(TIME * 0.5 + up * 2.2 + phase) * sway * up;
	float xw = x - bend;

	// Plume: narrow at the base, ballooning upward.
	float width = 0.16 + up * 0.75;
	float edge = 1.0 - abs(xw) / max(width, 0.001);

	// Billowing interior.
	float n = fbm(vec2(xw * 1.4 + phase, up * 2.0 - TIME * rise_speed));
	float d = edge * (0.55 + n * 0.75) - 0.35;
	// Fade in at the very base, dissipate towards the top.
	d *= smoothstep(0.0, 0.08, up) * (1.0 - smoothstep(0.45, 1.0, up) * 0.85);

	float a = clamp(d, 0.0, 1.0) * density;
	if (a <= 0.003) {
		discard;
	}
	ALBEDO = mix(smoke_color_dark.rgb, smoke_color.rgb, clamp(n * 1.2, 0.0, 1.0));
	ALPHA = a;
}
