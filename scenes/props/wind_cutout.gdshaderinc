// Shared body for the wind-animated cutout (alpha-scissor) props.
// Included by wind_cutout_unshaded.gdshader and wind_cutout_lit.gdshader.
//
// Globals (written every frame by the Wind node, declared in project.godot):
global uniform vec2  wind_direction;   // normalised XZ direction the wind blows TOWARDS
global uniform float wind_strength;    // 0..1+, already includes gusts
global uniform float wind_speed;       // animation speed multiplier
global uniform float wind_turbulence;  // 0..1 side-to-side flutter amount
// Spatial variation: seamless noise sampled at the prop's WORLD position and scrolled
// downwind over time, so gusts have a size, a place and travel across the field.
global uniform sampler2D wind_noise;
global uniform float wind_noise_scale;      // metres covered by one noise tile
global uniform float wind_noise_influence;  // 0 = uniform wind, 1 = fully noise-driven
global uniform float wind_noise_scroll;     // m/s the gust pattern travels downwind
global uniform float wind_noise_dir_var;    // radians of direction wobble from the noise

uniform sampler2D albedo_tex : source_color, filter_nearest, repeat_disable;
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.5;
// Per-material response: 0 = rigid (rocks, signs), 1 = normal, 2 = very flexible.
uniform float wind_influence : hint_range(0.0, 3.0) = 1.0;
// Metres the TOP of the mesh leans downwind at wind_strength 1.0.
uniform float sway_amount : hint_range(0.0, 3.0, 0.01) = 0.35;
// Metres of side-to-side flutter at the top, scaled by wind_turbulence.
uniform float flutter_amount : hint_range(0.0, 1.0, 0.01) = 0.12;
// World-space push applied at the top (linear with height) by tree.gd when something
// walks into the prop. Driven per frame, defaults to none.
uniform vec3 hit_offset = vec3(0.0);

void vertex() {
	// QuadMesh UV: v = 0 at the top edge, 1 at the bottom (ground). h: 0 ground -> 1 top.
	float h = clamp(1.0 - UV.y, 0.0, 1.0);
	// Per-instance phase so neighbouring props don't move in lockstep.
	float phase = dot(NODE_POSITION_WORLD.xz, vec2(1.7, 2.3));
	float t = TIME * wind_speed;

	// --- spatial wind: one sample per prop (NODE_POSITION_WORLD) so the whole prop
	// feels the same gust and doesn't tear. UV scrolls against the wind direction so
	// the pattern moves downwind. Wrapped with fract() so the texture repeats.
	vec2 scroll = wind_direction * (TIME * wind_noise_scroll);
	vec2 nuv = fract((NODE_POSITION_WORLD.xz - scroll) / max(wind_noise_scale, 0.001));
	float n = textureLod(wind_noise, nuv, 0.0).r;                 // 0..1, mean ~0.5
	float n2 = textureLod(wind_noise, fract(nuv + vec2(0.37, 0.61)), 0.0).r;
	float spatial = mix(1.0, n * 2.0, wind_noise_influence);       // 0..2, mean 1
	float dir_angle = (n2 - 0.5) * 2.0 * wind_noise_dir_var * wind_noise_influence;
	vec2 wdir = vec2(
		wind_direction.x * cos(dir_angle) - wind_direction.y * sin(dir_angle),
		wind_direction.x * sin(dir_angle) + wind_direction.y * cos(dir_angle));

	float w = wind_strength * wind_influence * spatial;
	// Slow per-tree pulsing on top of the global gusts.
	float local_gust = 0.8 + 0.2 * sin(t * 0.7 + phase);
	// Parabolic bend: the base stays put, the crown moves the most.
	float bend = w * sway_amount * local_gust * h * h;
	// Flutter: two mixed sines, orthogonal to the wind, linear with height.
	float flutter = w * wind_turbulence * flutter_amount * h
			* (0.6 * sin(t * 3.1 + phase) + 0.4 * sin(t * 5.3 + phase * 1.31));

	vec3 dir = vec3(wdir.x, 0.0, wdir.y);
	vec3 side = vec3(-dir.z, 0.0, dir.x);
	vec3 offset_world = dir * bend + side * flutter;
	// Slight downward drop when bent so the tip doesn't visibly stretch.
	offset_world.y -= bend * bend * 0.5;
	// Collision shake: whole prop leans, most at the top.
	offset_world += hit_offset * h;

	VERTEX += inverse(mat3(MODEL_MATRIX)) * offset_world;
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
	ALBEDO = tex.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
