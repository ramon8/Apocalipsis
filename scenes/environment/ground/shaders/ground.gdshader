// ground.gdshader — procedural pixel-art style ground.
// Base colour comes from a tiled texture (or a flat colour), then world-space noise adds
// large tonal patches, fine grain and sparse speckles. Everything is snapped to a texel
// grid and quantized to a few levels so it reads as chunky pixels, not smooth noise.
// World-space sampling means the pattern never stretches with UVs or mesh size.
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

uniform sampler2D albedo_tex : source_color, filter_nearest, repeat_enable, hint_default_white;
uniform vec4 albedo_color : source_color = vec4(0.53, 0.40, 0.31, 1.0);
// Metres covered by one texture tile.
uniform float tile_size : hint_range(0.25, 20.0, 0.25) = 2.0;

// Texels per metre of the procedural pattern (higher = finer pixels).
uniform float texels_per_meter : hint_range(1.0, 64.0, 1.0) = 4.0;
// Number of brightness steps the noise is quantized to (2-3 = very pixel-art, 8 = soft).
uniform int levels : hint_range(2, 16) = 3;

// Large patches: size in metres; separate strength for the darker and the lighter areas.
uniform float patch_size : hint_range(0.5, 30.0, 0.5) = 8.0;
uniform float patch_dark_strength : hint_range(0.0, 0.8, 0.01) = 0.14;
uniform float patch_light_strength : hint_range(0.0, 0.8, 0.01) = 0.28;
// Fine grain: size in metres and strength.
uniform float grain_size : hint_range(0.05, 4.0, 0.05) = 1.0;
uniform float grain_strength : hint_range(0.0, 0.5, 0.01) = 0.08;
// Speckles (pebbles/dark spots): probability per texel; colour = base * multiplier,
// so they follow whatever texture/colour the ground has.
uniform float speckle_density : hint_range(0.0, 0.2, 0.001) = 0.015;
uniform float speckle_brightness : hint_range(0.2, 1.0, 0.05) = 0.65;
uniform float light_speckle_density : hint_range(0.0, 0.2, 0.001) = 0.006;
uniform float light_speckle_brightness : hint_range(1.0, 2.0, 0.05) = 1.3;
// Darker patches drift towards this tint (multiplied with the base colour).
uniform vec4 patch_tint : source_color = vec4(0.85, 0.8, 0.8, 1.0);
uniform float patch_tint_strength : hint_range(0.0, 1.0, 0.05) = 0.4;

varying vec3 world_pos;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Smooth value noise in [0,1].
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float quantize(float v) {
	float n = float(max(levels - 1, 1));
	return floor(v * n + 0.5) / n;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Snap the sample position to the texel grid: crisp pixels instead of smooth gradients.
	vec2 texel = floor(world_pos.xz * texels_per_meter) / texels_per_meter;

	vec3 base = texture(albedo_tex, texel / tile_size).rgb * albedo_color.rgb;

	// Large patches (two octaves), centred on 0.
	float patch = vnoise(texel / patch_size) * 0.65 + vnoise(texel / patch_size * 2.3 + 17.0) * 0.35;
	patch = quantize(patch) - 0.5;
	// Fine grain.
	float grain = quantize(vnoise(texel / grain_size)) - 0.5;

	float patch_gain = (patch >= 0.0) ? patch_light_strength : patch_dark_strength;
	vec3 col = base * (1.0 + patch * 2.0 * patch_gain + grain * 2.0 * grain_strength);
	// Tint the darker patches.
	float dampness = clamp(-patch * 2.0, 0.0, 1.0) * patch_tint_strength;
	col = mix(col, col * patch_tint.rgb, dampness);

	// Speckles, one texel each.
	float s = hash21(texel * 7.1 + 3.7);
	if (s < speckle_density) {
		col = base * speckle_brightness;
	} else if (s > 1.0 - light_speckle_density) {
		col = base * light_speckle_brightness;
	}

	ALBEDO = col;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
