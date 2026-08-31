// Smooth "realistic" flame on a single Y-billboarded quad (UV: y 0 top .. 1 bottom).
// Continuous fbm noise, soft colour ramp and additive blending: glows over the scene
// instead of reading as pixel cells. The retro pipeline still pixelates the final image.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform;

uniform float speed : hint_range(0.2, 6.0, 0.1) = 1.6;
uniform float turbulence : hint_range(0.0, 1.5, 0.05) = 0.75;
uniform vec4 color_core : source_color = vec4(1.0, 0.95, 0.6, 1.0);
uniform vec4 color_mid : source_color = vec4(1.0, 0.55, 0.12, 1.0);
uniform vec4 color_outer : source_color = vec4(0.85, 0.22, 0.05, 1.0);
uniform float intensity : hint_range(0.0, 1.5, 0.05) = 1.0;
uniform float glow : hint_range(0.0, 3.0, 0.05) = 1.2;

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
		p = p * 2.1 + vec2(13.7, 7.3);
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
}

void fragment() {
	float phase = fract(dot(NODE_POSITION_WORLD.xz, vec2(0.717, 0.331))) * 37.0;
	float up = 1.0 - UV.y;               // 0 base .. 1 tip
	float x = (UV.x - 0.5) * 2.0;        // -1 .. 1

	// Rising, licking noise (two layers moving at different speeds).
	float n = fbm(vec2(x * 1.6 + phase, up * 2.6 - TIME * speed));
	n = 0.7 * n + 0.3 * fbm(vec2(x * 3.2 - phase, up * 4.0 - TIME * speed * 1.7));

	// Teardrop: wide base, narrowing to the tip; noise eats the silhouette.
	float body = 1.0 - up;
	float edge = 1.0 - x * x * (1.1 + up * 2.4);
	float f = min(body, edge) * intensity - n * turbulence * (0.25 + up * 0.85);

	float a = smoothstep(0.02, 0.22, f);
	if (a <= 0.001) {
		discard;
	}
	vec3 col = mix(color_outer.rgb, color_mid.rgb, smoothstep(0.1, 0.3, f));
	col = mix(col, color_core.rgb, smoothstep(0.34, 0.55, f));
	// Additive: black contributes nothing, so shape with the alpha directly.
	ALBEDO = col * a * glow;
}
