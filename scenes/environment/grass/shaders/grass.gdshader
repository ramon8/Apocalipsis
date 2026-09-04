// grass.gdshader — flat-coloured grass blades for a MultiMesh.
// Each instance is a thin vertical strip (x: -0.5..0.5, y: 0..1, several rows).
// The strip is billboarded around Y towards the camera so it always reads as a line,
// bends with the global wind (same globals as the trees) and fades from a base colour
// to a tip colour. Per-instance INSTANCE_CUSTOM: r = tint variation, g = wind phase.
shader_type spatial;
render_mode unshaded, cull_disabled, skip_vertex_transform, depth_draw_opaque;

global uniform vec2  wind_direction;
global uniform float wind_strength;
global uniform float wind_speed;
global uniform float wind_turbulence;
global uniform sampler2D wind_noise;
global uniform float wind_noise_scale;
global uniform float wind_noise_influence;
global uniform float wind_noise_scroll;

uniform vec4 base_color : source_color = vec4(0.18, 0.32, 0.14, 1.0);
uniform vec4 tip_color : source_color = vec4(0.45, 0.62, 0.25, 1.0);
// Second tint mixed in per blade (INSTANCE_CUSTOM.r) for variation.
uniform vec4 variation_color : source_color = vec4(0.35, 0.45, 0.18, 1.0);
uniform float variation_amount : hint_range(0.0, 1.0, 0.05) = 0.5;
// Blade width in metres (~1-2 internal pixels looks best).
uniform float blade_width : hint_range(0.005, 0.3, 0.005) = 0.05;
// Metres the tip moves at wind strength 1.0.
uniform float sway_amount : hint_range(0.0, 1.0, 0.01) = 0.12;
uniform float flutter_amount : hint_range(0.0, 0.5, 0.01) = 0.04;
// Constant lean so blades aren't perfectly vertical (metres at the tip).
uniform float lean : hint_range(0.0, 0.5, 0.01) = 0.04;
// 0 = blades stay vertical (only rotate around Y towards the camera);
// 1 = full billboard: blades also tilt to face the camera head-on at any pitch.
uniform float billboard_tilt : hint_range(0.0, 1.0, 0.05) = 0.0;
// Bend curvature: higher = only the tip moves.
uniform float bend_power : hint_range(1.0, 3.0, 0.1) = 1.8;

varying float v_h;
varying float v_tint;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;                 // instance position (world)
	float height = length(MODEL_MATRIX[1].xyz);        // instance scale.y = blade height
	float h = clamp(VERTEX.y, 0.0, 1.0);               // 0 root .. 1 tip
	v_h = h;
	v_tint = INSTANCE_CUSTOM.r;
	float phase = INSTANCE_CUSTOM.g * 6.2831;

	// Billboard around Y: camera right vector flattened onto XZ.
	vec3 cam_right = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z));
	// Full billboard: blade "up" leans towards the camera's up so the strip faces the
	// camera head-on regardless of pitch (blended by billboard_tilt).
	vec3 up = normalize(mix(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[1].xyz, billboard_tilt));
	vec3 world = origin + cam_right * (VERTEX.x * blade_width) + up * (h * height);

	// Wind (same model as the props, sampled per blade at its root).
	vec2 scroll = wind_direction * (TIME * wind_noise_scroll);
	vec2 nuv = fract((origin.xz - scroll) / max(wind_noise_scale, 0.001));
	float spatial = mix(1.0, textureLod(wind_noise, nuv, 0.0).r * 2.0, wind_noise_influence);
	float w = wind_strength * spatial;
	float t = TIME * wind_speed;
	float bend_curve = pow(h, bend_power);
	float sway = (w * sway_amount * (0.8 + 0.2 * sin(t * 1.3 + phase)) + lean) * bend_curve;
	float flutter = w * wind_turbulence * flutter_amount * bend_curve * sin(t * 4.0 + phase * 1.7);
	vec3 dir = vec3(wind_direction.x, 0.0, wind_direction.y);
	vec3 side = vec3(-dir.z, 0.0, dir.x);
	world += dir * sway + side * flutter;
	world.y -= sway * sway * 0.5;  // keep length roughly constant when bent

	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}

void fragment() {
	vec3 col = mix(base_color.rgb, tip_color.rgb, v_h);
	col = mix(col, col * (variation_color.rgb / max(base_color.rgb, vec3(0.001))), v_tint * variation_amount);
	ALBEDO = col;
}
